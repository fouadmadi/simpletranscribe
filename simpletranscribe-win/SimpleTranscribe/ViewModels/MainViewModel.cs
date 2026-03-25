using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using SimpleTranscribe.Models;
using SimpleTranscribe.Services;

namespace SimpleTranscribe.ViewModels;

/// <summary>
/// Main view model for the application. Port of macOS AppModel.swift + ContentView logic.
/// Uses CommunityToolkit.Mvvm source generators for INotifyPropertyChanged.
/// </summary>
public partial class MainViewModel : ObservableObject
{
    private readonly AudioManager _audioManager = new();
    private readonly TranscriptionManager _transcriptionManager = new();
    private readonly HotKeyManager _hotKeyManager = new();
    private readonly ModelService _modelService = new();

    [ObservableProperty] private bool _isRecording;
    [ObservableProperty] private bool _isProcessing;
    [ObservableProperty] private bool _isLoadingModel;
    [ObservableProperty] private bool _modelLoaded;
    [ObservableProperty] private bool _showTranscriptionStarted;
    [ObservableProperty] private string _transcribedText = "";
    [ObservableProperty] private string? _errorMessage;

    [ObservableProperty] private string _selectedLanguage;
    [ObservableProperty] private string _selectedModelId;
    [ObservableProperty] private string? _selectedDeviceId;

    [ObservableProperty] private List<AudioDeviceInfo> _availableDevices = new();
    [ObservableProperty] private List<ModelInfo> _downloadedModels = new();

    public ModelService ModelService => _modelService;
    public HotKeyManager HotKeyManager => _hotKeyManager;

    public bool CanRecord => ModelLoaded && !string.IsNullOrEmpty(SelectedModelId);
    public bool HasDownloadedModels => _modelService.AvailableModels.Any(m => m.IsAvailable);

    public MainViewModel()
    {
        // Restore persisted settings
        _selectedLanguage = GetSetting("language", "en");
        _selectedModelId = GetSetting("selectedModelId", "");
        _selectedDeviceId = GetSetting("selectedDeviceId");

        // Wire up audio buffer relay
        _audioManager.OnBufferReceived += buffer =>
        {
            if (IsRecording)
                _transcriptionManager.AppendAudio(buffer);
        };

        _audioManager.OnError += ex =>
        {
            ErrorMessage = $"Audio error: {ex.Message}";
            SoundManager.PlayError();
        };

        // Wire up hotkey
        _hotKeyManager.HotKeyStateChanged += OnHotKeyStateChanged;

        // Wire up model service changes
        _modelService.ModelsChanged += RefreshDownloadedModels;

        // Initialize
        RefreshDownloadedModels();
        RefreshDevices();

        // Auto-select default model if persisted one isn't valid
        if (string.IsNullOrEmpty(SelectedModelId) || _modelService.GetModel(SelectedModelId)?.IsAvailable != true)
            SelectDefaultModel();
    }

    /// <summary>
    /// One-time setup after the window is loaded and message pump is running.
    /// </summary>
    public async Task SetupAsync()
    {
        _hotKeyManager.Setup();
        RefreshDevices();

        if (!string.IsNullOrEmpty(SelectedModelId) &&
            _modelService.GetModel(SelectedModelId)?.IsAvailable == true)
        {
            await LoadModelAsync();
        }
    }

    // --- Settings persistence ---

    partial void OnSelectedLanguageChanged(string value) => SaveSetting("language", value);
    partial void OnSelectedModelIdChanged(string value)
    {
        SaveSetting("selectedModelId", value);
        ModelLoaded = false;
        ErrorMessage = null;
        OnPropertyChanged(nameof(CanRecord));

        if (!string.IsNullOrEmpty(value) && _modelService.GetModel(value)?.IsAvailable == true)
            _ = LoadModelAsync();
    }
    partial void OnSelectedDeviceIdChanged(string? value) => SaveSetting("selectedDeviceId", value ?? "");
    partial void OnModelLoadedChanged(bool value) => OnPropertyChanged(nameof(CanRecord));

    // --- Model management ---

    public async Task LoadModelAsync()
    {
        if (string.IsNullOrEmpty(SelectedModelId))
        {
            ModelLoaded = false;
            return;
        }

        var modelPath = _modelService.GetModelPath(SelectedModelId);
        if (modelPath == null)
        {
            ErrorMessage = "Model file not found. Download it from the Models tab.";
            ModelLoaded = false;
            return;
        }

        IsLoadingModel = true;
        ModelLoaded = false;
        ErrorMessage = null;

        try
        {
            await _transcriptionManager.LoadModelAsync(modelPath);
            ModelLoaded = true;
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Failed to load model: {ex.Message}";
            ModelLoaded = false;
        }
        finally
        {
            IsLoadingModel = false;
        }
    }

    public void SelectDefaultModel()
    {
        var firstDownloaded = _modelService.AvailableModels.FirstOrDefault(m => m.IsAvailable);
        SelectedModelId = firstDownloaded?.Id ?? "";
    }

    // --- Recording ---

    [RelayCommand]
    public void ToggleRecording()
    {
        if (IsRecording)
            StopRecordingAndTranscribe(autoPaste: false);
        else
            StartRecording();
    }

    private void StartRecording()
    {
        if (!CanRecord || IsRecording || IsProcessing)
            return;

        ErrorMessage = null;

        try
        {
            _transcriptionManager.StartTranscription(SelectedLanguage);
            IsRecording = true;
            ShowTranscriptionStarted = true;
            _audioManager.StartRecording(SelectedDeviceId);
            SoundManager.PlayRecordingStarted();
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Failed to start recording: {ex.Message}";
            IsRecording = false;
            ShowTranscriptionStarted = false;
            SoundManager.PlayError();
        }
    }

    private async void StopRecordingAndTranscribe(bool autoPaste)
    {
        _audioManager.StopRecording();
        IsRecording = false;
        IsProcessing = true;
        ErrorMessage = null;
        ShowTranscriptionStarted = false;

        try
        {
            var text = await _transcriptionManager.ProcessAudioAsync(SelectedLanguage);
            var trimmed = text.Trim();

            if (!string.IsNullOrEmpty(trimmed))
            {
                TranscribedText = string.IsNullOrEmpty(TranscribedText)
                    ? trimmed
                    : TranscribedText + " " + trimmed;
            }

            IsProcessing = false;
            SoundManager.PlayTranscriptionComplete();

            if (autoPaste && !string.IsNullOrEmpty(trimmed))
                PasteService.CopyAndPaste(trimmed);
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Transcription failed: {ex.Message}";
            IsProcessing = false;
            SoundManager.PlayError();
        }
    }

    // --- Hotkey ---

    private void OnHotKeyStateChanged(bool pressed)
    {
        if (pressed)
            StartRecording();
        else if (IsRecording)
            StopRecordingAndTranscribe(autoPaste: true);
    }

    // --- Devices ---

    public void RefreshDevices()
    {
        AvailableDevices = AudioManager.GetInputDevices();
        if (SelectedDeviceId == null || !AvailableDevices.Any(d => d.Id == SelectedDeviceId))
            SelectedDeviceId = AudioManager.GetDefaultDeviceId() ?? AvailableDevices.FirstOrDefault()?.Id;
    }

    private void RefreshDownloadedModels()
    {
        DownloadedModels = _modelService.AvailableModels.Where(m => m.IsAvailable).ToList();
        OnPropertyChanged(nameof(HasDownloadedModels));
    }

    // --- Clipboard ---

    [RelayCommand]
    public void CopyToClipboard()
    {
        if (!string.IsNullOrEmpty(TranscribedText))
            PasteService.CopyToClipboard(TranscribedText);
    }

    // --- Settings helpers ---

    private static string GetSetting(string key, string defaultValue = "")
    {
        try
        {
            var settingsDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "SimpleTranscribe");
            var settingsFile = Path.Combine(settingsDir, "settings.json");

            if (!File.Exists(settingsFile))
                return defaultValue;

            var json = File.ReadAllText(settingsFile);
            var dict = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, string>>(json);
            return dict?.GetValueOrDefault(key, defaultValue) ?? defaultValue;
        }
        catch
        {
            return defaultValue;
        }
    }

    private static void SaveSetting(string key, string value)
    {
        try
        {
            var settingsDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "SimpleTranscribe");
            Directory.CreateDirectory(settingsDir);
            var settingsFile = Path.Combine(settingsDir, "settings.json");

            Dictionary<string, string> dict;
            if (File.Exists(settingsFile))
            {
                var json = File.ReadAllText(settingsFile);
                dict = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, string>>(json) ?? new();
            }
            else
            {
                dict = new();
            }

            dict[key] = value;
            File.WriteAllText(settingsFile, System.Text.Json.JsonSerializer.Serialize(dict));
        }
        catch { /* Best effort settings persistence */ }
    }

    public void Cleanup()
    {
        _hotKeyManager.Dispose();
        _audioManager.Dispose();
        _transcriptionManager.Dispose();
    }
}

using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using SimpleTranscribe.Models;
using SimpleTranscribe.Services;

namespace SimpleTranscribe.ViewModels;

/// <summary>
/// Main view model for the application. Port of macOS AppModel.swift + ContentView logic.
/// Uses CommunityToolkit.Mvvm source generators for INotifyPropertyChanged.
/// MVVMTK0045 suppressed: unpackaged app doesn't need WinRT AOT marshalling.
/// </summary>
#pragma warning disable MVVMTK0045
public partial class MainViewModel : ObservableObject, IDisposable
{
    private readonly AudioManager _audioManager = new();
    private readonly TranscriptionManager _transcriptionManager = new();
    private readonly HotKeyManager _hotKeyManager = new();
    private readonly ModelService _modelService = new();
    private AudioDeviceNotifier? _deviceNotifier;
    private SynchronizationContext? _syncContext;
    private DateTime? _recordingStartTime;

    public TranscriptHistoryService History { get; } = new();
    public PostProcessorConfig PostProcessorConfig { get; private set; } = new();

    [ObservableProperty] private bool _isRecording;
    [ObservableProperty] private bool _isProcessing;
    [ObservableProperty] private bool _isLoadingModel;
    [ObservableProperty] private bool _modelLoaded;
    [ObservableProperty] private bool _showTranscriptionStarted;
    [ObservableProperty] private string _transcribedText = "";
    [ObservableProperty] private string? _errorMessage;
    [ObservableProperty] private OverlayState _overlayState = OverlayState.Idle;
    [ObservableProperty] private string _liveTranscriptText = "";
    [ObservableProperty] private bool _streamingEnabled;
    [ObservableProperty] private bool _autoClearAfterPaste;
    [ObservableProperty] private double _lastRecordingDuration;
    [ObservableProperty] private int _wordCount;
    [ObservableProperty] private int _charCount;

    private StreamingTranscriber? _streamingTranscriber;

    [ObservableProperty] private string _selectedLanguage;
    [ObservableProperty] private string _selectedModelId;
    [ObservableProperty] private string? _selectedDeviceId;
    [ObservableProperty] private bool _useSystemDefault = true;
    [ObservableProperty] private string _deviceSwitchMessage = "";
    [ObservableProperty] private int _hotKeyVKey = Win32Interop.VK_SPACE;
    [ObservableProperty] private int _hotKeyModifierVKey = Win32Interop.VK_CONTROL;

    [ObservableProperty] private List<AudioDeviceInfo> _availableDevices = new();
    [ObservableProperty] private List<ModelInfo> _downloadedModels = new();

    public ModelService ModelService => _modelService;
    public HotKeyManager HotKeyManager => _hotKeyManager;

    public bool CanRecord => ModelLoaded && !string.IsNullOrEmpty(SelectedModelId);
    public bool HasDownloadedModels => _modelService.AvailableModels.Any(m => m.IsAvailable);
    public string LastRecordingDurationLabel => LastRecordingDuration < 1 ? ""
        : $"{LastRecordingDuration:F0}s recorded";

    public List<SupportedLanguage> AvailableLanguages => SupportedLanguages.Available(SelectedModelId);

    private void ValidateLanguageForModel(string modelId)
    {
        var allowed = SupportedLanguages.SupportedCodes(modelId);
        if (allowed == null) return;
        if (SelectedLanguage != "auto" && !allowed.Contains(SelectedLanguage))
        {
            SelectedLanguage = "en";
            var modelName = _modelService.GetModel(modelId)?.Name ?? modelId;
            DeviceSwitchMessage = $"{modelName} doesn't support the selected language — switched to English.";
            ClearDeviceSwitchMessageAfterDelay();
        }
        OnPropertyChanged(nameof(AvailableLanguages));
    }

    public MainViewModel()
    {
        // Restore persisted settings
        _selectedLanguage = GetSetting("language", "en");
        _selectedModelId = GetSetting("selectedModelId", "");
        _selectedDeviceId = GetSetting("selectedDeviceId");
        _useSystemDefault = GetSetting("useSystemDefault", "True") == "True";
        _hotKeyVKey = int.TryParse(GetSetting("hotKeyVKey"), out var vk) ? vk : Win32Interop.VK_SPACE;
        _hotKeyModifierVKey = int.TryParse(GetSetting("hotKeyModifierVKey"), out var mod) ? mod : Win32Interop.VK_CONTROL;
        _streamingEnabled = GetSetting("streamingEnabled", "False") == "True";
        _autoClearAfterPaste = GetSetting("autoClearAfterPaste", "False") == "True";
        PostProcessorConfig = PostProcessorConfig.Load(k => GetSetting(k));

        // Wire up audio buffer relay — feeds both accumulator and streaming transcriber
        _audioManager.OnBufferReceived += buffer =>
        {
            if (IsRecording)
            {
                _transcriptionManager.AppendAudio(buffer);
                if (_streamingTranscriber != null)
                {
                    // Fire-and-forget: update live text when a chunk is ready
                    _ = _streamingTranscriber.FeedAsync(buffer).ContinueWith(t =>
                    {
                        var partial = t.Result;
                        if (partial != null && _syncContext != null)
                            _syncContext.Post(_ => LiveTranscriptText = partial, null);
                    }, TaskContinuationOptions.OnlyOnRanToCompletion);
                }
            }
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
        _syncContext = SynchronizationContext.Current;

        _deviceNotifier = new AudioDeviceNotifier();
        _deviceNotifier.DevicesChanged += HandleDeviceListChanged;
        _deviceNotifier.DefaultDeviceChanged += HandleDefaultDeviceChanged;

        _hotKeyManager.Setup();
        _hotKeyManager.UpdateHotKey(HotKeyVKey, HotKeyModifierVKey);
        RefreshDevices();

        if (!string.IsNullOrEmpty(SelectedModelId) &&
            _modelService.GetModel(SelectedModelId)?.IsAvailable == true)
        {
            await LoadModelAsync();
        }
    }

    // --- Settings persistence ---

    partial void OnSelectedLanguageChanged(string value) => SaveSetting("language", value);
    partial void OnStreamingEnabledChanged(bool value) => SaveSetting("streamingEnabled", value.ToString());
    partial void OnAutoClearAfterPasteChanged(bool value) => SaveSetting("autoClearAfterPaste", value.ToString());
    partial void OnTranscribedTextChanged(string value)
    {
        WordCount = string.IsNullOrEmpty(value) ? 0
            : value.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length;
        CharCount = value.Length;
    }
    partial void OnHotKeyVKeyChanged(int value)
    {
        SaveSetting("hotKeyVKey", value.ToString());
        _hotKeyManager.UpdateHotKey(value, HotKeyModifierVKey);
    }
    partial void OnHotKeyModifierVKeyChanged(int value)
    {
        SaveSetting("hotKeyModifierVKey", value.ToString());
        _hotKeyManager.UpdateHotKey(HotKeyVKey, value);
    }
    partial void OnSelectedModelIdChanged(string value)
    {
        SaveSetting("selectedModelId", value);
        ModelLoaded = false;
        ErrorMessage = null;
        OnPropertyChanged(nameof(CanRecord));

        // Validate language against the new model's supported set
        ValidateLanguageForModel(value);

        if (!string.IsNullOrEmpty(value) && _modelService.GetModel(value)?.IsAvailable == true)
            LoadModelInBackground();
    }
    partial void OnSelectedDeviceIdChanged(string? value) => SaveSetting("selectedDeviceId", value ?? "");
    partial void OnUseSystemDefaultChanged(bool value) => SaveSetting("useSystemDefault", value.ToString());
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
            var model = _modelService.GetModel(SelectedModelId);
            var modelType = model?.ModelType ?? ModelType.Whisper;
            await _transcriptionManager.LoadModelAsync(modelPath, modelType);
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

    /// <summary>
    /// Fire-and-forget wrapper that catches unobserved exceptions from LoadModelAsync.
    /// </summary>
    private async void LoadModelInBackground()
    {
        try { await LoadModelAsync(); }
        catch (Exception ex) { ErrorMessage = $"Failed to load model: {ex.Message}"; }
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
            _recordingStartTime = DateTime.Now;
            ShowTranscriptionStarted = true;
            OverlayState = OverlayState.Recording;
            _audioManager.StartRecording(SelectedDeviceId);
            SoundManager.PlayRecordingStarted();

            // Start streaming preview if enabled and a Whisper model is loaded
            if (StreamingEnabled && _transcriptionManager.IsWhisperLoaded)
            {
                _streamingTranscriber = new StreamingTranscriber(
                    _transcriptionManager.SharedCtx,
                    _transcriptionManager.SharedCtxLock,
                    SelectedLanguage);
                _streamingTranscriber.Start();
            }
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Failed to start recording: {ex.Message}";
            IsRecording = false;
            ShowTranscriptionStarted = false;
            OverlayState = OverlayState.Error;
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
        OverlayState = OverlayState.Transcribing;

        // Stop streaming preview
        _streamingTranscriber?.Stop();
        _streamingTranscriber?.Dispose();
        _streamingTranscriber = null;
        LiveTranscriptText = "";

        try
        {
            var text = await _transcriptionManager.ProcessAudioAsync(SelectedLanguage);
            var trimmed = text.Trim();
            var config = PostProcessorConfig;
            var processed = string.IsNullOrEmpty(trimmed) ? trimmed
                : await Task.Run(() => TextPostProcessor.Process(trimmed, config));

            if (!string.IsNullOrEmpty(processed))
            {
                TranscribedText = string.IsNullOrEmpty(TranscribedText)
                    ? processed
                    : TranscribedText + " " + processed;

                var duration = _recordingStartTime.HasValue
                    ? (DateTime.Now - _recordingStartTime.Value).TotalSeconds
                    : 0;
                LastRecordingDuration = duration;
                OnPropertyChanged(nameof(LastRecordingDurationLabel));
                History.Append(new Models.TranscriptEntry
                {
                    Text = processed,
                    DurationSeconds = duration,
                    ModelId = SelectedModelId,
                    Language = SelectedLanguage
                });
            }

            IsProcessing = false;
            OverlayState = OverlayState.Done;
            SoundManager.PlayTranscriptionComplete();

            if (autoPaste && !string.IsNullOrEmpty(processed))
            {
                PasteService.CopyAndPaste(processed);
                if (AutoClearAfterPaste)
                {
                    await Task.Delay(300);
                    TranscribedText = "";
                }
            }
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Transcription failed: {ex.Message}";
            IsProcessing = false;
            OverlayState = OverlayState.Error;
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

    private void HandleDeviceListChanged()
    {
        void DoWork()
        {
            RefreshDevices();

            if (SelectedDeviceId != null && AvailableDevices.Any(d => d.Id == SelectedDeviceId))
                return;

            // Current device is gone — switch to system default
            SelectedDeviceId = AudioManager.GetDefaultDeviceId() ?? AvailableDevices.FirstOrDefault()?.Id;
            var deviceName = AvailableDevices.FirstOrDefault(d => d.Id == SelectedDeviceId)?.Name ?? "default";
            DeviceSwitchMessage = $"Switched to {deviceName} (device removed)";
            ClearDeviceSwitchMessageAfterDelay();

            RestartRecordingOnNewDevice();
        }

        if (_syncContext != null)
            _syncContext.Post(_ => DoWork(), null);
        else
            DoWork();
    }

    private void HandleDefaultDeviceChanged(string newDeviceId)
    {
        void DoWork()
        {
            RefreshDevices();

            if (UseSystemDefault)
            {
                SelectedDeviceId = newDeviceId;
                var deviceName = AvailableDevices.FirstOrDefault(d => d.Id == newDeviceId)?.Name ?? "default";
                DeviceSwitchMessage = $"Switched to {deviceName}";
                ClearDeviceSwitchMessageAfterDelay();
                RestartRecordingOnNewDevice();
            }
            else if (SelectedDeviceId != null && !AvailableDevices.Any(d => d.Id == SelectedDeviceId))
            {
                // Device-gone is handled by HandleDeviceListChanged — no action needed here.
            }
        }

        if (_syncContext != null)
            _syncContext.Post(_ => DoWork(), null);
        else
            DoWork();
    }

    private void RestartRecordingOnNewDevice()
    {
        if (!IsRecording) return;

        // Stop only the audio capture — do NOT trigger transcription
        _audioManager.StopRecording();

        // TranscriptionManager's accumulated audio is preserved

        try
        {
            _audioManager.StartRecording(SelectedDeviceId);
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Failed to switch microphone: {ex.Message}";
            SoundManager.PlayError();
        }
    }

    private CancellationTokenSource? _switchMessageCts;

    private async void ClearDeviceSwitchMessageAfterDelay()
    {
        try
        {
            _switchMessageCts?.Cancel();
            _switchMessageCts = new CancellationTokenSource();
            var token = _switchMessageCts.Token;
            await Task.Delay(3000, token);
            DeviceSwitchMessage = "";
        }
        catch { /* Timer cancelled or app shutting down */ }
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

    // Export is handled in MainWindow (needs HWND access) — exposes formatted content only.
    public string GetExportContent(string format) => format switch
    {
        "md"  => TranscriptExporter.FormatMarkdown(TranscribedText),
        "srt" => TranscriptExporter.FormatSrt(History.Entries),
        "history-txt" => string.Join("\n\n", History.Entries.Select(e => e.Text)),
        "history-md"  => TranscriptExporter.FormatHistoryMarkdown(History.Entries),
        "history-srt" => TranscriptExporter.FormatSrt(History.Entries),
        _     => TranscriptExporter.FormatText(TranscribedText),
    };

    // --- Settings helpers ---

    private static readonly object _settingsLock = new();
    private static Dictionary<string, string>? _settingsCache;

    private static string SettingsFilePath
    {
        get
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "SimpleTranscribe");
            return Path.Combine(dir, "settings.json");
        }
    }

    private static Dictionary<string, string> LoadSettingsFromDisk()
    {
        try
        {
            var path = SettingsFilePath;
            if (!File.Exists(path))
                return new();

            var json = File.ReadAllText(path);
            return System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, string>>(json) ?? new();
        }
        catch
        {
            return new();
        }
    }

    private static string GetSetting(string key, string defaultValue = "")
    {
        lock (_settingsLock)
        {
            _settingsCache ??= LoadSettingsFromDisk();
            return _settingsCache.GetValueOrDefault(key, defaultValue);
        }
    }

    private static void SaveSetting(string key, string value)
    {
        lock (_settingsLock)
        {
            _settingsCache ??= LoadSettingsFromDisk();
            _settingsCache[key] = value;

            try
            {
                var path = SettingsFilePath;
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                File.WriteAllText(path, System.Text.Json.JsonSerializer.Serialize(_settingsCache));
            }
            catch { /* Best effort settings persistence */ }
        }
    }

    /// <summary>Public entry point for external callers (e.g., MainWindow) to persist arbitrary settings keys.</summary>
    public void SaveSettingPublic(string key, string value) => SaveSetting(key, value);

    public void Cleanup()
    {
        Dispose();
    }

    public void Dispose()
    {
        if (_deviceNotifier != null)
        {
            _deviceNotifier.DevicesChanged -= HandleDeviceListChanged;
            _deviceNotifier.DefaultDeviceChanged -= HandleDefaultDeviceChanged;
            _deviceNotifier.Dispose();
            _deviceNotifier = null;
        }

        _modelService.ModelsChanged -= RefreshDownloadedModels;
        _hotKeyManager.Dispose();
        _audioManager.Dispose();
        _transcriptionManager.Dispose();
        GC.SuppressFinalize(this);
    }
}

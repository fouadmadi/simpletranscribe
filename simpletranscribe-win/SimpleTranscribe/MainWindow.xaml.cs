using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using SimpleTranscribe.Interop;
using SimpleTranscribe.ViewModels;
using Win32Interop = SimpleTranscribe.Interop.Win32Interop;

namespace SimpleTranscribe;

public sealed partial class MainWindow : Window
{
    private void OnAboutMenuClicked(object sender, RoutedEventArgs e)
    {
        ShowAboutDialog();
    }
    private async void ShowAboutDialog()
    {
        var dialog = new Views.AboutDialog();
        await dialog.ShowAsync();
    }
    private readonly MainViewModel _vm;
    private bool _isQuitting;

    public MainWindow(MainViewModel viewModel)
    {
        _vm = viewModel;
        InitializeComponent();

        // Set default window size to match macOS (700×550)
        AppWindow.Resize(new Windows.Graphics.SizeInt32(700, 550));
        Title = "SimpleTranscribe";

        // Wire up view events to view model
        RecordingControls.ToggleRecordingClicked += (_, _) => _vm.ToggleRecording();
        RecordingControls.ShowModelManagerClicked += (_, _) => ShowModelManager();
        RecordingControls.ToggleHistoryClicked += (_, _) => ToggleHistory();

        Settings.DeviceChanged += (_, id) => _vm.SelectedDeviceId = id;
        Settings.ModelChanged += (_, id) => _vm.SelectedModelId = id;
        Settings.LanguageChanged += (_, lang) => _vm.SelectedLanguage = lang;
        Settings.UseSystemDefaultChanged += (_, value) => _vm.UseSystemDefault = value;
        Settings.HotKeyChanged += (_, combo) =>
        {
            _vm.HotKeyVKey = combo.vKey;
            _vm.HotKeyModifierVKey = combo.modifierVKey;
        };
        Settings.StreamingChanged += (_, enabled) => _vm.StreamingEnabled = enabled;
        Settings.CapitaliseSentencesChanged += (_, v) => { _vm.PostProcessorConfig.CapitaliseSentences = v; _vm.PostProcessorConfig.Save(SaveSetting); };
        Settings.RemoveFillersChanged += (_, v) => { _vm.PostProcessorConfig.RemoveFillersEnabled = v; _vm.PostProcessorConfig.Save(SaveSetting); };
        Settings.NumberFormattingChanged += (_, v) => { _vm.PostProcessorConfig.NumberFormattingEnabled = v; _vm.PostProcessorConfig.Save(SaveSetting); };
        Settings.AutoClearAfterPasteChanged += (_, v) => _vm.AutoClearAfterPaste = v;
        Settings.FontSizeChanged += (_, size) => _vm.TranscriptFontSize = size;

        TranscriptResults.TextChanged += (_, text) => _vm.TranscribedText = text;
        TranscriptResults.CopyClicked += (_, _) => _vm.CopyToClipboard();
        TranscriptResults.ExportRequested += (_, format) => _ = ExportTranscriptAsync(format);

        ModelDownloadPanel.CloseRequested += (_, _) => HideModelManager();
        ModelDownloadPanel.ModelSelected += (_, id) => _vm.SelectedModelId = id;

        HistoryPanel.History = _vm.History;

        // Subscribe to view model property changes
        _vm.PropertyChanged += OnViewModelPropertyChanged;

        // Deferred setup
        DispatcherQueue.TryEnqueue(async () =>
        {
            ModelDownloadPanel.Initialize(_vm.ModelService, _vm.SelectedModelId);
            await _vm.SetupAsync();
            SyncAllUI();
        });

        // Hide to system tray on close instead of quitting
        AppWindow.Closing += (_, args) =>
        {
            if (!_isQuitting)
            {
                args.Cancel = true;
                HideWindow();
            }
        };

        Closed += (_, _) =>
        {
            ModelDownloadPanel.Detach();
        };
    }

    private void OnViewModelPropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            switch (e.PropertyName)
            {
                case nameof(MainViewModel.IsRecording):
                case nameof(MainViewModel.IsProcessing):
                case nameof(MainViewModel.ModelLoaded):
                case nameof(MainViewModel.IsLoadingModel):
                case nameof(MainViewModel.ShowTranscriptionStarted):
                case nameof(MainViewModel.CanRecord):
                    UpdateRecordingControls();
                    break;

                case nameof(MainViewModel.TranscribedText):
                    TranscriptResults.Text = _vm.TranscribedText;
                    break;

                case nameof(MainViewModel.LiveTranscriptText):
                    TranscriptResults.LiveText = _vm.LiveTranscriptText;
                    break;

                case nameof(MainViewModel.ErrorMessage):
                    UpdateErrorBanner();
                    break;

                case nameof(MainViewModel.AvailableDevices):
                    Settings.UpdateDevices(_vm.AvailableDevices, _vm.SelectedDeviceId);
                    break;

                case nameof(MainViewModel.DeviceSwitchMessage):
                    Settings.UpdateDeviceSwitchMessage(_vm.DeviceSwitchMessage);
                    break;

                case nameof(MainViewModel.UseSystemDefault):
                    Settings.UpdateUseSystemDefault(_vm.UseSystemDefault);
                    break;

                case nameof(MainViewModel.DownloadedModels):
                    Settings.UpdateModels(_vm.DownloadedModels, _vm.SelectedModelId);
                    Settings.UpdateLanguages(_vm.AvailableLanguages, _vm.SelectedLanguage);
                    UpdateModelBanner();
                    break;

                case nameof(MainViewModel.AvailableLanguages):
                    Settings.UpdateLanguages(_vm.AvailableLanguages, _vm.SelectedLanguage);
                    break;

                case nameof(MainViewModel.SelectedLanguage):
                    Settings.UpdateLanguage(_vm.SelectedLanguage);
                    break;

                case nameof(MainViewModel.WordCount):
                case nameof(MainViewModel.CharCount):
                case nameof(MainViewModel.LastRecordingDuration):
                case nameof(MainViewModel.RecordingElapsedLabel):
                case nameof(MainViewModel.RecordingTimeLimitWarning):
                    UpdateStatusBar();
                    UpdateTimeLimitWarningBar();
                    break;

                case nameof(MainViewModel.PasteFailedMessage):
                    UpdatePasteFailedBar();
                    break;

                case nameof(MainViewModel.TranscriptFontSize):
                    TranscriptResults.TranscriptFontSize = _vm.TranscriptFontSize;
                    Settings.UpdateFontSize(_vm.TranscriptFontSize);
                    break;

                case nameof(MainViewModel.ActiveComputeBackend):
                    Settings.UpdateBackend(_vm.ActiveComputeBackend);
                    break;

                case nameof(MainViewModel.HasDownloadedModels):
                    UpdateModelBanner();
                    break;
            }
        });
    }

    private void SyncAllUI()
    {
        UpdateRecordingControls();
        Settings.UpdateDevices(_vm.AvailableDevices, _vm.SelectedDeviceId);
        Settings.UpdateUseSystemDefault(_vm.UseSystemDefault);
        Settings.UpdateModels(_vm.DownloadedModels, _vm.SelectedModelId);
        Settings.UpdateLanguages(_vm.AvailableLanguages, _vm.SelectedLanguage);
        Settings.UpdateHotKey(_vm.HotKeyVKey, _vm.HotKeyModifierVKey);
        Settings.UpdateStreaming(_vm.StreamingEnabled);
        Settings.UpdateTextProcessing(
            _vm.PostProcessorConfig.CapitaliseSentences,
            _vm.PostProcessorConfig.RemoveFillersEnabled,
            _vm.PostProcessorConfig.NumberFormattingEnabled,
            _vm.AutoClearAfterPaste);
        TranscriptResults.Text = _vm.TranscribedText;
        TranscriptResults.TranscriptFontSize = _vm.TranscriptFontSize;
        Settings.UpdateFontSize(_vm.TranscriptFontSize);
        Settings.UpdateBackend(_vm.ActiveComputeBackend);
        UpdateModelBanner();
        UpdateErrorBanner();
        UpdateStatusBar();
        UpdateTimeLimitWarningBar();
        UpdatePasteFailedBar();
    }

    /// <summary>Delegate passed to PostProcessorConfig.Save so it can persist via the VM's settings store.</summary>
    private void SaveSetting(string key, string value) => _vm.SaveSettingPublic(key, value);

    private async Task ExportTranscriptAsync(string format)
    {
        var content = _vm.GetExportContent(format);
        if (string.IsNullOrEmpty(content))
        {
            _vm.ErrorMessage = "Nothing to export.";
            return;
        }

        var picker = new Windows.Storage.Pickers.FileSavePicker
        {
            SuggestedFileName = $"transcript.{format}",
            SuggestedStartLocation = Windows.Storage.Pickers.PickerLocationId.DocumentsLibrary
        };
        picker.FileTypeChoices.Add(format.ToUpperInvariant(), new List<string> { $".{format}" });

        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);

        var file = await picker.PickSaveFileAsync();
        if (file == null) return;

        try
        {
            await Windows.Storage.FileIO.WriteTextAsync(file, content);
        }
        catch (Exception ex)
        {
            _vm.ErrorMessage = $"Export failed: {ex.Message}";
        }
    }

    private void UpdateStatusBar()
    {
        if (_vm.WordCount > 0)
        {
            WordCountText.Text = $"{_vm.WordCount} words";
            WordCountText.Visibility = Visibility.Visible;
            CharCountText.Text = $"{_vm.CharCount} chars";
            CharCountText.Visibility = Visibility.Visible;
        }
        else
        {
            WordCountText.Visibility = Visibility.Collapsed;
            CharCountText.Visibility = Visibility.Collapsed;
        }

        var label = _vm.LastRecordingDurationLabel;
        DurationText.Text = label;
        DurationText.Visibility = string.IsNullOrEmpty(label) ? Visibility.Collapsed : Visibility.Visible;

        RecordingElapsedText.Text = _vm.RecordingElapsedLabel;
        RecordingElapsedText.Visibility = string.IsNullOrEmpty(_vm.RecordingElapsedLabel)
            ? Visibility.Collapsed
            : Visibility.Visible;
        RecordingElapsedText.Foreground = new SolidColorBrush(
            _vm.RecordingTimeLimitWarning ? Colors.Orange : Colors.Gray);
    }

    private void UpdateTimeLimitWarningBar()
    {
        TimeLimitWarningBar.IsOpen = _vm.RecordingTimeLimitWarning;
    }

    private void UpdatePasteFailedBar()
    {
        PasteFailedBar.IsOpen = !string.IsNullOrEmpty(_vm.PasteFailedMessage);
        PasteFailedBar.Message = _vm.PasteFailedMessage;
    }

    private void UpdateRecordingControls()
    {
        RecordingControls.UpdateState(
            _vm.IsRecording,
            _vm.IsProcessing,
            false, // isTranscribing tracked via IsProcessing on Windows
            _vm.CanRecord,
            _vm.IsLoadingModel,
            _vm.ShowTranscriptionStarted);
    }

    private void UpdateModelBanner()
    {
        // Always detach both handlers before reconfiguring
        BannerButton.Click -= OnBannerLoadModel;
        BannerButton.Click -= OnBannerShowModelManager;

        if (_vm.IsLoadingModel)
        {
            ModelStatusBanner.Visibility = Visibility.Visible;
            BannerIcon.Glyph = "\uE896";
            BannerText.Text = "Loading model...";
            BannerButton.Visibility = Visibility.Collapsed;
        }
        else if (!_vm.ModelLoaded && _vm.HasDownloadedModels)
        {
            ModelStatusBanner.Visibility = Visibility.Visible;
            BannerIcon.Glyph = "\uE896";
            BannerText.Text = "Model not loaded. Select a model or click Load.";
            BannerButton.Content = "Load Model";
            BannerButton.Visibility = Visibility.Visible;
            BannerButton.Click += OnBannerLoadModel;
        }
        else if (!_vm.ModelLoaded)
        {
            ModelStatusBanner.Visibility = Visibility.Visible;
            BannerIcon.Glyph = "\uE946";
            BannerText.Text = "No models downloaded. Download a model to get started.";
            BannerButton.Content = "Download";
            BannerButton.Visibility = Visibility.Visible;
            BannerButton.Click += OnBannerShowModelManager;
        }
        else
        {
            ModelStatusBanner.Visibility = Visibility.Collapsed;
        }
    }

    private void OnBannerLoadModel(object sender, RoutedEventArgs e)
    {
        _ = LoadModelWithErrorHandling();
    }

    private void OnBannerShowModelManager(object sender, RoutedEventArgs e)
    {
        ShowModelManager();
    }

    private async Task LoadModelWithErrorHandling()
    {
        try { await _vm.LoadModelAsync(); }
        catch (Exception ex) { _vm.ErrorMessage = $"Failed to load model: {ex.Message}"; }
    }

    private void UpdateErrorBanner()
    {
        if (!string.IsNullOrEmpty(_vm.ErrorMessage))
        {
            ErrorBanner.Visibility = Visibility.Visible;
            ErrorText.Text = _vm.ErrorMessage;
        }
        else
        {
            ErrorBanner.Visibility = Visibility.Collapsed;
        }
    }

    private void ShowModelManager()
    {
        ModelDownloadPanel.Initialize(_vm.ModelService, _vm.SelectedModelId);
        ModelOverlay.Visibility = Visibility.Visible;
    }

    private void HideModelManager()
    {
        ModelOverlay.Visibility = Visibility.Collapsed;
        _vm.SelectDefaultModel();
    }

    private bool _historyVisible = false;
    private void ToggleHistory()
    {
        _historyVisible = !_historyVisible;
        HistoryBorder.Visibility = _historyVisible ? Visibility.Visible : Visibility.Collapsed;
        RecordingControls.UpdateHistoryButtonState(_historyVisible);
    }

    /// <summary>Shows and restores the window from the system tray.</summary>
    public void ShowAndRestore()
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        Win32Interop.ShowWindow(hwnd, Win32Interop.SW_RESTORE);
        Win32Interop.SetForegroundWindow(hwnd);
        Activate();
    }

    /// <summary>Hides the window (minimizes to tray).</summary>
    public void HideWindow()
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        Win32Interop.ShowWindow(hwnd, Win32Interop.SW_HIDE);
    }

    /// <summary>Marks the window for actual close (quit) instead of hide-to-tray.</summary>
    public void PrepareForQuit()
    {
        _isQuitting = true;
    }
}

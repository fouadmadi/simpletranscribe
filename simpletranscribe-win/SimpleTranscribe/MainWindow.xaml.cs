using Microsoft.UI.Xaml;
using SimpleTranscribe.ViewModels;

namespace SimpleTranscribe;

public sealed partial class MainWindow : Window
{
    private readonly MainViewModel _vm = new();

    public MainWindow()
    {
        InitializeComponent();

        // Set default window size to match macOS (700×550)
        AppWindow.Resize(new Windows.Graphics.SizeInt32(700, 550));
        Title = "SimpleTranscribe";

        // Wire up view events to view model
        RecordingControls.ToggleRecordingClicked += (_, _) => _vm.ToggleRecording();
        RecordingControls.ShowModelManagerClicked += (_, _) => ShowModelManager();

        Settings.DeviceChanged += (_, id) => _vm.SelectedDeviceId = id;
        Settings.ModelChanged += (_, id) => _vm.SelectedModelId = id;
        Settings.LanguageChanged += (_, lang) => _vm.SelectedLanguage = lang;

        TranscriptResults.TextChanged += (_, text) => _vm.TranscribedText = text;
        TranscriptResults.CopyClicked += (_, _) => _vm.CopyToClipboard();

        ModelDownloadPanel.CloseRequested += (_, _) => HideModelManager();
        ModelDownloadPanel.ModelSelected += (_, id) => _vm.SelectedModelId = id;

        // Subscribe to view model property changes
        _vm.PropertyChanged += OnViewModelPropertyChanged;

        // Deferred setup
        DispatcherQueue.TryEnqueue(async () =>
        {
            ModelDownloadPanel.Initialize(_vm.ModelService, _vm.SelectedModelId);
            await _vm.SetupAsync();
            SyncAllUI();
        });

        Closed += (_, _) =>
        {
            ModelDownloadPanel.Detach();
            _vm.Cleanup();
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

                case nameof(MainViewModel.ErrorMessage):
                    UpdateErrorBanner();
                    break;

                case nameof(MainViewModel.AvailableDevices):
                    Settings.UpdateDevices(_vm.AvailableDevices, _vm.SelectedDeviceId);
                    break;

                case nameof(MainViewModel.DownloadedModels):
                    Settings.UpdateModels(_vm.DownloadedModels, _vm.SelectedModelId);
                    UpdateModelBanner();
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
        Settings.UpdateModels(_vm.DownloadedModels, _vm.SelectedModelId);
        Settings.UpdateLanguage(_vm.SelectedLanguage);
        TranscriptResults.Text = _vm.TranscribedText;
        UpdateModelBanner();
        UpdateErrorBanner();
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
}

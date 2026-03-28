using Microsoft.UI.Xaml;
using SimpleTranscribe.Models;
using SimpleTranscribe.Services;
using SimpleTranscribe.ViewModels;
using SimpleTranscribe.Views;

namespace SimpleTranscribe;

public partial class App : Application
{
    private MainWindow? _window;
    private MainViewModel? _vm;
    private TrayIconManager? _trayIcon;
    private FloatingOverlayWindow? _overlay;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _vm = new MainViewModel();
        _window = new MainWindow(_vm);

        InitializeTrayIcon();
        InitializeOverlay();

        // Update tray tooltip when recording/processing state changes
        _vm.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(MainViewModel.IsRecording)
                               or nameof(MainViewModel.IsProcessing))
            {
                var state = _vm.IsRecording ? "Recording..."
                          : _vm.IsProcessing ? "Transcribing..."
                          : "Idle";
                _trayIcon?.UpdateTooltip($"SimpleTranscribe - {state}");
            }
        };

        // Show window unless launched with --minimized
        bool startMinimized = Environment.GetCommandLineArgs()
            .Any(a => a.Equals("--minimized", StringComparison.OrdinalIgnoreCase));

        if (!startMinimized)
            _window.Activate();
        else
            _window.HideWindow();
    }

    private void InitializeTrayIcon()
    {
        _trayIcon = new TrayIconManager();
        _trayIcon.ShowWindowRequested += ShowMainWindow;
        _trayIcon.QuitRequested += Quit;

        var (hIcon, ownsIcon) = LoadAppIcon();
        _trayIcon.Show(hIcon, ownsIcon);
    }

    private void InitializeOverlay()
    {
        _overlay = new FloatingOverlayWindow();

        // Hide the overlay window immediately — it starts hidden
        _overlay.Activate();
        _overlay.HideOverlay();

        if (_vm is null) return;

        _vm.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName != nameof(MainViewModel.OverlayState)) return;

            _overlay.DispatcherQueue.TryEnqueue(() =>
            {
                switch (_vm.OverlayState)
                {
                    case OverlayState.Recording:
                    case OverlayState.Transcribing:
                        _overlay.ShowOverlay(_vm.OverlayState);
                        break;
                    case OverlayState.Done:
                        _overlay.ShowDone();
                        break;
                    case OverlayState.Error:
                        _overlay.ShowError(_vm.ErrorMessage ?? "Error");
                        break;
                    case OverlayState.Idle:
                    default:
                        _overlay.HideOverlay();
                        break;
                }
            });
        };
    }

    private static (nint hIcon, bool ownsIcon) LoadAppIcon()
    {
        // Try to extract the first icon from the running executable
        var exePath = Environment.ProcessPath;
        if (!string.IsNullOrEmpty(exePath))
        {
            var icon = Interop.Win32Interop.ExtractIconW(0, exePath, 0);
            if (icon > 1) // 0 = file not found, 1 = no icons in file
                return (icon, true);
        }

        // Fall back to the stock system application icon (shared; do not destroy)
        return (Interop.Win32Interop.LoadIconW(0, Interop.Win32Interop.IDI_APPLICATION), false);
    }

    private void ShowMainWindow()
    {
        _window?.ShowAndRestore();
    }

    internal void Quit()
    {
        _trayIcon?.Dispose();
        _trayIcon = null;

        _overlay?.HideOverlay();
        _overlay = null;

        _window?.PrepareForQuit();
        _window?.Close();
        _window = null;

        _vm?.Cleanup();
        _vm = null;
    }
}

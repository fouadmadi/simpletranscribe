using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using SimpleTranscribe.Interop;
using SimpleTranscribe.Models;

namespace SimpleTranscribe.Views;

public sealed partial class FloatingOverlayWindow : Window
{
    private const int OverlayWidth = 160;
    private const int OverlayHeight = 40;
    private const int ScreenMargin = 16;

    private DispatcherTimer? _autoDismissTimer;

    public FloatingOverlayWindow()
    {
        InitializeComponent();
        ConfigureWindowChrome();
    }

    private void ConfigureWindowChrome()
    {
        Title = string.Empty;

        // Borderless, always-on-top, non-resizable
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsAlwaysOnTop = true;
            presenter.IsResizable = false;
            presenter.IsMinimizable = false;
            presenter.IsMaximizable = false;
            presenter.SetBorderAndTitleBar(false, false);
        }

        AppWindow.Resize(new Windows.Graphics.SizeInt32(OverlayWidth, OverlayHeight));
        PositionTopRight();
    }

    private void PositionTopRight()
    {
        int screenWidth = Win32Interop.GetSystemMetrics(Win32Interop.SM_CXSCREEN);
        int x = screenWidth - OverlayWidth - ScreenMargin;
        int y = ScreenMargin;
        AppWindow.Move(new Windows.Graphics.PointInt32(x, y));
    }

    private void MakeClickThrough()
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        int exStyle = Win32Interop.GetWindowLong(hwnd, Win32Interop.GWL_EXSTYLE);
        Win32Interop.SetWindowLong(hwnd, Win32Interop.GWL_EXSTYLE,
            exStyle | Win32Interop.WS_EX_TRANSPARENT | Win32Interop.WS_EX_LAYERED);
    }

    private void RemoveClickThrough()
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        int exStyle = Win32Interop.GetWindowLong(hwnd, Win32Interop.GWL_EXSTYLE);
        Win32Interop.SetWindowLong(hwnd, Win32Interop.GWL_EXSTYLE,
            exStyle & ~(Win32Interop.WS_EX_TRANSPARENT | Win32Interop.WS_EX_LAYERED));
    }

    public void ShowOverlay(OverlayState state)
    {
        StopAutoDismiss();

        // Reset all indicator visibility
        RecordingDot.Visibility = Visibility.Collapsed;
        TranscribingRing.Visibility = Visibility.Collapsed;
        TranscribingRing.IsActive = false;
        DoneIcon.Visibility = Visibility.Collapsed;
        ErrorIcon.Visibility = Visibility.Collapsed;
        PulseStoryboard.Stop();

        switch (state)
        {
            case OverlayState.Recording:
                RecordingDot.Visibility = Visibility.Visible;
                StatusText.Text = "Recording...";
                PulseStoryboard.Begin();
                break;

            case OverlayState.Transcribing:
                TranscribingRing.Visibility = Visibility.Visible;
                TranscribingRing.IsActive = true;
                StatusText.Text = "Transcribing...";
                break;

            case OverlayState.Done:
                DoneIcon.Visibility = Visibility.Visible;
                StatusText.Text = "Done!";
                break;

            case OverlayState.Error:
                ErrorIcon.Visibility = Visibility.Visible;
                StatusText.Text = "Error";
                break;

            default:
                HideOverlay();
                return;
        }

        PositionTopRight();
        Activate();

        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        Win32Interop.ShowWindow(hwnd, Win32Interop.SW_SHOWNOACTIVATE);

        MakeClickThrough();
    }

    public void HideOverlay()
    {
        StopAutoDismiss();
        PulseStoryboard.Stop();
        TranscribingRing.IsActive = false;

        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        Win32Interop.ShowWindow(hwnd, Win32Interop.SW_HIDE);
        RemoveClickThrough();
    }

    public void ShowDone()
    {
        ShowOverlay(OverlayState.Done);
        StartAutoDismiss(TimeSpan.FromSeconds(1.5));
    }

    public void ShowError(string message)
    {
        ShowOverlay(OverlayState.Error);
        StatusText.Text = string.IsNullOrEmpty(message) ? "Error" : message;
        StartAutoDismiss(TimeSpan.FromSeconds(3));
    }

    private void StartAutoDismiss(TimeSpan delay)
    {
        StopAutoDismiss();
        _autoDismissTimer = new DispatcherTimer { Interval = delay };
        _autoDismissTimer.Tick += (_, _) =>
        {
            StopAutoDismiss();
            HideOverlay();
        };
        _autoDismissTimer.Start();
    }

    private void StopAutoDismiss()
    {
        if (_autoDismissTimer is not null)
        {
            _autoDismissTimer.Stop();
            _autoDismissTimer = null;
        }
    }
}

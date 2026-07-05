# Dev Design #15 — Windows Floating Overlay

## Problem
The macOS app has a `FloatingOverlayWindow` — a small always-on-top HUD shown during recording and transcribing that lets the user see app state without switching focus. The Windows app has a system tray icon but no equivalent overlay. When the user minimises the app to the tray and starts recording (via hotkey), there is no visible feedback that anything is happening.

---

## Goals
- Add a small, always-on-top, borderless overlay window on Windows, shown during recording and transcribing.
- Overlay is non-interactive (click-through) during recording; dismissible by clicking during error states.
- Disappears automatically when recording/transcribing ends.
- Mirrors the Mac `FloatingOverlayWindow` in UX concept, using WinUI 3 primitives.

---

## Architecture Overview

WinUI 3 does not provide a native "always-on-top borderless window" via XAML alone. The approach is:

1. Create a secondary `Microsoft.UI.Windowing.AppWindow` using `OverlappedPresenter` with no title bar, no frame, and topmost set.
2. Host a WinUI 3 `DesktopChildSiteBridge` or a standalone `Window` with transparent background.
3. Position the window in the bottom-right corner, inset from the taskbar.
4. Control visibility from `MainViewModel` via an `OverlayManager` service.

---

## Implementation

### 1. OverlayState enum

```csharp
// OverlayState.cs
public enum OverlayState
{
    Hidden,
    Recording,
    Transcribing,
    Error
}
```

### 2. OverlayWindow.xaml (new Window)

Create a new WinUI 3 `Window` with a minimal XAML layout:

```xml
<!-- OverlayWindow.xaml -->
<Window x:Class="SimpleTranscribe.OverlayWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
    <Grid Background="Transparent">
        <Border CornerRadius="12"
                Padding="12,8"
                Background="{ThemeResource AcrylicInAppFillColorDefaultBrush}"
                BorderBrush="{ThemeResource DividerStrokeColorDefaultBrush}"
                BorderThickness="1">
            <StackPanel Orientation="Horizontal" Spacing="10">

                <!-- Recording indicator -->
                <Ellipse x:Name="RecordingDot"
                         Width="10" Height="10"
                         Fill="Red"
                         Visibility="Collapsed"/>

                <!-- Transcribing spinner -->
                <ProgressRing x:Name="TranscribingSpinner"
                              Width="16" Height="16"
                              IsActive="False"
                              Visibility="Collapsed"/>

                <!-- State label -->
                <TextBlock x:Name="StateLabel"
                           VerticalAlignment="Center"
                           FontSize="12"
                           Foreground="{ThemeResource TextFillColorPrimaryBrush}"/>
            </StackPanel>
        </Border>
    </Grid>
</Window>
```

### 3. OverlayWindow.xaml.cs

```csharp
// OverlayWindow.xaml.cs
using Microsoft.UI.Windowing;
using Microsoft.UI;
using WinRT.Interop;

public sealed partial class OverlayWindow : Window
{
    private readonly AppWindow _appWindow;

    public OverlayWindow()
    {
        InitializeComponent();

        var hwnd = WindowNative.GetWindowHandle(this);
        var windowId = Win32Interop.GetWindowIdFromWindow(hwnd);
        _appWindow = AppWindow.GetFromWindowId(windowId);

        ConfigureWindow();
        PositionBottomRight();
    }

    private void ConfigureWindow()
    {
        // Remove title bar, frame, and make always-on-top
        var presenter = OverlappedPresenter.CreateForToolWindow();
        presenter.IsResizable = false;
        presenter.IsMaximizable = false;
        presenter.IsMinimizable = false;
        presenter.IsAlwaysOnTop = true;
        _appWindow.SetPresenter(presenter);

        // Remove the title bar entirely
        _appWindow.TitleBar.ExtendsContentIntoTitleBar = true;

        // Make window click-through during recording
        SetClickThrough(true);

        _appWindow.Resize(new Windows.Graphics.SizeInt32 { Width = 200, Height = 48 });
    }

    private void PositionBottomRight()
    {
        // Position in bottom-right, above the taskbar (~80px inset)
        var displayArea = DisplayArea.GetFromWindowId(_appWindow.Id, DisplayAreaFallback.Nearest);
        var workArea = displayArea.WorkArea;
        _appWindow.Move(new Windows.Graphics.PointInt32
        {
            X = workArea.X + workArea.Width - 220,
            Y = workArea.Y + workArea.Height - 80
        });
    }

    private void SetClickThrough(bool enabled)
    {
        var hwnd = WindowNative.GetWindowHandle(this);
        var style = Win32Helper.GetWindowLong(hwnd, Win32Helper.GWL_EXSTYLE);
        if (enabled)
            style |= Win32Helper.WS_EX_TRANSPARENT | Win32Helper.WS_EX_LAYERED;
        else
            style &= ~(Win32Helper.WS_EX_TRANSPARENT | Win32Helper.WS_EX_LAYERED);
        Win32Helper.SetWindowLong(hwnd, Win32Helper.GWL_EXSTYLE, style);
    }

    public void SetState(OverlayState state, string? errorMessage = null)
    {
        switch (state)
        {
            case OverlayState.Recording:
                RecordingDot.Visibility = Visibility.Visible;
                TranscribingSpinner.Visibility = Visibility.Collapsed;
                TranscribingSpinner.IsActive = false;
                StateLabel.Text = "Recording…";
                SetClickThrough(true);
                _appWindow.Show();
                break;

            case OverlayState.Transcribing:
                RecordingDot.Visibility = Visibility.Collapsed;
                TranscribingSpinner.Visibility = Visibility.Visible;
                TranscribingSpinner.IsActive = true;
                StateLabel.Text = "Transcribing…";
                SetClickThrough(true);
                break;

            case OverlayState.Error:
                RecordingDot.Visibility = Visibility.Collapsed;
                TranscribingSpinner.Visibility = Visibility.Collapsed;
                TranscribingSpinner.IsActive = false;
                StateLabel.Text = errorMessage ?? "Error";
                SetClickThrough(false);   // allow click-to-dismiss
                break;

            case OverlayState.Hidden:
            default:
                _appWindow.Hide();
                break;
        }
    }
}
```

### 4. Win32Helper.cs (minimal P/Invoke)

```csharp
// Win32Helper.cs
internal static class Win32Helper
{
    internal const int GWL_EXSTYLE   = -20;
    internal const int WS_EX_LAYERED = 0x00080000;
    internal const int WS_EX_TRANSPARENT = 0x00000020;

    [DllImport("user32.dll")]
    internal static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    internal static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
}
```

### 5. OverlayManager.cs (new service)

```csharp
// OverlayManager.cs
public class OverlayManager
{
    private OverlayWindow? _window;

    public void Show(OverlayState state, string? errorMessage = null)
    {
        if (_window is null)
        {
            _window = new OverlayWindow();
            _window.Closed += (_, _) => _window = null;
        }
        _window.SetState(state, errorMessage);
    }

    public void Hide()
    {
        _window?.SetState(OverlayState.Hidden);
    }

    public void ShowError(string message)
    {
        Show(OverlayState.Error, message);
        // Auto-dismiss after 4 seconds
        Task.Delay(4000).ContinueWith(_ => Hide());
    }
}
```

### 6. MainViewModel — integrate OverlayManager

```csharp
// MainViewModel.cs
private readonly OverlayManager _overlayManager = new();

// In StartRecording():
_overlayManager.Show(OverlayState.Recording);

// In StopRecordingAndTranscribe(), before transcription begins:
_overlayManager.Show(OverlayState.Transcribing);

// After transcription completes:
_overlayManager.Hide();

// On error:
_overlayManager.ShowError("Transcription failed — see log");
```

### 7. Settings — enable/disable overlay

Add a toggle to the Settings page so power users can disable the overlay:

```csharp
// SettingsManager — new key
public bool ShowFloatingOverlay
{
    get => Get("ShowFloatingOverlay", defaultValue: true);
    set => Set("ShowFloatingOverlay", value);
}
```

```xml
<!-- SettingsPage.xaml -->
<ToggleSwitch Header="Show floating overlay during recording"
              IsOn="{x:Bind _vm.ShowFloatingOverlay, Mode=TwoWay}"/>
```

In `MainViewModel`, gate overlay calls:

```csharp
if (_settingsManager.ShowFloatingOverlay)
    _overlayManager.Show(OverlayState.Recording);
```

---

## Overlay Behaviour Matrix

| Scenario | Overlay visible? | State shown |
|----------|-----------------|-------------|
| App in foreground, recording | Yes (optional) | Recording |
| App minimised to tray, recording | Yes | Recording |
| App in foreground, transcribing | Yes | Transcribing |
| App minimised to tray, transcribing | Yes | Transcribing |
| Transcription complete | No | — |
| Transcription error | Yes (4 s) | Error message |
| Paste failed | Yes (4 s, or defer to design #11) | Paste failed |
| Model loading | No | — |
| App closed (no tray) | No | — |

---

## Recording Dot Animation

Add a simple pulse animation to the red recording dot via WinUI 3 `Storyboard`:

```xml
<Ellipse.Resources>
    <Storyboard x:Name="PulseStoryboard" RepeatBehavior="Forever">
        <DoubleAnimation Storyboard.TargetProperty="Opacity"
                         From="1.0" To="0.3" Duration="0:0:0.8"
                         AutoReverse="True"/>
    </Storyboard>
</Ellipse.Resources>
```

Start the storyboard in `SetState(OverlayState.Recording)`:

```csharp
PulseStoryboard.Begin();
```

---

## Acceptance Criteria
- [ ] Overlay window appears in the bottom-right corner when recording starts (via hotkey or UI button).
- [ ] Overlay remains on top of all other windows.
- [ ] Overlay is click-through during recording and transcribing (does not steal focus or input).
- [ ] Overlay transitions from "Recording" to "Transcribing" state when recording stops.
- [ ] Overlay hides automatically when transcription completes.
- [ ] Error state shows a message and auto-dismisses after 4 seconds.
- [ ] Error state is not click-through (user can dismiss early by clicking).
- [ ] Overlay can be disabled via the Settings toggle.
- [ ] Overlay positions correctly on multi-monitor setups (follows the primary display work area).
- [ ] Overlay renders correctly in both light and dark Windows themes.
- [ ] No focus stealing — active window remains focused throughout.

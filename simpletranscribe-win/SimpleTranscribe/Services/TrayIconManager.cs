using System.Runtime.InteropServices;
using SimpleTranscribe.Interop;

namespace SimpleTranscribe.Services;

/// <summary>
/// Manages a system tray icon using raw Win32 Shell_NotifyIcon P/Invoke.
/// Creates a hidden message-only window to receive tray icon click messages.
/// </summary>
public sealed class TrayIconManager : IDisposable
{
    private static readonly AppLogger Log = AppLogger.Instance;

    private const uint TRAY_ICON_ID = 1;
    private const uint WM_TRAYICON = Win32Interop.WM_APP + 1;
    private const uint IDM_OPEN = 1001;
    private const uint IDM_QUIT = 1002;
    private const uint IDM_STARTUP = 1003;

    private nint _messageHwnd;
    private nint _hIcon;
    private bool _ownsIcon;
    private bool _iconAdded;
    private bool _disposed;
    private nint _classNamePtr;

    // Must prevent GC of the delegate
    private Win32Interop.WndProc? _wndProc;

    /// <summary>Fired when the user requests showing the main window (left-click or "Open" menu item).</summary>
    public event Action? ShowWindowRequested;

    /// <summary>Fired when the user selects "Quit" from the tray context menu.</summary>
    public event Action? QuitRequested;

    /// <summary>
    /// Creates and shows the tray icon.
    /// </summary>
    /// <param name="hIcon">Icon handle to display in the tray.</param>
    /// <param name="ownsIcon">If true, the icon handle will be destroyed on Dispose.</param>
    public void Show(nint hIcon, bool ownsIcon)
    {
        _hIcon = hIcon;
        _ownsIcon = ownsIcon;
        CreateMessageWindow();
        AddTrayIcon("SimpleTranscribe - Idle");
    }

    /// <summary>
    /// Updates the tray icon tooltip text.
    /// </summary>
    public void UpdateTooltip(string tooltip)
    {
        if (!_iconAdded || _messageHwnd == 0) return;

        var nid = CreateNotifyIconData();
        nid.uFlags = Win32Interop.NIF_TIP;
        SetTip(ref nid, tooltip);

        Win32Interop.Shell_NotifyIconW(Win32Interop.NIM_MODIFY, ref nid);
    }

    private void CreateMessageWindow()
    {
        _wndProc = WndProc;
        var hInstance = Win32Interop.GetModuleHandleW(null);
        _classNamePtr = Marshal.StringToHGlobalUni("SimpleTranscribeTrayWnd");

        var wc = new WNDCLASSEXW
        {
            cbSize = (uint)Marshal.SizeOf<WNDCLASSEXW>(),
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(_wndProc),
            hInstance = hInstance,
            lpszClassName = _classNamePtr
        };

        Win32Interop.RegisterClassExW(ref wc);

        _messageHwnd = Win32Interop.CreateWindowExW(
            0, "SimpleTranscribeTrayWnd", "",
            0, 0, 0, 0, 0,
            Win32Interop.HWND_MESSAGE,
            nint.Zero, hInstance, nint.Zero);

        Log.Info("Tray", _messageHwnd != 0
            ? "Message window created"
            : "Failed to create message window");
    }

    private void AddTrayIcon(string tooltip)
    {
        var nid = CreateNotifyIconData();
        nid.uFlags = Win32Interop.NIF_MESSAGE | Win32Interop.NIF_ICON | Win32Interop.NIF_TIP;
        nid.uCallbackMessage = WM_TRAYICON;
        nid.hIcon = _hIcon;
        SetTip(ref nid, tooltip);

        _iconAdded = Win32Interop.Shell_NotifyIconW(Win32Interop.NIM_ADD, ref nid);
        Log.Info("Tray", _iconAdded ? "Tray icon added" : "Failed to add tray icon");
    }

    private void RemoveTrayIcon()
    {
        if (!_iconAdded) return;

        var nid = CreateNotifyIconData();
        Win32Interop.Shell_NotifyIconW(Win32Interop.NIM_DELETE, ref nid);
        _iconAdded = false;
    }

    private NOTIFYICONDATAW CreateNotifyIconData()
    {
        var nid = new NOTIFYICONDATAW();
        SetNotifyIconSize(ref nid);
        nid.hWnd = _messageHwnd;
        nid.uID = TRAY_ICON_ID;
        return nid;
    }

    private static unsafe void SetNotifyIconSize(ref NOTIFYICONDATAW nid)
    {
        nid.cbSize = (uint)sizeof(NOTIFYICONDATAW);
    }

    private static unsafe void SetTip(ref NOTIFYICONDATAW nid, string tip)
    {
        var span = tip.AsSpan();
        var len = Math.Min(span.Length, 63);
        for (int i = 0; i < len; i++)
            nid.szTip[i] = span[i];
        nid.szTip[len] = '\0';
    }

    private nint WndProc(nint hWnd, uint msg, nint wParam, nint lParam)
    {
        if (msg == WM_TRAYICON)
        {
            // Default version (pre-V4): lParam = mouse message
            var mouseMsg = (uint)lParam;

            if (mouseMsg == Win32Interop.WM_LBUTTONUP)
                ShowWindowRequested?.Invoke();
            else if (mouseMsg == Win32Interop.WM_RBUTTONUP)
                ShowContextMenu();

            return 0;
        }

        if (msg == Win32Interop.WM_COMMAND)
        {
            var cmdId = (uint)(wParam & 0xFFFF);
            switch (cmdId)
            {
                case IDM_OPEN:
                    ShowWindowRequested?.Invoke();
                    break;
                case IDM_STARTUP:
                    StartupManager.Toggle();
                    break;
                case IDM_QUIT:
                    QuitRequested?.Invoke();
                    break;
            }
            return 0;
        }

        return Win32Interop.DefWindowProcW(hWnd, msg, wParam, lParam);
    }

    private void ShowContextMenu()
    {
        var hMenu = Win32Interop.CreatePopupMenu();
        if (hMenu == 0) return;

        Win32Interop.AppendMenuW(hMenu, Win32Interop.MF_STRING, (nuint)IDM_OPEN, "Open SimpleTranscribe");
        Win32Interop.AppendMenuW(hMenu, Win32Interop.MF_SEPARATOR, 0, null);

        var startupFlags = StartupManager.IsEnabled
            ? Win32Interop.MF_STRING | Win32Interop.MF_CHECKED
            : Win32Interop.MF_STRING | Win32Interop.MF_UNCHECKED;
        Win32Interop.AppendMenuW(hMenu, startupFlags, (nuint)IDM_STARTUP, "Start at Login");

        Win32Interop.AppendMenuW(hMenu, Win32Interop.MF_SEPARATOR, 0, null);
        Win32Interop.AppendMenuW(hMenu, Win32Interop.MF_STRING, (nuint)IDM_QUIT, "Quit");

        // SetForegroundWindow + PostMessage(WM_NULL) is required for proper menu dismissal
        Win32Interop.GetCursorPos(out var pt);
        Win32Interop.SetForegroundWindow(_messageHwnd);
        Win32Interop.TrackPopupMenuEx(
            hMenu,
            Win32Interop.TPM_LEFTALIGN | Win32Interop.TPM_BOTTOMALIGN,
            pt.x, pt.y, _messageHwnd, nint.Zero);
        Win32Interop.PostMessageW(_messageHwnd, Win32Interop.WM_NULL, 0, 0);

        Win32Interop.DestroyMenu(hMenu);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        RemoveTrayIcon();

        if (_messageHwnd != 0)
        {
            Win32Interop.DestroyWindow(_messageHwnd);
            _messageHwnd = 0;
        }

        if (_ownsIcon && _hIcon != 0)
        {
            Win32Interop.DestroyIcon(_hIcon);
            _hIcon = 0;
        }

        if (_classNamePtr != 0)
        {
            Marshal.FreeHGlobal(_classNamePtr);
            _classNamePtr = 0;
        }

        _wndProc = null;
    }
}

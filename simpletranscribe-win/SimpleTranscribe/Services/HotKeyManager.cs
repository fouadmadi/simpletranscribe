using System.Runtime.InteropServices;
using SimpleTranscribe.Interop;

namespace SimpleTranscribe.Services;

/// <summary>
/// Global press-to-talk hotkey using a low-level keyboard hook.
/// Port of macOS HotKeyManager.swift — uses Ctrl+Space instead of fn+Ctrl (configurable).
/// 
/// Detects key-down → start recording, key-up → stop &amp; transcribe.
/// </summary>
public class HotKeyManager : IDisposable
{
    private static readonly AppLogger Log = AppLogger.Instance;

    private nint _hookId;
    private Win32Interop.LowLevelKeyboardProc? _hookProc;
    private bool _isCtrlHeld;
    private bool _isHotKeyPressed;
    private bool _disposed;

    /// <summary>
    /// The virtual key code for the hotkey trigger key. Default is Space (0x20).
    /// </summary>
    public int TargetVKey { get; set; } = Win32Interop.VK_SPACE;

    /// <summary>
    /// The required modifier virtual key code. Default is Control (0x11).
    /// </summary>
    public int TargetModifierVKey { get; set; } = Win32Interop.VK_CONTROL;

    /// <summary>
    /// Whether the hotkey combo is currently held down.
    /// </summary>
    public bool IsHotKeyPressed
    {
        get => _isHotKeyPressed;
        private set
        {
            if (_isHotKeyPressed == value) return;
            _isHotKeyPressed = value;
            HotKeyStateChanged?.Invoke(value);
        }
    }

    /// <summary>
    /// Fired when hotkey state changes (true = pressed, false = released).
    /// Always fired on the thread that installed the hook.
    /// </summary>
    public event Action<bool>? HotKeyStateChanged;

    /// <summary>
    /// Update the active hotkey combination.
    /// </summary>
    public void UpdateHotKey(int vKey, int modifierVKey)
    {
        // Reset any in-progress state before switching
        if (IsHotKeyPressed)
            IsHotKeyPressed = false;
        _isCtrlHeld = false;
        TargetVKey = vKey;
        TargetModifierVKey = modifierVKey;
    }

    /// <summary>
    /// Install the keyboard hook. Must be called from a thread with a message pump.
    /// </summary>
    public void Setup()
    {
        if (_hookId != nint.Zero)
            return;

        // Must keep a reference to prevent the delegate from being garbage collected
        _hookProc = HookCallback;

        var moduleHandle = Win32Interop.GetModuleHandleW(null);
        _hookId = Win32Interop.SetWindowsHookExW(
            Win32Interop.WH_KEYBOARD_LL,
            _hookProc,
            moduleHandle,
            0);

        Log.Info("HotKey", _hookId != nint.Zero ? "Keyboard hook installed" : "Failed to install keyboard hook");
    }

    private nint HookCallback(int nCode, nint wParam, nint lParam)
    {
        if (nCode >= 0)
        {
            var hookStruct = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
            var vkCode = hookStruct.vkCode;
            var msgType = (int)wParam;

            bool isKeyDown = msgType is Win32Interop.WM_KEYDOWN or Win32Interop.WM_SYSKEYDOWN;
            bool isKeyUp = msgType is Win32Interop.WM_KEYUP or Win32Interop.WM_SYSKEYUP;

            // Track modifier state (Ctrl variants)
            bool isModifier = vkCode == TargetModifierVKey ||
                              (TargetModifierVKey == Win32Interop.VK_CONTROL &&
                               vkCode is 0xA2 or 0xA3); // VK_LCONTROL, VK_RCONTROL

            if (isModifier)
            {
                _isCtrlHeld = isKeyDown;
                if (isKeyUp && IsHotKeyPressed)
                    IsHotKeyPressed = false;
            }

            // Detect trigger key while modifier is held
            if (vkCode == TargetVKey)
            {
                if (isKeyDown && _isCtrlHeld && !IsHotKeyPressed)
                    IsHotKeyPressed = true;
                else if (isKeyUp && IsHotKeyPressed)
                    IsHotKeyPressed = false;
            }
        }

        return Win32Interop.CallNextHookEx(_hookId, nCode, wParam, lParam);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        if (_hookId != nint.Zero)
        {
            Win32Interop.UnhookWindowsHookEx(_hookId);
            _hookId = nint.Zero;
        }
        _hookProc = null;

        GC.SuppressFinalize(this);
    }
}

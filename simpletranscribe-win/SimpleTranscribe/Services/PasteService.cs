using System.Runtime.InteropServices;
using SimpleTranscribe.Interop;

namespace SimpleTranscribe.Services;

/// <summary>
/// Handles copy-to-clipboard and paste-at-cursor via Win32 SendInput.
/// Port of macOS PasteService.swift — replaces CGEvent/AppleScript with SendInput.
///
/// Unlike macOS which needs Accessibility permission and has 3 fallback strategies,
/// Windows SendInput works universally (except for elevated windows due to UIPI).
/// </summary>
public static class PasteService
{
    /// <summary>
    /// Copy text to clipboard and simulate Ctrl+V to paste at cursor.
    /// </summary>
    public static void CopyAndPaste(string text)
    {
        if (!SetClipboardText(text))
            return;

        // Small delay to ensure clipboard is populated before simulating paste
        Task.Delay(150).ContinueWith(_ => SimulateCtrlV(), TaskScheduler.Default);
    }

    /// <summary>
    /// Copy text to clipboard only (no paste simulation).
    /// </summary>
    public static void CopyToClipboard(string text)
    {
        SetClipboardText(text);
    }

    /// <summary>
    /// Set clipboard text using Win32 API (works from any thread).
    /// Returns true if text was successfully placed on the clipboard.
    /// </summary>
    private static bool SetClipboardText(string text)
    {
        if (!Win32Interop.OpenClipboard(nint.Zero))
            return false;

        try
        {
            Win32Interop.EmptyClipboard();

            var bytes = (text.Length + 1) * 2; // UTF-16 + null terminator
            var hGlobal = Win32Interop.GlobalAlloc(Win32Interop.GMEM_MOVEABLE, (nuint)bytes);
            if (hGlobal == nint.Zero)
                return false;

            var locked = Win32Interop.GlobalLock(hGlobal);
            if (locked == nint.Zero)
            {
                // GlobalLock failed — free the memory and bail out
                Win32Interop.GlobalFree(hGlobal);
                return false;
            }

            Marshal.Copy(text.ToCharArray(), 0, locked, text.Length);
            // Null terminator is already zeroed by GlobalAlloc
            Win32Interop.GlobalUnlock(hGlobal);

            // SetClipboardData takes ownership of hGlobal on success.
            // On failure, we must free it ourselves.
            if (Win32Interop.SetClipboardData(Win32Interop.CF_UNICODETEXT, hGlobal) == nint.Zero)
            {
                Win32Interop.GlobalFree(hGlobal);
                return false;
            }

            return true;
        }
        finally
        {
            Win32Interop.CloseClipboard();
        }
    }

    /// <summary>
    /// Simulate Ctrl+V keystroke via SendInput.
    /// </summary>
    private static void SimulateCtrlV()
    {
        var inputs = new INPUT[]
        {
            // Ctrl down
            new()
            {
                type = Win32Interop.INPUT_KEYBOARD,
                u = new InputUnion { ki = new KEYBDINPUT { wVk = Win32Interop.VK_CONTROL } }
            },
            // V down
            new()
            {
                type = Win32Interop.INPUT_KEYBOARD,
                u = new InputUnion { ki = new KEYBDINPUT { wVk = Win32Interop.VK_V } }
            },
            // V up
            new()
            {
                type = Win32Interop.INPUT_KEYBOARD,
                u = new InputUnion
                {
                    ki = new KEYBDINPUT { wVk = Win32Interop.VK_V, dwFlags = Win32Interop.KEYEVENTF_KEYUP }
                }
            },
            // Ctrl up
            new()
            {
                type = Win32Interop.INPUT_KEYBOARD,
                u = new InputUnion
                {
                    ki = new KEYBDINPUT { wVk = Win32Interop.VK_CONTROL, dwFlags = Win32Interop.KEYEVENTF_KEYUP }
                }
            },
        };

        var sent = Win32Interop.SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
        if (sent != inputs.Length)
        {
            // SendInput failed (e.g., UIPI blocked input to an elevated window).
            // Text remains on clipboard for manual Ctrl+V.
        }
    }
}

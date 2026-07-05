# Dev Design #11 — Paste Failure Notification

## Problem
On macOS, `PasteService` tries three strategies (CGEvent, AppleScript, osascript) and logs failures, but gives the user no visible feedback when all three fail. On Windows, `SendInput` silently fails for elevated target windows (UIPI). In both cases the transcribed text remains on the clipboard but the user does not know to press ⌘V / Ctrl+V manually.

---

## Goals
- Show a non-intrusive toast/banner when auto-paste fails, instructing the user to press ⌘V / Ctrl+V.
- Dismiss automatically after 4 seconds.
- Never block the UI or require a click to dismiss.
- Log the failure reason for debugging.

---

## Mac Design (Swift)

### PasteService — return result

Change `copyAndPaste` to report success/failure back to the caller via a completion callback:

```swift
// PasteService.swift
static func copyAndPaste(_ text: String, completion: @escaping (Bool) -> Void) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        var succeeded = false
        if pasteWithCGEvent()        { succeeded = true }
        else if pasteWithAppleScript() { succeeded = true }
        else if pasteWithOsascript()   { succeeded = true }

        if !succeeded {
            logger.error("Auto-paste failed — text is on clipboard, user should ⌘V")
        }
        completion(succeeded)
    }
}
```

### AppModel — handle paste result

```swift
// In stopRecordingAndTranscribe:
if autoPaste && !trimmed.isEmpty {
    if let target = self.previousApp, !target.isTerminated {
        target.activate()
    }
    PasteService.copyAndPaste(trimmed) { [weak self] success in
        DispatchQueue.main.async {
            if !success {
                self?.pasteFailedMessage = "Auto-paste failed — press ⌘V to paste"
                self?.autoClearPasteFailedMessage()
            }
        }
    }
}
```

Add to `AppModel`:

```swift
var pasteFailedMessage: String = ""
@ObservationIgnored private var pasteFailedWorkItem: DispatchWorkItem?

private func autoClearPasteFailedMessage() {
    pasteFailedWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
        self?.pasteFailedMessage = ""
    }
    pasteFailedWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
}
```

### ContentView — paste failure banner

Add a banner below the transcript, styled similarly to the existing `errorBanner`:

```swift
@ViewBuilder
private var pasteFailedBanner: some View {
    if !appModel.pasteFailedMessage.isEmpty {
        HStack(spacing: 8) {
            Image(systemName: "clipboard.fill")
                .foregroundColor(.orange)
            Text(appModel.pasteFailedMessage)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Copy Again") {
                copyToClipboard()
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut, value: appModel.pasteFailedMessage)
    }
}
```

Also update `FloatingOverlayView` to show a distinct paste-failed error:

```swift
// In AppModel.stopRecordingAndTranscribe, on paste failure:
overlayState = .error("Paste failed — press ⌘V")
autoClearOverlay(after: 4.0)
```

---

## Windows Design (C#)

### PasteService — return result

```csharp
// PasteService.cs
public static bool CopyAndPaste(string text)
{
    if (!SetClipboardText(text))
        return false;

    // Synchronously wait for clipboard, then simulate paste
    Task.Delay(150).Wait();
    var sent = SimulateCtrlV();
    return sent;
}

// SimulateCtrlV returns bool
private static bool SimulateCtrlV()
{
    // … existing SendInput code …
    var sent = Win32Interop.SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    return sent == (uint)inputs.Length;
}
```

> `CopyAndPaste` is called from `async void StopRecordingAndTranscribe`. Keep it fire-and-forget but capture the result:

```csharp
// In StopRecordingAndTranscribe:
if (autoPaste && !string.IsNullOrEmpty(trimmed))
{
    bool pasted = PasteService.CopyAndPaste(trimmed);
    if (!pasted)
    {
        PasteFailedMessage = "Auto-paste failed — press Ctrl+V to paste";
        _ = ClearPasteFailedMessageAsync();
    }
}
```

### MainViewModel

```csharp
[ObservableProperty] private string _pasteFailedMessage = "";

private async Task ClearPasteFailedMessageAsync()
{
    await Task.Delay(4000);
    PasteFailedMessage = "";
}
```

### UI — InfoBar in MainWindow.xaml

```xml
<InfoBar x:Name="PasteFailedBar"
         IsOpen="{x:Bind _vm.PasteFailedMessage, Converter={StaticResource StringToBoolConverter}, Mode=OneWay}"
         Severity="Warning"
         Title="Auto-paste failed"
         Message="{x:Bind _vm.PasteFailedMessage, Mode=OneWay}"
         IsClosable="True"
         CloseButtonClick="OnPasteFailedBarClose"/>
```

### Tray icon tooltip update

When paste fails while the window is hidden, update the tray tooltip briefly:

```csharp
_trayManager.UpdateTooltip("SimpleTranscribe — Press Ctrl+V to paste");
// Reset after 4s
await Task.Delay(4000);
_trayManager.UpdateTooltip("SimpleTranscribe — Idle");
```

---

## When Paste Fails (Common Causes)

| Cause | Platform | Explanation |
|-------|----------|-------------|
| No Accessibility permission | Mac | CGEvent requires `AXIsProcessTrusted`. Show the accessibility banner (already exists). |
| Elevated target window (UIPI) | Win | SendInput is blocked by UAC elevation on the target app. Cannot be worked around without elevation matching. |
| No frontmost app | Both | App had no target to paste into. Silently ignore (text is on clipboard). |
| System Events unavailable | Mac | AppleScript path fails; inform user. |

The banner message should be context-aware if possible:

- Accessibility not granted (Mac): *"Auto-paste failed — grant Accessibility in System Settings."* (Link to the existing Accessibility banner.)
- UIPI (Win): *"Auto-paste failed — Ctrl+V to paste (target app is elevated)."*
- Generic: *"Auto-paste failed — press ⌘V / Ctrl+V to paste."*

---

## Acceptance Criteria
- [ ] When all paste strategies fail, a banner appears within 200 ms.
- [ ] Banner message instructs the user to paste manually.
- [ ] Banner dismisses automatically after 4 seconds.
- [ ] Banner has a "Copy Again" button that re-copies the text to the clipboard.
- [ ] Floating overlay also shows a paste-failed error state on Mac.
- [ ] On Windows, the tray tooltip updates when the window is hidden.
- [ ] Paste success causes no banner (existing happy path unchanged).
- [ ] Accessibility permission denied (Mac) surfaces the existing Accessibility banner, not just the paste-failed banner.

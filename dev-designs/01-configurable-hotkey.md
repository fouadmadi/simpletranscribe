# Dev Design #1 — Configurable Hotkey

## Problem
Both apps hardcode the push-to-talk hotkey: `fn+Control` on Mac and `Ctrl+Space` on Windows.
Ctrl+Space conflicts with IDE autocomplete shortcuts (VS Code, IntelliJ, Xcode) and some keyboard layout dead-key sequences. Users have no recourse.

---

## Goals
- Let the user record any modifier-only combo (Mac) or key+modifier combo (Windows) as their hotkey.
- Persist the preference across launches.
- Detect and warn on conflicts with well-known system shortcuts.
- Keep the default behaviour unchanged for users who never visit Settings.

---

## Mac Design (Swift)

### Data Model

Add to `UserDefaults` persistence (already in `AppModel`):

```swift
// AppModel.swift
var hotKeyModifiers: NSEvent.ModifierFlags = {
    let raw = UserDefaults.standard.integer(forKey: "hotKeyModifiers")
    return raw == 0
        ? [.function, .control]               // default
        : NSEvent.ModifierFlags(rawValue: UInt(raw))
}() {
    didSet {
        UserDefaults.standard.set(Int(hotKeyModifiers.rawValue), forKey: "hotKeyModifiers")
        hotKeyManager?.updateHotKey(modifiers: hotKeyModifiers)
    }
}
```

### HotKeyManager changes

```swift
// HotKeyManager.swift
private(set) var requiredFlags: NSEvent.ModifierFlags = [.function, .control]

func updateHotKey(modifiers: NSEvent.ModifierFlags) {
    requiredFlags = modifiers
}
```

The `handleFlagsChanged` method already reads `requiredFlags` dynamically — no other change needed there.

### UI — Hotkey Recorder

Add a `HotKeyRecorderView` to `SettingsAreaView`:

```swift
struct HotKeyRecorderView: View {
    @Binding var modifiers: NSEvent.ModifierFlags
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(isRecording ? "Press keys…" : symbolString(modifiers)) {
            startRecording()
        }
        .buttonStyle(.bordered)
        .foregroundColor(isRecording ? .accentColor : .primary)
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let flags = event.modifierFlags.intersection([
                .command, .option, .control, .shift, .function
            ])
            if !flags.isEmpty {
                modifiers = flags
                stopRecording()
            }
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func symbolString(_ flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.function) { parts.append("fn") }
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        return parts.joined()
    }
}
```

Add a conflict-warning label if the chosen combo matches `.command` alone (Cmd shortcuts are intercepted by the system).

---

## Windows Design (C#)

### Data Model

Add to `MainViewModel` / settings JSON:

```csharp
// Stored as "hotKeyModifiers" (int, VK mask) and "hotKeyVKey" (int)
[ObservableProperty] private int _hotKeyVKey = Win32Interop.VK_SPACE;      // default Space
[ObservableProperty] private int _hotKeyModifiers = Win32Interop.MOD_CTRL; // default Ctrl

partial void OnHotKeyVKeyChanged(int value)     => SaveSetting("hotKeyVKey", value.ToString());
partial void OnHotKeyModifiersChanged(int value) => SaveSetting("hotKeyModifiers", value.ToString());
```

### HotKeyManager changes

Replace the hardcoded VK_SPACE + Ctrl check with configurable fields:

```csharp
public int TargetVKey { get; set; } = Win32Interop.VK_SPACE;
public int TargetModifiers { get; set; } = Win32Interop.VK_CONTROL;
```

Update `HookCallback` to compare against `TargetVKey` and `TargetModifiers`. On key-down, check all modifier states against `TargetModifiers` bitmask before firing.

### UI — Hotkey Recorder (WinUI 3)

Add a `HotKeyBox` UserControl to `SettingsPanel.xaml`:

```xml
<TextBox x:Name="HotKeyBox"
         IsReadOnly="True"
         PlaceholderText="Click to record hotkey"
         GotFocus="HotKeyBox_GotFocus"
         LostFocus="HotKeyBox_LostFocus"
         KeyDown="HotKeyBox_KeyDown" />
```

In code-behind, on `GotFocus` start intercepting `KeyDown` / `KeyUp`, build the combo string, write to `HotKeyBox.Text`, then on `LostFocus` commit the new values to the ViewModel:

```csharp
private void HotKeyBox_KeyDown(object sender, KeyRoutedEventArgs e)
{
    var modifiers = (int)Microsoft.UI.Input.InputKeyboardSource
        .GetKeyStateForCurrentThread(Windows.System.VirtualKey.Control);
    _vm.HotKeyVKey   = (int)e.Key;
    _vm.HotKeyModifiers = modifiers;
    HotKeyBox.Text   = FormatHotKey(_vm.HotKeyModifiers, _vm.HotKeyVKey);
    e.Handled = true;
}
```

---

## Conflict Detection (Both Platforms)

Maintain a static set of known problematic combos:

```
Mac: [.command], [.command, .shift]  — intercepted by menu bar
Win: Ctrl+C, Ctrl+V, Ctrl+Z, Ctrl+A — clipboard/undo shortcuts
```

Show an inline `Text` warning in orange if the user picks a conflicting combo. Do not block the choice — just inform.

---

## Persistence

| Platform | Storage key | Format |
|----------|------------|--------|
| Mac | `UserDefaults` `"hotKeyModifiers"` | `Int` (NSEvent.ModifierFlags rawValue) |
| Win | `settings.json` `"hotKeyVKey"`, `"hotKeyModifiers"` | `int` |

---

## Acceptance Criteria
- [ ] Default hotkey unchanged on fresh install.
- [ ] User can open Settings, click the hotkey recorder, press a new combo, and the new combo activates recording.
- [ ] Preference survives app restart.
- [ ] Conflict warning shown for known-bad combos.
- [ ] Reset-to-default button clears to original combo.

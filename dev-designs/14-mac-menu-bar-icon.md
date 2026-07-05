# Dev Design #14 — macOS Menu Bar Icon

## Problem
SimpleTranscribe for Mac has no menu bar icon. When the main window is closed or the app is in the background, the user has no quick way to trigger a transcription, check the model status, or access settings without clicking the Dock icon. The Windows version has a system tray icon with a full context menu (`TrayIconManager.cs`).

---

## Goals
- Add an `NSStatusItem` to the macOS menu bar.
- Menu bar icon reflects the current recording/transcribing state.
- Context menu provides: Open Window, Start/Stop Recording (hotkey shown), Launch at Login toggle, and Quit.
- Clicking the icon opens the main window (same as Dock click).
- Minimal extra complexity — hook into the existing `AppModel` state.

---

## Implementation

### 1. MenuBarManager.swift (new file)

```swift
import AppKit
import SwiftUI

@MainActor
final class MenuBarManager: ObservableObject {

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var stateObserver: (any Observation.ObservationRegistrar)?

    func setup(appModel: AppModel) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "waveform.circle",
                                     accessibilityDescription: "SimpleTranscribe")
        item.button?.action = #selector(statusItemClicked)
        item.button?.target = self
        statusItem = item

        buildMenu(appModel: appModel)
        observeState(appModel: appModel)
    }

    func teardown() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: - Icon state

    func updateIcon(isRecording: Bool, isTranscribing: Bool) {
        let name: String
        if isRecording {
            name = "waveform.circle.fill"   // filled = active recording
        } else if isTranscribing {
            name = "ellipsis.circle"        // processing
        } else {
            name = "waveform.circle"        // idle
        }
        statusItem?.button?.image = NSImage(systemSymbolName: name,
                                             accessibilityDescription: "SimpleTranscribe")
    }

    // MARK: - Menu

    private func buildMenu(appModel: AppModel) {
        let m = NSMenu()

        let openItem = NSMenuItem(title: "Open SimpleTranscribe",
                                  action: #selector(openMainWindow),
                                  keyEquivalent: "")
        openItem.target = self
        m.addItem(openItem)

        m.addItem(.separator())

        let recordItem = NSMenuItem(title: "Start Recording",
                                    action: #selector(toggleRecording),
                                    keyEquivalent: "")
        recordItem.target = self
        recordItem.tag = 10   // tag used to update title later
        m.addItem(recordItem)

        m.addItem(.separator())

        let loginItem = NSMenuItem(title: "Launch at Login",
                                   action: #selector(toggleLaunchAtLogin),
                                   keyEquivalent: "")
        loginItem.target = self
        loginItem.tag = 20
        m.addItem(loginItem)

        m.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit SimpleTranscribe",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        m.addItem(quitItem)

        statusItem?.menu = m
        menu = m
    }

    private func observeState(appModel: AppModel) {
        // Use withObservationTracking to react to AppModel changes
        // Runs on MainActor; re-registers after each change (standard Swift Observation pattern)
        func track() {
            withObservationTracking {
                let recording     = appModel.isRecording
                let transcribing  = appModel.isTranscribing
                let loginEnabled  = LaunchAtLoginManager.isEnabled

                updateIcon(isRecording: recording, isTranscribing: transcribing)
                updateMenuItems(isRecording: recording, loginEnabled: loginEnabled)
            } onChange: {
                Task { @MainActor in track() }
            }
        }
        track()
    }

    private func updateMenuItems(isRecording: Bool, loginEnabled: Bool) {
        if let recordItem = menu?.item(withTag: 10) {
            recordItem.title = isRecording ? "Stop Recording" : "Start Recording (fn⌃)"
        }
        if let loginItem = menu?.item(withTag: 20) {
            loginItem.state = loginEnabled ? .on : .off
        }
    }

    // MARK: - Actions

    @objc private func statusItemClicked() {
        openMainWindow()
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.isMainWindow || $0.title == "SimpleTranscribe" })?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleRecording() {
        // Post a notification that AppModel listens to (avoids direct coupling)
        NotificationCenter.default.post(name: .menuBarToggleRecording, object: nil)
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLoginManager.toggle()
        if let loginItem = menu?.item(withTag: 20) {
            loginItem.state = LaunchAtLoginManager.isEnabled ? .on : .off
        }
    }
}

extension Notification.Name {
    static let menuBarToggleRecording = Notification.Name("menuBarToggleRecording")
}
```

### 2. simpletranscribeApp.swift — initialise MenuBarManager

```swift
@main
struct simpletranscribeApp: App {
    @State private var appModel = AppModel()
    @StateObject private var menuBarManager = MenuBarManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .onAppear {
                    menuBarManager.setup(appModel: appModel)
                }
        }
        .commands {
            // existing commands …
        }
    }
}
```

### 3. AppModel — respond to menu bar toggle notification

```swift
// AppModel.init() or onAppear setup:
NotificationCenter.default.addObserver(forName: .menuBarToggleRecording,
                                        object: nil, queue: .main) { [weak self] _ in
    guard let self else { return }
    if self.isRecording {
        self.stopRecordingAndTranscribe()
    } else {
        self.startRecording()
    }
}
```

### 4. Icon Assets

Add three icon variants to `Assets.xcassets`:

| Symbol | State |
|--------|-------|
| `waveform.circle` | Idle (SF Symbol, template mode) |
| `waveform.circle.fill` | Recording (filled = active) |
| `ellipsis.circle` | Transcribing |

All icons should use template rendering (tint adapts to menu bar appearance, light/dark).

### 5. App Policy — keep app alive when window is closed

Currently closing the window terminates the app. With a menu bar icon the app should remain running:

```swift
// simpletranscribeApp.swift
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false   // Keep running when window is closed; user quits via menu bar
    }
}
```

Alternatively, add `LSUIElement = YES` to `Info.plist` if the app should have **no Dock icon** (pure menu bar app). This is a UX decision — default recommendation is **keep the Dock icon** (`LSUIElement` off) and just add the menu bar extra.

---

## Menu Bar Behaviour by State

| App State | Icon | "Recording" menu item |
|-----------|------|-----------------------|
| Idle, model loaded | `waveform.circle` | "Start Recording (fn⌃)" |
| Recording | `waveform.circle.fill` (animated tint: red) | "Stop Recording" |
| Transcribing | `ellipsis.circle` | "Stop Recording" (disabled) |
| No model loaded | `waveform.circle` | "Start Recording" (disabled) |
| Downloading model | `arrow.down.circle` | "Start Recording" (disabled) |

To achieve a red tint on the status button during recording:

```swift
statusItem?.button?.contentTintColor = isRecording ? .systemRed : nil
```

---

## Acceptance Criteria
- [ ] `NSStatusItem` appears in the menu bar when the app launches.
- [ ] Icon switches between idle / recording / transcribing states.
- [ ] Icon tint is red during recording.
- [ ] Clicking the icon opens/focuses the main window.
- [ ] "Start Recording" / "Stop Recording" menu item functions correctly and shows the hotkey.
- [ ] "Launch at Login" menu item reflects and toggles the `LaunchAtLoginManager` state.
- [ ] Closing the main window keeps the app running (menu bar icon remains).
- [ ] Quitting via the menu bar context menu terminates the app.
- [ ] Menu bar icon is removed cleanly on app termination.
- [ ] Icon renders correctly in both light and dark menu bar appearances.

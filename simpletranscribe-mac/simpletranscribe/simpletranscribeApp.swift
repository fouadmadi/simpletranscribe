//
//  simpletranscribeApp.swift
//  simpletranscribe
//
//  Created by user on 2/22/26.
//

import SwiftUI
import ApplicationServices
import ServiceManagement

@main
struct simpletranscribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some Scene {
        Window("SimpleTranscribe", id: "main") {
            ContentView()
                .environment(appDelegate.appModel)
        }
        .defaultSize(width: 700, height: 550)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About SimpleTranscribe") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "SimpleTranscribe",
                        .version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                    ])
                }
            }
        }

        MenuBarExtra {
            Button("Open SimpleTranscribe") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            Divider()
            Toggle("Start at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    launchAtLogin = LaunchAtLoginManager.setEnabled(newValue)
                }
            Divider()
            Button("Quit SimpleTranscribe") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: appDelegate.appModel.isRecording ? "record.circle" : "mic.fill")
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let appModel = AppModel()
    let hotKeyManager = HotKeyManager()
    let audioManager = AudioManager()
    let transcriptionManager = TranscriptionManager()
    let overlayWindow = FloatingOverlayWindow()

    private var overlayObservation: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock — show only in menu bar
        NSApplication.shared.setActivationPolicy(.accessory)
        // Yield focus back so we don't steal frontmost from the previous app
        NSApplication.shared.hide(nil)

        // Wire up service references
        appModel.audioManager = audioManager
        appModel.transcriptionManager = transcriptionManager

        // Core initialization (runs regardless of window state)
        appModel.setup()
        hotKeyManager.setup()
        appModel.setupAudio()
        appModel.requestAccessibilityPermission()

        // Auto-load model at startup
        if !appModel.selectedModelID.isEmpty,
           appModel.currentModel?.isAvailable == true {
            Task {
                await appModel.loadModelAsync()
            }
        }

        // Global hotkey handling (works even when window is closed)
        hotKeyManager.onHotKeyChanged = { [weak self] pressed in
            self?.appModel.handleHotKey(pressed: pressed)
        }

        // Refresh accessibility state when app becomes active
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.appModel.accessibilityGranted = AXIsProcessTrusted()
        }

        // Observe overlay state and drive the floating overlay window
        startOverlayObservation()
    }

    private func startOverlayObservation() {
        overlayObservation = withObservationTracking {
            _ = appModel.overlayState
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.handleOverlayStateChange()
                self?.startOverlayObservation()
            }
        }
    }

    private func handleOverlayStateChange() {
        switch appModel.overlayState {
        case .idle:
            overlayWindow.hide()
        case .recording, .transcribing:
            overlayWindow.show(state: appModel.overlayState)
        case .done:
            overlayWindow.showDone()
        case .error(let message):
            overlayWindow.showError(message)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

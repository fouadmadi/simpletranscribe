import SwiftUI
import ServiceManagement

@main
struct SimpleRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("SimpleRecorder", id: "main") {
            ContentView()
                .environment(appDelegate.appModel)
        }
        .defaultSize(width: 680, height: 520)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About SimpleRecorder") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "SimpleRecorder",
                        .version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                    ])
                }
            }
        }

        MenuBarExtra {
            Button(appDelegate.appModel.isRecording ? "Stop Recording" : "Open SimpleRecorder") {
                if appDelegate.appModel.isRecording {
                    appDelegate.appModel.toggleRecording()
                } else {
                    openWindow(id: "main")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }
            Divider()
            Button("Quit SimpleRecorder") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: appDelegate.appModel.isRecording ? "record.circle.fill" : "waveform.circle")
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let appModel = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApplication.shared.hide(nil)

        Task { @MainActor in
            await appModel.checkPermissions()
        }
        appModel.loadRecordings()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Refresh screen recording permission whenever the app comes to foreground
        appModel.refreshScreenRecordingPermission()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

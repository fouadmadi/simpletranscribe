import Cocoa
import Observation

@Observable
class HotKeyManager {
    private(set) var isHotKeyPressed = false

    /// Callback fired on the main thread whenever the hotkey state changes.
    var onHotKeyChanged: ((Bool) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastReportedState = false

    // The modifier combo we're looking for: fn + ctrl
    private let requiredFlags: NSEvent.ModifierFlags = [.function, .control]

    init() {
        // Monitoring is deferred to setup() so NSEvent monitors aren't
        // registered before the app's event loop is fully running.
    }

    /// Call after app activation to register event monitors
    func setup() {
        guard globalMonitor == nil else { return }
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        // Global monitor: fires when the app is NOT focused
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Local monitor: fires when the app IS focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    private func stopMonitoring() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let pressed = event.modifierFlags.contains(requiredFlags)

        // Skip if state hasn't changed (avoids unnecessary main-thread dispatches)
        guard pressed != lastReportedState else { return }
        lastReportedState = pressed

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isHotKeyPressed = pressed
            self.onHotKeyChanged?(pressed)
        }
    }
}

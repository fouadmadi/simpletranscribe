import Cocoa
import Observation

@Observable
class HotKeyManager {
    private(set) var isHotKeyPressed = false

    private var globalMonitor: Any?
    private var localMonitor: Any?

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
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let pressed = flags.contains(requiredFlags)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if pressed != self.isHotKeyPressed {
                self.isHotKeyPressed = pressed
            }
        }
    }
}

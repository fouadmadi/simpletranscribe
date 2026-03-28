import ServiceManagement
import os

enum LaunchAtLoginManager {
    private static let logger = Logger(subsystem: "com.simpletranscribe", category: "LaunchAtLogin")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Attempts to set the login item state. Returns the actual state after the operation.
    @discardableResult
    static func setEnabled(_ value: Bool) -> Bool {
        do {
            if value {
                try SMAppService.mainApp.register()
                logger.info("Registered login item")
            } else {
                try SMAppService.mainApp.unregister()
                logger.info("Unregistered login item")
            }
        } catch {
            logger.error("Failed to \(value ? "register" : "unregister") login item: \(error, privacy: .public)")
        }
        return isEnabled
    }

    static func toggle() {
        setEnabled(!isEnabled)
    }
}

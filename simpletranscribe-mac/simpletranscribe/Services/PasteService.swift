import AppKit
import ApplicationServices
import os

/// Handles paste-at-cursor via multiple strategies (CGEvent, AppleScript, osascript).
///
/// Under App Sandbox, the strategies have different requirements:
/// - **CGEvent**: Requires Accessibility permission (user must grant in System Settings).
/// - **AppleScript**: Requires `com.apple.security.automation.apple-events` entitlement.
/// - **osascript**: Will fail under strict sandbox (Process spawning is restricted).
///   Kept as a last-resort fallback for non-sandboxed development builds.
///
/// If all methods fail, text remains on the clipboard for manual ⌘V.
enum PasteService {
    private static let logger = Logger(subsystem: "com.simpletranscribe", category: "Paste")

    /// Copy text to pasteboard and attempt to paste it at the cursor.
    static func copyAndPaste(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didSet = pasteboard.setString(text, forType: .string)
        logger.debug("pasteboard set: \(didSet, privacy: .public), text length: \(text.count, privacy: .public)")

        if let frontApp = NSWorkspace.shared.frontmostApplication {
            logger.debug("frontmost app: \(frontApp.localizedName ?? "unknown", privacy: .public) (pid: \(frontApp.processIdentifier, privacy: .public))")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            logger.debug("attempting CGEvent paste...")
            if pasteWithCGEvent() {
                logger.debug("CGEvent paste succeeded")
                return
            }
            logger.debug("CGEvent failed, trying AppleScript...")
            if pasteWithAppleScript() {
                logger.debug("AppleScript paste succeeded")
                return
            }
            logger.debug("AppleScript failed, trying osascript process...")
            if pasteWithOsascript() {
                logger.debug("osascript paste succeeded")
                return
            }
            logger.error("ALL paste methods failed — text is on clipboard, user can ⌘V manually")
        }
    }

    /// Simulate ⌘V using CGEvent (Quartz Event Services).
    private static func pasteWithCGEvent() -> Bool {
        let hasPreflight = CGPreflightPostEventAccess()
        logger.debug("[CGEvent] preflight=\(hasPreflight, privacy: .public)")
        guard hasPreflight else { return false }

        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            logger.error("[CGEvent] failed to create key events")
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        logger.debug("[CGEvent] posted ⌘V via cgSessionEventTap")
        return true
    }

    /// Simulate ⌘V via AppleScript using System Events bundle identifier.
    @discardableResult
    private static func pasteWithAppleScript() -> Bool {
        let script = NSAppleScript(source: """
            tell application id "com.apple.systemevents"
                keystroke "v" using command down
            end tell
        """)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        if let error {
            logger.error("[AppleScript] FAILED: \(error, privacy: .public)")
            return false
        }
        logger.debug("[AppleScript] succeeded")
        return true
    }

    /// Simulate ⌘V by spawning osascript as a child process.
    private static func pasteWithOsascript() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", "tell application id \"com.apple.systemevents\" to keystroke \"v\" using command down"
        ]
        let pipe = Pipe()
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let status = process.terminationStatus
            if status != 0 {
                let stderr = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                logger.error("[osascript] exit \(status, privacy: .public): \(stderr, privacy: .public)")
            }
            return status == 0
        } catch {
            logger.error("[osascript] launch failed: \(error, privacy: .public)")
            return false
        }
    }
}

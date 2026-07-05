import Foundation
import os

/// Writes timestamped diagnostic entries to a persistent log file when enabled.
///
/// Toggle via **Settings → Diagnostic logging** or the UserDefaults key `"diagnosticLogging"`.
///
/// Log location (within the app sandbox):
/// `~/Library/Containers/mfeglobal.simpletranscribe/Data/Library/Logs/simpletranscribe/debug.log`
///
/// The file rotates automatically when it exceeds 2 MB, archiving the previous run as `debug.1.log`.
final class DiagnosticLogger {
    static let shared = DiagnosticLogger()

    private static let osLog = Logger(subsystem: "com.simpletranscribe", category: "Diagnostic")

    // Serial queue keeps all file I/O off the main thread and prevents data races.
    private let queue = DispatchQueue(label: "com.simpletranscribe.diagnosticLogger", qos: .utility)
    private var fileHandle: FileHandle?
    private let maxFileSize: UInt64 = 2 * 1024 * 1024  // 2 MB

    // Formatter is accessed only on `queue`, so no lock needed.
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    let logFileURL: URL

    private init() {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Logs/simpletranscribe", directoryHint: .isDirectory)
        logFileURL = logsDir.appending(path: "debug.log")

        queue.async { [self] in
            try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: self.logFileURL.path) {
                FileManager.default.createFile(atPath: self.logFileURL.path, contents: nil)
            }
            self.fileHandle = try? FileHandle(forWritingTo: self.logFileURL)
            self.fileHandle?.seekToEndOfFile()
        }
    }

    // MARK: - Public API

    func log(_ message: String, category: String = "App") {
        guard UserDefaults.standard.bool(forKey: "diagnosticLogging") else { return }
        // Mirror to os_log so Console.app also captures it.
        Self.osLog.debug("[\(category, privacy: .public)] \(message, privacy: .public)")
        queue.async { [self] in
            rotateIfNeeded()
            let timestamp = formatter.string(from: Date())
            let line = "[\(timestamp)] [\(category)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            fileHandle?.write(data)
        }
    }

    // MARK: - Private Helpers

    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let size = attrs[.size] as? UInt64,
              size > maxFileSize else { return }

        try? fileHandle?.close()
        let archiveURL = logFileURL.deletingLastPathComponent().appending(path: "debug.1.log")
        try? FileManager.default.removeItem(at: archiveURL)
        try? FileManager.default.moveItem(at: logFileURL, to: archiveURL)
        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
    }
}

import Foundation
import Observation
import os

@Observable
final class TranscriptHistory {
    private static let logger = Logger(subsystem: "com.simpletranscribe", category: "History")
    private static let maxFileSizeBytes: Int = 5 * 1024 * 1024  // 5 MB

    private(set) var entries: [TranscriptEntry] = []
    let maxEntries: Int
    private let storageURL: URL

    init(maxEntries: Int = 200) {
        self.maxEntries = maxEntries
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storageURL = support
            .appendingPathComponent("com.simpletranscribe")
            .appendingPathComponent("history.json")
        load()
    }

    func append(_ entry: TranscriptEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            entries = try JSONDecoder().decode([TranscriptEntry].self, from: data)
        } catch {
            Self.logger.error("Failed to load history: \(error, privacy: .public)")
        }
    }

    private func save() {
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            // Prune if over size limit
            if data.count > Self.maxFileSizeBytes, entries.count > 1 {
                entries = Array(entries.prefix(entries.count / 2))
                let pruned = try JSONEncoder().encode(entries)
                try pruned.write(to: storageURL, options: .atomic)
            } else {
                try data.write(to: storageURL, options: .atomic)
            }
        } catch {
            Self.logger.error("Failed to save history: \(error, privacy: .public)")
        }
    }
}

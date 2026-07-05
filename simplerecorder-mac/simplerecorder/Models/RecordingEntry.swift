import Foundation

enum RecordingSource: String, CaseIterable, Codable, Identifiable {
    case microphone = "Microphone"
    case systemAudio = "System Audio"
    case both = "Both"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .microphone: return "mic.fill"
        case .systemAudio: return "speaker.wave.3.fill"
        case .both: return "waveform"
        }
    }
}

struct RecordingEntry: Identifiable, Codable {
    let id: UUID
    let url: URL
    let date: Date
    let duration: TimeInterval
    let source: RecordingSource

    init(url: URL, date: Date, duration: TimeInterval, source: RecordingSource) {
        self.id = UUID()
        self.url = url
        self.date = date
        self.duration = duration
        self.source = source
    }

    var formattedDuration: String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%02d:%02d", m, s)
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    var formattedSize: String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var filename: String { url.lastPathComponent }
}

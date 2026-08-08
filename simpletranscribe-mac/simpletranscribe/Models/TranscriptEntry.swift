import Foundation

struct TranscriptEntry: Identifiable, Codable {
    let id: UUID
    let text: String
    let timestamp: Date
    let duration: TimeInterval  // seconds of audio recorded
    let modelID: String
    let language: String

    init(id: UUID = UUID(), text: String, timestamp: Date = Date(),
         duration: TimeInterval, modelID: String, language: String) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.duration = duration
        self.modelID = modelID
        self.language = language
    }

    var timestampRelative: String {
        let delta = Date().timeIntervalSince(timestamp)
        if delta < 60 { return "just now" }
        if delta < 3600 { return "\(Int(delta / 60))min ago" }
        if delta < 86400 { return "\(Int(delta / 3600))h ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: timestamp)
    }

    var durationLabel: String {
        "\(Int(duration))s"
    }
}

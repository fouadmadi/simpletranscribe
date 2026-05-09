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
}

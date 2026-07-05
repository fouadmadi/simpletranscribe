import Foundation
import SwiftLAME

enum MP3Encoder {
    static var saveDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("SimpleRecorder")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func outputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "recording_\(formatter.string(from: Date())).mp3"
        return saveDirectory.appendingPathComponent(name)
    }

    static func encode(sourceURL: URL, destinationURL: URL) async throws {
        let encoder = try SwiftLameEncoder(
            sourceUrl: sourceURL,
            configuration: LameConfiguration(
                sampleRate: .default,
                bitrateMode: .constant(192),
                quality: .nearBest
            ),
            destinationUrl: destinationURL
        )
        try await encoder.encode(priority: .userInitiated)
    }
}

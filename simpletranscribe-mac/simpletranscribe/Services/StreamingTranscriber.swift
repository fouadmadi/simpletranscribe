import Foundation
import SwiftWhisper
import os

/// An actor that performs chunked (streaming) Whisper inference on live audio.
/// Uses the same shared Whisper instance as the batch pass — synchronized via the actor's isolation.
actor StreamingTranscriber {
    private static let logger = Logger(subsystem: "com.simpletranscribe", category: "Streaming")

    private let chunkDuration: TimeInterval = 3.0
    private let sampleRate: Double = 16_000
    private var buffer: [Float] = []
    private var isRunning = false

    // Weak-ish reference — Whisper is a class; no reference semantics issue
    private weak var whisper: Whisper?

    func start(whisper: Whisper) {
        self.whisper = whisper
        buffer.removeAll(keepingCapacity: true)
        isRunning = true
    }

    func stop() {
        isRunning = false
        buffer.removeAll()
    }

    /// Feed audio samples; returns partial text when a full 3-second chunk is ready.
    func feed(samples: [Float]) async -> String? {
        guard isRunning, let w = whisper else { return nil }
        buffer.append(contentsOf: samples)

        let chunkSamples = Int(chunkDuration * sampleRate)
        guard buffer.count >= chunkSamples else { return nil }

        let chunk = Array(buffer.prefix(chunkSamples))
        buffer.removeFirst(chunkSamples)

        do {
            let segments = try await w.transcribe(audioFrames: chunk)
            let text = segments.map { $0.text.trimmingCharacters(in: .whitespaces) }
                               .filter { !$0.isEmpty }
                               .joined(separator: " ")
            return text.isEmpty ? nil : text
        } catch {
            Self.logger.debug("Streaming chunk failed: \(error, privacy: .public)")
            return nil
        }
    }
}

import SwiftUI
import Combine
import SwiftWhisper
import whisper_cpp

class TranscriptionManager: ObservableObject {
    var whisper: Whisper?
    
    @Published var isTranscribing = false
    
    // For streaming
    private var accumulatedAudio: [Float] = []
    private let audioLock = NSLock()
    
    private static let languageMap: [String: WhisperLanguage] = [
        "auto": .auto,
        "en": .english,
        "es": .spanish,
        "fr": .french,
        "de": .german,
        "zh": .chinese,
    ]
    
    init() {}
    
    func loadModel(modelPath: URL) async throws {
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw NSError(domain: "WhisperError", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Model file not found at \(modelPath.lastPathComponent)"])
        }
        
        // Free old model memory before loading new one
        await MainActor.run {
            self.whisper = nil
        }
        
        // Initialize SwiftWhisper on a background thread (heavy I/O + CoreML probe)
        let w = await Task.detached(priority: .userInitiated) {
            return Whisper(fromFileURL: modelPath)
        }.value
        
        await MainActor.run {
            self.whisper = w
            self.configureParams()
        }
    }
    
    /// Configure whisper params for optimal transcription speed
    private func configureParams() {
        guard let params = whisper?.params else { return }
        params.language = .english
        params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount))
        params.no_context = true
        params.greedy.best_of = 1
        params.single_segment = true
        params.print_progress = false
        params.print_timestamps = false
    }
    
    func startTranscription(language: String) {
        audioLock.lock()
        self.accumulatedAudio.removeAll(keepingCapacity: true)
        self.accumulatedAudio.reserveCapacity(1_920_000)  // 2 min at 16kHz
        audioLock.unlock()
        self.isTranscribing = true
        
        let whisperLanguage = Self.languageMap[language] ?? .english
        
        self.whisper?.params.language = whisperLanguage
    }
        
    func appendAudio(buffer: [Float]) {
        audioLock.lock()
        self.accumulatedAudio.append(contentsOf: buffer)
        audioLock.unlock()
    }
    
    /// Thread-safe snapshot of accumulated audio
    private func takeAudioSnapshot() -> [Float] {
        audioLock.lock()
        defer { audioLock.unlock() }
        return accumulatedAudio
    }
    
    /// Process the currently accumulated audio and return the full text.
    func processAudio(onPartialOutput: @escaping (String) -> Void) async throws -> String {
        // Ensure isTranscribing is always reset, regardless of early returns or errors
        defer {
            DispatchQueue.main.async {
                self.isTranscribing = false
            }
        }
        
        guard let whisper = whisper else {
            throw NSError(domain: "WhisperError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }
        
        let audioSnapshot = takeAudioSnapshot()
        
        guard !audioSnapshot.isEmpty else { return "" }
        
        // SwiftWhisper transcribe returns [Segment] synchronously or via delegate, but it also has async methods depending on version.
        // The most standard way in SwiftWhisper 1.0.0+ is to use the async `transcribe` function.
        let segments = try await whisper.transcribe(audioFrames: audioSnapshot)
        
        let text = segments.map { $0.text }.joined(separator: " ")
        
        return text
    }
}

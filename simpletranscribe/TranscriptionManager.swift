import SwiftUI
import Combine
import SwiftWhisper

class TranscriptionManager: ObservableObject {
    var whisper: Whisper?
    
    @Published var isTranscribing = false
    
    // For streaming
    private var accumulatedAudio: [Float] = []
    
    init() {}
    
    func loadModel(modelPath: URL) throws {
        // Initialize SwiftWhisper
        self.whisper = Whisper(fromFileURL: modelPath)
        // Optionally set default params here if needed
        self.whisper?.params.language = .english
    }
    
    func startTranscription(language: String) {
        self.accumulatedAudio.removeAll()
        self.isTranscribing = true
        
        // Update language
        var whisperLanguage: WhisperLanguage = .english
        if language == "auto" { whisperLanguage = .auto }
        else if language == "en" { whisperLanguage = .english }
        else if language == "es" { whisperLanguage = .spanish }
        else if language == "fr" { whisperLanguage = .french }
        else if language == "de" { whisperLanguage = .german }
        else if language == "zh" { whisperLanguage = .chinese }
        
        self.whisper?.params.language = whisperLanguage
    }
        
    func appendAudio(buffer: [Float]) {
        self.accumulatedAudio.append(contentsOf: buffer)
    }
    
    /// Process the currently accumulated audio and return the full text.
    func processAudio(onPartialOutput: @escaping (String) -> Void) async throws -> String {
        guard let whisper = whisper else {
            throw NSError(domain: "WhisperError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }
        
        guard !accumulatedAudio.isEmpty else { return "" }
        
        // SwiftWhisper transcribe returns [Segment] synchronously or via delegate, but it also has async methods depending on version.
        // The most standard way in SwiftWhisper 1.0.0+ is to use the async `transcribe` function.
        let segments = try await whisper.transcribe(audioFrames: accumulatedAudio)
        
        let text = segments.map { $0.text }.joined(separator: " ")
        
        DispatchQueue.main.async {
            self.isTranscribing = false
        }
        
        return text
    }
}

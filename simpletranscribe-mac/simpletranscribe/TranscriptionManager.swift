import SwiftUI
import Observation
import SwiftWhisper
import whisper_cpp

@Observable
class TranscriptionManager {
    var whisper: Whisper?
    
    var isTranscribing = false
    
    /// The compute backend currently in use for inference (e.g. "CoreML", "CPU").
    var activeComputeBackend: String = "CPU"
    
    // For streaming — ignored to avoid observation overhead on the audio thread
    @ObservationIgnored private var accumulatedAudio: [Float] = []
    private let audioLock = NSLock()
    
    // Track which engine type is loaded
    private var loadedModelType: ModelType = .whisper
    
    private static let languageMap: [String: WhisperLanguage] = [
        "auto": .auto,
        "en": .english,
        "zh": .chinese,
        "de": .german,
        "es": .spanish,
        "ru": .russian,
        "ko": .korean,
        "fr": .french,
        "ja": .japanese,
        "pt": .portuguese,
        "tr": .turkish,
        "pl": .polish,
        "nl": .dutch,
        "ar": .arabic,
        "it": .italian,
        "sv": .swedish,
        "hi": .hindi,
        "da": .danish,
        "fi": .finnish,
        "he": .hebrew,
        "uk": .ukrainian,
        "cs": .czech,
        "el": .greek,
        "hr": .croatian,
        "hu": .hungarian,
        "ro": .romanian,
        "sk": .slovak,
        "no": .norwegian,
        "bg": .bulgarian,
        "id": .indonesian,
        "ms": .malay,
        "th": .thai,
        "vi": .vietnamese,
        "ca": .catalan,
        "gl": .galician,
        "sl": .slovenian,
        "et": .estonian,
        "lv": .latvian,
        "lt": .lithuanian,
        "af": .afrikaans,
        "az": .azerbaijani,
        "be": .belarusian,
        "bn": .bengali,
        "bs": .bosnian,
        "cy": .welsh,
        "eu": .basque,
        "fa": .persian,
        "gu": .gujarati,
        "hy": .armenian,
        "is": .icelandic,
        "ka": .georgian,
        "kk": .kazakh,
        "km": .khmer,
        "kn": .kannada,
        "lo": .lao,
        "lb": .luxembourgish,
        "mk": .macedonian,
        "ml": .malayalam,
        "mn": .mongolian,
        "mr": .marathi,
        "mt": .maltese,
        "my": .myanmar,
        "ne": .nepali,
        "pa": .punjabi,
        "si": .sinhala,
        "sq": .albanian,
        "sr": .serbian,
        "su": .sundanese,
        "sw": .swahili,
        "ta": .tamil,
        "te": .telugu,
        "tg": .tajik,
        "tl": .tagalog,
        "tt": .tatar,
        "ur": .urdu,
        "uz": .uzbek,
        "yi": .yiddish,
        "yo": .yoruba,
        "jw": .javanese,
        "haw": .hawaiian,
        "mi": .maori,
        "ht": .haitian,
        "ha": .hausa,
        "sn": .shona,
    ]
    
    init() {}
    
    func loadModel(modelPath: URL, modelType: ModelType = .whisper) async throws {
        // Clean up the other backend before loading
        #if SHERPA_ONNX
        if modelType == .whisper {
            await MainActor.run { self.parakeetRecognizer = nil }
        } else {
            await MainActor.run { self.whisper = nil }
        }
        #endif
        
        switch modelType {
        case .whisper:
            try await loadWhisperModel(modelPath: modelPath)
        case .parakeet:
            try await loadParakeetModel(modelDirectory: modelPath)
        }
        
        // Set model type only after successful load
        loadedModelType = modelType
    }
    
    // MARK: - Whisper Backend
    
    private func loadWhisperModel(modelPath: URL) async throws {
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
    
    // MARK: - Parakeet Backend (ONNX Runtime)
    
    #if SHERPA_ONNX
    // sherpa-onnx offline recognizer for Parakeet models
    private var parakeetRecognizer: SherpaOnnxOfflineRecognizer?
    
    private func loadParakeetModel(modelDirectory: URL) async throws {
        // Verify directory exists and required files are present
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: modelDirectory.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw NSError(domain: "ParakeetError", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Parakeet model directory not found at \(modelDirectory.lastPathComponent)"])
        }
        
        let requiredFiles = ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"]
        for file in requiredFiles {
            let filePath = modelDirectory.appending(path: file)
            guard FileManager.default.fileExists(atPath: filePath.path) else {
                throw NSError(domain: "ParakeetError", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Missing required file: \(file)"])
            }
        }
        
        // Free Whisper model if one was loaded
        await MainActor.run {
            self.whisper = nil
        }
        
        let encoderPath = modelDirectory.appending(path: "encoder.int8.onnx").path
        let decoderPath = modelDirectory.appending(path: "decoder.int8.onnx").path
        let joinerPath = modelDirectory.appending(path: "joiner.int8.onnx").path
        let tokensPath = modelDirectory.appending(path: "tokens.txt").path
        let numThreads = max(1, ProcessInfo.processInfo.activeProcessorCount)
        
        let recognizer = await Task.detached(priority: .userInitiated) {
            // On Apple Silicon, prefer CoreML for faster ONNX inference; fall back to CPU
            #if arch(arm64)
            let providers = ["coreml", "cpu"]
            #else
            let providers = ["cpu"]
            #endif

            for provider in providers {
                let transducerConfig = sherpaOnnxOfflineTransducerModelConfig(
                    encoder: encoderPath,
                    decoder: decoderPath,
                    joiner: joinerPath
                )

                let modelConfig = sherpaOnnxOfflineModelConfig(
                    tokens: tokensPath,
                    transducer: transducerConfig,
                    numThreads: numThreads,
                    provider: provider
                )

                let featConfig = sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80)

                var config = sherpaOnnxOfflineRecognizerConfig(
                    featConfig: featConfig,
                    modelConfig: modelConfig
                )

                if let r = SherpaOnnxOfflineRecognizer(config: &config) {
                    return (recognizer: r, provider: provider)
                }
            }
            return nil as (recognizer: SherpaOnnxOfflineRecognizer, provider: String)?
        }.value

        await MainActor.run {
            self.parakeetRecognizer = recognizer?.recognizer
            self.activeComputeBackend = recognizer?.provider == "coreml" ? "CoreML" : "CPU"
        }
    }
    #else
    private func loadParakeetModel(modelDirectory: URL) async throws {
        throw NSError(domain: "ParakeetError", code: 99,
                      userInfo: [NSLocalizedDescriptionKey: "Parakeet support requires sherpa-onnx. Add -DSHERPA_ONNX to Swift flags after installing the xcframeworks."])
    }
    #endif
    
    /// Configure whisper params for optimal transcription speed.
    /// Language is NOT set here — it is applied per-recording in startTranscription().
    private func configureParams() {
        guard let params = whisper?.params else { return }
        params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount))
        params.no_context = true
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
        
        // Language setting only applies to Whisper models
        if loadedModelType == .whisper {
            let whisperLanguage = Self.languageMap[language] ?? .english
            self.whisper?.params.language = whisperLanguage
        }
    }
        
    private static let maxSamples = 30 * 60 * 16_000  // 30 minutes at 16kHz

    func appendAudio(buffer: [Float]) {
        audioLock.lock()
        let remaining = Self.maxSamples - accumulatedAudio.count
        if remaining > 0 {
            let samplesToAdd = min(buffer.count, remaining)
            accumulatedAudio.append(contentsOf: buffer.prefix(samplesToAdd))
        }
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
        
        let audioSnapshot = takeAudioSnapshot()
        guard !audioSnapshot.isEmpty else { return "" }
        
        switch loadedModelType {
        case .whisper:
            guard let whisper = whisper else {
                throw NSError(domain: "WhisperError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Whisper model not loaded"])
            }
            let segments = try await whisper.transcribe(audioFrames: audioSnapshot)
            return segments.map { $0.text }.joined(separator: " ")
            
        case .parakeet:
            #if SHERPA_ONNX
            guard let recognizer = parakeetRecognizer else {
                throw NSError(domain: "ParakeetError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Parakeet model not loaded"])
            }
            let result = await Task.detached(priority: .userInitiated) {
                recognizer.decode(samples: audioSnapshot, sampleRate: 16_000)
            }.value
            return result.text
            #else
            throw NSError(domain: "ParakeetError", code: 99, userInfo: [NSLocalizedDescriptionKey: "Parakeet support not compiled. Add -DSHERPA_ONNX to Swift flags."])
            #endif
        }
    }
}

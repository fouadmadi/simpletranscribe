import Foundation

/// Hardcoded registry of known Whisper models
struct KnownModels {
    static let all: [ModelInfo] = [
        ModelInfo(
            id: "ggml-tiny.en",
            name: "Tiny (English)",
            description: "256 MB • Fastest • Lower accuracy",
            size: 140_000_000, // ~140 MB
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin")!,
            language: "en"
        ),
        ModelInfo(
            id: "ggml-base.en",
            name: "Base (English)",
            description: "514 MB • Fast • Balanced accuracy",
            size: 140_000_000, // ~140 MB
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!,
            language: "en"
        ),
        ModelInfo(
            id: "ggml-small.en",
            name: "Small (English)",
            description: "769 MB • Moderate speed • Good accuracy",
            size: 461_000_000, // ~461 MB
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!,
            language: "en"
        ),
        ModelInfo(
            id: "ggml-medium.en",
            name: "Medium (English)",
            description: "1.5 GB • Slow • High accuracy",
            size: 1_460_000_000, // ~1.5 GB
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin")!,
            language: "en"
        ),
        ModelInfo(
            id: "ggml-large",
            name: "Large (Multilingual)",
            description: "2.9 GB • Very slow • Highest accuracy",
            size: 2_900_000_000, // ~2.9 GB
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!,
            language: "multilingual"
        ),
    ]
    
    /// Get a model by its ID
    static func model(withID id: String) -> ModelInfo? {
        all.first { $0.id == id }
    }
}

import Foundation

/// Hardcoded registry of known Whisper models
struct KnownModels {
    static let all: [ModelInfo] = [
        ModelInfo(
            id: "ggml-tiny.en",
            name: "Tiny (English)",
            description: "Fastest • Lower accuracy",
            size: 77_700_000, // ~78 MB
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin")!,
            language: "en"
        ),
        ModelInfo(
            id: "ggml-base.en",
            name: "Base (English)",
            description: "Fast • Balanced accuracy",
            size: 147_500_000, // ~148 MB
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!,
            language: "en"
        ),
        ModelInfo(
            id: "ggml-small.en",
            name: "Small (English)",
            description: "Moderate speed • Good accuracy",
            size: 488_000_000, // ~488 MB
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!,
            language: "en"
        ),
        ModelInfo(
            id: "ggml-medium.en",
            name: "Medium (English)",
            description: "Slow • High accuracy",
            size: 1_533_000_000, // ~1.5 GB
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin")!,
            language: "en"
        ),
        ModelInfo(
            id: "ggml-large",
            name: "Large (Multilingual)",
            description: "Very slow • Highest accuracy",
            size: 3_095_000_000, // ~3.1 GB
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!,
            language: "multilingual"
        ),
    ]
    
    /// Get a model by its ID
    static func model(withID id: String) -> ModelInfo? {
        all.first { $0.id == id }
    }
}

import Foundation

/// Hardcoded registry of known Whisper models
struct KnownModels {
    static let all: [ModelInfo] = [
        ModelInfo(
            id: "ggml-tiny.en",
            name: "Tiny (English)",
            description: "Fastest • Lower accuracy",
            size: 77_704_715,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin")!,
            language: "en",
            sha256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f"
        ),
        ModelInfo(
            id: "ggml-base.en",
            name: "Base (English)",
            description: "Fast • Balanced accuracy",
            size: 147_964_211,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin")!,
            language: "en",
            sha256: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"
        ),
        ModelInfo(
            id: "ggml-small.en",
            name: "Small (English)",
            description: "Moderate speed • Good accuracy",
            size: 487_614_201,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")!,
            language: "en",
            sha256: "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d"
        ),
        ModelInfo(
            id: "ggml-medium.en",
            name: "Medium (English)",
            description: "Slow • High accuracy",
            size: 1_533_774_781,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin")!,
            language: "en",
            sha256: "cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356"
        ),
        ModelInfo(
            id: "ggml-large",
            name: "Large (Multilingual)",
            description: "Very slow • Highest accuracy",
            size: 3_095_033_483,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!,
            language: "multilingual",
            sha256: "64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2"
        ),
    ]
    
    /// Get a model by its ID
    static func model(withID id: String) -> ModelInfo? {
        all.first { $0.id == id }
    }
}

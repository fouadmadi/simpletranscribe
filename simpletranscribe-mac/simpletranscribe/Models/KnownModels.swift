import Foundation

/// Hardcoded registry of known speech-to-text models
struct KnownModels {

    // MARK: - URL bases

    private static let parakeetV2HFBase = "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/main/"
    private static let parakeetV3HFBase = "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/main/"
    private static let whisperHFBase    = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"

    // MARK: - Registry

    /// All models available in this build.
    /// Parakeet models are only included when compiled with -DSHERPA_ONNX.
    /// Without the sherpa-onnx xcframeworks they cannot be loaded, so showing
    /// them in the download list would only confuse users.
    static let all: [ModelInfo] = {
        var models: [ModelInfo] = []

        // Parakeet ONNX models — require -DSHERPA_ONNX and the xcframeworks.
        #if SHERPA_ONNX
        models += [
            ModelInfo(
                id: "parakeet-tdt-0.6b-v2",
                name: "Parakeet V2 (English)",
                description: "Fast • High accuracy • English only",
                size: 661_190_513,
                downloadURL: URL(string: parakeetV2HFBase + "encoder.int8.onnx")!,
                language: "en",
                sha256: nil,
                modelType: .parakeet,
                isDirectory: true,
                files: [
                    ModelFile(filename: "encoder.int8.onnx",
                              downloadURL: URL(string: parakeetV2HFBase + "encoder.int8.onnx")!,
                              size: 652_184_296,
                              sha256: "a32b12d17bbbc309d0686fbbcc2987b5e9b8333a7da83fa6b089f0a2acd651ab"),
                    ModelFile(filename: "decoder.int8.onnx",
                              downloadURL: URL(string: parakeetV2HFBase + "decoder.int8.onnx")!,
                              size: 7_257_753,
                              sha256: "b6bb64963457237b900e496ee9994b59294526439fbcc1fecf705b31a15c6b4e"),
                    ModelFile(filename: "joiner.int8.onnx",
                              downloadURL: URL(string: parakeetV2HFBase + "joiner.int8.onnx")!,
                              size: 1_739_080,
                              sha256: "7946164367946e7f9f29a122407c3252b680dbae9a51343eb2488d057c3c43d2"),
                    ModelFile(filename: "tokens.txt",
                              downloadURL: URL(string: parakeetV2HFBase + "tokens.txt")!,
                              size: 9_384,
                              sha256: nil),
                ]
            ),
            ModelInfo(
                id: "parakeet-tdt-0.6b-v3",
                name: "Parakeet V3 (Multilingual)",
                description: "Fast • High accuracy • 27 languages",
                size: 670_478_772,
                downloadURL: URL(string: parakeetV3HFBase + "encoder.int8.onnx")!,
                language: "multilingual",
                sha256: nil,
                modelType: .parakeet,
                isDirectory: true,
                files: [
                    ModelFile(filename: "encoder.int8.onnx",
                              downloadURL: URL(string: parakeetV3HFBase + "encoder.int8.onnx")!,
                              size: 652_184_281,
                              sha256: "acfc2b4456377e15d04f0243af540b7fe7c992f8d898d751cf134c3a55fd2247"),
                    ModelFile(filename: "decoder.int8.onnx",
                              downloadURL: URL(string: parakeetV3HFBase + "decoder.int8.onnx")!,
                              size: 11_845_275,
                              sha256: "179e50c43d1a9de79c8a24149a2f9bac6eb5981823f2a2ed88d655b24248db4e"),
                    ModelFile(filename: "joiner.int8.onnx",
                              downloadURL: URL(string: parakeetV3HFBase + "joiner.int8.onnx")!,
                              size: 6_355_277,
                              sha256: "3164c13fc2821009440d20fcb5fdc78bff28b4db2f8d0f0b329101719c0948b3"),
                    ModelFile(filename: "tokens.txt",
                              downloadURL: URL(string: parakeetV3HFBase + "tokens.txt")!,
                              size: 93_939,
                              sha256: nil),
                ]
            ),
        ]
        #endif

        // Whisper models — always available.
        models += [
            ModelInfo(
                id: "ggml-tiny.en",
                name: "Tiny (English)",
                description: "Fastest • Lower accuracy",
                size: 77_704_715,
                downloadURL: URL(string: whisperHFBase + "ggml-tiny.en.bin")!,
                language: "en",
                sha256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f",
                coreMlEncoderZipURL: URL(string: whisperHFBase + "ggml-tiny.en-encoder.mlmodelc.zip")
            ),
            ModelInfo(
                id: "ggml-base.en",
                name: "Base (English)",
                description: "Fast • Balanced accuracy",
                size: 147_964_211,
                downloadURL: URL(string: whisperHFBase + "ggml-base.en.bin")!,
                language: "en",
                sha256: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002",
                coreMlEncoderZipURL: URL(string: whisperHFBase + "ggml-base.en-encoder.mlmodelc.zip")
            ),
            ModelInfo(
                id: "ggml-small.en",
                name: "Small (English)",
                description: "Moderate speed • Good accuracy",
                size: 487_614_201,
                downloadURL: URL(string: whisperHFBase + "ggml-small.en.bin")!,
                language: "en",
                sha256: "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d",
                coreMlEncoderZipURL: URL(string: whisperHFBase + "ggml-small.en-encoder.mlmodelc.zip")
            ),
            ModelInfo(
                id: "ggml-medium.en",
                name: "Medium (English)",
                description: "Slow • High accuracy",
                size: 1_533_774_781,
                downloadURL: URL(string: whisperHFBase + "ggml-medium.en.bin")!,
                language: "en",
                sha256: "cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356",
                coreMlEncoderZipURL: URL(string: whisperHFBase + "ggml-medium.en-encoder.mlmodelc.zip")
            ),
            ModelInfo(
                id: "ggml-large",
                name: "Large (Multilingual)",
                description: "Very slow • Highest accuracy",
                size: 3_095_033_483,
                downloadURL: URL(string: whisperHFBase + "ggml-large-v3.bin")!,
                language: "multilingual",
                sha256: "64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2"
            ),
        ]

        return models
    }()

    /// Get a model by its ID
    static func model(withID id: String) -> ModelInfo? {
        all.first { $0.id == id }
    }
}

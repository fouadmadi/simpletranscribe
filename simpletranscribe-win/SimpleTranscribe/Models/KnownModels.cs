namespace SimpleTranscribe.Models;

/// <summary>
/// Hardcoded registry of known speech-to-text models.
/// Mirrors the macOS KnownModels.swift — same model IDs, URLs, sizes, and SHA256 hashes.
/// </summary>
public static class KnownModels
{
    private const string ParakeetV2HFBase = "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/main/";
    private const string ParakeetV3HFBase = "https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/main/";

    public static readonly IReadOnlyList<ModelInfo> All = new List<ModelInfo>
    {
        // Parakeet TDT 0.6B v2 (INT8) — English only, fast and accurate
        new()
        {
            Id = "parakeet-tdt-0.6b-v2",
            Name = "Parakeet V2 (English)",
            Description = "Fast • High accuracy • English only",
            Size = 661_190_513,
            DownloadUrl = new Uri(ParakeetV2HFBase + "encoder.int8.onnx"),
            Language = "en",
            ModelType = ModelType.Parakeet,
            IsDirectory = true,
            Files = new List<ModelFile>
            {
                new() { Filename = "encoder.int8.onnx", DownloadUrl = new Uri(ParakeetV2HFBase + "encoder.int8.onnx"), Size = 652_184_296, Sha256 = "a32b12d17bbbc309d0686fbbcc2987b5e9b8333a7da83fa6b089f0a2acd651ab" },
                new() { Filename = "decoder.int8.onnx", DownloadUrl = new Uri(ParakeetV2HFBase + "decoder.int8.onnx"), Size = 7_257_753, Sha256 = "b6bb64963457237b900e496ee9994b59294526439fbcc1fecf705b31a15c6b4e" },
                new() { Filename = "joiner.int8.onnx", DownloadUrl = new Uri(ParakeetV2HFBase + "joiner.int8.onnx"), Size = 1_739_080, Sha256 = "7946164367946e7f9f29a122407c3252b680dbae9a51343eb2488d057c3c43d2" },
                new() { Filename = "tokens.txt", DownloadUrl = new Uri(ParakeetV2HFBase + "tokens.txt"), Size = 9_384 },
            }
        },
        // Parakeet TDT 0.6B v3 (INT8) — Multilingual (25 EU languages + RU/UK)
        new()
        {
            Id = "parakeet-tdt-0.6b-v3",
            Name = "Parakeet V3 (Multilingual)",
            Description = "Fast • High accuracy • 27 languages",
            Size = 670_478_772,
            DownloadUrl = new Uri(ParakeetV3HFBase + "encoder.int8.onnx"),
            Language = "multilingual",
            ModelType = ModelType.Parakeet,
            IsDirectory = true,
            Files = new List<ModelFile>
            {
                new() { Filename = "encoder.int8.onnx", DownloadUrl = new Uri(ParakeetV3HFBase + "encoder.int8.onnx"), Size = 652_184_281, Sha256 = "acfc2b4456377e15d04f0243af540b7fe7c992f8d898d751cf134c3a55fd2247" },
                new() { Filename = "decoder.int8.onnx", DownloadUrl = new Uri(ParakeetV3HFBase + "decoder.int8.onnx"), Size = 11_845_275, Sha256 = "179e50c43d1a9de79c8a24149a2f9bac6eb5981823f2a2ed88d655b24248db4e" },
                new() { Filename = "joiner.int8.onnx", DownloadUrl = new Uri(ParakeetV3HFBase + "joiner.int8.onnx"), Size = 6_355_277, Sha256 = "3164c13fc2821009440d20fcb5fdc78bff28b4db2f8d0f0b329101719c0948b3" },
                new() { Filename = "tokens.txt", DownloadUrl = new Uri(ParakeetV3HFBase + "tokens.txt"), Size = 93_939 },
            }
        },
        // Whisper models
        new()
        {
            Id = "ggml-tiny.en",
            Name = "Tiny (English)",
            Description = "Fastest • Lower accuracy",
            Size = 77_704_715,
            DownloadUrl = new Uri("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin"),
            Language = "en",
            Sha256 = "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f"
        },
        new()
        {
            Id = "ggml-base.en",
            Name = "Base (English)",
            Description = "Fast • Balanced accuracy",
            Size = 147_964_211,
            DownloadUrl = new Uri("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"),
            Language = "en",
            Sha256 = "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"
        },
        new()
        {
            Id = "ggml-small.en",
            Name = "Small (English)",
            Description = "Moderate speed • Good accuracy",
            Size = 487_614_201,
            DownloadUrl = new Uri("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"),
            Language = "en",
            Sha256 = "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d"
        },
        new()
        {
            Id = "ggml-medium.en",
            Name = "Medium (English)",
            Description = "Slow • High accuracy",
            Size = 1_533_774_781,
            DownloadUrl = new Uri("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin"),
            Language = "en",
            Sha256 = "cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356"
        },
        new()
        {
            Id = "ggml-large",
            Name = "Large (Multilingual)",
            Description = "Very slow • Highest accuracy",
            Size = 3_095_033_483,
            DownloadUrl = new Uri("https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"),
            Language = "multilingual",
            Sha256 = "64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2"
        },
    };

    /// <summary>
    /// Get a model by its ID.
    /// </summary>
    public static ModelInfo? Get(string id) => All.FirstOrDefault(m => m.Id == id);
}

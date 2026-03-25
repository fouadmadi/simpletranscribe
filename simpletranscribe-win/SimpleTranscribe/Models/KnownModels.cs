namespace SimpleTranscribe.Models;

/// <summary>
/// Hardcoded registry of known Whisper models.
/// Mirrors the macOS KnownModels.swift — same model IDs, URLs, sizes, and SHA256 hashes.
/// </summary>
public static class KnownModels
{
    public static readonly IReadOnlyList<ModelInfo> All = new List<ModelInfo>
    {
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

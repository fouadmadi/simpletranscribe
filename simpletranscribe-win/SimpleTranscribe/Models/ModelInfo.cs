namespace SimpleTranscribe.Models;

/// <summary>
/// Represents metadata and status of a Whisper model.
/// Mirrors the macOS ModelInfo.swift struct.
/// </summary>
public class ModelInfo
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    public string Description { get; init; } = "";
    public long Size { get; init; }
    public Uri DownloadUrl { get; init; } = null!;
    public string Language { get; init; } = "en";
    public string? Sha256 { get; init; }

    // Local state
    public ModelStatus Status { get; set; } = ModelStatus.NotDownloaded;
    public string? DownloadedPath { get; set; }
    public double DownloadProgress { get; set; }

    /// <summary>
    /// Human-readable file size (e.g., "77.7 MB", "2.9 GB").
    /// </summary>
    public string FormattedSize => FormatBytes(Size);

    /// <summary>
    /// Whether this model is available for use.
    /// </summary>
    public bool IsAvailable => Status == ModelStatus.Downloaded && DownloadedPath != null;

    public static string FormatBytes(long bytes)
    {
        if (bytes >= 1_073_741_824)
            return $"{bytes / 1_073_741_824.0:F1} GB";
        if (bytes >= 1_048_576)
            return $"{bytes / 1_048_576.0:F1} MB";
        if (bytes >= 1024)
            return $"{bytes / 1024.0:F1} KB";
        return $"{bytes} B";
    }
}

public enum ModelStatus
{
    NotDownloaded,
    Downloading,
    Downloaded,
    Failed
}

using System.Security.Cryptography;
using SimpleTranscribe.Models;

namespace SimpleTranscribe.Services;

/// <summary>
/// Manages model downloads, discovery, and lifecycle.
/// Port of macOS ModelService.swift.
/// </summary>
public class ModelService
{
    private static readonly AppLogger Log = AppLogger.Instance;

    private readonly string _modelsDirectory;
    private readonly HttpClient _httpClient;
    private readonly Dictionary<string, CancellationTokenSource> _activeCancellations = new();
    private readonly Dictionary<string, DownloadProgress> _downloadProgressByModel = new();
    private readonly Dictionary<string, List<SpeedSample>> _speedSamples = new();
    private const double SpeedWindowSeconds = 5.0;

    public List<ModelInfo> AvailableModels { get; private set; } = new();
    public event Action? ModelsChanged;

    private record SpeedSample(DateTime Timestamp, long Bytes);

    public ModelService()
    {
        _modelsDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "SimpleTranscribe", "models");
        Directory.CreateDirectory(_modelsDirectory);

        _httpClient = new HttpClient();
        _httpClient.Timeout = TimeSpan.FromHours(1);

        LoadAvailableModels();
    }

    /// <summary>
    /// Load and initialize available models, checking which are already downloaded.
    /// </summary>
    public void LoadAvailableModels()
    {
        var models = KnownModels.All.Select(m => new ModelInfo
        {
            Id = m.Id,
            Name = m.Name,
            Description = m.Description,
            Size = m.Size,
            DownloadUrl = m.DownloadUrl,
            Language = m.Language,
            Sha256 = m.Sha256,
            ModelType = m.ModelType,
            IsDirectory = m.IsDirectory,
            Files = m.Files
        }).ToList();

        // Check which models are already downloaded
        foreach (var model in models)
        {
            if (model.IsDirectory)
            {
                // Directory-based models (Parakeet): check that directory and all files exist
                var modelDir = Path.Combine(_modelsDirectory, model.Id);
                if (IsDirectoryModelComplete(modelDir, model.Files))
                {
                    model.Status = ModelStatus.Downloaded;
                    model.DownloadedPath = modelDir;
                }
            }
            else
            {
                var modelPath = Path.Combine(_modelsDirectory, model.Id + ".bin");
                if (File.Exists(modelPath))
                {
                    model.Status = ModelStatus.Downloaded;
                    model.DownloadedPath = modelPath;
                }
            }
        }

        // Discover custom .bin files
        try
        {
            foreach (var file in Directory.GetFiles(_modelsDirectory, "*.bin"))
            {
                var modelId = Path.GetFileNameWithoutExtension(file);
                if (models.Any(m => m.Id == modelId))
                    continue;

                if (!IsValidGgmlFile(file))
                    continue;

                models.Add(new ModelInfo
                {
                    Id = modelId,
                    Name = modelId,
                    Description = "Custom model",
                    Size = new FileInfo(file).Length,
                    DownloadUrl = new Uri("about:blank"),
                    Language = "unknown",
                    Sha256 = null,
                    Status = ModelStatus.Downloaded,
                    DownloadedPath = file
                });
            }
        }
        catch { /* Ignore discovery errors */ }

        AvailableModels = models;
        ModelsChanged?.Invoke();
    }

    /// <summary>
    /// Check if all files in a directory-based model are present.
    /// </summary>
    private static bool IsDirectoryModelComplete(string dir, List<ModelFile> files)
    {
        if (files.Count == 0) return false;
        if (!Directory.Exists(dir)) return false;
        return files.All(f => File.Exists(Path.Combine(dir, f.Filename)));
    }

    /// <summary>
    /// Download a model by ID with progress reporting.
    /// </summary>
    public async Task DownloadModelAsync(string modelId, IProgress<DownloadProgress>? progress = null, CancellationToken externalToken = default)
    {
        var model = GetModel(modelId)
            ?? throw new InvalidOperationException("Model not found in registry");

        if (model.Status == ModelStatus.Downloaded)
            return;

        var cts = CancellationTokenSource.CreateLinkedTokenSource(externalToken);
        _activeCancellations[modelId] = cts;

        try
        {
            model.Status = ModelStatus.Downloading;
            model.DownloadProgress = 0;
            ResetProgressTracking(model.Id, model.Size);
            ModelsChanged?.Invoke();
            Log.Info("ModelService", $"Starting download: {modelId}");

            if (model.IsDirectory && model.Files.Count > 0)
            {
                await DownloadDirectoryModelAsync(model, progress, cts.Token);
            }
            else
            {
                await DownloadSingleFileModelAsync(model, progress, cts.Token);
            }

            Log.Info("ModelService", $"Download complete: {modelId}");
        }
        catch (OperationCanceledException)
        {
            model.Status = ModelStatus.NotDownloaded;
            model.DownloadProgress = 0;
            ClearProgressTracking(model.Id);
            CleanupDownload(model);
            Log.Info("ModelService", $"Download cancelled: {modelId}");
        }
        catch (Exception ex)
        {
            model.Status = ModelStatus.Failed;
            model.DownloadProgress = 0;
            ClearProgressTracking(model.Id);
            CleanupDownload(model);
            Log.Error("ModelService", $"Download failed: {modelId}", ex);
            throw new ModelDownloadException($"Download failed: {ex.Message}", ex);
        }
        finally
        {
            if (_activeCancellations.Remove(modelId, out var removedCts))
                removedCts.Dispose();
            ModelsChanged?.Invoke();
        }
    }

    /// <summary>
    /// Download a single-file model (e.g., Whisper .bin).
    /// </summary>
    private async Task DownloadSingleFileModelAsync(ModelInfo model, IProgress<DownloadProgress>? progress, CancellationToken ct)
    {
        var destPath = Path.Combine(_modelsDirectory, model.Id + ".bin");
        var tempPath = destPath + ".tmp";

        using var response = await _httpClient.GetAsync(
            model.DownloadUrl,
            HttpCompletionOption.ResponseHeadersRead,
            ct);
        response.EnsureSuccessStatusCode();

        var totalBytes = response.Content.Headers.ContentLength ?? 0L;

        await using var contentStream = await response.Content.ReadAsStreamAsync(ct);
        await using var fileStream = new FileStream(tempPath, FileMode.Create, FileAccess.Write, FileShare.None, 81920, true);

        var buffer = new byte[81920];
        long bytesRead = 0;
        int read;
        var lastProgressReport = DateTime.MinValue;

        while ((read = await contentStream.ReadAsync(buffer.AsMemory(0, buffer.Length), ct)) > 0)
        {
            await fileStream.WriteAsync(buffer.AsMemory(0, read), ct);
            bytesRead += read;

            var now = DateTime.UtcNow;
            if ((now - lastProgressReport).TotalSeconds >= 1.0)
            {
                lastProgressReport = now;
                ReportProgress(model, bytesRead, totalBytes, progress, now);
            }
        }

        await fileStream.FlushAsync(ct);
        fileStream.Close();

        // Verify SHA256 hash
        await VerifyFileIntegrityAsync(tempPath, model.Sha256);

        // Move temp file to final location
        if (File.Exists(destPath))
            File.Delete(destPath);
        File.Move(tempPath, destPath);

        model.Status = ModelStatus.Downloaded;
        model.DownloadedPath = destPath;
        ReportProgress(model, totalBytes > 0 ? totalBytes : bytesRead, totalBytes > 0 ? totalBytes : bytesRead, progress, DateTime.UtcNow);
    }

    /// <summary>
    /// Download a directory-based model (e.g., Parakeet ONNX with multiple files).
    /// </summary>
    private async Task DownloadDirectoryModelAsync(ModelInfo model, IProgress<DownloadProgress>? progress, CancellationToken ct)
    {
        var finalDir = Path.Combine(_modelsDirectory, model.Id);
        var tempDir = Path.Combine(_modelsDirectory, model.Id + ".downloading");

        if (Directory.Exists(tempDir))
            Directory.Delete(tempDir, true);
        Directory.CreateDirectory(tempDir);

        var totalSize = model.Files.Sum(f => f.Size);
        long downloadedBytes = 0;
        var lastProgressReport = DateTime.MinValue;

        foreach (var file in model.Files)
        {
            var destPath = Path.Combine(tempDir, file.Filename);

            using var response = await _httpClient.GetAsync(
                file.DownloadUrl,
                HttpCompletionOption.ResponseHeadersRead,
                ct);
            response.EnsureSuccessStatusCode();

            await using var contentStream = await response.Content.ReadAsStreamAsync(ct);
            await using var fileStream = new FileStream(destPath, FileMode.Create, FileAccess.Write, FileShare.None, 81920, true);

            var buffer = new byte[81920];
            int read;

            while ((read = await contentStream.ReadAsync(buffer.AsMemory(0, buffer.Length), ct)) > 0)
            {
                await fileStream.WriteAsync(buffer.AsMemory(0, read), ct);
                downloadedBytes += read;

                var now = DateTime.UtcNow;
                if ((now - lastProgressReport).TotalSeconds >= 1.0)
                {
                    lastProgressReport = now;
                    ReportProgress(model, downloadedBytes, totalSize, progress, now);
                }
            }

            await fileStream.FlushAsync(ct);
            fileStream.Close();

            await VerifyFileIntegrityAsync(destPath, file.Sha256);
        }

        if (Directory.Exists(finalDir))
            Directory.Delete(finalDir, true);
        Directory.Move(tempDir, finalDir);

        model.Status = ModelStatus.Downloaded;
        model.DownloadedPath = finalDir;
        ReportProgress(model, totalSize, totalSize, progress, DateTime.UtcNow);
    }

    /// <summary>
    /// Cancel an ongoing download.
    /// </summary>
    public void CancelDownload(string modelId)
    {
        if (_activeCancellations.TryGetValue(modelId, out var cts))
        {
            cts.Cancel();
        }
    }

    /// <summary>
    /// Delete a downloaded model.
    /// </summary>
    public void DeleteModel(string modelId)
    {
        var model = GetModel(modelId)
            ?? throw new InvalidOperationException("Model not found");

        if (model.DownloadedPath != null)
        {
            if (model.IsDirectory && Directory.Exists(model.DownloadedPath))
                Directory.Delete(model.DownloadedPath, true);
            else if (File.Exists(model.DownloadedPath))
                File.Delete(model.DownloadedPath);
        }

        // Also clean up temp download directory
        var tempDir = Path.Combine(_modelsDirectory, modelId + ".downloading");
        if (Directory.Exists(tempDir))
            try { Directory.Delete(tempDir, true); } catch { }

        model.Status = ModelStatus.NotDownloaded;
        model.DownloadedPath = null;
        ClearProgressTracking(modelId);
        ModelsChanged?.Invoke();
    }

    /// <summary>
    /// Get a model by ID.
    /// </summary>
    public ModelInfo? GetModel(string modelId) =>
        AvailableModels.FirstOrDefault(m => m.Id == modelId);

    /// <summary>
    /// Get the local file path for a model.
    /// </summary>
    public string? GetModelPath(string modelId) =>
        GetModel(modelId)?.DownloadedPath;

    public DownloadProgress? GetDownloadProgress(string modelId) =>
        _downloadProgressByModel.TryGetValue(modelId, out var progress) ? progress : null;

    /// <summary>
    /// Calculate total size of downloaded models.
    /// </summary>
    public long TotalDownloadedSize() =>
        AvailableModels
            .Where(m => m.Status == ModelStatus.Downloaded && m.DownloadedPath != null)
            .Sum(m => File.Exists(m.DownloadedPath!) ? new FileInfo(m.DownloadedPath!).Length : 0);

    // --- Private helpers ---

    private void ResetProgressTracking(string modelId, long totalBytes)
    {
        _speedSamples[modelId] = new List<SpeedSample>();
        _downloadProgressByModel[modelId] = new DownloadProgress(0, 0, totalBytes, 0);
    }

    private void ClearProgressTracking(string modelId)
    {
        _downloadProgressByModel.Remove(modelId);
        _speedSamples.Remove(modelId);
    }

    private double ComputeSpeed(string modelId, long latestBytes, DateTime now)
    {
        if (!_speedSamples.TryGetValue(modelId, out var samples))
        {
            samples = new List<SpeedSample>();
            _speedSamples[modelId] = samples;
        }

        samples.Add(new SpeedSample(now, latestBytes));
        samples.RemoveAll(sample => (now - sample.Timestamp).TotalSeconds > SpeedWindowSeconds);

        if (samples.Count < 2)
            return 0;

        var first = samples[0];
        var elapsed = (now - first.Timestamp).TotalSeconds;
        return elapsed > 0 ? (latestBytes - first.Bytes) / elapsed : 0;
    }

    private void ReportProgress(
        ModelInfo model,
        long receivedBytes,
        long totalBytes,
        IProgress<DownloadProgress>? progress,
        DateTime now)
    {
        var details = new DownloadProgress(
            Fraction: totalBytes > 0 ? (double)receivedBytes / totalBytes : 0,
            BytesPerSecond: ComputeSpeed(model.Id, receivedBytes, now),
            TotalBytes: totalBytes,
            ReceivedBytes: receivedBytes);

        model.DownloadProgress = details.Fraction;
        _downloadProgressByModel[model.Id] = details;
        progress?.Report(details);
        ModelsChanged?.Invoke();
    }

    private async Task VerifyFileIntegrityAsync(string filePath, string? expectedHash)
    {
        if (string.IsNullOrEmpty(expectedHash))
            return;

        using var sha256 = SHA256.Create();
        await using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read, 81920, true);
        var buffer = new byte[81920];
        int read;
        while ((read = await stream.ReadAsync(buffer)) > 0)
        {
            sha256.TransformBlock(buffer, 0, read, null, 0);
        }
        sha256.TransformFinalBlock([], 0, 0);
        var actualHash = BitConverter.ToString(sha256.Hash!).Replace("-", "").ToLowerInvariant();

        if (actualHash != expectedHash)
        {
            File.Delete(filePath);
            throw new ModelDownloadException(
                $"File integrity check failed (expected {expectedHash[..8]}…, got {actualHash[..8]}…)");
        }
    }

    /// <summary>
    /// Validate that a file has a recognized GGML magic header.
    /// </summary>
    private static bool IsValidGgmlFile(string filePath)
    {
        try
        {
            using var stream = File.OpenRead(filePath);
            Span<byte> header = stackalloc byte[4];
            if (stream.Read(header) < 4)
                return false;

            var magic = BitConverter.ToUInt32(header);
            // Known GGML magic numbers: "ggml" (0x67676d6c), "ggmf" (0x67676d66), "ggjt" (0x67676a74)
            return magic is 0x67676d6c or 0x67676d66 or 0x67676a74;
        }
        catch
        {
            return false;
        }
    }

    private void CleanupDownload(ModelInfo model)
    {
        // Clean up single-file temp
        var tempPath = Path.Combine(_modelsDirectory, model.Id + ".bin.tmp");
        try { if (File.Exists(tempPath)) File.Delete(tempPath); } catch { }
        // Clean up directory download temp
        var tempDir = Path.Combine(_modelsDirectory, model.Id + ".downloading");
        try { if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true); } catch { }
        ClearProgressTracking(model.Id);
    }
}

public class ModelDownloadException : Exception
{
    public ModelDownloadException(string message) : base(message) { }
    public ModelDownloadException(string message, Exception inner) : base(message, inner) { }
}

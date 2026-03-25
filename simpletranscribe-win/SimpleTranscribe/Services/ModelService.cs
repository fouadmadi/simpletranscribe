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

    public List<ModelInfo> AvailableModels { get; private set; } = new();
    public event Action? ModelsChanged;

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
            Sha256 = m.Sha256
        }).ToList();

        // Check which models are already downloaded
        foreach (var model in models)
        {
            var modelPath = Path.Combine(_modelsDirectory, model.Id + ".bin");
            if (File.Exists(modelPath))
            {
                model.Status = ModelStatus.Downloaded;
                model.DownloadedPath = modelPath;
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
    /// Download a model by ID with progress reporting.
    /// </summary>
    public async Task DownloadModelAsync(string modelId, IProgress<double>? progress = null, CancellationToken externalToken = default)
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
            ModelsChanged?.Invoke();
            Log.Info("ModelService", $"Starting download: {modelId}");

            var destPath = Path.Combine(_modelsDirectory, modelId + ".bin");
            var tempPath = destPath + ".tmp";

            using var response = await _httpClient.GetAsync(
                model.DownloadUrl,
                HttpCompletionOption.ResponseHeadersRead,
                cts.Token);
            response.EnsureSuccessStatusCode();

            var totalBytes = response.Content.Headers.ContentLength ?? -1;

            await using var contentStream = await response.Content.ReadAsStreamAsync(cts.Token);
            await using var fileStream = new FileStream(tempPath, FileMode.Create, FileAccess.Write, FileShare.None, 81920, true);

            var buffer = new byte[81920];
            long bytesRead = 0;
            int read;
            var lastProgressReport = DateTime.MinValue;

            while ((read = await contentStream.ReadAsync(buffer.AsMemory(0, buffer.Length), cts.Token)) > 0)
            {
                await fileStream.WriteAsync(buffer.AsMemory(0, read), cts.Token);
                bytesRead += read;

                // Throttle progress updates to ~5Hz (matches macOS 0.2s throttle)
                var now = DateTime.UtcNow;
                if (totalBytes > 0 && (now - lastProgressReport).TotalMilliseconds >= 200)
                {
                    var progressValue = (double)bytesRead / totalBytes;
                    model.DownloadProgress = progressValue;
                    progress?.Report(progressValue);
                    ModelsChanged?.Invoke();
                    lastProgressReport = now;
                }
            }

            await fileStream.FlushAsync(cts.Token);
            fileStream.Close();

            // Verify SHA256 hash
            await VerifyFileIntegrityAsync(tempPath, model.Sha256);

            // Move temp file to final location
            if (File.Exists(destPath))
                File.Delete(destPath);
            File.Move(tempPath, destPath);

            model.Status = ModelStatus.Downloaded;
            model.DownloadedPath = destPath;
            model.DownloadProgress = 1.0;
            progress?.Report(1.0);
            Log.Info("ModelService", $"Download complete: {modelId}");
        }
        catch (OperationCanceledException)
        {
            model.Status = ModelStatus.NotDownloaded;
            model.DownloadProgress = 0;
            CleanupTempFile(modelId);
            Log.Info("ModelService", $"Download cancelled: {modelId}");
        }
        catch (Exception ex)
        {
            model.Status = ModelStatus.Failed;
            model.DownloadProgress = 0;
            CleanupTempFile(modelId);
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

        if (model.DownloadedPath != null && File.Exists(model.DownloadedPath))
        {
            File.Delete(model.DownloadedPath);
        }

        model.Status = ModelStatus.NotDownloaded;
        model.DownloadedPath = null;
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

    /// <summary>
    /// Calculate total size of downloaded models.
    /// </summary>
    public long TotalDownloadedSize() =>
        AvailableModels
            .Where(m => m.Status == ModelStatus.Downloaded && m.DownloadedPath != null)
            .Sum(m => File.Exists(m.DownloadedPath!) ? new FileInfo(m.DownloadedPath!).Length : 0);

    // --- Private helpers ---

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

    private void CleanupTempFile(string modelId)
    {
        var tempPath = Path.Combine(_modelsDirectory, modelId + ".bin.tmp");
        try { if (File.Exists(tempPath)) File.Delete(tempPath); } catch { }
    }
}

public class ModelDownloadException : Exception
{
    public ModelDownloadException(string message) : base(message) { }
    public ModelDownloadException(string message, Exception inner) : base(message, inner) { }
}

using System.Collections.Concurrent;

namespace SimpleTranscribe.Services;

/// <summary>
/// Simple structured logging for diagnostics. Logs to a file in %LOCALAPPDATA%/SimpleTranscribe/logs/.
/// Rotates logs when they exceed 5 MB. Designed to be lightweight with async flushing.
/// </summary>
public sealed class AppLogger : IDisposable
{
    private static readonly Lazy<AppLogger> _instance = new(() => new AppLogger());
    public static AppLogger Instance => _instance.Value;

    private readonly string _logDir;
    private readonly ConcurrentQueue<string> _buffer = new();
    private readonly Timer _flushTimer;
    private readonly object _writeLock = new();
    private bool _disposed;

    private const long MaxFileSize = 5 * 1024 * 1024; // 5 MB

    private AppLogger()
    {
        _logDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "SimpleTranscribe", "logs");
        Directory.CreateDirectory(_logDir);

        // Flush buffered entries every 2 seconds
        _flushTimer = new Timer(_ => Flush(), null, TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(2));
    }

    public void Info(string source, string message)
        => Enqueue("INFO", source, message);

    public void Warn(string source, string message)
        => Enqueue("WARN", source, message);

    public void Error(string source, string message, Exception? ex = null)
    {
        var msg = ex != null ? $"{message} | {ex.GetType().Name}: {ex.Message}" : message;
        Enqueue("ERROR", source, msg);
    }

    private void Enqueue(string level, string source, string message)
    {
        if (_disposed) return;
        var entry = $"{DateTime.UtcNow:yyyy-MM-dd HH:mm:ss.fff} [{level}] [{source}] {message}";
        _buffer.Enqueue(entry);
    }

    private void Flush()
    {
        if (_buffer.IsEmpty) return;

        var lines = new List<string>();
        while (_buffer.TryDequeue(out var entry))
            lines.Add(entry);

        if (lines.Count == 0) return;

        lock (_writeLock)
        {
            try
            {
                var logFile = Path.Combine(_logDir, "simpletranscribe.log");

                // Rotate if too large
                if (File.Exists(logFile) && new FileInfo(logFile).Length > MaxFileSize)
                {
                    var rotated = Path.Combine(_logDir, $"simpletranscribe_{DateTime.UtcNow:yyyyMMdd_HHmmss}.log");
                    File.Move(logFile, rotated);

                    // Keep only the 3 most recent rotated logs
                    var oldLogs = Directory.GetFiles(_logDir, "simpletranscribe_*.log")
                        .OrderByDescending(f => f)
                        .Skip(3);
                    foreach (var old in oldLogs)
                        try { File.Delete(old); } catch { }
                }

                File.AppendAllLines(logFile, lines);
            }
            catch { /* Logging must never crash the app */ }
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _flushTimer.Dispose();
        Flush(); // Final flush
    }
}

using SimpleTranscribe.Interop;

namespace SimpleTranscribe.Services;

/// <summary>
/// Performs chunked (streaming) Whisper inference on live audio for live-preview.
/// Shares the caller's whisper context and ctxLock — inference is serialized.
/// Parakeet models are not supported; callers should gate on model type.
/// </summary>
public sealed class StreamingTranscriber : IDisposable
{
    private const double ChunkDurationSec = 3.0;
    private const int SampleRate = 16_000;

    private readonly nint _ctx;
    private readonly SemaphoreSlim _ctxLock;
    private readonly SemaphoreSlim _bufferLock = new(1, 1);
    private readonly List<float> _buffer = new();
    private readonly string _language;
    private bool _running;
    private bool _disposed;

    public StreamingTranscriber(nint sharedCtx, SemaphoreSlim sharedCtxLock, string language)
    {
        _ctx = sharedCtx;
        _ctxLock = sharedCtxLock;
        _language = language;
    }

    public void Start()
    {
        _buffer.Clear();
        _running = true;
    }

    public void Stop()
    {
        _running = false;
        _buffer.Clear();
    }

    /// <summary>
    /// Feed audio samples. Returns partial transcription text when a 3-second chunk is ready.
    /// Returns null if the buffer is not full yet or streaming is stopped.
    /// </summary>
    public async Task<string?> FeedAsync(float[] samples)
    {
        if (!_running || _ctx == nint.Zero) return null;

        await _bufferLock.WaitAsync();
        try { _buffer.AddRange(samples); }
        finally { _bufferLock.Release(); }

        var chunkSamples = (int)(ChunkDurationSec * SampleRate);

        await _bufferLock.WaitAsync();
        float[] chunk;
        try
        {
            if (_buffer.Count < chunkSamples) return null;
            chunk = _buffer.Take(chunkSamples).ToArray();
            _buffer.RemoveRange(0, chunkSamples);
        }
        finally { _bufferLock.Release(); }

        return await Task.Run(() => RunChunk(chunk));
    }

    private string? RunChunk(float[] chunk)
    {
        if (!_ctxLock.Wait(0)) return null; // Skip if batch pass has the lock
        try
        {
            using var pars = WhisperParams.CreateDefault(WhisperSamplingStrategy.Greedy);
            pars.NThreads = Math.Max(1, Environment.ProcessorCount / 2);
            pars.NoContext = true;
            pars.SingleSegment = true;
            pars.PrintProgress = false;
            pars.PrintTimestamps = false;
            pars.PrintSpecial = false;
            pars.ConfigureLanguage(_language == "auto" ? "auto" : _language);

            if (WhisperNative.Full(_ctx, pars.Pointer, chunk, chunk.Length) != 0)
                return null;

            var n = WhisperNative.FullNSegments(_ctx);
            var parts = new List<string>();
            for (int i = 0; i < n; i++)
            {
                var t = WhisperHelpers.GetSegmentText(_ctx, i).Trim();
                if (!string.IsNullOrEmpty(t)) parts.Add(t);
            }
            var result = string.Join(" ", parts).Trim();
            return string.IsNullOrEmpty(result) ? null : result;
        }
        finally { _ctxLock.Release(); }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _bufferLock.Dispose();
    }
}

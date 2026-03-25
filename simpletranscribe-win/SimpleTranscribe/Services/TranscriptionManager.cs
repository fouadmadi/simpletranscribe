using System.Runtime.InteropServices;
using SimpleTranscribe.Interop;

namespace SimpleTranscribe.Services;

/// <summary>
/// Manages Whisper model loading, audio accumulation, and transcription.
/// Port of macOS TranscriptionManager.swift using whisper.cpp P/Invoke.
/// Thread-safe: all access to the native whisper context is synchronized via _ctxLock.
/// </summary>
public class TranscriptionManager : IDisposable
{
    private nint _ctx;
    private readonly List<float> _accumulatedAudio = new();
    private readonly SemaphoreSlim _audioLock = new(1, 1);
    private readonly SemaphoreSlim _ctxLock = new(1, 1);
    private bool _isTranscribing;
    private bool _disposed;

    // 30 minutes at 16kHz — matches macOS maxSamples
    private const int MaxSamples = 30 * 60 * 16_000;

    private static readonly Dictionary<string, string> LanguageMap = new()
    {
        ["auto"] = "auto",
        ["en"] = "en",
        ["es"] = "es",
        ["fr"] = "fr",
        ["de"] = "de",
        ["zh"] = "zh",
    };

    public bool IsTranscribing
    {
        get => _isTranscribing;
        private set
        {
            _isTranscribing = value;
            IsTranscribingChanged?.Invoke(value);
        }
    }

    public bool IsModelLoaded => Volatile.Read(ref _ctx) != nint.Zero;

    public event Action<bool>? IsTranscribingChanged;

    /// <summary>
    /// Load a Whisper model from the given file path.
    /// Waits for any in-flight inference to complete before swapping the context.
    /// </summary>
    public async Task LoadModelAsync(string modelPath)
    {
        if (!File.Exists(modelPath))
            throw new FileNotFoundException("Model file not found", modelPath);

        // Acquire context lock to prevent loading while inference is running
        await _ctxLock.WaitAsync();
        try
        {
            FreeModelUnsafe();

            // Load on a background thread (heavy I/O)
            var ctx = await Task.Run(() => WhisperNative.InitFromFile(modelPath));

            if (ctx == nint.Zero)
                throw new InvalidOperationException($"Failed to load model from {Path.GetFileName(modelPath)}");

            Volatile.Write(ref _ctx, ctx);
        }
        finally
        {
            _ctxLock.Release();
        }
    }

    /// <summary>
    /// Prepare for a new recording session — clears accumulated audio and sets language.
    /// </summary>
    public void StartTranscription(string language)
    {
        _audioLock.Wait();
        try
        {
            _accumulatedAudio.Clear();
            _accumulatedAudio.Capacity = Math.Max(_accumulatedAudio.Capacity, 1_920_000); // 2 min at 16kHz
        }
        finally
        {
            _audioLock.Release();
        }

        IsTranscribing = true;
    }

    /// <summary>
    /// Append audio samples from the AudioManager. Thread-safe.
    /// </summary>
    public void AppendAudio(float[] buffer)
    {
        _audioLock.Wait();
        try
        {
            var remaining = MaxSamples - _accumulatedAudio.Count;
            if (remaining > 0)
            {
                var samplesToAdd = Math.Min(buffer.Length, remaining);
                if (samplesToAdd == buffer.Length)
                    _accumulatedAudio.AddRange(buffer);
                else
                    _accumulatedAudio.AddRange(buffer[..samplesToAdd]);
            }
        }
        finally
        {
            _audioLock.Release();
        }
    }

    /// <summary>
    /// Process accumulated audio and return the transcribed text.
    /// </summary>
    public async Task<string> ProcessAudioAsync(string language = "en")
    {
        try
        {
            if (Volatile.Read(ref _ctx) == nint.Zero)
                throw new InvalidOperationException("Model not loaded");

            // Take a snapshot of accumulated audio
            float[] audioSnapshot;
            _audioLock.Wait();
            try
            {
                audioSnapshot = _accumulatedAudio.ToArray();
            }
            finally
            {
                _audioLock.Release();
            }

            if (audioSnapshot.Length == 0)
                return "";

            // Run whisper inference on background thread, holding context lock
            var text = await Task.Run(async () =>
            {
                await _ctxLock.WaitAsync();
                try
                {
                    var ctx = Volatile.Read(ref _ctx);
                    if (ctx == nint.Zero)
                        throw new InvalidOperationException("Model was unloaded during inference");
                    return RunInference(ctx, audioSnapshot, language);
                }
                finally
                {
                    _ctxLock.Release();
                }
            });
            return text.Trim();
        }
        finally
        {
            IsTranscribing = false;
        }
    }

    private static string RunInference(nint ctx, float[] audio, string language)
    {
        using var pars = WhisperParams.CreateDefault(WhisperSamplingStrategy.Greedy);

        // Configure params to match macOS settings
        pars.NThreads = Math.Max(1, Environment.ProcessorCount);
        pars.NoContext = true;
        pars.SingleSegment = true;
        pars.PrintProgress = false;
        pars.PrintTimestamps = false;
        pars.PrintSpecial = false;
        pars.PrintRealtime = false;

        // Language configuration via safe field offsets
        pars.ConfigureLanguage(LanguageMap.GetValueOrDefault(language, "en"));

        var result = WhisperNative.Full(ctx, pars.Pointer, audio, audio.Length);
        if (result != 0)
            throw new InvalidOperationException($"Whisper inference failed with code {result}");

        var segments = WhisperNative.FullNSegments(ctx);
        var texts = new List<string>();

        for (int i = 0; i < segments; i++)
        {
            var segText = WhisperHelpers.GetSegmentText(ctx, i);
            if (!string.IsNullOrWhiteSpace(segText))
                texts.Add(segText);
        }

        return string.Join(" ", texts);
    }

    /// <summary>Free the native context. Caller must hold _ctxLock.</summary>
    private void FreeModelUnsafe()
    {
        var ctx = Volatile.Read(ref _ctx);
        if (ctx != nint.Zero)
        {
            WhisperNative.Free(ctx);
            Volatile.Write(ref _ctx, nint.Zero);
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        // Acquire lock to ensure no in-flight inference before freeing
        _ctxLock.Wait();
        try
        {
            FreeModelUnsafe();
        }
        finally
        {
            _ctxLock.Release();
        }

        _audioLock.Dispose();
        _ctxLock.Dispose();
        GC.SuppressFinalize(this);
    }
}

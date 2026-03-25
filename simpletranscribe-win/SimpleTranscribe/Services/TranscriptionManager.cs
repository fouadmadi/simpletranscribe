using System.Runtime.InteropServices;
using SimpleTranscribe.Interop;

namespace SimpleTranscribe.Services;

/// <summary>
/// Manages Whisper model loading, audio accumulation, and transcription.
/// Port of macOS TranscriptionManager.swift using whisper.cpp P/Invoke.
/// </summary>
public class TranscriptionManager : IDisposable
{
    private nint _ctx;
    private readonly List<float> _accumulatedAudio = new();
    private readonly SemaphoreSlim _audioLock = new(1, 1);
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

    public bool IsModelLoaded => _ctx != nint.Zero;

    public event Action<bool>? IsTranscribingChanged;

    /// <summary>
    /// Load a Whisper model from the given file path.
    /// </summary>
    public async Task LoadModelAsync(string modelPath)
    {
        if (!File.Exists(modelPath))
            throw new FileNotFoundException("Model file not found", modelPath);

        // Free existing model
        FreeModel();

        // Load on a background thread (heavy I/O)
        var ctx = await Task.Run(() => WhisperNative.InitFromFile(modelPath));

        if (ctx == nint.Zero)
            throw new InvalidOperationException($"Failed to load model from {Path.GetFileName(modelPath)}");

        _ctx = ctx;
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
                _accumulatedAudio.AddRange(buffer.AsSpan(0, samplesToAdd).ToArray());
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
            if (_ctx == nint.Zero)
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

            // Run whisper inference on background thread
            var text = await Task.Run(() => RunInference(audioSnapshot, language));
            return text.Trim();
        }
        finally
        {
            IsTranscribing = false;
        }
    }

    private string RunInference(float[] audio, string language)
    {
        var pars = WhisperNative.FullDefaultParams(WhisperSamplingStrategy.Greedy);

        // Configure params to match macOS settings
        pars.n_threads = Math.Max(1, Environment.ProcessorCount);
        pars.no_context = true;
        pars.single_segment = true;
        pars.print_progress = false;
        pars.print_timestamps = false;
        pars.print_special = false;
        pars.print_realtime = false;

        // Set language
        var whisperLang = LanguageMap.GetValueOrDefault(language, "en");
        pars.language = whisperLang;
        pars.detect_language = whisperLang == "auto";

        var result = WhisperNative.Full(_ctx, pars, audio, audio.Length);
        if (result != 0)
            throw new InvalidOperationException($"Whisper inference failed with code {result}");

        var segments = WhisperNative.FullNSegments(_ctx);
        var texts = new List<string>();

        for (int i = 0; i < segments; i++)
        {
            var segText = WhisperHelpers.GetSegmentText(_ctx, i);
            if (!string.IsNullOrWhiteSpace(segText))
                texts.Add(segText);
        }

        return string.Join(" ", texts);
    }

    private void FreeModel()
    {
        if (_ctx != nint.Zero)
        {
            WhisperNative.Free(_ctx);
            _ctx = nint.Zero;
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        FreeModel();
        _audioLock.Dispose();
        GC.SuppressFinalize(this);
    }
}

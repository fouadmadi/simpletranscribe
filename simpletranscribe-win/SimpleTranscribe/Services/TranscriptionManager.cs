using System.Runtime.InteropServices;
using SimpleTranscribe.Interop;
using SimpleTranscribe.Models;
using SherpaOnnx;

namespace SimpleTranscribe.Services;

/// <summary>
/// Manages Whisper and Parakeet model loading, audio accumulation, and transcription.
/// Port of macOS TranscriptionManager.swift using whisper.cpp P/Invoke and sherpa-onnx.
/// Thread-safe: all access to the native contexts is synchronized via _ctxLock.
/// </summary>
public class TranscriptionManager : IDisposable
{
    private static readonly AppLogger Log = AppLogger.Instance;

    // Whisper backend
    private nint _ctx;

    // Parakeet backend (sherpa-onnx)
    private OfflineRecognizer? _parakeetRecognizer;

    // Track which backend is active
    private ModelType _loadedModelType = ModelType.Whisper;

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

    public bool IsModelLoaded => Volatile.Read(ref _ctx) != nint.Zero || _parakeetRecognizer != null;

    public event Action<bool>? IsTranscribingChanged;

    /// <summary>
    /// Load a model from the given file path or directory.
    /// Waits for any in-flight inference to complete before swapping the context.
    /// </summary>
    public async Task LoadModelAsync(string modelPath, ModelType modelType = ModelType.Whisper)
    {
        switch (modelType)
        {
            case ModelType.Whisper:
                await LoadWhisperModelAsync(modelPath);
                break;
            case ModelType.Parakeet:
                await LoadParakeetModelAsync(modelPath);
                break;
            default:
                throw new InvalidOperationException($"Unsupported model type: {modelType}");
        }

        _loadedModelType = modelType;
    }

    /// <summary>
    /// Load a Whisper model from a .bin file.
    /// </summary>
    private async Task LoadWhisperModelAsync(string modelPath)
    {
        if (!File.Exists(modelPath))
            throw new FileNotFoundException("Model file not found", modelPath);

        Log.Info("Transcription", $"Loading Whisper model: {Path.GetFileName(modelPath)}");

        await _ctxLock.WaitAsync();
        try
        {
            FreeModelUnsafe();
            var ctx = await Task.Run(() => WhisperNative.InitFromFile(modelPath));

            if (ctx == nint.Zero)
                throw new InvalidOperationException($"Failed to load model from {Path.GetFileName(modelPath)}");

            Volatile.Write(ref _ctx, ctx);
            Log.Info("Transcription", "Whisper model loaded successfully");
        }
        finally
        {
            _ctxLock.Release();
        }
    }

    /// <summary>
    /// Load a Parakeet ONNX model from a directory containing encoder, decoder, joiner, and tokens.
    /// </summary>
    private async Task LoadParakeetModelAsync(string modelDirectory)
    {
        if (!Directory.Exists(modelDirectory))
            throw new DirectoryNotFoundException($"Parakeet model directory not found: {modelDirectory}");

        var requiredFiles = new[] { "encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt" };
        foreach (var file in requiredFiles)
        {
            var filePath = Path.Combine(modelDirectory, file);
            if (!File.Exists(filePath))
                throw new FileNotFoundException($"Missing required file: {file}", filePath);
        }

        Log.Info("Transcription", $"Loading Parakeet model from: {Path.GetFileName(modelDirectory)}");

        await _ctxLock.WaitAsync();
        try
        {
            FreeModelUnsafe();

            _parakeetRecognizer = await Task.Run(() =>
            {
                var config = new OfflineRecognizerConfig();
                config.FeatConfig.SampleRate = 16000;
                config.FeatConfig.FeatureDim = 80;

                config.ModelConfig.Transducer.Encoder = Path.Combine(modelDirectory, "encoder.int8.onnx");
                config.ModelConfig.Transducer.Decoder = Path.Combine(modelDirectory, "decoder.int8.onnx");
                config.ModelConfig.Transducer.Joiner = Path.Combine(modelDirectory, "joiner.int8.onnx");
                config.ModelConfig.Tokens = Path.Combine(modelDirectory, "tokens.txt");
                config.ModelConfig.NumThreads = Math.Max(1, Environment.ProcessorCount);
                config.ModelConfig.Provider = "cpu";
                config.DecodingMethod = "greedy_search";

                return new OfflineRecognizer(config);
            });

            Log.Info("Transcription", "Parakeet model loaded successfully");
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
            if (!IsModelLoaded)
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

            Log.Info("Transcription", $"Processing {audioSnapshot.Length} samples ({audioSnapshot.Length / 16000.0:F1}s)");

            var text = await Task.Run(async () =>
            {
                await _ctxLock.WaitAsync();
                try
                {
                    if (_loadedModelType == ModelType.Parakeet && _parakeetRecognizer != null)
                        return RunParakeetInference(_parakeetRecognizer, audioSnapshot);

                    var ctx = Volatile.Read(ref _ctx);
                    if (ctx == nint.Zero)
                        throw new InvalidOperationException("Model was unloaded during inference");
                    return RunWhisperInference(ctx, audioSnapshot, language);
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

    private static string RunWhisperInference(nint ctx, float[] audio, string language)
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

    /// <summary>Run Parakeet (sherpa-onnx) offline transducer inference.</summary>
    private static string RunParakeetInference(OfflineRecognizer recognizer, float[] audio)
    {
        using var stream = recognizer.CreateStream();
        stream.AcceptWaveform(16000, audio);
        recognizer.Decode(stream);
        return stream.Result.Text;
    }

    /// <summary>Free all native contexts. Caller must hold _ctxLock.</summary>
    private void FreeModelUnsafe()
    {
        var ctx = Volatile.Read(ref _ctx);
        if (ctx != nint.Zero)
        {
            WhisperNative.Free(ctx);
            Volatile.Write(ref _ctx, nint.Zero);
        }

        _parakeetRecognizer?.Dispose();
        _parakeetRecognizer = null;
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

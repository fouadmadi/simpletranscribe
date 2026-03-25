using System.Diagnostics;
using SimpleTranscribe.Services;

namespace SimpleTranscribe.Tests;

/// <summary>
/// Performance benchmarks for Whisper inference.
/// Requires a downloaded model and whisper.dll to run.
/// </summary>
public class PerformanceTests
{
    private static string? FindModelPath()
    {
        var modelsDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "SimpleTranscribe", "models");

        if (!Directory.Exists(modelsDir))
            return null;

        var tinyPath = Path.Combine(modelsDir, "ggml-tiny.en.bin");
        return File.Exists(tinyPath) ? tinyPath : null;
    }

    [Fact]
    [Trait("Category", "Performance")]
    public async Task WhisperInference_TinyModel_CompletesWithin30Seconds()
    {
        var modelPath = FindModelPath();
        if (modelPath == null)
            return; // Skip if no model

        using var manager = new TranscriptionManager();
        await manager.LoadModelAsync(modelPath);

        manager.StartTranscription("en");

        // Feed 5 seconds of silence
        var silence = new float[16000 * 5];
        manager.AppendAudio(silence);

        var sw = Stopwatch.StartNew();
        var text = await manager.ProcessAudioAsync("en");
        sw.Stop();

        // Tiny model should process 5s of audio in well under 30 seconds
        Assert.True(sw.Elapsed.TotalSeconds < 30,
            $"Inference took {sw.Elapsed.TotalSeconds:F1}s — expected < 30s for tiny model on 5s audio");
    }

    [Fact]
    [Trait("Category", "Performance")]
    public async Task ModelLoading_TinyModel_CompletesWithin10Seconds()
    {
        var modelPath = FindModelPath();
        if (modelPath == null)
            return;

        using var manager = new TranscriptionManager();

        var sw = Stopwatch.StartNew();
        await manager.LoadModelAsync(modelPath);
        sw.Stop();

        Assert.True(sw.Elapsed.TotalSeconds < 10,
            $"Model loading took {sw.Elapsed.TotalSeconds:F1}s — expected < 10s for tiny model");
        Assert.True(manager.IsModelLoaded);
    }
}

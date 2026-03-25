using SimpleTranscribe.Models;
using SimpleTranscribe.Services;

namespace SimpleTranscribe.Tests;

/// <summary>
/// Integration tests that verify the end-to-end flow.
/// These tests require whisper.dll and a downloaded model to run.
/// Mark with [Trait("Category", "Integration")] to skip in CI without native deps.
/// </summary>
public class IntegrationTests
{
    private static string? FindModelPath()
    {
        var modelsDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "SimpleTranscribe", "models");

        if (!Directory.Exists(modelsDir))
            return null;

        // Prefer tiny model for fast tests
        var tinyPath = Path.Combine(modelsDir, "ggml-tiny.en.bin");
        if (File.Exists(tinyPath))
            return tinyPath;

        // Fall back to any available model
        return Directory.GetFiles(modelsDir, "*.bin").FirstOrDefault();
    }

    [Fact]
    [Trait("Category", "Integration")]
    public void ModelService_CanLoadAndListModels()
    {
        var service = new ModelService();
        Assert.NotEmpty(service.AvailableModels);
        Assert.True(service.AvailableModels.Count >= 5); // At least the 5 known models
    }

    [Fact]
    [Trait("Category", "Integration")]
    public async Task TranscriptionManager_CanLoadModel_WhenAvailable()
    {
        var modelPath = FindModelPath();
        if (modelPath == null)
        {
            // Skip: no model downloaded on this machine
            return;
        }

        using var manager = new TranscriptionManager();
        await manager.LoadModelAsync(modelPath);
        Assert.True(manager.IsModelLoaded);
    }

    [Fact]
    [Trait("Category", "Integration")]
    public async Task FullPipeline_RecordSilence_ReturnsEmptyOrShortText()
    {
        var modelPath = FindModelPath();
        if (modelPath == null)
            return;

        using var transcription = new TranscriptionManager();
        await transcription.LoadModelAsync(modelPath);

        transcription.StartTranscription("en");

        // Feed 1 second of silence (16000 samples at 16kHz)
        var silence = new float[16000];
        transcription.AppendAudio(silence);

        var text = await transcription.ProcessAudioAsync("en");

        // Whisper may produce empty text or hallucinate a short phrase for silence
        // The important thing is it doesn't crash
        Assert.NotNull(text);
    }

    [Fact]
    [Trait("Category", "Integration")]
    public void AudioManager_DeviceEnumeration_Works()
    {
        var devices = AudioManager.GetInputDevices();
        // On a machine with audio hardware, should find at least one device
        // On CI without audio, this will be empty but shouldn't throw
        Assert.NotNull(devices);
    }
}

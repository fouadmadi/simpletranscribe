using SimpleTranscribe.Services;

namespace SimpleTranscribe.Tests;

public class TranscriptionManagerTests
{
    [Fact]
    public void IsModelLoaded_ReturnsFalse_Initially()
    {
        using var manager = new TranscriptionManager();
        Assert.False(manager.IsModelLoaded);
    }

    [Fact]
    public async Task LoadModelAsync_ThrowsFileNotFound_ForMissingFile()
    {
        using var manager = new TranscriptionManager();
        await Assert.ThrowsAsync<FileNotFoundException>(
            () => manager.LoadModelAsync(@"C:\nonexistent\model.bin"));
    }

    [Fact]
    public void AppendAudio_AcceptsBuffers()
    {
        using var manager = new TranscriptionManager();
        manager.StartTranscription("en");

        // Should not throw
        manager.AppendAudio(new float[1600]);
        manager.AppendAudio(new float[1600]);
    }

    [Fact]
    public async Task ProcessAudioAsync_ThrowsWhenNoModel()
    {
        using var manager = new TranscriptionManager();
        manager.StartTranscription("en");

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => manager.ProcessAudioAsync());
    }

    [Fact]
    public void Dispose_CanBeCalledMultipleTimes()
    {
        var manager = new TranscriptionManager();
        manager.Dispose();
        manager.Dispose(); // Should not throw
    }
}

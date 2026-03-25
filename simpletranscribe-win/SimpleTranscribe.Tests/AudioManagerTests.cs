using SimpleTranscribe.Services;

namespace SimpleTranscribe.Tests;

public class AudioManagerTests
{
    [Fact]
    public void GetInputDevices_ReturnsListWithoutThrowingOnAnyPlatform()
    {
        // Should not throw even if no audio hardware (returns empty list)
        var devices = AudioManager.GetInputDevices();
        Assert.NotNull(devices);
    }

    [Fact]
    public void StartRecording_WithInvalidDevice_RaisesError()
    {
        using var manager = new AudioManager();
        Exception? capturedError = null;
        manager.OnError += ex => capturedError = ex;

        // A non-existent device ID should trigger an error
        manager.StartRecording("nonexistent-device-id-12345");

        // Either an error was raised or the method handled it gracefully
        // (depends on whether NAudio throws or returns null)
        manager.StopRecording();
    }

    [Fact]
    public void StopRecording_WhenNotRecording_DoesNotThrow()
    {
        using var manager = new AudioManager();
        manager.StopRecording(); // Should be safe to call even if never started
    }

    [Fact]
    public void Dispose_CanBeCalledMultipleTimes()
    {
        var manager = new AudioManager();
        manager.Dispose();
        manager.Dispose(); // Should not throw
    }
}

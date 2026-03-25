namespace SimpleTranscribe.Services;

/// <summary>
/// Plays audio feedback sounds for recording/transcription events.
/// Port of macOS SoundManager.swift — uses bundled .wav files instead of NSSound system sounds.
/// </summary>
public static class SoundManager
{
    private static readonly string SoundsDir = Path.Combine(
        AppContext.BaseDirectory, "Assets", "Sounds");

    /// <summary>
    /// Play when recording starts. Equivalent to macOS "Tink" sound.
    /// </summary>
    public static void PlayRecordingStarted()
        => PlaySound("recording_start.wav");

    /// <summary>
    /// Play when transcription is complete. Equivalent to macOS "Glass" sound.
    /// </summary>
    public static void PlayTranscriptionComplete()
        => PlaySound("transcription_complete.wav");

    /// <summary>
    /// Play when an error occurs. Equivalent to macOS "Basso" sound.
    /// </summary>
    public static void PlayError()
        => PlaySound("error.wav");

    private static void PlaySound(string filename)
    {
        try
        {
            var path = Path.Combine(SoundsDir, filename);
            if (!File.Exists(path))
                return;

            // Use System.Media.SoundPlayer for simple synchronous-capable playback
            var player = new System.Media.SoundPlayer(path);
            player.Play(); // Asynchronous playback — does not block UI
        }
        catch
        {
            // Silently ignore sound playback errors — non-critical
        }
    }
}

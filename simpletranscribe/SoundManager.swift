import AppKit

/// Plays system sounds for recording/transcription feedback
enum SoundManager {
    /// Play when recording starts
    static func playRecordingStarted() {
        NSSound(named: "Tink")?.play()
    }
    
    /// Play when transcription is complete
    static func playTranscriptionComplete() {
        NSSound(named: "Glass")?.play()
    }
    
    /// Play when an error occurs
    static func playError() {
        NSSound(named: "Basso")?.play()
    }
}

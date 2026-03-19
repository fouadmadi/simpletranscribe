import AppKit

/// Plays system sounds for recording/transcription feedback
enum SoundManager {
    private static let tink = NSSound(named: "Tink")
    private static let glass = NSSound(named: "Glass")
    private static let basso = NSSound(named: "Basso")

    /// Play when recording starts
    static func playRecordingStarted() {
        tink?.play()
    }
    
    /// Play when transcription is complete
    static func playTranscriptionComplete() {
        glass?.play()
    }
    
    /// Play when an error occurs
    static func playError() {
        basso?.play()
    }
}

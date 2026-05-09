import Foundation
import SwiftUI

struct RecordingControlsView: View {
    let isRecording: Bool
    let isProcessing: Bool
    let isTranscribing: Bool
    let canRecord: Bool
    let isLoadingModel: Bool
    let showTranscriptionStarted: Bool
    let recordingElapsedSeconds: Int
    let timeLimitWarning: Bool
    let onToggleRecording: () -> Void
    let onShowModelManager: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggleRecording) {
                HStack {
                    Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    Text(isRecording ? "Stop" : "Transcribe")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(isRecording ? .red : .accentColor)
            .disabled(isProcessing || !canRecord || isLoadingModel)
            .help("Hold fn+Control to record, release to transcribe")

            Text("fn+⌃")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(NSColor.tertiaryLabelColor).opacity(0.2))
                .cornerRadius(4)
                .help("Hold fn+Control to start recording, release to stop and transcribe")

            if recordingElapsedSeconds > 0 {
                Text(formattedElapsedTime)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(timeLimitWarning ? .orange : .secondary)
                    .padding(.leading, 8)
            }

            if isProcessing || isTranscribing {
                ProgressView()
                    .scaleEffect(0.6)
                    .padding(.leading, 8)
                Text("Processing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if showTranscriptionStarted {
                Label("Transcription started", systemImage: "waveform")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .padding(.leading, 8)
            }

            Spacer()

            Button(action: onShowModelManager) {
                Image(systemName: "gearshape")
                Text("Models")
            }
            .buttonStyle(.bordered)
            .help("Manage models")
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var formattedElapsedTime: String {
        let minutes = recordingElapsedSeconds / 60
        let seconds = recordingElapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

import SwiftUI

struct RecordingControlsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        VStack(spacing: 12) {
            // Source picker
            Picker("Source", selection: $appModel.recordingSource) {
                ForEach(RecordingSource.allCases) { source in
                    Label(source.rawValue, systemImage: source.iconName).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .disabled(appModel.isRecording)

            HStack(spacing: 16) {
                // Record / Stop button
                Button(action: { appModel.toggleRecording() }) {
                    HStack(spacing: 8) {
                        Image(systemName: appModel.isRecording ? "stop.circle.fill" : "record.circle.fill")
                            .font(.title3)
                        Text(appModel.isRecording ? "Stop" : "Record")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(appModel.isRecording ? .red : .accentColor)
                .disabled(!appModel.canRecord || appModel.isSaving)

                // Timer
                if appModel.isRecording || appModel.elapsedSeconds > 0 {
                    Text(formattedTime(appModel.elapsedSeconds))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(appModel.isRecording ? .red : .secondary)
                }

                // Saving indicator
                if appModel.isSaving {
                    ProgressView().scaleEffect(0.8)
                    Text("Encoding to MP3…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Last saved badge
                if !appModel.isRecording && !appModel.isSaving, let url = appModel.lastSavedURL {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Saved: \(url.lastPathComponent)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            .font(.caption)
                            .buttonStyle(.borderless)
                    }
                }

                Spacer()
            }

            // Permission warnings
            if appModel.needsMicPermission {
                permissionBanner(
                    icon: "mic.slash.fill",
                    message: "Microphone access denied.",
                    action: appModel.openMicPermissionSettings
                )
            }
            if appModel.needsScreenPermission {
                permissionBanner(
                    icon: "display.trianglebadge.exclamationmark",
                    message: "Screen Recording permission needed for system audio.",
                    action: appModel.openScreenRecordingSettings
                )
            }

            // Error banner
            if let error = appModel.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") { appModel.errorMessage = nil }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
                .padding(8)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func permissionBanner(icon: String, message: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.orange)
            Text(message).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Open Settings", action: action)
                .font(.caption)
                .buttonStyle(.borderedProminent)
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func formattedTime(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

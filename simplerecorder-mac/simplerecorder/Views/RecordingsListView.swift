import SwiftUI

struct RecordingsListView: View {
    @Environment(AppModel.self) private var appModel
    @State private var entryToDelete: RecordingEntry?

    var body: some View {
        Group {
            if appModel.recordings.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No recordings yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Press Record to create your first recording.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(appModel.recordings) { entry in
                RecordingRowView(entry: entry) {
                    entryToDelete = entry
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .confirmationDialog(
            "Delete \"\(entryToDelete?.filename ?? "")\"?",
            isPresented: Binding(
                get: { entryToDelete != nil },
                set: { if !$0 { entryToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let entry = entryToDelete { appModel.deleteRecording(entry) }
                entryToDelete = nil
            }
            Button("Cancel", role: .cancel) { entryToDelete = nil }
        }
    }
}

private struct RecordingRowView: View {
    let entry: RecordingEntry
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.source.iconName)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.filename)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 8) {
                    Label(entry.source.rawValue, systemImage: entry.source.iconName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(entry.formattedDuration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(entry.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(entry.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.open(entry.url)
                } label: {
                    Label("Play", systemImage: "play.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Open in default audio player")

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .help("Delete recording")
            }
        }
        .padding(.vertical, 4)
    }
}

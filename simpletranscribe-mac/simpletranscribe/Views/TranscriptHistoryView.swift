import SwiftUI

struct TranscriptHistoryView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                Button("Clear All") {
                    showClearConfirm = true
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .foregroundColor(.red)
                .disabled(appModel.history.entries.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            if appModel.history.entries.isEmpty {
                Spacer()
                Text("No transcriptions yet")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(appModel.history.entries) { entry in
                    HistoryEntryRow(entry: entry) {
                        appModel.history.delete(entry.id)
                    }
                }
                .listStyle(.plain)
            }
        }
        .confirmationDialog("Clear History", isPresented: $showClearConfirm) {
            Button("Clear All", role: .destructive) {
                appModel.history.clear()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all transcript history.")
        }
    }
}

private struct HistoryEntryRow: View {
    let entry: TranscriptEntry
    let onDelete: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("·")
                    .foregroundColor(.secondary)
                Text(String(format: "%.0fs", entry.duration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(entry.text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                        .foregroundColor(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Delete")
            }

            Text(entry.text)
                .font(.callout)
                .lineLimit(3)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 4)
    }
}

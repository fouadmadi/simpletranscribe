import SwiftUI

struct TranscriptHistoryView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showClearConfirm = false
    @State private var searchText = ""

    private var filteredEntries: [TranscriptEntry] {
        if searchText.isEmpty { return appModel.history.entries }
        return appModel.history.entries.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                Menu {
                    ForEach(ExportFormat.allCases) { format in
                        Button(format.displayName) {
                            appModel.exportHistory(format: format)
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .help("Export history")
                .disabled(appModel.history.entries.isEmpty)

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

            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search transcripts...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(6)
            .padding(.horizontal)
            .padding(.bottom, 6)

            Divider()

            if filteredEntries.isEmpty {
                Spacer()
                Text(searchText.isEmpty ? "No transcriptions yet" : "No results found")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List(filteredEntries) { entry in
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

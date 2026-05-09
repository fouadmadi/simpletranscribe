import SwiftUI
import AppKit

struct TranscriptStatusBar: View {
    let text: String
    let lastDuration: TimeInterval

    private var wordCount: Int {
        text.split(separator: " ").count
    }
    private var charCount: Int { text.count }
    private var durationLabel: String {
        lastDuration < 1 ? "" : String(format: "%.0fs recorded", lastDuration)
    }

    var body: some View {
        HStack(spacing: 16) {
            if !text.isEmpty {
                Text("\(wordCount) words")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(charCount) chars")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if !durationLabel.isEmpty {
                Text(durationLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

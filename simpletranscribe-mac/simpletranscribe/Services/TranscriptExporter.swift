import Foundation
import UniformTypeIdentifiers
import AppKit

// MARK: - Format

enum ExportFormat: String, CaseIterable, Identifiable {
    case txt, md, srt
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .txt: return "Plain Text (.txt)"
        case .md:  return "Markdown (.md)"
        case .srt: return "SubRip (.srt)"
        }
    }

    var contentType: UTType {
        switch self {
        case .txt: return .plainText
        case .md:  return UTType("net.daringfireball.markdown") ?? .plainText
        case .srt: return UTType("com.scenarist.closed-caption-srt") ?? .plainText
        }
    }
}

// MARK: - Exporter

enum TranscriptExporter {

    static func formatText(_ text: String) -> String { text }

    static func formatMarkdown(_ text: String, title: String = "Transcript") -> String {
        "# \(title)\n\n\(text)\n"
    }

    static func formatSRT(entries: [TranscriptEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        var offset: TimeInterval = 0
        return entries.enumerated().map { (i, entry) in
            let start = srtTime(offset)
            let end   = srtTime(offset + max(entry.duration, 1))
            offset   += entry.duration
            return "\(i + 1)\n\(start) --> \(end)\n\(entry.text)\n"
        }.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func srtTime(_ seconds: TimeInterval) -> String {
        let h  = Int(seconds / 3600)
        let m  = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        let s  = Int(seconds.truncatingRemainder(dividingBy: 60))
        let ms = Int((seconds - floor(seconds)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }
}

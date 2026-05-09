import Foundation

struct DownloadProgress {
    let fraction: Double
    let bytesPerSecond: Double
    let totalBytes: Int64
    let receivedBytes: Int64

    var etaSeconds: Double? {
        guard totalBytes > 0, bytesPerSecond > 0 else { return nil }
        let remaining = Double(max(totalBytes - receivedBytes, 0))
        return remaining / bytesPerSecond
    }

    var speedString: String {
        let mbs = bytesPerSecond / 1_048_576
        if mbs >= 1 {
            return String(format: "%.1f MB/s", mbs)
        }
        let kbs = bytesPerSecond / 1_024
        return String(format: "%.0f KB/s", max(kbs, 0))
    }

    var etaString: String {
        guard let eta = etaSeconds else { return "" }
        if eta < 60 {
            return String(format: "~%.0fs remaining", eta)
        }
        if eta < 3600 {
            return String(format: "~%.0fmin remaining", eta / 60)
        }
        return String(format: "~%.1fh remaining", eta / 3600)
    }
}

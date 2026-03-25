import Foundation

/// Represents metadata and status of a Whisper model
struct ModelInfo: Identifiable, Codable {
    let id: String                    // e.g., "ggml-tiny.en"
    let name: String                  // e.g., "Tiny (English)"
    let description: String           // e.g., "Fastest, Lower accuracy"
    let size: Int64                   // Size in bytes
    let downloadURL: URL              // Remote download source
    let language: String              // e.g., "en" or "multilingual"
    let sha256: String?               // Expected SHA256 hash for verification
    
    // Local state
    var status: ModelStatus = .notDownloaded
    var downloadedPath: URL?          // Local path if downloaded
    var downloadProgress: Double = 0  // 0.0 to 1.0
    
    enum ModelStatus: String, Codable {
        case notDownloaded
        case downloading
        case downloaded
        case failed
    }
    
    /// Human-readable file size
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    /// Whether this model is available for use
    var isAvailable: Bool {
        status == .downloaded && downloadedPath != nil
    }
}

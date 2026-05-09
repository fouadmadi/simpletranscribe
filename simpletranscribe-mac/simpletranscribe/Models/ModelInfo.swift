import Foundation

/// The inference engine a model uses
enum ModelType: String, Codable {
    case whisper
    case parakeet
}

/// Describes a single file within a directory-based model (e.g., Parakeet ONNX)
struct ModelFile: Codable {
    let filename: String       // e.g., "encoder.int8.onnx"
    let downloadURL: URL       // Full remote URL for this file
    let size: Int64            // Size in bytes
    let sha256: String?        // Optional SHA256 hash
}

/// Represents metadata and status of a speech-to-text model
struct ModelInfo: Identifiable, Codable {
    let id: String                    // e.g., "ggml-tiny.en" or "parakeet-tdt-0.6b-v2"
    let name: String                  // e.g., "Tiny (English)"
    let description: String           // e.g., "Fastest, Lower accuracy"
    let size: Int64                   // Total size in bytes (sum of all files)
    let downloadURL: URL              // Remote download source (primary/single-file models)
    let language: String              // e.g., "en" or "multilingual"
    let sha256: String?               // Expected SHA256 hash (single-file models only)
    var modelType: ModelType = .whisper
    var isDirectory: Bool = false     // true for multi-file models like Parakeet ONNX
    var files: [ModelFile] = []       // Individual files for directory-based models
    
    // Local state
    var status: ModelStatus = .notDownloaded
    var downloadedPath: URL?          // Local path if downloaded (file or directory)
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

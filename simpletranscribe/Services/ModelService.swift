import Foundation
import Observation

/// Manages model downloads, discovery, and lifecycle
@Observable
final class ModelService: NSObject, URLSessionDownloadDelegate {
    var availableModels: [ModelInfo] = []
    var downloadProgress: [String: Double] = [:]
    var downloadError: [String: String] = [:]
    
    private let modelsDirectory: URL
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var downloadContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var urlSession: URLSession!
    
    override init() {
        // Create models directory: ~/Library/Application Support/com.simpletranscribe/models/
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.modelsDirectory = appSupportURL.appending(path: "com.simpletranscribe/models", directoryHint: .isDirectory)
        
        super.init()
        
        // Initialize URLSession with delegate
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: .main)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        
        // Load available models and check which ones are downloaded
        loadAvailableModels()
    }
    
    /// Load and initialize available models
    func loadAvailableModels() {
        var models = KnownModels.all
        
        // Check which models are already downloaded
        for i in 0..<models.count {
            let modelURL = modelsDirectory.appending(path: models[i].id + ".bin")
            if FileManager.default.fileExists(atPath: modelURL.path) {
                models[i].status = .downloaded
                models[i].downloadedPath = modelURL
            }
        }
        
        // Discover custom .bin files in the models directory
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil)
            for url in contents where url.pathExtension == "bin" {
                let modelID = url.deletingPathExtension().lastPathComponent
                // Only add if not already in the known models list
                if !models.contains(where: { $0.id == modelID }) {
                    var customModel = ModelInfo(
                        id: modelID,
                        name: modelID,
                        description: "Custom model",
                        size: 0,
                        downloadURL: URL(string: "about:blank")!,
                        language: "unknown"
                    )
                    customModel.status = .downloaded
                    customModel.downloadedPath = url
                    models.append(customModel)
                }
            }
        } catch {
            print("Error discovering custom models: \(error)")
        }
        
        self.availableModels = models
    }
    
    /// Download a model by ID
    func downloadModel(_ modelID: String) async throws {
        guard let model = availableModels.first(where: { $0.id == modelID }) else {
            throw ModelDownloadError.modelNotFound
        }
        
        guard model.status != .downloaded else {
            return  // Already downloaded
        }
        
        // Update status
        updateModelStatus(modelID, to: .downloading)
        downloadProgress[modelID] = 0.0
        
        // Start the download
        await withCheckedContinuation { continuation in
            let task = urlSession.downloadTask(with: model.downloadURL)
            downloadTasks[modelID] = task
            downloadContinuations[modelID] = continuation
            task.resume()
        }
    }
    
    /// Cancel an ongoing download
    func cancelDownload(_ modelID: String) {
        downloadTasks[modelID]?.cancel()
        downloadTasks.removeValue(forKey: modelID)
        downloadProgress.removeValue(forKey: modelID)
        
        if let index = availableModels.firstIndex(where: { $0.id == modelID }) {
            availableModels[index].status = .notDownloaded
        }
    }
    
    /// Delete a downloaded model
    func deleteModel(_ modelID: String) throws {
        guard let model = availableModels.first(where: { $0.id == modelID }) else {
            throw ModelDownloadError.modelNotFound
        }
        
        if let path = model.downloadedPath {
            try FileManager.default.removeItem(at: path)
        }
        
        if let index = availableModels.firstIndex(where: { $0.id == modelID }) {
            availableModels[index].status = .notDownloaded
            availableModels[index].downloadedPath = nil
        }
    }
    
    /// Get the local path for a model
    func getModelPath(_ modelID: String) -> URL? {
        availableModels.first(where: { $0.id == modelID })?.downloadedPath
    }
    
    /// Calculate total size of downloaded models
    func totalDownloadedSize() -> Int64 {
        availableModels
            .filter { $0.status == .downloaded }
            .reduce(0) { $0 + ($1.downloadedPath.map { getFileSize($0) } ?? 0) }
    }
    
    // MARK: - Private Helpers
    
    private func updateModelStatus(_ modelID: String, to status: ModelInfo.ModelStatus) {
        if let index = availableModels.firstIndex(where: { $0.id == modelID }) {
            availableModels[index].status = status
        }
    }
    
    private func getFileSize(_ url: URL) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Find the model ID from the download task
        let modelID = downloadTasks.first(where: { $0.value === downloadTask })?.key
        guard let modelID = modelID else { return }
        
        // Work with the file synchronously while it's still available
        do {
            // Ensure models directory exists
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
            
            let destinationURL = modelsDirectory.appending(path: modelID + ".bin")
            
            // Remove existing file if it exists
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            // Copy the temp file to the final location synchronously
            try FileManager.default.copyItem(at: location, to: destinationURL)
            
            // Now update UI on main thread
            DispatchQueue.main.async {
                // Update model status
                if let index = self.availableModels.firstIndex(where: { $0.id == modelID }) {
                    self.availableModels[index].status = .downloaded
                    self.availableModels[index].downloadedPath = destinationURL
                }
                
                self.downloadProgress[modelID] = 1.0
                self.downloadTasks.removeValue(forKey: modelID)
                
                // Resume continuation
                if let continuation = self.downloadContinuations.removeValue(forKey: modelID) {
                    continuation.resume()
                }
            }
        } catch {
            print("Error finishing download for model \(modelID): \(error)")
            DispatchQueue.main.async {
                self.updateModelStatus(modelID, to: .failed)
                self.downloadError[modelID] = error.localizedDescription
                self.downloadTasks.removeValue(forKey: modelID)
                
                if let continuation = self.downloadContinuations.removeValue(forKey: modelID) {
                    continuation.resume()
                }
            }
        }
    }
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let modelID = downloadTasks.first(where: { $0.value === downloadTask })?.key else { return }
        
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        
        DispatchQueue.main.async {
            self.downloadProgress[modelID] = progress
        }
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let downloadTask = task as? URLSessionDownloadTask else { return }
        guard let modelID = downloadTasks.first(where: { $0.value === downloadTask })?.key else { return }
        
        if let error = error {
            DispatchQueue.main.async {
                self.updateModelStatus(modelID, to: .failed)
                self.downloadError[modelID] = error.localizedDescription
                self.downloadTasks.removeValue(forKey: modelID)
                
                if let continuation = self.downloadContinuations.removeValue(forKey: modelID) {
                    continuation.resume()
                }
            }
        }
    }
}

enum ModelDownloadError: LocalizedError {
    case modelNotFound
    case downloadFailed(String)
    case invalidURL
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Model not found in registry"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .invalidURL:
            return "Invalid download URL"
        }
    }
}

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
    private var lastProgressUpdate: [String: Date] = [:]
    private var modelIndex: [String: Int] = [:]
    
    override init() {
        // Create models directory: ~/Library/Application Support/com.simpletranscribe/models/
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.modelsDirectory = appSupportURL.appending(path: "com.simpletranscribe/models", directoryHint: .isDirectory)
        
        super.init()
        
        // Initialize URLSession with delegate
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: {
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            queue.name = "com.simpletranscribe.download-delegate"
            return queue
        }())
        
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
        rebuildModelIndex()
    }
    
    /// Download a model by ID
    func downloadModel(_ modelID: String) async throws {
        guard let index = modelIndex[modelID] else {
            throw ModelDownloadError.modelNotFound
        }
        let model = availableModels[index]
        
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
        
        if let index = modelIndex[modelID] {
            availableModels[index].status = .notDownloaded
        }
    }
    
    /// Delete a downloaded model
    func deleteModel(_ modelID: String) throws {
        guard let index = modelIndex[modelID] else {
            throw ModelDownloadError.modelNotFound
        }
        let model = availableModels[index]
        
        if let path = model.downloadedPath {
            try FileManager.default.removeItem(at: path)
        }
        
        availableModels[index].status = .notDownloaded
        availableModels[index].downloadedPath = nil
    }
    
    /// Get a model by ID (O(1) lookup)
    func getModel(_ modelID: String) -> ModelInfo? {
        modelIndex[modelID].map { availableModels[$0] }
    }
    
    /// Get the local path for a model
    func getModelPath(_ modelID: String) -> URL? {
        getModel(modelID)?.downloadedPath
    }
    
    /// Calculate total size of downloaded models
    func totalDownloadedSize() -> Int64 {
        availableModels
            .filter { $0.status == .downloaded }
            .reduce(0) { $0 + ($1.downloadedPath.map { getFileSize($0) } ?? 0) }
    }
    
    // MARK: - Private Helpers
    
    private func updateModelStatus(_ modelID: String, to status: ModelInfo.ModelStatus) {
        if let index = modelIndex[modelID] {
            availableModels[index].status = status
        }
    }
    
    private func rebuildModelIndex() {
        modelIndex = Dictionary(uniqueKeysWithValues: availableModels.enumerated().map { ($1.id, $0) })
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
        // Look up modelID safely from main thread
        var modelID: String?
        DispatchQueue.main.sync {
            modelID = self.downloadTasks.first(where: { $0.value === downloadTask })?.key
        }
        guard let modelID = modelID else { return }
        
        // File copy happens on the background delegate queue (desired for large files)
        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
            
            let destinationURL = modelsDirectory.appending(path: modelID + ".bin")
            
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            try FileManager.default.copyItem(at: location, to: destinationURL)
            
            DispatchQueue.main.async {
                if let index = self.modelIndex[modelID] {
                    self.availableModels[index].status = .downloaded
                    self.availableModels[index].downloadedPath = destinationURL
                }
                
                self.downloadProgress[modelID] = 1.0
                self.downloadTasks.removeValue(forKey: modelID)
                self.lastProgressUpdate.removeValue(forKey: modelID)
                
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
                self.lastProgressUpdate.removeValue(forKey: modelID)
                
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
        var modelID: String?
        DispatchQueue.main.sync {
            modelID = self.downloadTasks.first(where: { $0.value === downloadTask })?.key
        }
        guard let modelID = modelID else { return }
        
        let now = Date()
        let throttleInterval: TimeInterval = 0.2  // 5 Hz max
        
        if let lastUpdate = lastProgressUpdate[modelID],
           now.timeIntervalSince(lastUpdate) < throttleInterval {
            return
        }
        lastProgressUpdate[modelID] = now
        
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
        var modelID: String?
        DispatchQueue.main.sync {
            modelID = self.downloadTasks.first(where: { $0.value === downloadTask })?.key
        }
        guard let modelID = modelID else { return }
        
        if let error = error {
            DispatchQueue.main.async {
                self.updateModelStatus(modelID, to: .failed)
                self.downloadError[modelID] = error.localizedDescription
                self.downloadTasks.removeValue(forKey: modelID)
                self.lastProgressUpdate.removeValue(forKey: modelID)
                
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

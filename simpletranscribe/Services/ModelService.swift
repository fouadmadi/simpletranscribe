import Foundation
import Observation
import os
import CryptoKit

/// Manages model downloads, discovery, and lifecycle
@Observable
final class ModelService: NSObject, URLSessionDownloadDelegate {
    private let logger = Logger(subsystem: "com.simpletranscribe", category: "ModelService")
    
    var availableModels: [ModelInfo] = []
    var downloadProgress: [String: Double] = [:]
    var downloadError: [String: String] = [:]
    
    private let modelsDirectory: URL
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var downloadContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var urlSession: URLSession!
    private var lastProgressUpdate: [String: Date] = [:]
    private var modelIndex: [String: Int] = [:]
    // Thread-safe reverse lookup: task identifier -> model ID (written on main, read on delegate queue)
    private var taskToModelID: [Int: String] = [:]
    private let taskMapLock = NSLock()
    
    override init() {
        // Create models directory: ~/Library/Application Support/com.simpletranscribe/models/
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.modelsDirectory = appSupportURL.appending(path: "com.simpletranscribe/models", directoryHint: .isDirectory)
        
        super.init()
        
        // Initialize URLSession with delegate
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.waitsForConnectivity = true
        sessionConfig.timeoutIntervalForRequest = 30
        sessionConfig.timeoutIntervalForResource = 3600 // 1 hour max for large models
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
                        language: "unknown",
                        sha256: nil
                    )
                    customModel.status = .downloaded
                    customModel.downloadedPath = url
                    models.append(customModel)
                }
            }
        } catch {
            logger.error("Error discovering custom models: \(error, privacy: .public)")
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
            taskMapLock.lock()
            taskToModelID[task.taskIdentifier] = modelID
            taskMapLock.unlock()
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
    
    /// Thread-safe lookup of model ID from a download task identifier
    private func modelID(for taskIdentifier: Int) -> String? {
        taskMapLock.lock()
        defer { taskMapLock.unlock() }
        return taskToModelID[taskIdentifier]
    }
    
    /// Clean up task mapping after download completes or fails
    private func removeTaskMapping(for taskIdentifier: Int) {
        taskMapLock.lock()
        taskToModelID.removeValue(forKey: taskIdentifier)
        taskMapLock.unlock()
    }
    
    private func getFileSize(_ url: URL) -> Int64 {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    /// Compute SHA256 hash of a file using streaming reads to avoid loading large models into memory
    private func sha256OfFile(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
        
        var hasher = SHA256()
        let bufferSize = 1024 * 1024 // 1 MB chunks
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: bufferSize)
            guard !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}
        
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Verify downloaded file matches expected SHA256 hash
    private func verifyFileIntegrity(at url: URL, expectedHash: String?) throws {
        guard let expectedHash = expectedHash, !expectedHash.isEmpty else { return }
        
        let actualHash = try sha256OfFile(at: url)
        guard actualHash == expectedHash else {
            throw ModelDownloadError.hashMismatch(expected: expectedHash, actual: actualHash)
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let modelID = modelID(for: downloadTask.taskIdentifier) else { return }
        
        // File copy happens on the background delegate queue (desired for large files)
        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
            
            let destinationURL = modelsDirectory.appending(path: modelID + ".bin")
            
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            try FileManager.default.copyItem(at: location, to: destinationURL)
            
            // Verify file integrity using SHA256 hash
            let expectedHash: String? = {
                taskMapLock.lock()
                defer { taskMapLock.unlock() }
                // sha256 is immutable, safe to read from background queue
                return KnownModels.model(withID: modelID)?.sha256
            }()
            try self.verifyFileIntegrity(at: destinationURL, expectedHash: expectedHash)
            
            DispatchQueue.main.async {
                if let index = self.modelIndex[modelID] {
                    self.availableModels[index].status = .downloaded
                    self.availableModels[index].downloadedPath = destinationURL
                }
                
                self.downloadProgress[modelID] = 1.0
                self.downloadTasks.removeValue(forKey: modelID)
                self.lastProgressUpdate.removeValue(forKey: modelID)
                self.removeTaskMapping(for: downloadTask.taskIdentifier)
                
                if let continuation = self.downloadContinuations.removeValue(forKey: modelID) {
                    continuation.resume()
                }
            }
        } catch {
            logger.error("Error finishing download for model \(modelID, privacy: .public): \(error, privacy: .public)")
            DispatchQueue.main.async {
                self.updateModelStatus(modelID, to: .failed)
                self.downloadError[modelID] = error.localizedDescription
                self.downloadTasks.removeValue(forKey: modelID)
                self.lastProgressUpdate.removeValue(forKey: modelID)
                self.removeTaskMapping(for: downloadTask.taskIdentifier)
                
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
        guard let modelID = modelID(for: downloadTask.taskIdentifier) else { return }
        
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
        guard let modelID = modelID(for: downloadTask.taskIdentifier) else { return }
        
        if let error = error {
            DispatchQueue.main.async {
                self.updateModelStatus(modelID, to: .failed)
                self.downloadError[modelID] = error.localizedDescription
                self.downloadTasks.removeValue(forKey: modelID)
                self.lastProgressUpdate.removeValue(forKey: modelID)
                self.removeTaskMapping(for: downloadTask.taskIdentifier)
                
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
    case hashMismatch(expected: String, actual: String)
    
    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "Model not found in registry"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .invalidURL:
            return "Invalid download URL"
        case .hashMismatch(let expected, let actual):
            return "File integrity check failed (expected \(expected.prefix(8))…, got \(actual.prefix(8))…)"
        }
    }
}

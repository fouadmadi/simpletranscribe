import Foundation
import Observation
import os
import CryptoKit

/// Manages model downloads, discovery, and lifecycle
@Observable
final class ModelService: NSObject, URLSessionDownloadDelegate {
    private let logger = Logger(subsystem: "com.simpletranscribe", category: "ModelService")
    
    var availableModels: [ModelInfo] = []
    var downloadProgress: [String: DownloadProgress] = [:]
    var downloadError: [String: String] = [:]
    
    private let modelsDirectory: URL
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var directoryDownloadTasks: [String: Task<Void, Error>] = [:]
    private var downloadContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var urlSession: URLSession!
    private var lastProgressUpdate: [String: Date] = [:]
    private var speedSamples: [String: [SpeedSample]] = [:]
    private let speedWindowSeconds: TimeInterval = 5.0
    private var modelIndex: [String: Int] = [:]
    // Thread-safe reverse lookup: task identifier -> model ID (written on main, read on delegate queue)
    private var taskToModelID: [Int: String] = [:]
    private let taskMapLock = NSLock()

    private struct SpeedSample {
        let timestamp: Date
        let bytes: Int64
    }
    
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
        
        // Download missing Core ML encoders for already-downloaded whisper models
        Task { await ensureCoreMlEncoders() }
    }
    
    /// Load and initialize available models
    func loadAvailableModels() {
        var models = KnownModels.all
        
        // Check which models are already downloaded
        for i in 0..<models.count {
            if models[i].isDirectory {
                // Directory-based models (Parakeet): check that directory exists and all files are present
                let modelDir = modelsDirectory.appending(path: models[i].id, directoryHint: .isDirectory)
                if isDirectoryModelComplete(modelDir, files: models[i].files) {
                    models[i].status = .downloaded
                    models[i].downloadedPath = modelDir
                }
            } else {
                // Single-file models (Whisper): check for .bin file
                let modelURL = modelsDirectory.appending(path: models[i].id + ".bin")
                if FileManager.default.fileExists(atPath: modelURL.path) {
                    models[i].status = .downloaded
                    models[i].downloadedPath = modelURL
                }
            }
        }
        
        // Discover custom .bin files in the models directory (validate format before accepting)
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil)
            for url in contents where url.pathExtension == "bin" {
                let modelID = url.deletingPathExtension().lastPathComponent
                // Only add if not already in the known models list
                if !models.contains(where: { $0.id == modelID }) {
                    guard isValidGGMLFile(at: url) else {
                        logger.debug("Skipping unrecognized file: \(url.lastPathComponent, privacy: .public)")
                        continue
                    }
                    var customModel = ModelInfo(
                        id: modelID,
                        name: modelID,
                        description: "Custom model",
                        size: getFileSize(url),
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
    
    /// Check if all files in a directory-based model are present
    private func isDirectoryModelComplete(_ dir: URL, files: [ModelFile]) -> Bool {
        guard !files.isEmpty else { return false }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        return files.allSatisfy { file in
            FileManager.default.fileExists(atPath: dir.appending(path: file.filename).path)
        }
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
        downloadError.removeValue(forKey: modelID)
        resetProgressTracking(for: modelID, totalBytes: model.size)
        
        if model.isDirectory && !model.files.isEmpty {
            // Directory-based model: stream each file into a subdirectory so progress can report speed and ETA.
            let task = Task {
                try await downloadDirectoryModel(modelID: modelID, model: model)
            }
            directoryDownloadTasks[modelID] = task
            defer { directoryDownloadTasks.removeValue(forKey: modelID) }
            do {
                try await task.value
            } catch is CancellationError {
                return
            } catch {
                logger.error("Directory model download failed for \(modelID, privacy: .public): \(error, privacy: .public)")
                return
            }
        } else {
            // Single-file model: use URLSession download delegate
            await withCheckedContinuation { continuation in
                let task = urlSession.downloadTask(with: model.downloadURL)
                downloadTasks[modelID] = task
                downloadContinuations[modelID] = continuation
                taskMapLock.lock()
                taskToModelID[task.taskIdentifier] = modelID
                taskMapLock.unlock()
                task.resume()
            }
            
            // After .bin download, fetch Core ML encoder for hardware-accelerated inference
            if let index = modelIndex[modelID],
               availableModels[index].status == .downloaded,
               let zipURL = model.coreMlEncoderZipURL {
                await downloadCoreMlEncoder(modelID: modelID, zipURL: zipURL)
            }
        }
    }
    
    /// Download a directory-based model (multiple files into a subdirectory)
    private func downloadDirectoryModel(modelID: String, model: ModelInfo) async throws {
        let modelDir = modelsDirectory.appending(path: modelID, directoryHint: .isDirectory)
        let tempDir = modelsDirectory.appending(path: modelID + ".downloading", directoryHint: .isDirectory)
        let fileManager = FileManager.default

        try? fileManager.removeItem(at: tempDir)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let totalSize = model.files.reduce(0) { $0 + $1.size }
        var downloadedBytes: Int64 = 0
        let bufferSize = 64 * 1024

        do {
            for file in model.files {
                try Task.checkCancellation()

                let destinationURL = tempDir.appending(path: file.filename)
                fileManager.createFile(atPath: destinationURL.path, contents: nil)
                let handle = try FileHandle(forWritingTo: destinationURL)
                var buffer = Data()
                buffer.reserveCapacity(bufferSize)
                var fileBytes: Int64 = 0

                do {
                    let request = URLRequest(url: file.downloadURL, timeoutInterval: 3600)
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)

                    for try await byte in bytes {
                        try Task.checkCancellation()
                        buffer.append(byte)
                        fileBytes += 1
                        downloadedBytes += 1

                        if buffer.count >= bufferSize {
                            try handle.write(contentsOf: buffer)
                            buffer.removeAll(keepingCapacity: true)
                        }

                        let now = Date()
                        if now.timeIntervalSince(lastProgressUpdate[modelID] ?? .distantPast) >= 1.0 {
                            lastProgressUpdate[modelID] = now
                            let progress = buildDownloadProgress(
                                for: modelID,
                                receivedBytes: downloadedBytes,
                                totalBytes: totalSize,
                                now: now
                            )
                            await MainActor.run {
                                self.downloadProgress[modelID] = progress
                            }
                        }
                    }

                    if !buffer.isEmpty {
                        try handle.write(contentsOf: buffer)
                    }
                    try handle.close()
                } catch {
                    try? handle.close()
                    throw error
                }

                logger.debug("Downloaded \(fileBytes, privacy: .public) bytes for \(file.filename, privacy: .public)")
                try verifyFileIntegrity(at: destinationURL, expectedHash: file.sha256)
            }

            if fileManager.fileExists(atPath: modelDir.path) {
                try fileManager.removeItem(at: modelDir)
            }
            try fileManager.moveItem(at: tempDir, to: modelDir)

            await MainActor.run {
                if let index = self.modelIndex[modelID] {
                    self.availableModels[index].status = .downloaded
                    self.availableModels[index].downloadedPath = modelDir
                }
                self.downloadError.removeValue(forKey: modelID)
                self.downloadProgress[modelID] = DownloadProgress(
                    fraction: 1.0,
                    bytesPerSecond: self.downloadProgress[modelID]?.bytesPerSecond ?? 0,
                    totalBytes: totalSize,
                    receivedBytes: totalSize
                )
            }
        } catch {
            try? fileManager.removeItem(at: tempDir)

            await MainActor.run {
                if error is CancellationError {
                    self.updateModelStatus(modelID, to: .notDownloaded)
                    self.downloadError.removeValue(forKey: modelID)
                } else {
                    self.updateModelStatus(modelID, to: .failed)
                    self.downloadError[modelID] = error.localizedDescription
                }
                self.clearProgressTracking(for: modelID)
            }
            throw error
        }
    }
    
    /// Cancel an ongoing download
    func cancelDownload(_ modelID: String) {
        downloadTasks[modelID]?.cancel()
        downloadTasks.removeValue(forKey: modelID)
        directoryDownloadTasks[modelID]?.cancel()
        directoryDownloadTasks.removeValue(forKey: modelID)
        clearProgressTracking(for: modelID)
        downloadError.removeValue(forKey: modelID)

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
        
        // Also clean up temp download directory if it exists
        let tempDir = modelsDirectory.appending(path: modelID + ".downloading")
        try? FileManager.default.removeItem(at: tempDir)
        
        availableModels[index].status = .notDownloaded
        availableModels[index].downloadedPath = nil
        clearProgressTracking(for: modelID)
        downloadError.removeValue(forKey: modelID)
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
    
    /// Downloads and extracts the Core ML encoder zip for a whisper model.
    /// Only runs on Apple Silicon — Core ML encoders use MPSGraph ops that fail on Intel Macs.
    /// Non-fatal: if this fails, whisper.cpp falls back to CPU inference.
    private func downloadCoreMlEncoder(modelID: String, zipURL: URL) async {
        #if arch(arm64)
        let encoderName = modelID + "-encoder.mlmodelc"
        let encoderDir = modelsDirectory.appending(path: encoderName, directoryHint: .isDirectory)
        
        guard !FileManager.default.fileExists(atPath: encoderDir.path) else {
            logger.debug("Core ML encoder already present for \(modelID, privacy: .public)")
            return
        }
        
        logger.info("Downloading Core ML encoder for \(modelID, privacy: .public)")
        DiagnosticLogger.shared.log("Downloading CoreML encoder: \(modelID)", category: "CoreML")
        let tempZip = modelsDirectory.appending(path: encoderName + ".zip")
        do {
            let (downloadedURL, _) = try await URLSession.shared.download(from: zipURL)
            try? FileManager.default.removeItem(at: tempZip)
            try FileManager.default.moveItem(at: downloadedURL, to: tempZip)
            
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-o", tempZip.path, "-d", modelsDirectory.path]
            unzip.standardOutput = FileHandle.nullDevice
            unzip.standardError = FileHandle.nullDevice
            try unzip.run()
            unzip.waitUntilExit()
            
            try? FileManager.default.removeItem(at: tempZip)
            
            if FileManager.default.fileExists(atPath: encoderDir.path) {
                logger.info("Core ML encoder ready for \(modelID, privacy: .public)")
                DiagnosticLogger.shared.log("CoreML encoder ready: \(modelID)", category: "CoreML")
            } else {
                logger.warning("Core ML encoder zip extracted but directory not found for \(modelID, privacy: .public)")
                DiagnosticLogger.shared.log("CoreML encoder extraction incomplete: \(modelID)", category: "CoreML")
            }
        } catch {
            try? FileManager.default.removeItem(at: tempZip)
            logger.warning("Core ML encoder download failed for \(modelID, privacy: .public): \(error, privacy: .public)")
            DiagnosticLogger.shared.log("CoreML encoder download failed (\(modelID)): \(error.localizedDescription)", category: "CoreML")
        }
        #endif
    }
    
    /// Ensures Core ML encoders are in the correct state for all downloaded whisper models.
    /// On Apple Silicon: downloads missing encoders for hardware-accelerated inference.
    /// On Intel: removes any encoders that were previously downloaded, because Core ML
    /// uses MPSGraph ops that are incompatible with Intel Macs and cause inference failures.
    func ensureCoreMlEncoders() async {
        #if arch(arm64)
        DiagnosticLogger.shared.log("Checking CoreML encoders (Apple Silicon)", category: "CoreML")
        let whisperModels = availableModels.filter {
            $0.modelType == .whisper &&
            $0.status == .downloaded &&
            $0.coreMlEncoderZipURL != nil
        }
        for model in whisperModels {
            guard let zipURL = model.coreMlEncoderZipURL else { continue }
            await downloadCoreMlEncoder(modelID: model.id, zipURL: zipURL)
        }
        #else
        // Remove any Core ML encoders that may have been downloaded on this Intel Mac.
        // Their presence causes whisper.cpp to attempt Core ML inference, which fails
        // with MPSGraph errors and -10877, making transcription non-functional.
        DiagnosticLogger.shared.log("Intel Mac detected — removing incompatible CoreML encoders", category: "CoreML")
        removeCoreMlEncoders()
        #endif
    }

    private func removeCoreMlEncoders() {
        let whisperModels = availableModels.filter { $0.modelType == .whisper }
        for model in whisperModels {
            let encoderDir = modelsDirectory.appending(
                path: model.id + "-encoder.mlmodelc",
                directoryHint: .isDirectory
            )
            guard FileManager.default.fileExists(atPath: encoderDir.path) else { continue }
            do {
                try FileManager.default.removeItem(at: encoderDir)
                logger.info("Removed incompatible Core ML encoder on Intel Mac: \(model.id, privacy: .public)")
                DiagnosticLogger.shared.log("Removed Intel-incompatible CoreML encoder: \(model.id)", category: "CoreML")
            } catch {
                logger.warning("Failed to remove Core ML encoder \(model.id, privacy: .public): \(error, privacy: .public)")
                DiagnosticLogger.shared.log("Failed to remove CoreML encoder (\(model.id)): \(error.localizedDescription)", category: "CoreML")
            }
        }
    }

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

    private func resetProgressTracking(for modelID: String, totalBytes: Int64) {
        lastProgressUpdate[modelID] = .distantPast
        speedSamples[modelID] = []
        downloadProgress[modelID] = DownloadProgress(
            fraction: 0,
            bytesPerSecond: 0,
            totalBytes: totalBytes,
            receivedBytes: 0
        )
    }

    private func clearProgressTracking(for modelID: String) {
        downloadProgress.removeValue(forKey: modelID)
        lastProgressUpdate.removeValue(forKey: modelID)
        speedSamples.removeValue(forKey: modelID)
    }

    private func buildDownloadProgress(
        for modelID: String,
        receivedBytes: Int64,
        totalBytes: Int64,
        now: Date = Date()
    ) -> DownloadProgress {
        let speed = computeSpeed(for: modelID, latestBytes: receivedBytes, now: now)
        let fraction = totalBytes > 0 ? Double(receivedBytes) / Double(totalBytes) : 0
        return DownloadProgress(
            fraction: fraction,
            bytesPerSecond: speed,
            totalBytes: totalBytes,
            receivedBytes: receivedBytes
        )
    }

    private func computeSpeed(for modelID: String, latestBytes: Int64, now: Date) -> Double {
        var samples = speedSamples[modelID] ?? []
        samples.append(SpeedSample(timestamp: now, bytes: latestBytes))
        samples.removeAll { now.timeIntervalSince($0.timestamp) > speedWindowSeconds }
        speedSamples[modelID] = samples

        guard samples.count >= 2, let first = samples.first else { return 0 }
        let elapsed = now.timeIntervalSince(first.timestamp)
        guard elapsed > 0 else { return 0 }
        return Double(latestBytes - first.bytes) / elapsed
    }
    
    /// Validate that a file has a recognized GGML magic header
    private func isValidGGMLFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { handle.closeFile() }
        
        let headerData = handle.readData(ofLength: 4)
        guard headerData.count == 4 else { return false }
        
        let magic = headerData.withUnsafeBytes { $0.load(as: UInt32.self) }
        // Known GGML magic numbers: 0x67676d6c ("ggml"), 0x67676d66 ("ggmf"), 0x67676a74 ("ggjt")
        let validMagics: Set<UInt32> = [0x67676d6c, 0x67676d66, 0x67676a74]
        return validMagics.contains(magic)
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

                let totalBytes = self.getFileSize(destinationURL)
                self.downloadError.removeValue(forKey: modelID)
                self.downloadProgress[modelID] = DownloadProgress(
                    fraction: 1.0,
                    bytesPerSecond: self.downloadProgress[modelID]?.bytesPerSecond ?? 0,
                    totalBytes: totalBytes,
                    receivedBytes: totalBytes
                )
                self.downloadTasks.removeValue(forKey: modelID)
                self.lastProgressUpdate.removeValue(forKey: modelID)
                self.speedSamples.removeValue(forKey: modelID)
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
                self.clearProgressTracking(for: modelID)
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
        let throttleInterval: TimeInterval = 1.0

        if let lastUpdate = lastProgressUpdate[modelID],
           now.timeIntervalSince(lastUpdate) < throttleInterval {
            return
        }
        lastProgressUpdate[modelID] = now

        let totalBytes = max(totalBytesExpectedToWrite, 0)
        let progress = self.buildDownloadProgress(
            for: modelID,
            receivedBytes: totalBytesWritten,
            totalBytes: totalBytes,
            now: now
        )

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
            let isCancelled = (error as NSError).code == NSURLErrorCancelled
            DispatchQueue.main.async {
                self.updateModelStatus(modelID, to: isCancelled ? .notDownloaded : .failed)
                if isCancelled {
                    self.downloadError.removeValue(forKey: modelID)
                } else {
                    self.downloadError[modelID] = error.localizedDescription
                }
                self.downloadTasks.removeValue(forKey: modelID)
                self.clearProgressTracking(for: modelID)
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

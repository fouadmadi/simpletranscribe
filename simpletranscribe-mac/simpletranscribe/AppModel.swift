import SwiftUI
import Observation
import AVFoundation
import ApplicationServices
import os

@Observable
class AppModel {
    private static let logger = Logger(subsystem: "com.simpletranscribe", category: "AppModel")

    // Thread-safe flag for audio callback (read from AVAudioEngine's I/O thread)
    private let recordingLock = NSLock()
    private var _isRecordingAtomic: Bool = false

    var isRecording: Bool = false {
        didSet {
            recordingLock.lock()
            _isRecordingAtomic = isRecording
            recordingLock.unlock()
        }
    }
    var transcribedText: String = ""
    var selectedLanguage: String = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "en" {
        didSet { UserDefaults.standard.set(selectedLanguage, forKey: "selectedLanguage") }
    }
    var selectedModelID: String = UserDefaults.standard.string(forKey: "selectedModelID") ?? "" {
        didSet { UserDefaults.standard.set(selectedModelID, forKey: "selectedModelID") }
    }
    var selectedInputDevice: AVCaptureDevice? {
        didSet { UserDefaults.standard.set(selectedInputDevice?.uniqueID, forKey: "selectedInputDeviceID") }
    }
    var availableInputDevices: [AVCaptureDevice] = []
    
    // Model management
    let modelService = ModelService()
    
    // Status properties
    var isProcessing: Bool = false
    var errorMessage: String? = nil
    // Feedback properties
    var showTranscriptionStarted: Bool = false
    var overlayState: OverlayState = .idle

    // Properties moved from ContentView
    var modelLoaded = false
    var isLoadingModel = false
    var accessibilityGranted = false

    // Service references (set during app startup)
    var audioManager: AudioManager?
    var transcriptionManager: TranscriptionManager?

    // Track the app the user was in when recording started (for paste-back)
    @ObservationIgnored private var previousApp: NSRunningApplication?

    var currentModel: ModelInfo? {
        modelService.getModel(selectedModelID)
    }

    var hasDownloadedModels: Bool {
        modelService.availableModels.contains { $0.isAvailable }
    }

    var canRecord: Bool {
        modelLoaded && currentModel?.isAvailable == true
    }

    var isTranscribing: Bool {
        transcriptionManager?.isTranscribing ?? false
    }

    init() {
        // ModelService.init() already calls loadAvailableModels().
        // Audio device discovery is deferred to setup() to avoid
        // blocking app activation with Core Audio initialization.
        
        // If we have a persisted model that's still valid, use it; otherwise pick default
        if selectedModelID.isEmpty || modelService.getModel(selectedModelID)?.isAvailable != true {
            selectDefaultModel()
        }
    }
    
    /// Call after app has fully activated to initialize audio hardware.
    /// Runs Core Audio discovery on a background thread to avoid blocking the UI.
    func setup() {
        let savedDeviceID = UserDefaults.standard.string(forKey: "selectedInputDeviceID")
        
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInMicrophone, .externalUnknown],
                mediaType: .audio,
                position: .unspecified
            )
            let devices = discoverySession.devices
            let restoredDevice = devices.first(where: { $0.uniqueID == savedDeviceID })
            let defaultDevice = restoredDevice ?? AVCaptureDevice.default(for: .audio) ?? devices.first
            
            DispatchQueue.main.async {
                self.availableInputDevices = devices
                if self.selectedInputDevice == nil {
                    self.selectedInputDevice = defaultDevice
                }
            }
        }
    }
    
    /// Select the first downloaded model, or empty string if none are available
    func selectDefaultModel() {
        let downloadedModels = modelService.availableModels.filter { $0.isAvailable }
        if let firstDownloaded = downloadedModels.first {
            self.selectedModelID = firstDownloaded.id
        } else {
            self.selectedModelID = ""
        }
    }
    
    func refreshAudioDevices() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        
        // Filter out devices without names (sometimes virtual/aggregate devices appear without recognizable info)
        self.availableInputDevices = discoverySession.devices
        if self.selectedInputDevice == nil {
            self.selectedInputDevice = AVCaptureDevice.default(for: .audio) ?? self.availableInputDevices.first
        }
    }

    // MARK: - Service Setup

    func setupAudio() {
        audioManager?.onBufferReceived = { [weak self] buffer in
            guard let self else { return }
            self.recordingLock.lock()
            let recording = self._isRecordingAtomic
            self.recordingLock.unlock()
            if recording {
                self.transcriptionManager?.appendAudio(buffer: buffer)
            }
        }
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Model Loading

    func loadModelAsync() async {
        guard !selectedModelID.isEmpty else {
            modelLoaded = false
            return
        }

        guard let modelPath = modelService.getModelPath(selectedModelID) else {
            errorMessage = "Model file not found. Download it from the Models tab."
            modelLoaded = false
            return
        }

        isLoadingModel = true
        modelLoaded = false
        errorMessage = nil

        do {
            try await transcriptionManager?.loadModel(modelPath: modelPath)
            modelLoaded = true
            isLoadingModel = false
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            modelLoaded = false
            isLoadingModel = false
        }
    }

    func loadModel() {
        Task { @MainActor in
            await loadModelAsync()
        }
    }

    // MARK: - Recording

    func handleHotKey(pressed: Bool) {
        if pressed {
            startRecording()
        } else if isRecording {
            Self.logger.debug("hotkey released, stopping recording (autoPaste=true)")
            stopRecordingAndTranscribe(autoPaste: true)
        }
    }

    func startRecording() {
        guard canRecord, !isRecording, !isProcessing else { return }
        guard let audioManager, let transcriptionManager else { return }

        errorMessage = nil
        // Remember which app the user is in so we can paste back into it
        previousApp = NSWorkspace.shared.frontmostApplication
        audioManager.requestMicrophoneAccess { [weak self] granted in
            guard let self, granted else {
                self?.errorMessage = "Microphone access denied."
                self?.overlayState = .error("Mic access denied")
                self?.autoClearOverlay(after: 3.0)
                return
            }

            do {
                self.transcribedText = ""
                transcriptionManager.startTranscription(language: self.selectedLanguage)
                self.isRecording = true
                self.showTranscriptionStarted = true
                self.overlayState = .recording
                try audioManager.startRecording(device: self.selectedInputDevice)
                SoundManager.playRecordingStarted()
            } catch {
                self.errorMessage = "Failed to start recording: \(error.localizedDescription)"
                self.isRecording = false
                self.showTranscriptionStarted = false
                self.overlayState = .error("Recording failed")
                self.autoClearOverlay(after: 3.0)
                SoundManager.playError()
            }
        }
    }

    func stopRecordingAndTranscribe(autoPaste: Bool = false) {
        guard let audioManager, let transcriptionManager else { return }

        audioManager.stopRecording()
        isRecording = false
        isProcessing = true
        errorMessage = nil
        showTranscriptionStarted = false
        overlayState = .transcribing

        Task { @MainActor in
            do {
                let text = try await transcriptionManager.processAudio { _ in }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                Self.logger.debug("transcription result length: \(trimmed.count, privacy: .public) (autoPaste=\(autoPaste, privacy: .public))")

                if !trimmed.isEmpty {
                    if transcribedText.isEmpty {
                        transcribedText = trimmed
                    } else {
                        transcribedText += " " + trimmed
                    }
                }

                isProcessing = false
                overlayState = .done
                autoClearOverlay(after: 1.5)
                SoundManager.playTranscriptionComplete()

                if autoPaste && !trimmed.isEmpty {
                    // Re-activate the app the user was in before recording
                    if let target = self.previousApp, !target.isTerminated {
                        target.activate()
                    }
                    PasteService.copyAndPaste(trimmed)
                }
            } catch {
                Self.logger.error("transcription error: \(error, privacy: .public)")
                errorMessage = "Transcription failed: \(error.localizedDescription)"
                isProcessing = false
                overlayState = .error("Transcription failed")
                autoClearOverlay(after: 3.0)
                SoundManager.playError()
            }
        }
    }

    func toggleRecording() {
        if isRecording {
            stopRecordingAndTranscribe(autoPaste: false)
        } else {
            startRecording()
        }
    }

    // MARK: - Overlay Helpers

    private var overlayClearWorkItem: DispatchWorkItem?

    private func autoClearOverlay(after seconds: TimeInterval) {
        overlayClearWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.overlayState = .idle
        }
        overlayClearWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

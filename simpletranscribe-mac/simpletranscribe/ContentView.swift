import SwiftUI
import AVFoundation
import ApplicationServices
import os

struct ContentView: View {
    private static let logger = Logger(subsystem: "com.simpletranscribe", category: "ContentView")

    @State private var appModel = AppModel()
    @State private var audioManager = AudioManager()
    @StateObject private var transcriptionManager = TranscriptionManager()
    @Environment(HotKeyManager.self) private var hotKeyManager

    @State private var showCopiedAlert = false
    @State private var showModelManager = false
    @State private var accessibilityGranted = false
    @State private var modelLoaded = false
    @State private var isLoadingModel = false

    var currentModel: ModelInfo? {
        appModel.modelService.getModel(appModel.selectedModelID)
    }

    var hasDownloadedModels: Bool {
        appModel.modelService.availableModels.contains { $0.isAvailable }
    }

    var canRecord: Bool {
        modelLoaded && currentModel?.isAvailable == true
    }

    var body: some View {
        VStack(spacing: 0) {
            RecordingControlsView(
                isRecording: appModel.isRecording,
                isProcessing: appModel.isProcessing,
                isTranscribing: transcriptionManager.isTranscribing,
                canRecord: canRecord,
                isLoadingModel: isLoadingModel,
                showTranscriptionStarted: appModel.showTranscriptionStarted,
                onToggleRecording: toggleRecording,
                onShowModelManager: { showModelManager = true }
            )

            Divider()

            SettingsAreaView(
                selectedInputDevice: $appModel.selectedInputDevice,
                selectedModelID: $appModel.selectedModelID,
                selectedLanguage: $appModel.selectedLanguage,
                availableInputDevices: appModel.availableInputDevices,
                downloadedModels: appModel.modelService.availableModels.filter { $0.isAvailable }
            )

            Divider()

            TranscriptResultsView(
                transcribedText: $appModel.transcribedText,
                showCopiedAlert: $showCopiedAlert,
                onCopy: copyToClipboard
            )

            modelStatusBanner
            errorBanner
            accessibilityBanner
        }
        .frame(minWidth: 600, minHeight: 500)
        .task {
            appModel.setup()
            hotKeyManager.setup()
            setupAudio()
            requestAccessibilityPermission()

            if !appModel.selectedModelID.isEmpty,
               currentModel?.isAvailable == true {
                await loadModelAsync()
            }
        }
        .onChange(of: appModel.selectedModelID) { oldValue, newValue in
            modelLoaded = false
            appModel.errorMessage = nil
            if !newValue.isEmpty,
               appModel.modelService.getModel(newValue)?.isAvailable == true {
                loadModel()
            }
        }
        .sheet(isPresented: $showModelManager) {
            ModelDownloadView(appModel: appModel)
                .frame(minWidth: 700, minHeight: 600)
                .onDisappear {
                    appModel.selectDefaultModel()
                }
        }
        .onChange(of: hotKeyManager.isHotKeyPressed) { _, pressed in
            handleHotKey(pressed: pressed)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = AXIsProcessTrusted()
        }
    }

    // MARK: - Status Banners

    @ViewBuilder
    private var modelStatusBanner: some View {
        if isLoadingModel {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Loading model...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
            .background(Color.blue.opacity(0.1))
        } else if !modelLoaded && hasDownloadedModels {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(.accentColor)
                Text("Model not loaded. Click to load manually.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Load Model") {
                    loadModel()
                }
                .buttonStyle(.borderedProminent)
                .font(.caption)
                .disabled(appModel.selectedModelID.isEmpty)
            }
            .padding()
            .background(Color.accentColor.opacity(0.08))
        } else if !modelLoaded {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.orange)
                Text("No models downloaded. Download a model to get started.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Download") {
                    showModelManager = true
                }
                .buttonStyle(.borderedProminent)
                .font(.caption)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = appModel.errorMessage {
            Text(error)
                .foregroundColor(.red)
                .font(.caption)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var accessibilityBanner: some View {
        if !accessibilityGranted {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Accessibility permission needed for paste-at-cursor")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Open Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.caption)
                }
                Text("In Settings → Accessibility, click + and add this app.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
        }
    }

    // MARK: - Audio & Model

    private func setupAudio() {
        audioManager.onBufferReceived = { buffer in
            if appModel.isRecording {
                transcriptionManager.appendAudio(buffer: buffer)
            }
        }
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    private func loadModelAsync() async {
        guard !appModel.selectedModelID.isEmpty else {
            modelLoaded = false
            return
        }

        guard let modelPath = appModel.modelService.getModelPath(appModel.selectedModelID) else {
            appModel.errorMessage = "Model file not found. Download it from the Models tab."
            modelLoaded = false
            return
        }

        isLoadingModel = true
        modelLoaded = false
        appModel.errorMessage = nil

        do {
            try await transcriptionManager.loadModel(modelPath: modelPath)
            modelLoaded = true
            isLoadingModel = false
            appModel.errorMessage = nil
        } catch {
            appModel.errorMessage = "Failed to load model: \(error.localizedDescription)"
            modelLoaded = false
            isLoadingModel = false
        }
    }

    private func loadModel() {
        Task {
            await loadModelAsync()
        }
    }

    // MARK: - Recording

    private func handleHotKey(pressed: Bool) {
        if pressed {
            startRecording()
        } else if appModel.isRecording {
            Self.logger.debug("hotkey released, stopping recording (autoPaste=true)")
            stopRecordingAndTranscribe(autoPaste: true)
        }
    }

    private func startRecording() {
        guard canRecord, !appModel.isRecording, !appModel.isProcessing else { return }

        appModel.errorMessage = nil
        audioManager.requestMicrophoneAccess { granted in
            guard granted else {
                appModel.errorMessage = "Microphone access denied."
                return
            }

            do {
                transcriptionManager.startTranscription(language: appModel.selectedLanguage)
                appModel.isRecording = true
                appModel.showTranscriptionStarted = true
                try audioManager.startRecording(device: appModel.selectedInputDevice)
                SoundManager.playRecordingStarted()
            } catch {
                appModel.errorMessage = "Failed to start recording: \(error.localizedDescription)"
                appModel.isRecording = false
                appModel.showTranscriptionStarted = false
                SoundManager.playError()
            }
        }
    }

    private func stopRecordingAndTranscribe(autoPaste: Bool = false) {
        audioManager.stopRecording()
        appModel.isRecording = false
        appModel.isProcessing = true
        appModel.errorMessage = nil
        appModel.showTranscriptionStarted = false

        Task {
            do {
                let text = try await transcriptionManager.processAudio { _ in }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                Self.logger.debug("transcription result length: \(trimmed.count, privacy: .public) (autoPaste=\(autoPaste, privacy: .public))")

                if !trimmed.isEmpty {
                    if appModel.transcribedText.isEmpty {
                        appModel.transcribedText = trimmed
                    } else {
                        appModel.transcribedText += " " + trimmed
                    }
                }

                appModel.isProcessing = false
                SoundManager.playTranscriptionComplete()

                if autoPaste && !trimmed.isEmpty {
                    PasteService.copyAndPaste(trimmed)
                }
            } catch {
                Self.logger.error("transcription error: \(error, privacy: .public)")
                appModel.errorMessage = "Transcription failed: \(error.localizedDescription)"
                appModel.isProcessing = false
                SoundManager.playError()
            }
        }
    }

    private func toggleRecording() {
        if appModel.isRecording {
            stopRecordingAndTranscribe(autoPaste: false)
        } else {
            startRecording()
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(appModel.transcribedText, forType: .string)

        showCopiedAlert = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopiedAlert = false
        }
    }
}


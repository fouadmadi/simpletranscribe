import SwiftUI
import AVFoundation
import ApplicationServices

struct ContentView: View {
    @State private var appModel = AppModel()
    @State private var audioManager = AudioManager()
    @StateObject private var transcriptionManager = TranscriptionManager()
    @Environment(HotKeyManager.self) private var hotKeyManager
    
    // For copy to clipboard alert
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
            // Header: Controls
            HStack {
                Button(action: toggleRecording) {
                    HStack {
                        Image(systemName: appModel.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        Text(appModel.isRecording ? "Stop" : "Transcribe")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(appModel.isRecording ? .red : .accentColor)
                .disabled(appModel.isProcessing || !canRecord || isLoadingModel)
                
                if appModel.isProcessing || transcriptionManager.isTranscribing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .padding(.leading, 8)
                    Text("Processing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if appModel.showTranscriptionStarted {
                    Label("Transcription started", systemImage: "waveform")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .padding(.leading, 8)
                }
                
                Spacer()
                
                Button(action: { showModelManager = true }) {
                    Image(systemName: "gearshape")
                    Text("Models")
                }
                .buttonStyle(.bordered)
                .help("Manage models")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Sidebar / Settings Area
            HStack(spacing: 20) {
                Picker("Microphone", selection: $appModel.selectedInputDevice) {
                    if appModel.availableInputDevices.isEmpty {
                        Text("Detecting…").tag(nil as AVCaptureDevice?)
                    }
                    ForEach(appModel.availableInputDevices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device as AVCaptureDevice?)
                    }
                }
                .frame(maxWidth: 250)
                
                Picker("Model", selection: $appModel.selectedModelID) {
                    let downloadedModels = appModel.modelService.availableModels.filter({ $0.isAvailable })
                    if downloadedModels.isEmpty {
                        Text("No models downloaded").tag("")
                    }
                    ForEach(downloadedModels) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .frame(maxWidth: 200)
                
                Picker("Language", selection: $appModel.selectedLanguage) {
                    Text("Auto Detect").tag("auto")
                    Text("English").tag("en")
                    Text("Spanish").tag("es")
                    Text("French").tag("fr")
                    Text("German").tag("de")
                    Text("Chinese").tag("zh")
                }
                .frame(maxWidth: 150)
                
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Results Area
            ZStack(alignment: .bottomTrailing) {
                TextEditor(text: $appModel.transcribedText)
                    .font(.body)
                    .padding()
                    .frame(minHeight: 200, maxHeight: .infinity)
                
                // Copy Button
                Button(action: copyToClipboard) {
                    Image(systemName: "doc.on.clipboard")
                        .padding(8)
                }
                .buttonStyle(.borderless)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .cornerRadius(8)
                .padding()
                .help("Copy to Clipboard")
                .popover(isPresented: $showCopiedAlert) {
                    Text("Copied!")
                        .padding()
                }
            }
            
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
            
            if let error = appModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            if !accessibilityGranted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Accessibility permission required for paste-at-cursor.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Open Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.caption)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .task {
            // Deferred init: setup() dispatches Core Audio to a background thread,
            // so it won't block the main thread or interfere with app activation.
            appModel.setup()
            hotKeyManager.setup()
            setupAudio()
            requestAccessibilityPermission()
            
            // Auto-load the selected model if one is already downloaded
            if !appModel.selectedModelID.isEmpty,
               currentModel?.isAvailable == true {
                await loadModelAsync()
            }
        }
        .onChange(of: appModel.selectedModelID) { oldValue, newValue in
            modelLoaded = false
            appModel.errorMessage = nil
            // Auto-load the newly selected model if it's downloaded
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
    
    private func setupAudio() {
        audioManager.onBufferReceived = { buffer in
            if appModel.isRecording {
                transcriptionManager.appendAudio(buffer: buffer)
            }
        }
    }
    
    /// Prompt the user for Accessibility permission (needed for paste-at-cursor via CGEvent).
    /// Shows the macOS system dialog if not already granted.
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
    
    private func handleHotKey(pressed: Bool) {
        if pressed {
            startRecording()
        } else if appModel.isRecording {
            print("[Paste] hotkey released, stopping recording (autoPaste=true)")
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
                let text = try await transcriptionManager.processAudio { partial in }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[Paste] transcription result: '\(trimmed)' (autoPaste=\(autoPaste))")
                
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
                    print("[Paste] calling copyAndPaste")
                    copyAndPaste(trimmed)
                } else {
                    print("[Paste] skipped paste: autoPaste=\(autoPaste), isEmpty=\(trimmed.isEmpty)")
                }
            } catch {
                print("[Paste] transcription error: \(error)")
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
    
    private func copyAndPaste(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didSet = pasteboard.setString(text, forType: .string)
        print("[Paste] pasteboard set: \(didSet), text length: \(text.count)")
        
        // Verify pasteboard content
        let verify = pasteboard.string(forType: .string)
        print("[Paste] pasteboard verify: '\(verify?.prefix(50) ?? "nil")'")
        
        // Check frontmost app
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            print("[Paste] frontmost app: \(frontApp.localizedName ?? "unknown") (pid: \(frontApp.processIdentifier))")
        }
        
        // Small delay to ensure pasteboard is populated, then paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            print("[Paste] attempting CGEvent paste...")
            if Self.pasteWithCGEvent() {
                print("[Paste] CGEvent paste succeeded")
                return
            }
            print("[Paste] CGEvent failed, trying AppleScript...")
            Self.pasteWithAppleScript()
        }
    }
    
    /// Simulate ⌘V using CGEvent (Quartz Event Services).
    /// Returns true if the events were posted successfully.
    private static func pasteWithCGEvent() -> Bool {
        let hasPreflight = CGPreflightPostEventAccess()
        print("[Paste][CGEvent] preflight=\(hasPreflight)")
        
        guard hasPreflight else {
            print("[Paste][CGEvent] no Accessibility permission — requesting...")
            CGRequestPostEventAccess()
            return false
        }
        
        let source = CGEventSource(stateID: .hidSystemState)
        print("[Paste][CGEvent] source created: \(source != nil)")
        
        // 'v' key = keycode 9
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            print("[Paste][CGEvent] failed to create key events")
            return false
        }
        
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        
        // Try session event tap (works better with sandboxed apps)
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        print("[Paste][CGEvent] posted ⌘V via cgSessionEventTap")
        return true
    }
    
    /// Simulate ⌘V using AppleScript → System Events (sandboxed fallback).
    private static func pasteWithAppleScript() {
        print("[Paste][AppleScript] attempting...")
        let script = NSAppleScript(source: """
            tell application "System Events"
                keystroke "v" using command down
            end tell
        """)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if let error {
            print("[Paste][AppleScript] FAILED: \(error)")
        } else {
            print("[Paste][AppleScript] succeeded, result: \(String(describing: result))")
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


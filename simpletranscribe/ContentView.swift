import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var appModel = AppModel()
    let audioManager = AudioManager()
    @StateObject private var transcriptionManager = TranscriptionManager()
    
    // For copy to clipboard alert
    @State private var showCopiedAlert = false
    
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
                .disabled(appModel.isProcessing)
                
                if appModel.isProcessing || transcriptionManager.isTranscribing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .padding(.leading, 8)
                    Text("Processing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Sidebar / Settings Area
            HStack(spacing: 20) {
                Picker("Microphone", selection: $appModel.selectedInputDevice) {
                    ForEach(appModel.availableInputDevices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device as AVCaptureDevice?)
                    }
                }
                .frame(maxWidth: 250)
                
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
            
            if let error = appModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            setupAudio()
            loadModel()
        }
    }
    
    private func setupAudio() {
        audioManager.onBufferReceived = { buffer in
            if appModel.isRecording {
                transcriptionManager.appendAudio(buffer: buffer)
            }
        }
    }
    
    private func loadModel() {
        // Look for the model file in the app bundle
        Task {
            if let modelURL = Bundle.main.url(forResource: "ggml-tiny.en", withExtension: "bin") {
                do {
                    try transcriptionManager.loadModel(modelPath: modelURL)
                } catch {
                     DispatchQueue.main.async {
                         appModel.errorMessage = "Failed to load model: \(error.localizedDescription)"
                     }
                }
            } else {
                 DispatchQueue.main.async {
                     appModel.errorMessage = "Model file ggml-tiny.en.bin not found in bundle."
                 }
            }
        }
    }
    
    private func toggleRecording() {
        if appModel.isRecording {
            // Stop
            audioManager.stopRecording()
            appModel.isRecording = false
            appModel.isProcessing = true
            appModel.errorMessage = nil
            
            // Process the accumulated audio
            Task {
                do {
                    let text = try await transcriptionManager.processAudio { partial in
                        // Optional real-time updates could go here
                    }
                    
                    // Add a space and the new text if appending, or replace
                    if appModel.transcribedText.isEmpty {
                        appModel.transcribedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        appModel.transcribedText += " " + text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    
                    appModel.isProcessing = false
                    
                } catch {
                    appModel.errorMessage = "Transcription failed: \(error.localizedDescription)"
                    appModel.isProcessing = false
                }
            }
        } else {
            // Start
            appModel.errorMessage = nil
            audioManager.requestMicrophoneAccess { granted in
                guard granted else {
                    appModel.errorMessage = "Microphone access denied."
                    return
                }
                
                do {
                    transcriptionManager.startTranscription(language: appModel.selectedLanguage)
                    appModel.isRecording = true
                    try audioManager.startRecording(device: appModel.selectedInputDevice)
                } catch {
                    appModel.errorMessage = "Failed to start recording: \(error.localizedDescription)"
                    appModel.isRecording = false
                }
            }
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

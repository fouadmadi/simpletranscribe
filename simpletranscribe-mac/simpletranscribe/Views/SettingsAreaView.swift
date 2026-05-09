import SwiftUI
import AVFoundation

// MARK: - HotKey Recorder

struct HotKeyRecorderView: View {
    @Binding var modifiers: NSEvent.ModifierFlags
    @State private var isRecording = false
    @State private var monitor: Any?

    private static let knownConflicts: [NSEvent.ModifierFlags] = [
        [.command], [.command, .shift]
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Button(isRecording ? "Press keys…" : symbolString(modifiers)) {
                    if isRecording { stopRecording() } else { startRecording() }
                }
                .buttonStyle(.bordered)
                .foregroundColor(isRecording ? .accentColor : .primary)

                Button("↺") {
                    modifiers = [.function, .control]
                    stopRecording()
                }
                .buttonStyle(.borderless)
                .help("Reset to default (fn⌃)")
            }

            if Self.knownConflicts.contains(modifiers) {
                Text("⚠ May conflict with system shortcuts")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }
        }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let flags = event.modifierFlags.intersection([
                .command, .option, .control, .shift, .function
            ])
            if !flags.isEmpty {
                modifiers = flags
                stopRecording()
            }
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func symbolString(_ flags: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if flags.contains(.function) { parts.append("fn") }
        if flags.contains(.control)  { parts.append("⌃") }
        if flags.contains(.option)   { parts.append("⌥") }
        if flags.contains(.shift)    { parts.append("⇧") }
        if flags.contains(.command)  { parts.append("⌘") }
        return parts.isEmpty ? "None" : parts.joined()
    }
}

// MARK: - SettingsAreaView

struct SettingsAreaView: View {
    @Binding var selectedInputDevice: AVCaptureDevice?
    @Binding var selectedModelID: String
    @Binding var selectedLanguage: String
    @Binding var useSystemDefault: Bool
    @Binding var hotKeyModifiers: NSEvent.ModifierFlags
    @Binding var streamingEnabled: Bool
    @Binding var postProcessorConfig: PostProcessorConfig
    let availableInputDevices: [AVCaptureDevice]
    let downloadedModels: [ModelInfo]

    var availableLanguages: [SupportedLanguage] {
        SupportedLanguages.available(for: selectedModelID)
    }

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Picker("Microphone", selection: $selectedInputDevice) {
                    if availableInputDevices.isEmpty {
                        Text("Detecting…").tag(nil as AVCaptureDevice?)
                    }
                    ForEach(availableInputDevices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device as AVCaptureDevice?)
                    }
                }
                .disabled(useSystemDefault)
                .opacity(useSystemDefault ? 0.5 : 1.0)
                .frame(maxWidth: 250)

                Toggle("Use system default", isOn: $useSystemDefault)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }

            Picker("Model", selection: $selectedModelID) {
                if downloadedModels.isEmpty {
                    Text("No models downloaded").tag("")
                }
                ForEach(downloadedModels) { model in
                    Text(model.name).tag(model.id)
                }
            }
            .frame(maxWidth: 200)

            Picker("Language", selection: $selectedLanguage) {
                ForEach(availableLanguages) { lang in
                    Text(lang.displayName).tag(lang.code)
                }
            }
            .frame(maxWidth: 180)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hotkey")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HotKeyRecorderView(modifiers: $hotKeyModifiers)
            }

            Toggle("Live preview", isOn: $streamingEnabled)
                .toggleStyle(.checkbox)
                .font(.caption)
                .help("Show partial transcription while recording (Whisper models, lower accuracy)")
                .disabled(downloadedModels.first(where: { $0.id == selectedModelID })?.modelType == .parakeet)

            // Text processing toggles
            VStack(alignment: .leading, spacing: 2) {
                Text("Text Processing")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("Capitalise sentences", isOn: $postProcessorConfig.capitaliseSentences)
                    .toggleStyle(.checkbox).font(.caption)
                Toggle("Remove filler words", isOn: $postProcessorConfig.removeFillersEnabled)
                    .toggleStyle(.checkbox).font(.caption)
                Toggle("Number formatting", isOn: $postProcessorConfig.numberFormattingEnabled)
                    .toggleStyle(.checkbox).font(.caption)
            }

            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

import SwiftUI
import AVFoundation

struct SettingsAreaView: View {
    @Binding var selectedInputDevice: AVCaptureDevice?
    @Binding var selectedModelID: String
    @Binding var selectedLanguage: String
    let availableInputDevices: [AVCaptureDevice]
    let downloadedModels: [ModelInfo]

    var body: some View {
        HStack(spacing: 20) {
            Picker("Microphone", selection: $selectedInputDevice) {
                if availableInputDevices.isEmpty {
                    Text("Detecting…").tag(nil as AVCaptureDevice?)
                }
                ForEach(availableInputDevices, id: \.uniqueID) { device in
                    Text(device.localizedName).tag(device as AVCaptureDevice?)
                }
            }
            .frame(maxWidth: 250)

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
    }
}

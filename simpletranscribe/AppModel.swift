import SwiftUI
import Observation
import AVFoundation

@Observable
class AppModel {
    var isRecording: Bool = false
    var transcribedText: String = ""
    var selectedLanguage: String = "en"  // Default to English
    var selectedModel: String = "ggml-tiny.en.bin"  // Default small model
    var availableModels: [String] = ["ggml-tiny.en.bin", "ggml-base.en.bin", "ggml-small.en.bin"]
    var selectedInputDevice: AVCaptureDevice?
    var availableInputDevices: [AVCaptureDevice] = []
    
    // Status properties
    var isProcessing: Bool = false
    var errorMessage: String? = nil
    
    // Initialization to find available microphones
    init() {
        refreshAudioDevices()
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
}

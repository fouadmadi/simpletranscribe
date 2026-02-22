import SwiftUI
import Observation
import AVFoundation

@Observable
class AppModel {
    var isRecording: Bool = false
    var transcribedText: String = ""
    var selectedLanguage: String = "en"  // Default to English
    var selectedModelID: String = ""  // Start empty, will be set if models are downloaded
    var selectedInputDevice: AVCaptureDevice?
    var availableInputDevices: [AVCaptureDevice] = []
    
    // Model management
    let modelService = ModelService()
    
    // Status properties
    var isProcessing: Bool = false
    var errorMessage: String? = nil
    
    // Initialization to find available microphones and load models
    init() {
        refreshAudioDevices()
        modelService.loadAvailableModels()
        selectDefaultModel()
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
}

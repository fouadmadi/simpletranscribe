import SwiftUI
import Observation
import AVFoundation

@Observable
class AppModel {
    var isRecording: Bool = false
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
    // Feedback property
    var showTranscriptionStarted: Bool = false
    
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
}

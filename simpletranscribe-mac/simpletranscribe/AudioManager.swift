import AVFoundation
import AudioToolbox
import CoreAudio

class AudioManager: NSObject {
    private lazy var engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var outputBuffer: AVAudioPCMBuffer?
    
    // Whisper requires 16kHz mono, 32-bit float or 16-bit int depending on the exact implementation.
    // whisper.cpp Swift bindings conventionally use an array of Floats at 16kHz.
    private let targetSampleRate: Double = 16000.0
    
    var onBufferReceived: (([Float]) -> Void)?
    var onError: ((Error) -> Void)?
    
    func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }
    
    func startRecording(device: AVCaptureDevice?) throws {
        // Stop if running
        if engine.isRunning {
             stopRecording()
        }
        
        let inputNode = engine.inputNode
        
        // If a specific device is requested, route the engine's input to it
        if let device = device,
           let coreAudioDeviceID = Self.audioDeviceID(for: device.uniqueID) {
            guard let audioUnit = inputNode.audioUnit else {
                throw NSError(domain: "AudioManagerError", code: 3,
                             userInfo: [NSLocalizedDescriptionKey: "Cannot access audio unit"])
            }
            var deviceID = coreAudioDeviceID
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                print("AudioManager: Failed to set input device (OSStatus \(status)), falling back to default")
            }
        }
        
        // Setup input format from the hardware (read AFTER setting the device)
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // Setup the target format for Whisper (16kHz, Mono, 32-bit Float)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "AudioManagerError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create output audio format"])
        }
        
        // Set up the converter
        self.converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        
        // Pre-allocate output buffer for reuse across processBuffer calls
        let tapBufferSize: AVAudioFrameCount = 1024
        let outputCapacity = AVAudioFrameCount(ceil(Double(tapBufferSize) * (targetSampleRate / inputFormat.sampleRate)))
        self.outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity)
        
        // Install tap on the input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            self.processBuffer(buffer: buffer, fromFormat: inputFormat, toFormat: outputFormat)
        }
        
        engine.prepare()
        try engine.start()
    }
    
    private func processBuffer(buffer: AVAudioPCMBuffer, fromFormat: AVAudioFormat, toFormat: AVAudioFormat) {
        guard let converter = self.converter else { return }
        
        // Re-allocate only if the incoming buffer is larger than expected
        let requiredCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * (targetSampleRate / fromFormat.sampleRate)))
        if outputBuffer == nil || outputBuffer!.frameCapacity < requiredCapacity {
            outputBuffer = AVAudioPCMBuffer(pcmFormat: toFormat, frameCapacity: requiredCapacity)
        }
        guard let outputBuffer = self.outputBuffer else { return }
        
        var error: NSError? = nil
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        // Perform conversion
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if status == .haveData || status == .inputRanDry {
            // Extract the Float array
            if let channelData = outputBuffer.floatChannelData?[0] {
                let frameLength = Int(outputBuffer.frameLength)
                let floatArray = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
                
                // Pass back to TranscriptionManager
                self.onBufferReceived?(floatArray)
            }
        }
    }
    
    /// Maps an AVCaptureDevice.uniqueID to the corresponding CoreAudio AudioDeviceID.
    private static func audioDeviceID(for uniqueID: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize
        ) == noErr else { return nil }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return nil }
        
        for id in deviceIDs {
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uid: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            if AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &uid) == noErr {
                if (uid as String) == uniqueID {
                    return id
                }
            }
        }
        return nil
    }
    
    func stopRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        outputBuffer = nil
    }
}

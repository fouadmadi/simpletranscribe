import AVFoundation
import CoreAudio

class AudioManager: NSObject {
    private var engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    
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
        
        // Setup input format from the hardware
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
        
        // Calculate the output frame capacity
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * (targetSampleRate / fromFormat.sampleRate))
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: toFormat, frameCapacity: capacity) else {
            return
        }
        
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
    
    func stopRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
    }
}

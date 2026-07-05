import AVFoundation
import AudioToolbox

class MicrophoneManager {
    private lazy var engine = AVAudioEngine()
    private var converter: AVAudioConverter?

    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 44100,
        channels: 1,
        interleaved: false
    )!

    var onBufferReceived: (([Float]) -> Void)?

    func requestAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    func start() throws {
        if engine.isRunning { stop() }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.process(buffer, inputFormat: inputFormat)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
    }

    private func process(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        guard let converter = converter else { return }

        let ratio = 44100.0 / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio))
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard (status == .haveData || status == .inputRanDry), error == nil,
              let channelData = output.floatChannelData else { return }

        let floats = Array(UnsafeBufferPointer(start: channelData[0], count: Int(output.frameLength)))
        onBufferReceived?(floats)
    }
}

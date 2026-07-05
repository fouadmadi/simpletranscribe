import AVFoundation
import Foundation

final class RecordingSession {
    let source: RecordingSource

    private var micManager: MicrophoneManager?
    private var systemAudioManager: SystemAudioManager?
    private var audioMixer: AudioMixer?
    private var audioFile: AVAudioFile?
    private var tempURL: URL?

    // Serial queue ensuring AVAudioFile writes never race
    private let writeQueue = DispatchQueue(label: "com.simplerecorder.session.write")

    private let audioFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 44100,
        channels: 1,
        interleaved: false
    )!

    init(source: RecordingSource) {
        self.source = source
    }

    func start() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".wav")
        tempURL = url
        audioFile = try AVAudioFile(forWriting: url, settings: audioFormat.settings)

        switch source {
        case .microphone:
            let mic = MicrophoneManager()
            mic.onBufferReceived = { [weak self] floats in self?.writeToFile(floats) }
            try mic.start()
            micManager = mic

        case .systemAudio:
            let sys = SystemAudioManager()
            sys.onBufferReceived = { [weak self] floats in self?.writeToFile(floats) }
            try await sys.start()
            systemAudioManager = sys

        case .both:
            let mixer = AudioMixer()
            mixer.onMixedBuffer = { [weak self] floats in self?.writeToFile(floats) }
            audioMixer = mixer

            let mic = MicrophoneManager()
            mic.onBufferReceived = { [weak mixer] floats in mixer?.addMicBuffer(floats) }
            try mic.start()
            micManager = mic

            let sys = SystemAudioManager()
            sys.onBufferReceived = { [weak mixer] floats in mixer?.addSystemBuffer(floats) }
            try await sys.start()
            systemAudioManager = sys
        }
    }

    func stop() async throws -> URL {
        micManager?.stop()
        micManager = nil
        await systemAudioManager?.stop()
        systemAudioManager = nil
        audioMixer?.reset()
        audioMixer = nil

        // Close the file only after all pending writes have flushed
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writeQueue.async {
                self.audioFile = nil
                continuation.resume()
            }
        }

        guard let tempURL else {
            throw NSError(domain: "RecordingSession", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No temporary audio file found."])
        }

        let outputURL = MP3Encoder.outputURL()
        try await MP3Encoder.encode(sourceURL: tempURL, destinationURL: outputURL)
        try? FileManager.default.removeItem(at: tempURL)
        self.tempURL = nil

        return outputURL
    }

    private func writeToFile(_ floats: [Float]) {
        writeQueue.async { [weak self] in
            guard let self, let audioFile = self.audioFile else { return }
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: self.audioFormat,
                frameCapacity: AVAudioFrameCount(floats.count)
            ) else { return }

            buffer.frameLength = AVAudioFrameCount(floats.count)
            if let channelData = buffer.floatChannelData {
                channelData[0].assign(from: floats, count: floats.count)
            }
            try? audioFile.write(from: buffer)
        }
    }
}

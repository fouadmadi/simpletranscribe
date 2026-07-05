import Foundation

/// Thread-safe mixer that blends two mono PCM streams sample-by-sample.
/// Holds back data from the faster source until the slower one catches up.
final class AudioMixer {
    var onMixedBuffer: (([Float]) -> Void)?

    private var micAccumulator: [Float] = []
    private var systemAccumulator: [Float] = []
    private let lock = NSLock()

    // Prevent unbounded memory use: cap each accumulator at ~5 seconds of audio
    private let maxAccumulatorFrames = 44100 * 5

    func addMicBuffer(_ buffer: [Float]) {
        var mixed: [Float]?
        lock.withLock {
            if micAccumulator.count < maxAccumulatorFrames {
                micAccumulator.append(contentsOf: buffer)
            }
            mixed = tryFlushLocked()
        }
        if let mixed { onMixedBuffer?(mixed) }
    }

    func addSystemBuffer(_ buffer: [Float]) {
        var mixed: [Float]?
        lock.withLock {
            if systemAccumulator.count < maxAccumulatorFrames {
                systemAccumulator.append(contentsOf: buffer)
            }
            mixed = tryFlushLocked()
        }
        if let mixed { onMixedBuffer?(mixed) }
    }

    func reset() {
        lock.withLock {
            micAccumulator.removeAll()
            systemAccumulator.removeAll()
        }
    }

    // Must be called while holding `lock`. Returns mixed data if available.
    private func tryFlushLocked() -> [Float]? {
        let count = min(micAccumulator.count, systemAccumulator.count)
        guard count >= 512 else { return nil }

        var mixed = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let sum = micAccumulator[i] + systemAccumulator[i]
            mixed[i] = max(-1.0, min(1.0, sum * 0.5))
        }
        micAccumulator.removeFirst(count)
        systemAccumulator.removeFirst(count)
        return mixed
    }
}

private extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

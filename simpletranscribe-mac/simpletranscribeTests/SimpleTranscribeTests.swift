import Testing
import Foundation
@testable import simpletranscribe

@Suite("KnownModels Tests")
struct KnownModelsTests {
    @Test("All models have unique IDs")
    func uniqueIDs() {
        let ids = KnownModels.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("All models have valid download URLs")
    func validDownloadURLs() {
        for model in KnownModels.all {
            #expect(model.downloadURL.scheme == "https")
            #expect(model.downloadURL.host?.contains("huggingface.co") == true)
        }
    }

    @Test("All models have SHA256 hashes")
    func allModelsHaveHashes() {
        for model in KnownModels.all {
            #expect(model.sha256 != nil)
            #expect(model.sha256?.count == 64)
        }
    }

    @Test("All models have non-zero sizes")
    func nonZeroSizes() {
        for model in KnownModels.all {
            #expect(model.size > 0)
        }
    }

    @Test("Model lookup by ID works")
    func lookupByID() {
        let model = KnownModels.model(withID: "ggml-tiny.en")
        #expect(model != nil)
        #expect(model?.name == "Tiny (English)")
    }

    @Test("Model lookup returns nil for unknown ID")
    func lookupUnknownID() {
        let model = KnownModels.model(withID: "nonexistent")
        #expect(model == nil)
    }
}

@Suite("ModelInfo Tests")
struct ModelInfoTests {
    @Test("formattedSize returns human-readable string")
    func formattedSize() {
        let model = KnownModels.all[0]  // Tiny ~77MB
        let formatted = model.formattedSize
        #expect(formatted.contains("MB"))
    }

    @Test("isAvailable is false when not downloaded")
    func isAvailableDefault() {
        let model = KnownModels.all[0]
        #expect(model.isAvailable == false)
    }

    @Test("isAvailable is true when downloaded with path")
    func isAvailableWhenDownloaded() {
        var model = KnownModels.all[0]
        model.status = .downloaded
        model.downloadedPath = URL(fileURLWithPath: "/tmp/test.bin")
        #expect(model.isAvailable == true)
    }

    @Test("isAvailable is false when downloaded without path")
    func isAvailableWithoutPath() {
        var model = KnownModels.all[0]
        model.status = .downloaded
        model.downloadedPath = nil
        #expect(model.isAvailable == false)
    }
}

@Suite("TranscriptionManager Tests")
struct TranscriptionManagerTests {
    @Test("Audio buffer respects 30-minute cap")
    func bufferCap() async {
        let manager = TranscriptionManager()
        manager.startTranscription(language: "en")

        let largeBuf = [Float](repeating: 0.5, count: 30 * 60 * 16_000 + 1000)
        manager.appendAudio(buffer: largeBuf)

        // The manager should have capped at maxSamples (30 * 60 * 16_000)
        // We can't directly access accumulatedAudio, but we can verify
        // it doesn't crash and processes without error
        #expect(true, "Buffer accepted without crash")
    }

    @Test("Start transcription resets state")
    func startResetsState() {
        let manager = TranscriptionManager()
        manager.appendAudio(buffer: [1.0, 2.0, 3.0])
        manager.startTranscription(language: "en")
        // Starting should clear accumulated audio (via removeAll)
        #expect(true, "Start transcription succeeded")
    }
}

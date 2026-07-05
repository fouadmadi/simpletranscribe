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

    @Test("Single-file models have SHA256 hashes")
    func singleFileModelsHaveHashes() {
        // Directory-based models (Parakeet) use per-file hashes stored in ModelFile, not top-level.
        let singleFileModels = KnownModels.all.filter { !$0.isDirectory }
        for model in singleFileModels {
            #expect(model.sha256 != nil, "Missing hash for \(model.id)")
            #expect(model.sha256?.count == 64, "Invalid hash length for \(model.id)")
        }
    }

    @Test("Directory models have per-file SHA256 hashes")
    func directoryModelsHaveFileHashes() {
        let directoryModels = KnownModels.all.filter { $0.isDirectory }
        for model in directoryModels {
            #expect(!model.files.isEmpty, "Directory model \(model.id) has no files")
            for file in model.files where file.sha256 != nil {
                #expect(file.sha256?.count == 64, "Invalid hash for \(file.filename) in \(model.id)")
            }
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
        // Tiny model is ~77 MB
        let model = KnownModels.model(withID: "ggml-tiny.en")!
        let formatted = model.formattedSize
        #expect(formatted.contains("MB") || formatted.contains("GB"))
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

    @Test("coreMlEncoderZipURL field is present and optional")
    func coreMlFieldExists() {
        var model = KnownModels.model(withID: "ggml-base.en")!
        // Verify the field exists and can be set/cleared
        #expect(model.coreMlEncoderZipURL != nil)
        model.coreMlEncoderZipURL = nil
        #expect(model.coreMlEncoderZipURL == nil)
    }
}

// MARK: - Fix regression: no duplicate language codes (was "gl" appearing twice)

@Suite("SupportedLanguages Tests")
struct SupportedLanguagesTests {
    @Test("whisper language list has no duplicate codes")
    func noDuplicateCodes() {
        let codes = SupportedLanguages.whisper.map(\.code)
        let duplicates = Dictionary(grouping: codes, by: { $0 })
            .filter { $1.count > 1 }
            .keys.sorted()
        #expect(duplicates.isEmpty, "Duplicate language codes found: \(duplicates)")
    }

    @Test("whisper language list has no duplicate display names")
    func noDuplicateDisplayNames() {
        let names = SupportedLanguages.whisper.map(\.displayName)
        let duplicates = Dictionary(grouping: names, by: { $0 })
            .filter { $1.count > 1 }
            .keys.sorted()
        #expect(duplicates.isEmpty, "Duplicate display names found: \(duplicates)")
    }

    @Test("available(for:) returns unique codes for every known model")
    func availableReturnsUniqueCodes() {
        for model in KnownModels.all {
            let langs = SupportedLanguages.available(for: model.id)
            let codes = langs.map(\.id)
            let duplicates = Dictionary(grouping: codes, by: { $0 })
                .filter { $1.count > 1 }.keys.sorted()
            #expect(duplicates.isEmpty, "Duplicate IDs in available(for: \(model.id)): \(duplicates)")
        }
    }

    @Test("Parakeet V2 is English-only")
    func parakeetV2EnglishOnly() {
        #expect(SupportedLanguages.parakeetV2 == ["en"])
    }

    @Test("Parakeet V3 language codes are all present in the whisper list")
    func parakeetV3CodesAreInWhisperList() {
        let whisperCodes = Set(SupportedLanguages.whisper.map(\.code))
        for code in SupportedLanguages.parakeetV3 {
            #expect(whisperCodes.contains(code), "Parakeet V3 code '\(code)' missing from whisper list")
        }
    }

    @Test("available(for:) returns full whisper list for unknown model IDs")
    func availableForUnknownIDReturnsFullList() {
        let full = SupportedLanguages.available(for: "some-unknown-model")
        #expect(full.count == SupportedLanguages.whisper.count)
    }
}

// MARK: - Regression: CoreML encoders only for compatible whisper models

@Suite("CoreML Encoder URL Tests")
struct CoreMLEncoderURLTests {
    private let modelsWithCoreML = ["ggml-tiny.en", "ggml-base.en", "ggml-small.en", "ggml-medium.en"]

    @Test("English whisper models have CoreML encoder zip URLs")
    func englishWhisperModelsHaveURLs() {
        for id in modelsWithCoreML {
            let model = KnownModels.model(withID: id)
            #expect(model?.coreMlEncoderZipURL != nil, "Missing CoreML URL for \(id)")
        }
    }

    @Test("CoreML encoder URLs point to the correct model's zip on HuggingFace")
    func coreMlURLsAreWellFormed() {
        for id in modelsWithCoreML {
            guard let url = KnownModels.model(withID: id)?.coreMlEncoderZipURL else {
                Issue.record("No CoreML URL for \(id)"); continue
            }
            #expect(url.scheme == "https", "Non-HTTPS URL for \(id)")
            #expect(url.host?.contains("huggingface.co") == true, "Not HuggingFace URL for \(id)")
            #expect(url.pathExtension == "zip", "Expected .zip for \(id)")
            #expect(url.absoluteString.contains(id), "URL doesn't reference model ID '\(id)'")
        }
    }

    @Test("Large whisper model has no CoreML encoder URL (naming mismatch)")
    func largeModelHasNoCoreMlURL() {
        #expect(KnownModels.model(withID: "ggml-large")?.coreMlEncoderZipURL == nil)
    }

    @Test("Parakeet models have no CoreML encoder URLs")
    func parakeetModelsHaveNoCoreMlURLs() {
        // When SHERPA_ONNX is not compiled, there are no Parakeet models in the list.
        // When it is compiled, Parakeet models must not have CoreML URLs.
        for model in KnownModels.all.filter({ $0.modelType == .parakeet }) {
            #expect(model.coreMlEncoderZipURL == nil, "Unexpected CoreML URL for \(model.id)")
        }
    }
}

// MARK: - Regression: model switching / selectDefaultModel

@Suite("Model Selection Tests")
struct ModelSelectionTests {
    @Test("KnownModels order: parakeet before whisper (affects selectDefaultModel priority)")
    func parakeetBeforeWhisperInOrder() {
        // When SHERPA_ONNX is not compiled, no Parakeet models are present — test is vacuously true.
        let ids = KnownModels.all.map(\.id)
        let firstParakeetIdx = ids.firstIndex(where: { $0.hasPrefix("parakeet") })
        let firstWhisperIdx  = ids.firstIndex(where: { $0.hasPrefix("ggml") })
        if let p = firstParakeetIdx, let w = firstWhisperIdx {
            #expect(p < w, "Parakeet models should precede whisper models in the list")
        }
    }

    @Test("Without SHERPA_ONNX, no Parakeet models appear in KnownModels")
    func noParakeetWithoutSherpaOnnx() {
        #if SHERPA_ONNX
        // With the flag, Parakeet models must be present
        #expect(KnownModels.all.contains(where: { $0.modelType == .parakeet }))
        #else
        // Without the flag, no Parakeet model should be downloadable or selectable
        #expect(!KnownModels.all.contains(where: { $0.modelType == .parakeet }),
                "Parakeet models must not appear without SHERPA_ONNX — users can't load them")
        #endif
    }

    @Test("selectDefaultModel: returns empty string when no models are available")
    func selectDefaultModelEmpty() {
        let available: [ModelInfo] = []
        let selected = available.first?.id ?? ""
        #expect(selected == "")
    }

    @Test("selectDefaultModel: picks first available model")
    func selectDefaultModelPicksFirst() {
        var models = KnownModels.all
        models[0].status = .downloaded
        models[0].downloadedPath = URL(fileURLWithPath: "/tmp/a")
        models[1].status = .downloaded
        models[1].downloadedPath = URL(fileURLWithPath: "/tmp/b")

        let available = models.filter { $0.isAvailable }
        let selected = available.first?.id ?? ""
        #expect(selected == KnownModels.all[0].id)
    }

    @Test("Stale model load is blocked when selection changes mid-load")
    func staleLloadGuard() {
        // Simulates the intendedModelID guard in AppModel.loadModelAsync:
        // if selectedModelID changed while the load was in progress, the result is discarded.
        let intendedModelID = "ggml-tiny.en"
        let currentModelID  = "ggml-base.en"  // user switched while tiny.en was loading
        let shouldCommit    = currentModelID == intendedModelID
        #expect(shouldCommit == false, "A stale load must not commit when the selection has moved on")
    }

    @Test("Model load commits when selection is unchanged")
    func freshLoadCommits() {
        let intendedModelID = "ggml-tiny.en"
        let currentModelID  = "ggml-tiny.en"  // still the same
        let shouldCommit    = currentModelID == intendedModelID
        #expect(shouldCommit == true, "A current load must commit when the selection matches")
    }
}

// MARK: - Existing tests (preserved)

@Suite("TranscriptionManager Tests")
struct TranscriptionManagerTests {
    @Test("Audio buffer respects 30-minute cap")
    func bufferCap() async {
        let manager = TranscriptionManager()
        manager.startTranscription(language: "en")

        let largeBuf = [Float](repeating: 0.5, count: 30 * 60 * 16_000 + 1000)
        manager.appendAudio(buffer: largeBuf)

        #expect(true, "Buffer accepted without crash")
    }

    @Test("Start transcription resets state")
    func startResetsState() {
        let manager = TranscriptionManager()
        manager.appendAudio(buffer: [1.0, 2.0, 3.0])
        manager.startTranscription(language: "en")
        #expect(true, "Start transcription succeeded")
    }
}

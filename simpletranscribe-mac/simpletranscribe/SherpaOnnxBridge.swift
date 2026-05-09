/// SherpaOnnxBridge.swift
/// Minimal Swift wrapper for sherpa-onnx C API — offline transducer recognition only.
///
/// Based on the official SherpaOnnx.swift from https://github.com/k2-fsa/sherpa-onnx
/// Copyright (c) 2023 Xiaomi Corporation
///
/// SETUP REQUIRED:
///   1. Download sherpa_onnx.xcframework and onnxruntime.xcframework from
///      https://github.com/k2-fsa/sherpa-onnx/releases
///   2. Add both xcframeworks to the Xcode project (Frameworks, Libraries)
///   3. Create a bridging header (SherpaOnnx-Bridging-Header.h) that includes:
///        #import "sherpa-onnx/c-api/c-api.h"
///   4. Set the bridging header in Build Settings → Swift Compiler → Objective-C Bridging Header
///   5. Add -DSHERPA_ONNX to Other Swift Flags in Build Settings

import Foundation

#if SHERPA_ONNX

// MARK: - C Pointer Helper

/// Convert a Swift String to a `const char*` for passing to C functions.
func toCPointer(_ s: String) -> UnsafePointer<Int8>! {
    let cs = (s as NSString).utf8String
    return UnsafePointer<Int8>(cs)
}

// MARK: - Config Builders

func sherpaOnnxFeatureConfig(
    sampleRate: Int = 16000,
    featureDim: Int = 80
) -> SherpaOnnxFeatureConfig {
    return SherpaOnnxFeatureConfig(
        sample_rate: Int32(sampleRate),
        feature_dim: Int32(featureDim)
    )
}

func sherpaOnnxOfflineTransducerModelConfig(
    encoder: String = "",
    decoder: String = "",
    joiner: String = ""
) -> SherpaOnnxOfflineTransducerModelConfig {
    return SherpaOnnxOfflineTransducerModelConfig(
        encoder: toCPointer(encoder),
        decoder: toCPointer(decoder),
        joiner: toCPointer(joiner)
    )
}

func sherpaOnnxOfflineModelConfig(
    tokens: String,
    transducer: SherpaOnnxOfflineTransducerModelConfig = sherpaOnnxOfflineTransducerModelConfig(),
    numThreads: Int = 1,
    provider: String = "cpu",
    debug: Int = 0,
    modelType: String = ""
) -> SherpaOnnxOfflineModelConfig {
    return SherpaOnnxOfflineModelConfig(
        transducer: transducer,
        paraformer: SherpaOnnxOfflineParaformerModelConfig(model: toCPointer("")),
        nemo_ctc: SherpaOnnxOfflineNemoEncDecCtcModelConfig(model: toCPointer("")),
        whisper: SherpaOnnxOfflineWhisperModelConfig(
            encoder: toCPointer(""), decoder: toCPointer(""),
            language: toCPointer(""), task: toCPointer("transcribe"),
            tail_paddings: -1, enable_token_timestamps: 0, enable_segment_timestamps: 0
        ),
        tdnn: SherpaOnnxOfflineTdnnModelConfig(model: toCPointer("")),
        tokens: toCPointer(tokens),
        num_threads: Int32(numThreads),
        debug: Int32(debug),
        provider: toCPointer(provider),
        model_type: toCPointer(modelType),
        modeling_unit: toCPointer("cjkchar"),
        bpe_vocab: toCPointer(""),
        telespeech_ctc: toCPointer(""),
        sense_voice: SherpaOnnxOfflineSenseVoiceModelConfig(
            model: toCPointer(""), language: toCPointer(""), use_itn: 0
        ),
        moonshine: SherpaOnnxOfflineMoonshineModelConfig(
            preprocessor: toCPointer(""), encoder: toCPointer(""),
            uncached_decoder: toCPointer(""), cached_decoder: toCPointer(""),
            merged_decoder: toCPointer("")
        ),
        fire_red_asr: SherpaOnnxOfflineFireRedAsrModelConfig(
            encoder: toCPointer(""), decoder: toCPointer("")
        ),
        dolphin: SherpaOnnxOfflineDolphinModelConfig(model: toCPointer("")),
        zipformer_ctc: SherpaOnnxOfflineZipformerCtcModelConfig(model: toCPointer("")),
        canary: SherpaOnnxOfflineCanaryModelConfig(
            encoder: toCPointer(""), decoder: toCPointer(""),
            src_lang: toCPointer("en"), tgt_lang: toCPointer("en"), use_pnc: 1
        ),
        wenet_ctc: SherpaOnnxOfflineWenetCtcModelConfig(model: toCPointer("")),
        omnilingual: SherpaOnnxOfflineOmnilingualAsrCtcModelConfig(model: toCPointer("")),
        medasr: SherpaOnnxOfflineMedAsrCtcModelConfig(model: toCPointer("")),
        funasr_nano: SherpaOnnxOfflineFunASRNanoModelConfig(
            encoder_adaptor: toCPointer(""), llm: toCPointer(""),
            embedding: toCPointer(""), tokenizer: toCPointer(""),
            system_prompt: toCPointer(""), user_prompt: toCPointer(""),
            max_new_tokens: 512, temperature: 1e-6, top_p: 0.8, seed: 42,
            language: toCPointer(""), itn: 1, hotwords: toCPointer("")
        ),
        fire_red_asr_ctc: SherpaOnnxOfflineFireRedAsrCtcModelConfig(model: toCPointer("")),
        qwen3_asr: SherpaOnnxOfflineQwen3ASRModelConfig(
            conv_frontend: toCPointer(""), encoder: toCPointer(""),
            decoder: toCPointer(""), tokenizer: toCPointer(""),
            max_total_len: 512, max_new_tokens: 128,
            temperature: 1e-6, top_p: 0.8, seed: 42, hotwords: toCPointer("")
        ),
        cohere_transcribe: SherpaOnnxOfflineCohereTranscribeModelConfig(
            encoder: toCPointer(""), decoder: toCPointer(""),
            language: toCPointer(""), use_punct: 1, use_itn: 1
        )
    )
}

func sherpaOnnxOfflineLMConfig(
    model: String = "",
    scale: Float = 1.0
) -> SherpaOnnxOfflineLMConfig {
    return SherpaOnnxOfflineLMConfig(
        model: toCPointer(model),
        scale: scale
    )
}

func sherpaOnnxHomophoneReplacerConfig(
    dictDir: String = "",
    lexicon: String = "",
    ruleFsts: String = ""
) -> SherpaOnnxHomophoneReplacerConfig {
    return SherpaOnnxHomophoneReplacerConfig(
        dict_dir: toCPointer(dictDir),
        lexicon: toCPointer(lexicon),
        rule_fsts: toCPointer(ruleFsts)
    )
}

func sherpaOnnxOfflineRecognizerConfig(
    featConfig: SherpaOnnxFeatureConfig,
    modelConfig: SherpaOnnxOfflineModelConfig,
    lmConfig: SherpaOnnxOfflineLMConfig = sherpaOnnxOfflineLMConfig(),
    decodingMethod: String = "greedy_search",
    maxActivePaths: Int = 4,
    hotwordsFile: String = "",
    hotwordsScore: Float = 1.5,
    ruleFsts: String = "",
    ruleFars: String = "",
    blankPenalty: Float = 0.0,
    hr: SherpaOnnxHomophoneReplacerConfig = sherpaOnnxHomophoneReplacerConfig()
) -> SherpaOnnxOfflineRecognizerConfig {
    return SherpaOnnxOfflineRecognizerConfig(
        feat_config: featConfig,
        model_config: modelConfig,
        lm_config: lmConfig,
        decoding_method: toCPointer(decodingMethod),
        max_active_paths: Int32(maxActivePaths),
        hotwords_file: toCPointer(hotwordsFile),
        hotwords_score: hotwordsScore,
        rule_fsts: toCPointer(ruleFsts),
        rule_fars: toCPointer(ruleFars),
        blank_penalty: blankPenalty,
        hr: hr
    )
}

// MARK: - Recognition Result

class SherpaOnnxOfflineRecognitionResult {
    let result: UnsafePointer<SherpaOnnxOfflineRecognizerResult>

    private lazy var _text: String = {
        guard let cstr = result.pointee.text else { return "" }
        return String(cString: cstr)
    }()

    var text: String { _text }
    var count: Int { Int(result.pointee.count) }

    init(result: UnsafePointer<SherpaOnnxOfflineRecognizerResult>) {
        self.result = result
    }

    deinit {
        SherpaOnnxDestroyOfflineRecognizerResult(result)
    }
}

// MARK: - Stream Wrapper

class SherpaOnnxOfflineStreamWrapper {
    let stream: OpaquePointer

    init(stream: OpaquePointer) {
        self.stream = stream
    }

    deinit {
        SherpaOnnxDestroyOfflineStream(stream)
    }

    func acceptWaveform(samples: [Float], sampleRate: Int = 16_000) {
        SherpaOnnxAcceptWaveformOffline(stream, Int32(sampleRate), samples, Int32(samples.count))
    }
}

// MARK: - Offline Recognizer

class SherpaOnnxOfflineRecognizer {
    private let recognizer: OpaquePointer

    init(config: UnsafePointer<SherpaOnnxOfflineRecognizerConfig>) {
        guard let ptr = SherpaOnnxCreateOfflineRecognizer(config) else {
            fatalError("Failed to create SherpaOnnxOfflineRecognizer")
        }
        self.recognizer = ptr
    }

    deinit {
        SherpaOnnxDestroyOfflineRecognizer(recognizer)
    }

    /// Decode audio samples and return the recognition result.
    func decode(samples: [Float], sampleRate: Int = 16_000) -> SherpaOnnxOfflineRecognitionResult {
        let stream = createStream()
        stream.acceptWaveform(samples: samples, sampleRate: sampleRate)
        decode(stream: stream)
        return getResult(stream: stream)
    }

    func createStream() -> SherpaOnnxOfflineStreamWrapper {
        guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
            fatalError("Failed to create offline stream")
        }
        return SherpaOnnxOfflineStreamWrapper(stream: stream)
    }

    func decode(stream: SherpaOnnxOfflineStreamWrapper) {
        SherpaOnnxDecodeOfflineStream(recognizer, stream.stream)
    }

    func getResult(stream: SherpaOnnxOfflineStreamWrapper) -> SherpaOnnxOfflineRecognitionResult {
        guard let resultPtr = SherpaOnnxGetOfflineStreamResult(stream.stream) else {
            fatalError("Failed to get offline recognition result")
        }
        return SherpaOnnxOfflineRecognitionResult(result: resultPtr)
    }
}

#endif // SHERPA_ONNX

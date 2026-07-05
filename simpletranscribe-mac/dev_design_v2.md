# SimpleTranscribe — Detailed Developer Design

> **Version:** 1.0 Design Draft  
> **App:** SimpleTranscribe (macOS 14+, Swift/SwiftUI)  
> **Scope:** Comprehensive design covering current state, architecture refactor, new features, and implementation roadmap

---

## 1. Executive Summary

SimpleTranscribe is a native macOS app that records audio from a microphone and transcribes it locally using Whisper (via SwiftWhisper + whisper.cpp). The current implementation is functional but has significant architectural and UX gaps:

- No test coverage at all
- No settings persistence (language/model resets on each launch)
- No real-time partial transcription during recording
- No audio file import (file → transcribe)
- No transcript history or sessions
- Minimal accessibility
- Single-window, no toolbar or menu integration
- Hard-coded model list (no ability to add custom models via UI)
- Recording stops, then processing starts — no streaming pipeline

This design document defines the **v2 architecture**, new features, refactoring plan, and an implementation-ready spec for all components.

---

## 2. Current State Inventory

### 2.1 Source Files

| File | LOC | Responsibility |
|------|-----|----------------|
| `simpletranscribeApp.swift` | ~10 | App entry, `WindowGroup` |
| `ContentView.swift` | ~286 | Monolithic main UI |
| `AppModel.swift` | ~51 | Observable state, device discovery |
| `AudioManager.swift` | ~100 | AVAudioEngine, format conversion |
| `TranscriptionManager.swift` | ~62 | SwiftWhisper wrapper, audio buffer accumulation |
| `Models/ModelInfo.swift` | ~30 | Model metadata struct |
| `Models/KnownModels.swift` | ~60 | Static registry of 5 Whisper models |
| `Services/ModelService.swift` | ~264 | Download, delete, discover model files |
| `Views/ModelDownloadView.swift` | ~300 | Model management sheet UI |

**Total: ~1,163 LOC, 0 tests**

### 2.2 Technology Stack (Current)

| Layer | Technology |
|-------|-----------|
| Language | Swift 5.9+ |
| UI | SwiftUI (macOS 14+, `@Observable` macro) |
| Audio capture | `AVAudioEngine` + `AVAudioConverter` |
| Transcription | `SwiftWhisper` (bindings to `whisper.cpp`) |
| Model source | Hugging Face (`ggerganov/whisper.cpp` repo) |
| Storage | FileManager → `~/Library/Application Support/com.simpletranscribe/` |
| State management | `@Observable` (AppModel), `@ObservableObject` (TranscriptionManager) |
| Networking | `URLSession` + `URLSessionDownloadTask` |
| Build system | Xcode + Swift Package Manager |
| Tests | None |

### 2.3 Known Issues / Gaps

1. **No settings persistence** — language, model, microphone preferences reset on every launch
2. **No real-time transcription** — audio accumulates in RAM, all processed after Stop
3. **No file import** — cannot transcribe a pre-recorded audio file
4. **No transcript history** — results are lost on quit
5. **No keyboard shortcuts** — no menu integration, no ⌘R to start recording
6. **No recording waveform visualization** — no audio feedback during capture
7. **No model checksum verification** — downloaded .bin files aren't validated
8. **Hard-coded language list** — limited to 6 languages, Whisper supports 99+
9. **ContentView is a monolith** — all logic mixed into 286-line view struct
10. **Mixed reactive patterns** — `@Observable` for AppModel, `@ObservableObject` for TranscriptionManager
11. **No error recovery** — errors are shown but not actionable in many cases
12. **Camera entitlement abuse** — uses `NSCameraUsageDescription` for audio device enumeration; this is unnecessary

---

## 3. v2 Architecture Design

### 3.1 Layered Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                         PRESENTATION LAYER                         │
│  ContentView  │  RecordingView  │  HistoryView  │  SettingsView    │
│  ModelManager │  TranscriptDetailView           │  WaveformView    │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ @Observable ViewModels
┌──────────────────────────────▼─────────────────────────────────────┐
│                        APPLICATION LAYER                           │
│  RecordingViewModel  │  HistoryViewModel  │  SettingsViewModel     │
│  ModelViewModel      │  (coordinators, no business logic)          │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ Protocol-based interfaces
┌──────────────────────────────▼─────────────────────────────────────┐
│                          DOMAIN LAYER                              │
│  AudioCaptureService    │  TranscriptionService  │  ModelService   │
│  TranscriptRepository   │  SettingsService       │  FileImportService │
└──────────────────────────────┬─────────────────────────────────────┘
                               │ Abstracted data sources
┌──────────────────────────────▼─────────────────────────────────────┐
│                       INFRASTRUCTURE LAYER                         │
│  AVAudioEngineWrapper  │  WhisperEngine    │  ModelDownloader      │
│  UserDefaultsStore     │  FileSystemStore  │  AudioFileReader      │
└────────────────────────────────────────────────────────────────────┘
```

### 3.2 Core State Management (Unified @Observable)

All services migrated to `@Observable` (eliminate `@ObservableObject` / `@StateObject`).

```swift
// Root application environment (injected via .environment())
@Observable
final class AppEnvironment {
    var recording: RecordingViewModel
    var history: HistoryViewModel
    var models: ModelViewModel
    var settings: SettingsViewModel
}
```

Each ViewModel owns a slice of state. No cross-ViewModel mutation — ViewModels communicate via async event streams or callbacks.

### 3.3 Service Protocol Interfaces

All services defined as protocols to enable testability and future swappability:

```swift
protocol AudioCaptureServiceProtocol {
    var audioBuffers: AsyncStream<[Float]> { get }
    func startCapture(device: AudioDevice) async throws
    func stopCapture() async
    var currentLevel: Float { get }  // for waveform
}

protocol TranscriptionEngineProtocol {
    func loadModel(at url: URL) async throws
    func transcribe(_ audio: [Float], language: String) async throws -> TranscriptionResult
    func unloadModel()
    var isLoaded: Bool { get }
}

protocol ModelRepositoryProtocol {
    var availableModels: [WhisperModel] { get }
    func downloadModel(_ id: ModelID) async throws
    func deleteModel(_ id: ModelID) throws
    func modelURL(for id: ModelID) -> URL?
}

protocol TranscriptRepositoryProtocol {
    func save(_ transcript: Transcript) throws
    func fetchAll() throws -> [Transcript]
    func delete(_ id: TranscriptID) throws
}

protocol SettingsServiceProtocol {
    var selectedModelID: ModelID? { get set }
    var selectedLanguage: Language { get set }
    var selectedDeviceID: String? { get set }
    var autoSaveTranscripts: Bool { get set }
}
```

---

## 4. Data Models

### 4.1 Core Domain Models

```swift
// Whisper model definition
struct WhisperModel: Identifiable, Codable, Hashable {
    let id: ModelID        // e.g. "ggml-base.en"
    let name: String       // e.g. "Base (English)"
    let sizeBytes: Int64   // e.g. 147_800_000
    let languages: ModelLanguageSupport  // .englishOnly | .multilingual
    let downloadURL: URL
    var localURL: URL?     // set when downloaded
    var downloadState: DownloadState
}

enum DownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case failed(error: String)
}

typealias ModelID = String

enum ModelLanguageSupport {
    case englishOnly
    case multilingual
}

// Language definition (all 99 Whisper languages)
struct Language: Identifiable, Codable, Hashable {
    let id: String     // ISO 639-1 code, e.g. "en"
    let name: String   // Display name, e.g. "English"
    static let auto = Language(id: "auto", name: "Auto Detect")
    static let all: [Language] = [ ... ]  // Full 99-item list
}

// Transcript session
struct Transcript: Identifiable, Codable {
    let id: TranscriptID       // UUID
    var title: String          // Auto-generated from first 50 chars or date
    let createdAt: Date
    var updatedAt: Date
    var text: String
    let modelID: ModelID
    let language: String
    let durationSeconds: Double
    let audioSourceName: String   // "MacBook Pro Microphone" or filename
}

typealias TranscriptID = UUID

// Result from transcription engine
struct TranscriptionResult {
    let segments: [TranscriptionSegment]
    let fullText: String
    let language: String
    let processingDurationSeconds: Double
}

struct TranscriptionSegment {
    let startMs: Int
    let endMs: Int
    let text: String
    let confidence: Float
}

// Audio capture device
struct AudioDevice: Identifiable, Hashable {
    let id: String          // AVCaptureDevice.uniqueID
    let name: String
    let isDefault: Bool
}
```

### 4.2 Settings Model

```swift
struct AppSettings: Codable {
    var selectedModelID: ModelID?
    var selectedLanguageID: String = "auto"
    var selectedDeviceID: String?
    var autoSaveTranscripts: Bool = true
    var appendMode: Bool = true      // New transcriptions append vs replace
    var showWaveform: Bool = true
    var windowFrame: CGRect?
}
```

---

## 5. Component-by-Component Design

### 5.1 AudioCaptureService (Refactored AudioManager)

**Responsibility:** Capture microphone input, convert to Whisper-compatible format, stream Float buffers.

**Key design changes from current:**
- Returns `AsyncStream<[Float]>` instead of callback-based `onBufferReceived`
- Exposes `currentLevel: Float` (RMS amplitude for waveform)
- Handles device hot-plug events (reconnect/disconnect)
- Removes `AVCaptureDevice` usage for device enumeration (use `AVAudioEngine.inputNode` directly + `CoreAudio` for device list)

```swift
@Observable
final class AudioCaptureService: AudioCaptureServiceProtocol {
    private(set) var isCapturing = false
    private(set) var currentLevel: Float = 0.0
    private(set) var availableDevices: [AudioDevice] = []

    private var engine: AVAudioEngine?
    private var continuation: AsyncStream<[Float]>.Continuation?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    var audioBuffers: AsyncStream<[Float]> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func startCapture(device: AudioDevice) async throws {
        // 1. Set AudioUnit device property to requested device
        // 2. Create AVAudioEngine
        // 3. Install tap on inputNode
        // 4. On each buffer: convert → compute RMS → yield via continuation
    }

    func stopCapture() async {
        continuation?.finish()
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
    }

    func refreshAvailableDevices() {
        // Use AudioObjectGetPropertyData (CoreAudio) to enumerate kAudioHardwarePropertyDevices
        // Filter to input-capable devices
    }
}
```

**Audio conversion pipeline:**
```
AVAudioEngine inputNode
    → hardware format (e.g. 48kHz stereo float32)
    → AVAudioConverter
    → 16kHz mono float32 PCM
    → RMS computation (store in currentLevel)
    → yield [Float] to AsyncStream
```

---

### 5.2 WhisperTranscriptionEngine (Refactored TranscriptionManager)

**Responsibility:** Load a Whisper model, transcribe Float audio arrays, report segments.

**Key design changes:**
- Protocol-backed for testability with `MockTranscriptionEngine`
- Exposes streaming partial results via `AsyncThrowingStream<TranscriptionSegment, Error>`
- Thread management: model loading and inference on a dedicated `DispatchQueue` or `Actor`
- Proper model unloading to free memory

```swift
actor WhisperTranscriptionEngine: TranscriptionEngineProtocol {
    private var whisper: Whisper?
    private(set) var isLoaded = false
    private(set) var loadedModelID: ModelID?

    func loadModel(at url: URL) async throws {
        // Unload existing model first
        unloadModel()
        whisper = Whisper(fromFileURL: url)
        isLoaded = true
    }

    func transcribe(_ audio: [Float], language: String) async throws -> TranscriptionResult {
        guard let whisper else { throw TranscriptionError.modelNotLoaded }
        let startTime = Date()
        whisper.params.language = (language == "auto") ? nil : language
        let segments = try await whisper.transcribe(audioFrames: audio)
        let full = segments.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        return TranscriptionResult(
            segments: segments.map { TranscriptionSegment(startMs: Int($0.startTime * 1000),
                                                          endMs: Int($0.endTime * 1000),
                                                          text: $0.text,
                                                          confidence: 1.0) },
            fullText: full,
            language: language,
            processingDurationSeconds: Date().timeIntervalSince(startTime)
        )
    }

    func unloadModel() {
        whisper = nil
        isLoaded = false
        loadedModelID = nil
    }
}
```

---

### 5.3 ModelService (Enhanced)

**Responsibility:** Model discovery, download, delete, integrity verification, custom model import.

**Key design changes from current:**
- Checksum (SHA256) verification after download
- Support importing local `.bin` files via drag-drop or file picker
- Background download continuation across app restart
- Metadata JSON sidecar file for custom models

```swift
@Observable
final class ModelService: ModelRepositoryProtocol {
    private(set) var availableModels: [WhisperModel] = []
    private let fileManager = FileManager.default
    private var downloadTasks: [ModelID: URLSessionDownloadTask] = [:]
    private var urlSession: URLSession

    // Download a model, resume on restart if interrupted
    func downloadModel(_ id: ModelID) async throws {
        guard let model = availableModels.first(where: { $0.id == id }) else { return }
        // Use background URLSession configuration for resume support
        // Write to temporary path, verify SHA256, then move to final path
    }

    // SHA256 verification
    private func verifyChecksum(_ url: URL, expected sha256: String) throws {
        // Compute SHA256 of file, compare to known hash
    }

    // Import a user-provided .bin file
    func importModel(from sourceURL: URL) throws {
        // Copy file into models directory
        // Extract model info from filename heuristic or ask user for name
        // Write metadata JSON sidecar
        // Refresh available models
    }
}
```

**Model registry expanded to include checksums:**
```swift
struct KnownModelDefinition {
    let id: ModelID
    let name: String
    let description: String
    let downloadURL: URL
    let sizeBytes: Int64
    let sha256: String
    let languages: ModelLanguageSupport
}
```

---

### 5.4 TranscriptRepository (NEW)

**Responsibility:** Persist and retrieve transcript sessions.

**Storage:** JSON files in `~/Library/Application Support/com.simpletranscribe/transcripts/`

```swift
final class TranscriptRepository: TranscriptRepositoryProtocol {
    private let storageDirectory: URL

    func save(_ transcript: Transcript) throws {
        let url = storageDirectory.appendingPathComponent("\(transcript.id.uuidString).json")
        let data = try JSONEncoder().encode(transcript)
        try data.write(to: url, options: .atomic)
    }

    func fetchAll() throws -> [Transcript] {
        // Enumerate JSON files, decode, sort by createdAt desc
    }

    func delete(_ id: TranscriptID) throws {
        let url = storageDirectory.appendingPathComponent("\(id.uuidString).json")
        try fileManager.removeItem(at: url)
    }

    func search(query: String) throws -> [Transcript] {
        // Simple string containment search on fullText field
    }
}
```

---

### 5.5 SettingsService (NEW)

**Responsibility:** Persist and retrieve user preferences.

**Storage:** `UserDefaults` with `AppSettings` Codable struct.

```swift
final class SettingsService: SettingsServiceProtocol {
    private let defaults = UserDefaults.standard
    private let key = "com.simpletranscribe.settings"

    var settings: AppSettings {
        get {
            guard let data = defaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
                return AppSettings()  // defaults
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: key)
            }
        }
    }
}
```

---

### 5.6 FileImportService (NEW)

**Responsibility:** Accept audio file URLs, read as PCM Float arrays for transcription.

**Supported formats:** `.mp3`, `.m4a`, `.wav`, `.ogg`, `.flac`, `.aiff`

```swift
final class FileImportService {
    func readAudioFile(_ url: URL) async throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: AVAudioFrameCount(audioFile.length)
        ) else { throw ImportError.bufferCreationFailed }

        let converter = AVAudioConverter(from: audioFile.processingFormat, to: targetFormat)!
        // Read full file, convert, extract Float array
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0],
                                         count: Int(buffer.frameLength)))
    }
}
```

---

## 6. ViewModels

### 6.1 RecordingViewModel

**Owns:** Recording state machine, audio → transcription pipeline.

```swift
@Observable
final class RecordingViewModel {
    enum RecordingState {
        case idle
        case recording
        case processing(progress: Double)
        case error(message: String)
    }

    private(set) var state: RecordingState = .idle
    private(set) var currentText: String = ""
    private(set) var audioLevel: Float = 0.0
    var appendMode: Bool = true

    private let audioService: AudioCaptureServiceProtocol
    private let engine: TranscriptionEngineProtocol
    private let settings: SettingsServiceProtocol
    private let transcriptRepo: TranscriptRepositoryProtocol
    private var accumulatedAudio: [Float] = []
    private var captureTask: Task<Void, Never>?

    func startRecording(device: AudioDevice, language: String) async {
        accumulatedAudio = []
        state = .recording

        captureTask = Task {
            do {
                for await buffer in audioService.audioBuffers {
                    accumulatedAudio.append(contentsOf: buffer)
                    audioLevel = audioService.currentLevel
                }
            } catch {
                state = .error(message: error.localizedDescription)
            }
        }
        try? await audioService.startCapture(device: device)
    }

    func stopAndTranscribe(language: String) async {
        captureTask?.cancel()
        await audioService.stopCapture()
        let audio = accumulatedAudio
        accumulatedAudio = []
        state = .processing(progress: 0)

        do {
            let result = try await engine.transcribe(audio, language: language)
            let newText = result.fullText.trimmingCharacters(in: .whitespaces)
            currentText = appendMode && !currentText.isEmpty
                ? currentText + " " + newText
                : newText
            state = .idle
            // Auto-save if enabled
        } catch {
            state = .error(message: "Transcription failed: \(error.localizedDescription)")
        }
    }

    func clearText() { currentText = "" }
}
```

---

### 6.2 HistoryViewModel (NEW)

```swift
@Observable
final class HistoryViewModel {
    private(set) var transcripts: [Transcript] = []
    private(set) var searchQuery: String = ""
    private(set) var selectedID: TranscriptID?
    private let repo: TranscriptRepositoryProtocol

    func load() throws { transcripts = try repo.fetchAll() }
    func delete(_ id: TranscriptID) throws {
        try repo.delete(id)
        transcripts.removeAll { $0.id == id }
    }
    func search(_ query: String) throws {
        transcripts = query.isEmpty ? try repo.fetchAll() : try repo.search(query: query)
    }
}
```

---

### 6.3 SettingsViewModel (NEW)

```swift
@Observable
final class SettingsViewModel {
    var selectedModelID: ModelID?
    var selectedLanguage: Language = .auto
    var selectedDevice: AudioDevice?
    var autoSaveTranscripts: Bool = true
    var appendMode: Bool = true
    var showWaveform: Bool = true

    private let service: SettingsServiceProtocol
    init(service: SettingsServiceProtocol) { self.service = service; load() }

    func load() {
        let s = service.settings
        selectedModelID = s.selectedModelID
        selectedLanguage = Language.all.first { $0.id == s.selectedLanguageID } ?? .auto
        // ...
    }

    func save() {
        service.settings = AppSettings(
            selectedModelID: selectedModelID,
            selectedLanguageID: selectedLanguage.id,
            // ...
        )
    }
}
```

---

## 7. UI Design

### 7.1 Window Structure

The app uses a **NavigationSplitView** for v2, enabling History sidebar:

```
┌─────────────────────────────────────────────────────────────┐
│  ⬤ ⬤ ⬤   SimpleTranscribe                     🔴 [Stop]    │
├──────────────┬──────────────────────────────────────────────┤
│  SIDEBAR     │  MAIN PANEL                                  │
│              │                                              │
│  ▸ New       │  ┌─ Settings Bar ──────────────────────┐    │
│              │  │ 🎙 MacBook Pro Mic ▾  Base(En) ▾  en ▾│   │
│  ── History ─│  └────────────────────────────────────┘    │
│  Today       │                                              │
│  · Transcript│  ┌─ Waveform ──────────────────────────┐   │
│    2:34pm    │  │  ████▁▄▇█▄▂▁▃▇████▄▁▂▄▇██▄▁▂        │   │
│  · Meeting   │  └────────────────────────────────────┘    │
│    10:00am   │                                              │
│  Yesterday   │  ┌─ Transcript Text ───────────────────┐   │
│  · Voice note│  │  Hello, this is a test of the new    │   │
│    4:12pm    │  │  transcription pipeline. The audio    │   │
│              │  │  quality seems excellent today...     │   │
│              │  │                                       │   │
│              │  │                                       │   │
│              │  └─────────────────────────────── 📋 ─┘   │
│  ─────────── │                                              │
│  ⚙️ Settings  │  [  ⏺ Transcribe  ]    [📂 Import File]    │
└──────────────┴──────────────────────────────────────────────┘
```

### 7.2 RecordingView (Main Panel Content)

**Sub-components:**

1. **SettingsBar** — microphone, model, language pickers in one HStack
2. **WaveformView** — real-time audio level visualization (hidden when not recording if `showWaveform = false`)
3. **TranscriptTextEditor** — editable TextEditor with font/copy controls
4. **ActionBar** — Transcribe button, Import File button, character/word count

### 7.3 WaveformView (NEW)

Visualizes incoming audio level using a scrolling bar graph:

```swift
struct WaveformView: View {
    var levels: [Float]   // Ring buffer of last 100 amplitude values
    var isRecording: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(isRecording ? Color.red.opacity(0.8) : Color.secondary.opacity(0.4))
                    .frame(width: 3, height: CGFloat(max(4, level * 60)))
            }
        }
        .frame(height: 60)
        .animation(.linear(duration: 0.05), value: levels)
    }
}
```

### 7.4 HistorySidebar (NEW)

```swift
struct HistorySidebar: View {
    @Bindable var viewModel: HistoryViewModel

    var body: some View {
        List(selection: $viewModel.selectedID) {
            Button("+ New Transcript") { ... }
            Divider()
            ForEach(groupedByDate) { group in
                Section(group.label) {
                    ForEach(group.transcripts) { t in
                        TranscriptRowView(transcript: t)
                            .tag(t.id)
                    }
                }
            }
        }
        .searchable(text: $viewModel.searchQuery)
        .onChange(of: viewModel.searchQuery) { _, query in
            try? viewModel.search(query)
        }
    }
}
```

### 7.5 ModelManagerView (Enhanced)

Current `ModelDownloadView` enhanced with:
- SHA256 verification status per model
- Custom model import button (file picker for `.bin` files)
- Model size on disk vs. expected size
- Resume interrupted downloads
- Model description expansion toggle

### 7.6 SettingsView (NEW)

Separate `Settings` scene (accessible via ⌘,):

```swift
struct SettingsView: View {
    @Bindable var vm: SettingsViewModel

    var body: some View {
        TabView {
            GeneralSettingsTab(vm: vm).tabItem { Label("General", systemImage: "gear") }
            ModelsSettingsTab(vm: vm).tabItem { Label("Models", systemImage: "square.stack.3d.up") }
            StorageSettingsTab().tabItem { Label("Storage", systemImage: "internaldrive") }
        }
        .frame(width: 480, height: 320)
    }
}
```

**General settings:**
- Default language
- Auto-save transcripts toggle
- Append vs. replace mode toggle
- Show waveform toggle

**Models settings:**
- Default model selector
- Model manager (existing sheet content inlined)

**Storage settings:**
- Models directory location + Open in Finder
- Transcripts directory + total size
- Clear all transcripts button (with confirmation)

---

## 8. macOS Menu Integration (NEW)

```swift
// In simpletranscribeApp.swift
var body: some Scene {
    WindowGroup {
        ContentView()
    }
    .commands {
        CommandGroup(replacing: .newItem) {
            Button("New Transcript") { ... }.keyboardShortcut("n")
        }
        CommandMenu("Recording") {
            Button("Start / Stop Recording") { ... }.keyboardShortcut("r")
            Button("Import Audio File…") { ... }.keyboardShortcut("o")
            Divider()
            Button("Copy Transcript") { ... }.keyboardShortcut("c", modifiers: [.shift, .command])
            Button("Clear Transcript") { ... }
        }
    }

    Settings {
        SettingsView(vm: appEnvironment.settings)
    }
}
```

---

## 9. Error Handling Design

### 9.1 Error Types

```swift
enum AudioError: LocalizedError {
    case microphoneAccessDenied
    case deviceNotFound(id: String)
    case engineStartFailed(underlying: Error)
    case conversionFailed

    var errorDescription: String? { ... }
    var recoverySuggestion: String? { ... }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case modelLoadFailed(path: URL, underlying: Error)
    case inferenceError(underlying: Error)
    case insufficientAudio  // < 0.5s captured

    var errorDescription: String? { ... }
}

enum ModelError: LocalizedError {
    case downloadFailed(url: URL, underlying: Error)
    case checksumMismatch(expected: String, actual: String)
    case fileNotFound(id: ModelID)
    case importFailed(reason: String)
}
```

### 9.2 Error Recovery Actions

Each displayed error includes a recovery action:

| Error | Recovery UI |
|-------|------------|
| Microphone access denied | "Open System Settings" button → `NSWorkspace.open` |
| Model not loaded | "Open Models" button → shows model manager |
| Model checksum mismatch | "Re-download" button → triggers fresh download |
| Transcription failed | "Retry" button → re-runs with same audio |
| File import failed | "Try Again" button → re-shows file picker |

---

## 10. Dependency Injection

All services injected via environment to enable testing:

```swift
// Production environment
extension AppEnvironment {
    static func production() -> AppEnvironment {
        let settings = SettingsService()
        let audioService = AudioCaptureService()
        let engine = WhisperTranscriptionEngine()
        let modelRepo = ModelService()
        let transcriptRepo = TranscriptRepository()
        let fileImport = FileImportService()
        return AppEnvironment(
            recording: RecordingViewModel(audio: audioService, engine: engine,
                                          settings: settings, repo: transcriptRepo),
            history: HistoryViewModel(repo: transcriptRepo),
            models: ModelViewModel(repo: modelRepo),
            settings: SettingsViewModel(service: settings)
        )
    }
}

// Test environment (SwiftUI Preview / Unit Tests)
extension AppEnvironment {
    static func mock() -> AppEnvironment {
        AppEnvironment(
            recording: RecordingViewModel(audio: MockAudioCaptureService(),
                                          engine: MockTranscriptionEngine(),
                                          settings: MockSettingsService(),
                                          repo: InMemoryTranscriptRepository()),
            ...
        )
    }
}

// Injection in view
struct ContentView: View {
    @Environment(AppEnvironment.self) var env
    ...
}
```

---

## 11. Testing Strategy

### 11.1 Unit Tests (Target: `SimpleTranscribeTests`)

| Test Class | What to Test |
|-----------|-------------|
| `RecordingViewModelTests` | State machine transitions, append/replace logic, error propagation |
| `WhisperEngineTests` | Model loading, transcription with mock audio, error on unloaded model |
| `ModelServiceTests` | Download progress tracking, checksum verification, file management |
| `TranscriptRepositoryTests` | CRUD operations, search, sorting by date |
| `SettingsServiceTests` | Encode/decode round-trip, default values |
| `AudioCaptureServiceTests` | Device enumeration, format conversion fidelity |
| `FileImportServiceTests` | Reading .wav files, format conversion |

**Test utilities:**
- `MockAudioCaptureService` — emits pre-recorded test buffers via `AsyncStream`
- `MockTranscriptionEngine` — returns deterministic `TranscriptionResult` 
- `InMemoryTranscriptRepository` — in-memory store, no disk I/O
- `MockModelRepository` — configurable model states
- `TestAudioSamples` — `.wav` fixture files for format conversion tests

### 11.2 UI Tests (Target: `SimpleTranscribeUITests`)

| Test | Scenario |
|------|---------|
| `testRecordButtonToggle` | Button toggles idle ↔ recording state |
| `testModelPickerPopulatesOnLaunch` | Picker shows downloaded models |
| `testCopyButtonCopiesText` | Pasteboard contains text after tap |
| `testHistorySidebarShowsSavedTranscripts` | Saved items appear in sidebar |
| `testImportFileDialogOpens` | File import triggers open panel |

### 11.3 Test Coverage Goal

- Unit tests: **≥ 80%** coverage on Domain + Application layers
- UI tests: **critical user paths** covered
- No coverage requirement on SwiftUI `View` structs

---

## 12. Performance Considerations

| Concern | Design Decision |
|---------|----------------|
| Large model loading time | Load model once at startup, reload only when user changes model; show loading indicator |
| Audio memory accumulation | Cap accumulatedAudio at 30 minutes (30 * 60 * 16000 = 28.8M floats ≈ 115MB); warn user |
| Transcription blocking main thread | `actor WhisperTranscriptionEngine` ensures inference runs off main thread |
| UI waveform performance | Limit waveform buffer to 100 samples, update at 20fps max with `TimelineView` |
| Model download resume | Use `URLSessionConfiguration.background` for downloads > 100MB to survive app backgrounding |
| Transcript search | For large history (>1000 transcripts), consider SQLite FTS5 instead of in-memory filtering |

---

## 13. Security & Privacy

| Area | Approach |
|------|---------|
| Microphone access | Request only when recording starts (already done); show `NSMicrophoneUsageDescription` |
| Camera entitlement | **Remove** — unnecessary, device enum works via `CoreAudio` without it |
| Network access | Limited to model downloads; no telemetry, no analytics |
| Model integrity | SHA256 verification after each download |
| Sandboxing | Keep app sandbox enabled; transcripts stored in App Support |
| No cloud dependency | All transcription offline; no audio data leaves device |
| Transcript privacy | Warn users that saved transcripts persist to disk |

---

## 14. File System Layout (v2)

```
~/Library/Application Support/com.simpletranscribe/
├── models/
│   ├── ggml-tiny.en.bin          (~140 MB)
│   ├── ggml-base.en.bin.sha256   (checksum sidecar)
│   ├── ggml-base.en.bin          (~140 MB)
│   ├── ggml-small.en.bin         (~461 MB)
│   ├── ggml-medium.en.bin        (~1.5 GB)
│   ├── ggml-large-v3.bin         (~2.9 GB)
│   └── custom/
│       ├── my-model.bin          (user-imported)
│       └── my-model.meta.json    (name, language, size)
├── transcripts/
│   ├── A3F12B44-....json
│   ├── B8E22C51-....json
│   └── ...
└── settings.json
```

---

## 15. Implementation Roadmap

### Phase 1 — Foundation & Refactor (no new features)
1. Normalize state to all-`@Observable`; remove `@ObservableObject` / `@StateObject` from TranscriptionManager
2. Extract protocols for AudioCaptureService, TranscriptionEngine, ModelRepository
3. Split ContentView monolith into RecordingView, SettingsBar, ActionBar
4. Add SettingsService + UserDefaults persistence for language, model, device
5. Remove unnecessary camera entitlement
6. Set up unit test target + first batch of model/settings tests

### Phase 2 — Transcript History
7. Implement TranscriptRepository (JSON file store)
8. Implement HistoryViewModel + HistorySidebar
9. Migrate to NavigationSplitView layout
10. Add search to sidebar
11. Auto-save after each successful transcription (if enabled)
12. Add transcript CRUD UI (rename, delete with confirmation)

### Phase 3 — UX Enhancements
13. Add WaveformView with AudioCaptureService.currentLevel feed
14. Add SettingsView scene (accessible via ⌘,)
15. Add macOS menu commands (⌘R to record, ⌘O to import file)
16. Expand language list to all 99 Whisper-supported languages
17. Add word and character count display in ActionBar
18. Add "Append" vs "Replace" mode toggle

### Phase 4 — File Import & Model Hardening
19. Implement FileImportService (mp3/m4a/wav/flac support)
20. Add "Import Audio File" button + drag-and-drop onto text area
21. Add SHA256 verification to model downloads
22. Add custom model import (file picker for .bin files)
23. Support background download resume for large models
24. Add download retry on failure with exponential backoff

### Phase 5 — Polish & Release Prep
25. Add comprehensive UI tests for critical paths
26. Accessibility: VoiceOver labels on all controls, keyboard navigation
27. Notarization & code signing for distribution
28. Build Release configuration + create .dmg installer
29. Write user-facing README / help page
30. Performance audit: memory caps, model loading time, waveform framerate

---

## 16. Dependency Summary (v2)

| Dependency | Version Strategy | Why |
|-----------|-----------------|-----|
| `SwiftWhisper` | Pin to tagged release (not master) | Stability; master had breaking changes |
| `AVFoundation` | System | Audio capture |
| `CoreAudio` | System | Device enumeration without camera permission |
| `Foundation` | System | File I/O, URLSession |
| `CryptoKit` | System | SHA256 model checksum verification |
| `UniformTypeIdentifiers` | System | File type declarations for import |

No new third-party packages introduced. Remove dependency on master-branch pinning of SwiftWhisper.

---

## 17. Open Questions / Decisions Needed

| # | Question | Options | Recommendation |
|---|---------|---------|---------------|
| 1 | Transcript storage format | JSON files vs. SQLite Core Data | JSON for simplicity now; migrate to SQLite if > 10k transcripts becomes a use case |
| 2 | Real-time streaming transcription | VAD-based chunking vs. post-stop only | Post-stop for v2 (streaming needs VAD implementation); add as v3 feature |
| 3 | Settings persistence | UserDefaults vs. JSON file | UserDefaults (simpler, already sandboxed) |
| 4 | macOS minimum version | Stay at 14.0 vs. lower to 13.0 | Stay at 14.0 (uses `@Observable` macro) |
| 5 | App distribution | Direct .app vs. Mac App Store | Direct for now (avoids MAS review delay) |
| 6 | Waveform rendering | Custom Canvas vs. Charts framework | Custom Canvas (Charts too heavyweight for this use) |

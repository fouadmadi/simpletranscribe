# Dev Design #9 — GPU Acceleration

## Problem
Whisper inference uses the CPU only, with thread count = processor count. whisper.cpp supports CoreML on macOS (Metal-accelerated via the CoreML backend) and DirectML / CUDA on Windows. Neither platform currently enables hardware acceleration. On Medium/Large Whisper models this leaves 5–10× speed on the table.

Parakeet ONNX models run through sherpa-onnx, which supports a `provider` field already set to `"cpu"`. sherpa-onnx supports CoreML (Mac) and DirectML (Win) providers too.

---

## Goals
- Enable CoreML acceleration for Whisper on Apple Silicon and Intel Mac (where CoreML is available).
- Enable DirectML acceleration for Whisper on Windows 10/11 with a compatible GPU.
- Enable CoreML/DirectML for Parakeet ONNX where available.
- Fall back gracefully to CPU if GPU acceleration fails or is unavailable.
- Show the active compute backend in the UI (e.g., "Metal", "DirectML", "CPU").

---

## Mac — CoreML for Whisper

### Build change

whisper.cpp already supports a CoreML backend. The app uses `SwiftWhisper`, which wraps whisper.cpp. To enable CoreML:

1. In the Xcode project, set the `WHISPER_COREML=1` Swift flag and link the CoreML framework.
2. Generate CoreML model files (`.mlmodelc`) for each Whisper model using the `whisper.cpp` Python script:
   ```bash
   python3 models/generate-coreml-model.py ggml-base.en.bin
   ```
   This produces `ggml-base.en-encoder.mlmodelc`.
3. Place the `.mlmodelc` bundle alongside the `.bin` file in the models directory.

### ModelService change (Mac)

When discovering a downloaded model, also check for the `.mlmodelc` bundle:

```swift
extension ModelInfo {
    var coreMLModelPath: URL? {
        guard let base = downloadedPath else { return nil }
        // e.g. ggml-base.en-encoder.mlmodelc
        let dir = base.deletingLastPathComponent()
        let name = base.deletingPathExtension().lastPathComponent
        let mlBundleURL = dir.appendingPathComponent("\(name)-encoder.mlmodelc")
        return FileManager.default.fileExists(atPath: mlBundleURL.path) ? mlBundleURL : nil
    }

    var computeBackend: String {
        coreMLModelPath != nil ? "CoreML" : "CPU"
    }
}
```

### TranscriptionManager change (Mac)

`SwiftWhisper` automatically uses CoreML if the `.mlmodelc` bundle is present next to the `.bin` file. No code change needed in `loadWhisperModel` — just ensure the paths are correct.

To expose the backend:

```swift
var activeBackend: String {
    if let model = appModel.currentModel {
        return model.computeBackend
    }
    return "CPU"
}
```

### ModelDownloadView change (Mac)

Add a "Generate CoreML model" button for downloaded Whisper models (or automate during download):

```swift
if model.isAvailable && model.modelType == .whisper && model.coreMLModelPath == nil {
    Button("Generate CoreML (faster on Apple Silicon)") {
        Task { await generateCoreMLModel(for: model) }
    }
    .buttonStyle(.bordered)
    .font(.caption)
}
```

`generateCoreMLModel` runs the Python script in a background shell process — or a pre-built Swift wrapper that calls the CoreML compilation API directly.

> **Simpler alternative:** Bundle pre-built `.mlmodelc` files for small/base/tiny models inside the app and extract them alongside the `.bin` download.

### Parakeet CoreML (Mac)

In `TranscriptionManager.swift`, change `provider: "cpu"` to `"coreml"` when the device supports it:

```swift
let provider: String
#if arch(arm64)
provider = "coreml"   // Apple Silicon — CoreML is fast
#else
provider = "cpu"       // Intel Mac — CoreML overhead may not be worth it
#endif
```

If sherpa-onnx fails to initialise with `"coreml"`, retry with `"cpu"`:

```swift
var recognizer: SherpaOnnxOfflineRecognizer? = SherpaOnnxOfflineRecognizer(config: &config)
if recognizer == nil {
    config.modelConfig.provider = "cpu"
    recognizer = SherpaOnnxOfflineRecognizer(config: &config)
}
```

---

## Windows — DirectML for Whisper

### whisper.cpp DirectML support

whisper.cpp has DirectML support via `WHISPER_DIRECTML=ON` in the CMake build. The Windows app uses P/Invoke against a pre-built `whisper.dll`. The build pipeline must be updated:

1. Build `whisper.dll` with `cmake -DWHISPER_DIRECTML=ON`.
2. Bundle `DirectML.dll` (from the Windows SDK or NuGet `Microsoft.AI.DirectML`) alongside the app.
3. The DLL will attempt GPU init at model load time and fall back to CPU automatically.

No C# source changes are needed for Whisper — the DLL handles device selection internally. However, expose the backend in the UI by adding a `QueryBackend()` P/Invoke call:

```csharp
// WhisperNative.cs
[DllImport("whisper", CallingConvention = CallingConvention.Cdecl)]
public static extern nint whisper_get_system_info();  // returns C string

// In MainViewModel:
public string ActiveBackend =>
    Marshal.PtrToStringAnsi(WhisperNative.GetSystemInfo()) ?? "CPU";
```

Parse the system info string for "DirectML" or "CUDA" to set the backend label.

### Parakeet DirectML (Windows)

In `TranscriptionManager.cs`, change `config.ModelConfig.Provider = "cpu"` to `"directml"` with CPU fallback:

```csharp
private static async Task<OfflineRecognizer> CreateParakeetRecognizer(
    string modelDirectory)
{
    var config = BuildParakeetConfig(modelDirectory, provider: "directml");
    try
    {
        return await Task.Run(() => new OfflineRecognizer(config));
    }
    catch
    {
        // DirectML not available — fall back to CPU
        config = BuildParakeetConfig(modelDirectory, provider: "cpu");
        return await Task.Run(() => new OfflineRecognizer(config));
    }
}
```

---

## UI — Backend Indicator

Add a small badge next to the model name in Settings showing the active compute backend:

**Mac example:**
```swift
HStack {
    Text(currentModel?.name ?? "—")
    Text(activeBackend)
        .font(.caption2)
        .padding(.horizontal, 4).padding(.vertical, 2)
        .background(activeBackend == "CPU" ? Color.secondary.opacity(0.2) : Color.green.opacity(0.2))
        .cornerRadius(4)
}
```

**Windows example:**
```xml
<StackPanel Orientation="Horizontal" Spacing="4">
    <TextBlock Text="{x:Bind _vm.SelectedModelName, Mode=OneWay}"/>
    <Border CornerRadius="3" Padding="4,1">
        <TextBlock Text="{x:Bind _vm.ActiveBackend, Mode=OneWay}"
                   Style="{StaticResource CaptionTextBlockStyle}"/>
    </Border>
</StackPanel>
```

---

## Expected Performance Gains

| Model | CPU (M2 Pro) | CoreML (M2 Pro) | CPU (Win i7) | DirectML (RTX 3060) |
|-------|-------------|----------------|-------------|-------------------|
| Tiny  | ~0.5 s      | ~0.15 s        | ~1 s        | ~0.3 s            |
| Base  | ~1 s        | ~0.3 s         | ~2 s        | ~0.5 s            |
| Small | ~3 s        | ~0.8 s         | ~6 s        | ~1.2 s            |
| Medium| ~8 s        | ~2 s           | ~20 s       | ~3 s              |

*(Approximate. Actual depends on audio length and hardware.)*

---

## Acceptance Criteria
- [ ] On Apple Silicon Mac, CoreML backend is used automatically when `.mlmodelc` is present.
- [ ] On Windows with DirectML-capable GPU, DirectML is used automatically.
- [ ] Falls back to CPU silently if hardware acceleration fails.
- [ ] Active backend ("CoreML", "DirectML", "CPU") shown in the Settings area next to the model name.
- [ ] Transcription results are identical between CPU and GPU paths.
- [ ] App startup time is not significantly increased by backend detection.

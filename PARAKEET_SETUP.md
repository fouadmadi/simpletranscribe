# Parakeet ONNX Model Setup

This document explains how to set up the sherpa-onnx dependency required for NVIDIA Parakeet model support in SimpleTranscribe.

## Windows (C# / WinUI 3)

### 1. Restore NuGet packages

The `org.k2fsa.sherpa.onnx` NuGet package has already been added to `SimpleTranscribe.csproj`. Restore packages:

```bash
cd simpletranscribe-win/SimpleTranscribe
dotnet restore
```

This automatically downloads:
- `org.k2fsa.sherpa.onnx` — managed C# bindings
- `org.k2fsa.sherpa.onnx.runtime.win-x64` — native runtime (x64)

> **Note:** For ARM64 Windows builds, you may need to manually add `org.k2fsa.sherpa.onnx.runtime.win-arm64` if available.

### 2. Build and run

```bash
dotnet build -c Release
```

No additional setup is needed — the NuGet package includes everything.

---

## macOS (Swift / SwiftUI)

### 1. Download sherpa-onnx frameworks

Download the prebuilt xcframeworks from the [sherpa-onnx GitHub releases](https://github.com/k2-fsa/sherpa-onnx/releases):

- `sherpa-onnx.xcframework` (or build from source)
- `onnxruntime.xcframework`

Alternatively, build from source:

```bash
git clone https://github.com/k2-fsa/sherpa-onnx.git
cd sherpa-onnx

# Build for macOS (both arm64 and x86_64)
mkdir build-macos && cd build-macos
cmake \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DSHERPA_ONNX_ENABLE_BINARY=OFF \
  -DBUILD_SHARED_LIBS=ON \
  ..
make -j$(sysctl -n hw.ncpu)
```

### 2. Add frameworks to Xcode project

1. Open `simpletranscribe-mac/simpletranscribe.xcodeproj` in Xcode
2. Select the project target → **General** → **Frameworks, Libraries, and Embedded Content**
3. Click **+** and add both xcframeworks:
   - `sherpa_onnx.xcframework`
   - `onnxruntime.xcframework`
4. Set both to **Embed & Sign**

### 3. Configure the bridging header

1. Select the project target → **Build Settings**
2. Search for **"Objective-C Bridging Header"**
3. Set the value to: `simpletranscribe/SherpaOnnx-Bridging-Header.h`

> The bridging header file (`SherpaOnnx-Bridging-Header.h`) is already created in the project directory.

### 4. Enable the SHERPA_ONNX compilation flag

1. Select the project target → **Build Settings**
2. Search for **"Other Swift Flags"**
3. Add `-DSHERPA_ONNX`

> Without this flag, Parakeet models are hidden from the download list entirely.
> Install the xcframeworks first, then add the flag — both steps are required.

### 5. Add the Swift wrapper to the project

1. In Xcode, right-click the `simpletranscribe` group in the navigator
2. Choose **Add Files to "simpletranscribe"...**
3. Select `SherpaOnnxBridge.swift`
4. Ensure it's added to the `simpletranscribe` target

### 6. Build and run

Build the project in Xcode. The Parakeet models should now load and transcribe audio using the sherpa-onnx offline recognizer.

---

## Downloading Parakeet Models

Models are downloaded through the app's model management UI, just like Whisper models. Available Parakeet models:

| Model | Languages | Size |
|-------|-----------|------|
| Parakeet TDT 0.6B v2 (INT8) | English only | ~661 MB |
| Parakeet TDT 0.6B v3 (INT8) | 27 languages | ~670 MB |

Models are downloaded from HuggingFace and stored as directories containing:
- `encoder.int8.onnx` — encoder network
- `decoder.int8.onnx` — decoder network
- `joiner.int8.onnx` — joiner network
- `tokens.txt` — vocabulary file

Each file is verified via SHA256 hash after download.

---

## Architecture Notes

- **Whisper models**: Single `.bin` file, loaded via SwiftWhisper (macOS) or whisper.cpp P/Invoke (Windows)
- **Parakeet models**: Directory with 4 ONNX files, loaded via sherpa-onnx offline transducer recognizer
- **Audio format**: Both backends use 16kHz mono float32 PCM
- **Inference**: Offline (non-streaming) — the full accumulated audio buffer is processed at once
- The app auto-detects which backend to use based on the model's `ModelType` field

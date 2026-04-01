# SimpleTranscribe for Windows

A Windows 11 native speech-to-text transcription app powered by [whisper.cpp](https://github.com/ggerganov/whisper.cpp).

## Requirements

- Windows 11 (22H2+)
- Visual Studio 2022 17.8+ with **.NET desktop development** and **Windows App SDK** workloads
- .NET 8 SDK

## Building

1. Open `SimpleTranscribe.sln` in Visual Studio 2022
2. Select **x64** or **arm64** platform
3. Build and run

## Versioning (CI/CD)

The Windows app uses semantic versioning, set in `SimpleTranscribe.csproj` and `app.manifest`.

- During CI builds (GitHub Actions), set the `BUILD_VERSION` environment variable (e.g., `1.2.3`) to override the version for that build.
- The version is displayed in the About dialog (Help > About) in the app.
- To increment the version automatically, update the `BUILD_VERSION` variable in your CI workflow.

Example GitHub Actions step:
```yaml
- name: Set version
  run: |
    echo "BUILD_VERSION=1.2.3" >> $GITHUB_ENV
```

## Project Structure

```
SimpleTranscribe/
├── Models/          # Data models (ModelInfo, KnownModels)
├── Services/        # Business logic (Audio, Transcription, Model management)
├── ViewModels/      # MVVM view models
├── Views/           # WinUI 3 XAML user controls
├── Interop/         # P/Invoke bindings (whisper.cpp, Win32)
├── Assets/          # Icons, sounds
└── Native/          # Native DLLs (whisper.dll)
```

## Status

🚧 In development — see [plan.md](../plan.md) for implementation roadmap.

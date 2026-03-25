# SimpleTranscribe

A lightweight macOS menu bar app for speech-to-text transcription powered by [whisper.cpp](https://github.com/ggerganov/whisper.cpp). Record audio, transcribe it locally on your Mac, and automatically paste the result at your cursor.

## Features

- **Press-to-talk hotkey** — Hold `fn + ctrl` to record, release to transcribe
- **100% local** — All transcription runs on-device using Whisper models, no cloud APIs
- **Auto-paste** — Transcribed text is copied to clipboard and pasted at your cursor automatically
- **Multiple models** — Download and switch between Whisper models (Tiny → Large) from within the app
- **Sound feedback** — Audio cues for recording start, transcription complete, and errors
- **Multi-language** — Supports English, Spanish, French, German, Chinese, and auto-detect

## Requirements

- macOS 15.7 or later
- Xcode 16+ (to build from source)
- ~140 MB–2.9 GB disk space depending on model choice

## Getting Started

1. **Build & run** the project in Xcode
2. On first launch, click **Download** in the orange banner to get a Whisper model
   - *Tiny (English)* is recommended to start (~140 MB, fastest)
3. The model loads automatically once downloaded — you're ready to transcribe

## Usage

### Button
Click **Transcribe** to start recording, click **Stop** to end and transcribe.

### Hotkey (recommended)
Hold **fn + ctrl** anywhere on your Mac to record. Release to stop, transcribe, and auto-paste at your cursor.

### Permissions
On first use you may be prompted for:
- **Microphone access** — required for recording
- **Accessibility / System Events** — required for auto-paste at cursor (⌘V simulation)

## Models

| Model | Size | Speed | Accuracy |
|-------|------|-------|----------|
| Tiny (English) | ~140 MB | Fastest | Lower |
| Base (English) | ~140 MB | Fast | Balanced |
| Small (English) | ~461 MB | Moderate | Good |
| Medium (English) | ~1.5 GB | Slow | High |
| Large (Multilingual) | ~2.9 GB | Very slow | Highest |

Manage models from the **Models** button in the toolbar.

## Architecture

- **SwiftUI** app using Swift Observation (`@Observable`)
- **SwiftWhisper** SPM package wrapping whisper.cpp
- **AVAudioEngine** for microphone capture (16kHz mono float32)
- **NSEvent** global/local monitors for hotkey detection
- Sandboxed with entitlements for audio, network, and automation

## Known issues

- the app fails to transcribe when using the multilanguage model

## License

MIT

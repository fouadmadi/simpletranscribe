# SimpleTranscribe

A lightweight speech-to-text transcription app powered by [whisper.cpp](https://github.com/ggerganov/whisper.cpp). Record audio, transcribe it locally on your device, and automatically paste the result at your cursor.

## Platforms

| Platform | Directory | Status |
|----------|-----------|--------|
| **macOS** | [`simpletranscribe-mac/`](simpletranscribe-mac/) | ✅ Available |
| **Windows** | [`simpletranscribe-win/`](simpletranscribe-win/) | 🚧 In development |

## Features

- **Press-to-talk hotkey** — Hold a hotkey to record, release to transcribe
- **100% local** — All transcription runs on-device using Whisper models, no cloud APIs
- **Auto-paste** — Transcribed text is copied to clipboard and pasted at your cursor automatically
- **Multiple models** — Download and switch between Whisper models (Tiny → Large) from within the app
- **Sound feedback** — Audio cues for recording start, transcription complete, and errors
- **Multi-language** — Supports English, Spanish, French, German, Chinese, and auto-detect

## Models

| Model | Size | Speed | Accuracy |
|-------|------|-------|----------|
| Tiny (English) | ~77 MB | Fastest | Lower |
| Base (English) | ~148 MB | Fast | Balanced |
| Small (English) | ~461 MB | Moderate | Good |
| Medium (English) | ~1.5 GB | Slow | High |
| Large (Multilingual) | ~2.9 GB | Very slow | Highest |

## Getting Started

### macOS

See [`simpletranscribe-mac/`](simpletranscribe-mac/) — requires macOS 15.0+, Xcode 16+.

### Windows

See [`simpletranscribe-win/`](simpletranscribe-win/) — requires Windows 11, Visual Studio 2022 17.8+.

## License

MIT

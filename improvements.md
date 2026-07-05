# SimpleTranscribe — Improvement Analysis

Analysis of the macOS (Swift/SwiftUI) and Windows (C#/WinUI 3) versions of SimpleTranscribe.
Each item is numbered and corresponds to a detailed design document in `/dev-designs/`.

---

## Summary of Current State

Both apps share strong architectural parity: push-to-talk hotkey, Whisper + Parakeet ONNX backends, model download manager with SHA-256 verification, automatic microphone hot-plug, floating overlay status, and auto-paste-at-cursor. Code quality is solid. The gaps below are in UX completeness, power-user features, performance, and platform parity.

---

## Improvements

### UX & Workflow

| # | Title | Affects | Priority |
|---|-------|---------|----------|
| 1 | [Configurable Hotkey](dev-designs/01-configurable-hotkey.md) | Mac + Win | High |
| 2 | [Transcript History](dev-designs/02-transcript-history.md) | Mac + Win | High |
| 3 | [Expanded Language Support](dev-designs/03-expanded-language-support.md) | Mac + Win | Medium |
| 4 | [Live Transcription Preview](dev-designs/04-live-transcription-preview.md) | Mac + Win | Medium |
| 5 | [Post-Processing Pipeline](dev-designs/05-post-processing-pipeline.md) | Mac + Win | Medium |
| 6 | [Transcript Export](dev-designs/06-transcript-export.md) | Mac + Win | Medium |
| 7 | [Auto-Clear & Word Count](dev-designs/07-auto-clear-and-word-count.md) | Mac + Win | Low |
| 8 | [Font Size Control](dev-designs/08-font-size-control.md) | Mac + Win | Low |

### Technical & Performance

| # | Title | Affects | Priority |
|---|-------|---------|----------|
| 9  | [GPU Acceleration](dev-designs/09-gpu-acceleration.md) | Mac + Win | High |
| 10 | [Recording Time Limit Warning](dev-designs/10-recording-limit-warning.md) | Mac + Win | Medium |
| 11 | [Paste Failure Notification](dev-designs/11-paste-failure-notification.md) | Mac + Win | Medium |
| 12 | [Download Speed & ETA](dev-designs/12-download-speed-eta.md) | Mac + Win | Low |
| 13 | [Model Load Cancellation](dev-designs/13-model-load-cancellation.md) | Mac + Win | Low |

### Platform Parity

| # | Title | Affects | Priority |
|---|-------|---------|----------|
| 14 | [Mac Menu Bar Icon](dev-designs/14-mac-menu-bar-icon.md) | Mac only | High |
| 15 | [Windows Floating Overlay](dev-designs/15-windows-floating-overlay.md) | Win only | High |

---

## Detailed Findings

### 1 — Configurable Hotkey
`fn+Control` (Mac) and `Ctrl+Space` (Win) are hardcoded. Users working in apps that already use those combos (e.g., IDEs using Ctrl+Space for autocomplete) cannot remap. There is no UI surface for changing the hotkey.

### 2 — Transcript History
Every recording either replaces or appends to a single text area. Once the user clears it or the app restarts, all transcriptions are gone. There is no per-session history, timestamp, or ability to recall what was transcribed 5 minutes ago.

### 3 — Expanded Language Support
The language picker is hardcoded to 6 options (auto, en, es, fr, de, zh). Whisper supports ~100 languages. The Parakeet V3 model covers 27 languages but the UI does not surface them. Non-English-primary users are poorly served.

### 4 — Live Transcription Preview
All audio is accumulated in memory and processed in a single batch after the user releases the hotkey. There is no partial/streaming output during recording. For long dictations, users must wait until the end to see any text.

### 5 — Post-Processing Pipeline
Parakeet models produce output with no punctuation and lowercase only. Whisper models vary. There is no post-processing layer (punctuation restoration, smart capitalisation, number-to-digit conversion, filler-word removal). Output quality could be improved without changing the model.

### 6 — Transcript Export
The only output options are copy-to-clipboard and auto-paste. There is no way to save the transcript to a file (.txt, .md, .srt with timestamps).

### 7 — Auto-Clear & Word Count
No option to auto-clear the transcript box after each auto-paste (useful for continuous dictation into another app). No word count, character count, or recording duration is shown to the user.

### 8 — Font Size Control
The transcript `TextEditor` / `TextBox` uses the system default body font at a fixed size. Users who dictate long texts or who have accessibility needs cannot adjust it.

### 9 — GPU Acceleration
Whisper inference runs on the CPU via whisper.cpp with thread count = processor count. macOS supports CoreML acceleration (already compiled into whisper.cpp via `WHISPER_COREML`). Windows supports DirectML and CUDA via whisper.cpp and ONNX Runtime. Neither platform enables hardware acceleration, leaving significant speed on the table — especially for Medium/Large models.

### 10 — Recording Time Limit Warning
`TranscriptionManager` silently stops accumulating audio at 30 minutes (30 × 60 × 16 000 samples). The user gets no warning as the limit approaches and no indication that their recording was truncated.

### 11 — Paste Failure Notification
On Mac, all three paste strategies (CGEvent, AppleScript, osascript) can silently fail — the text is on the clipboard but no toast/alert tells the user "Auto-paste failed — press ⌘V". On Windows the same silent failure occurs for elevated target windows (UIPI).

### 12 — Download Speed & ETA
Model downloads only show a percentage progress bar. No download speed (MB/s) or estimated time remaining is shown. For large models (Parakeet ~660 MB, Whisper Large ~3 GB) this is a poor experience.

### 13 — Model Load Cancellation
Once `loadModel()` / `LoadModelAsync()` is called, it cannot be cancelled. Whisper model loading (especially Large) can take 5–15 seconds. There is no cancel button and no timeout.

### 14 — Mac Menu Bar Icon
The Windows version has a full system tray icon with context menu (Open, Start at Login, Quit) via `TrayIconManager`. The Mac version has no equivalent menu bar status item — the app only shows a floating overlay when recording. Users must bring the app window to the foreground to quit or access settings. A menu bar icon would also allow recording from a fully hidden window.

### 15 — Windows Floating Overlay
The Mac version has a `FloatingOverlayWindow` that appears in the top-right corner during recording/transcription states. Windows has no equivalent — state is only visible in the main window (which may be hidden to the tray). Users have no ambient feedback during recording when the window is hidden.

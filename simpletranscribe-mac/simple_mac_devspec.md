# Simple Transcribe for macOS — Development Specification

## 1. Overview

The goal is to build a highly simplified, single-window macOS native application for audio transcription. Unlike complex menu-bar or overlay-based tools, this app provides a straightforward graphical interface where users can start/stop recording and immediately see the transcribed text, along with basic configuration parameters.

## 2. Technology Stack

- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI
- **Audio Capture:** AVFoundation (`AVAudioEngine` or `AVAudioRecorder`)
- **Transcription Engine:**
  - Option A: Apple's native `Speech` framework (`SFSpeechRecognizer`) for zero-dependency, out-of-the-box transcription.
  - Option B: `whisper.cpp` Swift package if local, offline open-source models are required.
- **Target OS:** macOS 14.0+

## 3. User Interface (UI)

The application will consist of a **single monolithic window** containing:

1.  **Header/Controls Area:**
    - **Transcribe Button:** Starts microphone capture. Changes state (e.g., color turns red, pulsing animation) while recording.
    - **Stop Button:** Ends audio capture and triggers the final transcription process (if not streaming).
2.  **Parameters/Settings Area (Collapsible or Sidebar):**
    - **Microphone Input:** Dropdown to select the audio capture device.
    - **Language:** Dropdown to select the target transcription language (e.g., English, Auto-detect).
    - _(If using Whisper)_ **Model Selection:** Dropdown to choose the model size (Tiny, Base, Small).
3.  **Results Area:**
    - A large, scrollable `TextEditor` or `NSTextView` taking up the majority of the window.
    - Displays the real-time (if supported) or final transcribed text.
    - **Copy Button:** A quick-action button in the corner to copy the result to the macOS clipboard.

## 4. Architecture / Data Flow

### 4.1. Core Components

- **`AppModel` (Observable Object / Macro):** Holds the application state:
  - `isRecording`: Boolean
  - `transcribedText`: String
  - `selectedInputDevice`: AudioDevice
  - `selectedLanguage`: String
- **`AudioManager`:** Handles interaction with `AVFoundation`.
  - Requests microphone permissions using `AVCaptureDevice.requestAccess`.
  - Manages the `AVAudioEngine` input node.
  - Writes audio to a temporary file (e.g., `.wav`) or streams buffers directly to the recognizer.
- **`TranscriptionManager`:**
  - Receives audio buffers or the final file URL from `AudioManager`.
  - Processes the audio into text using the chosen engine.
  - Publishes string updates back to the `AppModel`.

### 4.2. State Machine

1.  **Idle:** UI shows "Transcribe". Text area is empty or holds previous result.
2.  **Recording:** User clicks "Transcribe".
    - App requests/verifies Microphone permissions.
    - `AudioManager` starts engine.
    - UI buttons update ("Transcribe" disabled, "Stop" enabled).
3.  **Processing (Optional phase):** User clicks "Stop".
    - `AudioManager` stops and finalizes audio file.
    - `TranscriptionManager` processes the complete file (if not using real-time streaming).
    - UI shows a loading indicator.
4.  **Complete:** Transcription finishes.
    - Text area populates with the final string.
    - State returns to Idle.

## 5. Security & Permissions

The app requires the following configuration in `Info.plist` and sandbox entitlements:

- **Microphone Usage Description:** `NSMicrophoneUsageDescription` explaining why audio capture is needed.
- **App Sandbox:**
  - Hardware (Audio Input) must be checked.
  - Network (Client) might be required if using Apple's cloud-backed `SFSpeechRecognizer`.

## 6. Implementation Steps

1.  **Project Setup:** Create a new macOS SwiftUI project in Xcode. Configure Sandbox and Info.plist permissions.
2.  **UI Layout:** Build the main `ContentView` with the buttons, pickers for parameters, and the text area.
3.  **Audio Engine:** Implement the `AudioManager` class to handle selecting inputs and capturing audio to memory/disk.
4.  **Transcription Engine Integration:** Implement the `TranscriptionManager` to convert the captured audio to text and update the UI binding.
5.  **Refinement:** Add error handling (e.g., missing permissions, unrecognized speech), loading states, and the "Copy to Clipboard" utility.

# Dev Design #10 — Recording Time Limit Warning

## Problem
`TranscriptionManager` silently stops accumulating audio after 30 minutes (30 × 60 × 16 000 = 28,800,000 samples). The user receives no warning as the limit approaches and no indication that their recording was silently truncated. This could cause data loss in long dictation or meeting-capture sessions.

---

## Goals
- Show a visual warning (in the floating overlay and the main window) when the recording approaches the 30-minute cap (e.g., with 2 minutes remaining).
- Show a distinct "Max recording length reached" state when the cap is hit.
- Optionally auto-stop and auto-transcribe when the cap is hit, rather than silently dropping audio.
- Make the cap and warning threshold configurable in Settings (advanced).

---

## Implementation

### Shared concept

Track elapsed recording time in `AppModel` and compare against `TranscriptionManager.maxSamples`:

```
maxSamples = 30 * 60 * 16_000
warningSamples = maxSamples - (2 * 60 * 16_000)   // 28 min threshold
```

`TranscriptionManager` must expose the current sample count so `AppModel` can poll it.

---

## Mac Design (Swift)

### TranscriptionManager — expose sample count

```swift
// TranscriptionManager.swift
var accumulatedSampleCount: Int {
    audioLock.lock()
    defer { audioLock.unlock() }
    return accumulatedAudio.count
}

static let maxSamples = 30 * 60 * 16_000
static let warningSamples = maxSamples - (2 * 60 * 16_000) // 2 min warning
```

### AppModel — polling timer

Add a `Timer` that fires every second while recording is active:

```swift
// AppModel.swift
var recordingTimeLimitWarning: Bool = false
var recordingTimeLimitReached: Bool = false
@ObservationIgnored private var recordingTimer: Timer?

private func startRecordingTimer() {
    recordingTimeLimitWarning = false
    recordingTimeLimitReached = false
    recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
        self?.checkRecordingTimeLimit()
    }
}

private func stopRecordingTimer() {
    recordingTimer?.invalidate()
    recordingTimer = nil
}

private func checkRecordingTimeLimit() {
    guard let tm = transcriptionManager else { return }
    let count = tm.accumulatedSampleCount
    if count >= TranscriptionManager.maxSamples {
        recordingTimeLimitReached = true
        recordingTimeLimitWarning = false
        // Auto-stop: treat as hotkey release
        stopRecordingAndTranscribe(autoPaste: true)
        stopRecordingTimer()
    } else if count >= TranscriptionManager.warningSamples {
        recordingTimeLimitWarning = true
    }
}

// Call startRecordingTimer() in startRecording()
// Call stopRecordingTimer() in stopRecordingAndTranscribe()
```

### OverlayState — new cases

```swift
// FloatingOverlayView.swift
enum OverlayState: Equatable {
    case idle
    case recording
    case recordingWarning    // NEW — approaching time limit
    case transcribing
    case done
    case error(String)
}
```

In `AppModel.checkRecordingTimeLimit()`, set `overlayState = .recordingWarning` when the warning threshold is crossed.

### FloatingOverlayView — warning state

```swift
case .recordingWarning:
    Circle()
        .fill(Color.orange)
        .frame(width: 12, height: 12)
        .opacity(pulseOpacity)
        .onAppear { /* same pulse animation */ }
    Text("Recording — 2 min left")
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(.orange)
```

### RecordingControlsView — time display

While recording, show elapsed time:

```swift
if isRecording {
    Text(timeString(elapsed))
        .font(.caption.monospacedDigit())
        .foregroundColor(timeLimitWarning ? .orange : .secondary)
}
```

`elapsed` is the seconds since `recordingStartTime`. Compute in `AppModel` as a `@Published`/`@Observable` `recordingElapsedTime: TimeInterval` updated by the same 1-second timer.

---

## Windows Design (C#)

### TranscriptionManager — expose sample count

```csharp
// TranscriptionManager.cs
public const int MaxSamples = 30 * 60 * 16_000;
public const int WarningSamples = MaxSamples - (2 * 60 * 16_000);

public int AccumulatedSampleCount
{
    get
    {
        _audioLock.Wait();
        try { return _accumulatedAudio.Count; }
        finally { _audioLock.Release(); }
    }
}
```

### MainViewModel — polling timer

```csharp
[ObservableProperty] private bool _recordingTimeLimitWarning;
[ObservableProperty] private bool _recordingTimeLimitReached;
[ObservableProperty] private string _recordingElapsedLabel = "";

private System.Timers.Timer? _recordingTimer;

private void StartRecordingTimer()
{
    RecordingTimeLimitWarning = false;
    RecordingTimeLimitReached = false;
    _recordingStartTime = DateTime.UtcNow;
    _recordingTimer = new System.Timers.Timer(1000);
    _recordingTimer.Elapsed += (_, _) => CheckRecordingTimeLimit();
    _recordingTimer.Start();
}

private void StopRecordingTimer()
{
    _recordingTimer?.Stop();
    _recordingTimer?.Dispose();
    _recordingTimer = null;
    RecordingElapsedLabel = "";
}

private void CheckRecordingTimeLimit()
{
    var count = _transcriptionManager.AccumulatedSampleCount;
    var elapsed = (DateTime.UtcNow - _recordingStartTime).TotalSeconds;
    var mm = (int)elapsed / 60;
    var ss = (int)elapsed % 60;

    _syncContext?.Post(_ =>
    {
        RecordingElapsedLabel = $"{mm:D2}:{ss:D2}";

        if (count >= TranscriptionManager.MaxSamples)
        {
            RecordingTimeLimitReached = true;
            RecordingTimeLimitWarning = false;
            StopRecordingAndTranscribe(autoPaste: true);
            StopRecordingTimer();
        }
        else if (count >= TranscriptionManager.WarningSamples)
        {
            RecordingTimeLimitWarning = true;
        }
    }, null);
}
```

### UI

In `RecordingControlsPanel.xaml`, add an elapsed time label visible while recording:

```xml
<TextBlock x:Name="ElapsedLabel"
           Text="{x:Bind _vm.RecordingElapsedLabel, Mode=OneWay}"
           Foreground="{x:Bind _vm.RecordingTimeLimitWarning,
               Converter={StaticResource BoolToWarningBrushConverter}, Mode=OneWay}"
           Style="{StaticResource CaptionTextBlockStyle}"/>
```

Show a `InfoBar` warning in the main window when `RecordingTimeLimitWarning` is true:
```xml
<InfoBar x:Name="TimeLimitWarningBar"
         IsOpen="{x:Bind _vm.RecordingTimeLimitWarning, Mode=OneWay}"
         Severity="Warning"
         Title="Approaching recording limit"
         Message="Less than 2 minutes of recording time remaining."/>
```

---

## Auto-Stop Behaviour

When the cap is reached, the app automatically calls `stopRecordingAndTranscribe(autoPaste: true)` as if the user released the hotkey. The transcription proceeds normally. A brief overlay message `"Max length reached — transcribing…"` is shown.

This is safer than silently dropping samples, and matches user expectation that releasing the hotkey always produces a transcription.

---

## Settings (Advanced)

Optionally expose the max recording duration in Settings (clamped to 1–60 min):

```
Max recording length: [30] minutes  (slider or stepper)
```

Stored in `UserDefaults` / `settings.json`. Both `TranscriptionManager.maxSamples` and the warning threshold should be recomputed from this value.

---

## Acceptance Criteria
- [ ] Elapsed recording time displayed in the recording controls while recording.
- [ ] Warning state (orange overlay, warning banner) appears with 2 minutes remaining.
- [ ] At the 30-minute cap, recording stops automatically and transcription begins.
- [ ] A "Max recording length reached" message is shown briefly after auto-stop.
- [ ] No audio samples are silently dropped — all audio up to the cap is transcribed.
- [ ] Timer and warning state reset cleanly when a new recording starts.

# Dev Design #4 — Live Transcription Preview

## Problem
Audio is accumulated entirely in memory, then processed in one batch after the hotkey is released. For long dictations (30 s – several minutes), the user sees nothing until the whole recording is done. This feels unresponsive and gives no confidence the microphone is working.

---

## Goals
- Show partial transcription text appearing in the transcript area as the user speaks.
- Keep the batch-final pass for accuracy (streaming Whisper is less accurate than full-context inference).
- Add a "streaming quality" vs "batch quality" toggle in Settings.
- Ensure streaming does not block the UI thread.

---

## Architecture Overview

```
Microphone → AudioManager (16kHz float buffers)
                │
                ├─► TranscriptionManager.appendAudio()   [existing, unchanged]
                │
                └─► StreamingTranscriber (NEW)
                        │
                        ▼
                    Chunked inference (e.g. every 3s of audio)
                        │
                        ▼
                    AppModel.liveTranscriptText (NEW)
                        │
                        ▼
                    TranscriptResultsView (partial preview)
```

The final batch transcription (existing path) still runs on hotkey release and replaces `liveTranscriptText` with the authoritative result.

---

## Mac Design (Swift)

### New class: `StreamingTranscriber.swift`

```swift
actor StreamingTranscriber {
    private let chunkDuration: TimeInterval = 3.0   // seconds of audio per chunk
    private let sampleRate: Double = 16_000
    private var buffer: [Float] = []
    private var whisper: Whisper?
    private var isRunning = false

    func start(whisper: Whisper) {
        self.whisper = whisper
        buffer.removeAll()
        isRunning = true
    }

    func stop() { isRunning = false; buffer.removeAll() }

    /// Called from AudioManager callback — appends samples and transcribes when chunk is full.
    func feed(samples: [Float]) async -> String? {
        guard isRunning else { return nil }
        buffer.append(contentsOf: samples)

        let chunkSamples = Int(chunkDuration * sampleRate)
        guard buffer.count >= chunkSamples else { return nil }

        let chunk = Array(buffer.prefix(chunkSamples))
        buffer.removeFirst(chunkSamples)

        guard let w = whisper else { return nil }
        do {
            let segments = try await w.transcribe(audioFrames: chunk)
            return segments.map { $0.text }.joined(separator: " ")
        } catch {
            return nil
        }
    }
}
```

### AppModel changes

```swift
// Add to AppModel:
var liveTranscriptText: String = ""             // partial preview
var streamingEnabled: Bool = UserDefaults.standard.bool(forKey: "streamingEnabled") {
    didSet { UserDefaults.standard.set(streamingEnabled, forKey: "streamingEnabled") }
}
@ObservationIgnored private var streamingTranscriber: StreamingTranscriber?

// In setupAudio():
audioManager?.onBufferReceived = { [weak self] buffer in
    guard let self else { return }
    // existing batch path
    if self._isRecordingAtomic {
        self.transcriptionManager?.appendAudio(buffer: buffer)
    }
    // streaming preview path
    if self.streamingEnabled, self.isRecording {
        Task {
            if let partial = await self.streamingTranscriber?.feed(samples: buffer) {
                await MainActor.run {
                    self.liveTranscriptText += partial + " "
                }
            }
        }
    }
}

// In startRecording():
liveTranscriptText = ""
if streamingEnabled, let w = transcriptionManager?.whisper {
    streamingTranscriber = StreamingTranscriber()
    await streamingTranscriber?.start(whisper: w)
}

// In stopRecordingAndTranscribe():
streamingTranscriber?.stop()
// After batch result arrives, replace liveTranscriptText with trimmed batch result
```

### TranscriptResultsView changes

Display `liveTranscriptText` in italics below the TextEditor while recording:

```swift
if isRecording && !liveTranscriptText.isEmpty {
    Text(liveTranscriptText)
        .italic()
        .foregroundColor(.secondary)
        .font(.body)
        .padding(.horizontal)
}
```

Or replace the content of the `TextEditor` live, and swap for the batch result on completion.

---

## Windows Design (C#)

### New class: `StreamingTranscriber.cs`

```csharp
public class StreamingTranscriber : IDisposable
{
    private readonly double _chunkDurationSec;
    private readonly List<float> _buffer = new();
    private readonly SemaphoreSlim _lock = new(1, 1);
    private nint _ctx;                     // Whisper context (shared reference, NOT owned)
    private bool _running;

    public StreamingTranscriber(nint sharedCtx, double chunkDurationSec = 3.0)
    {
        _ctx = sharedCtx;
        _chunkDurationSec = chunkDurationSec;
    }

    public void Start() { _buffer.Clear(); _running = true; }
    public void Stop()  { _running = false; _buffer.Clear(); }

    /// Returns partial text if a full chunk was processed, otherwise null.
    public async Task<string?> FeedAsync(float[] samples)
    {
        if (!_running) return null;

        await _lock.WaitAsync();
        try { _buffer.AddRange(samples); }
        finally { _lock.Release(); }

        var chunkSamples = (int)(_chunkDurationSec * 16_000);
        if (_buffer.Count < chunkSamples) return null;

        await _lock.WaitAsync();
        float[] chunk;
        try
        {
            chunk = _buffer.Take(chunkSamples).ToArray();
            _buffer.RemoveRange(0, chunkSamples);
        }
        finally { _lock.Release(); }

        return await Task.Run(() => RunWhisperChunk(chunk));
    }

    private string RunWhisperChunk(float[] chunk)
    {
        using var pars = WhisperParams.CreateDefault(WhisperSamplingStrategy.Greedy);
        pars.NThreads     = Math.Max(1, Environment.ProcessorCount / 2); // half threads for streaming
        pars.NoContext    = true;
        pars.SingleSegment = true;
        pars.PrintProgress = false;

        if (WhisperNative.Full(_ctx, pars.Pointer, chunk, chunk.Length) != 0)
            return "";

        var n = WhisperNative.FullNSegments(_ctx);
        var parts = new List<string>();
        for (int i = 0; i < n; i++)
            parts.Add(WhisperHelpers.GetSegmentText(_ctx, i));
        return string.Join(" ", parts).Trim();
    }

    public void Dispose() => _lock.Dispose();
}
```

### MainViewModel changes

```csharp
[ObservableProperty] private string _liveTranscriptText = "";
[ObservableProperty] private bool _streamingEnabled;
private StreamingTranscriber? _streamingTranscriber;

// In AudioManager.OnBufferReceived:
if (StreamingEnabled && IsRecording && _streamingTranscriber != null)
{
    _ = _streamingTranscriber.FeedAsync(buffer).ContinueWith(t =>
    {
        if (t.Result is { } partial && !string.IsNullOrEmpty(partial))
            _syncContext?.Post(_ => LiveTranscriptText += partial + " ", null);
    }, TaskScheduler.Default);
}
```

### UI binding

Bind `LiveTranscriptText` to an italic `TextBlock` overlaid below the main `TextBox`, visible only while `IsRecording`.

---

## Limitations & Notes

- **Streaming is Whisper-only.** Parakeet is faster in batch mode and its API is not designed for sub-3s chunks. If Parakeet is selected, streaming preview is disabled automatically.
- **Accuracy trade-off.** Streaming chunks lack future context, so accuracy is lower than the final batch pass. The final result always replaces the preview.
- **Thread safety.** The Whisper context is shared between streaming inference and the final batch pass. Use a `SemaphoreSlim` (Win) / `NSLock` (Mac) to ensure only one inference runs at a time. If a streaming chunk is in-flight when the hotkey is released, wait for it to complete before starting the batch pass.
- **Battery / thermal.** Continuous inference every 3 s is CPU-intensive. Consider raising the chunk size to 5 s for lower-end machines, or letting the user configure it.

---

## Settings

Add a toggle to `SettingsAreaView` / `SettingsPanel`:

```
☐ Live preview (Whisper models only, lower accuracy while recording)
```

Default: **off** (preserve existing behaviour).

---

## Acceptance Criteria
- [ ] With streaming enabled, partial text appears in the transcript area within 3–5 s of speaking.
- [ ] The final batch result replaces the preview text after the hotkey is released.
- [ ] Streaming is disabled automatically when a Parakeet model is selected.
- [ ] Streaming toggle persists across restarts.
- [ ] No UI freeze or audio drop-out during streaming inference.
- [ ] Auto-paste uses the final batch result, not the live preview.

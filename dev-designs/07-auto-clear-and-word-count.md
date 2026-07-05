# Dev Design #7 — Auto-Clear & Word Count

## Problem
- The transcript text area accumulates all recordings in a single string. There is no option to auto-clear between recordings (useful for continuous dictation into another app via auto-paste).
- No word count, character count, or recording duration is shown. Users have no sense of how much they've said or how efficient the transcription is.

---

## Goals
- Add an "Auto-clear after paste" toggle.
- Show word count, character count, and last-recording duration in a status bar below the transcript.
- Keep existing behaviour (append with space) as the default.

---

## Mac Design (Swift)

### AppModel changes

```swift
// AppModel.swift
var autoClearAfterPaste: Bool = UserDefaults.standard.bool(forKey: "autoClearAfterPaste") {
    didSet { UserDefaults.standard.set(autoClearAfterPaste, forKey: "autoClearAfterPaste") }
}

var lastRecordingDuration: TimeInterval = 0

// In stopRecordingAndTranscribe(), after successful transcription:
if autoPaste && autoClearAfterPaste {
    // Paste happens, then clear
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        self.transcribedText = ""
    }
}
```

Track duration:

```swift
private var recordingStartTime: Date?

// In startRecording():
recordingStartTime = Date()

// In stopRecordingAndTranscribe(), on success:
if let start = recordingStartTime {
    lastRecordingDuration = Date().timeIntervalSince(start)
}
```

### New view: `TranscriptStatusBar.swift`

```swift
struct TranscriptStatusBar: View {
    let text: String
    let lastDuration: TimeInterval

    private var wordCount: Int {
        text.split(separator: " ").count
    }
    private var charCount: Int { text.count }
    private var durationLabel: String {
        lastDuration < 1 ? "" : String(format: "%.0fs recorded", lastDuration)
    }

    var body: some View {
        HStack(spacing: 16) {
            if !text.isEmpty {
                Text("\(wordCount) words")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(charCount) chars")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if !durationLabel.isEmpty {
                Text(durationLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
```

Place `TranscriptStatusBar` below `TranscriptResultsView` in `ContentView`.

### Auto-clear toggle in SettingsAreaView

```swift
Toggle("Auto-clear after paste", isOn: $appModel.autoClearAfterPaste)
    .toggleStyle(.checkbox)
    .font(.caption)
    .help("Clears the transcript box after each auto-paste")
```

---

## Windows Design (C#)

### MainViewModel changes

```csharp
[ObservableProperty] private bool _autoClearAfterPaste;
[ObservableProperty] private double _lastRecordingDuration;
[ObservableProperty] private int _wordCount;
[ObservableProperty] private int _charCount;

partial void OnAutoClearAfterPasteChanged(bool value) =>
    SaveSetting("autoClearAfterPaste", value.ToString());

partial void OnTranscribedTextChanged(string value)
{
    WordCount = string.IsNullOrEmpty(value)
        ? 0 : value.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length;
    CharCount = value.Length;
}

// In StopRecordingAndTranscribe, after paste:
if (autoPaste && AutoClearAfterPaste)
{
    await Task.Delay(300);
    TranscribedText = "";
}
```

### UI — Status bar in MainWindow.xaml

Add a `StackPanel` row below `TranscriptResults`:

```xml
<StackPanel Orientation="Horizontal" Spacing="16" Padding="8,4"
            Background="{ThemeResource SystemColorButtonFaceColor}">
    <TextBlock Text="{x:Bind _vm.WordCount, Mode=OneWay, Converter={StaticResource WordCountConverter}}"
               Style="{StaticResource CaptionTextBlockStyle}"/>
    <TextBlock Text="{x:Bind _vm.CharCount, Mode=OneWay, Converter={StaticResource CharCountConverter}}"
               Style="{StaticResource CaptionTextBlockStyle}"/>
    <TextBlock Text="{x:Bind _vm.LastRecordingDurationLabel, Mode=OneWay}"
               Style="{StaticResource CaptionTextBlockStyle}"/>
</StackPanel>
```

### Auto-clear toggle in SettingsPanel.xaml

```xml
<ToggleSwitch Header="Auto-clear after paste"
              IsOn="{x:Bind _vm.AutoClearAfterPaste, Mode=TwoWay}"
              OnContent="On" OffContent="Off"/>
```

---

## Edge Cases

| Scenario | Behaviour |
|----------|-----------|
| Auto-paste disabled, auto-clear enabled | Auto-clear has no effect (nothing was pasted). |
| Auto-paste enabled, paste fails (silent) | Do NOT clear — the text may be the user's only copy. |
| Recording produces empty result | Word/char count unchanged. |
| User manually edits transcript | Counts update in real time. |

---

## Acceptance Criteria
- [ ] Word count and character count update immediately when the transcript text changes.
- [ ] Last recording duration shown after each recording completes.
- [ ] Auto-clear toggle visible in Settings.
- [ ] When auto-clear is on and auto-paste succeeds, transcript clears after 300 ms.
- [ ] When auto-clear is on and auto-paste fails, transcript is NOT cleared.
- [ ] Settings persist across restarts.
- [ ] Status bar hidden (or shows zero counts) when transcript is empty.

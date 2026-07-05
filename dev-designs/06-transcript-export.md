# Dev Design #6 — Transcript Export

## Problem
The only output mechanisms are copy-to-clipboard and auto-paste-at-cursor. There is no way to save a transcript to a file. Users doing long dictation sessions, meeting notes, or subtitles have no persistent record outside the clipboard.

---

## Goals
- Allow exporting the current transcript (or history entries) to:
  - `.txt` — plain text
  - `.md` — Markdown (preserves paragraph structure if segments have timestamps)
  - `.srt` — SubRip subtitle format (timestamps per segment, requires streaming timestamps)
- Show a standard save-file dialog; no external dependencies.
- Export is accessible from a toolbar button and from the right-click context menu on the transcript text area.

---

## Mac Design (Swift)

### Export formats

```swift
enum ExportFormat: String, CaseIterable, Identifiable {
    case txt = "txt"
    case md  = "md"
    case srt = "srt"
    var id: String { rawValue }
    var displayName: String {
        switch self { case .txt: "Plain Text"; case .md: "Markdown"; case .srt: "SubRip (SRT)" }
    }
    var contentType: UTType {
        switch self {
        case .txt: .plainText
        case .md:  UTType("net.daringfireball.markdown") ?? .plainText
        case .srt: UTType("com.scenarist.closed-caption-srt") ?? .plainText
        }
    }
}
```

### Formatter

```swift
enum TranscriptExporter {

    static func formatText(_ text: String) -> String { text }

    static func formatMarkdown(_ text: String, title: String = "Transcript") -> String {
        "# \(title)\n\n\(text)\n"
    }

    /// SRT requires per-segment timestamps.
    /// Without streaming timestamps, produce a single block with a fake 0s–duration timestamp.
    static func formatSRT(entries: [TranscriptEntry]) -> String {
        entries.enumerated().map { (i, entry) in
            let start = formatSRTTime(0)
            let end   = formatSRTTime(entry.duration)
            return "\(i + 1)\n\(start) --> \(end)\n\(entry.text)\n"
        }.joined(separator: "\n")
    }

    private static func formatSRTTime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds / 3600)
        let m = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        let s = Int(seconds.truncatingRemainder(dividingBy: 60))
        let ms = Int((seconds - floor(seconds)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }
}
```

### Export action

Add `exportCurrentTranscript()` to `AppModel` (or a view-level function in `ContentView`):

```swift
func exportCurrentTranscript(format: ExportFormat) {
    let content: String
    switch format {
    case .txt: content = TranscriptExporter.formatText(transcribedText)
    case .md:  content = TranscriptExporter.formatMarkdown(transcribedText)
    case .srt: content = TranscriptExporter.formatSRT(entries: history.entries)
    }

    let panel = NSSavePanel()
    panel.title = "Export Transcript"
    panel.nameFieldStringValue = "transcript.\(format.rawValue)"
    panel.allowedContentTypes = [format.contentType]
    panel.canCreateDirectories = true

    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
        try content.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        errorMessage = "Export failed: \(error.localizedDescription)"
    }
}
```

### UI — Export button in TranscriptResultsView

Add a `Menu` button alongside the copy button:

```swift
Menu {
    ForEach(ExportFormat.allCases) { format in
        Button(format.displayName) {
            appModel.exportCurrentTranscript(format: format)
        }
    }
} label: {
    Image(systemName: "square.and.arrow.up")
        .padding(8)
}
.menuStyle(.borderlessButton)
.help("Export transcript")
```

### Export full history

Add "Export All History…" in the history panel (Design #2):

```swift
Button("Export All") {
    exportHistory(format: .md)
}
```

`exportHistory` iterates over `history.entries`, formats each with its timestamp header, and writes to a single file.

---

## Windows Design (C#)

### Formatter

Create `TranscriptExporter.cs` mirroring the Mac formatter.

### Export action in MainViewModel

```csharp
[RelayCommand]
public async Task ExportTranscriptAsync(string format)
{
    var content = format switch
    {
        "txt" => TranscriptExporter.FormatText(TranscribedText),
        "md"  => TranscriptExporter.FormatMarkdown(TranscribedText),
        "srt" => TranscriptExporter.FormatSrt(HistoryEntries),
        _     => TranscribedText
    };

    var picker = new FileSavePicker
    {
        SuggestedFileName = $"transcript.{format}",
        SuggestedStartLocation = PickerLocationId.DocumentsLibrary
    };
    picker.FileTypeChoices.Add(format.ToUpper(), new[] { $".{format}" });

    // Must initialise picker with HWND (WinUI 3 pattern)
    var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(App.MainWindow);
    WinRT.Interop.InitializeWithWindow.Initialize(picker, hwnd);

    var file = await picker.PickSaveFileAsync();
    if (file == null) return;

    await FileIO.WriteTextAsync(file, content);
}
```

### UI

In `TranscriptResultsPanel.xaml`, add a `SplitButton` next to the copy button:

```xml
<SplitButton Content="Export" Click="OnExportTxt">
    <SplitButton.Flyout>
        <MenuFlyout>
            <MenuFlyoutItem Text="Plain Text (.txt)" Click="OnExportTxt"/>
            <MenuFlyoutItem Text="Markdown (.md)"    Click="OnExportMd"/>
            <MenuFlyoutItem Text="SubRip (.srt)"     Click="OnExportSrt"/>
        </MenuFlyout>
    </SplitButton.Flyout>
</SplitButton>
```

In code-behind, each handler calls `_vm.ExportTranscriptCommand.Execute("txt")` etc.

---

## SRT timestamp accuracy

Full SRT with per-word/per-segment timestamps requires the Whisper segment timestamps from `whisper_full_get_segment_t0/t1`. These are available from whisper.cpp but currently discarded.

To support proper SRT export:

1. **Mac**: Change `processAudio` to return `[(text: String, start: TimeInterval, end: TimeInterval)]` instead of a plain `String`. Compute wall-clock timestamps by adding the recording start time.
2. **Win**: Extend `RunWhisperInference` to call `WhisperNative.FullGetSegmentT0/T1(ctx, i)` and return a list of `(string Text, TimeSpan Start, TimeSpan End)` tuples.
3. Store timestamps alongside text in `TranscriptEntry` (from Design #2).

This is additive — the SRT export degrades gracefully to a single 0s-duration block if timestamps aren't available (e.g. Parakeet output).

---

## Acceptance Criteria
- [ ] Export button visible in the transcript area with a format picker.
- [ ] Saving as `.txt` produces a clean plain-text file.
- [ ] Saving as `.md` produces a Markdown file with a title header.
- [ ] Saving as `.srt` produces a valid SubRip file (single segment if timestamps unavailable, per-segment if available).
- [ ] Export works from both the current transcript and the history panel (Design #2).
- [ ] Save dialog defaults to the user's Documents folder.
- [ ] An error banner is shown if the write fails (permission, disk full, etc.).

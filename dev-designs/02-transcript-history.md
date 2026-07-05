# Dev Design #2 — Transcript History

## Problem
Every recording appends to (or overwrites) a single `transcribedText` string. When the app restarts, or when the user manually clears the text area, all prior transcriptions are lost. There is no per-entry record, no timestamp, and no way to recall what was said 5 minutes ago.

---

## Goals
- Persist a chronological list of transcription entries (text + timestamp + duration).
- Show the history in a scrollable panel with per-entry copy/delete actions.
- Keep the current "live" text area for the most recent result.
- Write history to disk so it survives restarts; cap storage to a configurable maximum.

---

## Data Model (Shared Concept, Both Platforms)

```
TranscriptEntry {
    id:        UUID
    text:      String
    timestamp: Date          // when recording stopped
    duration:  TimeInterval  // seconds of audio recorded
    modelID:   String        // which model produced this
    language:  String        // language code used
}
```

Keep the last **N** entries in memory and on disk (default N = 200, configurable in Settings).

---

## Mac Design (Swift)

### New file: `TranscriptHistory.swift`

```swift
@Observable
final class TranscriptHistory {
    private(set) var entries: [TranscriptEntry] = []
    private let maxEntries: Int
    private let storageURL: URL

    init(maxEntries: Int = 200) {
        self.maxEntries = maxEntries
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storageURL = support.appendingPathComponent("com.simpletranscribe/history.json")
        load()
    }

    func append(_ entry: TranscriptEntry) {
        entries.insert(entry, at: 0)          // newest first
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() { entries = []; save() }

    private func load() { /* JSONDecoder from storageURL */ }
    private func save() { /* JSONEncoder to storageURL */ }
}
```

### AppModel integration

Add `let history = TranscriptHistory()` to `AppModel`. In `stopRecordingAndTranscribe`, after `transcribedText` is updated:

```swift
let entry = TranscriptEntry(
    id: UUID(),
    text: trimmed,
    timestamp: Date(),
    duration: recordingDuration,   // track start time in startRecording()
    modelID: selectedModelID,
    language: selectedLanguage
)
history.append(entry)
```

Track recording start time: add `private var recordingStartTime: Date?` to `AppModel`; set in `startRecording()`.

### New view: `TranscriptHistoryView.swift`

A collapsible sidebar or a tab alongside the transcript results:

```swift
struct TranscriptHistoryView: View {
    @Environment(AppModel.self) var appModel
    
    var body: some View {
        List(appModel.history.entries) { entry in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.timestamp, style: .relative)
                        .font(.caption2).foregroundColor(.secondary)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(String(format: "%.0fs", entry.duration))
                        .font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Button { copyEntry(entry) } label: {
                        Image(systemName: "doc.on.clipboard")
                    }.buttonStyle(.plain)
                    Button { appModel.history.delete(entry.id) } label: {
                        Image(systemName: "trash")
                    }.buttonStyle(.plain).foregroundColor(.red)
                }
                Text(entry.text)
                    .font(.callout)
                    .lineLimit(3)
            }
            .padding(.vertical, 4)
        }
        .listStyle(.plain)
    }
}
```

### Layout

Modify `ContentView` to add a collapsible history pane. Use a `HSplitView` (resizable) with the main transcript on the left and history on the right, toggled by a toolbar button.

---

## Windows Design (C#)

### New class: `TranscriptHistory.cs`

Same concept as Mac. Store entries as a `List<TranscriptEntry>` serialised to `%LocalAppData%\SimpleTranscribe\history.json` via `System.Text.Json`.

Expose via `ObservableCollection<TranscriptEntry>` on `MainViewModel` so the XAML `ListView` can bind directly.

### ViewModel changes

```csharp
public ObservableCollection<TranscriptEntry> HistoryEntries { get; } = new();

private void AppendHistory(TranscriptEntry entry)
{
    HistoryEntries.Insert(0, entry);      // newest first
    while (HistoryEntries.Count > MaxHistory)
        HistoryEntries.RemoveAt(HistoryEntries.Count - 1);
    _ = SaveHistoryAsync();
}
```

Track `_recordingStartTime = DateTime.UtcNow` in `StartRecording()` and compute duration in `StopRecordingAndTranscribe`.

### New view: `TranscriptHistoryPanel.xaml`

A `UserControl` containing a `ListView` with a `DataTemplate` for each entry:

```xml
<ListView x:Name="HistoryList" SelectionMode="None">
    <ListView.ItemTemplate>
        <DataTemplate x:DataType="models:TranscriptEntry">
            <Grid Padding="8,6">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <StackPanel Orientation="Horizontal" Grid.Row="0" Spacing="8">
                    <TextBlock Text="{x:Bind TimestampRelative}"
                               Style="{StaticResource CaptionTextBlockStyle}"
                               Foreground="{ThemeResource SystemColorGrayTextBrush}"/>
                    <TextBlock Text="{x:Bind DurationLabel}"
                               Style="{StaticResource CaptionTextBlockStyle}"/>
                </StackPanel>
                <TextBlock Text="{x:Bind Text}" Grid.Row="1"
                           MaxLines="3" TextTrimming="CharacterEllipsis"/>
            </Grid>
        </DataTemplate>
    </ListView.ItemTemplate>
</ListView>
```

Add the panel inside a collapsible `SplitView` or a right-side `Grid` column in `MainWindow.xaml`.

---

## Storage & Limits

| Setting | Default | Min | Max |
|---------|---------|-----|-----|
| Max entries kept | 200 | 10 | 10 000 |
| Max file size | ~5 MB | — | configurable |

If `history.json` exceeds 5 MB, prune the oldest entries on next save.

---

## Acceptance Criteria
- [ ] Every completed transcription is saved with timestamp and duration.
- [ ] History panel shows newest entries first.
- [ ] Each entry has copy and delete buttons.
- [ ] "Clear All" button with confirmation prompt.
- [ ] History persists across app restarts.
- [ ] History file is capped at max entries.
- [ ] Toggling the history panel is remembered via UserDefaults / settings.json.

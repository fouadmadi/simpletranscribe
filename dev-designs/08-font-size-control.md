# Dev Design #8 — Font Size Control

## Problem
The transcript `TextEditor` (Mac) / `TextBox` (Windows) uses the system default body font at a fixed size. Users who dictate long texts, or who have accessibility needs, cannot make the text larger or smaller. This is a basic usability gap.

---

## Goals
- Add a font size control (slider or stepper) to the Settings area.
- Range: 11 pt – 28 pt; default: system body size (~13 pt Mac, 14 pt Win).
- Persist the preference.
- Apply change immediately without requiring a restart.

---

## Mac Design (Swift)

### AppModel

```swift
// AppModel.swift
var transcriptFontSize: Double = UserDefaults.standard.double(forKey: "transcriptFontSize")
    .nonZero ?? 14.0 {
    didSet { UserDefaults.standard.set(transcriptFontSize, forKey: "transcriptFontSize") }
}

// Extension helper
private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
```

### TranscriptResultsView

Pass font size as a parameter and apply it:

```swift
struct TranscriptResultsView: View {
    @Binding var transcribedText: String
    @Binding var showCopiedAlert: Bool
    let fontSize: Double         // NEW
    let onCopy: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TextEditor(text: $transcribedText)
                .font(.system(size: fontSize))   // NEW — was .font(.body)
                .frame(minHeight: 75, maxHeight: .infinity)
            // … copy button unchanged
        }
    }
}
```

In `ContentView`, pass `appModel.transcriptFontSize`.

### SettingsAreaView — Font size control

Add a compact stepper + label in the settings row:

```swift
HStack(spacing: 4) {
    Text("Text Size")
        .font(.caption)
        .foregroundColor(.secondary)
    Stepper("", value: $appModel.transcriptFontSize, in: 11...28, step: 1)
        .labelsHidden()
    Text("\(Int(appModel.transcriptFontSize)) pt")
        .font(.caption)
        .foregroundColor(.secondary)
        .frame(width: 36, alignment: .trailing)
}
```

Or use a `Slider` for continuous adjustment:

```swift
Slider(value: $appModel.transcriptFontSize, in: 11...28, step: 1)
    .frame(width: 100)
```

---

## Windows Design (C#)

### MainViewModel

```csharp
[ObservableProperty] private double _transcriptFontSize;

public MainViewModel()
{
    _transcriptFontSize = double.TryParse(
        GetSetting("transcriptFontSize"), out var size) ? size : 14.0;
    // … rest of init
}

partial void OnTranscriptFontSizeChanged(double value) =>
    SaveSetting("transcriptFontSize", value.ToString());
```

### TranscriptResultsPanel.xaml

Bind `TextBox.FontSize` to the ViewModel:

```xml
<TextBox x:Name="TranscriptTextBox"
         FontSize="{x:Bind FontSize, Mode=OneWay}"
         ... />
```

Expose `FontSize` as a dependency property on `TranscriptResultsPanel`, updated via the existing `SyncAllUI` / `OnViewModelPropertyChanged` pattern.

### SettingsPanel.xaml — Font size control

Add a `Slider` + value label inside the settings panel:

```xml
<StackPanel Orientation="Horizontal" Spacing="8" VerticalAlignment="Center">
    <TextBlock Text="Text Size" VerticalAlignment="Center"
               Style="{StaticResource CaptionTextBlockStyle}"/>
    <Slider x:Name="FontSizeSlider" Minimum="11" Maximum="28" StepFrequency="1"
            Width="100" Value="{x:Bind _vm.TranscriptFontSize, Mode=TwoWay}"/>
    <TextBlock VerticalAlignment="Center"
               Style="{StaticResource CaptionTextBlockStyle}">
        <Run Text="{x:Bind _vm.TranscriptFontSize, Mode=OneWay}"/>
        <Run Text=" pt"/>
    </TextBlock>
</StackPanel>
```

---

## Keyboard Shortcuts (Bonus)

Optionally support standard zoom shortcuts:

| Platform | Zoom in | Zoom out | Reset |
|----------|---------|----------|-------|
| Mac | ⌘+ | ⌘– | ⌘0 |
| Win | Ctrl++ | Ctrl+– | Ctrl+0 |

These can be added as key commands in `ContentView` (Mac) or keyboard accelerators in `MainWindow.xaml` (Win), each incrementing/decrementing `transcriptFontSize` by 1 pt.

---

## Acceptance Criteria
- [ ] Font size slider/stepper visible in Settings.
- [ ] Transcript text resizes immediately as the control is adjusted.
- [ ] Range: 11–28 pt (integer steps).
- [ ] Default is system body size on first launch.
- [ ] Preference persists across restarts.
- [ ] Keyboard shortcuts (optional) increment/decrement and reset the size.

# Dev Design #5 — Post-Processing Pipeline

## Problem
Parakeet models produce output with no punctuation and all lowercase (e.g., `"hello my name is john i live in new york"`). Whisper models vary by language and model size. Neither app applies any post-processing. Output quality in the transcript and auto-pasted text could be improved without changing the model.

---

## Goals
- Add an optional, configurable post-processing pipeline that runs after transcription.
- Default transforms: smart capitalisation, basic punctuation restoration, number formatting.
- Additional optional transforms: filler-word removal, custom find-replace rules.
- Pipeline runs on a background thread; must complete in < 200 ms for typical dictation length.
- Each transform is independently toggleable in Settings.

---

## Pipeline Architecture

```
Raw transcription text
        │
        ▼
  [1] Sentence Capitalisation
        │
        ▼
  [2] Punctuation Restoration (rule-based)
        │
        ▼
  [3] Number Formatting  (e.g. "five dollars" → "$5")
        │
        ▼
  [4] Filler Word Removal  (optional)
        │
        ▼
  [5] Custom Find-Replace  (user-defined)
        │
        ▼
  Final processed text
```

---

## Mac Design (Swift)

### New file: `TextPostProcessor.swift`

```swift
struct PostProcessorConfig {
    var capitaliseSentences: Bool = true
    var removeFillersEnabled: Bool = false
    var numberFormattingEnabled: Bool = false
    var customRules: [(find: String, replace: String)] = []

    static func fromUserDefaults() -> PostProcessorConfig {
        var c = PostProcessorConfig()
        c.capitaliseSentences    = UserDefaults.standard.bool(forKey: "pp.capitaliseSentences")
        c.removeFillersEnabled   = UserDefaults.standard.bool(forKey: "pp.removeFillers")
        c.numberFormattingEnabled = UserDefaults.standard.bool(forKey: "pp.numberFormatting")
        // Load custom rules from JSON stored in UserDefaults
        return c
    }

    func save() {
        UserDefaults.standard.set(capitaliseSentences,     forKey: "pp.capitaliseSentences")
        UserDefaults.standard.set(removeFillersEnabled,    forKey: "pp.removeFillers")
        UserDefaults.standard.set(numberFormattingEnabled, forKey: "pp.numberFormatting")
    }
}

enum TextPostProcessor {
    static let fillerWords: Set<String> = [
        "um", "uh", "er", "ah", "like", "you know", "i mean",
        "sort of", "kind of", "basically", "literally", "right"
    ]

    static func process(_ text: String, config: PostProcessorConfig) -> String {
        var result = text

        if config.capitaliseSentences {
            result = capitaliseSentences(result)
        }
        if config.removeFillersEnabled {
            result = removeFillers(result)
        }
        if config.numberFormattingEnabled {
            result = formatNumbers(result)
        }
        for rule in config.customRules {
            result = result.replacingOccurrences(of: rule.find,
                                                  with: rule.replace,
                                                  options: [.caseInsensitive])
        }
        return result
    }

    // MARK: - Transforms

    static func capitaliseSentences(_ text: String) -> String {
        // Capitalise the very first character
        var result = text.prefix(1).uppercased() + text.dropFirst()
        // Capitalise after ". ", "! ", "? "
        let pattern = #"(?<=[.!?])\s+([a-z])"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range,
                withTemplate: { (match: String) -> String in match.uppercased() }
            )
        }
        // Capitalise standalone "i" → "I"
        result = result.replacingOccurrences(of: #"\bi\b"#,
                                              with: "I",
                                              options: .regularExpression)
        return result
    }

    static func removeFillers(_ text: String) -> String {
        var words = text.components(separatedBy: " ")
        words = words.filter { !fillerWords.contains($0.lowercased()) }
        return words.joined(separator: " ")
    }

    static func formatNumbers(_ text: String) -> String {
        // Use NSLinguisticTagger or a simple lookup table for
        // spoken number words → digits. Covers 1–999 and ordinals.
        // Example: "twenty three" → "23"
        let numberMap: [(String, String)] = [
            ("one hundred", "100"), ("two hundred", "200"),
            ("fifty", "50"), ("twenty", "20"), ("thirty", "30"),
            ("forty", "40"), ("sixty", "60"), ("seventy", "70"),
            ("eighty", "80"), ("ninety", "90"), ("eleven", "11"),
            ("twelve", "12"), ("thirteen", "13"), ("fourteen", "14"),
            ("fifteen", "15"), ("sixteen", "16"), ("seventeen", "17"),
            ("eighteen", "18"), ("nineteen", "19"), ("ten", "10"),
            ("one", "1"), ("two", "2"), ("three", "3"), ("four", "4"),
            ("five", "5"), ("six", "6"), ("seven", "7"), ("eight", "8"),
            ("nine", "9"), ("zero", "0"),
        ]
        var result = text.lowercased()
        for (word, digit) in numberMap {
            result = result.replacingOccurrences(
                of: #"\b"# + word + #"\b"#,
                with: digit,
                options: .regularExpression
            )
        }
        return result
    }
}
```

### AppModel integration

Add `var postProcessorConfig = PostProcessorConfig.fromUserDefaults()` to `AppModel`.

In `stopRecordingAndTranscribe`, after getting `trimmed`:

```swift
let processed = await Task.detached(priority: .userInitiated) {
    TextPostProcessor.process(trimmed, config: appModel.postProcessorConfig)
}.value
// Use `processed` everywhere `trimmed` was used (transcript, paste)
```

### Settings UI

Add a "Text Processing" section to `SettingsAreaView` (or a new collapsible card):

```swift
Section("Text Processing") {
    Toggle("Capitalise sentences", isOn: $config.capitaliseSentences)
    Toggle("Remove filler words (um, uh, like…)", isOn: $config.removeFillersEnabled)
    Toggle("Convert spoken numbers to digits", isOn: $config.numberFormattingEnabled)
    NavigationLink("Custom find & replace…") {
        CustomRulesEditorView(rules: $config.customRules)
    }
}
```

### Custom Rules Editor

A simple `List` with `+` and `-` buttons. Each row has two `TextField`s: "Find" and "Replace". Rules are stored as a JSON array in `UserDefaults`.

---

## Windows Design (C#)

### New class: `TextPostProcessor.cs`

```csharp
public static class TextPostProcessor
{
    public static string Process(string text, PostProcessorConfig config)
    {
        if (config.CapitaliseSentences)
            text = CapitaliseSentences(text);
        if (config.RemoveFillers)
            text = RemoveFillers(text);
        if (config.NumberFormatting)
            text = FormatNumbers(text);
        foreach (var (find, replace) in config.CustomRules)
            text = Regex.Replace(text, $@"\b{Regex.Escape(find)}\b", replace,
                                 RegexOptions.IgnoreCase);
        return text;
    }

    private static string CapitaliseSentences(string text)
    {
        if (string.IsNullOrEmpty(text)) return text;
        var result = char.ToUpper(text[0]) + text[1..];
        result = Regex.Replace(result, @"(?<=[.!?])\s+([a-z])",
                               m => m.Value.ToUpper());
        result = Regex.Replace(result, @"\bi\b", "I");
        return result;
    }

    private static readonly HashSet<string> Fillers = new(StringComparer.OrdinalIgnoreCase)
    {
        "um", "uh", "er", "ah", "like", "you know", "i mean",
        "sort of", "kind of", "basically", "literally", "right"
    };

    private static string RemoveFillers(string text) =>
        string.Join(" ", text.Split(' ').Where(w => !Fillers.Contains(w)));

    private static string FormatNumbers(string text)
    {
        // Same number-word-to-digit lookup table as Mac
        // Use Regex.Replace with a word-boundary pattern for each entry
        // ...
        return text;
    }
}
```

### Settings UI (WinUI 3)

Add toggles to `SettingsPanel.xaml` inside a `Expander` control:

```xml
<controls:Expander Header="Text Processing">
    <StackPanel Spacing="8">
        <ToggleSwitch Header="Capitalise sentences"
                      IsOn="{x:Bind _vm.PostProcessorConfig.CapitaliseSentences, Mode=TwoWay}"/>
        <ToggleSwitch Header="Remove filler words"
                      IsOn="{x:Bind _vm.PostProcessorConfig.RemoveFillers, Mode=TwoWay}"/>
        <ToggleSwitch Header="Convert spoken numbers to digits"
                      IsOn="{x:Bind _vm.PostProcessorConfig.NumberFormatting, Mode=TwoWay}"/>
        <Button Content="Custom find &amp; replace…" Click="OnCustomRules"/>
    </StackPanel>
</controls:Expander>
```

---

## Performance Notes

- All processing is synchronous string manipulation — runs in < 1 ms for typical dictation lengths (< 500 words).
- Run on a background thread (`Task.detached` / `Task.Run`) to keep the completion path non-blocking.
- Regex objects should be compiled (`RegexOptions.Compiled` on Win, `NSRegularExpression` cached as `static let` on Mac) to avoid recompilation on every transcription.

---

## Acceptance Criteria
- [ ] "Capitalise sentences" correctly uppercases the first letter of each sentence and standalone "I".
- [ ] "Remove fillers" strips words from the configurable filler list.
- [ ] "Number formatting" converts common spoken numbers to digits.
- [ ] Custom rules apply case-insensitively as whole-word matches.
- [ ] Each transform is independently toggleable and persists across restarts.
- [ ] Post-processing applies to both the transcript display and the auto-pasted text.
- [ ] Processing adds < 10 ms to the total time-to-paste for typical recordings.
- [ ] All transforms default to off (except sentence capitalisation, which defaults to on).

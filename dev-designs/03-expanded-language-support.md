# Dev Design #3 — Expanded Language Support

## Problem
The language picker is hardcoded to 6 options (auto, en, es, fr, de, zh) in both apps. Whisper supports ~100 languages; Parakeet V3 supports 27 specific languages. Users who primarily speak Japanese, Arabic, Portuguese, Hindi, Korean, Italian, etc. get no assistance.

---

## Goals
- Surface all Whisper-supported languages in the picker, grouped for usability.
- For Parakeet models, restrict the picker to the languages the loaded model supports.
- Keep "Auto Detect" as the first option.
- Persist the selection and migrate gracefully from old 6-option keys.

---

## Language Registry

Create a shared file on each platform containing the full Whisper language list, plus a per-model override set.

### Mac: `SupportedLanguages.swift`

```swift
struct SupportedLanguage: Identifiable {
    let code: String     // ISO 639-1 (or ISO 639-3 for some)
    let displayName: String
    var id: String { code }
}

enum SupportedLanguages {
    static let whisper: [SupportedLanguage] = [
        // ~100 languages from whisper.cpp's language table
        SupportedLanguage(code: "auto", displayName: "Auto Detect"),
        SupportedLanguage(code: "en",   displayName: "English"),
        SupportedLanguage(code: "zh",   displayName: "Chinese"),
        SupportedLanguage(code: "de",   displayName: "German"),
        SupportedLanguage(code: "es",   displayName: "Spanish"),
        SupportedLanguage(code: "ru",   displayName: "Russian"),
        SupportedLanguage(code: "ko",   displayName: "Korean"),
        SupportedLanguage(code: "fr",   displayName: "French"),
        SupportedLanguage(code: "ja",   displayName: "Japanese"),
        SupportedLanguage(code: "pt",   displayName: "Portuguese"),
        SupportedLanguage(code: "tr",   displayName: "Turkish"),
        SupportedLanguage(code: "pl",   displayName: "Polish"),
        SupportedLanguage(code: "nl",   displayName: "Dutch"),
        SupportedLanguage(code: "ar",   displayName: "Arabic"),
        SupportedLanguage(code: "it",   displayName: "Italian"),
        SupportedLanguage(code: "sv",   displayName: "Swedish"),
        SupportedLanguage(code: "hi",   displayName: "Hindi"),
        SupportedLanguage(code: "da",   displayName: "Danish"),
        SupportedLanguage(code: "fi",   displayName: "Finnish"),
        SupportedLanguage(code: "he",   displayName: "Hebrew"),
        SupportedLanguage(code: "uk",   displayName: "Ukrainian"),
        SupportedLanguage(code: "cs",   displayName: "Czech"),
        SupportedLanguage(code: "el",   displayName: "Greek"),
        SupportedLanguage(code: "hr",   displayName: "Croatian"),
        SupportedLanguage(code: "hu",   displayName: "Hungarian"),
        SupportedLanguage(code: "ro",   displayName: "Romanian"),
        SupportedLanguage(code: "sk",   displayName: "Slovak"),
        SupportedLanguage(code: "no",   displayName: "Norwegian"),
        SupportedLanguage(code: "bg",   displayName: "Bulgarian"),
        SupportedLanguage(code: "id",   displayName: "Indonesian"),
        SupportedLanguage(code: "ms",   displayName: "Malay"),
        SupportedLanguage(code: "th",   displayName: "Thai"),
        SupportedLanguage(code: "vi",   displayName: "Vietnamese"),
        SupportedLanguage(code: "uk",   displayName: "Ukrainian"),
        // … (add remaining ~60 whisper.cpp languages)
    ]

    /// Languages supported by Parakeet V3 (27 EU + RU/UK)
    static let parakeetV3: Set<String> = [
        "en","de","fr","es","it","pt","nl","pl","cs","sk",
        "hr","sl","bg","ro","hu","da","sv","fi","no","et",
        "lv","lt","uk","ru","el","ca","gl"
    ]

    /// Languages supported by Parakeet V2 (English only)
    static let parakeetV2: Set<String> = ["en"]

    static func supportedCodes(for modelID: String) -> Set<String>? {
        if modelID.contains("parakeet-tdt-0.6b-v2") { return parakeetV2 }
        if modelID.contains("parakeet-tdt-0.6b-v3") { return parakeetV3 }
        return nil  // nil = all Whisper languages
    }
}
```

### Windows: `SupportedLanguages.cs`

Same data as a `static readonly List<SupportedLanguage>` and `static readonly HashSet<string>` for each model.

---

## SettingsAreaView / SettingsPanel Changes

### Mac

Replace the hardcoded `Picker` with a filtered, searchable list:

```swift
// Compute available languages based on selected model
var availableLanguages: [SupportedLanguage] {
    guard let allowed = SupportedLanguages.supportedCodes(for: selectedModelID) else {
        return SupportedLanguages.whisper
    }
    return SupportedLanguages.whisper.filter { $0.code == "auto" || allowed.contains($0.code) }
}

// In SettingsAreaView.body:
Picker("Language", selection: $selectedLanguage) {
    ForEach(availableLanguages) { lang in
        Text(lang.displayName).tag(lang.code)
    }
}
.frame(maxWidth: 200)
```

For discoverability with 100 items, use a `Menu`-based picker with a search field:

```swift
// Use a searchable sheet or MenuButton instead of a plain Picker
// when the language list exceeds 10 items
```

A practical approach: show a `Menu` button that opens a sheet with a `List` + `searchable` modifier.

### Windows

Replace the hardcoded `ComboBox` items with data-binding:

```csharp
// SettingsPanel.xaml.cs
public void UpdateLanguages(List<SupportedLanguage> languages, string selectedCode)
{
    LanguagePicker.ItemsSource = languages;
    LanguagePicker.SelectedItem = languages.FirstOrDefault(l => l.Code == selectedCode);
}
```

Add an `AutoSuggestBox` above the `ComboBox` for filtering if the model is Whisper (large list).

---

## TranscriptionManager Language Mapping

### Mac — Fix the existing bug
`configureParams()` is called after model load and hardcodes `.english`. This is already overridden in `startTranscription()`, but only if the model type is `.whisper`. Ensure the full language map covers all new codes:

```swift
// Extend languageMap in TranscriptionManager.swift to all ~100 whisper.cpp codes
// Use a generated or complete mapping from whisper.cpp's `whisper_lang_id()`
private static let languageMap: [String: WhisperLanguage] = {
    // Map every ISO code to the matching WhisperLanguage enum case
    // For codes whisper.cpp doesn't have an enum value, fall back to .auto
    var m: [String: WhisperLanguage] = [
        "auto": .auto, "en": .english, "zh": .chinese,
        "de": .german, "es": .spanish, "fr": .french,
        "ru": .russian, "ko": .korean, "ja": .japanese,
        // … complete mapping
    ]
    return m
}()
```

### Windows — Extend LanguageMap

Same: extend `LanguageMap` dictionary in `TranscriptionManager.cs` to all ~100 Whisper codes. Keys map to the ISO string that whisper.cpp's `--language` flag accepts (e.g., `"ja"`, `"ko"`).

---

## Migration

- If a user's persisted `selectedLanguage` is one of the old 6 codes → already valid, no change.
- If the user switches to a model that doesn't support their selected language (e.g., Parakeet V2 + `"de"`), automatically switch to `"en"` and show a one-time informational banner: *"Parakeet V2 supports English only — language set to English."*

---

## Acceptance Criteria
- [ ] Whisper models show all ~100 languages in the picker.
- [ ] Parakeet V2 shows English only.
- [ ] Parakeet V3 shows its 27 supported languages.
- [ ] Switching models updates the language picker immediately.
- [ ] If the current language is unsupported by the newly selected model, a fallback is applied with a notice.
- [ ] Language selection persists and survives restart.
- [ ] Transcription quality is unchanged for existing 6 languages.

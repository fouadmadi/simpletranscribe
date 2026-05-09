import Foundation

struct SupportedLanguage: Identifiable {
    let code: String
    let displayName: String
    var id: String { code }
}

enum SupportedLanguages {
    // Full Whisper language list (~100 languages from whisper.cpp's language table)
    static let whisper: [SupportedLanguage] = [
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
        SupportedLanguage(code: "ca",   displayName: "Catalan"),
        SupportedLanguage(code: "gl",   displayName: "Galician"),
        SupportedLanguage(code: "sl",   displayName: "Slovenian"),
        SupportedLanguage(code: "et",   displayName: "Estonian"),
        SupportedLanguage(code: "lv",   displayName: "Latvian"),
        SupportedLanguage(code: "lt",   displayName: "Lithuanian"),
        SupportedLanguage(code: "af",   displayName: "Afrikaans"),
        SupportedLanguage(code: "az",   displayName: "Azerbaijani"),
        SupportedLanguage(code: "be",   displayName: "Belarusian"),
        SupportedLanguage(code: "bn",   displayName: "Bengali"),
        SupportedLanguage(code: "bs",   displayName: "Bosnian"),
        SupportedLanguage(code: "cy",   displayName: "Welsh"),
        SupportedLanguage(code: "eu",   displayName: "Basque"),
        SupportedLanguage(code: "fa",   displayName: "Persian"),
        SupportedLanguage(code: "gl",   displayName: "Galician"),
        SupportedLanguage(code: "gu",   displayName: "Gujarati"),
        SupportedLanguage(code: "hy",   displayName: "Armenian"),
        SupportedLanguage(code: "is",   displayName: "Icelandic"),
        SupportedLanguage(code: "ka",   displayName: "Georgian"),
        SupportedLanguage(code: "kk",   displayName: "Kazakh"),
        SupportedLanguage(code: "km",   displayName: "Khmer"),
        SupportedLanguage(code: "kn",   displayName: "Kannada"),
        SupportedLanguage(code: "lo",   displayName: "Lao"),
        SupportedLanguage(code: "lb",   displayName: "Luxembourgish"),
        SupportedLanguage(code: "mk",   displayName: "Macedonian"),
        SupportedLanguage(code: "ml",   displayName: "Malayalam"),
        SupportedLanguage(code: "mn",   displayName: "Mongolian"),
        SupportedLanguage(code: "mr",   displayName: "Marathi"),
        SupportedLanguage(code: "mt",   displayName: "Maltese"),
        SupportedLanguage(code: "my",   displayName: "Myanmar"),
        SupportedLanguage(code: "ne",   displayName: "Nepali"),
        SupportedLanguage(code: "nn",   displayName: "Nynorsk"),
        SupportedLanguage(code: "oc",   displayName: "Occitan"),
        SupportedLanguage(code: "pa",   displayName: "Punjabi"),
        SupportedLanguage(code: "ps",   displayName: "Pashto"),
        SupportedLanguage(code: "si",   displayName: "Sinhala"),
        SupportedLanguage(code: "sq",   displayName: "Albanian"),
        SupportedLanguage(code: "sr",   displayName: "Serbian"),
        SupportedLanguage(code: "su",   displayName: "Sundanese"),
        SupportedLanguage(code: "sw",   displayName: "Swahili"),
        SupportedLanguage(code: "ta",   displayName: "Tamil"),
        SupportedLanguage(code: "te",   displayName: "Telugu"),
        SupportedLanguage(code: "tg",   displayName: "Tajik"),
        SupportedLanguage(code: "tk",   displayName: "Turkmen"),
        SupportedLanguage(code: "tl",   displayName: "Tagalog"),
        SupportedLanguage(code: "tt",   displayName: "Tatar"),
        SupportedLanguage(code: "ur",   displayName: "Urdu"),
        SupportedLanguage(code: "uz",   displayName: "Uzbek"),
        SupportedLanguage(code: "yi",   displayName: "Yiddish"),
        SupportedLanguage(code: "yo",   displayName: "Yoruba"),
        SupportedLanguage(code: "yue",  displayName: "Cantonese"),
        SupportedLanguage(code: "jw",   displayName: "Javanese"),
        SupportedLanguage(code: "haw",  displayName: "Hawaiian"),
        SupportedLanguage(code: "sa",   displayName: "Sanskrit"),
        SupportedLanguage(code: "bo",   displayName: "Tibetan"),
        SupportedLanguage(code: "br",   displayName: "Breton"),
        SupportedLanguage(code: "fo",   displayName: "Faroese"),
        SupportedLanguage(code: "la",   displayName: "Latin"),
        SupportedLanguage(code: "ln",   displayName: "Lingala"),
        SupportedLanguage(code: "mg",   displayName: "Malagasy"),
        SupportedLanguage(code: "mi",   displayName: "Maori"),
        SupportedLanguage(code: "ht",   displayName: "Haitian Creole"),
        SupportedLanguage(code: "ha",   displayName: "Hausa"),
        SupportedLanguage(code: "sn",   displayName: "Shona"),
        SupportedLanguage(code: "sd",   displayName: "Sindhi"),
    ]

    /// Languages supported by Parakeet V3 (27 EU + RU/UK)
    static let parakeetV3: Set<String> = [
        "en", "de", "fr", "es", "it", "pt", "nl", "pl", "cs", "sk",
        "hr", "sl", "bg", "ro", "hu", "da", "sv", "fi", "no", "et",
        "lv", "lt", "uk", "ru", "el", "ca", "gl"
    ]

    /// Languages supported by Parakeet V2 (English only)
    static let parakeetV2: Set<String> = ["en"]

    /// Returns the set of allowed language codes for a given model ID.
    /// Returns nil if the model supports all Whisper languages.
    static func supportedCodes(for modelID: String) -> Set<String>? {
        if modelID.contains("parakeet-tdt-0.6b-v2") { return parakeetV2 }
        if modelID.contains("parakeet-tdt-0.6b-v3") { return parakeetV3 }
        return nil
    }

    /// Filtered language list for a given model ID.
    static func available(for modelID: String) -> [SupportedLanguage] {
        guard let allowed = supportedCodes(for: modelID) else { return whisper }
        return whisper.filter { $0.code == "auto" || allowed.contains($0.code) }
    }
}

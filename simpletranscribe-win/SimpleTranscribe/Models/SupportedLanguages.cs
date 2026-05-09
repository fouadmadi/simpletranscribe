namespace SimpleTranscribe.Models;

public class SupportedLanguage
{
    public string Code { get; init; } = "";
    public string DisplayName { get; init; } = "";
    public override string ToString() => DisplayName;
}

public static class SupportedLanguages
{
    public static readonly List<SupportedLanguage> Whisper = new()
    {
        new() { Code = "auto", DisplayName = "Auto Detect" },
        new() { Code = "en",   DisplayName = "English" },
        new() { Code = "zh",   DisplayName = "Chinese" },
        new() { Code = "de",   DisplayName = "German" },
        new() { Code = "es",   DisplayName = "Spanish" },
        new() { Code = "ru",   DisplayName = "Russian" },
        new() { Code = "ko",   DisplayName = "Korean" },
        new() { Code = "fr",   DisplayName = "French" },
        new() { Code = "ja",   DisplayName = "Japanese" },
        new() { Code = "pt",   DisplayName = "Portuguese" },
        new() { Code = "tr",   DisplayName = "Turkish" },
        new() { Code = "pl",   DisplayName = "Polish" },
        new() { Code = "nl",   DisplayName = "Dutch" },
        new() { Code = "ar",   DisplayName = "Arabic" },
        new() { Code = "it",   DisplayName = "Italian" },
        new() { Code = "sv",   DisplayName = "Swedish" },
        new() { Code = "hi",   DisplayName = "Hindi" },
        new() { Code = "da",   DisplayName = "Danish" },
        new() { Code = "fi",   DisplayName = "Finnish" },
        new() { Code = "he",   DisplayName = "Hebrew" },
        new() { Code = "uk",   DisplayName = "Ukrainian" },
        new() { Code = "cs",   DisplayName = "Czech" },
        new() { Code = "el",   DisplayName = "Greek" },
        new() { Code = "hr",   DisplayName = "Croatian" },
        new() { Code = "hu",   DisplayName = "Hungarian" },
        new() { Code = "ro",   DisplayName = "Romanian" },
        new() { Code = "sk",   DisplayName = "Slovak" },
        new() { Code = "no",   DisplayName = "Norwegian" },
        new() { Code = "bg",   DisplayName = "Bulgarian" },
        new() { Code = "id",   DisplayName = "Indonesian" },
        new() { Code = "ms",   DisplayName = "Malay" },
        new() { Code = "th",   DisplayName = "Thai" },
        new() { Code = "vi",   DisplayName = "Vietnamese" },
        new() { Code = "ca",   DisplayName = "Catalan" },
        new() { Code = "gl",   DisplayName = "Galician" },
        new() { Code = "sl",   DisplayName = "Slovenian" },
        new() { Code = "et",   DisplayName = "Estonian" },
        new() { Code = "lv",   DisplayName = "Latvian" },
        new() { Code = "lt",   DisplayName = "Lithuanian" },
        new() { Code = "af",   DisplayName = "Afrikaans" },
        new() { Code = "az",   DisplayName = "Azerbaijani" },
        new() { Code = "be",   DisplayName = "Belarusian" },
        new() { Code = "bn",   DisplayName = "Bengali" },
        new() { Code = "bs",   DisplayName = "Bosnian" },
        new() { Code = "cy",   DisplayName = "Welsh" },
        new() { Code = "eu",   DisplayName = "Basque" },
        new() { Code = "fa",   DisplayName = "Persian" },
        new() { Code = "gu",   DisplayName = "Gujarati" },
        new() { Code = "hy",   DisplayName = "Armenian" },
        new() { Code = "is",   DisplayName = "Icelandic" },
        new() { Code = "ka",   DisplayName = "Georgian" },
        new() { Code = "kk",   DisplayName = "Kazakh" },
        new() { Code = "km",   DisplayName = "Khmer" },
        new() { Code = "kn",   DisplayName = "Kannada" },
        new() { Code = "lo",   DisplayName = "Lao" },
        new() { Code = "lb",   DisplayName = "Luxembourgish" },
        new() { Code = "mk",   DisplayName = "Macedonian" },
        new() { Code = "ml",   DisplayName = "Malayalam" },
        new() { Code = "mn",   DisplayName = "Mongolian" },
        new() { Code = "mr",   DisplayName = "Marathi" },
        new() { Code = "mt",   DisplayName = "Maltese" },
        new() { Code = "my",   DisplayName = "Myanmar" },
        new() { Code = "ne",   DisplayName = "Nepali" },
        new() { Code = "pa",   DisplayName = "Punjabi" },
        new() { Code = "si",   DisplayName = "Sinhala" },
        new() { Code = "sq",   DisplayName = "Albanian" },
        new() { Code = "sr",   DisplayName = "Serbian" },
        new() { Code = "su",   DisplayName = "Sundanese" },
        new() { Code = "sw",   DisplayName = "Swahili" },
        new() { Code = "ta",   DisplayName = "Tamil" },
        new() { Code = "te",   DisplayName = "Telugu" },
        new() { Code = "tg",   DisplayName = "Tajik" },
        new() { Code = "tl",   DisplayName = "Tagalog" },
        new() { Code = "tt",   DisplayName = "Tatar" },
        new() { Code = "ur",   DisplayName = "Urdu" },
        new() { Code = "uz",   DisplayName = "Uzbek" },
        new() { Code = "yi",   DisplayName = "Yiddish" },
        new() { Code = "yo",   DisplayName = "Yoruba" },
        new() { Code = "yue",  DisplayName = "Cantonese" },
        new() { Code = "jw",   DisplayName = "Javanese" },
        new() { Code = "haw",  DisplayName = "Hawaiian" },
        new() { Code = "mi",   DisplayName = "Maori" },
        new() { Code = "ht",   DisplayName = "Haitian Creole" },
        new() { Code = "ha",   DisplayName = "Hausa" },
        new() { Code = "sn",   DisplayName = "Shona" },
        new() { Code = "sd",   DisplayName = "Sindhi" },
        new() { Code = "sa",   DisplayName = "Sanskrit" },
        new() { Code = "la",   DisplayName = "Latin" },
    };

    public static readonly HashSet<string> ParakeetV3 = new()
    {
        "en", "de", "fr", "es", "it", "pt", "nl", "pl", "cs", "sk",
        "hr", "sl", "bg", "ro", "hu", "da", "sv", "fi", "no", "et",
        "lv", "lt", "uk", "ru", "el", "ca", "gl"
    };

    public static readonly HashSet<string> ParakeetV2 = new() { "en" };

    public static HashSet<string>? SupportedCodes(string modelId)
    {
        if (modelId.Contains("parakeet-tdt-0.6b-v2")) return ParakeetV2;
        if (modelId.Contains("parakeet-tdt-0.6b-v3")) return ParakeetV3;
        return null;
    }

    public static List<SupportedLanguage> Available(string modelId)
    {
        var allowed = SupportedCodes(modelId);
        if (allowed == null) return Whisper;
        return Whisper.Where(l => l.Code == "auto" || allowed.Contains(l.Code)).ToList();
    }
}

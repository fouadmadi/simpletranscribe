using System.Text.RegularExpressions;
using SimpleTranscribe.Models;

namespace SimpleTranscribe.Services;

public static class TextPostProcessor
{
    private static readonly HashSet<string> Fillers = new(StringComparer.OrdinalIgnoreCase)
    {
        "um", "uh", "er", "ah", "like", "you know", "i mean",
        "sort of", "kind of", "basically", "literally", "right"
    };

    private static readonly (string Word, string Digit)[] NumberMap =
    [
        ("one thousand", "1000"), ("two thousand", "2000"),
        ("one hundred", "100"), ("two hundred", "200"), ("three hundred", "300"),
        ("four hundred", "400"), ("five hundred", "500"), ("six hundred", "600"),
        ("seven hundred", "700"), ("eight hundred", "800"), ("nine hundred", "900"),
        ("ninety", "90"), ("eighty", "80"), ("seventy", "70"), ("sixty", "60"),
        ("fifty", "50"), ("forty", "40"), ("thirty", "30"), ("twenty", "20"),
        ("nineteen", "19"), ("eighteen", "18"), ("seventeen", "17"), ("sixteen", "16"),
        ("fifteen", "15"), ("fourteen", "14"), ("thirteen", "13"), ("twelve", "12"),
        ("eleven", "11"), ("ten", "10"), ("nine", "9"), ("eight", "8"),
        ("seven", "7"), ("six", "6"), ("five", "5"), ("four", "4"),
        ("three", "3"), ("two", "2"), ("one", "1"), ("zero", "0"),
    ];

    // Compiled regexes cached at class level
    private static readonly Regex SentenceCapRegex =
        new(@"(?<=[.!?])\s+([a-z])", RegexOptions.Compiled);
    private static readonly Regex StandaloneIRegex =
        new(@"\bi\b", RegexOptions.Compiled);

    public static string Process(string text, PostProcessorConfig config)
    {
        if (string.IsNullOrEmpty(text)) return text;
        if (config.CapitaliseSentences) text = CapitaliseSentences(text);
        if (config.RemoveFillersEnabled) text = RemoveFillers(text);
        if (config.NumberFormattingEnabled) text = FormatNumbers(text);
        foreach (var rule in config.CustomRules)
        {
            if (string.IsNullOrEmpty(rule.Find)) continue;
            text = Regex.Replace(text,
                @"\b" + Regex.Escape(rule.Find) + @"\b",
                rule.Replace,
                RegexOptions.IgnoreCase);
        }
        return text;
    }

    private static string CapitaliseSentences(string text)
    {
        if (string.IsNullOrEmpty(text)) return text;
        text = char.ToUpper(text[0]) + text[1..];
        text = SentenceCapRegex.Replace(text, m => m.Value.ToUpper());
        text = StandaloneIRegex.Replace(text, "I");
        return text;
    }

    private static string RemoveFillers(string text) =>
        string.Join(" ", text.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Where(w => !Fillers.Contains(w)));

    private static string FormatNumbers(string text)
    {
        foreach (var (word, digit) in NumberMap)
            text = Regex.Replace(text, @"\b" + word + @"\b", digit, RegexOptions.IgnoreCase);
        return text;
    }
}

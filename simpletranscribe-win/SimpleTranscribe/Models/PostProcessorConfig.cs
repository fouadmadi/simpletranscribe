using System.Text.Json;

namespace SimpleTranscribe.Models;

public class PostProcessorConfig
{
    public bool CapitaliseSentences { get; set; } = true;
    public bool RemoveFillersEnabled { get; set; } = false;
    public bool NumberFormattingEnabled { get; set; } = false;
    public List<CustomRule> CustomRules { get; set; } = new();

    public class CustomRule
    {
        public string Find { get; set; } = "";
        public string Replace { get; set; } = "";
    }

    private const string SettingsKey = "postProcessorConfig";

    public static PostProcessorConfig Load(Func<string, string?> getSetting)
    {
        var json = getSetting(SettingsKey);
        if (!string.IsNullOrEmpty(json))
        {
            try { return JsonSerializer.Deserialize<PostProcessorConfig>(json) ?? new(); }
            catch { /* Fall through to default */ }
        }
        return new PostProcessorConfig();
    }

    public void Save(Action<string, string> saveSetting)
    {
        try { saveSetting(SettingsKey, JsonSerializer.Serialize(this)); }
        catch { /* Best effort */ }
    }
}

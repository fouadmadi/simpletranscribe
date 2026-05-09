using SimpleTranscribe.Models;

namespace SimpleTranscribe.Services;

public static class TranscriptExporter
{
    public static string FormatText(string text) => text;

    public static string FormatMarkdown(string text, string title = "Transcript") =>
        $"# {title}\n\n{text}\n";

    public static string FormatSrt(IEnumerable<TranscriptEntry> entries)
    {
        var parts = new List<string>();
        double offset = 0;
        int i = 1;
        foreach (var entry in entries)
        {
            var start = SrtTime(offset);
            var end   = SrtTime(offset + Math.Max(entry.DurationSeconds, 1));
            offset   += entry.DurationSeconds;
            parts.Add($"{i}\n{start} --> {end}\n{entry.Text}\n");
            i++;
        }
        return string.Join("\n", parts);
    }

    public static string FormatHistoryMarkdown(IEnumerable<TranscriptEntry> entries)
    {
        var body = string.Join("\n\n", entries.Select(e =>
            $"## {e.Timestamp:g}\n\n{e.Text}"));
        return FormatMarkdown(body, "Transcript History");
    }

    private static string SrtTime(double seconds)
    {
        var h  = (int)(seconds / 3600);
        var m  = (int)(seconds % 3600 / 60);
        var s  = (int)(seconds % 60);
        var ms = (int)((seconds - Math.Floor(seconds)) * 1000);
        return $"{h:D2}:{m:D2}:{s:D2},{ms:D3}";
    }
}

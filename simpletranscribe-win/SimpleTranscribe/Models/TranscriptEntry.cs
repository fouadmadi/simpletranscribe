using System.Text.Json.Serialization;

namespace SimpleTranscribe.Models;

public class TranscriptEntry
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Text { get; set; } = "";
    public DateTime Timestamp { get; set; } = DateTime.Now;
    public double DurationSeconds { get; set; }
    public string ModelId { get; set; } = "";
    public string Language { get; set; } = "";

    [JsonIgnore]
    public string TimestampRelative
    {
        get
        {
            var delta = DateTime.Now - Timestamp;
            if (delta.TotalSeconds < 60) return "just now";
            if (delta.TotalMinutes < 60) return $"{(int)delta.TotalMinutes}min ago";
            if (delta.TotalHours < 24) return $"{(int)delta.TotalHours}h ago";
            return Timestamp.ToString("MMM d");
        }
    }

    [JsonIgnore]
    public string DurationLabel => $"{DurationSeconds:F0}s";
}

using Xunit;
using SimpleTranscribe.Models;
using SimpleTranscribe.Services;

namespace SimpleTranscribe.Tests;

public class TranscriptExporterTests
{
    // --- FormatText ---

    [Fact]
    public void FormatText_ReturnsOriginalText()
    {
        var result = TranscriptExporter.FormatText("Hello world");
        Assert.Equal("Hello world", result);
    }

    [Fact]
    public void FormatText_HandlesEmptyString()
    {
        var result = TranscriptExporter.FormatText("");
        Assert.Equal("", result);
    }

    // --- FormatMarkdown ---

    [Fact]
    public void FormatMarkdown_DefaultTitle_ContainsHeader()
    {
        var result = TranscriptExporter.FormatMarkdown("Some text");
        Assert.StartsWith("# Transcript\n\n", result);
        Assert.Contains("Some text", result);
    }

    [Fact]
    public void FormatMarkdown_CustomTitle_UsesTitle()
    {
        var result = TranscriptExporter.FormatMarkdown("Body", "My Title");
        Assert.StartsWith("# My Title\n\n", result);
        Assert.Contains("Body", result);
    }

    [Fact]
    public void FormatMarkdown_EndsWithNewline()
    {
        var result = TranscriptExporter.FormatMarkdown("text");
        Assert.EndsWith("\n", result);
    }

    // --- FormatSrt ---

    [Fact]
    public void FormatSrt_EmptyEntries_ReturnsEmpty()
    {
        var result = TranscriptExporter.FormatSrt(Array.Empty<TranscriptEntry>());
        Assert.Equal("", result);
    }

    [Fact]
    public void FormatSrt_SingleEntry_FormatsCorrectly()
    {
        var entries = new[]
        {
            new TranscriptEntry { Text = "Hello world", DurationSeconds = 3.5 }
        };

        var result = TranscriptExporter.FormatSrt(entries);

        Assert.Contains("1\n", result);
        Assert.Contains("00:00:00,000 --> 00:00:03,500", result);
        Assert.Contains("Hello world", result);
    }

    [Fact]
    public void FormatSrt_MultipleEntries_SequentialTimestamps()
    {
        var entries = new[]
        {
            new TranscriptEntry { Text = "First", DurationSeconds = 2.0 },
            new TranscriptEntry { Text = "Second", DurationSeconds = 3.0 }
        };

        var result = TranscriptExporter.FormatSrt(entries);

        // First entry: 0-2s
        Assert.Contains("00:00:00,000 --> 00:00:02,000", result);
        // Second entry starts at 2s (offset of first)
        Assert.Contains("00:00:02,000 --> 00:00:05,000", result);
        Assert.Contains("1\n", result);
        Assert.Contains("2\n", result);
    }

    [Fact]
    public void FormatSrt_ZeroDuration_UsesMinimumOneSecond()
    {
        var entries = new[]
        {
            new TranscriptEntry { Text = "Quick", DurationSeconds = 0 }
        };

        var result = TranscriptExporter.FormatSrt(entries);
        Assert.Contains("00:00:00,000 --> 00:00:01,000", result);
    }

    [Fact]
    public void FormatSrt_LongDuration_FormatsHoursCorrectly()
    {
        var entries = new[]
        {
            new TranscriptEntry { Text = "Long", DurationSeconds = 3661.5 }
        };

        var result = TranscriptExporter.FormatSrt(entries);
        Assert.Contains("01:01:01,500", result);
    }

    // --- FormatHistoryMarkdown ---

    [Fact]
    public void FormatHistoryMarkdown_ContainsTitle()
    {
        var entries = new[]
        {
            new TranscriptEntry { Text = "Test entry" }
        };

        var result = TranscriptExporter.FormatHistoryMarkdown(entries);
        Assert.Contains("# Transcript History", result);
    }

    [Fact]
    public void FormatHistoryMarkdown_ContainsEntryText()
    {
        var entries = new[]
        {
            new TranscriptEntry { Text = "First entry" },
            new TranscriptEntry { Text = "Second entry" }
        };

        var result = TranscriptExporter.FormatHistoryMarkdown(entries);
        Assert.Contains("First entry", result);
        Assert.Contains("Second entry", result);
    }

    [Fact]
    public void FormatHistoryMarkdown_ContainsH2Headers()
    {
        var entries = new[]
        {
            new TranscriptEntry { Text = "Entry" }
        };

        var result = TranscriptExporter.FormatHistoryMarkdown(entries);
        Assert.Contains("## ", result);
    }
}

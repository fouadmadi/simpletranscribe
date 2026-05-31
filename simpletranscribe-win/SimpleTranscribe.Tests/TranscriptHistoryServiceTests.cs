using Xunit;
using SimpleTranscribe.Models;
using SimpleTranscribe.Services;

namespace SimpleTranscribe.Tests;

public class TranscriptHistoryServiceTests
{
    [Fact]
    public void NewService_HasEmptyEntries()
    {
        var service = new TranscriptHistoryService();
        Assert.Empty(service.Entries);
    }

    [Fact]
    public void Append_AddsEntryAtFront()
    {
        var service = new TranscriptHistoryService();
        var entry = new TranscriptEntry { Text = "Hello" };

        service.Append(entry);

        Assert.Single(service.Entries);
        Assert.Equal("Hello", service.Entries[0].Text);
    }

    [Fact]
    public void Append_NewerEntriesFirst()
    {
        var service = new TranscriptHistoryService();
        var first = new TranscriptEntry { Text = "First" };
        var second = new TranscriptEntry { Text = "Second" };

        service.Append(first);
        service.Append(second);

        Assert.Equal(2, service.Entries.Count);
        Assert.Equal("Second", service.Entries[0].Text);
        Assert.Equal("First", service.Entries[1].Text);
    }

    [Fact]
    public void Delete_RemovesById()
    {
        var service = new TranscriptHistoryService();
        var entry = new TranscriptEntry { Text = "To delete" };
        service.Append(entry);

        service.Delete(entry.Id);

        Assert.Empty(service.Entries);
    }

    [Fact]
    public void Delete_NoOpForUnknownId()
    {
        var service = new TranscriptHistoryService();
        service.Append(new TranscriptEntry { Text = "Keep" });

        service.Delete(Guid.NewGuid()); // Unknown ID

        Assert.Single(service.Entries);
    }

    [Fact]
    public void Clear_RemovesAllEntries()
    {
        var service = new TranscriptHistoryService();
        service.Append(new TranscriptEntry { Text = "One" });
        service.Append(new TranscriptEntry { Text = "Two" });
        service.Append(new TranscriptEntry { Text = "Three" });

        service.Clear();

        Assert.Empty(service.Entries);
    }

    [Fact]
    public void Append_EnforcesMaxEntries()
    {
        var service = new TranscriptHistoryService();

        // Add 205 entries (max is 200)
        for (int i = 0; i < 205; i++)
        {
            service.Append(new TranscriptEntry { Text = $"Entry {i}" });
        }

        Assert.Equal(200, service.Entries.Count);
        // Most recent should be first
        Assert.Equal("Entry 204", service.Entries[0].Text);
    }

    [Fact]
    public void TranscriptEntry_HasDefaultValues()
    {
        var entry = new TranscriptEntry();
        Assert.NotEqual(Guid.Empty, entry.Id);
        Assert.Equal("", entry.Text);
        Assert.Equal(0, entry.DurationSeconds);
        Assert.Equal("", entry.ModelId);
        Assert.Equal("", entry.Language);
    }

    [Fact]
    public void TranscriptEntry_TimestampRelative_JustNow()
    {
        var entry = new TranscriptEntry { Timestamp = DateTime.Now };
        Assert.Equal("just now", entry.TimestampRelative);
    }

    [Fact]
    public void TranscriptEntry_TimestampRelative_MinutesAgo()
    {
        var entry = new TranscriptEntry { Timestamp = DateTime.Now.AddMinutes(-5) };
        Assert.Equal("5min ago", entry.TimestampRelative);
    }

    [Fact]
    public void TranscriptEntry_TimestampRelative_HoursAgo()
    {
        var entry = new TranscriptEntry { Timestamp = DateTime.Now.AddHours(-3) };
        Assert.Equal("3h ago", entry.TimestampRelative);
    }

    [Fact]
    public void TranscriptEntry_TimestampRelative_OlderThanDay()
    {
        var entry = new TranscriptEntry { Timestamp = DateTime.Now.AddDays(-5) };
        Assert.Contains(entry.Timestamp.ToString("MMM"), entry.TimestampRelative);
    }

    [Fact]
    public void TranscriptEntry_DurationLabel_FormatsCorrectly()
    {
        var entry = new TranscriptEntry { DurationSeconds = 12.7 };
        Assert.Equal("13s", entry.DurationLabel);
    }
}

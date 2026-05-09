using System.Collections.ObjectModel;
using System.Text.Json;
using SimpleTranscribe.Models;

namespace SimpleTranscribe.Services;

public class TranscriptHistoryService
{
    private const int MaxEntries = 200;
    private const long MaxFileSizeBytes = 5 * 1024 * 1024; // 5 MB

    private static string StoragePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "SimpleTranscribe", "history.json");

    public ObservableCollection<TranscriptEntry> Entries { get; } = new();

    public TranscriptHistoryService()
    {
        Load();
    }

    public void Append(TranscriptEntry entry)
    {
        Entries.Insert(0, entry);
        while (Entries.Count > MaxEntries)
            Entries.RemoveAt(Entries.Count - 1);
        _ = SaveAsync();
    }

    public void Delete(Guid id)
    {
        var item = Entries.FirstOrDefault(e => e.Id == id);
        if (item != null)
        {
            Entries.Remove(item);
            _ = SaveAsync();
        }
    }

    public void Clear()
    {
        Entries.Clear();
        _ = SaveAsync();
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(StoragePath)) return;
            var json = File.ReadAllText(StoragePath);
            var list = JsonSerializer.Deserialize<List<TranscriptEntry>>(json);
            if (list == null) return;
            foreach (var entry in list)
                Entries.Add(entry);
        }
        catch { /* Best effort */ }
    }

    private async Task SaveAsync()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(StoragePath)!);
            var list = Entries.ToList();
            var json = JsonSerializer.Serialize(list);
            // Prune if over size limit
            if (json.Length > MaxFileSizeBytes && list.Count > 1)
            {
                list = list.Take(list.Count / 2).ToList();
                json = JsonSerializer.Serialize(list);
            }
            await File.WriteAllTextAsync(StoragePath, json);
        }
        catch { /* Best effort */ }
    }
}

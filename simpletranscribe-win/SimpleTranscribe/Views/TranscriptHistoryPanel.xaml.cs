using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using SimpleTranscribe.Models;
using SimpleTranscribe.Services;
using Windows.ApplicationModel.DataTransfer;

namespace SimpleTranscribe.Views;

public sealed partial class TranscriptHistoryPanel : UserControl
{
    public TranscriptHistoryService? History
    {
        get => (TranscriptHistoryService?)GetValue(HistoryProperty);
        set => SetValue(HistoryProperty, value);
    }

    public static readonly DependencyProperty HistoryProperty =
        DependencyProperty.Register(nameof(History), typeof(TranscriptHistoryService),
            typeof(TranscriptHistoryPanel), new PropertyMetadata(null));

    public TranscriptHistoryPanel()
    {
        InitializeComponent();
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        var query = SearchBox.Text?.Trim() ?? "";
        if (History == null) return;

        if (string.IsNullOrEmpty(query))
        {
            HistoryList.ItemsSource = History.Entries;
        }
        else
        {
            var filtered = History.Entries
                .Where(entry => entry.Text.Contains(query, StringComparison.OrdinalIgnoreCase))
                .ToList();
            HistoryList.ItemsSource = filtered;
        }
    }

    private void CopyEntry_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is string text)
        {
            var dp = new DataPackage();
            dp.SetText(text);
            Clipboard.SetContent(dp);
        }
    }

    private void DeleteEntry_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag is Guid id)
        {
            History?.Delete(id);
            // Re-apply search filter after deletion
            SearchBox_TextChanged(SearchBox, null!);
        }
    }

    private void ClearAll_Click(object sender, RoutedEventArgs e)
    {
        History?.Clear();
        SearchBox.Text = "";
    }
}

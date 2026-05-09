using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace SimpleTranscribe.Views;

public sealed partial class TranscriptResultsPanel : UserControl
{
    public event EventHandler<string>? TextChanged;
    public event EventHandler? CopyClicked;
    public event EventHandler<string>? ExportRequested; // format: "txt", "md", "srt"

    private bool _suppressEvents;

    public TranscriptResultsPanel()
    {
        InitializeComponent();
    }

    public string Text
    {
        get => TranscriptTextBox.Text;
        set
        {
            _suppressEvents = true;
            TranscriptTextBox.Text = value;
            _suppressEvents = false;
        }
    }

    /// <summary>
    /// Live partial transcription text shown while recording. Set to empty string to hide.
    /// </summary>
    public string LiveText
    {
        get => LivePreviewText.Text;
        set
        {
            LivePreviewText.Text = value;
            LivePreviewBorder.Visibility = string.IsNullOrEmpty(value)
                ? Visibility.Collapsed
                : Visibility.Visible;
        }
    }

    private void OnTextChanged(object sender, TextChangedEventArgs e)
    {
        if (!_suppressEvents)
            TextChanged?.Invoke(this, TranscriptTextBox.Text);
    }

    private void OnCopy(object sender, RoutedEventArgs e)
    {
        CopyClicked?.Invoke(this, EventArgs.Empty);
        CopiedTip.IsOpen = true;
        _ = HideCopiedTipAsync();
    }

    private void OnExportTxt(object sender, RoutedEventArgs e) => ExportRequested?.Invoke(this, "txt");
    private void OnExportMd(object sender, RoutedEventArgs e) => ExportRequested?.Invoke(this, "md");
    private void OnExportSrt(object sender, RoutedEventArgs e) => ExportRequested?.Invoke(this, "srt");

    private async Task HideCopiedTipAsync()
    {
        await Task.Delay(1500);
        CopiedTip.IsOpen = false;
    }
}

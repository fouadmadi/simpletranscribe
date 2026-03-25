using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace SimpleTranscribe.Views;

public sealed partial class TranscriptResultsPanel : UserControl
{
    public event EventHandler<string>? TextChanged;
    public event EventHandler? CopyClicked;

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

    private async Task HideCopiedTipAsync()
    {
        await Task.Delay(1500);
        CopiedTip.IsOpen = false;
    }
}

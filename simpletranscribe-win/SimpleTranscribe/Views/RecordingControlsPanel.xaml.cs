using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace SimpleTranscribe.Views;

public sealed partial class RecordingControlsPanel : UserControl
{
    public event EventHandler? ToggleRecordingClicked;
    public event EventHandler? ShowModelManagerClicked;
    public event EventHandler? ToggleHistoryClicked;

    public RecordingControlsPanel()
    {
        InitializeComponent();
    }

    public void UpdateState(bool isRecording, bool isProcessing, bool isTranscribing,
        bool canRecord, bool isLoadingModel, bool showTranscriptionStarted)
    {
        RecordButton.IsEnabled = !isProcessing && canRecord && !isLoadingModel;

        if (isRecording)
        {
            RecordIcon.Glyph = "\uE71A"; // Stop icon
            RecordText.Text = "Stop";
            RecordButton.Background = new SolidColorBrush(Colors.Red);
        }
        else
        {
            RecordIcon.Glyph = "\uE720"; // Mic icon
            RecordText.Text = "Transcribe";
            RecordButton.Background = null; // Reset to default accent
        }

        ProcessingPanel.Visibility = (isProcessing || isTranscribing)
            ? Visibility.Visible : Visibility.Collapsed;

        TranscriptionStartedPanel.Visibility = showTranscriptionStarted
            ? Visibility.Visible : Visibility.Collapsed;
    }

    public void UpdateHistoryButtonState(bool historyVisible)
    {
        HistoryIcon.Glyph = historyVisible ? "\uE81C" : "\uE81C"; // same icon; could swap for "filled" variant
        // Use Opacity to indicate active state
        HistoryButton.Opacity = historyVisible ? 1.0 : 0.6;
    }

    private void OnToggleRecording(object sender, RoutedEventArgs e)
        => ToggleRecordingClicked?.Invoke(this, EventArgs.Empty);

    private void OnShowModelManager(object sender, RoutedEventArgs e)
        => ShowModelManagerClicked?.Invoke(this, EventArgs.Empty);

    private void OnToggleHistory(object sender, RoutedEventArgs e)
        => ToggleHistoryClicked?.Invoke(this, EventArgs.Empty);
}

using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace SimpleTranscribe.Views;

public sealed partial class RecordingControlsPanel : UserControl
{
    public event EventHandler? ToggleRecordingClicked;
    public event EventHandler? ShowModelManagerClicked;

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

    private void OnToggleRecording(object sender, RoutedEventArgs e)
        => ToggleRecordingClicked?.Invoke(this, EventArgs.Empty);

    private void OnShowModelManager(object sender, RoutedEventArgs e)
        => ShowModelManagerClicked?.Invoke(this, EventArgs.Empty);
}

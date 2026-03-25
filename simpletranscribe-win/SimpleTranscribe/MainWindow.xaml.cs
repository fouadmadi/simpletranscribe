using Microsoft.UI.Xaml;

namespace SimpleTranscribe;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();

        // Set default window size to match macOS (700×550)
        var appWindow = this.AppWindow;
        appWindow.Resize(new Windows.Graphics.SizeInt32(700, 550));
    }
}

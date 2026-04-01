using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using System.Reflection;
using System.Diagnostics;

namespace SimpleTranscribe.Views
{
    public sealed partial class AboutDialog : ContentDialog
    {
        public string AppVersion { get; }

        public AboutDialog()
        {
            this.InitializeComponent();
            var versionInfo = FileVersionInfo.GetVersionInfo(Assembly.GetExecutingAssembly().Location);
            AppVersion = versionInfo.ProductVersion ?? "Unknown";
        }
    }
}

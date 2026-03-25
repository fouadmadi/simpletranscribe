using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using SimpleTranscribe.Models;
using SimpleTranscribe.Services;

namespace SimpleTranscribe.Views;

public sealed partial class ModelDownloadPage : UserControl
{
    private ModelService? _modelService;
    private string _selectedModelId = "";

    public event EventHandler? CloseRequested;
    public event EventHandler<string>? ModelSelected;

    public ModelDownloadPage()
    {
        InitializeComponent();
    }

    public void Initialize(ModelService modelService, string selectedModelId)
    {
        _modelService = modelService;
        _selectedModelId = selectedModelId;
        _modelService.ModelsChanged += RefreshList;
        RefreshList();
    }

    public void Detach()
    {
        if (_modelService != null)
            _modelService.ModelsChanged -= RefreshList;
    }

    private void RefreshList()
    {
        if (_modelService == null) return;

        DispatcherQueue.TryEnqueue(() =>
        {
            ModelList.Children.Clear();

            var totalSize = _modelService.TotalDownloadedSize();
            StorageText.Text = $"Storage Used: {FormatBytes(totalSize)}";

            foreach (var model in _modelService.AvailableModels)
            {
                ModelList.Children.Add(CreateModelRow(model));
            }
        });
    }

    private UIElement CreateModelRow(ModelInfo model)
    {
        var card = new Border
        {
            Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(16),
        };

        var outerStack = new StackPanel { Spacing = 8 };

        // Main row
        var row = new Grid();
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(40) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        // Status icon
        var icon = new FontIcon { FontSize = 20 };
        if (model.IsAvailable && model.Id == _selectedModelId)
        {
            icon.Glyph = "\uE73E"; // Checkmark
            icon.Foreground = new SolidColorBrush(Colors.Green);
        }
        else if (model.IsAvailable)
        {
            icon.Glyph = "\uEA3A"; // Circle
            icon.Foreground = new SolidColorBrush(Colors.Gray);
        }
        else if (model.Status == ModelStatus.Downloading)
        {
            icon.Glyph = "\uE896"; // Download
            icon.Foreground = (Brush)Application.Current.Resources["AccentFillColorDefaultBrush"];
        }
        else
        {
            icon.Glyph = "\uE896"; // Cloud download
            icon.Foreground = new SolidColorBrush(Colors.Gray);
        }
        Grid.SetColumn(icon, 0);
        row.Children.Add(icon);

        // Info
        var info = new StackPanel { Spacing = 2 };
        info.Children.Add(new TextBlock
        {
            Text = model.Name,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
        });

        var detailsPanel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        detailsPanel.Children.Add(new TextBlock
        {
            Text = model.FormattedSize,
            FontSize = 12,
            Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"]
        });
        if (model.Language != "unknown")
        {
            detailsPanel.Children.Add(new TextBlock
            {
                Text = model.Language.ToUpperInvariant(),
                FontSize = 11,
                Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"]
            });
        }
        info.Children.Add(detailsPanel);

        info.Children.Add(new TextBlock
        {
            Text = model.Description,
            FontSize = 12,
            Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"]
        });

        Grid.SetColumn(info, 1);
        row.Children.Add(info);

        // Actions
        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };

        if (model.IsAvailable)
        {
            var selectBtn = new Button
            {
                Content = model.Id == _selectedModelId ? "Selected" : "Select",
                IsEnabled = model.Id != _selectedModelId,
                FontSize = 12
            };
            var modelId = model.Id;
            selectBtn.Click += (_, _) =>
            {
                _selectedModelId = modelId;
                ModelSelected?.Invoke(this, modelId);
                RefreshList();
            };
            actions.Children.Add(selectBtn);

            var deleteBtn = new Button { FontSize = 12, Foreground = new SolidColorBrush(Colors.Red) };
            deleteBtn.Content = new FontIcon { Glyph = "\uE74D", FontSize = 12 };
            deleteBtn.Click += (_, _) =>
            {
                _modelService?.DeleteModel(modelId);
            };
            actions.Children.Add(deleteBtn);
        }
        else if (model.Status == ModelStatus.Downloading)
        {
            var cancelBtn = new Button { Content = "Cancel", FontSize = 12 };
            var modelId = model.Id;
            cancelBtn.Click += (_, _) => _modelService?.CancelDownload(modelId);
            actions.Children.Add(cancelBtn);
        }
        else
        {
            var downloadBtn = new Button { FontSize = 12 };
            var btnContent = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            btnContent.Children.Add(new FontIcon { Glyph = "\uE896", FontSize = 12 });
            btnContent.Children.Add(new TextBlock { Text = "Download" });
            downloadBtn.Content = btnContent;
            var modelId = model.Id;
            downloadBtn.Click += async (_, _) =>
            {
                try { await _modelService!.DownloadModelAsync(modelId); }
                catch { /* Error shown via model status */ }
            };
            actions.Children.Add(downloadBtn);
        }

        Grid.SetColumn(actions, 2);
        row.Children.Add(actions);

        outerStack.Children.Add(row);

        // Progress bar for active downloads
        if (model.Status == ModelStatus.Downloading)
        {
            var progressBar = new ProgressBar
            {
                Value = model.DownloadProgress * 100,
                Maximum = 100,
                Margin = new Thickness(0, 4, 0, 0)
            };
            outerStack.Children.Add(progressBar);

            outerStack.Children.Add(new TextBlock
            {
                Text = $"{(int)(model.DownloadProgress * 100)}%",
                FontSize = 11,
                Foreground = (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"],
                HorizontalAlignment = HorizontalAlignment.Center
            });
        }

        // Error message with retry
        if (model.Status == ModelStatus.Failed)
        {
            var errorPanel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            errorPanel.Children.Add(new FontIcon
            {
                Glyph = "\uE783",
                FontSize = 14,
                Foreground = new SolidColorBrush(Colors.Red)
            });
            errorPanel.Children.Add(new TextBlock
            {
                Text = "Download failed",
                FontSize = 12,
                Foreground = new SolidColorBrush(Colors.Red),
                VerticalAlignment = VerticalAlignment.Center
            });

            var retryBtn = new Button { Content = "Retry", FontSize = 12 };
            var modelId = model.Id;
            retryBtn.Click += async (_, _) =>
            {
                try { await _modelService!.DownloadModelAsync(modelId); }
                catch { }
            };
            errorPanel.Children.Add(retryBtn);
            outerStack.Children.Add(errorPanel);
        }

        card.Child = outerStack;
        return card;
    }

    private void OnClose(object sender, RoutedEventArgs e)
        => CloseRequested?.Invoke(this, EventArgs.Empty);

    private static string FormatBytes(long bytes)
    {
        if (bytes >= 1_073_741_824) return $"{bytes / 1_073_741_824.0:F1} GB";
        if (bytes >= 1_048_576) return $"{bytes / 1_048_576.0:F1} MB";
        if (bytes >= 1024) return $"{bytes / 1024.0:F1} KB";
        return $"{bytes} B";
    }
}

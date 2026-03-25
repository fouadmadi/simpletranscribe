using Microsoft.UI.Xaml.Controls;
using SimpleTranscribe.Models;
using SimpleTranscribe.Services;

namespace SimpleTranscribe.Views;

public sealed partial class SettingsPanel : UserControl
{
    public event EventHandler<string?>? DeviceChanged;
    public event EventHandler<string>? ModelChanged;
    public event EventHandler<string>? LanguageChanged;

    private bool _suppressEvents;

    public SettingsPanel()
    {
        InitializeComponent();
    }

    public void UpdateDevices(List<AudioDeviceInfo> devices, string? selectedId)
    {
        _suppressEvents = true;
        MicrophoneComboBox.Items.Clear();
        int selectedIndex = -1;
        for (int i = 0; i < devices.Count; i++)
        {
            MicrophoneComboBox.Items.Add(new ComboBoxItem
            {
                Content = devices[i].Name,
                Tag = devices[i].Id
            });
            if (devices[i].Id == selectedId)
                selectedIndex = i;
        }
        if (selectedIndex >= 0)
            MicrophoneComboBox.SelectedIndex = selectedIndex;
        _suppressEvents = false;
    }

    public void UpdateModels(List<ModelInfo> models, string selectedId)
    {
        _suppressEvents = true;
        ModelComboBox.Items.Clear();
        int selectedIndex = -1;
        for (int i = 0; i < models.Count; i++)
        {
            ModelComboBox.Items.Add(new ComboBoxItem
            {
                Content = models[i].Name,
                Tag = models[i].Id
            });
            if (models[i].Id == selectedId)
                selectedIndex = i;
        }
        if (selectedIndex >= 0)
            ModelComboBox.SelectedIndex = selectedIndex;
        _suppressEvents = false;
    }

    public void UpdateLanguage(string language)
    {
        _suppressEvents = true;
        for (int i = 0; i < LanguageComboBox.Items.Count; i++)
        {
            if (LanguageComboBox.Items[i] is ComboBoxItem item && (string)item.Tag == language)
            {
                LanguageComboBox.SelectedIndex = i;
                break;
            }
        }
        _suppressEvents = false;
    }

    private void OnMicrophoneChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressEvents) return;
        var selected = MicrophoneComboBox.SelectedItem as ComboBoxItem;
        DeviceChanged?.Invoke(this, selected?.Tag as string);
    }

    private void OnModelChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressEvents) return;
        var selected = ModelComboBox.SelectedItem as ComboBoxItem;
        if (selected?.Tag is string modelId)
            ModelChanged?.Invoke(this, modelId);
    }

    private void OnLanguageChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressEvents) return;
        var selected = LanguageComboBox.SelectedItem as ComboBoxItem;
        if (selected?.Tag is string lang)
            LanguageChanged?.Invoke(this, lang);
    }
}

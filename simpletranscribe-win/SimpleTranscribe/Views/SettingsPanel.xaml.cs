using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using SimpleTranscribe.Models;
using SimpleTranscribe.Services;
using Windows.System;

namespace SimpleTranscribe.Views;

public sealed partial class SettingsPanel : UserControl
{
    public event EventHandler<string?>? DeviceChanged;
    public event EventHandler<string>? ModelChanged;
    public event EventHandler<string>? LanguageChanged;
    public event EventHandler<bool>? UseSystemDefaultChanged;
    public event EventHandler<(int vKey, int modifierVKey)>? HotKeyChanged;
    public event EventHandler<bool>? StreamingChanged;
    public event EventHandler<bool>? CapitaliseSentencesChanged;
    public event EventHandler<bool>? RemoveFillersChanged;
    public event EventHandler<bool>? NumberFormattingChanged;

    private bool _suppressEvents;
    private bool _isRecordingHotKey;

    // Known conflict combos: (modifierVKey, vKey) pairs
    private static readonly HashSet<(int, int)> KnownConflicts = new()
    {
        (0x11, 0x43), // Ctrl+C
        (0x11, 0x56), // Ctrl+V
        (0x11, 0x5A), // Ctrl+Z
        (0x11, 0x41), // Ctrl+A
    };

    public SettingsPanel()
    {
        InitializeComponent();
    }

    // --- Existing update methods ---

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

    public void UpdateLanguages(List<SupportedLanguage> languages, string selectedCode)
    {
        _suppressEvents = true;
        LanguageComboBox.Items.Clear();
        int selectedIndex = 0;
        for (int i = 0; i < languages.Count; i++)
        {
            LanguageComboBox.Items.Add(new ComboBoxItem
            {
                Content = languages[i].DisplayName,
                Tag = languages[i].Code
            });
            if (languages[i].Code == selectedCode)
                selectedIndex = i;
        }
        if (LanguageComboBox.Items.Count > 0)
            LanguageComboBox.SelectedIndex = selectedIndex;
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

    public void UpdateUseSystemDefault(bool value)
    {
        _suppressEvents = true;
        UseSystemDefaultCheckBox.IsChecked = value;
        MicrophoneComboBox.IsEnabled = !value;
        _suppressEvents = false;
    }

    public void UpdateDeviceSwitchMessage(string message)
    {
        DeviceSwitchMessageText.Text = message;
        DeviceSwitchMessageText.Visibility = string.IsNullOrEmpty(message)
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

    public void UpdateHotKey(int vKey, int modifierVKey)
    {
        HotKeyBox.Text = FormatHotKey(modifierVKey, vKey);
        HotKeyConflictText.Visibility = KnownConflicts.Contains((modifierVKey, vKey))
            ? Visibility.Visible : Visibility.Collapsed;
    }

    // --- Event handlers ---

    private void OnUseSystemDefaultChanged(object sender, RoutedEventArgs e)
    {
        if (_suppressEvents) return;
        UseSystemDefaultChanged?.Invoke(this, UseSystemDefaultCheckBox.IsChecked == true);
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

    // --- Hotkey recorder ---

    private void HotKeyBox_GotFocus(object sender, RoutedEventArgs e)
    {
        _isRecordingHotKey = true;
        HotKeyBox.PlaceholderText = "Press keys…";
        HotKeyBox.Text = "";
    }

    private void HotKeyBox_LostFocus(object sender, RoutedEventArgs e)
    {
        _isRecordingHotKey = false;
        HotKeyBox.PlaceholderText = "Click to record";
    }

    private void HotKeyBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (!_isRecordingHotKey) return;

        var vKey = (int)e.Key;
        // Determine modifier: check Ctrl
        bool ctrlHeld = Microsoft.UI.Input.InputKeyboardSource
            .GetKeyStateForCurrentThread(VirtualKey.Control)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);
        bool shiftHeld = Microsoft.UI.Input.InputKeyboardSource
            .GetKeyStateForCurrentThread(VirtualKey.Shift)
            .HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);

        // Skip if only a modifier key was pressed
        if (vKey is 0x10 or 0x11 or 0x12 or 0xA0 or 0xA1 or 0xA2 or 0xA3 or 0xA4 or 0xA5)
            return;

        int modVKey = ctrlHeld ? 0x11 : (shiftHeld ? 0x10 : 0);
        HotKeyBox.Text = FormatHotKey(modVKey, vKey);
        HotKeyConflictText.Visibility = KnownConflicts.Contains((modVKey, vKey))
            ? Visibility.Visible : Visibility.Collapsed;
        HotKeyChanged?.Invoke(this, (vKey, modVKey));
        e.Handled = true;

        // Release focus after recording
        HotKeyBox.IsEnabled = false;
        HotKeyBox.IsEnabled = true;
    }

    private void HotKeyReset_Click(object sender, RoutedEventArgs e)
    {
        int defaultVKey = 0x20; // VK_SPACE
        int defaultModVKey = 0x11; // VK_CONTROL
        HotKeyBox.Text = FormatHotKey(defaultModVKey, defaultVKey);
        HotKeyConflictText.Visibility = Visibility.Collapsed;
        HotKeyChanged?.Invoke(this, (defaultVKey, defaultModVKey));
    }

    // --- Streaming toggle ---

    public void UpdateStreaming(bool enabled)
    {
        _suppressEvents = true;
        StreamingCheckBox.IsChecked = enabled;
        _suppressEvents = false;
    }

    private void OnStreamingChanged(object sender, RoutedEventArgs e)
    {
        if (_suppressEvents) return;
        StreamingChanged?.Invoke(this, StreamingCheckBox.IsChecked == true);
    }

    // --- Text processing toggles ---

    public void UpdateTextProcessing(bool capitalise, bool fillers, bool numbers)
    {
        _suppressEvents = true;
        CapitaliseCheckBox.IsChecked = capitalise;
        FillersCheckBox.IsChecked = fillers;
        NumbersCheckBox.IsChecked = numbers;
        _suppressEvents = false;
    }

    private void OnCapitaliseChanged(object sender, RoutedEventArgs e)
    {
        if (_suppressEvents) return;
        CapitaliseSentencesChanged?.Invoke(this, CapitaliseCheckBox.IsChecked == true);
    }

    private void OnFillersChanged(object sender, RoutedEventArgs e)
    {
        if (_suppressEvents) return;
        RemoveFillersChanged?.Invoke(this, FillersCheckBox.IsChecked == true);
    }

    private void OnNumbersChanged(object sender, RoutedEventArgs e)
    {
        if (_suppressEvents) return;
        NumberFormattingChanged?.Invoke(this, NumbersCheckBox.IsChecked == true);
    }

    private static string FormatHotKey(int modVKey, int vKey)
    {
        var parts = new List<string>();
        if (modVKey == 0x11) parts.Add("Ctrl");
        else if (modVKey == 0x10) parts.Add("Shift");
        else if (modVKey == 0x12) parts.Add("Alt");

        // Convert vKey to readable name
        var keyName = vKey switch
        {
            0x20 => "Space",
            0x0D => "Enter",
            0x09 => "Tab",
            >= 0x41 and <= 0x5A => ((char)vKey).ToString(),
            >= 0x30 and <= 0x39 => ((char)vKey).ToString(),
            >= 0x70 and <= 0x7B => $"F{vKey - 0x6F}",
            _ => $"Key{vKey:X2}"
        };
        parts.Add(keyName);
        return string.Join("+", parts);
    }
}

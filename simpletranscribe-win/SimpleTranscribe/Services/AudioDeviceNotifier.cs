using NAudio.CoreAudioApi;
using NAudio.CoreAudioApi.Interfaces;

namespace SimpleTranscribe.Services;

/// <summary>
/// Listens for Windows audio endpoint changes (device added/removed, default changed)
/// via the MMDevice notification API and surfaces them as .NET events.
/// COM callbacks arrive on a background thread — consumers must marshal to UI thread.
/// </summary>
public class AudioDeviceNotifier : IMMNotificationClient, IDisposable
{
    private static readonly AppLogger Log = AppLogger.Instance;

    private readonly MMDeviceEnumerator _enumerator;
    private readonly object _debounceLock = new();
    private Timer? _debounceTimer;
    private bool _disposed;

    /// <summary>
    /// Raised when any device is added, removed, or changes state.
    /// Debounced to fire at most once per 300ms of quiet.
    /// </summary>
    public event Action? DevicesChanged;

    /// <summary>
    /// Raised when the default capture (input) device changes.
    /// The argument is the new default device ID.
    /// </summary>
    public event Action<string>? DefaultDeviceChanged;

    public AudioDeviceNotifier()
    {
        _enumerator = new MMDeviceEnumerator();
        _enumerator.RegisterEndpointNotificationCallback(this);
        Log.Info("AudioDeviceNotifier", "Registered for endpoint notifications");
    }

    public void OnDeviceStateChanged(string deviceId, DeviceState newState)
    {
        Log.Info("AudioDeviceNotifier", $"Device state changed: {deviceId} → {newState}");
        RaiseDevicesChanged();
    }

    public void OnDeviceAdded(string deviceId)
    {
        Log.Info("AudioDeviceNotifier", $"Device added: {deviceId}");
        RaiseDevicesChanged();
    }

    public void OnDeviceRemoved(string deviceId)
    {
        Log.Info("AudioDeviceNotifier", $"Device removed: {deviceId}");
        RaiseDevicesChanged();
    }

    public void OnDefaultDeviceChanged(DataFlow flow, Role role, string defaultDeviceId)
    {
        if (flow != DataFlow.Capture)
            return;

        Log.Info("AudioDeviceNotifier", $"Default capture device changed: {defaultDeviceId}");
        DefaultDeviceChanged?.Invoke(defaultDeviceId);
    }

    public void OnPropertyValueChanged(string deviceId, PropertyKey key)
    {
        // Intentionally ignored — property changes are too noisy and not actionable.
    }

    /// <summary>
    /// Debounce rapid device events — only fire DevicesChanged after 300ms of quiet.
    /// </summary>
    private void RaiseDevicesChanged()
    {
        lock (_debounceLock)
        {
            _debounceTimer?.Dispose();
            _debounceTimer = new Timer(_ => DevicesChanged?.Invoke(), null, 300, Timeout.Infinite);
        }
    }

    public void Dispose()
    {
        if (_disposed)
            return;
        _disposed = true;

        try
        {
            _enumerator.UnregisterEndpointNotificationCallback(this);
        }
        catch (Exception ex)
        {
            Log.Error("AudioDeviceNotifier", "Failed to unregister notification callback", ex);
        }

        lock (_debounceLock)
        {
            _debounceTimer?.Dispose();
            _debounceTimer = null;
        }

        _enumerator.Dispose();
        Log.Info("AudioDeviceNotifier", "Disposed");
        GC.SuppressFinalize(this);
    }
}

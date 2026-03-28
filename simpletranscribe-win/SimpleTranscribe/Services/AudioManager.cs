using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace SimpleTranscribe.Services;

/// <summary>
/// Handles audio capture from microphone, converting to 16kHz mono float32 for Whisper.
/// Port of macOS AudioManager.swift using NAudio WASAPI.
/// </summary>
public class AudioManager : IDisposable
{
    private static readonly AppLogger Log = AppLogger.Instance;

    private WasapiCapture? _capture;
    private MMDevice? _captureDevice;
    private WaveFormat? _captureFormat;
    private bool _isRecording;

    private const int TargetSampleRate = 16000;

    /// <summary>
    /// Fired when a new buffer of float32 audio samples (16kHz mono) is available.
    /// </summary>
    public event Action<float[]>? OnBufferReceived;

    /// <summary>
    /// Fired when a capture error occurs.
    /// </summary>
    public event Action<Exception>? OnError;

    /// <summary>
    /// Get available audio input devices.
    /// </summary>
    public static List<AudioDeviceInfo> GetInputDevices()
    {
        var devices = new List<AudioDeviceInfo>();
        using var enumerator = new MMDeviceEnumerator();

        try
        {
            var endpoints = enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active);
            foreach (var device in endpoints)
            {
                try
                {
                    devices.Add(new AudioDeviceInfo(device.ID, device.FriendlyName));
                }
                finally
                {
                    device.Dispose();
                }
            }
        }
        catch { /* Device enumeration may fail if no audio subsystem */ }

        return devices;
    }

    /// <summary>
    /// Get the default audio input device ID, or null if none.
    /// </summary>
    public static string? GetDefaultDeviceId()
    {
        try
        {
            using var enumerator = new MMDeviceEnumerator();
            using var device = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);
            return device.ID;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// Start recording from the specified device (or default if null).
    /// Audio is resampled to 16kHz mono float32 before invoking OnBufferReceived.
    /// </summary>
    public void StartRecording(string? deviceId = null)
    {
        if (_isRecording)
            StopRecording();

        try
        {
            using var enumerator = new MMDeviceEnumerator();
            _captureDevice = deviceId != null
                ? enumerator.GetDevice(deviceId)
                : enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);

            _capture = new WasapiCapture(_captureDevice)
            {
                ShareMode = AudioClientShareMode.Shared
            };

            _captureFormat = _capture.WaveFormat;
            _capture.DataAvailable += OnDataAvailable;
            _capture.RecordingStopped += OnRecordingStopped;
            _capture.StartRecording();
            _isRecording = true;
            Log.Info("Audio", $"Recording started (device={_captureDevice?.FriendlyName}, format={_captureFormat})");
        }
        catch (Exception ex)
        {
            _isRecording = false;
            _capture?.Dispose();
            _capture = null;
            _captureDevice?.Dispose();
            _captureDevice = null;
            Log.Error("Audio", "Failed to start recording", ex);
            OnError?.Invoke(ex);
        }
    }

    /// <summary>
    /// Stop recording and release resources.
    /// </summary>
    public void StopRecording()
    {
        if (!_isRecording || _capture == null)
            return;

        _isRecording = false;
        try
        {
            _capture.StopRecording();
        }
        catch { /* Ignore errors during stop */ }

        _capture.DataAvailable -= OnDataAvailable;
        _capture.RecordingStopped -= OnRecordingStopped;
        _capture.Dispose();
        _capture = null;

        _captureDevice?.Dispose();
        _captureDevice = null;
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        if (e.BytesRecorded == 0 || _captureFormat == null)
            return;

        try
        {
            // Convert raw bytes to float samples based on capture format
            var floats = ConvertToFloat(_captureFormat, e.Buffer, e.BytesRecorded);

            // Resample to 16kHz mono if needed
            if (_captureFormat.SampleRate != TargetSampleRate || _captureFormat.Channels != 1)
            {
                floats = ResampleToMono16kHz(floats, _captureFormat.SampleRate, _captureFormat.Channels);
            }

            if (floats.Length > 0)
                OnBufferReceived?.Invoke(floats);
        }
        catch (Exception ex)
        {
            OnError?.Invoke(ex);
        }
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        _isRecording = false;
        if (e.Exception != null)
            OnError?.Invoke(e.Exception);
    }

    /// <summary>
    /// Convert raw audio bytes to float32 samples normalized to [-1, 1].
    /// </summary>
    private static float[] ConvertToFloat(WaveFormat format, byte[] buffer, int bytesRecorded)
    {
        if (format.Encoding == WaveFormatEncoding.IeeeFloat)
        {
            var sampleCount = bytesRecorded / 4;
            var result = new float[sampleCount];
            Buffer.BlockCopy(buffer, 0, result, 0, bytesRecorded);
            return result;
        }
        else if (format.BitsPerSample == 16)
        {
            var sampleCount = bytesRecorded / 2;
            var result = new float[sampleCount];
            for (int i = 0; i < sampleCount; i++)
            {
                var sample = BitConverter.ToInt16(buffer, i * 2);
                result[i] = sample / 32768f;
            }
            return result;
        }
        else if (format.BitsPerSample == 24)
        {
            var sampleCount = bytesRecorded / 3;
            var result = new float[sampleCount];
            for (int i = 0; i < sampleCount; i++)
            {
                int sample = buffer[i * 3] | (buffer[i * 3 + 1] << 8) | (buffer[i * 3 + 2] << 16);
                if ((sample & 0x800000) != 0) sample |= unchecked((int)0xFF000000); // Sign extend
                result[i] = sample / 8388608f;
            }
            return result;
        }
        else if (format.BitsPerSample == 32 && format.Encoding != WaveFormatEncoding.IeeeFloat)
        {
            var sampleCount = bytesRecorded / 4;
            var result = new float[sampleCount];
            for (int i = 0; i < sampleCount; i++)
            {
                var sample = BitConverter.ToInt32(buffer, i * 4);
                result[i] = sample / 2147483648f;
            }
            return result;
        }

        return [];
    }

    /// <summary>
    /// Resample multi-channel audio to 16kHz mono using simple linear interpolation.
    /// </summary>
    private static float[] ResampleToMono16kHz(float[] input, int sourceSampleRate, int channels)
    {
        // First, mix down to mono if multi-channel
        float[] mono;
        if (channels > 1)
        {
            var monoLength = input.Length / channels;
            mono = new float[monoLength];
            for (int i = 0; i < monoLength; i++)
            {
                float sum = 0;
                for (int ch = 0; ch < channels; ch++)
                    sum += input[i * channels + ch];
                mono[i] = sum / channels;
            }
        }
        else
        {
            mono = input;
        }

        // Resample to 16kHz if needed
        if (sourceSampleRate == TargetSampleRate)
            return mono;

        var ratio = (double)TargetSampleRate / sourceSampleRate;
        var outputLength = (int)(mono.Length * ratio);
        var output = new float[outputLength];

        for (int i = 0; i < outputLength; i++)
        {
            var srcIndex = i / ratio;
            var idx = (int)srcIndex;
            var frac = (float)(srcIndex - idx);

            if (idx + 1 < mono.Length)
                output[i] = mono[idx] * (1 - frac) + mono[idx + 1] * frac;
            else if (idx < mono.Length)
                output[i] = mono[idx];
        }

        return output;
    }

    public void Dispose()
    {
        StopRecording();
        GC.SuppressFinalize(this);
    }
}

/// <summary>
/// Simple audio device descriptor.
/// </summary>
public record AudioDeviceInfo(string Id, string Name);

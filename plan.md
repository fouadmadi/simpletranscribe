# SimpleTranscribe Windows Port — Implementation Plan

> **Target:** Windows 11, C# / WinUI 3, whisper.cpp via C/C++ interop  
> **Distribution:** Standalone installer (.exe/.msi)  
> **Repo layout:** Monorepo — new `simpletranscribe-win/` folder alongside existing macOS project  
> **Goal:** Full feature parity with macOS version

---

## 1. macOS Source Inventory & Windows Mapping

This section maps every macOS source file to its Windows equivalent, identifying exact API replacements.

### 1.1 File-by-File Mapping

| macOS File | LOC | macOS APIs Used | Windows Equivalent | Windows APIs |
|---|---|---|---|---|
| `simpletranscribeApp.swift` | 31 | `SwiftUI.App`, `WindowGroup`, `NSApplication` | `App.xaml` + `App.xaml.cs` | `Microsoft.UI.Xaml.Application`, `Window` |
| `AppModel.swift` | 87 | `@Observable`, `AVCaptureDevice.DiscoverySession`, `UserDefaults` | `AppModel.cs` | `CommunityToolkit.Mvvm.ObservableObject`, `Windows.Devices.Enumeration.DeviceInformation`, `Windows.Storage.ApplicationData.Current.LocalSettings` |
| `AudioManager.swift` | 107 | `AVAudioEngine`, `AVAudioConverter`, `AVAudioPCMBuffer`, `AVCaptureDevice` | `AudioManager.cs` | `Windows.Media.Capture.MediaCapture`, `NAudio.Wave.WasapiCapture` or `AudioGraph` API |
| `TranscriptionManager.swift` | 115 | `SwiftWhisper.Whisper`, `whisper_cpp`, `NSLock` | `TranscriptionManager.cs` | `whisper.cpp` P/Invoke or Whisper.net, `SemaphoreSlim` |
| `HotKeyManager.swift` | 66 | `NSEvent.addGlobalMonitorForEvents`, `NSEvent.addLocalMonitorForEvents`, `.flagsChanged` | `HotKeyManager.cs` | `User32.RegisterHotKey` / low-level keyboard hook via `SetWindowsHookEx` |
| `SoundManager.swift` | 23 | `NSSound(named: "Tink/Glass/Basso")` | `SoundManager.cs` | `Windows.Media.Playback.MediaPlayer` with bundled .wav files, or `System.Media.SystemSounds` |
| `PasteService.swift` | 111 | `CGEvent` (Quartz), `NSAppleScript`, `Process("osascript")`, `NSPasteboard` | `PasteService.cs` | `Windows.ApplicationModel.DataTransfer.Clipboard` + `SendKeys` / `InputSimulator` (via `SendInput` Win32 API) |
| `ContentView.swift` | 332 | SwiftUI views, `@State`, `@Environment`, `AXIsProcessTrusted()` | `MainWindow.xaml` + `MainWindow.xaml.cs` | WinUI 3 XAML, `x:Bind`, community toolkit |
| `Models/ModelInfo.swift` | 37 | Foundation `Codable`, `ByteCountFormatter` | `Models/ModelInfo.cs` | `System.Text.Json`, custom byte formatter |
| `Models/KnownModels.swift` | 57 | Foundation static list | `Models/KnownModels.cs` | Static `List<ModelInfo>` |
| `Services/ModelService.swift` | 372 | `URLSession`, `URLSessionDownloadDelegate`, `FileManager`, `CryptoKit.SHA256`, `FileHandle` | `Services/ModelService.cs` | `HttpClient` + `IProgress<T>`, `System.IO.File`, `System.Security.Cryptography.SHA256` |
| `Views/ModelDownloadView.swift` | 228 | SwiftUI `@Bindable`, `ScrollView`, `ProgressView` | `Views/ModelDownloadPage.xaml` | WinUI 3 `ListView`, `ProgressBar`, `ContentDialog` |
| `Views/RecordingControlsView.swift` | 64 | SwiftUI `Button`, `ProgressView`, `HStack` | `Views/RecordingControlsPanel.xaml` | WinUI 3 `StackPanel`, `Button`, `ProgressRing` |
| `Views/SettingsAreaView.swift` | 48 | SwiftUI `Picker`, `AVCaptureDevice` | `Views/SettingsPanel.xaml` | WinUI 3 `ComboBox`, `DeviceInformation` |
| `Views/TranscriptResultsView.swift` | 30 | SwiftUI `TextEditor`, `NSPasteboard` | `Views/TranscriptResultsPanel.xaml` | WinUI 3 `TextBox` (multiline), `Clipboard` |

### 1.2 External Dependencies Mapping

| macOS Dependency | Purpose | Windows Replacement | NuGet / Source |
|---|---|---|---|
| `SwiftWhisper` (SPM, wraps whisper.cpp) | Whisper inference | **whisper.cpp native DLL** + C# P/Invoke wrapper | Build from source or use `Whisper.net` NuGet as fallback |
| `AVFoundation` (system) | Audio capture | **NAudio** (preferred) or `Windows.Media.Audio.AudioGraph` | `NAudio` NuGet |
| `CryptoKit` (system) | SHA256 hash verification | `System.Security.Cryptography` | Built-in .NET |
| `ApplicationServices` (system) | CGEvent paste simulation | **Win32 `SendInput`** via P/Invoke | Built-in Windows SDK |
| `Cocoa/AppKit` (system) | NSEvent, NSSound, NSPasteboard, NSWorkspace | Various Win32 + WinRT APIs | Windows App SDK |

---

## 2. Project Structure

```
simpletranscribe/
├── simpletranscribe/            # (existing macOS project)
├── simpletranscribe.xcodeproj/  # (existing)
├── simpletranscribe-win/        # ★ NEW — Windows project root
│   ├── SimpleTranscribe.sln
│   ├── SimpleTranscribe/
│   │   ├── SimpleTranscribe.csproj
│   │   ├── App.xaml
│   │   ├── App.xaml.cs
│   │   ├── MainWindow.xaml
│   │   ├── MainWindow.xaml.cs
│   │   ├── Models/
│   │   │   ├── ModelInfo.cs
│   │   │   └── KnownModels.cs
│   │   ├── Services/
│   │   │   ├── AudioManager.cs
│   │   │   ├── TranscriptionManager.cs
│   │   │   ├── ModelService.cs
│   │   │   ├── HotKeyManager.cs
│   │   │   ├── SoundManager.cs
│   │   │   └── PasteService.cs
│   │   ├── ViewModels/
│   │   │   └── MainViewModel.cs
│   │   ├── Views/
│   │   │   ├── RecordingControlsPanel.xaml(.cs)
│   │   │   ├── SettingsPanel.xaml(.cs)
│   │   │   ├── TranscriptResultsPanel.xaml(.cs)
│   │   │   └── ModelDownloadPage.xaml(.cs)
│   │   ├── Interop/
│   │   │   ├── WhisperInterop.cs       # P/Invoke bindings for whisper.cpp
│   │   │   └── Win32Interop.cs         # SendInput, RegisterHotKey, etc.
│   │   ├── Assets/
│   │   │   ├── Sounds/
│   │   │   │   ├── recording_start.wav
│   │   │   │   ├── transcription_complete.wav
│   │   │   │   └── error.wav
│   │   │   └── Icons/
│   │   │       └── (app icon .ico)
│   │   └── Native/
│   │       └── whisper.dll             # Pre-built or build-from-source
│   ├── SimpleTranscribe.Installer/     # WiX / Inno Setup project
│   │   └── ...
│   └── SimpleTranscribe.Tests/
│       ├── SimpleTranscribe.Tests.csproj
│       └── ...
```

---

## 3. Detailed Implementation — Component by Component

### 3.1 whisper.cpp Integration (Interop/WhisperInterop.cs)

**macOS approach:** SwiftWhisper SPM package wraps whisper.cpp C library. `Whisper(fromFileURL:)` loads model, `whisper.transcribe(audioFrames:)` runs inference.

**Windows approach:**

1. **Build whisper.cpp as a native DLL** (`whisper.dll`) targeting x64 and ARM64
   - Clone `ggerganov/whisper.cpp`, build with CMake:
     ```
     cmake -B build -DBUILD_SHARED_LIBS=ON -DWHISPER_NO_AVX2=OFF
     cmake --build build --config Release
     ```
   - Output: `whisper.dll` + `whisper.h`

2. **Create C# P/Invoke wrapper** (`WhisperInterop.cs`):
   ```csharp
   internal static partial class WhisperNative
   {
       [LibraryImport("whisper", EntryPoint = "whisper_init_from_file")]
       internal static partial IntPtr InitFromFile(
           [MarshalAs(UnmanagedType.LPStr)] string pathModel);

       [LibraryImport("whisper", EntryPoint = "whisper_full")]
       internal static partial int Full(IntPtr ctx, WhisperFullParams pars,
           float[] samples, int nSamples);

       [LibraryImport("whisper", EntryPoint = "whisper_full_n_segments")]
       internal static partial int FullNSegments(IntPtr ctx);

       [LibraryImport("whisper", EntryPoint = "whisper_full_get_segment_text")]
       internal static partial IntPtr FullGetSegmentText(IntPtr ctx, int iSegment);

       [LibraryImport("whisper", EntryPoint = "whisper_free")]
       internal static partial void Free(IntPtr ctx);
   }
   ```

3. **High-level wrapper** (`TranscriptionManager.cs`):
   ```csharp
   public class TranscriptionManager : IDisposable
   {
       private IntPtr _ctx;
       private readonly List<float> _accumulatedAudio = new();
       private readonly SemaphoreSlim _audioLock = new(1, 1);

       public async Task LoadModelAsync(string modelPath) { ... }
       public void AppendAudio(float[] buffer) { ... }
       public async Task<string> ProcessAudioAsync() { ... }
   }
   ```

**Key considerations:**
- Ship `whisper.dll` alongside the .exe (same directory or `Native/` subfolder)
- Use `NativeLibrary.SetDllImportResolver()` to handle DLL search path
- Support both x64 and ARM64 by shipping platform-specific DLLs in `runtimes/win-x64/native/` and `runtimes/win-arm64/native/`
- Match macOS params: `n_threads = Environment.ProcessorCount`, `no_context = true`, `single_segment = true`

### 3.2 Audio Capture (Services/AudioManager.cs)

**macOS approach:** `AVAudioEngine` installs a tap on the input node, receives `AVAudioPCMBuffer` at hardware sample rate, converts to 16kHz mono Float32 via `AVAudioConverter`.

**Windows approach using NAudio:**

```csharp
public class AudioManager : IDisposable
{
    private WasapiCapture? _capture;
    private WaveFormat _targetFormat = new(16000, 16, 1); // 16kHz mono
    public event Action<float[]>? OnBufferReceived;

    public async Task<IReadOnlyList<DeviceInfo>> GetInputDevicesAsync()
    {
        // Use MMDeviceEnumerator to list audio input devices
        var enumerator = new MMDeviceEnumerator();
        return enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active)
            .Select(d => new DeviceInfo(d.ID, d.FriendlyName))
            .ToList();
    }

    public void StartRecording(string? deviceId = null)
    {
        var device = deviceId != null
            ? new MMDeviceEnumerator().GetDevice(deviceId)
            : new MMDeviceEnumerator().GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);

        _capture = new WasapiCapture(device);
        _capture.WaveFormat = new WaveFormat(16000, 16, 1);
        _capture.DataAvailable += OnDataAvailable;
        _capture.StartRecording();
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        // Convert byte[] to float[] (16-bit PCM → float normalized to [-1, 1])
        var floats = ConvertToFloat(e.Buffer, e.BytesRecorded);
        OnBufferReceived?.Invoke(floats);
    }

    public void StopRecording() { _capture?.StopRecording(); ... }
}
```

**Key considerations:**
- NAudio's `WasapiCapture` is the closest equivalent to `AVAudioEngine`
- Must handle sample rate conversion if device doesn't support 16kHz natively — use `MediaFoundationResampler` or `WdlResamplingSampleProvider`
- Buffer format: whisper.cpp expects float32 normalized to [-1, 1] range at 16kHz mono (identical to macOS)
- Device enumeration via `MMDeviceEnumerator` replaces `AVCaptureDevice.DiscoverySession`

### 3.3 Global Hotkey (Services/HotKeyManager.cs)

**macOS approach:** `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` watches for `fn + ctrl` modifier combo. Works both in-app and globally.

**Windows approach:**

Two options, both needed:

1. **`RegisterHotKey` Win32 API** — for a specific key combo (e.g., `Ctrl+Shift+T` to toggle):
   ```csharp
   [DllImport("user32.dll")]
   static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
   ```
   - Simpler but only supports key-down events (no press-and-hold detection)

2. **Low-level keyboard hook** (`SetWindowsHookEx` with `WH_KEYBOARD_LL`) — for press-to-talk:
   ```csharp
   // Detect key down → start recording, key up → stop & transcribe
   private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
   {
       if (nCode >= 0)
       {
           var vkCode = Marshal.ReadInt32(lParam);
           bool isKeyDown = wParam == (IntPtr)WM_KEYDOWN;
           bool isKeyUp = wParam == (IntPtr)WM_KEYUP;
           // Check for configured hotkey combo...
       }
       return CallNextHookEx(_hookID, nCode, wParam, lParam);
   }
   ```

**Recommended approach:** Use a low-level keyboard hook for press-to-talk (hold `Ctrl+Space` to record, release to transcribe) — this directly mirrors the macOS `fn+ctrl` hold behavior. Wrap in `Win32Interop.cs`.

**Key considerations:**
- macOS `fn` key has no direct Windows equivalent; use `Ctrl+Space` or make it configurable
- Low-level hooks require a message pump (WinUI 3's `DispatcherQueue` provides this)
- Hook callback runs on the thread that installed it — marshal to UI thread via `DispatcherQueue`

### 3.4 Paste-at-Cursor (Services/PasteService.cs)

**macOS approach:** Three fallback strategies: `CGEvent` (simulates ⌘V), `NSAppleScript`, `osascript` subprocess. Requires Accessibility permission.

**Windows approach:**

```csharp
public static class PasteService
{
    public static void CopyAndPaste(string text)
    {
        // 1. Copy to clipboard
        var dataPackage = new DataPackage();
        dataPackage.SetText(text);
        Clipboard.SetContent(dataPackage);

        // 2. Simulate Ctrl+V via SendInput
        SimulateCtrlV();
    }

    private static void SimulateCtrlV()
    {
        var inputs = new INPUT[]
        {
            // Ctrl down
            new INPUT { type = INPUT_KEYBOARD, ki = new KEYBDINPUT { wVk = VK_CONTROL } },
            // V down
            new INPUT { type = INPUT_KEYBOARD, ki = new KEYBDINPUT { wVk = 0x56 } },
            // V up
            new INPUT { type = INPUT_KEYBOARD, ki = new KEYBDINPUT { wVk = 0x56, dwFlags = KEYEVENTF_KEYUP } },
            // Ctrl up
            new INPUT { type = INPUT_KEYBOARD, ki = new KEYBDINPUT { wVk = VK_CONTROL, dwFlags = KEYEVENTF_KEYUP } },
        };
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }
}
```

**Key considerations:**
- Windows `SendInput` is the direct equivalent of macOS `CGEvent` posting — no special permissions needed (unlike macOS Accessibility)
- No need for multiple fallback strategies on Windows; `SendInput` works universally
- Add a small delay (~100ms) between clipboard set and `SendInput` to ensure clipboard is ready
- WinUI 3 clipboard API (`Windows.ApplicationModel.DataTransfer.Clipboard`) or classic `System.Windows.Forms.Clipboard`

### 3.5 Sound Feedback (Services/SoundManager.cs)

**macOS approach:** `NSSound(named: "Tink")`, `NSSound(named: "Glass")`, `NSSound(named: "Basso")` — system sounds.

**Windows approach:**

```csharp
public static class SoundManager
{
    private static readonly MediaPlayer _player = new();

    public static void PlayRecordingStarted()
        => PlaySound("ms-appx:///Assets/Sounds/recording_start.wav");

    public static void PlayTranscriptionComplete()
        => PlaySound("ms-appx:///Assets/Sounds/transcription_complete.wav");

    public static void PlayError()
        => PlaySound("ms-appx:///Assets/Sounds/error.wav");

    private static void PlaySound(string uri)
    {
        _player.Source = MediaSource.CreateFromUri(new Uri(uri));
        _player.Play();
    }
}
```

**Key considerations:**
- Windows has no direct equivalent of macOS named system sounds with nice tones
- Bundle 3 short .wav files (can source from Windows system sounds or create custom)
- Alternative: use `SystemSounds.Asterisk.Play()` etc., but these are limited and not as pleasant
- `MediaPlayer` from `Windows.Media.Playback` namespace works well in WinUI 3

### 3.6 App Model / State Management (ViewModels/MainViewModel.cs)

**macOS approach:** `@Observable class AppModel` with `UserDefaults` persistence in `didSet`.

**Windows approach:**

```csharp
public partial class MainViewModel : ObservableObject
{
    [ObservableProperty] private bool _isRecording;
    [ObservableProperty] private string _transcribedText = "";
    [ObservableProperty] private bool _isProcessing;
    [ObservableProperty] private string? _errorMessage;
    [ObservableProperty] private bool _showTranscriptionStarted;

    // Persisted via ApplicationData.Current.LocalSettings
    private string _selectedLanguage;
    public string SelectedLanguage
    {
        get => _selectedLanguage;
        set { SetProperty(ref _selectedLanguage, value); SaveSetting("language", value); }
    }
    // ... similar for selectedModelID, selectedInputDeviceId
}
```

**Key considerations:**
- Use `CommunityToolkit.Mvvm` NuGet for `ObservableObject`, `[ObservableProperty]`, `[RelayCommand]`
- Settings persistence: `Windows.Storage.ApplicationData.Current.LocalSettings` (WinRT) or `System.Text.Json` to a local config file
- Device enumeration: `Windows.Devices.Enumeration.DeviceInformation.FindAllAsync(DeviceClass.AudioCapture)`

### 3.7 Model Service (Services/ModelService.cs)

**macOS approach:** `URLSession` + `URLSessionDownloadDelegate` with throttled progress, SHA256 verification, GGML header validation.

**Windows approach:**

```csharp
public class ModelService
{
    private readonly HttpClient _httpClient = new();
    private readonly string _modelsDirectory;

    public ModelService()
    {
        _modelsDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "SimpleTranscribe", "models");
        Directory.CreateDirectory(_modelsDirectory);
    }

    public async Task DownloadModelAsync(string modelId, IProgress<double> progress, CancellationToken ct)
    {
        var model = KnownModels.Get(modelId);
        using var response = await _httpClient.GetAsync(model.DownloadUrl, HttpCompletionOption.ResponseHeadersRead, ct);
        var totalBytes = response.Content.Headers.ContentLength ?? -1;

        await using var stream = await response.Content.ReadAsStreamAsync(ct);
        await using var fileStream = File.Create(Path.Combine(_modelsDirectory, $"{modelId}.bin"));

        var buffer = new byte[81920];
        long bytesRead = 0;
        int read;
        while ((read = await stream.ReadAsync(buffer, ct)) > 0)
        {
            await fileStream.WriteAsync(buffer.AsMemory(0, read), ct);
            bytesRead += read;
            if (totalBytes > 0) progress.Report((double)bytesRead / totalBytes);
        }

        // SHA256 verification
        VerifyFileIntegrity(Path.Combine(_modelsDirectory, $"{modelId}.bin"), model.Sha256);
    }
}
```

**Key considerations:**
- `HttpClient` with streaming download replaces `URLSessionDownloadTask`
- `IProgress<double>` + `CancellationToken` replace the delegate pattern
- Storage path: `%LOCALAPPDATA%\SimpleTranscribe\models\` (mirrors macOS `~/Library/Application Support/`)
- SHA256 via `System.Security.Cryptography.SHA256.Create()` with streaming reads
- GGML header validation: same 4-byte magic check, using `BinaryReader`

### 3.8 UI Layer (WinUI 3 XAML)

**macOS approach:** SwiftUI declarative views with `@State`, `@Binding`, `@Environment`.

**Windows approach:** WinUI 3 XAML with `x:Bind` and MVVM pattern.

#### MainWindow.xaml (maps to ContentView.swift)
```xml
<Window>
  <Grid RowDefinitions="Auto,Auto,Auto,*,Auto,Auto,Auto">
    <local:RecordingControlsPanel Row="0" />
    <Border Row="1" /> <!-- Divider -->
    <local:SettingsPanel Row="2" />
    <Border Row="3" /> <!-- Divider -->
    <local:TranscriptResultsPanel Row="4" />
    <!-- Status banners in rows 5-7 -->
  </Grid>
</Window>
```

#### Key UI mappings:
| macOS SwiftUI | WinUI 3 XAML |
|---|---|
| `VStack/HStack` | `StackPanel` (Orientation) |
| `Spacer()` | Grid column/row with `*` sizing |
| `Button.buttonStyle(.borderedProminent)` | `<Button Style="{StaticResource AccentButtonStyle}">` |
| `ProgressView()` | `<ProgressRing IsActive="True" />` |
| `TextEditor(text:)` | `<TextBox AcceptsReturn="True" TextWrapping="Wrap" />` |
| `Picker(selection:)` | `<ComboBox SelectedItem="{x:Bind ...}">` |
| `.sheet(isPresented:)` | `<ContentDialog>` or separate `Page` in `NavigationView` |
| `@State` / `@Binding` | `x:Bind` with `Mode=TwoWay` |
| `Color(NSColor.controlBackgroundColor)` | `{ThemeResource ControlFillColorDefaultBrush}` |
| `Image(systemName:)` | `<FontIcon Glyph="&#xE720;" />` (Segoe Fluent Icons) |

---

## 4. Implementation Todos (Ordered)

### Phase 1: Project Scaffolding
1. **scaffold-solution** — Create `simpletranscribe-win/` directory, `.sln`, `.csproj` with WinUI 3, NuGet references (CommunityToolkit.Mvvm, NAudio)
2. **setup-native-interop** — Build whisper.cpp as DLL, create `WhisperInterop.cs` with P/Invoke bindings, verify model loading works

### Phase 2: Core Engine (No UI)
3. **impl-model-info** — Port `ModelInfo.swift` → `ModelInfo.cs` and `KnownModels.swift` → `KnownModels.cs`
4. **impl-model-service** — Port `ModelService.swift` → `ModelService.cs` (download with progress, SHA256 verify, GGML validation, delete)
5. **impl-audio-manager** — Port `AudioManager.swift` → `AudioManager.cs` using NAudio (device enumeration, 16kHz capture, float[] buffers)
6. **impl-transcription-mgr** — Port `TranscriptionManager.swift` → `TranscriptionManager.cs` (load model, accumulate audio, run whisper inference)
7. **impl-sound-manager** — Port `SoundManager.swift` → `SoundManager.cs` with bundled .wav files

### Phase 3: Platform Services
8. **impl-hotkey-manager** — Port `HotKeyManager.swift` → `HotKeyManager.cs` using low-level keyboard hook for press-to-talk
9. **impl-paste-service** — Port `PasteService.swift` → `PasteService.cs` using Clipboard + SendInput

### Phase 4: UI
10. **impl-main-viewmodel** — Port `AppModel.swift` → `MainViewModel.cs` with CommunityToolkit.Mvvm, settings persistence
11. **impl-main-window** — Build `MainWindow.xaml` layout matching macOS ContentView structure
12. **impl-recording-controls** — Port `RecordingControlsView.swift` → `RecordingControlsPanel.xaml`
13. **impl-settings-panel** — Port `SettingsAreaView.swift` → `SettingsPanel.xaml` (mic picker, model picker, language picker)
14. **impl-transcript-results** — Port `TranscriptResultsView.swift` → `TranscriptResultsPanel.xaml`
15. **impl-model-download-ui** — Port `ModelDownloadView.swift` → `ModelDownloadPage.xaml` (model list, progress, download/delete/select)
16. **impl-status-banners** — Port model status, error, and accessibility banners from ContentView

### Phase 5: Integration & Polish
17. **wire-recording-flow** — Connect AudioManager → TranscriptionManager → ViewModel → UI (record, stop, transcribe, display)
18. **wire-hotkey-flow** — Connect HotKeyManager → recording toggle → auto-paste on release
19. **wire-model-flow** — Connect ModelService → model selection → TranscriptionManager.LoadModel
20. **add-app-icon** — Create Windows .ico from app design
21. **impl-installer** — Create standalone installer using WiX Toolset or Inno Setup

### Phase 6: Testing & Hardening
22. **unit-tests** — Test TranscriptionManager, ModelService, AudioManager (mock interfaces)
23. **integration-test** — End-to-end: download model → record → transcribe → verify text output
24. **perf-test** — Benchmark whisper inference on Windows vs macOS for equivalent hardware

---

## 5. NuGet Dependencies

| Package | Purpose | Version |
|---|---|---|
| `Microsoft.WindowsAppSDK` | WinUI 3 framework | Latest stable (1.5+) |
| `CommunityToolkit.Mvvm` | MVVM source generators (`ObservableObject`, `RelayCommand`) | 8.x |
| `CommunityToolkit.WinUI.UI` | UI helpers, converters | 8.x |
| `NAudio` | Audio capture (WASAPI), format conversion | 2.x |
| `System.Text.Json` | JSON serialization (built-in but explicit for clarity) | Built-in |

**Native dependency:** `whisper.dll` built from `ggerganov/whisper.cpp` (not a NuGet — manual build or CI artifact).

---

## 6. Key Technical Decisions & Risks

### 6.1 whisper.cpp DLL Build
- **Risk:** Cross-compiling whisper.cpp for Windows ARM64 may have SIMD issues
- **Mitigation:** Build on actual ARM64 hardware or use GitHub Actions with ARM64 runners
- **Alternative fallback:** `Whisper.net` NuGet wraps whisper.cpp and ships pre-built binaries for win-x64/arm64

### 6.2 Audio Resampling
- **Risk:** Not all microphones output at 16kHz; need resampling
- **Mitigation:** NAudio's `MediaFoundationResampler` or `WdlResamplingSampleProvider` handles this; test with USB mics, Bluetooth headsets, and built-in mics

### 6.3 Global Hotkey Conflicts
- **Risk:** Low-level keyboard hooks can conflict with other apps or be blocked by antivirus
- **Mitigation:** Make hotkey configurable (default `Ctrl+Space`); use `RegisterHotKey` as primary, fall back to hook only if needed

### 6.4 SendInput and UIPI
- **Risk:** `SendInput` won't work for elevated (admin) target windows due to User Interface Privilege Isolation
- **Mitigation:** Document this limitation; text is always on clipboard as fallback (same as macOS when all paste methods fail)

### 6.5 WinUI 3 Clipboard
- **Risk:** WinUI 3's `Clipboard` API requires the calling thread to have a `CoreWindow` or `AppWindow`
- **Mitigation:** Use `Windows.ApplicationModel.DataTransfer.Clipboard` on the UI thread; fallback to Win32 `OpenClipboard`/`SetClipboardData` P/Invoke if needed

---

## 7. Feature Parity Checklist

| Feature | macOS | Windows Plan |
|---|---|---|
| Record audio from microphone | ✅ AVAudioEngine | ✅ NAudio WasapiCapture |
| Select input device | ✅ AVCaptureDevice.DiscoverySession | ✅ MMDeviceEnumerator |
| Local transcription (whisper.cpp) | ✅ SwiftWhisper | ✅ whisper.cpp P/Invoke |
| Download/manage multiple models | ✅ URLSession delegate | ✅ HttpClient + IProgress |
| SHA256 model verification | ✅ CryptoKit | ✅ System.Security.Cryptography |
| GGML header validation | ✅ FileHandle 4-byte read | ✅ BinaryReader 4-byte read |
| Select language (6 + auto) | ✅ Picker | ✅ ComboBox |
| Select model | ✅ Picker | ✅ ComboBox |
| Press-to-talk global hotkey | ✅ NSEvent monitors (fn+ctrl) | ✅ Low-level keyboard hook (Ctrl+Space) |
| Auto-paste at cursor | ✅ CGEvent/AppleScript/osascript | ✅ SendInput (Ctrl+V) |
| Copy to clipboard | ✅ NSPasteboard | ✅ Clipboard API |
| Sound feedback | ✅ NSSound (Tink/Glass/Basso) | ✅ MediaPlayer + bundled .wav |
| Settings persistence | ✅ UserDefaults | ✅ LocalSettings or JSON file |
| Model download progress | ✅ URLSessionDownloadDelegate | ✅ IProgress<double> |
| Error display banners | ✅ SwiftUI conditional views | ✅ XAML InfoBar / conditional panels |
| 30-minute max recording | ✅ maxSamples constant | ✅ Same constant |
| Thread-safe audio accumulation | ✅ NSLock | ✅ SemaphoreSlim |

---

## 8. Build & CI Considerations

- **IDE:** Visual Studio 2022 17.8+ (required for WinUI 3 + .NET 8)
- **.NET version:** .NET 8 (LTS) or .NET 9
- **Windows SDK:** 10.0.22621.0 (Windows 11 22H2)
- **whisper.cpp build:** CMake + MSVC or Ninja on GitHub Actions
- **Installer:** WiX Toolset v4 for `.msi` or Inno Setup for `.exe` installer
- **CI:** GitHub Actions with `windows-latest` runner; build whisper.dll → build C# project → run tests → create installer

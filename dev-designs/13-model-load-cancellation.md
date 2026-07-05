# Dev Design #13 — Model Load Cancellation

## Problem
Once a Whisper or Parakeet model starts loading, there is no way to cancel the operation. On slow machines, Whisper Large can take 20-30 seconds to load into memory. The UI shows a loading banner with no Cancel button. If the user changes their mind (e.g., wants to switch to a smaller model) they must wait or force-quit the app.

---

## Goals
- Show a **Cancel** button alongside the loading banner.
- Cancelling aborts the in-flight load as early as safely possible.
- After cancellation, the model state returns to **unloaded** and the UI returns to the model picker.
- whisper.cpp does not expose a mid-load cancellation hook, so cancellation primarily covers the **Swift/C# Task scheduling layer** and the **post-load model swap step**.

---

## Mac Design (Swift)

### AppModel — loading task + cancellation

```swift
// AppModel.swift
@Published var isLoadingModel: Bool = false

// NEW: hold a reference to the current loading task
@ObservationIgnored private var modelLoadTask: Task<Void, Never>?

func loadSelectedModel() {
    modelLoadTask?.cancel()          // cancel any previous in-flight load
    isLoadingModel = true
    loadError = nil

    modelLoadTask = Task {
        do {
            try await transcriptionManager.loadModel(selectedModel,
                                                     cancellationToken: Task.isCancelled)
            guard !Task.isCancelled else {
                await MainActor.run {
                    isLoadingModel = false
                }
                return
            }
            await MainActor.run {
                isLoadingModel = false
                currentModel = selectedModel
                logger.info("Model loaded: \(selectedModel.name)")
            }
        } catch is CancellationError {
            await MainActor.run { isLoadingModel = false }
        } catch {
            await MainActor.run {
                isLoadingModel = false
                loadError = error.localizedDescription
            }
        }
    }
}

func cancelModelLoad() {
    modelLoadTask?.cancel()
    modelLoadTask = nil
    isLoadingModel = false
    // transcriptionManager is still in undefined state — reset it
    transcriptionManager.unloadModel()
}
```

### TranscriptionManager — structured load with cooperative cancellation

The underlying `whisper_init_from_file` and `SherpaOnnxCreateOnlineRecognizer` are C calls and cannot be interrupted once started. The strategy is to:

1. **Check cancellation before starting the blocking C call.**
2. **Run the C call on a detached background thread** (`Task.detached` with `.userInitiated` priority).
3. **Check cancellation immediately after the C call returns**, before committing the model to the state.

```swift
// TranscriptionManager.swift
func loadModel(_ model: KnownModel,
               cancellationToken: @escaping @Sendable () -> Bool) async throws {

    // Pre-call cooperative check
    try Task.checkCancellation()

    switch model.type {
    case .whisper:
        let modelPath = modelsDirectory.appendingPathComponent(model.filename).path
        let ctx = try await Task.detached(priority: .userInitiated) {
            // whisper.cpp blocking call
            whisper_init_from_file(modelPath)
        }.value

        // Post-call cooperative check — discard the loaded model if cancelled
        try Task.checkCancellation()

        guard let ctx else { throw ModelError.failedToLoad }
        self.whisperContext = ctx

    case .parakeet:
        let config = buildParakeetConfig(model)
        let recognizer = try await Task.detached(priority: .userInitiated) {
            SherpaOnnxCreateOnlineRecognizer(&config)
        }.value

        try Task.checkCancellation()

        guard let recognizer else { throw ModelError.failedToLoad }
        self.parakeetRecognizer = recognizer
    }
}

func unloadModel() {
    if let ctx = whisperContext {
        whisper_free(ctx)
        whisperContext = nil
    }
    if let r = parakeetRecognizer {
        SherpaOnnxDestroyOnlineRecognizer(r)
        parakeetRecognizer = nil
    }
    currentModelType = nil
}
```

### ContentView — Cancel button in loading banner

```swift
// In the loading banner HStack:
if appModel.isLoadingModel {
    HStack {
        ProgressView().controlSize(.small)
        Text("Loading model…")
            .font(.caption)
            .foregroundStyle(.secondary)
        Spacer()
        Button("Cancel") {
            appModel.cancelModelLoad()
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .tint(.orange)
    }
    .padding(.horizontal)
    .padding(.vertical, 4)
}
```

---

## Windows Design (C#)

### MainViewModel — CancellationTokenSource

```csharp
// MainViewModel.cs
private CancellationTokenSource? _modelLoadCts;

[ObservableProperty] private bool _isLoadingModel;

public async Task LoadSelectedModelAsync()
{
    _modelLoadCts?.Cancel();
    _modelLoadCts?.Dispose();
    _modelLoadCts = new CancellationTokenSource();
    var ct = _modelLoadCts.Token;

    IsLoadingModel = true;
    LoadError = string.Empty;

    try
    {
        await _transcriptionManager.LoadModelAsync(SelectedModel, ct);

        if (ct.IsCancellationRequested) return;

        CurrentModel = SelectedModel;
    }
    catch (OperationCanceledException)
    {
        // No-op — user cancelled
    }
    catch (Exception ex)
    {
        LoadError = ex.Message;
    }
    finally
    {
        IsLoadingModel = false;
    }
}

[RelayCommand]
private void CancelModelLoad()
{
    _modelLoadCts?.Cancel();
    IsLoadingModel = false;
    _transcriptionManager.UnloadModel();
}
```

### TranscriptionManager — cooperative cancellation

```csharp
// TranscriptionManager.cs
public async Task LoadModelAsync(KnownModel model, CancellationToken ct = default)
{
    ct.ThrowIfCancellationRequested();

    if (model.Type == ModelType.Whisper)
    {
        string modelPath = Path.Combine(_modelsDir, model.Filename);

        // Run blocking P/Invoke on a thread-pool thread
        var ctx = await Task.Run(() => WhisperNative.InitFromFile(modelPath), ct);

        ct.ThrowIfCancellationRequested();  // discard if cancelled after load

        if (ctx == IntPtr.Zero)
            throw new InvalidOperationException("Failed to load Whisper model.");

        UnloadModel();  // free any previous model
        _whisperContext = ctx;
    }
    else if (model.Type == ModelType.Parakeet)
    {
        var config = BuildParakeetConfig(model);

        var recognizer = await Task.Run(() =>
            SherpaOnnxSharp.SherpaOnnxCreateOnlineRecognizer(ref config), ct);

        ct.ThrowIfCancellationRequested();

        if (recognizer == IntPtr.Zero)
            throw new InvalidOperationException("Failed to load Parakeet model.");

        UnloadModel();
        _parakeetRecognizer = recognizer;
    }
}

public void UnloadModel()
{
    if (_whisperContext != IntPtr.Zero)
    {
        WhisperNative.Free(_whisperContext);
        _whisperContext = IntPtr.Zero;
    }
    if (_parakeetRecognizer != IntPtr.Zero)
    {
        SherpaOnnxSharp.SherpaOnnxDestroyOnlineRecognizer(_parakeetRecognizer);
        _parakeetRecognizer = IntPtr.Zero;
    }
    _currentModelType = null;
}
```

### MainWindow.xaml — Cancel button

```xml
<!-- Loading banner StackPanel -->
<StackPanel Orientation="Horizontal"
            Visibility="{x:Bind _vm.IsLoadingModel, Converter={StaticResource BoolToVisibility}, Mode=OneWay}">
    <ProgressRing IsActive="True" Width="16" Height="16" Margin="0,0,8,0"/>
    <TextBlock Text="Loading model…"
               VerticalAlignment="Center"
               Style="{StaticResource CaptionTextBlockStyle}"/>
    <Button Content="Cancel"
            Command="{x:Bind _vm.CancelModelLoadCommand}"
            Margin="12,0,0,0"
            Style="{StaticResource AccentButtonStyle}"/>
</StackPanel>
```

---

## Limitations and Known Trade-offs

| Limitation | Explanation |
|------------|-------------|
| whisper.cpp `whisper_init_from_file` is not interruptible | The C function will still run to completion on its thread-pool thread. Cancellation takes effect *after* it returns by discarding the result and calling `whisper_free`. Memory is allocated then immediately freed. |
| SherpaOnnxCreateOnlineRecognizer is not interruptible | Same as above. |
| Model load time is not reduced by cancelling | The user still has to wait for the C call to finish before the memory is freed. The UX improvement is that the app returns to a usable state faster. |
| Rapid model switching | If the user clicks Cancel and then immediately loads again, `_modelLoadCts` is cancelled and recreated. The old thread-pool task finishes and discards its result; the new task starts fresh. This is safe. |

---

## Acceptance Criteria
- [ ] A **Cancel** button is visible in the loading banner while a model is loading.
- [ ] Clicking Cancel returns the UI to the model picker (unloaded state) within 500 ms of the C call returning.
- [ ] After cancellation, the previously loaded model (if any) is correctly unloaded and memory freed.
- [ ] Starting a new load while one is in progress cancels the previous load.
- [ ] If whisper.cpp or sherpa-onnx returns an error after cancellation, the error is silently swallowed (not shown to user).
- [ ] No memory leaks: every allocated model context is freed on cancel.
- [ ] Cancelling during Parakeet's multi-step load (4 ONNX files) cleans up any partially-loaded state.

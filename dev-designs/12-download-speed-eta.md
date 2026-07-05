# Dev Design #12 — Download Speed & ETA

## Problem
`ModelDownloadView` (Mac) and `ModelDownloadPage` (Windows) show a progress bar and a percentage but provide no indication of download speed or estimated time remaining. For large models (Whisper Large ≈ 1.5 GB, Parakeet ≈ 220 MB) this leaves the user with no sense of progress quality.

---

## Goals
- Display download speed (MB/s) and estimated time remaining (minutes / seconds) below the progress bar.
- Compute speed over a rolling 5-second window to avoid spikes.
- Update the display at most once per second.
- Keep implementation self-contained in `ModelService` (both platforms) so any future download UI benefits automatically.

---

## Mac Design (Swift)

### DownloadProgress struct

```swift
// New file: DownloadProgress.swift
struct DownloadProgress {
    let fraction: Double          // 0.0 – 1.0
    let bytesPerSecond: Double    // rolling average
    let totalBytes: Int64
    let receivedBytes: Int64

    var etaSeconds: Double? {
        guard bytesPerSecond > 0 else { return nil }
        let remaining = Double(totalBytes - receivedBytes)
        return remaining / bytesPerSecond
    }

    var speedString: String {
        let mbs = bytesPerSecond / 1_048_576
        if mbs >= 1 { return String(format: "%.1f MB/s", mbs) }
        let kbs = bytesPerSecond / 1_024
        return String(format: "%.0f KB/s", kbs)
    }

    var etaString: String {
        guard let eta = etaSeconds else { return "" }
        if eta < 60  { return String(format: "~%.0fs remaining", eta) }
        let mins = eta / 60
        if eta < 3600 { return String(format: "~%.0fmin remaining", mins) }
        return String(format: "~%.1fh remaining", eta / 3600)
    }
}
```

### Rolling-window speed tracker

```swift
// Inside ModelService.swift
private struct SpeedSample { let timestamp: Date; let bytes: Int64 }

private var speedSamples: [SpeedSample] = []
private let speedWindowSeconds: TimeInterval = 5.0

private func computeSpeed(latestBytes: Int64) -> Double {
    let now = Date()
    speedSamples.append(SpeedSample(timestamp: now, bytes: latestBytes))
    // Prune samples older than the window
    speedSamples.removeAll { now.timeIntervalSince($0.timestamp) > speedWindowSeconds }
    guard speedSamples.count >= 2,
          let first = speedSamples.first else { return 0 }
    let elapsed = now.timeIntervalSince(first.timestamp)
    guard elapsed > 0 else { return 0 }
    return Double(latestBytes - first.bytes) / elapsed
}
```

### Publish progress from downloadModel

Change the `downloadModel` progress handler to emit `DownloadProgress`:

```swift
// In ModelService.swift — current signature
func downloadModel(_ model: KnownModel, progress: @escaping (Double) -> Void) async throws

// New signature
func downloadModel(_ model: KnownModel,
                   progress: @escaping (DownloadProgress) -> Void) async throws
```

Inside the URL session bytes loop:

```swift
var received: Int64 = 0
var lastUpdate: Date = .distantPast

for try await bytes in session.bytes(for: request) {
    received += Int64(bytes.count)
    // ... write to file ...

    let now = Date()
    if now.timeIntervalSince(lastUpdate) >= 1.0 {
        lastUpdate = now
        let speed = computeSpeed(latestBytes: received)
        let dp = DownloadProgress(fraction: Double(received) / Double(total),
                                  bytesPerSecond: speed,
                                  totalBytes: total,
                                  receivedBytes: received)
        await MainActor.run { progress(dp) }
    }
}
```

### AppModel — store DownloadProgress

```swift
// AppModel.swift
var downloadProgress: DownloadProgress = DownloadProgress(fraction: 0, bytesPerSecond: 0,
                                                           totalBytes: 0, receivedBytes: 0)
```

Update the call site:

```swift
await modelService.downloadModel(model) { [weak self] dp in
    self?.downloadProgress = dp
}
```

### ModelDownloadView — show speed + ETA

Below the existing `ProgressView`:

```swift
if appModel.downloadProgress.fraction > 0 {
    HStack {
        Text(appModel.downloadProgress.speedString)
            .font(.caption)
            .foregroundStyle(.secondary)
        Spacer()
        Text(appModel.downloadProgress.etaString)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding(.horizontal)
}
```

---

## Windows Design (C#)

### DownloadProgress model

```csharp
// DownloadProgress.cs
public record DownloadProgress(
    double Fraction,
    double BytesPerSecond,
    long TotalBytes,
    long ReceivedBytes)
{
    public double? EtaSeconds =>
        BytesPerSecond > 0
            ? (TotalBytes - ReceivedBytes) / BytesPerSecond
            : (double?)null;

    public string SpeedString
    {
        get
        {
            double mbs = BytesPerSecond / 1_048_576;
            if (mbs >= 1) return $"{mbs:F1} MB/s";
            double kbs = BytesPerSecond / 1_024;
            return $"{kbs:F0} KB/s";
        }
    }

    public string EtaString
    {
        get
        {
            if (EtaSeconds is not { } eta) return "";
            if (eta < 60) return $"~{eta:F0}s remaining";
            if (eta < 3600) return $"~{eta / 60:F0}min remaining";
            return $"~{eta / 3600:F1}h remaining";
        }
    }
}
```

### Rolling-window tracker

```csharp
// Inside ModelService.cs
private record SpeedSample(DateTime Timestamp, long Bytes);
private readonly List<SpeedSample> _speedSamples = new();
private const double SpeedWindowSeconds = 5.0;

private double ComputeSpeed(long latestBytes)
{
    var now = DateTime.UtcNow;
    _speedSamples.Add(new SpeedSample(now, latestBytes));
    _speedSamples.RemoveAll(s => (now - s.Timestamp).TotalSeconds > SpeedWindowSeconds);
    if (_speedSamples.Count < 2) return 0;
    var first = _speedSamples[0];
    var elapsed = (now - first.Timestamp).TotalSeconds;
    return elapsed > 0 ? (latestBytes - first.Bytes) / elapsed : 0;
}
```

### Updated DownloadModelAsync

```csharp
public async Task DownloadModelAsync(
    KnownModel model,
    IProgress<DownloadProgress> progress,
    CancellationToken ct = default)
{
    using var response = await _httpClient.GetAsync(model.DownloadUrl,
        HttpCompletionOption.ResponseHeadersRead, ct);
    response.EnsureSuccessStatusCode();
    var totalBytes = response.Content.Headers.ContentLength ?? 0L;
    long received = 0;
    var lastUpdate = DateTime.MinValue;

    await using var stream = await response.Content.ReadAsStreamAsync(ct);
    var buffer = new byte[81920];
    int read;
    while ((read = await stream.ReadAsync(buffer, ct)) > 0)
    {
        received += read;
        // ... write to temp file ...

        var now = DateTime.UtcNow;
        if ((now - lastUpdate).TotalSeconds >= 1.0)
        {
            lastUpdate = now;
            var speed = ComputeSpeed(received);
            progress.Report(new DownloadProgress(
                Fraction: totalBytes > 0 ? (double)received / totalBytes : 0,
                BytesPerSecond: speed,
                TotalBytes: totalBytes,
                ReceivedBytes: received));
        }
    }
}
```

### MainViewModel

```csharp
[ObservableProperty] private DownloadProgress _downloadProgress = new(0, 0, 0, 0);
```

Update the call site to use the new `IProgress<DownloadProgress>`:

```csharp
var progressReporter = new Progress<DownloadProgress>(dp =>
    DownloadProgress = dp);
await _modelService.DownloadModelAsync(model, progressReporter, _downloadCts.Token);
```

### ModelDownloadPage.xaml

```xml
<StackPanel>
    <ProgressBar Value="{x:Bind _vm.DownloadProgress.Fraction, Mode=OneWay}" Maximum="1"/>
    <Grid>
        <TextBlock Text="{x:Bind _vm.DownloadProgress.SpeedString, Mode=OneWay}"
                   HorizontalAlignment="Left"
                   Style="{StaticResource CaptionTextBlockStyle}"
                   Foreground="{ThemeResource SystemFillColorCautionBrush}"/>
        <TextBlock Text="{x:Bind _vm.DownloadProgress.EtaString, Mode=OneWay}"
                   HorizontalAlignment="Right"
                   Style="{StaticResource CaptionTextBlockStyle}"
                   Foreground="{ThemeResource SystemFillColorCautionBrush}"/>
    </Grid>
</StackPanel>
```

---

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Server doesn't send `Content-Length` | `totalBytes = 0`; ETA becomes `nil`/`null`, only speed is shown |
| Speed drops to 0 (stalled) | ETA string shows nothing; speed shows 0 KB/s |
| Parakeet multi-file download | Tracker is reset between files; progress fraction is cumulative across all 4 files |
| Download cancelled mid-way | Progress resets to 0; existing cancel button/`CancellationToken` handles this (see Design #13) |

---

## Acceptance Criteria
- [ ] Download speed displays in MB/s or KB/s (switches automatically based on magnitude).
- [ ] ETA shows seconds, minutes, or hours as appropriate.
- [ ] Speed is computed over a rolling 5-second window.
- [ ] Display updates at most once per second.
- [ ] When `Content-Length` is absent, only speed is shown (no ETA).
- [ ] Parakeet's multi-file download reports cumulative progress correctly.
- [ ] Progress resets cleanly when a download is cancelled or a new one starts.

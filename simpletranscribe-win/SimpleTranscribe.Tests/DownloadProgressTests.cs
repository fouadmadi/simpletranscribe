using Xunit;
using SimpleTranscribe.Models;

namespace SimpleTranscribe.Tests;

public class DownloadProgressTests
{
    // --- SpeedString ---

    [Fact]
    public void SpeedString_MegabytesPerSecond_WhenAboveThreshold()
    {
        var progress = new DownloadProgress(0.5, 2_097_152, 100_000_000, 50_000_000); // 2 MB/s
        Assert.Equal("2.0 MB/s", progress.SpeedString);
    }

    [Fact]
    public void SpeedString_KilobytesPerSecond_WhenBelowThreshold()
    {
        var progress = new DownloadProgress(0.1, 512_000, 100_000_000, 10_000_000); // 500 KB/s
        Assert.Equal("500 KB/s", progress.SpeedString);
    }

    [Fact]
    public void SpeedString_ZeroSpeed_ShowsZeroKB()
    {
        var progress = new DownloadProgress(0, 0, 100_000_000, 0);
        Assert.Equal("0 KB/s", progress.SpeedString);
    }

    [Fact]
    public void SpeedString_ExactlyOneMB_ShowsMB()
    {
        var progress = new DownloadProgress(0.5, 1_048_576, 100_000_000, 50_000_000); // exactly 1 MB/s
        Assert.Equal("1.0 MB/s", progress.SpeedString);
    }

    // --- EtaSeconds ---

    [Fact]
    public void EtaSeconds_CalculatesCorrectly()
    {
        // 100MB total, 50MB received, 10MB/s => 5 seconds remaining
        var progress = new DownloadProgress(0.5, 10_485_760, 104_857_600, 52_428_800);
        Assert.NotNull(progress.EtaSeconds);
        Assert.Equal(5.0, progress.EtaSeconds!.Value, 0.1);
    }

    [Fact]
    public void EtaSeconds_ReturnsNull_WhenZeroSpeed()
    {
        var progress = new DownloadProgress(0.5, 0, 100_000_000, 50_000_000);
        Assert.Null(progress.EtaSeconds);
    }

    [Fact]
    public void EtaSeconds_ReturnsNull_WhenZeroTotalBytes()
    {
        var progress = new DownloadProgress(0, 1000, 0, 0);
        Assert.Null(progress.EtaSeconds);
    }

    // --- EtaString ---

    [Fact]
    public void EtaString_Seconds_WhenUnderOneMinute()
    {
        // 100MB total, 90MB done, 2MB/s => ~5s remaining
        var progress = new DownloadProgress(0.9, 2_097_152, 104_857_600, 94_371_840);
        Assert.Contains("s remaining", progress.EtaString);
        Assert.StartsWith("~", progress.EtaString);
    }

    [Fact]
    public void EtaString_Minutes_WhenOverOneMinute()
    {
        // 100MB total, 50MB done, 500KB/s => ~100s (~2min)
        var progress = new DownloadProgress(0.5, 512_000, 104_857_600, 52_428_800);
        Assert.Contains("min remaining", progress.EtaString);
    }

    [Fact]
    public void EtaString_Hours_WhenOverOneHour()
    {
        // 3GB total, 0 done, 500KB/s => ~6000s (~1.7h)
        var progress = new DownloadProgress(0, 512_000, 3_221_225_472, 0);
        Assert.Contains("h remaining", progress.EtaString);
    }

    [Fact]
    public void EtaString_Empty_WhenNoSpeed()
    {
        var progress = new DownloadProgress(0.5, 0, 100_000_000, 50_000_000);
        Assert.Equal("", progress.EtaString);
    }

    // --- Fraction ---

    [Fact]
    public void Fraction_IsZero_AtStart()
    {
        var progress = new DownloadProgress(0, 0, 100, 0);
        Assert.Equal(0, progress.Fraction);
    }

    [Fact]
    public void Fraction_IsOne_WhenComplete()
    {
        var progress = new DownloadProgress(1.0, 0, 100, 100);
        Assert.Equal(1.0, progress.Fraction);
    }
}

using Xunit;
using SimpleTranscribe.Models;

namespace SimpleTranscribe.Tests;

public class ModelInfoTests
{
    [Fact]
    public void FormattedSize_ReturnsCorrectFormat_ForMegabytes()
    {
        var model = new ModelInfo { Size = 77_704_715 };
        Assert.Contains("MB", model.FormattedSize);
    }

    [Fact]
    public void FormattedSize_ReturnsCorrectFormat_ForGigabytes()
    {
        var model = new ModelInfo { Size = 3_095_033_483 };
        Assert.Contains("GB", model.FormattedSize);
    }

    [Fact]
    public void IsAvailable_ReturnsFalse_WhenNotDownloaded()
    {
        var model = new ModelInfo { Status = ModelStatus.NotDownloaded };
        Assert.False(model.IsAvailable);
    }

    [Fact]
    public void IsAvailable_ReturnsFalse_WhenDownloadedButNoPath()
    {
        var model = new ModelInfo { Status = ModelStatus.Downloaded, DownloadedPath = null };
        Assert.False(model.IsAvailable);
    }

    [Fact]
    public void IsAvailable_ReturnsTrue_WhenDownloadedWithPath()
    {
        var model = new ModelInfo
        {
            Status = ModelStatus.Downloaded,
            DownloadedPath = @"C:\models\test.bin"
        };
        Assert.True(model.IsAvailable);
    }
}

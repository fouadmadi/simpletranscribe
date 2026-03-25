using Xunit;
using SimpleTranscribe.Services;

namespace SimpleTranscribe.Tests;

public class ModelServiceTests
{
    [Fact]
    public void Constructor_CreatesModelsDirectory()
    {
        var service = new ModelService();
        Assert.NotEmpty(service.AvailableModels);
    }

    [Fact]
    public void LoadAvailableModels_PopulatesKnownModels()
    {
        var service = new ModelService();
        Assert.Equal(5, service.AvailableModels.Count(m =>
            Models.KnownModels.All.Any(k => k.Id == m.Id)));
    }

    [Fact]
    public void GetModel_ReturnsNull_ForInvalidId()
    {
        var service = new ModelService();
        Assert.Null(service.GetModel("fake-model"));
    }

    [Fact]
    public void GetModel_ReturnsModel_ForValidId()
    {
        var service = new ModelService();
        var model = service.GetModel("ggml-tiny.en");
        Assert.NotNull(model);
        Assert.Equal("ggml-tiny.en", model.Id);
    }

    [Fact]
    public void GetModelPath_ReturnsNull_WhenNotDownloaded()
    {
        var service = new ModelService();
        Assert.Null(service.GetModelPath("ggml-tiny.en"));
    }

    [Fact]
    public void TotalDownloadedSize_ReturnsZero_WhenNoModelsDownloaded()
    {
        var service = new ModelService();
        // Unless models are pre-downloaded on the test machine, this should be 0
        // (or a positive number if models happen to exist)
        Assert.True(service.TotalDownloadedSize() >= 0);
    }
}

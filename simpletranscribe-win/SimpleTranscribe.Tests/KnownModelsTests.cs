using SimpleTranscribe.Models;

namespace SimpleTranscribe.Tests;

public class KnownModelsTests
{
    [Fact]
    public void All_Contains_FiveModels()
    {
        Assert.Equal(5, KnownModels.All.Count);
    }

    [Fact]
    public void All_Models_Have_NonEmpty_Fields()
    {
        foreach (var model in KnownModels.All)
        {
            Assert.False(string.IsNullOrEmpty(model.Id));
            Assert.False(string.IsNullOrEmpty(model.Name));
            Assert.False(string.IsNullOrEmpty(model.Description));
            Assert.True(model.Size > 0);
            Assert.NotNull(model.DownloadUrl);
            Assert.False(string.IsNullOrEmpty(model.Language));
            Assert.False(string.IsNullOrEmpty(model.Sha256));
        }
    }

    [Fact]
    public void Get_ReturnsModel_WhenIdExists()
    {
        var model = KnownModels.Get("ggml-tiny.en");
        Assert.NotNull(model);
        Assert.Equal("Tiny (English)", model.Name);
    }

    [Fact]
    public void Get_ReturnsNull_WhenIdNotFound()
    {
        var model = KnownModels.Get("nonexistent");
        Assert.Null(model);
    }

    [Theory]
    [InlineData("ggml-tiny.en")]
    [InlineData("ggml-base.en")]
    [InlineData("ggml-small.en")]
    [InlineData("ggml-medium.en")]
    [InlineData("ggml-large")]
    public void Get_ReturnsModel_ForAllKnownIds(string id)
    {
        var model = KnownModels.Get(id);
        Assert.NotNull(model);
        Assert.Equal(id, model.Id);
    }

    [Fact]
    public void Models_DownloadUrls_AreHuggingFace()
    {
        foreach (var model in KnownModels.All)
        {
            Assert.StartsWith("https://huggingface.co/", model.DownloadUrl.ToString());
        }
    }

    [Fact]
    public void Sha256_Hashes_Match_MacOS_Values()
    {
        // Verify the SHA256 hashes match the macOS KnownModels.swift exactly
        Assert.Equal("921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f",
            KnownModels.Get("ggml-tiny.en")!.Sha256);
        Assert.Equal("a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002",
            KnownModels.Get("ggml-base.en")!.Sha256);
    }
}

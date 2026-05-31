using Xunit;
using SimpleTranscribe.Models;

namespace SimpleTranscribe.Tests;

public class PostProcessorConfigTests
{
    [Fact]
    public void DefaultValues_AreCorrect()
    {
        var config = new PostProcessorConfig();
        Assert.True(config.CapitaliseSentences);
        Assert.False(config.RemoveFillersEnabled);
        Assert.False(config.NumberFormattingEnabled);
        Assert.Empty(config.CustomRules);
    }

    [Fact]
    public void Load_ReturnsDefault_WhenNoSetting()
    {
        var config = PostProcessorConfig.Load(_ => null);
        Assert.True(config.CapitaliseSentences);
        Assert.False(config.RemoveFillersEnabled);
    }

    [Fact]
    public void Load_ReturnsDefault_WhenEmptySetting()
    {
        var config = PostProcessorConfig.Load(_ => "");
        Assert.True(config.CapitaliseSentences);
    }

    [Fact]
    public void Load_ReturnsDefault_WhenInvalidJson()
    {
        var config = PostProcessorConfig.Load(_ => "not valid json {{{");
        Assert.True(config.CapitaliseSentences);
        Assert.Empty(config.CustomRules);
    }

    [Fact]
    public void Save_And_Load_RoundTrips()
    {
        var original = new PostProcessorConfig
        {
            CapitaliseSentences = false,
            RemoveFillersEnabled = true,
            NumberFormattingEnabled = true,
            CustomRules = new() { new() { Find = "test", Replace = "replaced" } }
        };

        string? savedJson = null;
        original.Save((key, value) => savedJson = value);

        Assert.NotNull(savedJson);

        var loaded = PostProcessorConfig.Load(key => savedJson);
        Assert.False(loaded.CapitaliseSentences);
        Assert.True(loaded.RemoveFillersEnabled);
        Assert.True(loaded.NumberFormattingEnabled);
        Assert.Single(loaded.CustomRules);
        Assert.Equal("test", loaded.CustomRules[0].Find);
        Assert.Equal("replaced", loaded.CustomRules[0].Replace);
    }

    [Fact]
    public void Load_HandlesPartialJson()
    {
        // JSON with only some fields set
        var json = """{"CapitaliseSentences":false}""";
        var config = PostProcessorConfig.Load(_ => json);
        Assert.False(config.CapitaliseSentences);
        Assert.False(config.RemoveFillersEnabled); // default
        Assert.Empty(config.CustomRules); // default
    }

    [Fact]
    public void CustomRule_DefaultValues()
    {
        var rule = new PostProcessorConfig.CustomRule();
        Assert.Equal("", rule.Find);
        Assert.Equal("", rule.Replace);
    }
}

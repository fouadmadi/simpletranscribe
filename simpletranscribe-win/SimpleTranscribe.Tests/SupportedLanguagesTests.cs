using SimpleTranscribe.Models;
using Xunit;

namespace SimpleTranscribe.Tests;

public class SupportedLanguagesTests
{
    [Fact]
    public void WhisperLanguageList_HasUniqueCodes()
    {
        var codes = SupportedLanguages.Whisper.Select(l => l.Code).ToList();
        Assert.Equal(codes.Count, codes.Distinct().Count());
    }

    [Theory]
    [InlineData("ggml-tiny.en")]
    [InlineData("ggml-base.en")]
    [InlineData("ggml-small.en")]
    [InlineData("ggml-medium.en")]
    public void EnglishOnlyWhisperModels_ExposeEnglishOnly(string modelId)
    {
        var languages = SupportedLanguages.Available(modelId);

        Assert.Collection(languages,
            language => Assert.Equal("en", language.Code));
    }

    [Fact]
    public void LargeWhisper_ExposesFullLanguageListIncludingAuto()
    {
        var languages = SupportedLanguages.Available("ggml-large");

        Assert.Equal(SupportedLanguages.Whisper.Count, languages.Count);
        Assert.Contains(languages, language => language.Code == "auto");
        Assert.Contains(languages, language => language.Code == "es");
    }

    [Fact]
    public void ParakeetV3_UsesModelSpecificSubsetPlusAuto()
    {
        var languages = SupportedLanguages.Available("parakeet-tdt-0.6b-v3");

        Assert.Contains(languages, language => language.Code == "auto");
        Assert.Contains(languages, language => language.Code == "fr");
        Assert.DoesNotContain(languages, language => language.Code == "ja");
    }
}

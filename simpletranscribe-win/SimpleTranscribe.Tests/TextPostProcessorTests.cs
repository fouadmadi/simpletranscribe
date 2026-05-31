using Xunit;
using SimpleTranscribe.Models;
using SimpleTranscribe.Services;

namespace SimpleTranscribe.Tests;

public class TextPostProcessorTests
{
    private static PostProcessorConfig DefaultConfig(
        bool capitalise = false,
        bool fillers = false,
        bool numbers = false) => new()
    {
        CapitaliseSentences = capitalise,
        RemoveFillersEnabled = fillers,
        NumberFormattingEnabled = numbers
    };

    // --- Capitalisation ---

    [Fact]
    public void CapitaliseSentences_CapitalisesFirstLetter()
    {
        var config = DefaultConfig(capitalise: true);
        var result = TextPostProcessor.Process("hello world", config);
        Assert.Equal("Hello world", result);
    }

    [Fact]
    public void CapitaliseSentences_CapitalisesAfterPeriod()
    {
        var config = DefaultConfig(capitalise: true);
        var result = TextPostProcessor.Process("hello. world", config);
        Assert.Equal("Hello. World", result);
    }

    [Fact]
    public void CapitaliseSentences_CapitalisesAfterExclamation()
    {
        var config = DefaultConfig(capitalise: true);
        var result = TextPostProcessor.Process("wow! great", config);
        Assert.Equal("Wow! Great", result);
    }

    [Fact]
    public void CapitaliseSentences_CapitalisesAfterQuestion()
    {
        var config = DefaultConfig(capitalise: true);
        var result = TextPostProcessor.Process("what? nothing", config);
        Assert.Equal("What? Nothing", result);
    }

    [Fact]
    public void CapitaliseSentences_CapitalisesStandaloneI()
    {
        var config = DefaultConfig(capitalise: true);
        var result = TextPostProcessor.Process("i think i am right", config);
        Assert.Equal("I think I am right", result);
    }

    [Fact]
    public void CapitaliseSentences_DoesNotAffectAlreadyCapitalised()
    {
        var config = DefaultConfig(capitalise: true);
        var result = TextPostProcessor.Process("Hello World", config);
        Assert.Equal("Hello World", result);
    }

    // --- Filler removal ---

    [Theory]
    [InlineData("um", "")]
    [InlineData("uh", "")]
    [InlineData("er", "")]
    [InlineData("ah", "")]
    [InlineData("like", "")]
    public void RemoveFillers_RemovesSingleFiller(string filler, string expected)
    {
        var config = DefaultConfig(fillers: true);
        var result = TextPostProcessor.Process(filler, config);
        Assert.Equal(expected, result);
    }

    [Fact]
    public void RemoveFillers_RemovesFromSentence()
    {
        var config = DefaultConfig(fillers: true);
        var result = TextPostProcessor.Process("I um think this is uh great", config);
        Assert.Equal("I think this is great", result);
    }

    [Fact]
    public void RemoveFillers_DoesNotRemoveWhenDisabled()
    {
        var config = DefaultConfig(fillers: false);
        var result = TextPostProcessor.Process("I um think", config);
        Assert.Equal("I um think", result);
    }

    // --- Number formatting ---

    [Theory]
    [InlineData("one", "1")]
    [InlineData("two", "2")]
    [InlineData("ten", "10")]
    [InlineData("twenty", "20")]
    [InlineData("one hundred", "100")]
    [InlineData("one thousand", "1000")]
    public void FormatNumbers_ConvertsWordToDigit(string input, string expected)
    {
        var config = DefaultConfig(numbers: true);
        var result = TextPostProcessor.Process(input, config);
        Assert.Equal(expected, result);
    }

    [Fact]
    public void FormatNumbers_ConvertsInSentence()
    {
        var config = DefaultConfig(numbers: true);
        var result = TextPostProcessor.Process("I have three cats", config);
        Assert.Equal("I have 3 cats", result);
    }

    [Fact]
    public void FormatNumbers_DoesNotConvertWhenDisabled()
    {
        var config = DefaultConfig(numbers: false);
        var result = TextPostProcessor.Process("I have three cats", config);
        Assert.Equal("I have three cats", result);
    }

    // --- Custom rules ---

    [Fact]
    public void CustomRules_ReplacesMatchingWord()
    {
        var config = DefaultConfig();
        config.CustomRules.Add(new PostProcessorConfig.CustomRule { Find = "gonna", Replace = "going to" });
        var result = TextPostProcessor.Process("I am gonna do it", config);
        Assert.Equal("I am going to do it", result);
    }

    [Fact]
    public void CustomRules_IsCaseInsensitive()
    {
        var config = DefaultConfig();
        config.CustomRules.Add(new PostProcessorConfig.CustomRule { Find = "btw", Replace = "by the way" });
        var result = TextPostProcessor.Process("BTW that is cool", config);
        Assert.Equal("by the way that is cool", result);
    }

    [Fact]
    public void CustomRules_SkipsEmptyFind()
    {
        var config = DefaultConfig();
        config.CustomRules.Add(new PostProcessorConfig.CustomRule { Find = "", Replace = "oops" });
        var result = TextPostProcessor.Process("hello world", config);
        Assert.Equal("hello world", result);
    }

    // --- Edge cases ---

    [Fact]
    public void Process_HandlesEmptyString()
    {
        var config = DefaultConfig(capitalise: true, fillers: true, numbers: true);
        var result = TextPostProcessor.Process("", config);
        Assert.Equal("", result);
    }

    [Fact]
    public void Process_HandlesNull()
    {
        var config = DefaultConfig(capitalise: true);
        var result = TextPostProcessor.Process(null!, config);
        Assert.Equal(null!, result);
    }

    [Fact]
    public void Process_AllOptionsEnabled()
    {
        var config = DefaultConfig(capitalise: true, fillers: true, numbers: true);
        var result = TextPostProcessor.Process("um i have like three cats", config);
        Assert.Equal("I have 3 cats", result);
    }
}

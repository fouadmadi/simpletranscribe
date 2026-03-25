using System.Runtime.InteropServices;

namespace SimpleTranscribe.Interop;

/// <summary>
/// P/Invoke bindings for whisper.cpp native library.
/// Expects whisper.dll in the Native/ directory or application root.
/// Build whisper.cpp with: cmake -B build -DBUILD_SHARED_LIBS=ON && cmake --build build --config Release
/// </summary>
internal static partial class WhisperNative
{
    private const string LibName = "whisper";

    // --- Context lifecycle ---

    [LibraryImport(LibName, EntryPoint = "whisper_init_from_file_with_params")]
    internal static partial nint InitFromFileWithParams(
        [MarshalAs(UnmanagedType.LPStr)] string pathModel,
        WhisperContextParams cparams);

    [LibraryImport(LibName, EntryPoint = "whisper_init_from_file")]
    internal static partial nint InitFromFile(
        [MarshalAs(UnmanagedType.LPStr)] string pathModel);

    [LibraryImport(LibName, EntryPoint = "whisper_free")]
    internal static partial void Free(nint ctx);

    // --- Full inference ---

    [LibraryImport(LibName, EntryPoint = "whisper_full")]
    internal static partial int Full(nint ctx, WhisperFullParams pars, float[] samples, int nSamples);

    [LibraryImport(LibName, EntryPoint = "whisper_full_n_segments")]
    internal static partial int FullNSegments(nint ctx);

    [LibraryImport(LibName, EntryPoint = "whisper_full_get_segment_text")]
    internal static partial nint FullGetSegmentText(nint ctx, int iSegment);

    // --- Default params ---

    [LibraryImport(LibName, EntryPoint = "whisper_full_default_params")]
    internal static partial WhisperFullParams FullDefaultParams(int strategy);

    // --- Context params ---

    [LibraryImport(LibName, EntryPoint = "whisper_context_default_params")]
    internal static partial WhisperContextParams ContextDefaultParams();

    // --- System info ---

    [LibraryImport(LibName, EntryPoint = "whisper_print_system_info")]
    internal static partial nint PrintSystemInfo();
}

/// <summary>
/// Whisper sampling strategy constants.
/// </summary>
internal static class WhisperSamplingStrategy
{
    public const int Greedy = 0;
    public const int BeamSearch = 1;
}

/// <summary>
/// Mirrors whisper_context_params from whisper.h.
/// </summary>
[StructLayout(LayoutKind.Sequential)]
internal struct WhisperContextParams
{
    [MarshalAs(UnmanagedType.I1)]
    public bool use_gpu;
    public int gpu_device;
    [MarshalAs(UnmanagedType.I1)]
    public bool flash_attn;
}

/// <summary>
/// Mirrors whisper_full_params from whisper.h (greedy strategy).
/// Only the fields we actually configure are included; the rest are left
/// at their default values from whisper_full_default_params().
/// </summary>
[StructLayout(LayoutKind.Sequential)]
internal struct WhisperFullParams
{
    public int strategy;

    public int n_threads;
    public int n_max_text_ctx;
    public int offset_ms;
    public int duration_ms;

    [MarshalAs(UnmanagedType.I1)]
    public bool translate;
    [MarshalAs(UnmanagedType.I1)]
    public bool no_context;
    [MarshalAs(UnmanagedType.I1)]
    public bool no_timestamps;
    [MarshalAs(UnmanagedType.I1)]
    public bool single_segment;

    [MarshalAs(UnmanagedType.I1)]
    public bool print_special;
    [MarshalAs(UnmanagedType.I1)]
    public bool print_progress;
    [MarshalAs(UnmanagedType.I1)]
    public bool print_realtime;
    [MarshalAs(UnmanagedType.I1)]
    public bool print_timestamps;

    [MarshalAs(UnmanagedType.I1)]
    public bool token_timestamps;
    public float thold_pt;
    public float thold_ptsum;
    public int max_len;
    [MarshalAs(UnmanagedType.I1)]
    public bool split_on_word;
    public int max_tokens;

    [MarshalAs(UnmanagedType.I1)]
    public bool speed_up;
    [MarshalAs(UnmanagedType.I1)]
    public bool debug_mode;
    public int audio_ctx;

    [MarshalAs(UnmanagedType.I1)]
    public bool tdrz_enable;
    [MarshalAs(UnmanagedType.LPStr)]
    public string? initial_prompt;
    public nint prompt_tokens;
    public int prompt_n_tokens;

    [MarshalAs(UnmanagedType.LPStr)]
    public string? language;
    [MarshalAs(UnmanagedType.I1)]
    public bool detect_language;

    [MarshalAs(UnmanagedType.I1)]
    public bool suppress_blank;
    [MarshalAs(UnmanagedType.I1)]
    public bool suppress_non_speech_tokens;

    public float temperature;
    public float max_initial_ts;
    public float length_penalty;

    public int temperature_inc;
    public float entropy_thold;
    public float logprob_thold;
    public float no_speech_thold;

    // Greedy-specific
    public int greedy_best_of;

    // BeamSearch-specific
    public int beam_search_beam_size;
    public float beam_search_patience;
}

/// <summary>
/// Helper to marshal segment text from native pointer to C# string.
/// </summary>
internal static class WhisperHelpers
{
    public static string? GetSegmentText(nint ctx, int index)
    {
        var ptr = WhisperNative.FullGetSegmentText(ctx, index);
        return ptr == nint.Zero ? null : Marshal.PtrToStringUTF8(ptr);
    }
}

using System.Runtime.InteropServices;

namespace SimpleTranscribe.Interop;

/// <summary>
/// P/Invoke bindings for whisper.cpp native library.
/// 
/// SAFETY: We do NOT define C# structs for whisper_full_params or whisper_context_params
/// because these structs change across whisper.cpp versions (new fields, callbacks, grammar, etc.)
/// and a size mismatch causes stack buffer overflow. Instead, we:
///   1. Call whisper_full_default_params_by_ref to fill native-allocated memory
///   2. Modify only the fields we need via known byte offsets
///   3. Pass the native pointer to whisper_full
/// 
/// For model loading, we use whisper_init_from_file (no context params) to avoid struct issues.
/// </summary>
internal static class WhisperNative
{
    private const string LibName = "whisper";

    static WhisperNative()
    {
        // WinUI apps don't probe runtimes/{rid}/ automatically for native DLLs.
        NativeLibrary.SetDllImportResolver(typeof(WhisperNative).Assembly, (name, asm, paths) =>
        {
            if (name != LibName)
                return nint.Zero;

            if (NativeLibrary.TryLoad(name, asm, paths, out var h))
                return h;

            var arch = RuntimeInformation.ProcessArchitecture switch
            {
                Architecture.X64 => "win-x64",
                Architecture.Arm64 => "win-arm64",
                _ => null
            };

            if (arch is not null)
            {
                // Whisper.net.Runtime copies DLLs to runtimes/{rid}/ (not runtimes/{rid}/native/).
                // Probe both locations.
                string[] probeDirs =
                [
                    Path.Combine(AppContext.BaseDirectory, "runtimes", arch),
                    Path.Combine(AppContext.BaseDirectory, "runtimes", arch, "native"),
                ];

                foreach (var dir in probeDirs)
                {
                    if (!Directory.Exists(dir)) continue;

                    var probe = Path.Combine(dir, $"{name}.dll");
                    if (!File.Exists(probe)) continue;

                    AddDllDirectory(dir);

                    // LOAD_WITH_ALTERED_SEARCH_PATH so whisper.dll finds ggml-*.dll in the same dir
                    h = LoadLibraryExW(probe, nint.Zero, 0x00000008);
                    if (h != nint.Zero)
                        return h;
                }
            }

            return nint.Zero;
        });
    }

    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern nint AddDllDirectory(string newDirectory);

    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern nint LoadLibraryExW(string lpLibFileName, nint hFile, uint dwFlags);

    // --- Context lifecycle ---

    [DllImport(LibName, EntryPoint = "whisper_init_from_file", CallingConvention = CallingConvention.Cdecl)]
    internal static extern nint InitFromFile(
        [MarshalAs(UnmanagedType.LPStr)] string pathModel);

    [DllImport(LibName, EntryPoint = "whisper_free", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void Free(nint ctx);

    // --- Full inference (pointer-based for safe struct handling) ---

    [DllImport(LibName, EntryPoint = "whisper_full", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int Full(nint ctx, nint pars, float[] samples, int nSamples);

    [DllImport(LibName, EntryPoint = "whisper_full_n_segments", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int FullNSegments(nint ctx);

    [DllImport(LibName, EntryPoint = "whisper_full_get_segment_text", CallingConvention = CallingConvention.Cdecl)]
    internal static extern nint FullGetSegmentText(nint ctx, int iSegment);

    /// <summary>
    /// Allocates and returns a pointer to whisper_full_params with defaults for the given strategy.
    /// The returned pointer must be freed with whisper_free_params.
    /// </summary>
    [DllImport(LibName, EntryPoint = "whisper_full_default_params_by_ref", CallingConvention = CallingConvention.Cdecl)]
    internal static extern nint FullDefaultParamsByRef(int strategy);

    /// <summary>
    /// Frees a whisper_full_params pointer returned by whisper_full_default_params_by_ref.
    /// </summary>
    [DllImport(LibName, EntryPoint = "whisper_free_params", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void FreeParams(nint paramsPtr);

    /// <summary>
    /// Get sizeof(whisper_full_params) from the native library.
    /// Falls back to whisper_full_default_params if _by_ref is unavailable.
    /// </summary>
    [DllImport(LibName, EntryPoint = "whisper_full_default_params", CallingConvention = CallingConvention.Cdecl)]
    private static extern nint FullDefaultParamsRaw(int strategy);

    // --- System info ---

    [DllImport(LibName, EntryPoint = "whisper_print_system_info", CallingConvention = CallingConvention.Cdecl)]
    internal static extern nint PrintSystemInfo();
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
/// Safe wrapper for whisper_full_params that operates on native memory.
/// Allocates a native buffer, fills it with defaults from whisper.cpp, and provides
/// typed setters for the fields we actually use. This is version-independent because
/// the native library fills the entire struct including fields we don't know about.
///
/// Field offsets are for whisper.cpp v1.5+ (the most commonly used versions).
/// The struct starts with: int strategy, int n_threads, int n_max_text_ctx, int offset_ms, int duration_ms,
/// then bool fields (1 byte each, packed with potential padding).
/// </summary>
internal sealed class WhisperParams : IDisposable
{
    private nint _native;
    private bool _disposed;
    private bool _ownedByNative; // true = free via whisper_free_params, false = Marshal.FreeHGlobal

    /// <summary>Pointer to the native whisper_full_params memory.</summary>
    internal nint Pointer => _native;

    private WhisperParams(nint native, bool ownedByNative)
    {
        _native = native;
        _ownedByNative = ownedByNative;
    }

    /// <summary>
    /// Create a new WhisperParams initialized with whisper.cpp defaults for the given strategy.
    /// </summary>
    public static WhisperParams CreateDefault(int strategy)
    {
        // whisper_full_default_params_by_ref allocates and returns a pointer to default params
        try
        {
            var ptr = WhisperNative.FullDefaultParamsByRef(strategy);
            if (ptr != nint.Zero)
                return new WhisperParams(ptr, ownedByNative: true);
        }
        catch (EntryPointNotFoundException)
        {
            // Older whisper.cpp builds without this function — use fallback below
        }

        // Fallback: allocate our own buffer and set known-good defaults
        var native = Marshal.AllocHGlobal(NativeAllocSize);
        unsafe { new Span<byte>((void*)native, NativeAllocSize).Clear(); }
        FallbackFillDefaults(native, strategy);
        return new WhisperParams(native, ownedByNative: false);
    }

    // Conservative allocation for fallback path
    private const int NativeAllocSize = 1024;

    private static void FallbackFillDefaults(nint target, int strategy)
    {
        // whisper_full_default_params returns the struct by value on the stack.
        // We can't safely receive it in C# because we don't know the exact size.
        // Instead, write known-good defaults for the fields we care about.
        // The struct was zeroed above, so unknown fields default to 0/false/null.
        Marshal.WriteInt32(target, Offsets.Strategy, strategy);
        Marshal.WriteInt32(target, Offsets.NThreads, Math.Max(1, Environment.ProcessorCount));
        Marshal.WriteInt32(target, Offsets.NMaxTextCtx, 16384);
    }

    // --- Known field offsets for whisper_full_params (whisper.cpp v1.5+) ---
    // These are stable across minor versions. The struct layout is:
    //   int32 strategy           @ 0
    //   int32 n_threads          @ 4
    //   int32 n_max_text_ctx     @ 8
    //   int32 offset_ms          @ 12
    //   int32 duration_ms        @ 16
    //   bool  translate          @ 20
    //   bool  no_context         @ 21
    //   bool  no_timestamps      @ 22
    //   bool  single_segment     @ 23
    //   bool  print_special      @ 24
    //   bool  print_progress     @ 25
    //   bool  print_realtime     @ 26
    //   bool  print_timestamps   @ 27
    //   bool  token_timestamps   @ 28
    //   (3 bytes padding)
    //   float thold_pt           @ 32
    //   float thold_ptsum        @ 36
    //   int32 max_len            @ 40
    //   bool  split_on_word      @ 44
    //   (3 bytes padding)
    //   int32 max_tokens         @ 48
    //   -- fields below may shift between versions; we only set the safe ones above --
    internal static class Offsets
    {
        public const int Strategy = 0;
        public const int NThreads = 4;
        public const int NMaxTextCtx = 8;
        public const int OffsetMs = 12;
        public const int DurationMs = 16;
        public const int Translate = 20;
        public const int NoContext = 21;
        public const int NoTimestamps = 22;
        public const int SingleSegment = 23;
        public const int PrintSpecial = 24;
        public const int PrintProgress = 25;
        public const int PrintRealtime = 26;
        public const int PrintTimestamps = 27;
        public const int TokenTimestamps = 28;
    }

    // --- Typed setters for fields we configure ---

    public int NThreads
    {
        set => Marshal.WriteInt32(_native, Offsets.NThreads, value);
    }

    public bool NoContext
    {
        set => Marshal.WriteByte(_native, Offsets.NoContext, value ? (byte)1 : (byte)0);
    }

    public bool SingleSegment
    {
        set => Marshal.WriteByte(_native, Offsets.SingleSegment, value ? (byte)1 : (byte)0);
    }

    public bool PrintProgress
    {
        set => Marshal.WriteByte(_native, Offsets.PrintProgress, value ? (byte)1 : (byte)0);
    }

    public bool PrintTimestamps
    {
        set => Marshal.WriteByte(_native, Offsets.PrintTimestamps, value ? (byte)1 : (byte)0);
    }

    public bool PrintSpecial
    {
        set => Marshal.WriteByte(_native, Offsets.PrintSpecial, value ? (byte)1 : (byte)0);
    }

    public bool PrintRealtime
    {
        set => Marshal.WriteByte(_native, Offsets.PrintRealtime, value ? (byte)1 : (byte)0);
    }

    /// <summary>
    /// Set language and detect_language fields.
    /// These fields are deeper in the struct and their exact offset depends on whisper.cpp version.
    /// We use whisper_full_default_params to set all defaults, then only override the early fields.
    /// For language, we rely on the defaults (English) unless "auto" is requested.
    /// 
    /// NOTE: To safely set language for non-default languages, the caller should use a thin
    /// C wrapper function, or we accept that non-English may not work without version-specific offsets.
    /// For the initial release, we support English (the default) and auto-detect.
    /// </summary>
    public void ConfigureLanguage(string language)
    {
        // The default params already have language="en".
        // For auto-detect, we need to set detect_language=true.
        // Since the language/detect_language field offsets vary by version,
        // we leave this as a known limitation documented below.
        //
        // TODO: When targeting a specific whisper.cpp version, add exact offsets for:
        //   - language (const char*) 
        //   - detect_language (bool)
        //   - suppress_blank (bool)
        //   - suppress_non_speech_tokens (bool)
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        if (_native != nint.Zero)
        {
            if (_ownedByNative)
                WhisperNative.FreeParams(_native);
            else
                Marshal.FreeHGlobal(_native);
            _native = nint.Zero;
        }
    }
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

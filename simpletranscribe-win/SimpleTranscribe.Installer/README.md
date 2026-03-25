# Installer

This directory contains the installer configuration for SimpleTranscribe on Windows.

## Recommended: Inno Setup

[Inno Setup](https://jrsoftware.org/isinfo.php) is a free, well-established installer creator for Windows.

### Building the installer

1. Install [Inno Setup 6+](https://jrsoftware.org/isdl.php)
2. Build the project in Release mode:
   ```
   dotnet publish ..\SimpleTranscribe\SimpleTranscribe.csproj -c Release -r win-x64 --self-contained
   ```
3. Open `SimpleTranscribe.iss` in Inno Setup Compiler
4. Click **Build → Compile**
5. Output: `Output/SimpleTranscribe-Setup.exe`

### What the installer does

- Installs to `%LOCALAPPDATA%\Programs\SimpleTranscribe`
- Creates Start Menu shortcut
- Creates optional Desktop shortcut
- Registers uninstaller
- Includes `whisper.dll` and sound assets

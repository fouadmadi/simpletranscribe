# Version Injection in CI

This project injects version numbers into both macOS and Windows builds during CI using GitHub Actions.

## Version Source
- If a Git tag is present, it is used as the version.
- Otherwise, the version is generated from the commit hash and date: `0.0.0-<short-hash>-<YYYYMMDD>`

## macOS (Swift)
- The workflow updates `simpletranscribe-mac/simpletranscribe/Info.plist`:
  - `CFBundleShortVersionString` and `CFBundleVersion` are set to the version.
- This is done before the Xcode build step using `/usr/libexec/PlistBuddy`.

## Windows (.NET)
- The workflow sets the `BUILD_VERSION` environment variable.
- The `.csproj` file uses this variable to override `Version`, `AssemblyVersion`, `FileVersion`, and `InformationalVersion`.
- This ensures the built executable and installer reflect the correct version.

See `.github/workflows/ci.yml` for implementation details.
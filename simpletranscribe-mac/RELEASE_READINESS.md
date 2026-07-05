# SimpleTranscribe — Apple App Store Release Readiness Report

**Generated:** 2026-03-20  
**Verdict:** 🚨 **NOT READY** — 8 critical blockers, 5 security/quality issues, 4 UX improvements, 4 code quality items

---

## Executive Summary

SimpleTranscribe is a well-architected macOS menu bar transcription app (~1,500 LOC) using SwiftUI + whisper.cpp. Core functionality works, but **the app cannot be submitted to the App Store** in its current state due to sandbox violations, invalid deployment targets, missing icons, and an unpinned dependency.

---

## 🚨 Critical Blockers (Must Fix Before Submission)

### 1. App Sandbox is Disabled
- **File:** `simpletranscribe/simpletranscribe.entitlements`
- **Issue:** `com.apple.security.app-sandbox` is set to `false`
- **Impact:** Automatic rejection — Mac App Store requires sandboxing
- **Fix:** Enable sandbox and add targeted entitlements:
  ```xml
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.device.audio-input</key>
  <true/>
  <key>com.apple.security.automation.apple-events</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  ```

### 2. Incomplete Entitlements File
- **File:** `simpletranscribe/simpletranscribe.entitlements`
- **Issue:** Only contains sandbox=false. Missing all required permission entitlements.
- **Fix:** Add entitlements for microphone, audio input, Apple Events automation, and outgoing network connections.

### 3. Invalid Deployment Targets
- **File:** `simpletranscribe.xcodeproj/project.pbxproj`
- **Issue:** iOS deployment target is `26.2`, visionOS is `26.2` — these versions don't exist
- **Impact:** Build will fail for those platforms
- **Fix:** Either remove iOS/visionOS support (recommended — this is a macOS app) or set valid targets (e.g., iOS 18.0)

### 4. Unstable SPM Dependency
- **File:** `simpletranscribe.xcodeproj/project.pbxproj`
- **Issue:** SwiftWhisper tracks `master` branch — no version pinning
- **Impact:** Builds may break at any time; App Review expects reproducible builds
- **Fix:** Pin to a specific release tag or commit SHA

### 5. Missing App Icons
- **File:** `simpletranscribe/Assets.xcassets/AppIcon.appiconset/Contents.json`
- **Issue:** Icon slots are defined (16×16 through 1024×1024) but **no image files** are referenced
- **Impact:** App Store requires a 1024×1024 icon; all sizes needed for macOS
- **Fix:** Create app icon artwork and add to asset catalog

### 6. No Team ID / Signing Identity
- **File:** `simpletranscribe.xcodeproj/project.pbxproj`
- **Issue:** `CODE_SIGN_STYLE = Automatic` but no `DEVELOPMENT_TEAM` is set
- **Impact:** Cannot sign for distribution without valid team
- **Fix:** Set your Apple Developer Team ID in Xcode signing settings

### 7. Wrong Model File Sizes
- **File:** `simpletranscribe/Models/KnownModels.swift`
- **Issue:** Tiny model listed as 140 MB but actual size is ~77 MB
- **Impact:** Misleading download size shown to users
- **Fix:** Update `size` values to match actual Hugging Face file sizes

### 8. Privacy Description Verification
- **File:** Build settings (auto-generated Info.plist)
- **Status:** `NSMicrophoneUsageDescription` and `NSAppleEventsUsageDescription` are present in build settings ✅
- **Risk:** Verify these are correctly embedded in the final binary after sandbox is re-enabled

---

## ⚠️ Security & Quality Issues (Strongly Recommended)

### 9. Debug Print Statements in Production Code
- **Files:** `ContentView.swift`, `ModelService.swift`, `TranscriptionManager.swift`
- **Issue:** Numerous `print("[Paste]...")`, `print("[Model]...")` statements
- **Fix:** Replace with `os_log` or remove entirely

### 10. No Model File Validation
- **Files:** `Services/ModelService.swift`, `Models/KnownModels.swift`
- **Issue:** Downloaded .bin model files are not hash-verified — could be corrupted or tampered
- **Fix:** Add SHA256 checksums to `KnownModels.swift` and verify after download

### 11. No Download Timeout Handling
- **File:** `Services/ModelService.swift`
- **Issue:** URLSession downloads have no timeout — can hang indefinitely on poor connections
- **Fix:** Configure `URLSessionConfiguration.timeoutIntervalForResource`

### 12. Potential Deadlock in ModelService
- **File:** `Services/ModelService.swift` (download delegate)
- **Issue:** `DispatchQueue.main.sync` called from delegate queue — if main thread is waiting on this result, deadlock occurs
- **Fix:** Use `DispatchQueue.main.async` or restructure to avoid synchronous main-thread access

### 13. Unvalidated Custom Model Discovery
- **File:** `Services/ModelService.swift` (lines ~55-77)
- **Issue:** Silently discovers and loads any `.bin` file in the models directory without validation
- **Fix:** Validate file format/header before loading, or restrict to known models only

---

## 💡 User Experience Improvements (Recommended)

### 14. No Settings Persistence
- **File:** `AppModel.swift`
- **Issue:** `selectedLanguage`, `selectedModelID`, and `selectedInputDevice` reset every launch
- **Fix:** Use `@AppStorage` or `UserDefaults` for persistence

### 15. No Download Retry
- **File:** `Views/ModelDownloadView.swift`
- **Issue:** Failed downloads show error but no retry button
- **Fix:** Add retry mechanism in download error state

### 16. Recording Buffer Overflow (2-Minute Limit)
- **File:** `TranscriptionManager.swift` (line ~62)
- **Issue:** Audio buffer hardcoded to 1,920,000 samples (~2 minutes at 16kHz). Longer recordings silently lose data.
- **Fix:** Use dynamic buffer sizing or warn the user

### 17. Non-Discoverable Hotkey
- **File:** `HotKeyManager.swift`
- **Issue:** fn+ctrl hotkey is hardcoded and not mentioned anywhere in the UI
- **Fix:** Add tooltip, menu item, or onboarding hint

---

## 🔧 Code Quality (Nice to Have)

### 18. Monolithic ContentView (500+ Lines)
- **File:** `ContentView.swift`
- **Issue:** All UI, recording logic, paste strategies, and settings in one file
- **Fix:** Extract into `RecordingControlsView`, `TranscriptResultsView`, `SettingsAreaView`

### 19. Zero Test Coverage
- **Directory:** `simpletranscribeTests/` (empty)
- **Issue:** No unit tests exist for any component
- **Fix:** Add tests for `TranscriptionManager`, `AudioManager`, `ModelService`, `AppModel`

### 20. No Shared Build Scheme
- **Directory:** `simpletranscribe.xcodeproj/xcshareddata/xcschemes/` (empty)
- **Issue:** No shared scheme for reproducible CI/CD builds
- **Fix:** Create and commit a shared scheme

### 21. Paste Mechanism Under Sandbox
- **File:** `ContentView.swift` (lines ~420-486)
- **Issue:** Three paste strategies (CGEvent, AppleScript, osascript subprocess) — untested under sandbox
- **Risk:** `osascript` subprocess may be blocked by sandbox; CGEvent may need additional entitlements
- **Fix:** Test all strategies with sandbox enabled; remove non-functional paths

---

## ✅ What's Already Good

| Area | Status |
|------|--------|
| SwiftUI + @Observable architecture | ✅ Modern, clean |
| AVAudioEngine audio capture (16kHz mono) | ✅ Correct format for Whisper |
| Model download with progress tracking | ✅ Good UX |
| Application Support directory usage | ✅ Proper file management |
| Privacy descriptions in build settings | ✅ Present |
| Sound feedback (Tink/Glass/Basso) | ✅ Good UX |
| No hardcoded paths or secrets | ✅ Secure |
| Auto-generated Info.plist | ✅ Modern approach |
| Dead code stripping enabled | ✅ Release optimization |

---

## Platform Decision Required

The project declares support for **macOS, iOS, iPadOS, and visionOS** but the app uses macOS-only APIs:
- `NSEvent` global/local monitors (menu bar hotkey)
- `CGEvent` posting (paste-at-cursor)
- `NSSound` (audio feedback)
- System Events / AppleScript automation

**Recommendation:** Release as **macOS-only** and remove iOS/visionOS targets to avoid confusion and build errors.

---

## Recommended Fix Order

| Priority | Item | Effort |
|----------|------|--------|
| 1 | Enable sandbox + fix entitlements | Small |
| 2 | Fix/remove invalid deployment targets | Small |
| 3 | Pin SwiftWhisper to release version | Small |
| 4 | Add app icons | Medium |
| 5 | Set Team ID for signing | Small |
| 6 | Fix model sizes in KnownModels | Small |
| 7 | Remove debug prints → os_log | Small |
| 8 | Add model hash verification | Medium |
| 9 | Add settings persistence | Small |
| 10 | Fix deadlock risk in ModelService | Small |
| 11 | Test paste strategies under sandbox | Medium |
| 12 | Add download retry + timeouts | Medium |
| 13 | Refactor ContentView | Medium |
| 14 | Add unit tests | Large |

---

*Items 1-6 are required for App Store submission. Items 7-11 are strongly recommended for a quality release. Items 12-14 improve long-term maintainability.*

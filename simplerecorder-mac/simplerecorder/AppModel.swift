import SwiftUI
import Observation
import AVFoundation

@MainActor
@Observable
final class AppModel {
    var isRecording = false
    var isSaving = false
    var recordingSource: RecordingSource = .microphone
    var elapsedSeconds = 0
    var recordings: [RecordingEntry] = []
    var micPermissionGranted = false
    var screenRecordingPermissionGranted = false
    var errorMessage: String?
    var lastSavedURL: URL?

    private var currentSession: RecordingSession?
    private var elapsedTimer: Timer?

    var canRecord: Bool {
        switch recordingSource {
        case .microphone:   return micPermissionGranted
        case .systemAudio:  return screenRecordingPermissionGranted
        case .both:         return micPermissionGranted && screenRecordingPermissionGranted
        }
    }

    var needsMicPermission: Bool { !micPermissionGranted }
    var needsScreenPermission: Bool {
        (recordingSource == .systemAudio || recordingSource == .both) && !screenRecordingPermissionGranted
    }

    // MARK: - Permissions

    func checkPermissions() async {
        micPermissionGranted = await withCheckedContinuation { continuation in
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                continuation.resume(returning: true)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            default:
                continuation.resume(returning: false)
            }
        }
        screenRecordingPermissionGranted = CGPreflightScreenCaptureAccess()
    }

    func refreshScreenRecordingPermission() {
        screenRecordingPermissionGranted = CGPreflightScreenCaptureAccess()
    }

    func openMicPermissionSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        )
    }

    func openScreenRecordingSettings() {
        CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        )
    }

    // MARK: - Recording

    func toggleRecording() {
        if isRecording {
            Task { await stopRecording() }
        } else {
            Task { await startRecording() }
        }
    }

    private func startRecording() async {
        guard canRecord else { return }
        errorMessage = nil
        lastSavedURL = nil

        let session = RecordingSession(source: recordingSource)
        currentSession = session

        do {
            try await session.start()
            isRecording = true
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
            currentSession = nil
        }
    }

    private func stopRecording() async {
        guard let session = currentSession else { return }

        isRecording = false
        stopTimer()
        let duration = TimeInterval(elapsedSeconds)
        elapsedSeconds = 0
        isSaving = true

        do {
            let url = try await session.stop()
            let entry = RecordingEntry(url: url, date: Date(), duration: duration, source: recordingSource)
            recordings.insert(entry, at: 0)
            lastSavedURL = url
            saveRecordingsList()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
        currentSession = nil
    }

    // MARK: - Recordings persistence

    func loadRecordings() {
        guard let data = UserDefaults.standard.data(forKey: "simplerecorder.recordings"),
              let list = try? JSONDecoder().decode([RecordingEntry].self, from: data) else { return }
        recordings = list.filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    func deleteRecording(_ entry: RecordingEntry) {
        try? FileManager.default.removeItem(at: entry.url)
        recordings.removeAll { $0.id == entry.id }
        saveRecordingsList()
    }

    private func saveRecordingsList() {
        if let data = try? JSONEncoder().encode(recordings) {
            UserDefaults.standard.set(data, forKey: "simplerecorder.recordings")
        }
    }

    // MARK: - Timer

    private func startTimer() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.elapsedSeconds += 1 }
        }
    }

    private func stopTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }
}

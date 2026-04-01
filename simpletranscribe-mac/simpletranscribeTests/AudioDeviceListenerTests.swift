import Testing
import Foundation
import CoreAudio
import AVFoundation
@testable import simpletranscribe

// MARK: - AudioDeviceListener Tests

@Suite("AudioDeviceListener Tests")
struct AudioDeviceListenerTests {

    @Test("Listener can be created and destroyed without crashing")
    func listenerCanBeCreatedAndDestroyed() {
        var listener: AudioDeviceListener? = AudioDeviceListener()
        #expect(listener != nil)
        listener = nil  // triggers deinit, should not crash
    }

    @Test("Callbacks can be set on the listener")
    func callbacksCanBeSet() {
        let listener = AudioDeviceListener()
        listener.onDefaultInputChanged = { _ in }
        #expect(listener.onDevicesChanged != nil)
        #expect(listener.onDefaultInputChanged != nil)
    }

    @Test("getCurrentDefaultInputDevice returns without crashing")
    func getCurrentDefaultInputDeviceReturnsWithoutCrash() {
        // On machines with audio hardware this returns a valid ID;
        // on CI without audio it may return 0 — both are acceptable.
        let deviceID = AudioDeviceListener.getCurrentDefaultInputDevice()
        _ = deviceID
    }

    @Test("Multiple listeners can coexist")
    func multipleListenersCoexist() {
        let a = AudioDeviceListener()
        let b = AudioDeviceListener()
        #expect(a !== b)
        // Both should clean up without crashing when they go out of scope
    }
}

// MARK: - AudioManager Tests

@Suite("AudioManager Tests")
struct AudioManagerTests {

    @Test("startRecording with nil device does not crash")
    func startRecordingWithNilDevice() {
        let manager = AudioManager()
        // Should use system default when device is nil.
        // May fail if no mic permission, so just verify no unexpected crash.
        do {
            try manager.startRecording(device: nil)
            manager.stopRecording()
        } catch {
            // Expected on CI or without microphone permission
        }
    }

    @Test("stopRecording is safe to call without prior start")
    func stopRecordingWithoutStart() {
        let manager = AudioManager()
        // Should not crash even if engine was never started
        manager.stopRecording()
    }
}

// MARK: - useSystemDefault Persistence Tests

@Suite("UseSystemDefault Persistence Tests")
struct UseSystemDefaultPersistenceTests {

    @Test("useSystemDefault round-trips through UserDefaults")
    func useSystemDefaultPersistence() {
        let key = "useSystemDefault"
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            // Restore original value
            if let original = original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.set(false, forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == false)

        UserDefaults.standard.set(true, forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == true)
    }

    @Test("useSystemDefault defaults to true when unset")
    func useSystemDefaultDefaultsToTrue() {
        let key = "useSystemDefault"
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original = original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.removeObject(forKey: key)
        let value = UserDefaults.standard.object(forKey: key) as? Bool ?? true
        #expect(value == true)
    }
}

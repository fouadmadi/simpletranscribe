import CoreAudio

/// Monitors CoreAudio hardware for device additions/removals and default input device changes.
/// Callbacks are always dispatched to the main queue.
class AudioDeviceListener {
    var onDevicesChanged: (() -> Void)?
    var onDefaultInputChanged: ((AudioDeviceID) -> Void)?

    private var devicesListenerInstalled = false
    private var defaultInputListenerInstalled = false
    private var selfPtr: UnsafeMutableRawPointer?

    private var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    init() {
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        selfPtr = ptr

        let devicesStatus = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            deviceListenerCallback,
            ptr
        )
        if devicesStatus == noErr {
            devicesListenerInstalled = true
        } else {
            print("AudioDeviceListener: failed to add devices listener (OSStatus \(devicesStatus))")
        }

        let defaultInputStatus = AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultInputAddress,
            deviceListenerCallback,
            ptr
        )
        if defaultInputStatus == noErr {
            defaultInputListenerInstalled = true
        } else {
            print("AudioDeviceListener: failed to add default-input listener (OSStatus \(defaultInputStatus))")
        }
    }

    deinit {
        if devicesListenerInstalled {
            AudioObjectRemovePropertyListener(
                AudioObjectID(kAudioObjectSystemObject),
                &devicesAddress,
                deviceListenerCallback,
                selfPtr
            )
        }

        if defaultInputListenerInstalled {
            AudioObjectRemovePropertyListener(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultInputAddress,
                deviceListenerCallback,
                selfPtr
            )
        }
    }

    // MARK: - Querying the current default input device

    static func getCurrentDefaultInputDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        return deviceID
    }

    // MARK: - Internal callback dispatch

    fileprivate func handlePropertyChange(_ selector: AudioObjectPropertySelector) {
        switch selector {
        case kAudioHardwarePropertyDevices:
            DispatchQueue.main.async { [weak self] in
                self?.onDevicesChanged?()
            }
        case kAudioHardwarePropertyDefaultInputDevice:
            let newDevice = AudioDeviceListener.getCurrentDefaultInputDevice()
            DispatchQueue.main.async { [weak self] in
                self?.onDefaultInputChanged?(newDevice)
            }
        default:
            break
        }
    }
}

// MARK: - Free C callback function

private func deviceListenerCallback(
    objectID: AudioObjectID,
    numberAddresses: UInt32,
    addresses: UnsafePointer<AudioObjectPropertyAddress>,
    clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let clientData = clientData else { return noErr }
    let listener = Unmanaged<AudioDeviceListener>.fromOpaque(clientData).takeUnretainedValue()

    for i in 0..<Int(numberAddresses) {
        listener.handlePropertyChange(addresses[i].mSelector)
    }
    return noErr
}

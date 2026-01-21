import Foundation
import CoreAudio
import AudioToolbox

class AudioDeviceService {
    var onDevicesChanged: (() -> Void)?
    var onVolumeChanged: (() -> Void)?

    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var volumeListenerBlock: AudioObjectPropertyListenerBlock?
    private var monitoredDeviceIds: Set<AudioObjectID> = []

    func getDevices() -> [AudioDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIds = [AudioObjectID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIds
        )

        guard status == noErr else { return [] }

        var devices: [AudioDevice] = []

        for deviceId in deviceIds {
            let hasInput = hasStreams(deviceId: deviceId, scope: kAudioDevicePropertyScopeInput)
            let hasOutput = hasStreams(deviceId: deviceId, scope: kAudioDevicePropertyScopeOutput)
            if !hasInput && !hasOutput {
                continue
            }

            guard let name = getDeviceName(id: deviceId) else { continue }
            guard let uid = getDeviceUID(id: deviceId) else { continue }

            if hasInput {
                devices.append(AudioDevice(id: deviceId, uid: uid, name: name, type: .input))
            }
            if hasOutput {
                devices.append(AudioDevice(id: deviceId, uid: uid, name: name, type: .output))
            }
        }

        return devices
    }

    func getCurrentDefaultDevice(type: AudioDeviceType) -> AudioObjectID? {
        let selector: AudioObjectPropertySelector = type == .input
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceId: AudioObjectID = 0
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceId
        )

        return status == noErr ? deviceId : nil
    }

    func setDefaultDevice(_ deviceId: AudioObjectID, type: AudioDeviceType) {
        let selector: AudioObjectPropertySelector = type == .input
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableDeviceId = deviceId
        let dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &mutableDeviceId
        )
    }

    func getOutputVolume() -> Float? {
        guard let deviceId = getCurrentDefaultDevice(type: .output) else { return nil }
        return getDeviceVolume(deviceId, scope: kAudioDevicePropertyScopeOutput)
    }

    func getInputVolume() -> Float? {
        guard let deviceId = getCurrentDefaultDevice(type: .input) else { return nil }
        return getDeviceVolume(deviceId, scope: kAudioDevicePropertyScopeInput)
    }

    func setOutputVolume(_ volume: Float) {
        guard let deviceId = getCurrentDefaultDevice(type: .output) else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableVolume = volume
        let dataSize = UInt32(MemoryLayout<Float32>.size)

        AudioObjectSetPropertyData(
            deviceId,
            &propertyAddress,
            0,
            nil,
            dataSize,
            &mutableVolume
        )
    }

    func setInputVolume(_ volume: Float) {
        guard let deviceId = getCurrentDefaultDevice(type: .input) else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var mutableVolume = volume
        let dataSize = UInt32(MemoryLayout<Float32>.size)

        AudioObjectSetPropertyData(
            deviceId,
            &propertyAddress,
            0,
            nil,
            dataSize,
            &mutableVolume
        )
    }

    private func getDeviceVolume(_ deviceId: AudioObjectID, scope: AudioObjectPropertyScope) -> Float? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var volume: Float32 = 0
        var dataSize = UInt32(MemoryLayout<Float32>.size)

        let status = AudioObjectGetPropertyData(
            deviceId,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &volume
        )

        return status == noErr ? volume : nil
    }

    func startListening() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        listenerBlock = { [weak self] _, _ in
            self?.onDevicesChanged?()
            self?.updateVolumeListeners()
        }

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            listenerBlock!
        )

        // Also listen to default device changes
        var inputDefaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &inputDefaultAddress,
            DispatchQueue.main,
            listenerBlock!
        )

        var outputDefaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &outputDefaultAddress,
            DispatchQueue.main,
            listenerBlock!
        )

        updateVolumeListeners()
    }

    func updateVolumeListeners() {
        removeVolumeListeners()

        let inputId = getCurrentDefaultDevice(type: .input)
        let outputId = getCurrentDefaultDevice(type: .output)
        let deviceIds = Set([inputId, outputId].compactMap { $0 })

        guard !deviceIds.isEmpty else { return }

        volumeListenerBlock = { [weak self] _, _ in
            self?.onVolumeChanged?()
        }

        for deviceId in deviceIds {
            var didAddListener = false

            if hasStreams(deviceId: deviceId, scope: kAudioDevicePropertyScopeOutput) {
                var volumeAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: kAudioObjectPropertyElementMain
                )
                AudioObjectAddPropertyListenerBlock(
                    deviceId,
                    &volumeAddress,
                    DispatchQueue.main,
                    volumeListenerBlock!
                )
                didAddListener = true
            }

            if hasStreams(deviceId: deviceId, scope: kAudioDevicePropertyScopeInput) {
                var volumeAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                    mScope: kAudioDevicePropertyScopeInput,
                    mElement: kAudioObjectPropertyElementMain
                )
                AudioObjectAddPropertyListenerBlock(
                    deviceId,
                    &volumeAddress,
                    DispatchQueue.main,
                    volumeListenerBlock!
                )
                didAddListener = true
            }

            if didAddListener {
                monitoredDeviceIds.insert(deviceId)
            }
        }
    }

    private func removeVolumeListeners() {
        guard let block = volumeListenerBlock else { return }

        for deviceId in monitoredDeviceIds {
            var volumeAddress = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(deviceId, &volumeAddress, DispatchQueue.main, block)

            volumeAddress.mScope = kAudioDevicePropertyScopeInput
            AudioObjectRemovePropertyListenerBlock(deviceId, &volumeAddress, DispatchQueue.main, block)
        }

        monitoredDeviceIds.removeAll()
        volumeListenerBlock = nil
    }


    func stopListening() {
        removeVolumeListeners()
        guard let block = listenerBlock else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )

        // Also remove default device change listeners
        var inputDefaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &inputDefaultAddress,
            DispatchQueue.main,
            block
        )

        var outputDefaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &outputDefaultAddress,
            DispatchQueue.main,
            block
        )

        listenerBlock = nil
    }

    private func hasStreams(deviceId: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceId,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        return status == noErr && dataSize > 0
    }

    private func getDeviceName(id: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(
            id,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        return status == noErr ? name as String? : nil
    }

    private func getDeviceUID(id: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(
            id,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &uid
        )

        return status == noErr ? uid as String? : nil
    }

    deinit {
        stopListening()
    }
}

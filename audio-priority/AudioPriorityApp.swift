import SwiftUI
import CoreAudio
import Observation

@main
struct AudioPriorityApp: App {
    @State private var audioManager = AudioManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(audioManager)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

@Observable
@MainActor
final class AudioManager {
    var isAutoSwitchEnabled: Bool {
        didSet {
            defaults.set(isAutoSwitchEnabled, forKey: autoSwitchDefaultsKey)
        }
    }
    var inputDevices: [AudioDevice] = []
    var speakerDevices: [AudioDevice] = []
    var hiddenInputDevices: [AudioDevice] = []
    var hiddenSpeakerDevices: [AudioDevice] = []
    var currentInputId: AudioObjectID?
    var currentOutputId: AudioObjectID?
    var volume: Float = 0
    var micVolume: Float = 0
    var isOutputVolumeAvailable: Bool = true
    var isInputVolumeAvailable: Bool = true
    private(set) var lockedInputVolumes: [String: Float] = [:]
    private(set) var lockedOutputVolumes: [String: Float] = [:]
    private let defaults = UserDefaults.standard
    private let autoSwitchDefaultsKey = "autoSwitchEnabled"
    private let deviceService = AudioDeviceService()
    private let priorityManager = PriorityManager()
    private var cachedDevices: [AudioDevice] = []
    private var pendingDeviceRefresh: DispatchWorkItem?
    private var pendingVolumeRefresh: DispatchWorkItem?

    private enum RefreshConstants {
        static let deviceDebounce: TimeInterval = 0.08
        static let volumeDebounce: TimeInterval = 0.03
        static let volumeComparisonTolerance: Float = 0.0001
    }

    var isOutputVolumeLocked: Bool {
        lockedVolume(for: .output) != nil
    }

    var isInputVolumeLocked: Bool {
        lockedVolume(for: .input) != nil
    }

    func refreshVolume() {
        if let volume = deviceService.getOutputVolume() {
            self.volume = volume
            isOutputVolumeAvailable = true
        } else {
            isOutputVolumeAvailable = false
        }
    }

    func refreshMicVolume() {
        if let volume = deviceService.getInputVolume() {
            micVolume = volume
            isInputVolumeAvailable = true
        } else {
            isInputVolumeAvailable = false
        }
    }

    func setVolume(_ newVolume: Float) {
        guard !isOutputVolumeLocked else { return }
        volume = newVolume
        deviceService.setOutputVolume(newVolume)
    }

    func setMicVolume(_ newVolume: Float) {
        guard !isInputVolumeLocked else { return }
        micVolume = newVolume
        deviceService.setInputVolume(newVolume)
    }

    init() {
        isAutoSwitchEnabled = defaults.object(forKey: autoSwitchDefaultsKey) as? Bool ?? true
        lockedInputVolumes = priorityManager.lockedVolumes(for: .input)
        lockedOutputVolumes = priorityManager.lockedVolumes(for: .output)
        performDeviceRefresh()
        refreshVolume()
        refreshMicVolume()
        setupDeviceChangeListener()
        setupVolumeListener()
        if isAutoSwitchEnabled {
            applyHighestPriorityInput()
            applyHighestPriorityOutput()
        }
    }

    private func setupVolumeListener() {
        deviceService.onVolumeChanged = { [weak self] in
            self?.scheduleVolumeRefresh()
        }
    }

    private func handleVolumeChange() {
        enforceCurrentVolumeLocks()
        refreshVolume()
        refreshMicVolume()
    }

    func refreshDevices() {
        if cachedDevices.isEmpty {
            performDeviceRefresh()
            return
        }
        applyDeviceSnapshot(cachedDevices)
    }

    private func applyDeviceSnapshot(_ allConnectedDevices: [AudioDevice]) {
        cachedDevices = allConnectedDevices
        let displayDevices = allConnectedDevices.map { device in
            device.renamed(to: priorityManager.customName(for: device) ?? device.originalName)
        }
        let connectedInputs = displayDevices.filter { $0.type == .input }
        let connectedOutputs = displayDevices.filter { $0.type == .output }

        let hiddenInputUIDs = priorityManager.hiddenUIDs(for: .input)
        var visibleInputs: [AudioDevice] = []
        var regularHiddenInputs: [AudioDevice] = []
        for device in connectedInputs {
            if hiddenInputUIDs.contains(device.uid) {
                regularHiddenInputs.append(device)
            } else {
                visibleInputs.append(device)
            }
        }
        inputDevices = priorityManager.sortByPriority(visibleInputs, type: .input)
        hiddenInputDevices = regularHiddenInputs

        let hiddenOutputUIDs = priorityManager.hiddenUIDs(for: .output)
        var visibleOutputs: [AudioDevice] = []
        var regularHiddenOutputs: [AudioDevice] = []
        for device in connectedOutputs {
            if hiddenOutputUIDs.contains(device.uid) {
                regularHiddenOutputs.append(device)
            } else {
                visibleOutputs.append(device)
            }
        }
        speakerDevices = priorityManager.sortByPriority(visibleOutputs, type: .output)
        hiddenSpeakerDevices = regularHiddenOutputs
        currentInputId = deviceService.getCurrentDefaultDevice(type: .input)
        currentOutputId = deviceService.getCurrentDefaultDevice(type: .output)
        enforceCurrentVolumeLocks()
    }

    private func performDeviceRefresh() {
        fetchDevices { [weak self] devices in
            self?.applyDeviceSnapshot(devices)
        }
    }

    private func scheduleDeviceRefresh() {
        pendingDeviceRefresh?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performDeviceRefreshAndApply()
        }
        pendingDeviceRefresh = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + RefreshConstants.deviceDebounce,
            execute: workItem
        )
    }

    private func performDeviceRefreshAndApply() {
        fetchDevices { [weak self] devices in
            guard let self else { return }
            self.applyDeviceSnapshot(devices)
            self.handleVolumeChange()
            if self.isAutoSwitchEnabled {
                self.applyHighestPriorityInput()
                self.applyHighestPriorityOutput()
            }
        }
    }

    private func scheduleVolumeRefresh() {
        pendingVolumeRefresh?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.handleVolumeChange()
        }
        pendingVolumeRefresh = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + RefreshConstants.volumeDebounce,
            execute: workItem
        )
    }

    func setAutoSwitchEnabled(_ enabled: Bool) {
        isAutoSwitchEnabled = enabled
        if enabled {
            applyHighestPriorityInput()
            applyHighestPriorityOutput()
        }
    }

    func hideDevice(_ device: AudioDevice) {
        priorityManager.hideDevice(device)
        refreshDevices()
        if !isAutoSwitchEnabled {
            return
        }
        if device.type == .input {
            applyHighestPriorityInput()
        } else {
            applyHighestPriorityOutput()
        }
    }

    func unhideDevice(_ device: AudioDevice) {
        priorityManager.unhideDevice(device)
        refreshDevices()
    }

    func renameDevice(_ device: AudioDevice, to proposedName: String) {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        if name == device.originalName {
            priorityManager.restoreOriginalName(for: device)
        } else {
            priorityManager.setCustomName(name, for: device)
        }
        refreshDevices()
    }

    func restoreOriginalName(for device: AudioDevice) {
        priorityManager.restoreOriginalName(for: device)
        refreshDevices()
    }

    func toggleOutputVolumeLock() {
        toggleVolumeLock(for: .output)
    }

    func toggleInputVolumeLock() {
        toggleVolumeLock(for: .input)
    }

    func moveInputDevice(from source: IndexSet, to destination: Int) {
        inputDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(inputDevices, type: .input)
        if let topInput = inputDevices.first {
            applyInputDevice(topInput)
        }
    }

    func moveSpeakerDevice(from source: IndexSet, to destination: Int) {
        speakerDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(speakerDevices, type: .output)
        if let topSpeaker = speakerDevices.first {
            applyOutputDevice(topSpeaker)
        }
    }

    func setInputDevice(_ device: AudioDevice) {
        applyInputDevice(device)
    }

    func setOutputDevice(_ device: AudioDevice) {
        applyOutputDevice(device)
    }

    private func applyInputDevice(_ device: AudioDevice) {
        if currentInputId == device.id {
            return
        }
        deviceService.setDefaultDevice(device.id, type: .input)
        currentInputId = device.id
        enforceVolumeLock(for: .input)
        refreshMicVolume()
    }

    private func applyOutputDevice(_ device: AudioDevice) {
        if currentOutputId == device.id {
            return
        }
        deviceService.setDefaultDevice(device.id, type: .output)
        currentOutputId = device.id
        enforceVolumeLock(for: .output)
        refreshVolume()
    }

    private func applyHighestPriorityInput() {
        if let first = inputDevices.first {
            applyInputDevice(first)
        }
    }

    private func applyHighestPriorityOutput() {
        if let first = speakerDevices.first {
            applyOutputDevice(first)
        }
    }

    private func fetchDevices(_ completion: @escaping @MainActor @Sendable ([AudioDevice]) -> Void) {
        let service = deviceService
        DispatchQueue.global(qos: .userInitiated).async {
            let devices = service.getDevices()
            Task { @MainActor in
                completion(devices)
            }
        }
    }

    private func setupDeviceChangeListener() {
        deviceService.onDevicesChanged = { [weak self] in
            self?.handleDeviceChange()
        }
        deviceService.startListening()
    }

    private func handleDeviceChange() {
        scheduleDeviceRefresh()
    }

    private func toggleVolumeLock(for type: AudioDeviceType) {
        guard let device = currentDevice(for: type) else { return }
        var lockedVolumes = type == .input ? lockedInputVolumes : lockedOutputVolumes

        if lockedVolumes[device.uid] != nil {
            lockedVolumes.removeValue(forKey: device.uid)
            priorityManager.setLockedVolume(nil, for: device)
        } else {
            let currentVolume = type == .input
                ? deviceService.getInputVolume()
                : deviceService.getOutputVolume()
            guard let currentVolume else { return }
            lockedVolumes[device.uid] = currentVolume
            priorityManager.setLockedVolume(currentVolume, for: device)
        }

        if type == .input {
            lockedInputVolumes = lockedVolumes
        } else {
            lockedOutputVolumes = lockedVolumes
        }
    }

    private func currentDevice(for type: AudioDeviceType) -> AudioDevice? {
        let currentId = type == .input ? currentInputId : currentOutputId
        return cachedDevices.first { $0.type == type && $0.id == currentId }
    }

    private func lockedVolume(for type: AudioDeviceType) -> Float? {
        guard let device = currentDevice(for: type) else { return nil }
        let lockedVolumes = type == .input ? lockedInputVolumes : lockedOutputVolumes
        return lockedVolumes[device.uid]
    }

    private func enforceCurrentVolumeLocks() {
        enforceVolumeLock(for: .input)
        enforceVolumeLock(for: .output)
    }

    private func enforceVolumeLock(for type: AudioDeviceType) {
        guard let lockedVolume = lockedVolume(for: type) else { return }
        let currentVolume = type == .input
            ? deviceService.getInputVolume()
            : deviceService.getOutputVolume()

        if let currentVolume,
           abs(currentVolume - lockedVolume) <= RefreshConstants.volumeComparisonTolerance {
            return
        }

        if type == .input {
            deviceService.setInputVolume(lockedVolume)
            micVolume = lockedVolume
        } else {
            deviceService.setOutputVolume(lockedVolume)
            volume = lockedVolume
        }
    }
}

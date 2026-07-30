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
    var applicationAudioSources: [ApplicationAudioSource] = []
    var applicationAudioMessage: String?
    private let defaults = UserDefaults.standard
    private let autoSwitchDefaultsKey = "autoSwitchEnabled"
    private let deviceService = AudioDeviceService()
    private let applicationAudioService = ApplicationAudioService()
    private let priorityManager = PriorityManager()
    private var cachedDevices: [AudioDevice] = []
    private var pendingDeviceRefresh: DispatchWorkItem?
    private var pendingVolumeRefresh: DispatchWorkItem?

    private enum RefreshConstants {
        static let deviceDebounce: TimeInterval = 0.08
        static let volumeDebounce: TimeInterval = 0.03
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
        volume = newVolume
        deviceService.setOutputVolume(newVolume)
    }

    func setMicVolume(_ newVolume: Float) {
        micVolume = newVolume
        deviceService.setInputVolume(newVolume)
    }

    init() {
        isAutoSwitchEnabled = defaults.object(forKey: autoSwitchDefaultsKey) as? Bool ?? true
        performDeviceRefresh()
        refreshVolume()
        refreshMicVolume()
        setupDeviceChangeListener()
        setupVolumeListener()
        setupApplicationAudio()
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

    private func setupApplicationAudio() {
        applicationAudioService.onSourcesChanged = { [weak self] sources in
            self?.applyApplicationAudioSources(sources)
        }
        applicationAudioService.startListening()
        if let message = applicationAudioService.setOutputDevice(
            deviceService.getCurrentDefaultDevice(type: .output)
        ) {
            applicationAudioMessage = message
        }
        refreshApplicationAudioSources()
    }

    private func handleVolumeChange() {
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
        let connectedInputs = allConnectedDevices.filter { $0.type == .input }
        let connectedOutputs = allConnectedDevices.filter { $0.type == .output }

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
        if let message = applicationAudioService.setOutputDevice(currentOutputId) {
            applicationAudioMessage = message
        }
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

    private func refreshApplicationAudioSources() {
        applyApplicationAudioSources(applicationAudioService.getSources())
    }

    func setApplicationVolume(_ volume: Float, for sourceID: AudioObjectID) {
        guard let index = applicationAudioSources.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        applicationAudioSources[index].volume = volume
        if let message = applicationAudioService.setVolume(volume, for: sourceID) {
            applicationAudioSources[index].volume = 1
            applicationAudioMessage = message
        } else {
            applicationAudioMessage = nil
        }
    }

    func dismissApplicationAudioMessage() {
        applicationAudioMessage = nil
    }

    private func applyApplicationAudioSources(_ sources: [ApplicationAudioSource]) {
        applicationAudioSources = sources
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
        refreshMicVolume()
    }

    private func applyOutputDevice(_ device: AudioDevice) {
        if currentOutputId == device.id {
            return
        }
        deviceService.setDefaultDevice(device.id, type: .output)
        currentOutputId = device.id
        if let message = applicationAudioService.setOutputDevice(device.id) {
            applicationAudioMessage = message
        }
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

    deinit {
        applicationAudioService.stopListening()
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
}

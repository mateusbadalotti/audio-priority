import SwiftUI
import CoreAudio

@main
struct AudioPriorityApp: App {
    @StateObject private var audioManager = AudioManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(audioManager)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
class AudioManager: ObservableObject {
    @Published var isAutoSwitchEnabled: Bool {
        didSet {
            defaults.set(isAutoSwitchEnabled, forKey: autoSwitchDefaultsKey)
        }
    }
    @Published var inputDevices: [AudioDevice] = []
    @Published var speakerDevices: [AudioDevice] = []
    @Published var hiddenInputDevices: [AudioDevice] = []
    @Published var hiddenSpeakerDevices: [AudioDevice] = []
    @Published var currentInputId: AudioObjectID?
    @Published var currentOutputId: AudioObjectID?
    @Published var volume: Float = 0
    @Published var micVolume: Float = 0
    @Published var isOutputVolumeAvailable: Bool = true
    @Published var isInputVolumeAvailable: Bool = true
    private let defaults = UserDefaults.standard
    private let autoSwitchDefaultsKey = "autoSwitchEnabled"
    private let deviceService = AudioDeviceService()
    let priorityManager = PriorityManager()
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
        if isAutoSwitchEnabled {
            applyHighestPriorityInput()
            applyHighestPriorityOutput()
        }
    }

    private func setupVolumeListener() {
        deviceService.onVolumeChanged = { [weak self] in
            Task { @MainActor in
                self?.scheduleVolumeRefresh()
            }
        }
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

        let visibleInputs = connectedInputs.filter { !priorityManager.isHidden($0) }
        let regularHiddenInputs = connectedInputs.filter { priorityManager.isHidden($0) }
        inputDevices = priorityManager.sortByPriority(visibleInputs, type: .input)
        hiddenInputDevices = regularHiddenInputs

        let visibleOutputs = connectedOutputs.filter { !priorityManager.isHidden($0) }
        let regularHiddenOutputs = connectedOutputs.filter { priorityManager.isHidden($0) }
        speakerDevices = priorityManager.sortByPriority(visibleOutputs, type: .output)
        hiddenSpeakerDevices = regularHiddenOutputs
        currentInputId = deviceService.getCurrentDefaultDevice(type: .input)
        currentOutputId = deviceService.getCurrentDefaultDevice(type: .output)
    }

    private func performDeviceRefresh() {
        let service = deviceService
        Task { [weak self] in
            let devices = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: service.getDevices())
                }
            }
            await MainActor.run {
                self?.applyDeviceSnapshot(devices)
            }
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
        let service = deviceService
        Task { [weak self] in
            let devices = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: service.getDevices())
                }
            }
            await MainActor.run {
                guard let self else { return }
                self.applyDeviceSnapshot(devices)
                self.handleVolumeChange()
                if self.isAutoSwitchEnabled {
                    self.applyHighestPriorityInput()
                    self.applyHighestPriorityOutput()
                }
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

    func moveInputDevice(from source: IndexSet, to destination: Int) {
        inputDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(inputDevices, type: .input)
        if let topInput = inputDevices.first, topInput.isConnected {
            applyInputDevice(topInput)
        }
    }

    func moveSpeakerDevice(from source: IndexSet, to destination: Int) {
        speakerDevices.move(fromOffsets: source, toOffset: destination)
        priorityManager.savePriorities(speakerDevices, type: .output)
        if let topSpeaker = speakerDevices.first, topSpeaker.isConnected {
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
        deviceService.setDefaultDevice(device.id, type: .input)
        currentInputId = device.id
        refreshMicVolume()
    }

    private func applyOutputDevice(_ device: AudioDevice) {
        deviceService.setDefaultDevice(device.id, type: .output)
        currentOutputId = device.id
    }

    private func applyHighestPriorityInput() {
        if let first = inputDevices.first(where: { $0.isConnected }) {
            applyInputDevice(first)
        }
    }

    private func applyHighestPriorityOutput() {
        if let first = speakerDevices.first(where: { $0.isConnected }) {
            applyOutputDevice(first)
        }
    }

    private func setupDeviceChangeListener() {
        deviceService.onDevicesChanged = { [weak self] in
            Task { @MainActor in
                self?.handleDeviceChange()
            }
        }
        deviceService.startListening()
    }

    private func handleDeviceChange() {
        scheduleDeviceRefresh()
    }
}

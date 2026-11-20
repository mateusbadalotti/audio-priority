import SwiftUI
import CoreAudio
import AppKit

private enum VolumeConstants {
    static let minVolume: Float = 0
    static let maxVolume: Float = 1
    static let percentScale: Float = 100
    static let percentTextWidth: CGFloat = 36
    static let range: ClosedRange<Double> = Double(minVolume)...Double(maxVolume)
    static let scrollStep: Float = 0.02
    static let updateDebounceInterval: TimeInterval = 0.03
    static let smoothAnimationDuration: Double = 0.08
    static let lowVolumeThreshold: Float = 0.33
    static let midVolumeThreshold: Float = 0.66
}

struct MenuBarView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LiquidGlassGroup(spacing: LiquidGlassMetrics.sectionSpacing) {
            VStack(spacing: LiquidGlassMetrics.sectionSpacing) {
                SpeakersPanel()
                MicrophonesPanel()
                FooterPanel()
            }
            .padding(LiquidGlassMetrics.outerPadding)
        }
        .frame(width: LiquidGlassMetrics.popoverWidth)
        .background(
            Color(nsColor: .windowBackgroundColor)
                .overlay(Color.black.opacity(colorScheme == .dark ? 0.40 : 0))
        )
    }
}

private struct SpeakersPanel: View {
    @Environment(AudioManager.self) private var audioManager

    var body: some View {
        DeviceSectionView(
            devices: audioManager.speakerDevices,
            currentDeviceId: audioManager.currentOutputId,
            emptyMessage: "No speakers connected",
            onMove: audioManager.moveSpeakerDevice,
            onSelect: audioManager.setOutputDevice,
            onHide: audioManager.hideDevice,
            onRename: audioManager.renameDevice,
            onRestoreName: audioManager.restoreOriginalName
        ) {
            OutputVolumeSliderView()
        }
    }
}

private struct MicrophonesPanel: View {
    @Environment(AudioManager.self) private var audioManager

    var body: some View {
        DeviceSectionView(
            devices: audioManager.inputDevices,
            currentDeviceId: audioManager.currentInputId,
            emptyMessage: "No microphones connected",
            onMove: audioManager.moveInputDevice,
            onSelect: audioManager.setInputDevice,
            onHide: audioManager.hideDevice,
            onRename: audioManager.renameDevice,
            onRestoreName: audioManager.restoreOriginalName
        ) {
            MicVolumeSliderView()
        }
    }
}

private struct FooterPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AudioManager.self) private var audioManager

    private var autoSwitchBinding: Binding<Bool> {
        Binding(
            get: { audioManager.isAutoSwitchEnabled },
            set: { isEnabled in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                    audioManager.setAutoSwitchEnabled(isEnabled)
                }
            }
        )
    }

    var body: some View {
        LiquidGlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                Toggle(isOn: autoSwitchBinding) {
                    Text("Auto-switch")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)

                Spacer(minLength: 0)

                IgnoredDevicesMenu()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(
                            width: LiquidGlassMetrics.iconButtonSize,
                            height: LiquidGlassMetrics.iconButtonSize
                        )
                }
                .liquidGlassIconButtonStyle()
                .keyboardShortcut("q")
                .accessibilityLabel("Quit AudioPriority")
            }
            .padding(.leading, 10)
        }
    }
}

struct OutputVolumeSliderView: View {
    @Environment(AudioManager.self) private var audioManager

    private var volumeIcon: String {
        if audioManager.volume <= VolumeConstants.minVolume {
            return "speaker.fill"
        } else if audioManager.volume < VolumeConstants.lowVolumeThreshold {
            return "speaker.wave.1.fill"
        } else if audioManager.volume < VolumeConstants.midVolumeThreshold {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    var body: some View {
        SmoothVolumeSlider(
            title: "Speakers",
            icon: volumeIcon,
            accessibilityLabel: "Output volume",
            lockAccessibilityLabel: audioManager.isOutputVolumeLocked
                ? "Unlock speaker volume"
                : "Lock speaker volume",
            value: audioManager.volume,
            isAvailable: audioManager.isOutputVolumeAvailable,
            isLocked: audioManager.isOutputVolumeLocked,
            onChange: audioManager.setVolume,
            onToggleLock: audioManager.toggleOutputVolumeLock
        )
    }
}

struct MicVolumeSliderView: View {
    @Environment(AudioManager.self) private var audioManager

    var body: some View {
        SmoothVolumeSlider(
            title: "Microphones",
            icon: audioManager.micVolume <= VolumeConstants.minVolume ? "mic.slash.fill" : "mic.fill",
            accessibilityLabel: "Microphone volume",
            lockAccessibilityLabel: audioManager.isInputVolumeLocked
                ? "Unlock microphone volume"
                : "Lock microphone volume",
            value: audioManager.micVolume,
            isAvailable: audioManager.isInputVolumeAvailable,
            isLocked: audioManager.isInputVolumeLocked,
            onChange: audioManager.setMicVolume,
            onToggleLock: audioManager.toggleInputVolumeLock
        )
    }
}

struct SmoothVolumeSlider: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: LocalizedStringResource
    let icon: String
    let accessibilityLabel: LocalizedStringResource
    let lockAccessibilityLabel: LocalizedStringResource
    let value: Float
    let isAvailable: Bool
    let isLocked: Bool
    let onChange: (Float) -> Void
    let onToggleLock: () -> Void

    @State private var sliderValue: Double
    @State private var isEditing = false
    @State private var pendingUpdate: DispatchWorkItem?

    init(
        title: LocalizedStringResource,
        icon: String,
        accessibilityLabel: LocalizedStringResource,
        lockAccessibilityLabel: LocalizedStringResource,
        value: Float,
        isAvailable: Bool,
        isLocked: Bool,
        onChange: @escaping (Float) -> Void,
        onToggleLock: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.lockAccessibilityLabel = lockAccessibilityLabel
        self.value = value
        self.isAvailable = isAvailable
        self.isLocked = isLocked
        self.onChange = onChange
        self.onToggleLock = onToggleLock
        _sliderValue = State(initialValue: Double(value))
    }

    private var displayValue: Float {
        isEditing ? Float(sliderValue) : value
    }

    private var percentText: String {
        if !isAvailable {
            return "-"
        }
        let percent = Int((displayValue * VolumeConstants.percentScale).rounded())
        return "\(percent)%"
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                LiquidGlassAudioIcon(systemName: icon)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.15),
                        value: icon
                    )

                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Spacer(minLength: 8)

                Text(percentText)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: VolumeConstants.percentTextWidth, alignment: .trailing)
                    .accessibilityHidden(true)

                Button(action: onToggleLock) {
                    Image(systemName: isLocked ? "lock.fill" : "lock.open")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isLocked ? Color.accentColor : Color.secondary.opacity(0.6))
                        .frame(
                            width: LiquidGlassMetrics.audioIconSize,
                            height: LiquidGlassMetrics.audioIconSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isAvailable && !isLocked)
                .accessibilityLabel(lockAccessibilityLabel)
            }

            Slider(
                value: $sliderValue,
                in: VolumeConstants.range,
                onEditingChanged: { editing in
                    isEditing = editing
                    if !editing {
                        pendingUpdate?.cancel()
                        onChange(Float(sliderValue))
                    }
                }
            )
            .controlSize(.small)
            .tint(.secondary)
            .disabled(!isAvailable || isLocked)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(percentText)
            .accessibilityHint(isLocked ? "Volume locked" : "")
        }
        .onChange(of: sliderValue) { _, newValue in
            if isEditing {
                scheduleUpdate(newValue)
            }
        }
        .onChange(of: value) { _, newValue in
            if !isEditing {
                withAnimation(
                    reduceMotion
                        ? nil
                        : .linear(duration: VolumeConstants.smoothAnimationDuration)
                ) {
                    sliderValue = Double(newValue)
                }
            }
        }
        .onScrollWheel { delta in
            guard isAvailable, !isLocked else { return }
            let newVolume = value + Float(delta) * VolumeConstants.scrollStep
            onChange(max(VolumeConstants.minVolume, min(VolumeConstants.maxVolume, newVolume)))
        }
    }

    private func scheduleUpdate(_ newValue: Double) {
        pendingUpdate?.cancel()
        let workItem = DispatchWorkItem {
            onChange(Float(newValue))
        }
        pendingUpdate = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + VolumeConstants.updateDebounceInterval,
            execute: workItem
        )
    }
}

struct ScrollWheelModifier: ViewModifier {
    let onScroll: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.background(
            ScrollWheelReceiver(onScroll: onScroll)
        )
    }
}

struct ScrollWheelReceiver: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

final class ScrollWheelNSView: NSView {
    var onScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.deltaY)
    }
}

extension View {
    func onScrollWheel(_ action: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollWheelModifier(onScroll: action))
    }
}

struct DeviceSectionView<Header: View>: View {
    let devices: [AudioDevice]
    let currentDeviceId: AudioObjectID?
    let emptyMessage: LocalizedStringResource
    let onMove: (IndexSet, Int) -> Void
    let onSelect: (AudioDevice) -> Void
    var onHide: ((AudioDevice) -> Void)?
    var onRename: ((AudioDevice, String) -> Void)?
    var onRestoreName: ((AudioDevice) -> Void)?
    @ViewBuilder let header: Header

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if devices.isEmpty {
                Text(emptyMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                DeviceListView(
                    devices: devices,
                    currentDeviceId: currentDeviceId,
                    onMove: onMove,
                    onSelect: onSelect,
                    onHide: onHide,
                    onRename: onRename,
                    onRestoreName: onRestoreName
                )
            }
        }
        .padding(LiquidGlassMetrics.panelPadding)
        .liquidGlassPanel(cornerRadius: LiquidGlassMetrics.panelCornerRadius)
    }
}

struct IgnoredDevicesMenu: View {
    @Environment(AudioManager.self) private var audioManager

    private var ignoredCount: Int {
        audioManager.hiddenSpeakerDevices.count + audioManager.hiddenInputDevices.count
    }

    var body: some View {
        if ignoredCount > 0 {
            Menu {
                ignoredSection("Speakers", devices: audioManager.hiddenSpeakerDevices)
                ignoredSection("Microphones", devices: audioManager.hiddenInputDevices)
            } label: {
                Label("\(ignoredCount) ignored", systemImage: "eye.slash")
                    .font(.system(size: 11, weight: .medium))
                    .frame(height: LiquidGlassMetrics.iconButtonSize)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .foregroundStyle(.secondary)
            .fixedSize()
            .accessibilityHint("Choose a device to stop ignoring it")
        }
    }

    @ViewBuilder
    private func ignoredSection(_ title: LocalizedStringKey, devices: [AudioDevice]) -> some View {
        if !devices.isEmpty {
            Section(title) {
                ForEach(devices) { device in
                    Button {
                        audioManager.unhideDevice(device)
                    } label: {
                        Label(device.name, systemImage: "eye")
                    }
                }
            }
        }
    }
}

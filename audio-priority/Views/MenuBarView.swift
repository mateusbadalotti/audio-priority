import SwiftUI
import CoreAudio
import AppKit

private enum VolumeConstants {
    static let minVolume: Float = 0
    static let maxVolume: Float = 1
    static let percentScale: Float = 100
    static let percentTextWidth: CGFloat = 42
    static let range: ClosedRange<Double> = Double(minVolume)...Double(maxVolume)
    static let scrollStep: Float = 0.02
    static let updateDebounceInterval: TimeInterval = 0.03
    static let smoothAnimationDuration: Double = 0.08
    static let lowVolumeThreshold: Float = 0.33
    static let midVolumeThreshold: Float = 0.66
}

struct MenuBarView: View {
    var body: some View {
        LiquidGlassGroup(spacing: LiquidGlassMetrics.sectionSpacing) {
            VStack(spacing: LiquidGlassMetrics.sectionSpacing) {
                VolumePanel()
                DevicePanel()
                FooterPanel()
            }
            .padding(LiquidGlassMetrics.outerPadding)
        }
        .frame(width: LiquidGlassMetrics.popoverWidth)
    }
}

private struct VolumePanel: View {
    var body: some View {
        VStack(spacing: 10) {
            OutputVolumeSliderView()
            MicVolumeSliderView()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlassPanel(cornerRadius: LiquidGlassMetrics.panelCornerRadius)
    }
}

private struct DevicePanel: View {
    @Environment(AudioManager.self) private var audioManager

    var body: some View {
        VStack(spacing: 16) {
            DeviceSectionView(
                title: "SPEAKERS",
                icon: "speaker.wave.2.fill",
                devices: audioManager.speakerDevices,
                currentDeviceId: audioManager.currentOutputId,
                onMove: audioManager.moveSpeakerDevice,
                onSelect: audioManager.setOutputDevice,
                onHide: audioManager.hideDevice
            )

            DeviceSectionView(
                title: "MICROPHONES",
                icon: "mic.fill",
                devices: audioManager.inputDevices,
                currentDeviceId: audioManager.currentInputId,
                onMove: audioManager.moveInputDevice,
                onSelect: audioManager.setInputDevice,
                onHide: audioManager.hideDevice
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
}

private struct FooterPanel: View {
    var body: some View {
        LiquidGlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)

                HiddenDevicesToggleView()
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))

                AutoSwitchToggle()

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
                .accessibilityLabel("Quit")
                .help("Quit")
            }
        }
        .padding(.top, 2)
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
            icon: volumeIcon,
            accessibilityLabel: "Output volume",
            value: audioManager.volume,
            isAvailable: audioManager.isOutputVolumeAvailable,
            onChange: audioManager.setVolume
        )
    }
}

struct MicVolumeSliderView: View {
    @Environment(AudioManager.self) private var audioManager

    var body: some View {
        SmoothVolumeSlider(
            icon: "mic.fill",
            accessibilityLabel: "Microphone volume",
            value: audioManager.micVolume,
            isAvailable: audioManager.isInputVolumeAvailable,
            onChange: audioManager.setMicVolume
        )
    }
}

struct SmoothVolumeSlider: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let icon: String
    let accessibilityLabel: LocalizedStringResource
    let value: Float
    let isAvailable: Bool
    let onChange: (Float) -> Void

    @State private var sliderValue: Double
    @State private var isEditing = false
    @State private var pendingUpdate: DispatchWorkItem?

    init(
        icon: String,
        accessibilityLabel: LocalizedStringResource,
        value: Float,
        isAvailable: Bool,
        onChange: @escaping (Float) -> Void
    ) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.value = value
        self.isAvailable = isAvailable
        self.onChange = onChange
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
        let percentString = String(percent)
        let maxDigits = String(Int(VolumeConstants.percentScale)).count
        let paddingCount = max(0, maxDigits - percentString.count)
        let padded = String(repeating: " ", count: paddingCount) + percentString
        return "\(padded)%"
    }

    var body: some View {
        HStack(spacing: 10) {
            LiquidGlassAudioIcon(
                systemName: icon,
                size: LiquidGlassMetrics.compactAudioIconSize,
                symbolSize: 10
            )
            .frame(width: 20)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.15),
                    value: icon
                )

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
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(percentText)

            Text(percentText)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: VolumeConstants.percentTextWidth, alignment: .trailing)
                .accessibilityHidden(true)
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

struct DeviceSectionView: View {
    let title: LocalizedStringResource
    let icon: String
    let devices: [AudioDevice]
    let currentDeviceId: AudioObjectID?
    let onMove: (IndexSet, Int) -> Void
    let onSelect: (AudioDevice) -> Void
    var onHide: ((AudioDevice) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                LiquidGlassAudioIcon(systemName: icon)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if devices.isEmpty {
                Text("No devices")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .italic()
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                DeviceListView(
                    devices: devices,
                    currentDeviceId: currentDeviceId,
                    onMove: onMove,
                    onSelect: onSelect,
                    onHide: onHide
                )
            }
        }
    }
}

struct HiddenDevicesToggleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AudioManager.self) private var audioManager
    @State private var isExpanded = false

    private var allHiddenDevices: [AudioDevice] {
        audioManager.hiddenInputDevices + audioManager.hiddenSpeakerDevices
    }

    var body: some View {
        if !allHiddenDevices.isEmpty {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: "eye.slash")
                    .font(.system(size: 12))
                    .frame(
                        width: LiquidGlassMetrics.iconButtonSize,
                        height: LiquidGlassMetrics.iconButtonSize
                    )
            }
            .liquidGlassIconButtonStyle()
            .accessibilityLabel("Show ignored devices")
            .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
                LiquidGlassGroup(spacing: 4) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(allHiddenDevices) { device in
                            HiddenDeviceRow(device: device)
                        }
                    }
                    .padding(12)
                    .frame(minWidth: 220)
                    .liquidGlassPanel(cornerRadius: LiquidGlassMetrics.panelCornerRadius)
                }
            }
        }
    }
}

struct HiddenDeviceRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AudioManager.self) private var audioManager
    let device: AudioDevice
    @State private var isHovering = false

    private var deviceIcon: String {
        device.type == .input ? "mic.fill" : "speaker.wave.2.fill"
    }

    var body: some View {
        HStack(spacing: 10) {
            LiquidGlassAudioIcon(
                systemName: deviceIcon,
                size: LiquidGlassMetrics.compactAudioIconSize,
                symbolSize: 10
            )
            .frame(width: 20)

            Text(device.name)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if isHovering {
                Button {
                    audioManager.unhideDevice(device)
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 13))
                        .frame(width: 24, height: 24)
                }
                .liquidGlassIconButtonStyle()
                .accessibilityLabel("Stop ignoring \(device.name)")
                .help("Stop ignoring")
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .liquidGlassRowBackground(isActive: isHovering)
        .accessibilityAction(named: "Stop ignoring") {
            audioManager.unhideDevice(device)
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.15),
            value: isHovering
        )
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

struct AutoSwitchToggle: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AudioManager.self) private var audioManager

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                audioManager.setAutoSwitchEnabled(!audioManager.isAutoSwitchEnabled)
            }
        } label: {
            Image(systemName: audioManager.isAutoSwitchEnabled ? "bolt.fill" : "bolt")
                .font(.system(size: 12, weight: .semibold))
                .frame(
                    width: LiquidGlassMetrics.iconButtonSize,
                    height: LiquidGlassMetrics.iconButtonSize
                )
        }
        .liquidGlassIconButtonStyle(isProminent: audioManager.isAutoSwitchEnabled)
        .accessibilityLabel("Auto Switch")
        .accessibilityValue(audioManager.isAutoSwitchEnabled ? "On" : "Off")
        .help(audioManager.isAutoSwitchEnabled ? "Disable auto-switching" : "Enable auto-switching")
    }
}

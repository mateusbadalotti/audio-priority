import SwiftUI

private enum VolumeMixerMetrics {
    static let rowHeight: CGFloat = 42
    static let maximumListHeight: CGFloat = 210
    static let percentageWidth: CGFloat = 38
}

struct VolumeMixerSectionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AudioManager.self) private var audioManager
    @State private var isExpanded = false

    private var hasAudioSources: Bool {
        !audioManager.applicationAudioSources.isEmpty
    }

    private var volumeMixerDisclosure: VolumeMixerDisclosure? {
        guard hasAudioSources else { return nil }
        return VolumeMixerDisclosure(
            sourceCount: audioManager.applicationAudioSources.count,
            isExpanded: isExpanded,
            toggle: toggleVolumeMixer
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            OutputVolumeSliderView(
                volumeMixerDisclosure: volumeMixerDisclosure
            )

            if isExpanded && hasAudioSources {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .opacity(0.45)

                    Text("Volume Mixer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    VolumeMixerContent()
                }
                .transition(.opacity)
            }
        }
        .onChange(of: hasAudioSources) { _, hasAudioSources in
            if !hasAudioSources {
                isExpanded = false
            }
        }
    }

    private func toggleVolumeMixer() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            isExpanded.toggle()
        }
    }
}

private struct VolumeMixerContent: View {
    @Environment(AudioManager.self) private var audioManager

    var body: some View {
        VStack(spacing: 8) {
            if let message = audioManager.applicationAudioMessage {
                ApplicationAudioMessageView(message: message)
            }

            VolumeMixerList()
        }
    }
}

private struct VolumeMixerList: View {
    @Environment(AudioManager.self) private var audioManager

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 6) {
                ForEach(audioManager.applicationAudioSources) { source in
                    VolumeMixerRow(source: source)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(
            height: min(
                CGFloat(audioManager.applicationAudioSources.count)
                    * (VolumeMixerMetrics.rowHeight + 6),
                VolumeMixerMetrics.maximumListHeight
            )
        )
    }
}

private struct VolumeMixerRow: View {
    @Environment(AudioManager.self) private var audioManager
    let source: ApplicationAudioSource

    private var percentageText: String {
        "\(Int((source.volume * 100).rounded()))%"
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { Double(source.volume) },
            set: { audioManager.setApplicationVolume(Float($0), for: source.id) }
        )
    }

    var body: some View {
        HStack(spacing: 9) {
            ApplicationSourceIcon(source: source)

            Text(source.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 92, alignment: .leading)

            Slider(value: volumeBinding, in: 0...1)
                .controlSize(.mini)
                .tint(source.volume < 1 ? .green : .secondary)
                .accessibilityLabel("\(source.name) volume")
                .accessibilityValue(percentageText)

            Button {
                audioManager.setApplicationVolume(1, for: source.id)
            } label: {
                Text(percentageText)
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(source.volume < 1 ? .primary : .secondary)
                    .frame(
                        width: VolumeMixerMetrics.percentageWidth,
                        alignment: .trailing
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(ResponsivePlainButtonStyle())
            .disabled(source.volume >= 1)
            .help(source.volume < 1 ? "Reset to 100%" : "Volume is at 100%")
            .accessibilityLabel("Reset \(source.name) to 100 percent")
        }
        .frame(height: VolumeMixerMetrics.rowHeight)
        .padding(.horizontal, 8)
        .background(
            source.volume < 1
                ? Color.green.opacity(0.045)
                : Color.primary.opacity(0.025),
            in: .rect(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    source.volume < 1
                        ? Color.green.opacity(0.1)
                        : Color.primary.opacity(0.035),
                    lineWidth: 0.5
                )
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ApplicationSourceIcon: View {
    let source: ApplicationAudioSource

    var body: some View {
        Group {
            if let icon = source.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app.fill")
                    .symbolRenderingMode(.hierarchical)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
        }
        .frame(width: 24, height: 24)
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
                .overlay {
                    Circle()
                        .stroke(.background, lineWidth: 1.5)
                }
                .accessibilityHidden(true)
        }
        .accessibilityHidden(true)
    }
}

private struct ApplicationAudioMessageView: View {
    @Environment(AudioManager.self) private var audioManager
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
                .padding(.top, 1)
                .accessibilityHidden(true)

            Text(message)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 2)

            Button {
                audioManager.dismissApplicationAudioMessage()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(ResponsivePlainButtonStyle())
            .accessibilityLabel("Dismiss message")
        }
        .padding(8)
        .background(.orange.opacity(0.07), in: .rect(cornerRadius: 10))
    }
}

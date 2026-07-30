import SwiftUI
import CoreAudio

struct DeviceListView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let devices: [AudioDevice]
    let currentDeviceId: AudioObjectID?
    let onMove: (IndexSet, Int) -> Void
    let onSelect: (AudioDevice) -> Void
    var onHide: ((AudioDevice) -> Void)?

    @State private var draggingIndex: Int?
    @State private var targetIndex: Int?
    
    private let rowHeight: CGFloat = 28
    private let rowSpacing: CGFloat = 7

    private var rowStride: CGFloat { rowHeight + rowSpacing }
    init(
        devices: [AudioDevice],
        currentDeviceId: AudioObjectID?,
        onMove: @escaping (IndexSet, Int) -> Void,
        onSelect: @escaping (AudioDevice) -> Void,
        onHide: ((AudioDevice) -> Void)? = nil
    ) {
        self.devices = devices
        self.currentDeviceId = currentDeviceId
        self.onMove = onMove
        self.onSelect = onSelect
        self.onHide = onHide
    }

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(devices.enumerated(), id: \.element.id) { index, device in
                DraggableDeviceRow(
                    device: device,
                    index: index,
                    isSelected: device.id == currentDeviceId,
                    onSelect: { onSelect(device) },
                    onHide: onHide,
                    isDragging: draggingIndex == index,
                    isDropTarget: isDropTarget(for: index),
                    isDropTargetBelow: isDropTargetBelow(for: index),
                    rowHeight: rowHeight,
                    rowStride: rowStride,
                    deviceCount: devices.count,
                    onDragStarted: {
                        draggingIndex = index
                    },
                    onTargetChanged: { newTarget in
                        targetIndex = newTarget
                    },
                    onDragEnded: {
                        performMove(fromIndex: index)
                    }
                )
                .offset(y: rowOffset(for: index))
                .zIndex(draggingIndex == index ? 100 : 0)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.12),
                    value: targetIndex
                )
            }
        }
    }
    
    private func isDropTarget(for index: Int) -> Bool {
        guard let target = targetIndex, let dragging = draggingIndex else { return false }
        return target == index && dragging != index && dragging != index - 1
    }
    
    private func isDropTargetBelow(for index: Int) -> Bool {
        guard let target = targetIndex, let dragging = draggingIndex else { return false }
        return target == devices.count && index == devices.count - 1 && dragging != devices.count - 1
    }

    private func rowOffset(for index: Int) -> CGFloat {
        guard let target = targetIndex, let dragging = draggingIndex else { return 0 }
        if dragging < target {
            return index > dragging && index < target ? -rowStride : 0
        }
        if dragging > target {
            return index >= target && index < dragging ? rowStride : 0
        }
        return 0
    }
    
    private func performMove(fromIndex: Int) {
        if let target = targetIndex, target != fromIndex {
            onMove(IndexSet(integer: fromIndex), target)
        }
        draggingIndex = nil
        targetIndex = nil
    }
}

struct DraggableDeviceRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let device: AudioDevice
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    var onHide: ((AudioDevice) -> Void)?
    let isDragging: Bool
    var isDropTarget: Bool = false
    var isDropTargetBelow: Bool = false
    let rowHeight: CGFloat
    let rowStride: CGFloat
    let deviceCount: Int
    let onDragStarted: () -> Void
    let onTargetChanged: (Int?) -> Void
    let onDragEnded: () -> Void
    
    @State private var isHovering = false
    @State private var lastReportedTarget: Int?

    private enum Style {
        static let selectedGreen = Color(red: 48.0 / 255.0, green: 227.0 / 255.0, blue: 79.0 / 255.0)
    }

    private func calculateTarget(offset: CGFloat) -> Int? {
        let rowsOffset = Int(round(offset / rowStride))
        var newTarget = index + rowsOffset
        newTarget = max(0, min(deviceCount, newTarget))
        
        if newTarget == index || newTarget == index + 1 {
            return nil
        }
        return newTarget
    }

    var body: some View {
        Button(action: onSelect) {
            rowContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel(device.name)
        .accessibilityValue(isSelected ? "Current device" : "Available device")
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .contextMenu {
            if let onHide {
                Button {
                    onHide(device)
                } label: {
                    let deviceLabel = device.type == .input ? "microphone" : "speaker"
                    Label("Ignore \(deviceLabel)", systemImage: "eye.slash")
                }
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            ZStack {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: rowHeight)
                    .opacity(isHovering || isDragging ? 1 : 0)
                    .scaleEffect(isHovering || isDragging ? 1 : 0.8)

                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.8))
                    .opacity(isHovering || isDragging ? 0 : 1)
                    .scaleEffect(isHovering || isDragging ? 0.8 : 1)
            }
            .frame(width: 36)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.12),
                value: isDragging
            )

            HStack(spacing: 8) {
                Text(device.name)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Style.selectedGreen)
                        .font(.system(size: 15))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7),
                value: isSelected
            )

        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 3)
        .opacity(isDragging ? 0.5 : 1.0)
        .liquidGlassRowBackground(
            isActive: isSelected || isHovering || isDragging,
            isProminent: isSelected
        )
        .overlay(alignment: .top) {
            if isDropTarget {
                DropIndicatorLine()
                    .offset(y: -5)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .overlay(alignment: .bottom) {
            if isDropTargetBelow {
                DropIndicatorLine()
                    .offset(y: 5)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: LiquidGlassMetrics.controlCornerRadius)
                .stroke(isDragging ? Color.secondary : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .animation(
            reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7),
            value: isDragging
        )
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if !isDragging {
                    onDragStarted()
                }
                let newTarget = calculateTarget(offset: value.translation.height)
                if newTarget != lastReportedTarget {
                    lastReportedTarget = newTarget
                    onTargetChanged(newTarget)
                }
            }
            .onEnded { _ in
                lastReportedTarget = nil
                onDragEnded()
            }
    }
}

struct DropIndicatorLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.secondary)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(Color.secondary)
                .frame(height: 2)
        }
        .padding(.horizontal, 2)
    }
}

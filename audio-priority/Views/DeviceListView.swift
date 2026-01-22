import SwiftUI
import CoreAudio

struct DeviceListView: View {
    let devices: [AudioDevice]
    let currentDeviceId: AudioObjectID?
    let onMove: (IndexSet, Int) -> Void
    let onSelect: (AudioDevice) -> Void
    var onHide: ((AudioDevice) -> Void)?

    @State private var draggingIndex: Int? = nil
    @State private var targetIndex: Int? = nil
    
    private let baseRowHeight: CGFloat = 32
    private let rowHeightScale: CGFloat = 0.7
    private let rowHeight: CGFloat
    private let rowSpacing: CGFloat = 4

    private var rowStride: CGFloat { rowHeight + rowSpacing }
    private var indexByDeviceId: [AudioObjectID: Int] {
        Dictionary(uniqueKeysWithValues: devices.enumerated().map { ($0.element.id, $0.offset) })
    }

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
        rowHeight = baseRowHeight * rowHeightScale
    }

    var body: some View {
        let indexByDeviceId = indexByDeviceId
        VStack(spacing: rowSpacing) {
            ForEach(devices, id: \.id) { device in
                let index = indexByDeviceId[device.id] ?? 0
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
                .animation(.easeInOut(duration: 0.12), value: targetIndex)
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
    @State private var lastReportedTarget: Int? = nil

    private enum Style {
        static let selectedGreenRed: Double = 48.0 / 255.0
        static let selectedGreenGreen: Double = 227.0 / 255.0
        static let selectedGreenBlue: Double = 79.0 / 255.0
        static let selectedGreen = Color(
            red: selectedGreenRed,
            green: selectedGreenGreen,
            blue: selectedGreenBlue
        )
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
        HStack(spacing: 8) {
            ZStack {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: rowHeight)
                    .opacity(isHovering || isDragging ? 1 : 0)
                    .scaleEffect(isHovering || isDragging ? 1 : 0.8)

                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.8))
                .opacity(isHovering || isDragging ? 0 : 1)
                .scaleEffect(isHovering || isDragging ? 0.8 : 1)
            }
            .frame(width: 36)
            .animation(.easeInOut(duration: 0.12), value: isDragging)

            HStack(spacing: 8) {
                Text(device.name)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(.primary)

                Spacer(minLength: 12)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Style.selectedGreen)
                        .font(.system(size: 15))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)

        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .opacity(isDragging ? 0.5 : 1.0)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.secondary.opacity(0.12) : (isHovering ? Color.primary.opacity(0.06) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.secondary.opacity(0.8) : Color.clear, lineWidth: 1.5)
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
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isDragging ? Color.secondary : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
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
        .gesture(
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
        )
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

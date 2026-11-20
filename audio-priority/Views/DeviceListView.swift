import SwiftUI
import CoreAudio

struct DeviceListView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let devices: [AudioDevice]
    let currentDeviceId: AudioObjectID?
    let onMove: (IndexSet, Int) -> Void
    let onSelect: (AudioDevice) -> Void
    var onHide: ((AudioDevice) -> Void)?
    var onRename: ((AudioDevice, String) -> Void)?
    var onRestoreName: ((AudioDevice) -> Void)?

    @State private var draggingIndex: Int?
    @State private var targetIndex: Int?
    @State private var deviceBeingRenamed: AudioDevice?
    @State private var proposedName = ""
    @State private var isRenameDialogPresented = false

    private let rowHeight: CGFloat = 30
    private let rowSpacing: CGFloat = 2

    private var rowStride: CGFloat { rowHeight + rowSpacing }
    init(
        devices: [AudioDevice],
        currentDeviceId: AudioObjectID?,
        onMove: @escaping (IndexSet, Int) -> Void,
        onSelect: @escaping (AudioDevice) -> Void,
        onHide: ((AudioDevice) -> Void)? = nil,
        onRename: ((AudioDevice, String) -> Void)? = nil,
        onRestoreName: ((AudioDevice) -> Void)? = nil
    ) {
        self.devices = devices
        self.currentDeviceId = currentDeviceId
        self.onMove = onMove
        self.onSelect = onSelect
        self.onHide = onHide
        self.onRename = onRename
        self.onRestoreName = onRestoreName
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
                    onRename: onRename == nil ? nil : { beginRenaming(device) },
                    onRestoreName: onRestoreName,
                    onMoveUp: index > 0 ? { move(from: index, to: index - 1) } : nil,
                    onMoveDown: index < devices.count - 1 ? { move(from: index, to: index + 2) } : nil,
                    isDragging: draggingIndex == index,
                    isDropTarget: isDropTarget(for: index),
                    isDropTargetBelow: isDropTargetBelow(for: index),
                    rowHeight: rowHeight,
                    rowSpacing: rowSpacing,
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
        .alert(
            "Rename device",
            isPresented: $isRenameDialogPresented,
            presenting: deviceBeingRenamed
        ) { device in
            TextField("Device name", text: $proposedName)
            Button("Cancel", role: .cancel) {
                deviceBeingRenamed = nil
            }
            Button("Save") {
                onRename?(device, proposedName)
                deviceBeingRenamed = nil
            }
            .disabled(proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { device in
            Text("Original name: \(device.originalName)")
        }
    }

    private func beginRenaming(_ device: AudioDevice) {
        proposedName = device.name
        deviceBeingRenamed = device
        isRenameDialogPresented = true
    }

    private func move(from index: Int, to destination: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
            onMove(IndexSet(integer: index), destination)
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
    var onRename: (() -> Void)?
    var onRestoreName: ((AudioDevice) -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    let isDragging: Bool
    var isDropTarget: Bool = false
    var isDropTargetBelow: Bool = false
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let deviceCount: Int
    let onDragStarted: () -> Void
    let onTargetChanged: (Int?) -> Void
    let onDragEnded: () -> Void

    @State private var isHovering = false
    @State private var lastReportedTarget: Int?

    private var rowStride: CGFloat { rowHeight + rowSpacing }

    private var showsHandle: Bool { isHovering || isDragging }

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
        .accessibilityHint("Priority \(index + 1) of \(deviceCount)")
        .accessibilityActions {
            if let onMoveUp {
                Button("Move up", action: onMoveUp)
            }
            if let onMoveDown {
                Button("Move down", action: onMoveDown)
            }
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .contextMenu {
            deviceActions
        }
        .overlay(alignment: .trailing) {
            if isHovering && !isDragging {
                moreActionsMenu
                    .padding(.trailing, 4)
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }

    @ViewBuilder
    private var deviceActions: some View {
        if onMoveUp != nil || onMoveDown != nil {
            if let onMoveUp {
                Button(action: onMoveUp) {
                    Label("Move up", systemImage: "arrow.up")
                }
            }
            if let onMoveDown {
                Button(action: onMoveDown) {
                    Label("Move down", systemImage: "arrow.down")
                }
            }
            Divider()
        }

        if let onRename {
            Button(action: onRename) {
                Label("Rename device...", systemImage: "pencil")
            }
        }

        if device.hasCustomName, let onRestoreName {
            Button {
                onRestoreName(device)
            } label: {
                Label("Restore original name", systemImage: "arrow.counterclockwise")
            }
        }

        if onRename != nil || (device.hasCustomName && onRestoreName != nil) {
            Divider()
        }

        if let onHide {
            Button {
                onHide(device)
            } label: {
                let deviceLabel = device.type == .input ? "microphone" : "speaker"
                Label("Ignore \(deviceLabel)", systemImage: "eye.slash")
            }
        }
    }

    private var moreActionsMenu: some View {
        Menu {
            deviceActions
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: LiquidGlassMetrics.iconButtonSize, height: rowHeight)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityHidden(true)
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            PriorityBar(isActive: isSelected)

            ZStack {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .opacity(showsHandle ? 1 : 0)
                    .scaleEffect(showsHandle ? 1 : 0.8)

                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .opacity(showsHandle ? 0 : 1)
                    .scaleEffect(showsHandle ? 0.8 : 1)
            }
            .frame(width: 16)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.12),
                value: isDragging
            )

            Text(device.name)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)

            Spacer(minLength: LiquidGlassMetrics.iconButtonSize)
        }
        .padding(.horizontal, 8)
        .frame(height: rowHeight)
        .opacity(isDragging ? 0.5 : 1.0)
        .liquidGlassRowBackground(
            isActive: isHovering || isDragging,
            isProminent: isSelected
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7),
            value: isSelected
        )
        .overlay(alignment: .top) {
            if isDropTarget {
                DropIndicatorLine()
                    .alignmentGuide(.top) { $0[VerticalAlignment.center] }
                    .offset(y: -rowSpacing / 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .overlay(alignment: .bottom) {
            if isDropTargetBelow {
                DropIndicatorLine()
                    .alignmentGuide(.bottom) { $0[VerticalAlignment.center] }
                    .offset(y: rowSpacing / 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: LiquidGlassMetrics.controlCornerRadius, style: .continuous)
                .stroke(isDragging ? Color.accentColor : Color.clear, lineWidth: 1.5)
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

struct PriorityBar: View {
    let isActive: Bool

    var body: some View {
        Capsule()
            .fill(isActive ? Color.accentColor : Color.primary.opacity(0.18))
            .frame(width: 3, height: isActive ? 16 : 8)
            .accessibilityHidden(true)
    }
}

struct DropIndicatorLine: View {
    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        }
        .padding(.horizontal, 2)
    }
}

import AppKit
import SwiftUI

struct TimelineDropReceiver: NSViewRepresentable {
    let onTargeted: (Bool) -> Void
    let onDrop: (UUID, CGFloat) -> Bool
    let onScreenFrameChange: (CGRect) -> Void

    func makeNSView(context: Context) -> TimelineDropReceiverNSView {
        let view = TimelineDropReceiverNSView()
        view.onTargeted = onTargeted
        view.onDrop = onDrop
        view.onScreenFrameChange = onScreenFrameChange
        Task { @MainActor in view.reportScreenFrame() }
        return view
    }

    func updateNSView(_ nsView: TimelineDropReceiverNSView, context: Context) {
        nsView.onTargeted = onTargeted
        nsView.onDrop = onDrop
        nsView.onScreenFrameChange = onScreenFrameChange
        Task { @MainActor in nsView.reportScreenFrame() }
    }
}

final class TimelineDropReceiverNSView: NSView {
    var onTargeted: ((Bool) -> Void)?
    var onDrop: ((UUID, CGFloat) -> Bool)?
    var onScreenFrameChange: ((CGRect) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.string])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.string])
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportScreenFrame()
    }

    override func layout() {
        super.layout()
        reportScreenFrame()
    }

    func reportScreenFrame() {
        guard let window else { return }
        let windowRect = convert(bounds, to: nil)
        onScreenFrameChange?(window.convertToScreen(windowRect))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggedTaskID(from: sender) != nil else { return [] }
        onTargeted?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggedTaskID(from: sender) == nil ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargeted?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { onTargeted?(false) }
        guard let taskID = draggedTaskID(from: sender) else { return false }
        let local = convert(sender.draggingLocation, from: nil)
        let downwardY = bounds.height - local.y
        return onDrop?(taskID, downwardY) ?? false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onTargeted?(false)
    }

    private func draggedTaskID(from sender: NSDraggingInfo) -> UUID? {
        sender.draggingPasteboard.string(forType: .string).flatMap(UUID.init(uuidString:))
    }
}

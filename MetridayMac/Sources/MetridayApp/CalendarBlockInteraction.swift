import AppKit
import SwiftUI

struct CalendarBlockInteraction: NSViewRepresentable {
    let startMinute: Int
    let endMinute: Int
    let hourHeight: CGFloat
    let onSelect: () -> Void
    let onMove: (Int) -> Void
    let onResizeStart: (Int) -> Void
    let onResizeEnd: (Int) -> Void

    func makeNSView(context: Context) -> CalendarBlockInteractionNSView {
        let view = CalendarBlockInteractionNSView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: CalendarBlockInteractionNSView, context: Context) {
        update(nsView)
    }

    private func update(_ view: CalendarBlockInteractionNSView) {
        view.startMinute = startMinute
        view.endMinute = endMinute
        view.hourHeight = hourHeight
        view.onSelect = onSelect
        view.onMove = onMove
        view.onResizeStart = onResizeStart
        view.onResizeEnd = onResizeEnd
    }
}

final class CalendarBlockInteractionNSView: NSView {
    private enum Mode {
        case move
        case resizeStart
        case resizeEnd
    }

    var startMinute = 0
    var endMinute = 0
    var hourHeight: CGFloat = 64
    var onSelect: (() -> Void)?
    var onMove: ((Int) -> Void)?
    var onResizeStart: ((Int) -> Void)?
    var onResizeEnd: ((Int) -> Void)?

    private var mode: Mode?
    private var mouseDownWindowY: CGFloat = 0
    private var originStart = 0
    private var originEnd = 0

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let edgeHeight = min(12, bounds.height / 3)
        addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: edgeHeight), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: 0, y: bounds.height - edgeHeight, width: bounds.width, height: edgeHeight), cursor: .resizeUpDown)
        if bounds.height > edgeHeight * 2 {
            addCursorRect(
                NSRect(x: 0, y: edgeHeight, width: bounds.width, height: bounds.height - edgeHeight * 2),
                cursor: .openHand
            )
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let edgeHeight = min(12, bounds.height / 3)
        if point.y <= edgeHeight {
            mode = .resizeEnd
            NSCursor.resizeUpDown.set()
        } else if point.y >= bounds.height - edgeHeight {
            mode = .resizeStart
            NSCursor.resizeUpDown.set()
        } else {
            mode = .move
            NSCursor.closedHand.set()
        }
        mouseDownWindowY = event.locationInWindow.y
        originStart = startMinute
        originEnd = endMinute
        onSelect?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mode else { return }
        // AppKit's y-axis grows upward. Timeline minutes grow downward.
        let downwardPoints = mouseDownWindowY - event.locationInWindow.y
        let deltaMinutes = Int((downwardPoints / hourHeight) * 60)
        switch mode {
        case .move:
            onMove?(originStart + deltaMinutes)
        case .resizeStart:
            onResizeStart?(originStart + deltaMinutes)
        case .resizeEnd:
            onResizeEnd?(originEnd + deltaMinutes)
        }
    }

    override func mouseUp(with event: NSEvent) {
        mode = nil
        NSCursor.arrow.set()
    }
}

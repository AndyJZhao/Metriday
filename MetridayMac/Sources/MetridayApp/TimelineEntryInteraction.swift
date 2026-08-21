import AppKit
import SwiftUI

/// AppKit pointer tracking for a horizontal activity timeline entry.
///
/// SwiftUI's gesture arbitration is intentionally avoided here: the parent
/// activity timeline uses a drag gesture to create a new selection, while an
/// existing entry needs to own the pointer so its body and edges can be
/// edited without selecting a second range underneath it.
struct TimelineEntryInteraction: NSViewRepresentable {
    let pixelsPerMinute: CGFloat
    let onSelect: () -> Void
    let onMove: (Int) -> Void
    let onResizeStart: (Int) -> Void
    let onResizeEnd: (Int) -> Void

    func makeNSView(context: Context) -> TimelineEntryInteractionNSView {
        let view = TimelineEntryInteractionNSView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: TimelineEntryInteractionNSView, context: Context) {
        update(nsView)
    }

    private func update(_ view: TimelineEntryInteractionNSView) {
        view.pixelsPerMinute = pixelsPerMinute
        view.onSelect = onSelect
        view.onMove = onMove
        view.onResizeStart = onResizeStart
        view.onResizeEnd = onResizeEnd
    }
}

final class TimelineEntryInteractionNSView: NSView {
    private enum Mode {
        case move
        case resizeStart
        case resizeEnd
    }

    var pixelsPerMinute: CGFloat = 1
    var onSelect: (() -> Void)?
    var onMove: ((Int) -> Void)?
    var onResizeStart: ((Int) -> Void)?
    var onResizeEnd: ((Int) -> Void)?

    private var mode: Mode?
    private var mouseDownWindowX: CGFloat = 0
    private var didDrag = false

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let edgeWidth = min(6, max(3, bounds.width * 0.25))
        addCursorRect(
            NSRect(x: 0, y: 0, width: edgeWidth, height: bounds.height),
            cursor: .resizeLeftRight
        )
        addCursorRect(
            NSRect(x: bounds.width - edgeWidth, y: 0, width: edgeWidth, height: bounds.height),
            cursor: .resizeLeftRight
        )
        if bounds.width > edgeWidth * 2 {
            addCursorRect(
                NSRect(
                    x: edgeWidth,
                    y: 0,
                    width: bounds.width - edgeWidth * 2,
                    height: bounds.height
                ),
                cursor: .openHand
            )
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let edgeWidth = min(6, max(3, bounds.width * 0.25))
        if point.x <= edgeWidth {
            mode = .resizeStart
            NSCursor.resizeLeftRight.set()
        } else if point.x >= bounds.width - edgeWidth {
            mode = .resizeEnd
            NSCursor.resizeLeftRight.set()
        } else {
            mode = .move
            NSCursor.closedHand.set()
        }
        mouseDownWindowX = event.locationInWindow.x
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mode else { return }
        let deltaPoints = event.locationInWindow.x - mouseDownWindowX
        if abs(deltaPoints) > 2 {
            didDrag = true
        }
        let rawMinutes = deltaPoints / max(0.01, pixelsPerMinute)
        // Activity entries follow the same quarter-hour editing granularity
        // as Plan time blocks and Timing's timeline adjustments.
        let deltaMinutes = Int((rawMinutes / 15).rounded()) * 15
        switch mode {
        case .move:
            onMove?(deltaMinutes)
        case .resizeStart:
            onResizeStart?(deltaMinutes)
        case .resizeEnd:
            onResizeEnd?(deltaMinutes)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag {
            onSelect?()
        }
        mode = nil
        didDrag = false
        NSCursor.arrow.set()
    }
}

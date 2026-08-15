import AppKit
import SwiftUI

/// A real, continuous Markdown text surface. The gutter is part of the editor:
/// line numbers are informational, while the six dots next to task lines are
/// native AppKit drag sources for the calendar timeline.
struct NativeMarkdownEditor: NSViewRepresentable {
    let text: String
    let taskLineIDs: [Int: UUID]
    let taskTitles: [UUID: String]
    let selectedTaskID: UUID?
    let onTextChange: (String) -> Void
    let onSelectTask: (UUID?) -> Void
    let onToggleTask: (UUID) -> Void
    let onDragStateChange: (UUID?, Bool) -> Void
    let onDragEnded: (UUID, CGPoint, NSEvent.ModifierFlags) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MarkdownEditorContainerView {
        let container = MarkdownEditorContainerView()
        let scrollView = container.scrollView
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = MarkdownTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.string = text
        textView.taskLineIDs = taskLineIDs
        textView.taskTitles = taskTitles
        textView.selectedTaskID = selectedTaskID
        textView.onSelectTask = onSelectTask
        textView.onToggleTask = onToggleTask
        textView.onDragStateChange = onDragStateChange
        textView.onDragEnded = onDragEnded
        textView.configureForMarkdown()
        MarkdownStyler.apply(to: textView)

        let gutter = MarkdownGutterRulerView(textView: textView)
        textView.gutterRuler = gutter
        container.install(textView: textView, gutter: gutter)
        context.coordinator.textView = textView
        return container
    }

    func updateNSView(_ container: MarkdownEditorContainerView, context: Context) {
        guard let textView = container.scrollView.documentView as? MarkdownTextView else { return }
        context.coordinator.parent = self
        textView.taskLineIDs = taskLineIDs
        textView.taskTitles = taskTitles
        textView.selectedTaskID = selectedTaskID
        textView.onSelectTask = onSelectTask
        textView.onToggleTask = onToggleTask
        textView.onDragStateChange = onDragStateChange
        textView.onDragEnded = onDragEnded
        textView.gutterRuler?.needsDisplay = true

        if textView.string != text {
            let selection = textView.selectedRange()
            context.coordinator.isApplyingExternalChange = true
            textView.string = text
            textView.setSelectedRange(NSRange(
                location: min(selection.location, (text as NSString).length),
                length: 0
            ))
            context.coordinator.isApplyingExternalChange = false
        }
        MarkdownStyler.apply(to: textView)
        textView.needsDisplay = true
        container.scrollView.layoutDocumentView()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeMarkdownEditor
        weak var textView: MarkdownTextView?
        var isApplyingExternalChange = false
        var isApplyingFormatting = false

        init(parent: NativeMarkdownEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalChange, !isApplyingFormatting,
                  let textView = notification.object as? MarkdownTextView else { return }
            parent.onTextChange(textView.string)
            isApplyingFormatting = true
            MarkdownStyler.apply(to: textView)
            isApplyingFormatting = false
            textView.needsDisplay = true
            textView.gutterRuler?.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView,
                  let line = textView.lineIndex(atCharacter: textView.selectedRange().location) else { return }
            parent.onSelectTask(parent.taskLineIDs[line])
            isApplyingFormatting = true
            MarkdownStyler.apply(to: textView)
            isApplyingFormatting = false
        }
    }
}

final class MarkdownEditorContainerView: NSView {
    let scrollView = MarkdownScrollView()
    private(set) var gutterView: MarkdownGutterRulerView?

    func install(textView: MarkdownTextView, gutter: MarkdownGutterRulerView) {
        gutterView = gutter
        addSubview(gutter)
        addSubview(scrollView)
        scrollView.documentView = textView
        scrollView.onScroll = { [weak gutter] in gutter?.needsDisplay = true }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let gutterWidth: CGFloat = 48
        gutterView?.frame = NSRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
        scrollView.frame = NSRect(x: gutterWidth, y: 0, width: max(0, bounds.width - gutterWidth), height: bounds.height)
        scrollView.layoutDocumentView()
    }
}

final class MarkdownScrollView: NSScrollView {
    var onScroll: (() -> Void)?

    override func layout() {
        super.layout()
        layoutDocumentView()
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        onScroll?()
    }

    func layoutDocumentView() {
        guard let textView = documentView as? MarkdownTextView else { return }
        let viewport = contentView.bounds.size
        guard viewport.width > 1, viewport.height > 1 else { return }

        var size = textView.frame.size
        size.width = viewport.width
        textView.setFrameSize(size)
        if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            size.height = max(viewport.height, layoutManager.usedRect(for: textContainer).height + 44)
        } else {
            size.height = viewport.height
        }
        if textView.frame.size != size {
            textView.setFrameSize(size)
        }
    }
}

final class MarkdownTextView: NSTextView {
    private let gutterWidth: CGFloat = 10
    private var pendingDragTaskID: UUID?
    private var dragSessionStarted = false
    private var taskCheckboxRects: [UUID: NSRect] = [:]

    var taskLineIDs: [Int: UUID] = [:]
    var taskTitles: [UUID: String] = [:]
    var selectedTaskID: UUID?
    var onSelectTask: ((UUID?) -> Void)?
    var onToggleTask: ((UUID) -> Void)?
    var onDragStateChange: ((UUID?, Bool) -> Void)?
    var onDragEnded: ((UUID, CGPoint, NSEvent.ModifierFlags) -> Void)?
    weak var gutterRuler: MarkdownGutterRulerView?

    func configureForMarkdown() {
        // Rich layout is used only as a presentation layer. Persistence still
        // reads `string`, so the on-disk document remains plain Markdown.
        isRichText = true
        usesFontPanel = false
        allowsDocumentBackgroundColorChange = false
        importsGraphics = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticLinkDetectionEnabled = true
        isAutomaticTextReplacementEnabled = false
        isContinuousSpellCheckingEnabled = true
        allowsUndo = true
        drawsBackground = true
        backgroundColor = .white
        textColor = NSColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1)
        insertionPointColor = NSColor(red: 0.33, green: 0.36, blue: 0.91, alpha: 1)
        font = .systemFont(ofSize: 15, weight: .regular)
        textContainerInset = NSSize(width: gutterWidth, height: 22)
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 8
        paragraph.paragraphSpacing = 4
        defaultParagraphStyle = paragraph
        typingAttributes = [
            .font: NSFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: textColor ?? .textColor,
            .paragraphStyle: paragraph
        ]
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else { return super.intrinsicContentSize }
        layoutManager.ensureLayout(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: layoutManager.usedRect(for: textContainer).height + 44)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawMarkdownDecorations(in: dirtyRect)
        gutterRuler?.needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let taskID = taskCheckboxRects.first(where: { $0.value.contains(point) })?.key {
            onToggleTask?(taskID)
            onSelectTask?(taskID)
            return
        }
        if point.x < gutterWidth,
           let line = lineIndex(at: point),
           let taskID = taskLineIDs[line] {
            pendingDragTaskID = taskID
            dragSessionStarted = false
            onSelectTask?(taskID)
            NSCursor.openHand.set()
            return
        }
        pendingDragTaskID = nil
        super.mouseDown(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        let source = string as NSString
        let selection = selectedRange()
        let safeLocation = min(selection.location, source.length)
        let lineRange = source.lineRange(for: NSRange(location: safeLocation, length: 0))
        let line = source.substring(with: NSRange(
            location: lineRange.location,
            length: min(lineRange.length, max(0, source.length - lineRange.location))
        )).trimmingCharacters(in: .newlines)

        if let continuation = listContinuation(for: line) {
            if continuation.isEmpty {
                let contentRange = NSRange(location: lineRange.location, length: (line as NSString).length)
                insertText("", replacementRange: contentRange)
                super.insertNewline(sender)
            } else {
                insertText("\n\(continuation)", replacementRange: selection)
            }
            return
        }
        super.insertNewline(sender)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let taskID = pendingDragTaskID else {
            super.mouseDragged(with: event)
            return
        }
        guard !dragSessionStarted else { return }
        dragSessionStarted = true

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(taskID.uuidString, forType: .string)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let point = convert(event.locationInWindow, from: nil)
        let image = dragImage(title: taskTitles[taskID] ?? "Task")
        draggingItem.setDraggingFrame(
            NSRect(x: point.x - 12, y: point.y - image.size.height / 2, width: image.size.width, height: image.size.height),
            contents: image
        )
        onDragStateChange?(taskID, true)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        pendingDragTaskID = nil
        dragSessionStarted = false
        NSCursor.arrow.set()
        super.mouseUp(with: event)
    }

    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    override func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if let taskID = pendingDragTaskID {
            onDragEnded?(taskID, screenPoint, NSEvent.modifierFlags)
        }
        onDragStateChange?(pendingDragTaskID, false)
        pendingDragTaskID = nil
        dragSessionStarted = false
        NSCursor.arrow.set()
    }

    override func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        false
    }

    func lineIndex(atCharacter characterIndex: Int) -> Int? {
        let nsString = string as NSString
        guard nsString.length > 0 else { return 0 }
        let safeIndex = min(max(0, characterIndex), nsString.length - 1)
        return nsString.substring(to: safeIndex).reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
    }

    private func listContinuation(for line: String) -> String? {
        let taskPattern = #"^([\t ]*)[-*+]\s+\[[ xX]\]\s*(.*)$"#
        if let match = try? NSRegularExpression(pattern: taskPattern).firstMatch(
            in: line,
            range: NSRange(location: 0, length: (line as NSString).length)
        ), let indentRange = Range(match.range(at: 1), in: line), let bodyRange = Range(match.range(at: 2), in: line) {
            return line[bodyRange].trimmingCharacters(in: .whitespaces).isEmpty
                ? ""
                : "\(line[indentRange])- [ ] "
        }

        let bulletPattern = #"^([\t ]*)[-*+]\s+(.*)$"#
        if let match = try? NSRegularExpression(pattern: bulletPattern).firstMatch(
            in: line,
            range: NSRange(location: 0, length: (line as NSString).length)
        ), let indentRange = Range(match.range(at: 1), in: line), let bodyRange = Range(match.range(at: 2), in: line) {
            return line[bodyRange].trimmingCharacters(in: .whitespaces).isEmpty
                ? ""
                : "\(line[indentRange])- "
        }

        let orderedPattern = #"^([\t ]*)(\d+)\.\s+(.*)$"#
        if let match = try? NSRegularExpression(pattern: orderedPattern).firstMatch(
            in: line,
            range: NSRange(location: 0, length: (line as NSString).length)
        ), let indentRange = Range(match.range(at: 1), in: line),
           let numberRange = Range(match.range(at: 2), in: line),
           let bodyRange = Range(match.range(at: 3), in: line) {
            guard !line[bodyRange].trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
            let next = (Int(line[numberRange]) ?? 0) + 1
            return "\(line[indentRange])\(next). "
        }
        return nil
    }

    private func drawMarkdownDecorations(in dirtyRect: NSRect) {
        taskCheckboxRects.removeAll(keepingCapacity: true)
        guard let layoutManager, let textContainer else { return }
        let origin = textContainerOrigin
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let lines = string.components(separatedBy: "\n")

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, glyphRange, _ in
            let characterIndex = layoutManager.characterIndexForGlyph(at: glyphRange.location)
            guard let lineIndex = self.lineIndex(atCharacter: characterIndex), lineIndex < lines.count else { return }
            let line = lines[lineIndex].trimmingCharacters(in: .whitespaces)
            let centerY = origin.y + usedRect.midY
            guard centerY >= dirtyRect.minY - 20, centerY <= dirtyRect.maxY + 20 else { return }

            if let taskID = self.taskLineIDs[lineIndex] {
                let rect = NSRect(x: origin.x + 2, y: centerY - 6, width: 12, height: 12)
                self.taskCheckboxRects[taskID] = rect.insetBy(dx: -4, dy: -4)
                let completed = line.range(of: #"^[-*+]\s+\[[xX]\]"#, options: .regularExpression) != nil
                let color = NSColor(red: 0.33, green: 0.36, blue: 0.91, alpha: 1)
                let path = NSBezierPath(ovalIn: rect)
                if completed {
                    color.setFill()
                    path.fill()
                    let check = NSBezierPath()
                    check.move(to: NSPoint(x: rect.minX + 3, y: rect.midY))
                    check.line(to: NSPoint(x: rect.minX + 5.2, y: rect.minY + 3.2))
                    check.line(to: NSPoint(x: rect.maxX - 2.5, y: rect.maxY - 3))
                    NSColor.white.setStroke()
                    check.lineWidth = 1.4
                    check.stroke()
                } else {
                    color.setStroke()
                    path.lineWidth = 1.3
                    path.stroke()
                }
            } else if line.range(of: #"^[-*+]\s+"#, options: .regularExpression) != nil {
                NSColor(red: 0.33, green: 0.36, blue: 0.91, alpha: 0.9).setFill()
                NSBezierPath(ovalIn: NSRect(x: origin.x + 6, y: centerY - 2.2, width: 4.4, height: 4.4)).fill()
            } else if line.hasPrefix(">") {
                NSColor(red: 0.33, green: 0.36, blue: 0.91, alpha: 0.32).setFill()
                NSBezierPath(roundedRect: NSRect(x: origin.x + 5, y: origin.y + usedRect.minY, width: 2, height: usedRect.height), xRadius: 1, yRadius: 1).fill()
            }
        }
    }

    fileprivate func lineIndex(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        let origin = textContainerOrigin
        let containerPoint = NSPoint(x: max(0, origin.x + 1), y: point.y - origin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        return lineIndex(atCharacter: characterIndex)
    }

    private func drawGutter(in dirtyRect: NSRect) {
        guard let layoutManager, let textContainer else { return }
        let origin = textContainerOrigin
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let lineAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.58)
        ]

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [weak self] _, usedRect, _, glyphRange, _ in
            guard let self else { return }
            let characterIndex = layoutManager.characterIndexForGlyph(at: glyphRange.location)
            guard let lineIndex = self.lineIndex(atCharacter: characterIndex) else { return }
            let y = origin.y + usedRect.minY + 2
            guard y <= dirtyRect.maxY + 30, y >= dirtyRect.minY - 30 else { return }

            let number = "\(lineIndex + 1)" as NSString
            number.draw(in: NSRect(x: 5, y: y, width: 25, height: 16), withAttributes: lineAttributes)

            if let taskID = self.taskLineIDs[lineIndex] {
                let color = taskID == self.selectedTaskID
                    ? NSColor(red: 0.33, green: 0.36, blue: 0.91, alpha: 1)
                    : NSColor.secondaryLabelColor.withAlphaComponent(0.66)
                color.setFill()
                for row in 0..<3 {
                    for column in 0..<2 {
                        NSBezierPath(ovalIn: NSRect(
                            x: 37 + CGFloat(column) * 5,
                            y: y + 3 + CGFloat(row) * 5,
                            width: 2.5,
                            height: 2.5
                        )).fill()
                    }
                }
            }
        }
    }

    fileprivate func dragImage(title: String) -> NSImage {
        let size = NSSize(width: 220, height: 38)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.windowBackgroundColor.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 8, yRadius: 8).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: size.width - 1, height: size.height - 1), xRadius: 8, yRadius: 8).stroke()
        (title as NSString).draw(
            in: NSRect(x: 14, y: 10, width: 192, height: 18),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
        )
        image.unlockFocus()
        return image
    }
}

final class MarkdownGutterRulerView: NSView, NSDraggingSource {
    private weak var markdownTextView: MarkdownTextView?
    private var pendingDragTaskID: UUID?
    private var dragSessionStarted = false
    private var taskHitRects: [UUID: NSRect] = [:]

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    init(textView: MarkdownTextView) {
        self.markdownTextView = textView
        super.init(frame: .zero)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: NSRect) {
        super.draw(rect)
        NSColor.white.setFill()
        rect.fill()
        taskHitRects.removeAll(keepingCapacity: true)
        guard let textView = markdownTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let lineAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.62)
        ]

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, glyphRange, _ in
            let characterIndex = layoutManager.characterIndexForGlyph(at: glyphRange.location)
            guard let lineIndex = textView.lineIndex(atCharacter: characterIndex) else { return }
            let textPoint = NSPoint(x: 0, y: textView.textContainerOrigin.y + usedRect.minY)
            let gutterPoint = self.convert(textPoint, from: textView)
            guard gutterPoint.y >= rect.minY - 24, gutterPoint.y <= rect.maxY + 24 else { return }

            ("\(lineIndex + 1)" as NSString).draw(
                in: NSRect(x: 4, y: gutterPoint.y + 2, width: 22, height: 16),
                withAttributes: lineAttributes
            )

            if let taskID = textView.taskLineIDs[lineIndex] {
                self.taskHitRects[taskID] = NSRect(
                    x: 0,
                    y: gutterPoint.y - 3,
                    width: self.bounds.width,
                    height: 25
                )
                let color = taskID == textView.selectedTaskID
                    ? NSColor(red: 0.33, green: 0.36, blue: 0.91, alpha: 1)
                    : NSColor.secondaryLabelColor.withAlphaComponent(0.70)
                color.setFill()
                for row in 0..<3 {
                    for column in 0..<2 {
                        NSBezierPath(ovalIn: NSRect(
                            x: 31 + CGFloat(column) * 5,
                            y: gutterPoint.y + 4 + CGFloat(row) * 5,
                            width: 2.5,
                            height: 2.5
                        )).fill()
                    }
                }
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let textView = markdownTextView else { return }
        let gutterPoint = convert(event.locationInWindow, from: nil)
        if let taskID = taskHitRects.first(where: { $0.value.contains(gutterPoint) })?.key {
            pendingDragTaskID = taskID
            dragSessionStarted = false
            textView.onSelectTask?(taskID)
            NSCursor.openHand.set()
        } else {
            pendingDragTaskID = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard pendingDragTaskID != nil else { return }
        dragSessionStarted = true
        NSCursor.closedHand.set()
    }

    override func mouseUp(with event: NSEvent) {
        if dragSessionStarted,
           let taskID = pendingDragTaskID,
           let textView = markdownTextView {
            let screenPoint = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            textView.onDragEnded?(taskID, screenPoint, event.modifierFlags)
            textView.onDragStateChange?(taskID, false)
        }
        pendingDragTaskID = nil
        dragSessionStarted = false
        NSCursor.arrow.set()
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if let taskID = pendingDragTaskID {
            markdownTextView?.onDragEnded?(taskID, screenPoint, NSEvent.modifierFlags)
        }
        markdownTextView?.onDragStateChange?(pendingDragTaskID, false)
        pendingDragTaskID = nil
        dragSessionStarted = false
        NSCursor.arrow.set()
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        false
    }
}

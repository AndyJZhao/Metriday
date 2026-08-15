import AppKit
import Foundation

@MainActor
enum MarkdownStyler {
    private static let graphite = NSColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1)
    private static let secondary = NSColor(red: 0.43, green: 0.46, blue: 0.52, alpha: 1)
    private static let accent = NSColor(red: 0.33, green: 0.36, blue: 0.91, alpha: 1)
    private static let accentSoft = NSColor(red: 0.94, green: 0.945, blue: 1.0, alpha: 1)
    private static let headingAccent = NSColor(red: 0.48, green: 0.30, blue: 0.74, alpha: 1)

    static func apply(to textView: MarkdownTextView) {
        guard let storage = textView.textStorage else { return }
        let text = textView.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)
        let activeLocation = min(textView.selectedRange().location, text.length)
        let baseParagraph = paragraph(lineSpacing: 7, paragraphSpacing: 5)
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: graphite,
            .paragraphStyle: baseParagraph
        ]

        storage.beginEditing()
        if fullRange.length > 0 {
            storage.setAttributes(base, range: fullRange)
        }

        var location = 0
        let lines = textView.string.components(separatedBy: "\n")
        for line in lines {
            let length = (line as NSString).length
            let contentRange = NSRange(location: location, length: length)
            let paragraphLength = min(length + 1, max(0, text.length - location))
            let paragraphRange = NSRange(location: location, length: paragraphLength)
            let active = activeLocation >= location && activeLocation <= location + length
            styleBlock(
                line,
                contentRange: contentRange,
                paragraphRange: paragraphRange,
                active: active,
                storage: storage
            )
            styleInline(
                line,
                lineLocation: location,
                active: active,
                storage: storage
            )
            location += length + 1
        }
        storage.endEditing()

        textView.typingAttributes = base
        textView.needsDisplay = true
        textView.gutterRuler?.needsDisplay = true
        textView.invalidateIntrinsicContentSize()
    }

    private static func styleBlock(
        _ line: String,
        contentRange: NSRange,
        paragraphRange: NSRange,
        active: Bool,
        storage: NSTextStorage
    ) {
        guard !line.isEmpty else { return }

        if let heading = match(#"^(#{1,6})[\t ]+(.+)$"#, in: line) {
            let level = heading.range(at: 1).length
            let marker = global(heading.range(at: 1), offset: contentRange.location)
            let body = global(heading.range(at: 2), offset: contentRange.location)
            let size: CGFloat = switch level {
            case 1: 27
            case 2: 22
            case 3: 18
            default: 16
            }
            storage.addAttributes([
                .font: NSFont.systemFont(ofSize: size, weight: level <= 2 ? .bold : .semibold),
                .foregroundColor: level == 1 ? headingAccent : accent
            ], range: body)
            storage.addAttributes([
                .paragraphStyle: paragraph(lineSpacing: 7, paragraphSpacing: level == 1 ? 11 : 8)
            ], range: paragraphRange)
            styleMarker(marker, active: active, storage: storage)
            return
        }

        if let task = match(#"^([\t ]*[-*+][\t ]+\[([ xX])\][\t ]*)(.*)$"#, in: line) {
            let marker = global(task.range(at: 1), offset: contentRange.location)
            let stateRange = task.range(at: 2)
            let body = global(task.range(at: 3), offset: contentRange.location)
            storage.addAttribute(.paragraphStyle, value: paragraph(indent: 23), range: paragraphRange)
            hideMarker(marker, storage: storage)
            if stateRange.location != NSNotFound,
               (line as NSString).substring(with: stateRange).lowercased() == "x" {
                storage.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: secondary
                ], range: body)
            }
            styleTimeAndTags(in: line, lineLocation: contentRange.location, storage: storage)
            return
        }

        if let quote = match(#"^([\t ]*>[\t ]?)(.*)$"#, in: line) {
            let marker = global(quote.range(at: 1), offset: contentRange.location)
            let body = global(quote.range(at: 2), offset: contentRange.location)
            storage.addAttribute(.paragraphStyle, value: paragraph(indent: 18), range: paragraphRange)
            hideMarker(marker, storage: storage)
            storage.addAttributes([
                .font: NSFont.systemFont(ofSize: 14.5).withTraits(.italicFontMask),
                .foregroundColor: secondary
            ], range: body)
            return
        }

        if let bullet = match(#"^([\t ]*[-*+][\t ]+)(.*)$"#, in: line) {
            let marker = global(bullet.range(at: 1), offset: contentRange.location)
            storage.addAttribute(.paragraphStyle, value: paragraph(indent: 19), range: paragraphRange)
            hideMarker(marker, storage: storage)
            return
        }

        if let ordered = match(#"^([\t ]*\d+\.[\t ]+)(.*)$"#, in: line) {
            let marker = global(ordered.range(at: 1), offset: contentRange.location)
            storage.addAttributes([
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: accent
            ], range: marker)
            storage.addAttribute(.paragraphStyle, value: paragraph(indent: 7), range: paragraphRange)
        }
    }

    private static func styleInline(
        _ line: String,
        lineLocation: Int,
        active: Bool,
        storage: NSTextStorage
    ) {
        applyDelimited(
            pattern: #"\*\*([^*\n]+)\*\*"#,
            line: line,
            lineLocation: lineLocation,
            active: active,
            innerAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .bold)],
            storage: storage
        )
        applyDelimited(
            pattern: #"__([^_\n]+)__"#,
            line: line,
            lineLocation: lineLocation,
            active: active,
            innerAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .bold)],
            storage: storage
        )
        applyDelimited(
            pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#,
            line: line,
            lineLocation: lineLocation,
            active: active,
            innerAttributes: [.font: NSFont.systemFont(ofSize: 15).withTraits(.italicFontMask)],
            storage: storage
        )
        applyDelimited(
            pattern: #"~~([^~\n]+)~~"#,
            line: line,
            lineLocation: lineLocation,
            active: active,
            innerAttributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue],
            storage: storage
        )
        applyDelimited(
            pattern: #"`([^`\n]+)`"#,
            line: line,
            lineLocation: lineLocation,
            active: active,
            innerAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .backgroundColor: accentSoft
            ],
            storage: storage
        )

        guard let expression = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#) else { return }
        let lineRange = NSRange(location: 0, length: (line as NSString).length)
        for result in expression.matches(in: line, range: lineRange) {
            let full = global(result.range(at: 0), offset: lineLocation)
            let label = global(result.range(at: 1), offset: lineLocation)
            storage.addAttributes([
                .foregroundColor: accent,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: label)
            if !active {
                hideOutside(inner: label, full: full, storage: storage)
            }
        }
    }

    private static func styleTimeAndTags(in line: String, lineLocation: Int, storage: NSTextStorage) {
        for pattern in [#"\b\d{1,2}:\d{2}[\t ]*[-–—][\t ]*\d{1,2}:\d{2}\b"#, #"(?<!\w)#[\p{L}\p{N}_-]+"#] {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(location: 0, length: (line as NSString).length)
            for result in expression.matches(in: line, range: range) {
                storage.addAttributes([
                    .foregroundColor: accent,
                    .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
                ], range: global(result.range, offset: lineLocation))
            }
        }
    }

    private static func applyDelimited(
        pattern: String,
        line: String,
        lineLocation: Int,
        active: Bool,
        innerAttributes: [NSAttributedString.Key: Any],
        storage: NSTextStorage
    ) {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
        let lineRange = NSRange(location: 0, length: (line as NSString).length)
        for result in expression.matches(in: line, range: lineRange) {
            let full = global(result.range(at: 0), offset: lineLocation)
            let inner = global(result.range(at: 1), offset: lineLocation)
            storage.addAttributes(innerAttributes, range: inner)
            if !active {
                hideOutside(inner: inner, full: full, storage: storage)
            }
        }
    }

    private static func hideOutside(inner: NSRange, full: NSRange, storage: NSTextStorage) {
        let before = NSRange(location: full.location, length: max(0, inner.location - full.location))
        let innerEnd = NSMaxRange(inner)
        let after = NSRange(location: innerEnd, length: max(0, NSMaxRange(full) - innerEnd))
        hideMarker(before, storage: storage)
        hideMarker(after, storage: storage)
    }

    private static func styleMarker(_ range: NSRange, active: Bool, storage: NSTextStorage) {
        if active {
            storage.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: secondary.withAlphaComponent(0.62)
            ], range: range)
        } else {
            hideMarker(range, storage: storage)
        }
    }

    private static func hideMarker(_ range: NSRange, storage: NSTextStorage) {
        guard range.location != NSNotFound, range.length > 0 else { return }
        storage.addAttributes([
            .font: NSFont.systemFont(ofSize: 0.1),
            .foregroundColor: NSColor.clear,
            .kern: -0.1
        ], range: range)
    }

    private static func match(_ pattern: String, in line: String) -> NSTextCheckingResult? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        return expression.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length))
    }

    private static func global(_ range: NSRange, offset: Int) -> NSRange {
        guard range.location != NSNotFound else { return range }
        return NSRange(location: range.location + offset, length: range.length)
    }

    private static func paragraph(lineSpacing: CGFloat = 7, paragraphSpacing: CGFloat = 5, indent: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        return style
    }
}

private extension NSFont {
    func withTraits(_ traits: NSFontTraitMask) -> NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: traits)
    }
}

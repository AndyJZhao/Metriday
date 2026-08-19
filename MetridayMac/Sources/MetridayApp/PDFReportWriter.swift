import AppKit
import Foundation

@MainActor
enum PDFReportWriter {
    static func write(to url: URL, html: String) throws {
        guard let htmlData = html.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let attributed = try NSAttributedString(
            data: htmlData,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 1_000))
        textView.isEditable = false
        textView.drawsBackground = true
        textView.backgroundColor = .white
        textView.textStorage?.setAttributedString(attributed)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let usedHeight = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 1_000
        textView.frame.size.height = max(1_000, usedHeight + 80)
        let pdf = textView.dataWithPDF(inside: textView.bounds)
        try pdf.write(to: url, options: .atomic)
    }
}

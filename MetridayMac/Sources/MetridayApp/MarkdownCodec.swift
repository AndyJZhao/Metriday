import Foundation

struct MarkdownDocument: Equatable {
    var date: Date
    var quote: String
    var tasks: [PlanTask]
    var notes: [String]
}

enum MarkdownCodec {
    static let calendar = Calendar(identifier: .gregorian)

    static func seed(for date: Date) -> MarkdownDocument {
        MarkdownDocument(
            date: date,
            quote: "Plan deep work. Ship calm results.",
            tasks: [
                PlanTask(title: "GeneZip rebuttal experiment", tags: ["research", "important"], startMinute: 14 * 60, endMinute: 16 * 60, tone: .accent),
                PlanTask(title: "Read reviewer 2", tags: ["review"], startMinute: 16 * 60 + 15, endMinute: 17 * 60),
                PlanTask(title: "Draft response", tags: ["writing"])
            ],
            notes: [
                "Reviewer 2 asks about generalization.",
                "Compare GeneZip vs. strong baselines."
            ]
        )
    }

    static func blank(for date: Date) -> MarkdownDocument {
        MarkdownDocument(
            date: date,
            quote: "Plan the day.",
            tasks: [],
            notes: []
        )
    }

    static func parse(
        _ markdown: String,
        date: Date,
        taskIDsByLine: [Int: UUID] = [:]
    ) -> MarkdownDocument {
        var quote = "Plan deep work. Ship calm results."
        var tasks: [PlanTask] = []
        var notes: [String] = []
        var section = ""

        for (lineIndex, rawLine) in markdown.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(">") {
                quote = line.dropFirst().trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("##") {
                section = line.dropFirst(2).trimmingCharacters(in: .whitespaces).lowercased()
            } else if let task = parseTask(line, id: taskIDsByLine[lineIndex] ?? UUID()) {
                tasks.append(task)
            } else if section == "notes", line.hasPrefix("-") {
                notes.append(line.dropFirst().trimmingCharacters(in: .whitespaces))
            }
        }

        return MarkdownDocument(date: date, quote: quote, tasks: tasks, notes: notes)
    }

    static func serialize(_ document: MarkdownDocument) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, MMMM d, yyyy"

        let taskLines = document.tasks.map(serializeTask)

        let noteLines = document.notes.map { "- \($0)" }
        return ([
            "# \(formatter.string(from: document.date))",
            "> \(document.quote)",
            "",
            "## Focus"
        ] + taskLines + ["", "## Notes"] + noteLines + [""]).joined(separator: "\n")
    }

    static func taskLineIndices(in markdown: String) -> [Int] {
        markdown.components(separatedBy: .newlines).enumerated().compactMap { index, rawLine in
            parseTask(rawLine.trimmingCharacters(in: .whitespaces), id: UUID()) == nil ? nil : index
        }
    }

    static func serializeTask(_ task: PlanTask) -> String {
        var chunks = ["- [\(task.isCompleted ? "x" : " ")]" ]
        if let timeRange = task.timeRange { chunks.append(timeRange) }
        chunks.append(task.title)
        chunks.append(contentsOf: task.tags.map { "#\($0)" })
        return chunks.joined(separator: " ")
    }

    static func parseTask(_ line: String, id: UUID = UUID()) -> PlanTask? {
        let pattern = #"^[-*+]\s+\[([ xX])\]\s+(?:(\d{1,2}:\d{2}\s*[–—-]\s*\d{1,2}:\d{2})\s+)?(.+)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let stateRange = Range(match.range(at: 1), in: line),
              let bodyRange = Range(match.range(at: 3), in: line) else { return nil }

        let completed = String(line[stateRange]).lowercased() == "x"
        let body = String(line[bodyRange])
        let pieces = body.split(separator: " ").map(String.init)
        let tags = pieces.filter { $0.hasPrefix("#") }.map { String($0.dropFirst()) }
        let title = pieces.filter { !$0.hasPrefix("#") }.joined(separator: " ")

        var start: Int?
        var end: Int?
        if match.range(at: 2).location != NSNotFound,
           let timeRange = Range(match.range(at: 2), in: line),
           let parsed = TimeFormat.parseRange(String(line[timeRange])) {
            start = parsed.start
            end = parsed.end
        }

        return PlanTask(
            id: id,
            title: title,
            tags: tags,
            startMinute: start,
            endMinute: end,
            isCompleted: completed,
            tone: title.localizedCaseInsensitiveContains("GeneZip") ? .accent : .soft
        )
    }
}

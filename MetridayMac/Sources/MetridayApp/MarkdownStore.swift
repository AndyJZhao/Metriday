import Combine
import Foundation

struct MarkdownPlanArchive: Codable {
    let version: Int
    let files: [String: String]
}

private struct MarkdownTaskIdentityArchive: Codable {
    let version: Int
    let identities: [String: UUID]
}

@MainActor
final class MarkdownStore: ObservableObject {
    static let dayStart = 8 * 60
    static let dayEnd = 20 * 60

    @Published private(set) var document: MarkdownDocument
    @Published private(set) var markdown: String
    @Published private(set) var taskLineIDs: [Int: UUID]
    @Published var lastUpdatedTaskID: UUID?
    @Published var statusMessage = "Local Markdown ready"

    @Published private(set) var fileURL: URL
    private let rootDirectory: URL
    private var taskIdentities: [String: UUID]

    init(date: Date = .now, rootDirectory: URL? = nil) {
        let root = rootDirectory ?? Self.defaultRootDirectory()
        self.rootDirectory = root
        let initialFileURL = Self.fileURL(for: date, rootDirectory: root)
        self.fileURL = initialFileURL
        var identities = Self.loadTaskIdentities(rootDirectory: root)

        let loadedMarkdown: String
        if let contents = try? String(contentsOf: initialFileURL, encoding: .utf8) {
            loadedMarkdown = contents
        } else {
            loadedMarkdown = MarkdownCodec.serialize(MarkdownCodec.blank(for: date))
        }
        let initialIDs = Self.assignTaskIDs(
            in: loadedMarkdown,
            date: date,
            identities: &identities
        )
        let loadedDocument = MarkdownCodec.parse(loadedMarkdown, date: date, taskIDsByLine: initialIDs)
        self.document = loadedDocument
        self.markdown = loadedMarkdown
        self.taskLineIDs = initialIDs
        self.lastUpdatedTaskID = loadedDocument.tasks.first?.id
        self.taskIdentities = identities
        if let firstTask = loadedDocument.tasks.first,
           let range = firstTask.timeRange {
            self.statusMessage = "Markdown updated · \(range) added"
        }
        persist()
    }

    var tasks: [PlanTask] { document.tasks }
    var quote: String { document.quote }
    var notes: [String] { document.notes }
    var lineCount: Int { markdown.components(separatedBy: .newlines).count }

    func task(_ id: UUID) -> PlanTask? {
        document.tasks.first { $0.id == id }
    }

    func taskID(atLine lineIndex: Int) -> UUID? {
        taskLineIDs[lineIndex]
    }

    @discardableResult
    func load(date: Date, createIfMissing: Bool = true) -> Bool {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        let destination = Self.fileURL(for: normalizedDate, rootDirectory: rootDirectory)
        let existing = try? String(contentsOf: destination, encoding: .utf8)
        let didCreate = existing == nil

        guard existing != nil || createIfMissing else { return false }

        let raw = existing ?? MarkdownCodec.serialize(MarkdownCodec.blank(for: normalizedDate))
        var identities = Self.loadTaskIdentities(rootDirectory: rootDirectory)
        let ids = Self.assignTaskIDs(
            in: raw,
            date: normalizedDate,
            identities: &identities
        )

        fileURL = destination
        markdown = raw
        taskLineIDs = ids
        document = MarkdownCodec.parse(raw, date: normalizedDate, taskIDsByLine: ids)
        taskIdentities = identities
        lastUpdatedTaskID = document.tasks.first?.id
        statusMessage = didCreate ? "Daily Markdown created" : "Daily Markdown opened"
        persist()
        return didCreate
    }

    func fileExists(for date: Date) -> Bool {
        FileManager.default.fileExists(atPath: Self.fileURL(for: date, rootDirectory: rootDirectory).path)
    }

    /// Ensures a selected date has its own blank Markdown document without
    /// changing the currently loaded editor document.
    @discardableResult
    func ensurePlanFile(for date: Date) -> Bool {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        let destination = Self.fileURL(for: normalizedDate, rootDirectory: rootDirectory)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return false }
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let blank = MarkdownCodec.serialize(MarkdownCodec.blank(for: normalizedDate))
            try blank.write(to: destination, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    func markdown(for date: Date) -> String? {
        try? String(
            contentsOf: Self.fileURL(for: date, rootDirectory: rootDirectory),
            encoding: .utf8
        )
    }

    @discardableResult
    func replaceMarkdown(_ raw: String, for date: Date) -> Bool {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        guard normalizedDate == document.date else {
            let url = Self.fileURL(for: normalizedDate, rootDirectory: rootDirectory)
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try raw.write(to: url, atomically: true, encoding: .utf8)
                return true
            } catch {
                return false
            }
        }
        updateRawMarkdown(raw)
        return true
    }

    func exportArchiveData() throws -> Data {
        let calendarDirectory = rootDirectory.appendingPathComponent("Calendar", isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: calendarDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        var contents: [String: String] = [:]
        for url in files where url.pathExtension.lowercased() == "md" {
            guard let value = try? String(contentsOf: url, encoding: .utf8) else { continue }
            contents[url.lastPathComponent] = value
        }
        let archive = MarkdownPlanArchive(version: 1, files: contents)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    @discardableResult
    func importArchiveData(_ data: Data) throws -> Int {
        let archive = try JSONDecoder().decode(MarkdownPlanArchive.self, from: data)
        let calendarDirectory = rootDirectory.appendingPathComponent("Calendar", isDirectory: true)
        try FileManager.default.createDirectory(at: calendarDirectory, withIntermediateDirectories: true)
        var imported = 0
        for (filename, value) in archive.files {
            guard filename.range(
                of: #"^\d{4}-\d{2}-\d{2}\.md$"#,
                options: .regularExpression
            ) != nil else { continue }
            try value.write(
                to: calendarDirectory.appendingPathComponent(filename),
                atomically: true,
                encoding: .utf8
            )
            imported += 1
        }
        _ = load(date: document.date, createIfMissing: false)
        return imported
    }

    @discardableResult
    func addTask(title: String, id: UUID = UUID()) -> UUID? {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        var lines = markdown.components(separatedBy: "\n")
        let notesIndex = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).lowercased() == "## notes" }
        let insertionIndex = notesIndex ?? lines.count
        lines.insert(MarkdownCodec.serializeTask(PlanTask(id: id, title: clean)), at: insertionIndex)
        applyRawMarkdown(
            lines.joined(separator: "\n"),
            preferredIDs: [insertionIndex: id],
            message: "Task added to Markdown",
            highlight: id
        )
        return id
    }

    func updateTitle(id: UUID, title: String) {
        mutateTask(id) { $0.title = title }
        commitTaskLine(id: id, message: "Markdown saved")
    }

    func updateTags(id: UUID, tags: [String]) {
        mutateTask(id) { $0.tags = tags }
        commitTaskLine(id: id, message: "Tags updated")
    }

    func toggleCompleted(id: UUID) {
        mutateTask(id) { $0.isCompleted.toggle() }
        commitTaskLine(id: id, message: "Task state updated")
    }

    func schedule(id: UUID, start: Int, end: Int, message: String? = nil) {
        let snappedStart = Self.clampAndSnap(start, lower: Self.dayStart, upper: Self.dayEnd - 30)
        let snappedEnd = Self.clampAndSnap(max(end, snappedStart + 30), lower: snappedStart + 30, upper: Self.dayEnd)
        mutateTask(id) {
            $0.startMinute = snappedStart
            $0.endMinute = snappedEnd
        }
        commitTaskLine(
            id: id,
            message: message ?? "Markdown updated · \(TimeFormat.range(start: snappedStart, end: snappedEnd)) added"
        )
    }

    func move(id: UUID, start: Int) {
        guard let task = task(id) else { return }
        let duration = task.duration
        let snapped = Self.clampAndSnap(start, lower: Self.dayStart, upper: Self.dayEnd - duration)
        schedule(id: id, start: snapped, end: snapped + duration, message: "Markdown time moved · \(TimeFormat.range(start: snapped, end: snapped + duration))")
    }

    func resize(id: UUID, end: Int) {
        guard let task = task(id), let start = task.startMinute else { return }
        let snapped = Self.clampAndSnap(end, lower: start + 30, upper: Self.dayEnd)
        schedule(id: id, start: start, end: snapped, message: "Markdown duration updated · \(TimeFormat.range(start: start, end: snapped))")
    }

    func resizeStart(id: UUID, start: Int) {
        guard let task = task(id), let end = task.endMinute else { return }
        let snapped = Self.clampAndSnap(start, lower: Self.dayStart, upper: end - 30)
        schedule(id: id, start: snapped, end: end, message: "Markdown start updated · \(TimeFormat.range(start: snapped, end: end))")
    }

    func unschedule(id: UUID) {
        mutateTask(id) {
            $0.startMinute = nil
            $0.endMinute = nil
        }
        commitTaskLine(id: id, message: "Time removed; Markdown task preserved")
    }

    func applyTimeText(id: UUID, value: String) -> Bool {
        guard let parsed = TimeFormat.parseRange(value),
              parsed.start >= Self.dayStart,
              parsed.end <= Self.dayEnd else { return false }
        schedule(id: id, start: parsed.start, end: parsed.end)
        return true
    }

    func replaceMarkdown(_ raw: String) {
        updateRawMarkdown(raw)
    }

    func updateRawMarkdown(_ raw: String) {
        applyRawMarkdown(raw, message: "Markdown saved")
    }

    private func mutateTask(_ id: UUID, mutation: (inout PlanTask) -> Void) {
        guard let index = document.tasks.firstIndex(where: { $0.id == id }) else { return }
        mutation(&document.tasks[index])
    }

    private func commitTaskLine(id: UUID, message: String) {
        guard let lineIndex = taskLineIDs.first(where: { $0.value == id })?.key,
              lineIndex < markdown.components(separatedBy: "\n").count,
              let task = task(id) else { return }
        var lines = markdown.components(separatedBy: "\n")
        let indentation = String(lines[lineIndex].prefix { $0 == " " || $0 == "\t" })
        lines[lineIndex] = indentation + MarkdownCodec.serializeTask(task)
        applyRawMarkdown(
            lines.joined(separator: "\n"),
            preferredIDs: [lineIndex: id],
            message: message,
            highlight: id
        )
    }

    private func applyRawMarkdown(
        _ raw: String,
        preferredIDs: [Int: UUID] = [:],
        message: String,
        highlight: UUID? = nil
    ) {
        let oldTasks = Dictionary(uniqueKeysWithValues: document.tasks.map { ($0.id, $0) })
        let oldLineIDs = taskLineIDs
        let newTaskLines = MarkdownCodec.taskLineIndices(in: raw)
        var assigned = Set<UUID>()
        var newIDs: [Int: UUID] = [:]

        for line in newTaskLines {
            if let preferred = preferredIDs[line] {
                newIDs[line] = preferred
                assigned.insert(preferred)
            }
        }

        let provisional = MarkdownCodec.parse(raw, date: document.date)
        for (offset, line) in newTaskLines.enumerated() where newIDs[line] == nil {
            guard offset < provisional.tasks.count else { continue }
            let candidate = provisional.tasks[offset]
            if let match = oldTasks.values.first(where: {
                !assigned.contains($0.id) && $0.title == candidate.title
            }) {
                newIDs[line] = match.id
                assigned.insert(match.id)
            }
        }

        for line in newTaskLines where newIDs[line] == nil {
            if let existing = oldLineIDs[line], !assigned.contains(existing) {
                newIDs[line] = existing
                assigned.insert(existing)
            } else {
                let fresh = UUID()
                newIDs[line] = fresh
                assigned.insert(fresh)
            }
        }

        for key in Self.taskIdentityKeys(in: raw, date: document.date) {
            if let id = newIDs[key.line] {
                taskIdentities[key.signature] = id
                taskIdentities[key.lineKey] = id
            }
        }

        markdown = raw
        taskLineIDs = newIDs
        document = MarkdownCodec.parse(raw, date: document.date, taskIDsByLine: newIDs)
        statusMessage = message
        lastUpdatedTaskID = highlight
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
            let archive = MarkdownTaskIdentityArchive(version: 1, identities: taskIdentities)
            let data = try JSONEncoder().encode(archive)
            try data.write(to: Self.taskIdentityURL(rootDirectory: rootDirectory), options: .atomic)
        } catch {
            statusMessage = "Could not save Markdown: \(error.localizedDescription)"
        }
    }

    private static func clampAndSnap(_ minute: Int, lower: Int, upper: Int) -> Int {
        min(upper, max(lower, Int((Double(minute) / 15.0).rounded()) * 15))
    }

    private static func defaultRootDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return applicationSupport.appendingPathComponent("Metriday", isDirectory: true)
    }

    private static func fileURL(for date: Date, rootDirectory: URL) -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return rootDirectory.appendingPathComponent("Calendar", isDirectory: true)
            .appendingPathComponent("\(formatter.string(from: date)).md")
    }

    private struct TaskIdentityKey {
        let line: Int
        let signature: String
        let lineKey: String
    }

    private static func taskIdentityKeys(in raw: String, date: Date) -> [TaskIdentityKey] {
        let dateKey = dateKey(for: date)
        let lines = raw.components(separatedBy: "\n")
        var occurrences: [String: Int] = [:]
        return MarkdownCodec.taskLineIndices(in: raw).compactMap { line in
            guard line < lines.count else { return nil }
            let normalized = lines[line]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            let occurrence = occurrences[normalized, default: 0]
            occurrences[normalized] = occurrence + 1
            return TaskIdentityKey(
                line: line,
                signature: "\(dateKey)|task:\(normalized)|occurrence:\(occurrence)",
                lineKey: "\(dateKey)|line:\(line)"
            )
        }
    }

    private static func assignTaskIDs(
        in raw: String,
        date: Date,
        identities: inout [String: UUID]
    ) -> [Int: UUID] {
        var assigned = Set<UUID>()
        var result: [Int: UUID] = [:]
        for key in taskIdentityKeys(in: raw, date: date) {
            let id = identities[key.signature] ?? identities[key.lineKey] ?? UUID()
            if assigned.contains(id) {
                let replacement = UUID()
                result[key.line] = replacement
                identities[key.signature] = replacement
                identities[key.lineKey] = replacement
                assigned.insert(replacement)
            } else {
                result[key.line] = id
                identities[key.signature] = id
                identities[key.lineKey] = id
                assigned.insert(id)
            }
        }
        return result
    }

    private static func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func taskIdentityURL(rootDirectory: URL) -> URL {
        rootDirectory.appendingPathComponent("TaskIdentities.json")
    }

    private static func loadTaskIdentities(rootDirectory: URL) -> [String: UUID] {
        let url = taskIdentityURL(rootDirectory: rootDirectory)
        guard let data = try? Data(contentsOf: url),
              let archive = try? JSONDecoder().decode(MarkdownTaskIdentityArchive.self, from: data) else {
            return [:]
        }
        return archive.identities
    }
}

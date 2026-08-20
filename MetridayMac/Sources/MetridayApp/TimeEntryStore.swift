import Combine
import Foundation

enum BillingStatus: String, CaseIterable, Codable, Identifiable {
    case billable
    case notBillable
    case pending
    case billed
    case paid

    var id: Self { self }

    var label: String {
        switch self {
        case .billable:
            return "Billable"
        case .notBillable:
            return "Not billable"
        case .pending:
            return "Pending"
        case .billed:
            return "Billed"
        case .paid:
            return "Paid"
        }
    }
}

struct TimeEntry: Identifiable, Hashable, Codable {
    let id: UUID
    var projectID: UUID?
    var title: String
    var notes: String
    var start: Date
    var end: Date
    var billingStatus: BillingStatus
    var isManual: Bool
    var customFields: [String: String]

    init(
        id: UUID = UUID(),
        projectID: UUID? = nil,
        title: String,
        notes: String = "",
        start: Date,
        end: Date,
        billingStatus: BillingStatus = .billable,
        isManual: Bool = true,
        customFields: [String: String] = [:]
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.notes = notes
        self.start = start
        self.end = max(end, start.addingTimeInterval(60))
        self.billingStatus = billingStatus
        self.isManual = isManual
        self.customFields = customFields
    }

    private enum CodingKeys: String, CodingKey {
        case id, projectID, title, notes, start, end, billingStatus, isManual, customFields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        billingStatus = try container.decodeIfPresent(BillingStatus.self, forKey: .billingStatus) ?? .billable
        isManual = try container.decodeIfPresent(Bool.self, forKey: .isManual) ?? true
        customFields = try container.decodeIfPresent([String: String].self, forKey: .customFields) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(billingStatus, forKey: .billingStatus)
        try container.encode(isManual, forKey: .isManual)
        try container.encode(customFields, forKey: .customFields)
    }

    var durationSeconds: Int {
        max(1, Int(end.timeIntervalSince(start)))
    }
}

struct RunningTimer: Hashable, Codable {
    let id: UUID
    var projectID: UUID?
    var title: String
    var notes: String
    var startedAt: Date
    var estimatedDurationSeconds: Int?
    var billingStatus: BillingStatus
    var customFields: [String: String]

    init(
        id: UUID = UUID(),
        projectID: UUID? = nil,
        title: String,
        notes: String = "",
        startedAt: Date,
        estimatedDurationSeconds: Int? = nil,
        billingStatus: BillingStatus = .billable,
        customFields: [String: String] = [:]
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.notes = notes
        self.startedAt = startedAt
        self.estimatedDurationSeconds = estimatedDurationSeconds.map { max(60, $0) }
        self.billingStatus = billingStatus
        self.customFields = customFields
    }

    private enum CodingKeys: String, CodingKey {
        case id, projectID, title, notes, startedAt, estimatedDurationSeconds, billingStatus, customFields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        estimatedDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .estimatedDurationSeconds)
        billingStatus = try container.decodeIfPresent(BillingStatus.self, forKey: .billingStatus) ?? .billable
        customFields = try container.decodeIfPresent([String: String].self, forKey: .customFields) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(estimatedDurationSeconds, forKey: .estimatedDurationSeconds)
        try container.encode(billingStatus, forKey: .billingStatus)
        try container.encode(customFields, forKey: .customFields)
    }
}

struct TimeEntryArchive: Codable {
    let version: Int
    let entries: [TimeEntry]
}

private struct EntryOMaticUndoBatch {
    let created: [TimeEntry]
    let replaced: [TimeEntry]
}

@MainActor
final class TimeEntryStore: ObservableObject {
    @Published private(set) var entries: [TimeEntry]
    @Published private(set) var runningTimer: RunningTimer?
    @Published var statusMessage = "Time entries ready"
    @Published private(set) var canUndoEntryOMatic = false
    @Published private(set) var lastEntryOMaticCreationCount = 0

    private let fileURL: URL
    private var entryOMaticUndoBatch: EntryOMaticUndoBatch?

    init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? Self.defaultRootDirectory()
        self.fileURL = root.appendingPathComponent("TimeEntries.json")

        if let data = try? Data(contentsOf: fileURL),
           let payload = try? JSONDecoder.timeEntryDecoder.decode(Payload.self, from: data) {
            self.entries = payload.entries
            self.runningTimer = payload.runningTimer
        } else {
            self.entries = []
            self.runningTimer = nil
        }
    }

    func entries(for date: Date) -> [TimeEntry] {
        let calendar = Calendar.current
        return entries
            .filter { calendar.isDate($0.start, inSameDayAs: date) }
            .sorted { $0.start < $1.start }
    }

    func entries(overlapping date: Date) -> [TimeEntry] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return entries
            .filter { $0.start < dayEnd && $0.end > dayStart }
            .sorted { $0.start < $1.start }
    }

    func entries(overlapping start: Date, end: Date, excluding id: UUID? = nil) -> [TimeEntry] {
        entries
            .filter { entry in
                entry.id != id && entry.start < end && entry.end > start
            }
            .sorted { $0.start < $1.start }
    }

    var runningDurationSeconds: Int {
        guard let runningTimer else { return 0 }
        return max(0, Int(Date().timeIntervalSince(runningTimer.startedAt)))
    }

    /// Materializes the active timer as a temporary entry for live summaries
    /// and reports. It is never persisted until the timer is stopped.
    func materializedEntries(at end: Date = .now) -> [TimeEntry] {
        guard let runningTimer else { return entries }
        let liveEntry = TimeEntry(
            id: runningTimer.id,
            projectID: runningTimer.projectID,
            title: runningTimer.title,
            notes: runningTimer.notes,
            start: runningTimer.startedAt,
            end: max(end, runningTimer.startedAt.addingTimeInterval(60)),
            billingStatus: runningTimer.billingStatus,
            isManual: false,
            customFields: runningTimer.customFields
        )
        return entries + [liveEntry]
    }

    func recentTimerEntries(limit: Int = 5) -> [TimeEntry] {
        var seen: Set<String> = []
        return entries
            .filter { !$0.isManual }
            .sorted { $0.end > $1.end }
            .filter { entry in
                let key = "\(entry.projectID?.uuidString ?? "unassigned")|\(entry.title.lowercased())"
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    func exportArchiveData() throws -> Data {
        let archive = TimeEntryArchive(version: 1, entries: entries)
        return try JSONEncoder.timeEntryEncoder.encode(archive)
    }

    @discardableResult
    func importArchiveData(_ data: Data) throws -> Int {
        let archive = try JSONDecoder.timeEntryDecoder.decode(TimeEntryArchive.self, from: data)
        let existingIDs = Set(entries.map(\.id))
        let imported = archive.entries.compactMap { entry -> TimeEntry? in
            guard !existingIDs.contains(entry.id),
                  !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  entry.end > entry.start else { return nil }
            return TimeEntry(
                id: entry.id,
                projectID: entry.projectID,
                title: entry.title,
                notes: entry.notes,
                start: entry.start,
                end: entry.end,
                billingStatus: entry.billingStatus,
                isManual: entry.isManual,
                customFields: entry.customFields
            )
        }
        entries.append(contentsOf: imported)
        entries.sort { $0.start < $1.start }
        persist()
        statusMessage = "Imported \(imported.count) time entries"
        return imported.count
    }

    func addEntry(
        title rawTitle: String,
        projectID: UUID?,
        notes: String = "",
        start: Date,
        end: Date,
        billingStatus: BillingStatus = .billable,
        customFields: [String: String] = [:]
    ) -> UUID? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!title.isEmpty || projectID != nil), end > start else { return nil }
        let entry = TimeEntry(
            projectID: projectID,
            title: title,
            notes: notes,
            start: start,
            end: end,
            billingStatus: billingStatus,
            customFields: customFields
        )
        entries.append(entry)
        persist()
        statusMessage = "Time entry added · \(title)"
        return entry.id
    }

    func update(_ entry: TimeEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var normalized = entry
        normalized.title = normalized.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!normalized.title.isEmpty || normalized.projectID != nil), normalized.end > normalized.start else {
            statusMessage = "Time entry needs a title and positive duration"
            return
        }
        entries[index] = normalized
        persist()
        statusMessage = "Time entry updated"
    }

    @discardableResult
    func updateBillingStatus(for ids: Set<UUID>, to status: BillingStatus) -> Int {
        guard !ids.isEmpty else { return 0 }
        var updatedCount = 0
        for index in entries.indices where ids.contains(entries[index].id) {
            guard entries[index].billingStatus != status else { continue }
            entries[index].billingStatus = status
            updatedCount += 1
        }
        guard updatedCount > 0 else {
            statusMessage = "Billing status already \(status.label.lowercased())"
            return 0
        }
        persist()
        statusMessage = "Updated billing status for \(updatedCount) time entries"
        return updatedCount
    }

    func recordEntryOMaticCreation(created: [TimeEntry], replaced: [TimeEntry]) {
        guard !created.isEmpty else { return }
        entryOMaticUndoBatch = EntryOMaticUndoBatch(created: created, replaced: replaced)
        canUndoEntryOMatic = true
        lastEntryOMaticCreationCount = created.count
        statusMessage = "Created \(created.count) time entries · press ⌘Z to undo"
    }

    @discardableResult
    func undoEntryOMaticCreation() -> Bool {
        guard let entryOMaticUndoBatch else { return false }
        let createdIDs = Set(entryOMaticUndoBatch.created.map(\.id))
        entries.removeAll { createdIDs.contains($0.id) }
        let existingIDs = Set(entries.map(\.id))
        entries.append(contentsOf: entryOMaticUndoBatch.replaced.filter { !existingIDs.contains($0.id) })
        entries.sort { $0.start < $1.start }
        self.entryOMaticUndoBatch = nil
        canUndoEntryOMatic = false
        lastEntryOMaticCreationCount = 0
        persist()
        statusMessage = "Undid Entry-O-Matic changes"
        return true
    }

    func delete(_ entry: TimeEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
        statusMessage = "Time entry removed"
    }

    func startTimer(
        title rawTitle: String,
        projectID: UUID?,
        notes: String = "",
        startedAt: Date = .now,
        estimatedDurationSeconds: Int? = nil,
        billingStatus: BillingStatus = .billable,
        customFields: [String: String] = [:]
    ) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if runningTimer != nil {
            _ = stopTimer(at: startedAt)
        }
        runningTimer = RunningTimer(
            id: UUID(),
            projectID: projectID,
            title: title,
            notes: notes,
            startedAt: startedAt,
            estimatedDurationSeconds: estimatedDurationSeconds,
            billingStatus: billingStatus,
            customFields: customFields
        )
        persist()
        statusMessage = "Timer started · \(title)"
    }

    /// Moves a running timer's start without changing its title or project.
    /// Timing uses this for the small retroactive corrections people make
    /// after starting a timer a few minutes late.
    func adjustRunningTimerStart(by seconds: TimeInterval) {
        guard var timer = runningTimer else { return }
        let latestStart = Date().addingTimeInterval(-60)
        let proposed = timer.startedAt.addingTimeInterval(seconds)
        timer.startedAt = min(proposed, latestStart)
        runningTimer = timer
        persist()
        statusMessage = "Timer start adjusted · \(formatDuration(runningDurationSeconds))"
    }

    func moveRunningTimerStart(to date: Date) {
        guard var timer = runningTimer else { return }
        timer.startedAt = min(date, Date().addingTimeInterval(-60))
        runningTimer = timer
        persist()
        statusMessage = "Timer start adjusted · \(formatDuration(runningDurationSeconds))"
    }

    @discardableResult
    func moveRunningTimerStartToPreviousEntryBoundary() -> Bool {
        guard var timer = runningTimer else { return false }
        let boundary = entries
            .filter { $0.id != timer.id && $0.end <= Date() }
            .max { $0.end < $1.end }?
            .end
        guard let boundary else { return false }
        timer.startedAt = min(boundary, Date().addingTimeInterval(-60))
        runningTimer = timer
        persist()
        statusMessage = "Timer aligned to previous entry"
        return true
    }

    func adjustRunningTimerEstimate(by seconds: Int) {
        guard var timer = runningTimer else { return }
        let current = timer.estimatedDurationSeconds ?? runningDurationSeconds
        timer.estimatedDurationSeconds = max(60, current + seconds)
        runningTimer = timer
        persist()
        statusMessage = "Timer estimate updated"
    }

    func setRunningTimerEstimate(to seconds: Int?) {
        guard var timer = runningTimer else { return }
        timer.estimatedDurationSeconds = seconds.map { max(60, $0) }
        runningTimer = timer
        persist()
        statusMessage = seconds == nil ? "Timer estimate cleared" : "Timer estimate set"
    }

    var runningTimerRemainingSeconds: Int? {
        guard let timer = runningTimer,
              let estimatedDurationSeconds = timer.estimatedDurationSeconds else { return nil }
        return estimatedDurationSeconds - Int(Date().timeIntervalSince(timer.startedAt))
    }

    @discardableResult
    func stopTimer(at end: Date = .now) -> UUID? {
        guard let runningTimer else { return nil }
        let entry = TimeEntry(
            id: runningTimer.id,
            projectID: runningTimer.projectID,
            title: runningTimer.title,
            notes: runningTimer.notes,
            start: runningTimer.startedAt,
            end: max(end, runningTimer.startedAt.addingTimeInterval(60)),
            billingStatus: runningTimer.billingStatus,
            isManual: false,
            customFields: runningTimer.customFields
        )
        entries.append(entry)
        self.runningTimer = nil
        persist()
        statusMessage = "Timer stopped · \(formatDuration(entry.durationSeconds))"
        return entry.id
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let payload = Payload(entries: entries, runningTimer: runningTimer)
            let data = try JSONEncoder.timeEntryEncoder.encode(payload)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            statusMessage = "Could not save time entries: \(error.localizedDescription)"
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }

    private static func defaultRootDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport.appendingPathComponent("Metriday", isDirectory: true)
    }

    private struct Payload: Codable {
        let entries: [TimeEntry]
        let runningTimer: RunningTimer?
    }
}

private extension JSONEncoder {
    static var timeEntryEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var timeEntryDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

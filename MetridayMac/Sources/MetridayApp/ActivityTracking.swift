import Foundation

enum ActivityPrivacy {
    static func isPrivateBrowserContext(
        appName: String,
        windowTitle: String,
        resource: String
    ) -> Bool {
        let browser = appName.lowercased()
        guard browser.contains("safari")
            || browser.contains("chrome")
            || browser.contains("firefox")
            || browser.contains("brave") else { return false }

        let title = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let markers = ["incognito", "inprivate", "private browsing", "private window"]
        return markers.contains { title.contains($0) }
            || resource.lowercased().hasPrefix("private:")
    }
}

enum ActivityCallDetector {
    static func isCall(appName: String, bundleIdentifier: String, windowTitle: String) -> Bool {
        let app = appName.lowercased()
        let bundle = bundleIdentifier.lowercased()
        let title = windowTitle.lowercased()
        let callMarkers = [
            "google meet",
            "zoom meeting",
            "microsoft teams",
            "slack huddle",
            "video call",
            "voice call",
            "facetime",
            "zoom call",
            "teams call"
        ]
        if bundle == "com.apple.facetime" { return true }
        let knownCallApp = [
            "us.zoom.xos",
            "us.zoom.xos.enterprise",
            "com.microsoft.teams",
            "com.microsoft.teams2",
            "com.tinyspeck.slackmacgap",
            "net.whatsapp.WhatsApp",
            "com.whatsapp.WhatsApp"
        ].contains(bundle)
        let browser = app.contains("safari") || app.contains("chrome") || app.contains("firefox")
        let whatsappCall = app.contains("whatsapp") && title.contains("call")
        return (knownCallApp || browser || whatsappCall) && callMarkers.contains { title.contains($0) }
    }
}

struct CallInterval: Identifiable, Hashable {
    let id = UUID()
    let appName: String
    let windowTitle: String
    let start: Date
    let end: Date

    var durationSeconds: Int {
        max(1, Int(end.timeIntervalSince(start)))
    }
}

struct IdleInterval: Identifiable, Hashable {
    let id = UUID()
    let start: Date
    let end: Date

    var durationSeconds: Int {
        max(1, Int(end.timeIntervalSince(start)))
    }
}

struct ActivitySummary: Hashable {
    private(set) var relatedSeconds = 0
    private(set) var distractedSeconds = 0
    private(set) var otherSeconds = 0
    private(set) var idleSeconds = 0

    var relatedMinutes: Int { roundedMinutes(relatedSeconds) }
    var distractedMinutes: Int { roundedMinutes(distractedSeconds) }
    var otherMinutes: Int { roundedMinutes(otherSeconds) }
    var idleMinutes: Int { roundedMinutes(idleSeconds) }
    var relatedDurationSeconds: Int { relatedSeconds }
    var distractedDurationSeconds: Int { distractedSeconds }
    var otherDurationSeconds: Int { otherSeconds }
    var idleDurationSeconds: Int { idleSeconds }
    var activeMinutes: Int { roundedMinutes(relatedSeconds + distractedSeconds + otherSeconds) }

    var totalMinutes: Int {
        roundedMinutes(relatedSeconds + distractedSeconds + otherSeconds + idleSeconds)
    }

    var taskRelatedPercentage: Int {
        let activeSeconds = relatedSeconds + distractedSeconds + otherSeconds
        guard activeSeconds > 0 else { return 0 }
        return Int((Double(relatedSeconds) / Double(activeSeconds) * 100).rounded())
    }

    init(segments: [ActivitySegment] = []) {
        for segment in segments {
            switch segment.relevance {
            case .related:
                relatedSeconds += segment.durationSeconds
            case .distracted:
                distractedSeconds += segment.durationSeconds
            case .other:
                otherSeconds += segment.durationSeconds
            case .idle:
                idleSeconds += segment.durationSeconds
            }
        }
    }

    private func roundedMinutes(_ seconds: Int) -> Int {
        Int((Double(seconds) / 60.0).rounded())
    }
}

enum ActivityClassifier {
    static let relatedBundleIdentifiers: Set<String> = [
        "com.microsoft.VSCode",
        "com.apple.dt.Xcode",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "md.obsidian",
        "com.apple.Notes",
        "com.apple.Preview"
    ]

    static let distractedBundleIdentifiers: Set<String> = [
        "com.google.Chrome",
        "com.apple.Safari",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.operasoftware.Opera"
    ]

    static let distractedTitleTokens = [
        "youtube", "reddit", "netflix", "tiktok", "instagram", "x.com", "twitter"
    ]

    static func relevance(appName: String, bundleIdentifier: String, windowTitle: String) -> ActivityRelevance {
        let normalizedTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if distractedTitleTokens.contains(where: { normalizedTitle.contains($0) }) {
            return .distracted
        }
        if relatedBundleIdentifiers.contains(bundleIdentifier) {
            return .related
        }
        if distractedBundleIdentifiers.contains(bundleIdentifier) {
            return .distracted
        }
        return .other
    }
}

struct EntryOMaticInterval: Hashable {
    let startSecond: Int
    let endSecond: Int

    var durationSeconds: Int {
        max(1, endSecond - startSecond)
    }
}

enum EntryOMaticGenerator {
    /// Converts app-usage segments into reviewable time-entry intervals.
    /// Adjacent segments are merged when the gap between them is no larger
    /// than `maximumGapSeconds`; existing entries can then be treated as
    /// covered time and subtracted from the generated intervals.
    static func intervals(
        from segments: [ActivitySegment],
        dayStart: Date,
        existingEntries: [TimeEntry],
        minimumDurationSeconds: Int = 5 * 60,
        maximumGapSeconds: Int = 60,
        overwriteExisting: Bool = false
    ) -> [EntryOMaticInterval] {
        let minimumDuration = max(1, minimumDurationSeconds)
        let maximumGap = max(0, maximumGapSeconds)
        let dayLength = 24 * 60 * 60
        let sorted = segments
            .filter { $0.relevance != .idle && $0.endSecond > $0.startSecond }
            .map {
                EntryOMaticInterval(
                    startSecond: max(0, min(dayLength, $0.startSecond)),
                    endSecond: max(0, min(dayLength, $0.endSecond))
                )
            }
            .filter { $0.endSecond > $0.startSecond }
            .sorted {
                if $0.startSecond == $1.startSecond { return $0.endSecond < $1.endSecond }
                return $0.startSecond < $1.startSecond
            }

        guard !sorted.isEmpty else { return [] }
        var merged: [EntryOMaticInterval] = []
        for interval in sorted {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }
            if interval.startSecond <= last.endSecond + maximumGap {
                merged[merged.index(before: merged.endIndex)] = EntryOMaticInterval(
                    startSecond: last.startSecond,
                    endSecond: max(last.endSecond, interval.endSecond)
                )
            } else {
                merged.append(interval)
            }
        }
        let longEnough = merged.filter { $0.durationSeconds >= minimumDuration }
        guard !longEnough.isEmpty, !overwriteExisting else { return longEnough }

        let covered = existingEntries.compactMap { entry -> EntryOMaticInterval? in
            let start = max(0, min(dayLength, Int(floor(entry.start.timeIntervalSince(dayStart)))))
            let end = max(0, min(dayLength, Int(ceil(entry.end.timeIntervalSince(dayStart)))))
            guard end > start else { return nil }
            return EntryOMaticInterval(startSecond: start, endSecond: end)
        }
        return subtract(longEnough, coveredBy: covered)
            .filter { $0.durationSeconds >= minimumDuration }
    }

    private static func subtract(
        _ intervals: [EntryOMaticInterval],
        coveredBy covered: [EntryOMaticInterval]
    ) -> [EntryOMaticInterval] {
        guard !covered.isEmpty else { return intervals }
        var result: [EntryOMaticInterval] = []
        for interval in intervals {
            var remaining = [interval]
            for blocker in covered {
                var next: [EntryOMaticInterval] = []
                for candidate in remaining {
                    if blocker.endSecond <= candidate.startSecond || blocker.startSecond >= candidate.endSecond {
                        next.append(candidate)
                        continue
                    }
                    if candidate.startSecond < blocker.startSecond {
                        next.append(EntryOMaticInterval(
                            startSecond: candidate.startSecond,
                            endSecond: min(candidate.endSecond, blocker.startSecond)
                        ))
                    }
                    if blocker.endSecond < candidate.endSecond {
                        next.append(EntryOMaticInterval(
                            startSecond: max(candidate.startSecond, blocker.endSecond),
                            endSecond: candidate.endSecond
                        ))
                    }
                }
                remaining = next.filter { $0.endSecond > $0.startSecond }
                if remaining.isEmpty { break }
            }
            result.append(contentsOf: remaining)
        }
        return result.sorted { $0.startSecond < $1.startSecond }
    }
}

struct ActivityHistoryStore {
    let rootDirectory: URL

    private var deletionURL: URL {
        rootDirectory.appendingPathComponent("DeletedActivities.json")
    }

    init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.rootDirectory = applicationSupport.appendingPathComponent("Metriday", isDirectory: true)
                .appendingPathComponent("Activity", isDirectory: true)
        }
    }

    func load(date: Date) -> [ActivitySegment] {
        let url = fileURL(for: date)
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(ActivityHistoryPayload.self, from: data) else {
            return []
        }
        let deleted = deletedIDs(for: date)
        return Self.normalized(payload.segments).filter { !deleted.contains($0.id) }
    }

    func save(_ segments: [ActivitySegment], date: Date) throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let payload = ActivityHistoryPayload(
            version: 1,
            date: Self.dateKey(for: date),
            segments: Self.normalized(segments)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: fileURL(for: date), options: .atomic)
    }

    func fileURL(for date: Date) -> URL {
        rootDirectory.appendingPathComponent("\(Self.dateKey(for: date)).json")
    }

    /// Marks captured activities as deleted without mutating an upstream
    /// source such as Apple's read-only Screen Time database. The tombstones
    /// are kept beside the daily history so a later import cannot resurrect a
    /// record the user intentionally removed.
    func markDeleted(_ ids: Set<UUID>, date: Date) {
        guard !ids.isEmpty else { return }
        var allDeleted = loadDeletionIndex()
        let key = Self.dateKey(for: date)
        allDeleted[key, default: []].formUnion(ids)
        saveDeletionIndex(allDeleted)
    }

    func restore(_ ids: Set<UUID>, date: Date) {
        guard !ids.isEmpty else { return }
        var allDeleted = loadDeletionIndex()
        let key = Self.dateKey(for: date)
        allDeleted[key]?.subtract(ids)
        if allDeleted[key]?.isEmpty == true {
            allDeleted.removeValue(forKey: key)
        }
        saveDeletionIndex(allDeleted)
    }

    func isDeleted(_ id: UUID, date: Date) -> Bool {
        deletedIDs(for: date).contains(id)
    }

    func storedDates() -> [Date] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return files.compactMap { url in
            guard url.pathExtension == "json" else { return nil }
            return formatter.date(from: url.deletingPathExtension().lastPathComponent)
        }.sorted()
    }

    private static func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func deletedIDs(for date: Date) -> Set<UUID> {
        loadDeletionIndex()[Self.dateKey(for: date)] ?? []
    }

    private func loadDeletionIndex() -> [String: Set<UUID>] {
        guard let data = try? Data(contentsOf: deletionURL),
              let archive = try? JSONDecoder().decode(ActivityDeletionArchive.self, from: data) else {
            return [:]
        }
        return archive.idsByDate.mapValues(Set.init)
    }

    private func saveDeletionIndex(_ idsByDate: [String: Set<UUID>]) {
        do {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            let archive = ActivityDeletionArchive(
                version: 1,
                idsByDate: idsByDate.mapValues { $0.sorted { $0.uuidString < $1.uuidString } }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(archive).write(to: deletionURL, options: .atomic)
        } catch {
            // History writes are intentionally best-effort, matching the
            // existing local activity persistence behavior.
        }
    }

    private static func normalized(_ segments: [ActivitySegment]) -> [ActivitySegment] {
        let sorted = segments.sorted {
            if $0.startSecond == $1.startSecond {
                return $0.endSecond < $1.endSecond
            }
            return $0.startSecond < $1.startSecond
        }
        var result: [ActivitySegment] = []

        for var segment in sorted {
            if segment.relevance == .idle,
               segment.bundleIdentifier != "com.metriday.idle",
               segment.appName != "Idle" {
                segment.relevance = .other
            }
            guard segment.endSecond > segment.startSecond else { continue }
            if let lastIndex = result.indices.last {
                let sameActivity = result[lastIndex].appName == segment.appName
                    && result[lastIndex].bundleIdentifier == segment.bundleIdentifier
                    && result[lastIndex].deviceName == segment.deviceName
                    && result[lastIndex].windowTitle == segment.windowTitle
                    && result[lastIndex].resource == segment.resource
                    && result[lastIndex].relevance == segment.relevance
                    && result[lastIndex].projectID == segment.projectID
                if sameActivity && segment.startSecond <= result[lastIndex].endSecond + 5 {
                    result[lastIndex].endSecond = max(result[lastIndex].endSecond, segment.endSecond)
                    continue
                }
            }
            result.append(segment)
        }
        return result
    }
}

struct ActivityHistoryDayArchive: Codable {
    let date: String
    let segments: [ActivitySegment]
    let deletedIDs: [UUID]

    init(date: String, segments: [ActivitySegment], deletedIDs: [UUID] = []) {
        self.date = date
        self.segments = segments
        self.deletedIDs = deletedIDs
    }

    private enum CodingKeys: String, CodingKey {
        case date, segments, deletedIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        segments = try container.decode([ActivitySegment].self, forKey: .segments)
        deletedIDs = try container.decodeIfPresent([UUID].self, forKey: .deletedIDs) ?? []
    }
}

struct ActivityHistoryArchive: Codable {
    let version: Int
    let days: [ActivityHistoryDayArchive]
}

extension ActivityHistoryStore {
    func exportArchiveData() throws -> Data {
        let archive = ActivityHistoryArchive(
            version: 1,
            days: storedDates().map { date in
                ActivityHistoryDayArchive(
                    date: Self.dateKey(for: date),
                    segments: load(date: date),
                    deletedIDs: Array(deletedIDs(for: date)).sorted { $0.uuidString < $1.uuidString }
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    @discardableResult
    func importArchiveData(_ data: Data) throws -> Int {
        let archive = try JSONDecoder().decode(ActivityHistoryArchive.self, from: data)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        var importedSegments = 0

        for day in archive.days {
            guard let date = formatter.date(from: day.date) else { continue }
            markDeleted(Set(day.deletedIDs), date: date)
            var merged = Dictionary(uniqueKeysWithValues: load(date: date).map { ($0.id, $0) })
            for segment in day.segments {
                if merged[segment.id] == nil { importedSegments += 1 }
                merged[segment.id] = segment
            }
            try save(Array(merged.values), date: date)
        }
        return importedSegments
    }
}

private struct ActivityHistoryPayload: Codable {
    let version: Int
    let date: String
    let segments: [ActivitySegment]
}

private struct ActivityDeletionArchive: Codable {
    let version: Int
    let idsByDate: [String: [UUID]]
}

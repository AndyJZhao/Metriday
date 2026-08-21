import AppKit
import Combine
import Foundation
import SQLite3

/// Imports Apple's Screen Time app-usage stream as ordinary, archived
/// ActivitySegments. The database is read-only; the imported records can be
/// assigned to projects and remain available after Apple's short retention
/// window expires.
@MainActor
final class ScreenTimeStore: ObservableObject {
    @Published private(set) var segments: [ActivitySegment] = []
    @Published private(set) var databaseAvailable = false
    @Published private(set) var statusMessage = "Screen Time integration not connected"

    private let databaseURL: URL
    private let history: ActivityHistoryStore
    private var selectedDate = Calendar.current.startOfDay(for: .now)
    private var wrapAtMinute = 0

    init(databaseURL: URL? = nil, archiveRootDirectory: URL? = nil) {
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL()
        let archiveRoot = archiveRootDirectory ?? Self.defaultArchiveDirectory()
        self.history = ActivityHistoryStore(rootDirectory: archiveRoot)
    }

    func load(for date: Date, wrapAtMinute: Int = 0) {
        selectedDate = Calendar.current.startOfDay(for: date)
        self.wrapAtMinute = TrackingDay.clampedWrapMinute(wrapAtMinute)
        let archived = history.load(date: selectedDate, wrapAtMinute: self.wrapAtMinute)

        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            databaseAvailable = false
            segments = archived
            statusMessage = archived.isEmpty
                ? "Screen Time database not found"
                : "Showing \(archived.count) archived Screen Time activities"
            return
        }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            if database != nil { sqlite3_close(database) }
            databaseAvailable = false
            segments = archived
            statusMessage = "Full Disk Access is required to read Screen Time"
            return
        }
        defer { sqlite3_close(database) }

        guard let columns = tableColumns(database, table: "ZOBJECT"),
              let startColumn = firstColumn(in: columns, candidates: ["ZSTARTDATE", "ZSTART"]),
              let streamColumn = firstColumn(in: columns, candidates: ["ZSTREAMNAME", "ZSTREAM"]) else {
            databaseAvailable = true
            segments = archived
            statusMessage = "Screen Time schema is not available"
            return
        }

        let endColumn = firstColumn(in: columns, candidates: ["ZENDDATE", "ZEND"])
        let valueColumn = firstColumn(
            in: columns,
            candidates: ["ZVALUESTRING", "ZVALUE", "ZTITLE", "ZNAME"]
        )
        let idColumn = firstColumn(in: columns, candidates: ["Z_PK", "ZID", "ZUUIDHASH"])
        let idExpression = idColumn.map(quotedIdentifier) ?? quotedIdentifier(startColumn)
        let startExpression = quotedIdentifier(startColumn)
        let endExpression = endColumn.map(quotedIdentifier) ?? "NULL"
        let valueExpression = valueColumn.map(quotedIdentifier) ?? "NULL"
        let streamExpression = quotedIdentifier(streamColumn)
        let query = """
        SELECT \(idExpression), \(startExpression), \(endExpression), \(valueExpression), \(streamExpression)
        FROM ZOBJECT
        WHERE \(streamExpression) IN ('/app/usage', '/app/inFocus', '/app/activity', '/app/webUsage')
        ORDER BY \(startExpression) ASC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            databaseAvailable = true
            segments = archived
            statusMessage = "Screen Time could not be read"
            return
        }
        defer { sqlite3_finalize(statement) }

        let calendar = Calendar.current
        let dayRange = TrackingDay.range(
            for: selectedDate,
            wrapAtMinute: self.wrapAtMinute,
            calendar: calendar
        )
        let dayStart = dayRange.start
        let dayEnd = dayRange.end
        var imported: [ActivitySegment] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let start = dateValue(statement, index: 1) else { continue }
            let rawEnd = dateValue(statement, index: 2)
            let end = max(
                start.addingTimeInterval(60),
                rawEnd ?? start.addingTimeInterval(60)
            )
            guard start < dayEnd && end > dayStart else { continue }

            let clippedStart = max(start, dayStart)
            let clippedEnd = min(end, dayEnd)
            let startSecond = TrackingDay.axisSeconds(
                for: clippedStart,
                logicalDayLabel: selectedDate,
                wrapAtMinute: self.wrapAtMinute,
                calendar: calendar
            )
            let endSecond = TrackingDay.axisSeconds(
                for: clippedEnd,
                logicalDayLabel: selectedDate,
                wrapAtMinute: self.wrapAtMinute,
                calendar: calendar
            )
            guard endSecond > startSecond else { continue }

            let value = textValue(statement, index: 3)
            let stream = textValue(statement, index: 4)
            let resource = value.hasPrefix("http://") || value.hasPrefix("https://") ? value : ""
            let bundleIdentifier = resource.isEmpty ? value : ""
            let appName = displayName(for: bundleIdentifier.isEmpty ? value : bundleIdentifier, stream: stream)
            let windowTitle = resource.isEmpty ? appName : (URL(string: resource)?.host ?? resource)
            let relevance = ActivityClassifier.relevance(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                windowTitle: windowTitle,
                resource: resource
            )
            let rawID = textValue(statement, index: 0)
            let stableKey = "\(rawID)|\(start.timeIntervalSinceReferenceDate)|\(value)|\(stream)"
            imported.append(
                ActivitySegment(
                    id: stableID(for: stableKey),
                    appName: appName,
                    bundleIdentifier: bundleIdentifier,
                    deviceName: "Screen Time",
                    windowTitle: windowTitle,
                    resource: resource,
                    startMinute: startSecond / 60,
                    endMinute: Int(ceil(Double(endSecond) / 60.0)),
                    startSecond: startSecond,
                    endSecond: endSecond,
                    relevance: relevance
                )
            )
        }

        databaseAvailable = true
        segments = merged(archived: archived, imported: imported)
            .filter { !history.isDeleted($0.id, date: selectedDate) }
        try? history.save(segments, date: selectedDate, wrapAtMinute: self.wrapAtMinute)
        statusMessage = imported.isEmpty
            ? (segments.isEmpty ? "No Screen Time activities for this day" : "Showing \(segments.count) archived Screen Time activities")
            : "Imported \(imported.count) Screen Time activities"
    }

    func contains(_ id: UUID) -> Bool {
        segments.contains { $0.id == id }
    }

    func segments(for date: Date) -> [ActivitySegment] {
        let normalized = Calendar.current.startOfDay(for: date)
        return normalized == selectedDate ? segments : history.load(date: normalized, wrapAtMinute: self.wrapAtMinute)
    }

    func exportArchiveData() throws -> Data {
        try history.exportArchiveData()
    }

    @discardableResult
    func importArchiveData(_ data: Data) throws -> Int {
        let imported = try history.importArchiveData(data)
        segments = history.load(date: selectedDate, wrapAtMinute: self.wrapAtMinute)
        return imported
    }

    func assignActivity(_ id: UUID, to projectID: UUID?, date: Date? = nil) {
        let targetDate = Calendar.current.startOfDay(for: date ?? selectedDate)
        if targetDate == selectedDate {
            guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
            segments[index].projectID = projectID
            try? history.save(segments, date: selectedDate, wrapAtMinute: self.wrapAtMinute)
            return
        }
        var historicalSegments = history.load(date: targetDate, wrapAtMinute: self.wrapAtMinute)
        guard let index = historicalSegments.firstIndex(where: { $0.id == id }) else { return }
        historicalSegments[index].projectID = projectID
        try? history.save(historicalSegments, date: targetDate, wrapAtMinute: self.wrapAtMinute)
    }

    @discardableResult
    func deleteActivities(_ ids: Set<UUID>, date: Date? = nil) -> [ActivitySegment] {
        guard !ids.isEmpty else { return [] }
        let targetDate = Calendar.current.startOfDay(for: date ?? selectedDate)
        let historicalSegments = history.load(date: targetDate, wrapAtMinute: self.wrapAtMinute)
        let deleted = historicalSegments.filter { ids.contains($0.id) }
        guard !deleted.isEmpty else { return [] }
        let deletedIDs = Set(deleted.map(\.id))
        history.markDeleted(deletedIDs, date: targetDate)
        try? history.save(historicalSegments.filter { !deletedIDs.contains($0.id) }, date: targetDate, wrapAtMinute: self.wrapAtMinute)
        if targetDate == selectedDate {
            segments.removeAll { deletedIDs.contains($0.id) }
        }
        return deleted
    }

    func restoreActivities(_ restored: [ActivitySegment], date: Date? = nil) {
        guard !restored.isEmpty else { return }
        let targetDate = Calendar.current.startOfDay(for: date ?? selectedDate)
        let ids = Set(restored.map(\.id))
        history.restore(ids, date: targetDate)
        var merged = Dictionary(uniqueKeysWithValues: history.load(date: targetDate, wrapAtMinute: self.wrapAtMinute).map { ($0.id, $0) })
        for segment in restored { merged[segment.id] = segment }
        try? history.save(Array(merged.values), date: targetDate, wrapAtMinute: self.wrapAtMinute)
        if targetDate == selectedDate {
            segments = history.load(date: targetDate, wrapAtMinute: self.wrapAtMinute)
        }
    }

    func openAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
        statusMessage = "Grant Full Disk Access, then refresh Screen Time"
    }

    private func merged(
        archived: [ActivitySegment],
        imported: [ActivitySegment]
    ) -> [ActivitySegment] {
        var byID = Dictionary(uniqueKeysWithValues: archived.map { ($0.id, $0) })
        for segment in imported {
            if let existing = byID[segment.id], let projectID = existing.projectID {
                var preserved = segment
                preserved.projectID = projectID
                byID[segment.id] = preserved
            } else {
                byID[segment.id] = segment
            }
        }
        return byID.values.sorted {
            if $0.startSecond == $1.startSecond { return $0.endSecond < $1.endSecond }
            return $0.startSecond < $1.startSecond
        }
    }

    private func displayName(for value: String, stream: String) -> String {
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return "Mobile Safari"
        }
        let knownNames: [String: String] = [
            "com.apple.Safari": "Safari",
            "com.google.Chrome": "Google Chrome",
            "com.apple.MobileSMS": "Messages",
            "com.apple.Preferences": "Settings",
            "com.apple.mobilesafari": "Safari"
        ]
        if let known = knownNames[value] { return known }
        if value.isEmpty { return stream == "/app/webUsage" ? "Mobile Safari" : "Screen Time activity" }
        if value.contains(".") {
            return value.split(separator: ".").last.map(String.init) ?? value
        }
        return value
    }

    private func tableColumns(_ database: OpaquePointer, table: String) -> Set<String>? {
        var statement: OpaquePointer?
        let query = "PRAGMA table_info(\(quotedIdentifier(table)))"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }

        var columns = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            let name = textValue(statement, index: 1)
            if !name.isEmpty { columns.insert(name.uppercased()) }
        }
        return columns.isEmpty ? nil : columns
    }

    private func firstColumn(in columns: Set<String>, candidates: [String]) -> String? {
        candidates.first { columns.contains($0.uppercased()) }
    }

    private func quotedIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func textValue(_ statement: OpaquePointer, index: Int32) -> String {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func numericValue(_ statement: OpaquePointer, index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    private func dateValue(_ statement: OpaquePointer, index: Int32) -> Date? {
        guard let value = numericValue(statement, index: index) else { return nil }
        if value > 1_000_000_000 {
            return Date(timeIntervalSince1970: value)
        }
        return Date(timeIntervalSinceReferenceDate: value)
    }

    private func stableID(for value: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in value.utf8.enumerated() {
            let slot = index % 16
            bytes[slot] = bytes[slot] &+ byte &+ UInt8(index & 0xff)
            bytes[(slot * 5 + 3) % 16] ^= byte
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func defaultDatabaseURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Knowledge/knowledgeC.db")
    }

    private static func defaultArchiveDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport
            .appendingPathComponent("Metriday", isDirectory: true)
            .appendingPathComponent("ScreenTime", isDirectory: true)
    }
}

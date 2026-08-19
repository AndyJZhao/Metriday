import Combine
import AppKit
import Foundation
import SQLite3

struct PhoneCallItem: Identifiable, Hashable {
    let id: String
    let address: String
    let serviceProvider: String
    let start: Date
    let durationSeconds: Int

    var end: Date {
        start.addingTimeInterval(TimeInterval(max(60, durationSeconds)))
    }

    var title: String {
        let cleanedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedAddress.isEmpty ? "Phone call" : "Call · \(cleanedAddress)"
    }

    var isPointInTime: Bool { durationSeconds <= 0 }
}

@MainActor
final class PhoneCallStore: ObservableObject {
    @Published private(set) var calls: [PhoneCallItem] = []
    @Published private(set) var databaseAvailable = false
    @Published private(set) var statusMessage = "Phone Calls integration not connected"
    @Published private(set) var hiddenAddresses: Set<String>

    private let databaseURL: URL
    private let preferencesURL: URL
    private var selectedDate = Calendar.current.startOfDay(for: .now)

    init(databaseURL: URL? = nil, rootDirectory: URL? = nil) {
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL()
        let root = rootDirectory ?? Self.defaultRootDirectory()
        self.preferencesURL = root.appendingPathComponent("PhoneCallPreferences.json")
        self.hiddenAddresses = Self.loadPreferences(from: preferencesURL)?.hiddenAddresses ?? []
    }

    func loadCalls(for date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        calls = []

        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            databaseAvailable = false
            statusMessage = "Call history database not found"
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
            statusMessage = "Full Disk Access is required to read call history"
            return
        }
        defer { sqlite3_close(database) }

        guard let columns = tableColumns(database, table: "ZCALLRECORD"),
              let dateColumn = firstColumn(in: columns, candidates: ["ZDATE", "ZSTARTDATE", "ZTIMESTAMP"]) else {
            databaseAvailable = true
            statusMessage = "Call history schema is not available"
            return
        }

        databaseAvailable = true
        let durationColumn = firstColumn(in: columns, candidates: ["ZDURATION", "ZDURATIONSECONDS"])
        let addressColumn = firstColumn(in: columns, candidates: ["ZADDRESS", "ZPHONE", "ZHANDLE"])
        let serviceColumn = firstColumn(in: columns, candidates: ["ZSERVICE_PROVIDER", "ZSERVICEPROVIDER", "ZPROVIDER"])
        let primaryKeyColumn = firstColumn(in: columns, candidates: ["Z_PK", "ZID"])

        let dateExpression = quotedIdentifier(dateColumn)
        let durationExpression = durationColumn.map(quotedIdentifier) ?? "NULL"
        let addressExpression = addressColumn.map(quotedIdentifier) ?? "NULL"
        let serviceExpression = serviceColumn.map(quotedIdentifier) ?? "NULL"
        let idExpression = primaryKeyColumn.map(quotedIdentifier) ?? dateExpression
        let query = """
        SELECT \(idExpression), \(dateExpression), \(durationExpression), \(addressExpression), \(serviceExpression)
        FROM ZCALLRECORD
        WHERE \(dateExpression) IS NOT NULL
        ORDER BY \(dateExpression) ASC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            statusMessage = "Call history could not be read"
            return
        }
        defer { sqlite3_finalize(statement) }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
        var mapped: [PhoneCallItem] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let start = dateValue(statement, index: 1) else { continue }
            let duration = max(0, numericValue(statement, index: 2).map(Int.init) ?? 0)
            let end = start.addingTimeInterval(TimeInterval(max(60, duration)))
            guard start < dayEnd && end > dayStart else { continue }

            let rawID = textValue(statement, index: 0)
            let id = rawID.isEmpty ? "\(start.timeIntervalSinceReferenceDate)-\(mapped.count)" : rawID
            let call = PhoneCallItem(
                    id: id,
                    address: textValue(statement, index: 3),
                    serviceProvider: textValue(statement, index: 4),
                    start: start,
                    durationSeconds: duration
                )
            guard !isAddressHidden(call.address) else { continue }
            mapped.append(call)
        }

        calls = mapped.sorted { $0.start < $1.start }
        statusMessage = calls.isEmpty
            ? "No phone calls for this day"
            : "Phone Calls ready · \(calls.count) calls"
    }

    func calls(for date: Date) -> [PhoneCallItem] {
        guard !Calendar.current.isDate(date, inSameDayAs: selectedDate) else { return calls }
        let previousDate = selectedDate
        loadCalls(for: date)
        let requestedCalls = calls
        loadCalls(for: previousDate)
        return requestedCalls
    }

    func setAddressHidden(_ address: String, hidden: Bool) {
        let normalized = Self.normalizedAddress(address)
        guard !normalized.isEmpty else { return }
        if hidden {
            hiddenAddresses.insert(normalized)
        } else {
            hiddenAddresses.remove(normalized)
        }
        persistPreferences()
        if hidden {
            calls.removeAll { Self.normalizedAddress($0.address) == normalized }
        } else {
            loadCalls(for: selectedDate)
        }
        statusMessage = hidden
            ? "Calls from this number are hidden"
            : "Calls from this number are visible"
    }

    func showAllAddresses() {
        guard !hiddenAddresses.isEmpty else { return }
        hiddenAddresses.removeAll()
        persistPreferences()
        loadCalls(for: selectedDate)
    }

    func isAddressHidden(_ address: String) -> Bool {
        hiddenAddresses.contains(Self.normalizedAddress(address))
    }

    func openAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
        statusMessage = "Grant Full Disk Access, then refresh call history"
    }

    private static func defaultDatabaseURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CallHistoryDB/CallHistory.storedata")
    }

    private static func defaultRootDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport.appendingPathComponent("Metriday", isDirectory: true)
    }

    private static func normalizedAddress(_ address: String) -> String {
        address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func persistPreferences() {
        let preferences = PhoneCallPreferences(hiddenAddresses: hiddenAddresses)
        do {
            try FileManager.default.createDirectory(
                at: preferencesURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(preferences).write(to: preferencesURL, options: .atomic)
        } catch {
            statusMessage = "Phone Calls preferences could not be saved"
        }
    }

    private static func loadPreferences(from url: URL) -> PhoneCallPreferences? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PhoneCallPreferences.self, from: data)
    }

    private struct PhoneCallPreferences: Codable {
        let hiddenAddresses: Set<String>
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
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        if sqlite3_column_type(statement, index) == SQLITE_TEXT {
            let raw = textValue(statement, index: index)
            if let date = ISO8601DateFormatter().date(from: raw) { return date }
            return nil
        }
        let value = sqlite3_column_double(statement, index)
        if value > 1_000_000_000 {
            return Date(timeIntervalSince1970: value)
        }
        return Date(timeIntervalSinceReferenceDate: value)
    }
}

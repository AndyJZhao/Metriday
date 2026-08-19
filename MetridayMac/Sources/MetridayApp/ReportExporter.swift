import Foundation

enum ReportIncludeMode: String, CaseIterable, Identifiable {
    case appUsage
    case timeEntries
    case both

    var id: Self { self }

    var label: String {
        switch self {
        case .appUsage:
            return "App usage only"
        case .timeEntries:
            return "Time entries only"
        case .both:
            return "App usage + time entries"
        }
    }
}

enum ReportGroupBy: String, CaseIterable, Identifiable {
    case none
    case day
    case weekAndDay
    case week
    case month
    case year
    case hour
    case project
    case topLevelProject
    case secondLevelProject
    case projectHierarchy
    case application
    case document

    var id: Self { self }

    var label: String {
        switch self {
        case .none:
            return "Exact entries"
        case .day:
            return "Day"
        case .weekAndDay:
            return "Week + Day"
        case .week:
            return "Week"
        case .month:
            return "Month"
        case .year:
            return "Year"
        case .hour:
            return "Hour"
        case .project:
            return "Project"
        case .topLevelProject:
            return "Top-level Project"
        case .secondLevelProject:
            return "Second-level Project"
        case .projectHierarchy:
            return "Project (Hierarchical)"
        case .application:
            return "Application"
        case .document:
            return "Document / Website"
        }
    }
}

enum ReportBillingFilter: String, CaseIterable, Identifiable {
    case all
    case billable
    case notBillable
    case pending
    case billed
    case paid

    var id: Self { self }

    var label: String {
        switch self {
        case .all:
            return "All statuses"
        case .billable:
            return BillingStatus.billable.label
        case .notBillable:
            return BillingStatus.notBillable.label
        case .pending:
            return BillingStatus.pending.label
        case .billed:
            return BillingStatus.billed.label
        case .paid:
            return BillingStatus.paid.label
        }
    }

    func matches(_ status: BillingStatus) -> Bool {
        switch self {
        case .all:
            return true
        case .billable:
            return status == .billable
        case .notBillable:
            return status == .notBillable
        case .pending:
            return status == .pending
        case .billed:
            return status == .billed
        case .paid:
            return status == .paid
        }
    }
}

enum ReportRoundingMode: String, CaseIterable, Identifiable {
    case none
    case up
    case down
    case nearest

    var id: Self { self }

    var label: String {
        switch self {
        case .none:
            return "No rounding"
        case .up:
            return "Round up"
        case .down:
            return "Round down"
        case .nearest:
            return "Round to nearest"
        }
    }
}

enum ReportDurationFormat: String, CaseIterable, Identifiable {
    case decimalMinutes
    case hms
    case human
    case seconds
    case decimalHours

    var id: Self { self }

    var label: String {
        switch self {
        case .decimalMinutes:
            return "Fractional minutes"
        case .hms:
            return "HH:MM:SS"
        case .human:
            return "Xh Ym Zs"
        case .seconds:
            return "Fractional seconds"
        case .decimalHours:
            return "Fractional hours"
        }
    }
}

enum ReportFileFormat: String, CaseIterable, Identifiable {
    case csv
    case xlsx
    case json
    case html
    case pdf

    var id: Self { self }

    var label: String {
        switch self {
        case .csv:
            return "CSV"
        case .xlsx:
            return "Excel (XLSX)"
        case .json:
            return "JSON"
        case .html:
            return "HTML"
        case .pdf:
            return "PDF / Print"
        }
    }

    var fileExtension: String { rawValue }
}

enum ReportColumn: String, CaseIterable, Hashable, Identifiable {
    case date
    case type
    case project
    case group
    case application
    case title
    case device
    case resource
    case start
    case end
    case duration
    case billingStatus
    case billingAmount
    case notes

    var id: Self { self }

    var label: String {
        switch self {
        case .date: return "Date"
        case .type: return "Type"
        case .project: return "Project"
        case .group: return "Group"
        case .application: return "Application"
        case .title: return "Title"
        case .device: return "Device"
        case .resource: return "URL or Path"
        case .start: return "Start"
        case .end: return "End"
        case .duration: return "Duration"
        case .billingStatus: return "Billing Status"
        case .billingAmount: return "Amount"
        case .notes: return "Notes"
        }
    }
}

enum ReportPreset: String, CaseIterable, Identifiable {
    case custom
    case timesheet
    case timesheetWeekDay
    case weeklySnippet
    case timePerProject
    case timePerApplication
    case timePerDocument
    case ultraDetailed
    case rawTimeEntries
    case rawAppUsage

    var id: Self { self }

    var label: String {
        switch self {
        case .custom:
            return "Custom"
        case .timesheet:
            return "Timesheet"
        case .timesheetWeekDay:
            return "Timesheet (Week + Day)"
        case .weeklySnippet:
            return "Weekly Snippet"
        case .timePerProject:
            return "Time Per Project"
        case .timePerApplication:
            return "Time Per Application"
        case .timePerDocument:
            return "Time Per Document"
        case .ultraDetailed:
            return "Ultra-Detailed"
        case .rawTimeEntries:
            return "Raw Time Entries"
        case .rawAppUsage:
            return "Raw App Usage"
        }
    }
}

struct ReportOptions: Hashable {
    var include: ReportIncludeMode = .both
    var groupBy: ReportGroupBy = .none
    var billingFilter: ReportBillingFilter = .all
    var rounding: ReportRoundingMode = .none
    var roundingMinutes = 15
    var durationFormat: ReportDurationFormat = .decimalMinutes
    var columns: Set<ReportColumn> = Set(ReportColumn.allCases)
    var roundIndividualEntries = true
    var includeCoveredAppUsage = false
    var includeShortEntries = true
    var projectIDs: Set<UUID> = []

    var includeNotes: Bool {
        get { columns.contains(.notes) }
        set { setColumn(.notes, enabled: newValue) }
    }

    var includeBillingStatus: Bool {
        get { columns.contains(.billingStatus) }
        set { setColumn(.billingStatus, enabled: newValue) }
    }

    var includeBillingAmount: Bool {
        get { columns.contains(.billingAmount) }
        set { setColumn(.billingAmount, enabled: newValue) }
    }

    private mutating func setColumn(_ column: ReportColumn, enabled: Bool) {
        if enabled { columns.insert(column) } else { columns.remove(column) }
    }
}

struct ReportRecord: Codable, Hashable {
    let date: String
    let device: String
    let type: String
    let group: String
    let project: String
    let application: String
    let title: String
    let resource: String
    let start: String
    let end: String
    let durationSeconds: Int
    let billingStatus: String
    let hourlyRate: Double
    let billingAmount: Double
    let currency: String
    let notes: String
}

@MainActor
enum ReportExporter {
    static func csv(
        activityDays: [(date: Date, segments: [ActivitySegment])],
        timeEntries: [TimeEntry],
        projectStore: ProjectStore,
        options: ReportOptions = ReportOptions()
    ) -> String {
        tableRows(
            activityDays: activityDays,
            timeEntries: timeEntries,
            projectStore: projectStore,
            options: options
        ).map { row in row.map(escape).joined(separator: ",") }
            .joined(separator: "\n") + "\n"
    }

    static func json(
        activityDays: [(date: Date, segments: [ActivitySegment])],
        timeEntries: [TimeEntry],
        projectStore: ProjectStore,
        options: ReportOptions = ReportOptions()
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(records(
            activityDays: activityDays,
            timeEntries: timeEntries,
            projectStore: projectStore,
            options: options
        ))
    }

    static func html(
        activityDays: [(date: Date, segments: [ActivitySegment])],
        timeEntries: [TimeEntry],
        projectStore: ProjectStore,
        options: ReportOptions = ReportOptions()
    ) -> String {
        let rows = tableRows(
            activityDays: activityDays,
            timeEntries: timeEntries,
            projectStore: projectStore,
            options: options
        )
        let headerHTML = rows.first?.map { "<th>\(htmlEscape($0))</th>" }.joined() ?? ""
        let rowHTML = rows.dropFirst().map { row in
            "<tr>\(row.map { "<td>\(htmlEscape($0))</td>" }.joined())</tr>"
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>Metriday Report</title>
        <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; color: #202124; margin: 28px; }
        h1 { font-size: 22px; } table { border-collapse: collapse; width: 100%; font-size: 11px; }
        th, td { border: 1px solid #d9dce3; padding: 6px 8px; text-align: left; vertical-align: top; }
        th { background: #f2f4f8; } tr:nth-child(even) { background: #fafbfc; }
        </style></head><body><h1>Metriday Report</h1>
        <table><thead><tr>\(headerHTML)</tr></thead><tbody>\(rowHTML)</tbody></table>
        </body></html>
        """
    }

    static func write(
        to url: URL,
        format: ReportFileFormat = .csv,
        activityDays: [(date: Date, segments: [ActivitySegment])],
        timeEntries: [TimeEntry],
        projectStore: ProjectStore,
        options: ReportOptions = ReportOptions()
    ) throws {
        switch format {
        case .csv:
            try csv(
                activityDays: activityDays,
                timeEntries: timeEntries,
                projectStore: projectStore,
                options: options
            ).write(to: url, atomically: true, encoding: .utf8)
        case .xlsx:
            try XLSXReportWriter.write(
                to: url,
                rows: tableRows(
                    activityDays: activityDays,
                    timeEntries: timeEntries,
                    projectStore: projectStore,
                    options: options
                )
            )
        case .json:
            try json(
                activityDays: activityDays,
                timeEntries: timeEntries,
                projectStore: projectStore,
                options: options
            ).write(to: url, options: .atomic)
        case .html:
            try html(
                activityDays: activityDays,
                timeEntries: timeEntries,
                projectStore: projectStore,
                options: options
            ).write(to: url, atomically: true, encoding: .utf8)
        case .pdf:
            try PDFReportWriter.write(
                to: url,
                html: html(
                    activityDays: activityDays,
                    timeEntries: timeEntries,
                    projectStore: projectStore,
                    options: options
                )
            )
        }
    }

    static func tableRows(
        activityDays: [(date: Date, segments: [ActivitySegment])],
        timeEntries: [TimeEntry],
        projectStore: ProjectStore,
        options: ReportOptions = ReportOptions()
    ) -> [[String]] {
        let records = records(
            activityDays: activityDays,
            timeEntries: timeEntries,
            projectStore: projectStore,
            options: options
        )
        let columns = ReportColumn.allCases.filter { options.columns.contains($0) }
        var rows = [columns.map(\.label)]
        rows += records.map { record in
            columns.map { column in
                switch column {
                case .date: return record.date
                case .type: return record.type
                case .project: return record.project
                case .group: return record.group
                case .application: return record.application
                case .title: return record.title
                case .device: return record.device
                case .resource: return record.resource
                case .start: return record.start
                case .end: return record.end
                case .duration: return formatDuration(record.durationSeconds, format: options.durationFormat)
                case .billingStatus: return record.billingStatus
                case .billingAmount: return formatAmount(record.billingAmount, currency: record.currency)
                case .notes: return record.notes
                }
            }
        }
        return rows
    }

    private static func records(
        activityDays: [(date: Date, segments: [ActivitySegment])],
        timeEntries: [TimeEntry],
        projectStore: ProjectStore,
        options: ReportOptions
    ) -> [ReportRecord] {
        let calendar = Calendar.current
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm:ss"

        var raw: [ReportRecord] = []
        for (date, segments) in activityDays {
            let dateKey = dayFormatter.string(from: date)
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let dayTimeEntries = timeEntries.filter {
                $0.start < dayEnd && $0.end > dayStart
            }
            if options.include == .appUsage || options.include == .both {
                let shouldAbsorbCoveredAppUsage = options.include == .both
                    && !options.includeCoveredAppUsage
                let reportSegments = !shouldAbsorbCoveredAppUsage
                    ? segments
                    : segments.flatMap {
                        uncoveredSegments(
                            $0,
                            on: date,
                            coveredBy: dayTimeEntries
                        )
                    }
                for segment in reportSegments
                where segment.relevance != .idle
                    && (options.includeShortEntries || segment.durationSeconds >= 60) {
                    guard includesProject(segment.projectID, options: options) else { continue }
                    let project = projectStore.project(segment.projectID)
                    let hourlyRate = project?.billingRate ?? 0
                    raw.append(ReportRecord(
                        date: dateKey,
                        device: segment.deviceName,
                        type: "App Usage",
                        group: "",
                        project: projectStore.hierarchyPath(for: segment.projectID),
                        application: segment.appName,
                        title: segment.windowTitle,
                        resource: segment.resource,
                        start: TimeFormat.string(segment.startMinute),
                        end: TimeFormat.string(segment.endMinute),
                        durationSeconds: segment.durationSeconds,
                        billingStatus: "",
                        hourlyRate: hourlyRate,
                        billingAmount: hourlyRate * Double(segment.durationSeconds) / 3_600.0,
                        currency: project?.currency ?? "USD",
                        notes: ""
                    ))
                }
            }

            if options.include == .timeEntries || options.include == .both {
                for entry in dayTimeEntries {
                    guard options.billingFilter.matches(entry.billingStatus) else { continue }
                    guard includesProject(entry.projectID, options: options) else { continue }
                    let project = projectStore.project(entry.projectID)
                    let hourlyRate = entry.billingStatus == .notBillable ? 0 : (project?.billingRate ?? 0)
                    let entryStart = max(entry.start, dayStart)
                    let entryEnd = min(entry.end, dayEnd)
                    let durationSeconds = max(1, Int(entryEnd.timeIntervalSince(entryStart)))
                    raw.append(ReportRecord(
                        date: dateKey,
                        device: "This Mac",
                        type: entry.isManual ? "Time Entry" : "Timer",
                        group: "",
                        project: projectStore.hierarchyPath(for: entry.projectID),
                        application: "",
                        title: entry.title,
                        resource: entry.notes,
                        start: timeFormatter.string(from: entryStart),
                        end: timeFormatter.string(from: entryEnd),
                        durationSeconds: durationSeconds,
                        billingStatus: entry.billingStatus.label,
                        hourlyRate: hourlyRate,
                        billingAmount: hourlyRate * Double(durationSeconds) / 3_600.0,
                        currency: project?.currency ?? "USD",
                        notes: entry.notes
                    ))
                }
            }
        }

        guard options.groupBy != .none else {
            return raw.map { record in
                if options.rounding != .none && options.roundIndividualEntries {
                    return replacingDuration(record, with: rounded(record.durationSeconds, options: options))
                }
                return record
            }
        }

        var grouped: [String: ReportRecord] = [:]
        for record in raw {
            let key = groupingKey(for: record, groupBy: options.groupBy)
            if let existing = grouped[key] {
                grouped[key] = replacingDuration(
                    existing,
                    with: existing.durationSeconds + record.durationSeconds,
                    billingAmount: existing.billingAmount + record.billingAmount,
                    currency: existing.currency == record.currency ? existing.currency : "Mixed"
                )
            } else {
                    grouped[key] = ReportRecord(
                    date: record.date,
                    device: record.device,
                    type: "Grouped",
                    group: key,
                    project: options.groupBy == .project
                        || options.groupBy == .topLevelProject
                        || options.groupBy == .secondLevelProject
                        || options.groupBy == .projectHierarchy
                        ? key
                        : record.project,
                    application: options.groupBy == .application ? key : record.application,
                    title: "",
                    resource: options.groupBy == .document ? key : "",
                    start: "",
                    end: "",
                    durationSeconds: record.durationSeconds,
                    billingStatus: "",
                    hourlyRate: 0,
                    billingAmount: record.billingAmount,
                    currency: record.currency,
                    notes: ""
                )
            }
        }
        return grouped.values.map { record in
            replacingDuration(record, with: rounded(record.durationSeconds, options: options))
        }.sorted {
            ($0.date, $0.group) < ($1.date, $1.group)
        }
    }

    private static func includesProject(_ projectID: UUID?, options: ReportOptions) -> Bool {
        guard !options.projectIDs.isEmpty else { return true }
        guard let projectID else { return false }
        return options.projectIDs.contains(projectID)
    }

    private static func uncoveredSegments(
        _ segment: ActivitySegment,
        on date: Date,
        coveredBy entries: [TimeEntry]
    ) -> [ActivitySegment] {
        guard !entries.isEmpty else { return [segment] }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEndSecond = 24 * 60 * 60
        var uncovered: [(start: Int, end: Int)] = [
            (max(0, segment.startSecond), min(dayEndSecond, segment.endSecond))
        ]

        for entry in entries {
            let coveredStart = max(
                0,
                Int(floor(entry.start.timeIntervalSince(dayStart)))
            )
            let coveredEnd = min(
                dayEndSecond,
                Int(ceil(entry.end.timeIntervalSince(dayStart)))
            )
            guard coveredEnd > coveredStart else { continue }

            var next: [(start: Int, end: Int)] = []
            for interval in uncovered {
                if coveredEnd <= interval.start || coveredStart >= interval.end {
                    next.append(interval)
                    continue
                }
                if interval.start < coveredStart {
                    next.append((interval.start, min(coveredStart, interval.end)))
                }
                if coveredEnd < interval.end {
                    next.append((max(coveredEnd, interval.start), interval.end))
                }
            }
            uncovered = next
            if uncovered.isEmpty { break }
        }

        return uncovered.compactMap { interval in
            guard interval.end > interval.start else { return nil }
            return ActivitySegment(
                id: UUID(),
                appName: segment.appName,
                bundleIdentifier: segment.bundleIdentifier,
                deviceName: segment.deviceName,
                windowTitle: segment.windowTitle,
                resource: segment.resource,
                startMinute: interval.start / 60,
                endMinute: Int(ceil(Double(interval.end) / 60.0)),
                startSecond: interval.start,
                endSecond: interval.end,
                relevance: segment.relevance,
                projectID: segment.projectID
            )
        }
    }

    private static func groupingKey(for record: ReportRecord, groupBy: ReportGroupBy) -> String {
        switch groupBy {
        case .none:
            return ""
        case .day:
            return record.date
        case .weekAndDay:
            let week = groupingKey(for: record, groupBy: .week)
            return "\(week) / \(record.date)"
        case .week:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            guard let date = formatter.date(from: record.date) else { return record.date }
            var calendar = Calendar.current
            calendar.firstWeekday = 2
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            let year = components.yearForWeekOfYear ?? 0
            let week = components.weekOfYear ?? 0
            return String(format: "%04d-W%02d", year, week)
        case .month:
            return String(record.date.prefix(7))
        case .year:
            return String(record.date.prefix(4))
        case .hour:
            let hour = String(record.start.prefix(2))
            return hour.count == 2 ? "\(record.date) \(hour):00" : record.date
        case .project:
            return record.project.isEmpty ? "Unassigned" : record.project
        case .topLevelProject:
            return hierarchyComponent(record.project, index: 0)
        case .secondLevelProject:
            let components = hierarchyComponents(record.project)
            return components.count > 1 ? components[1] : (components.first ?? "Unassigned")
        case .projectHierarchy:
            return record.project.isEmpty ? "Unassigned" : record.project
        case .application:
            if !record.application.isEmpty { return record.application }
            return record.title.isEmpty ? "Unassigned" : record.title
        case .document:
            if !record.resource.isEmpty { return record.resource }
            if !record.title.isEmpty { return record.title }
            return record.application.isEmpty ? "Unassigned" : record.application
        }
    }

    private static func hierarchyComponent(_ path: String, index: Int) -> String {
        hierarchyComponents(path).dropFirst(index).first ?? "Unassigned"
    }

    private static func hierarchyComponents(_ path: String) -> [String] {
        let components = path
            .split(separator: ">")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return components.isEmpty ? ["Unassigned"] : components
    }

    private static func replacingDuration(
        _ record: ReportRecord,
        with seconds: Int,
        billingAmount: Double? = nil,
        currency: String? = nil
    ) -> ReportRecord {
        ReportRecord(
            date: record.date,
            device: record.device,
            type: record.type,
            group: record.group,
            project: record.project,
            application: record.application,
            title: record.title,
            resource: record.resource,
            start: record.start,
            end: record.end,
            durationSeconds: seconds,
            billingStatus: record.billingStatus,
            hourlyRate: record.hourlyRate,
            billingAmount: billingAmount ?? (
                record.hourlyRate > 0
                    ? record.hourlyRate * Double(seconds) / 3_600.0
                    : record.billingAmount
            ),
            currency: currency ?? record.currency,
            notes: record.notes
        )
    }

    private static func formatAmount(_ amount: Double, currency: String) -> String {
        String(format: "%@ %.2f", currency, amount)
    }

    private static func rounded(_ seconds: Int, options: ReportOptions) -> Int {
        guard options.rounding != .none, options.roundingMinutes > 0 else { return seconds }
        let interval = options.roundingMinutes * 60
        switch options.rounding {
        case .none:
            return seconds
        case .up:
            return ((seconds + interval - 1) / interval) * interval
        case .down:
            return (seconds / interval) * interval
        case .nearest:
            return Int((Double(seconds) / Double(interval)).rounded()) * interval
        }
    }

    private static func formatDuration(_ seconds: Int, format: ReportDurationFormat) -> String {
        switch format {
        case .decimalMinutes:
            return String(format: "%.2f", Double(seconds) / 60.0)
        case .hms:
            return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
        case .human:
            let hours = seconds / 3_600
            let minutes = (seconds / 60) % 60
            let remainder = seconds % 60
            if hours > 0 { return "\(hours)h \(minutes)m \(remainder)s" }
            if minutes > 0 { return "\(minutes)m \(remainder)s" }
            return "\(remainder)s"
        case .seconds:
            return String(seconds)
        case .decimalHours:
            return String(format: "%.3f", Double(seconds) / 3_600.0)
        }
    }

    private static func escape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        guard escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") else {
            return escaped
        }
        return "\"\(escaped)\""
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

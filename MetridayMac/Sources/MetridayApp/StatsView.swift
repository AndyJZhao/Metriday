import Charts
import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var monitor: AppActivityMonitor
    @ObservedObject var screenTimeStore: ScreenTimeStore
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var timeEntryStore: TimeEntryStore
    let selectedDate: Date

    @State private var projectUnit: StatsProjectUnit = .hour

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageDateHeader(
                    title: "Stats",
                    subtitle: "See when, where, and how your time was spent"
                )

                HStack(spacing: 10) {
                    Text(weekRangeLabel)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("Open Activities") {
                        appState.section = .activities
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("stats.open-activities")
                }
                .padding(.horizontal, 2)

                HStack(spacing: 14) {
                    statCard(
                        title: "Total time",
                        value: formatSeconds(totalActiveSeconds),
                        note: "Active app usage",
                        color: MetridayTheme.accent,
                        symbol: "clock"
                    )
                    statCard(
                        title: "Productivity score",
                        value: totalActiveSeconds > 0 ? "\(productivityScore)%" : "—",
                        note: "Weighted by project relevance",
                        color: MetridayTheme.success,
                        symbol: "checkmark.seal"
                    )
                    statCard(
                        title: "Related time",
                        value: formatSeconds(weeklySummary.relatedDurationSeconds),
                        note: "Task-related activity",
                        color: MetridayTheme.success,
                        symbol: "target"
                    )
                    statCard(
                        title: "Distraction",
                        value: formatSeconds(weeklySummary.distractedDurationSeconds),
                        note: "Detected locally",
                        color: MetridayTheme.danger,
                        symbol: "exclamationmark.triangle"
                    )
                }

                HStack(alignment: .top, spacing: 16) {
                    weekdayChart(
                        title: "Most active weekdays",
                        subtitle: "Active minutes",
                        points: weekdayPoints,
                        value: { $0.activeMinutes },
                        color: MetridayTheme.accent,
                        identifier: "stats.active-weekdays"
                    )
                    weekdayChart(
                        title: "Most productive weekdays",
                        subtitle: "Productivity score",
                        points: weekdayPoints,
                        value: { $0.productivityScore },
                        color: MetridayTheme.success,
                        identifier: "stats.productive-weekdays"
                    )
                }

                HStack(alignment: .top, spacing: 16) {
                    hourChart(
                        title: "Most active hours",
                        subtitle: "Active minutes",
                        value: { $0.activeMinutes },
                        color: MetridayTheme.accent,
                        identifier: "stats.active-hours"
                    )
                    hourChart(
                        title: "Most productive hours",
                        subtitle: "Productivity score",
                        value: { $0.productivityScore },
                        color: MetridayTheme.success,
                        identifier: "stats.productive-hours"
                    )
                }

                HStack(alignment: .top, spacing: 16) {
                    projectChart
                    applicationsPanel
                }

                projectsAndEntriesPanel
            }
            .padding(28)
        }
    }

    private func statCard(
        title: String,
        value: String,
        note: String,
        color: Color,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)
                Spacer()
                Image(systemName: symbol)
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(MetridayTheme.graphite)
            Text(note)
                .font(.system(size: 10))
                .foregroundStyle(color)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stats.\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
    }

    private func weekdayChart(
        title: String,
        subtitle: String,
        points: [StatsDayPoint],
        value: @escaping (StatsDayPoint) -> Int,
        color: Color,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(color)
            }

            Chart {
                ForEach(points) { point in
                    BarMark(
                        x: .value("Day", point.label),
                        y: .value(subtitle, value(point))
                    )
                    .foregroundStyle(color)
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 170)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
        .accessibilityIdentifier(identifier)
    }

    private func hourChart(
        title: String,
        subtitle: String,
        value: @escaping (StatsHourPoint) -> Int,
        color: Color,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(color)
            }

            Chart {
                ForEach(hourPoints) { point in
                    BarMark(
                        x: .value("Hour", point.label),
                        y: .value(subtitle, value(point))
                    )
                    .foregroundStyle(color)
                }
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text(String(format: "%02d", hour))
                        }
                    }
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 170)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
        .accessibilityIdentifier(identifier)
    }

    private var projectChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time per Project")
                        .font(.system(size: 14, weight: .bold))
                    Text("Tracked activity and time entries")
                        .font(.system(size: 10))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                Picker("Unit", selection: $projectUnit) {
                    ForEach(StatsProjectUnit.allCases) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
            }

            Chart {
                ForEach(projectPoints) { point in
                    BarMark(
                        x: .value("Project", point.name),
                        y: .value("Minutes", point.displayMinutes)
                    )
                    .foregroundStyle(point.color)
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 200)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
        .accessibilityIdentifier("stats.time-per-project")
    }

    private var applicationsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Applications")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("Top 8")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)
            }

            if applicationPoints.isEmpty {
                Text("No application activity in this week yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(MetridayTheme.secondary)
            } else {
                let maximum = applicationPoints.first?.seconds ?? 1
                ForEach(applicationPoints) { point in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(point.name)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Text(formatSeconds(point.seconds))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(MetridayTheme.secondary)
                        }
                        ProgressView(value: Double(point.seconds), total: Double(maximum))
                            .tint(point.isDistracted ? MetridayTheme.danger : MetridayTheme.accent)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
        .accessibilityIdentifier("stats.applications")
    }

    private var projectsAndEntriesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Projects & Time Entries")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text(formatSeconds(projectPoints.reduce(0) { $0 + $1.seconds }))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)
            }

            if projectPoints.isEmpty {
                Text("No project-assigned activity or time entry yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(MetridayTheme.secondary)
            } else {
                ForEach(projectPoints) { point in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(point.color)
                            .frame(width: 8, height: 8)
                        Text(point.name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                        Text(formatSeconds(point.seconds))
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
        .accessibilityIdentifier("stats.projects-and-time-entries")
    }

    private var weeklySummary: ActivitySummary {
        ActivitySummary(segments: weekDates.flatMap(activitySegments(for:)))
    }

    private var totalActiveSeconds: Int {
        weeklySummary.relatedDurationSeconds
            + weeklySummary.distractedDurationSeconds
            + weeklySummary.otherDurationSeconds
    }

    private var productivityScore: Int {
        guard totalActiveSeconds > 0 else { return 0 }
        let weighted = weekDates
            .flatMap(activitySegments(for:))
            .filter { $0.relevance != .idle }
            .reduce(0.0) { $0 + productivityValue(for: $1) * Double($1.durationSeconds) }
        return Int((weighted / Double(totalActiveSeconds)).rounded()).clamped(to: -100...100)
    }

    private var weekDates: [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            return [selectedDate]
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private var weekRangeLabel: String {
        guard let first = weekDates.first, let last = weekDates.last else { return "This week" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: first))–\(formatter.string(from: last))"
    }

    private var weekdayPoints: [StatsDayPoint] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return weekDates.map { date in
            let segments = activitySegments(for: date).filter { $0.relevance != .idle }
            let activeSeconds = segments.reduce(0) { $0 + $1.durationSeconds }
            let score = activeSeconds > 0
                ? Int((segments.reduce(0.0) { $0 + productivityValue(for: $1) * Double($1.durationSeconds) } / Double(activeSeconds)).rounded())
                : 0
            return StatsDayPoint(
                id: date,
                label: formatter.string(from: date),
                activeMinutes: Int((Double(activeSeconds) / 60.0).rounded()),
                productivityScore: score
            )
        }
    }

    private var hourPoints: [StatsHourPoint] {
        var active = Array(repeating: 0, count: 24)
        var weighted = Array(repeating: 0.0, count: 24)
        var totals = Array(repeating: 0, count: 24)
        for segment in weekDates.flatMap(activitySegments(for:)) where segment.relevance != .idle {
            let hour = min(23, max(0, segment.startSecond / 3600))
            active[hour] += segment.durationSeconds
            totals[hour] += segment.durationSeconds
            weighted[hour] += productivityValue(for: segment) * Double(segment.durationSeconds)
        }
        return (0..<24).map { hour in
            StatsHourPoint(
                id: hour,
                label: String(format: "%02d", hour),
                activeMinutes: Int((Double(active[hour]) / 60.0).rounded()),
                productivityScore: totals[hour] > 0 ? Int((weighted[hour] / Double(totals[hour])).rounded()) : 0
            )
        }
    }

    private var projectPoints: [StatsProjectPoint] {
        var totals: [UUID?: Int] = [:]
        for segment in weekDates.flatMap(activitySegments(for:)) where segment.relevance != .idle {
            totals[segment.projectID, default: 0] += segment.durationSeconds
        }
        let weekStart = calendar.startOfDay(for: weekDates.first ?? selectedDate)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        for entry in timeEntryStore.materializedEntries() where entry.start < weekEnd && entry.end > weekStart {
            let clippedStart = max(entry.start, weekStart)
            let clippedEnd = min(entry.end, weekEnd)
            totals[entry.projectID, default: 0] += max(0, Int(clippedEnd.timeIntervalSince(clippedStart)))
        }
        return totals
            .filter { $0.value > 0 }
            .map { projectID, seconds in
                StatsProjectPoint(
                    id: projectID?.uuidString ?? "unassigned",
                    name: projectStore.name(for: projectID),
                    seconds: seconds,
                    color: projectColor(for: projectID),
                    unit: projectUnit
                )
            }
            .sorted { $0.seconds > $1.seconds }
            .prefix(8)
            .map { $0 }
    }

    private var applicationPoints: [StatsApplicationPoint] {
        var totals: [String: (seconds: Int, distracted: Bool)] = [:]
        for segment in weekDates.flatMap(activitySegments(for:)) where segment.relevance != .idle {
            let existing = totals[segment.displayTitle, default: (seconds: 0, distracted: false)]
            totals[segment.displayTitle] = (
                seconds: existing.seconds + segment.durationSeconds,
                distracted: existing.distracted || segment.relevance == .distracted
            )
        }
        return totals.map { name, value in
            StatsApplicationPoint(name: name, seconds: value.seconds, isDistracted: value.distracted)
        }
        .sorted { $0.seconds > $1.seconds }
        .prefix(8)
        .map { $0 }
    }

    private func activitySegments(for date: Date) -> [ActivitySegment] {
        monitor.segments(for: date) + screenTimeStore.segments(for: date)
    }

    private func productivityValue(for segment: ActivitySegment) -> Double {
        if let project = projectStore.project(segment.projectID) {
            return Double(project.productivity)
        }
        switch segment.relevance {
        case .related: return 100
        case .distracted: return 0
        case .other: return 50
        case .idle: return 0
        }
    }

    private func projectColor(for projectID: UUID?) -> Color {
        guard let project = projectStore.project(projectID) else { return MetridayTheme.secondary }
        switch project.color {
        case .blue: return MetridayTheme.accent
        case .green: return MetridayTheme.success
        case .orange: return MetridayTheme.warning
        case .purple: return .purple
        case .red: return MetridayTheme.danger
        case .graphite: return MetridayTheme.graphite
        }
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let minutes = Int((Double(seconds) / 60.0).rounded())
        if minutes < 1 { return "<1m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }
}

private enum StatsProjectUnit: String, CaseIterable, Identifiable {
    case hour
    case day

    var id: Self { self }

    var label: String {
        switch self {
        case .hour: return "Hour"
        case .day: return "Day"
        }
    }
}

private struct StatsDayPoint: Identifiable {
    let id: Date
    let label: String
    let activeMinutes: Int
    let productivityScore: Int
}

private struct StatsHourPoint: Identifiable {
    let id: Int
    let label: String
    let activeMinutes: Int
    let productivityScore: Int
}

private struct StatsProjectPoint: Identifiable {
    let id: String
    let name: String
    let seconds: Int
    let color: Color
    let unit: StatsProjectUnit

    var displayMinutes: Int {
        let divisor = unit == .hour ? 1 : 24
        return max(1, Int((Double(seconds) / 60.0 / Double(divisor)).rounded()))
    }
}

private struct StatsApplicationPoint: Identifiable {
    var id: String { name }
    let name: String
    let seconds: Int
    let isDistracted: Bool
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

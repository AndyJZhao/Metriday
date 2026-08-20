import Charts
import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var monitor: AppActivityMonitor
    @ObservedObject var filterStore: ActivityFilterStore
    @ObservedObject var categoryStore: ActivityCategoryStore
    @ObservedObject var screenTimeStore: ScreenTimeStore
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var timeEntryStore: TimeEntryStore
    let selectedDate: Date

    @State private var projectUnit: StatsProjectUnit = .hour
    @State private var projectScope: StatsProjectScope = .all

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
                    subtitle: "See when, where, and how your time was spent",
                    showsDateControls: true
                )

                HStack(alignment: .top, spacing: 16) {
                    projectScopePanel
                        .frame(width: 216)

                    VStack(alignment: .leading, spacing: 22) {
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

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 12
                        ) {
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
                            categoryPanel
                            applicationsPanel
                        }

                        HStack(alignment: .top, spacing: 16) {
                            projectChart
                            projectsAndEntriesPanel
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(28)
        }
    }

    private var projectScopePanel: some View {
        let totalSeconds = projectScopePoints.reduce(0) { $0 + $1.seconds }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Projects")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text(formatSeconds(totalSeconds))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MetridayTheme.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)

            Divider()

            VStack(spacing: 3) {
                projectScopeButton(
                    scope: .all,
                    name: "All Activities",
                    detail: "\(projectScopePoints.reduce(0) { $0 + $1.segmentCount }) segments",
                    symbol: "waveform.path"
                )
                projectScopeButton(
                    scope: .unassigned,
                    name: "Unassigned",
                    detail: formatSeconds(projectScopePoints.first(where: { $0.id == "unassigned" })?.seconds ?? 0),
                    symbol: "tray"
                )

                if !projectStore.activeProjects.isEmpty {
                    Text("MY PROJECTS")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(MetridayTheme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                        .padding(.horizontal, 8)
                }

                ForEach(projectStore.activeProjects) { project in
                    let point = projectScopePoints.first(where: { $0.projectID == project.id })
                    projectScopeButton(
                        scope: .project(project.id),
                        name: project.name,
                        detail: formatSeconds(point?.seconds ?? 0),
                        symbol: "folder"
                    )
                }
            }
            .padding(.top, 8)

            Text("Select a project to scope every chart and total to the same activity evidence.")
                .font(.system(size: 9))
                .foregroundStyle(MetridayTheme.secondary)
                .lineSpacing(2)
                .padding(.top, 12)
                .padding(.horizontal, 8)
        }
        .padding(.vertical, 14)
        .metridayPanel()
        .accessibilityIdentifier("stats.projects")
    }

    private func projectScopeButton(
        scope: StatsProjectScope,
        name: String,
        detail: String,
        symbol: String
    ) -> some View {
        Button {
            projectScope = scope
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(MetridayTheme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(projectScope == scope ? MetridayTheme.accentDeep : MetridayTheme.graphite)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(projectScope == scope ? MetridayTheme.accentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("stats.project-scope.(scope.identifier)")
        .accessibilityAddTraits(projectScope == scope ? .isSelected : [])
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

    private var categoryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time by Category")
                        .font(.system(size: 14, weight: .bold))
                    Text("Active App, website, and item time")
                        .font(.system(size: 10))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                Image(systemName: "chart.pie")
                    .foregroundStyle(MetridayTheme.accentDeep)
            }

            if categoryPoints.isEmpty {
                Text("No categorized activity in this week yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(MetridayTheme.secondary)
            } else {
                HStack(alignment: .center, spacing: 14) {
                    Chart {
                        ForEach(categoryPoints) { point in
                            SectorMark(
                                angle: .value("Time", point.seconds),
                                innerRadius: .ratio(0.62),
                                angularInset: 1.5
                            )
                            .foregroundStyle(point.color)
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(width: 170, height: 170)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(categoryPoints) { point in
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(point.color)
                                    .frame(width: 8, height: 8)
                                Text(point.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Text("\(point.percentage)%")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(formatSeconds(point.seconds))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(MetridayTheme.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
        .accessibilityIdentifier("stats.categories")
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
                HStack(alignment: .center, spacing: 14) {
                    Chart {
                        ForEach(applicationPoints) { point in
                            SectorMark(
                                angle: .value("Time", point.seconds),
                                innerRadius: .ratio(0.62),
                                angularInset: 1.5
                            )
                            .foregroundStyle(point.color)
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(width: 170, height: 170)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(applicationPoints) { point in
                            HStack(spacing: 7) {
                                AppIdentityIcon(
                                    symbol: "rectangle.on.rectangle",
                                    bundleIdentifier: point.bundleIdentifier,
                                    size: 22
                                )
                                Text(point.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Text(formatSeconds(point.seconds))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(MetridayTheme.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                HStack(alignment: .center, spacing: 14) {
                    Chart {
                        ForEach(projectPoints) { point in
                            SectorMark(
                                angle: .value("Time", point.seconds),
                                innerRadius: .ratio(0.62),
                                angularInset: 1.5
                            )
                            .foregroundStyle(point.color)
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(width: 170, height: 170)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(projectPoints) { point in
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(point.color)
                                    .frame(width: 8, height: 8)
                                Text(point.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Text(formatSeconds(point.seconds))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(MetridayTheme.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        let weighted = datedWeekSegments
            .filter { $0.segment.relevance != .idle }
            .reduce(0.0) { total, item in
                total + productivityValue(for: item.segment, date: item.date) * Double(item.segment.durationSeconds)
            }
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

    private var datedWeekSegments: [(date: Date, segment: ActivitySegment)] {
        weekDates.flatMap { date in
            activitySegments(for: date).map { (date: date, segment: $0) }
        }
    }

    private var weekdayPoints: [StatsDayPoint] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return weekDates.map { date in
            let segments = activitySegments(for: date).filter { $0.relevance != .idle }
            let activeSeconds = segments.reduce(0) { $0 + $1.durationSeconds }
            let score = activeSeconds > 0
                ? Int((segments.reduce(0.0) { $0 + productivityValue(for: $1, date: date) * Double($1.durationSeconds) } / Double(activeSeconds)).rounded())
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
        for item in datedWeekSegments where item.segment.relevance != .idle {
            let hour = min(23, max(0, item.segment.startSecond / 3600))
            active[hour] += item.segment.durationSeconds
            totals[hour] += item.segment.durationSeconds
            weighted[hour] += productivityValue(for: item.segment, date: item.date) * Double(item.segment.durationSeconds)
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
        for entry in timeEntryStore.materializedEntries() where entry.start < weekEnd && entry.end > weekStart && matchesProjectScope(entry.projectID) {
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

    private var categoryPoints: [StatsCategoryPoint] {
        var totals: [String: (name: String, seconds: Int, color: Color)] = [:]
        for item in datedWeekSegments {
            let definition = category(for: item.segment, date: item.date)
            guard definition.role != .idle else { continue }
            let key = definition.name + "::" + definition.role.rawValue
            let current = totals[key] ?? (name: definition.name, seconds: 0, color: categoryColor(for: definition))
            totals[key] = (
                name: current.name,
                seconds: current.seconds + item.segment.durationSeconds,
                color: current.color
            )
        }
        let total = totals.values.reduce(0) { $0 + $1.seconds }
        return totals.map { key, value in
            StatsCategoryPoint(
                id: key,
                name: value.name,
                seconds: value.seconds,
                percentage: total > 0 ? Int((Double(value.seconds) / Double(total) * 100).rounded()) : 0,
                color: value.color
            )
        }
        .sorted { $0.seconds > $1.seconds }
    }

    private var applicationPoints: [StatsApplicationPoint] {
        var totals: [String: (name: String, categoryName: String, bundleIdentifier: String, seconds: Int, color: Color)] = [:]
        for item in datedWeekSegments where item.segment.relevance != .idle {
            let definition = category(for: item.segment, date: item.date)
            let key = "\(item.segment.displayTitle)::\(definition.name)::\(definition.role.rawValue)"
            let existing = totals[key, default: (
                name: item.segment.displayTitle,
                categoryName: definition.name,
                bundleIdentifier: item.segment.bundleIdentifier,
                seconds: 0,
                color: categoryColor(for: definition)
            )]
            totals[key] = (
                name: existing.name,
                categoryName: existing.categoryName,
                bundleIdentifier: existing.bundleIdentifier.isEmpty ? item.segment.bundleIdentifier : existing.bundleIdentifier,
                seconds: existing.seconds + item.segment.durationSeconds,
                color: existing.color
            )
        }
        return totals.map { _, value in
            StatsApplicationPoint(
                name: value.name,
                categoryName: value.categoryName,
                bundleIdentifier: value.bundleIdentifier,
                seconds: value.seconds,
                color: value.color
            )
        }
        .sorted { $0.seconds > $1.seconds }
        .prefix(8)
        .map { $0 }
    }

    private var projectScopePoints: [StatsProjectScopePoint] {
        var totals: [UUID?: (seconds: Int, segmentCount: Int)] = [:]
        for segment in weekDates.flatMap(allActivitySegments(for:)) where segment.relevance != .idle {
            let current = totals[segment.projectID, default: (seconds: 0, segmentCount: 0)]
            totals[segment.projectID] = (
                seconds: current.seconds + segment.durationSeconds,
                segmentCount: current.segmentCount + 1
            )
        }
        let weekStart = calendar.startOfDay(for: weekDates.first ?? selectedDate)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        for entry in timeEntryStore.materializedEntries() where entry.start < weekEnd && entry.end > weekStart {
            let clippedStart = max(entry.start, weekStart)
            let clippedEnd = min(entry.end, weekEnd)
            let current = totals[entry.projectID, default: (seconds: 0, segmentCount: 0)]
            totals[entry.projectID] = (
                seconds: current.seconds + max(0, Int(clippedEnd.timeIntervalSince(clippedStart))),
                segmentCount: current.segmentCount
            )
        }
        return totals
            .filter { $0.value.seconds > 0 }
            .map { projectID, value in
                StatsProjectScopePoint(
                    id: projectID?.uuidString ?? "unassigned",
                    projectID: projectID,
                    seconds: value.seconds,
                    segmentCount: value.segmentCount
                )
            }
            .sorted { $0.seconds > $1.seconds }
    }

    private func allActivitySegments(for date: Date) -> [ActivitySegment] {
        categoryStore.applyingCategories(
            to: monitor.segments(for: date) + screenTimeStore.segments(for: date),
            filterStore: filterStore,
            date: date
        )
    }

    private func activitySegments(for date: Date) -> [ActivitySegment] {
        allActivitySegments(for: date).filter { matchesProjectScope($0.projectID) }
    }

    private func matchesProjectScope(_ projectID: UUID?) -> Bool {
        switch projectScope {
        case .all:
            return true
        case .unassigned:
            return projectID == nil
        case .project(let selectedID):
            return projectID == selectedID
        }
    }

    private func category(for segment: ActivitySegment, date: Date? = nil) -> ActivityCategoryDefinition {
        categoryStore.category(for: segment, filterStore: filterStore, date: date ?? selectedDate)
    }

    private func categoryColor(for category: ActivityCategoryDefinition) -> Color {
        switch category.color {
        case .blue: return MetridayTheme.accentDeep
        case .green: return MetridayTheme.success
        case .orange: return MetridayTheme.warning
        case .purple: return .purple
        case .red: return MetridayTheme.danger
        case .graphite: return MetridayTheme.secondary
        }
    }

    private func productivityValue(for segment: ActivitySegment, date: Date? = nil) -> Double {
        if let project = projectStore.project(segment.projectID) {
            return Double(project.productivity)
        }
        switch category(for: segment, date: date).role {
        case .focused: return 100
        case .distracting: return 0
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

private enum StatsProjectScope: Hashable {
    case all
    case unassigned
    case project(UUID)

    var identifier: String {
        switch self {
        case .all: return "all"
        case .unassigned: return "unassigned"
        case .project(let id): return id.uuidString
        }
    }
}

private struct StatsProjectScopePoint: Identifiable {
    let id: String
    let projectID: UUID?
    let seconds: Int
    let segmentCount: Int
}

private struct StatsCategoryPoint: Identifiable {
    let id: String
    let name: String
    let seconds: Int
    let percentage: Int
    let color: Color
}

private struct StatsApplicationPoint: Identifiable {
    var id: String { "\(name)::\(categoryName)" }
    let name: String
    let categoryName: String
    let bundleIdentifier: String
    let seconds: Int
    let color: Color
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

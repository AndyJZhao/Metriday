import Charts
import SwiftUI

private enum StatsPeriod: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return "Today"
        case .week: return "This Week"
        case .month: return "This Month"
        case .year: return "This Year"
        }
    }

    var chartTitle: String {
        switch self {
        case .day, .week: return "Time by Day"
        case .month, .year: return "Time by Week"
        }
    }
}

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
    @State private var statsPeriod: StatsPeriod = .week

    private var projectScope: StatsProjectScope {
        StatsProjectScope(appState.activityScope)
    }

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
                            VStack(alignment: .leading, spacing: 2) {
                                Text(periodRangeLabel)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(statsPeriod.label)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(MetridayTheme.secondary)
                            }
                            Spacer()
                            Picker("Stats range", selection: $statsPeriod) {
                                ForEach(StatsPeriod.allCases) { period in
                                    Text(period.label).tag(period)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 250)
                            .accessibilityIdentifier("stats.period-picker")
                            ShareLink(
                                item: statsShareText,
                                subject: Text("Metriday Stats"),
                                message: Text("Time overview for \(periodRangeLabel)")
                            ) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("stats.share")
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
                                value: formatSeconds(periodSummary.relatedDurationSeconds),
                                note: "Task-related activity",
                                color: MetridayTheme.success,
                                symbol: "target"
                            )
                            statCard(
                                title: "Distraction",
                                value: formatSeconds(periodSummary.distractedDurationSeconds),
                                note: "Detected locally",
                                color: MetridayTheme.danger,
                                symbol: "exclamationmark.triangle"
                            )
                        }

                        HStack(alignment: .top, spacing: 16) {
                            weekdayCategoryChart(
                                title: statsPeriod.chartTitle,
                                subtitle: "Active minutes by Category",
                                points: periodPoints,
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
                    projectScopeButton(
                        scope: .project(project.id),
                        name: project.name,
                        detail: formatSeconds(projectScopeSeconds(for: project.id)),
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
            appState.activityScope = scope.activityScope
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
        .accessibilityIdentifier("stats.project-scope.\(scope.identifier)")
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

    private func weekdayCategoryChart(
        title: String,
        subtitle: String,
        points: [StatsDayPoint],
        identifier: String
    ) -> some View {
        let bars = points.flatMap { point -> [StatsDayCategoryBar] in
            var cursor = 0.0
            return point.categories.map { segment in
                let start = cursor
                cursor += Double(segment.seconds) / 60.0
                return StatsDayCategoryBar(
                    id: "\(point.id.timeIntervalSinceReferenceDate)-\(segment.category.id.uuidString)",
                    label: point.label,
                    startMinutes: start,
                    endMinutes: cursor,
                    color: categoryColor(for: segment.category)
                )
            }
        }
        let categories = points.flatMap(\.categories).reduce(into: [UUID: ActivityCategoryDefinition]()) { result, segment in
            result[segment.category.id] = segment.category
        }.values.sorted { $0.name < $1.name }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(MetridayTheme.accentDeep)
            }

            if !categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(categories) { category in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(categoryColor(for: category))
                                    .frame(width: 6, height: 6)
                                Text(category.name)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(MetridayTheme.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Chart {
                    ForEach(bars) { bar in
                        BarMark(
                            x: .value("Day", bar.label),
                            yStart: .value("Start", bar.startMinutes),
                            yEnd: .value("End", bar.endMinutes)
                        )
                        .foregroundStyle(bar.color)
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(minWidth: max(320, CGFloat(bars.count) * 30))
                .frame(height: 170)
            }
            .frame(maxWidth: .infinity)
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
                    Text("Productivity pulse")
                        .font(.system(size: 14, weight: .bold))
                    Text("Category-weighted activity quality")
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
                    ZStack {
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

                        VStack(spacing: 1) {
                            Text(totalActiveSeconds > 0 ? "\(productivityScore)" : "—")
                                .font(.system(size: 27, weight: .bold))
                                .foregroundStyle(MetridayTheme.graphite)
                            Text("score")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(MetridayTheme.secondary)
                        }
                    }
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
                                Text(point.categoryName)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(point.color)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(point.color.opacity(0.10))
                                    .clipShape(Capsule())
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

    private var periodSummary: ActivitySummary {
        ActivitySummary(segments: periodDates.flatMap(activitySegments(for:)))
    }

    private var totalActiveSeconds: Int {
        periodSummary.relatedDurationSeconds
            + periodSummary.distractedDurationSeconds
            + periodSummary.otherDurationSeconds
    }

    private var productivityScore: Int {
        guard totalActiveSeconds > 0 else { return 0 }
        let weighted = datedPeriodSegments
            .filter { $0.segment.relevance != .idle }
            .reduce(0.0) { total, item in
                total + productivityValue(for: item.segment, date: item.date) * Double(item.segment.durationSeconds)
            }
        return Int((weighted / Double(totalActiveSeconds)).rounded()).clamped(to: -100...100)
    }

    private var periodDates: [Date] {
        switch statsPeriod {
        case .day:
            return [calendar.startOfDay(for: selectedDate)]
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
                return [selectedDate]
            }
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: selectedDate) else {
                return [selectedDate]
            }
            return dates(in: interval)
        case .year:
            guard let interval = calendar.dateInterval(of: .year, for: selectedDate) else {
                return [selectedDate]
            }
            return dates(in: interval)
        }
    }

    private var periodRangeLabel: String {
        guard let first = periodDates.first, let last = periodDates.last else { return statsPeriod.label }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = statsPeriod == .year ? "MMM yyyy" : "MMM d"
        if statsPeriod == .day {
            return formatter.string(from: first)
        }
        return statsPeriod == .year
            ? formatter.string(from: first)
            : "\(formatter.string(from: first))–\(formatter.string(from: last))"
    }

    private var statsShareText: String {
        let categories = categoryPoints.prefix(5).map { "\($0.name): \(formatSeconds($0.seconds))" }.joined(separator: "\n")
        return "Metriday Stats\n\(statsPeriod.label) · \(periodRangeLabel)\nTotal time: \(formatSeconds(totalActiveSeconds))\nProductivity score: \(productivityScore)%\nRelated time: \(formatSeconds(periodSummary.relatedDurationSeconds))\nDistraction: \(formatSeconds(periodSummary.distractedDurationSeconds))\n\nTop categories\n\(categories)"
    }

    private func dates(in interval: DateInterval) -> [Date] {
        var dates: [Date] = []
        var date = interval.start
        while date < interval.end {
            dates.append(date)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return dates
    }

    private var periodStartDate: Date {
        calendar.startOfDay(for: periodDates.first ?? selectedDate)
    }

    private var periodEndDate: Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: periodDates.last ?? selectedDate)) ?? selectedDate
    }

    private var datedPeriodSegments: [(date: Date, segment: ActivitySegment)] {
        periodDates.flatMap { date in
            activitySegments(for: date).map { (date: date, segment: $0) }
        }
    }

    private var weekdayPoints: [StatsDayPoint] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        var activeSeconds = Array(repeating: 0, count: 7)
        var weightedSeconds = Array(repeating: 0.0, count: 7)
        var categoryTotals = Array(repeating: [UUID: (category: ActivityCategoryDefinition, seconds: Int)](), count: 7)
        for date in periodDates {
            let weekday = calendar.component(.weekday, from: date)
            let index = (weekday + 5) % 7
            for segment in activitySegments(for: date) where segment.relevance != .idle {
                let definition = category(for: segment, date: date)
                categoryTotals[index][definition.id, default: (category: definition, seconds: 0)].seconds += segment.durationSeconds
                activeSeconds[index] += segment.durationSeconds
                weightedSeconds[index] += productivityValue(for: segment, date: date) * Double(segment.durationSeconds)
            }
        }
        let monday = periodDates.first(where: { calendar.component(.weekday, from: $0) == 2 })
            ?? calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start
            ?? selectedDate
        return (0..<7).map { index in
            let date = calendar.date(byAdding: .day, value: index, to: monday) ?? monday
            let seconds = activeSeconds[index]
            return StatsDayPoint(
                id: date,
                label: formatter.string(from: date),
                activeMinutes: Int((Double(seconds) / 60.0).rounded()),
                productivityScore: seconds > 0 ? Int((weightedSeconds[index] / Double(seconds)).rounded()) : 0,
                categories: categoryTotals[index].values
                    .filter { $0.seconds > 0 }
                    .map { StatsDayCategorySegment(category: $0.category, seconds: $0.seconds) }
                    .sorted { $0.seconds > $1.seconds }
            )
        }
    }

    private var periodPoints: [StatsDayPoint] {
        let buckets: [StatsPeriodBucket]
        switch statsPeriod {
        case .day, .week:
            buckets = periodDates.map { StatsPeriodBucket(label: dayLabel($0), dates: [$0]) }
        case .month, .year:
            buckets = stride(from: 0, to: periodDates.count, by: 7).map { start in
                let dates = Array(periodDates[start..<min(start + 7, periodDates.count)])
                return StatsPeriodBucket(label: shortDateLabel(dates[0]), dates: dates)
            }
        }
        return buckets.map { bucket in
            var categoryTotals: [UUID: (category: ActivityCategoryDefinition, seconds: Int)] = [:]
            var activeSeconds = 0
            var weightedSeconds = 0.0
            for date in bucket.dates {
                for segment in activitySegments(for: date) where segment.relevance != .idle {
                    let definition = category(for: segment, date: date)
                    categoryTotals[definition.id, default: (category: definition, seconds: 0)].seconds += segment.durationSeconds
                    activeSeconds += segment.durationSeconds
                    weightedSeconds += productivityValue(for: segment, date: date) * Double(segment.durationSeconds)
                }
            }
            return StatsDayPoint(
                id: bucket.dates[0],
                label: bucket.label,
                activeMinutes: Int((Double(activeSeconds) / 60.0).rounded()),
                productivityScore: activeSeconds > 0 ? Int((weightedSeconds / Double(activeSeconds)).rounded()) : 0,
                categories: categoryTotals.values
                    .filter { $0.seconds > 0 }
                    .map { StatsDayCategorySegment(category: $0.category, seconds: $0.seconds) }
                    .sorted { $0.seconds > $1.seconds }
            )
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func shortDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private var hourPoints: [StatsHourPoint] {
        var active = Array(repeating: 0, count: 24)
        var weighted = Array(repeating: 0.0, count: 24)
        var totals = Array(repeating: 0, count: 24)
        for item in datedPeriodSegments where item.segment.relevance != .idle {
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
        for segment in periodDates.flatMap(activitySegments(for:)) where segment.relevance != .idle {
            totals[segment.projectID, default: 0] += segment.durationSeconds
        }
        let periodStart = periodStartDate
        let periodEnd = periodEndDate
        for entry in timeEntryStore.materializedEntries() where entry.start < periodEnd && entry.end > periodStart && matchesProjectScope(entry.projectID) {
            let clippedStart = max(entry.start, periodStart)
            let clippedEnd = min(entry.end, periodEnd)
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
        for item in datedPeriodSegments {
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
        for item in datedPeriodSegments where item.segment.relevance != .idle {
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
        for segment in periodDates.flatMap(allActivitySegments(for:)) where segment.relevance != .idle {
            let current = totals[segment.projectID, default: (seconds: 0, segmentCount: 0)]
            totals[segment.projectID] = (
                seconds: current.seconds + segment.durationSeconds,
                segmentCount: current.segmentCount + 1
            )
        }
        let periodStart = periodStartDate
        let periodEnd = periodEndDate
        for entry in timeEntryStore.materializedEntries() where entry.start < periodEnd && entry.end > periodStart {
            let clippedStart = max(entry.start, periodStart)
            let clippedEnd = min(entry.end, periodEnd)
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
            guard let projectID else { return false }
            return projectStore.descendantProjectIDs(including: selectedID).contains(projectID)
        }
    }

    private func projectScopeSeconds(for projectID: UUID) -> Int {
        let projectIDs = projectStore.descendantProjectIDs(including: projectID)
        let activitySeconds = periodDates
            .flatMap(allActivitySegments(for:))
            .filter { segment in
                guard let assignedProjectID = segment.projectID else { return false }
                return projectIDs.contains(assignedProjectID) && segment.relevance != .idle
            }
            .reduce(0) { $0 + $1.durationSeconds }
        let periodStart = periodStartDate
        let periodEnd = periodEndDate
        let entrySeconds = timeEntryStore.materializedEntries()
            .filter { entry in
                guard let assignedProjectID = entry.projectID else { return false }
                return projectIDs.contains(assignedProjectID) && entry.start < periodEnd && entry.end > periodStart
            }
            .reduce(0) { total, entry in
                let clippedStart = max(entry.start, periodStart)
                let clippedEnd = min(entry.end, periodEnd)
                return total + max(0, Int(clippedEnd.timeIntervalSince(clippedStart)))
            }
        return activitySeconds + entrySeconds
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
    let categories: [StatsDayCategorySegment]
}

private struct StatsPeriodBucket {
    let label: String
    let dates: [Date]
}

private struct StatsDayCategorySegment: Identifiable {
    var id: UUID { category.id }
    let category: ActivityCategoryDefinition
    let seconds: Int
}

private struct StatsDayCategoryBar: Identifiable {
    let id: String
    let label: String
    let startMinutes: Double
    let endMinutes: Double
    let color: Color
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

    init(_ scope: ActivityProjectScope) {
        switch scope {
        case .all: self = .all
        case .unassigned: self = .unassigned
        case .project(let id): self = .project(id)
        }
    }

    var activityScope: ActivityProjectScope {
        switch self {
        case .all: return .all
        case .unassigned: return .unassigned
        case .project(let id): return .project(id)
        }
    }

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

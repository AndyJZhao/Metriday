import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

struct ReviewView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var monitor: AppActivityMonitor
    @ObservedObject var filterStore: ActivityFilterStore
    @ObservedObject var categoryStore: ActivityCategoryStore
    @ObservedObject var screenTimeStore: ScreenTimeStore
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var timeEntryStore: TimeEntryStore
    let selectedDate: Date

    @State private var showingReportBuilder = false

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageDateHeader(
                    title: "Review",
                    subtitle: "Understand where your planned time actually went",
                    showsDateControls: true
                )

                HStack(spacing: 16) {
                    metricCard(
                        title: "Productivity score",
                        value: percentage(productivityScore),
                        note: "\(currentSummary.taskRelatedPercentage)% task-related",
                        color: MetridayTheme.success,
                        symbol: "checkmark.seal"
                    )
                    metricCard(
                        title: "Deep work",
                        value: formatMinutes(currentSummary.relatedMinutes),
                        note: "Related app time",
                        color: MetridayTheme.accent,
                        symbol: "timer"
                    )
                    metricCard(
                        title: "Distraction",
                        value: formatMinutes(currentSummary.distractedMinutes),
                        note: "Detected locally",
                        color: MetridayTheme.danger,
                        symbol: "exclamationmark.triangle"
                    )
                    metricCard(
                        title: "Time entries",
                        value: formatMinutes(manualMinutes),
                        note: "Manual + timer",
                        color: MetridayTheme.warning,
                        symbol: "clock"
                    )
                }

                ActivityInsightsPanel(
                    segments: activitySegments(for: selectedDate)
                )

                categoryPulse

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Weekly focus quality")
                                .font(.system(size: 17, weight: .bold))
                            Text("\(weekRangeLabel) · activity and distraction minutes")
                                .font(.system(size: 11))
                                .foregroundStyle(MetridayTheme.secondary)
                        }
                        Spacer()
                        Button("Report Builder") {
                            showingReportBuilder = true
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("review.report-builder")
                        Button("Export CSV") {
                            exportCSV()
                        }
                        .buttonStyle(.bordered)
                        Button("Open Activities") {
                            appState.section = .activities
                        }
                        .buttonStyle(.bordered)
                    }

                    Chart {
                        ForEach(weeklyDays) { day in
                            BarMark(
                                x: .value("Day", day.label),
                                y: .value("Minutes", day.relatedMinutes)
                            )
                            .foregroundStyle(MetridayTheme.accent)
                            .position(by: .value("Type", "Related"))

                            BarMark(
                                x: .value("Day", day.label),
                                y: .value("Minutes", day.distractedMinutes)
                            )
                            .foregroundStyle(MetridayTheme.danger.opacity(0.7))
                            .position(by: .value("Type", "Distracted"))
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 280)
                }
                .padding(20)
                .metridayPanel()

                HStack(alignment: .top, spacing: 16) {
                    applicationBreakdown
                    hourlyBreakdown
                }

                HStack(alignment: .top, spacing: 16) {
                    projectBreakdown
                    reviewNotes
                }
            }
            .padding(28)
        }
        .sheet(isPresented: $showingReportBuilder) {
            ReportBuilderSheet(
                initialStartDate: weekDates.first ?? selectedDate,
                initialEndDate: weekDates.last ?? selectedDate,
                monitor: monitor,
                filterStore: filterStore,
                categoryStore: categoryStore,
                screenTimeStore: screenTimeStore,
                timeEntryStore: timeEntryStore,
                projectStore: projectStore
            )
        }
    }

    private var projectBreakdown: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Projects & Time Entries", systemImage: "folder")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatSeconds(projectTotals.reduce(0) { $0 + $1.seconds }))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MetridayTheme.secondary)
                    let totalAmount = projectTotals.reduce(0.0) { $0 + $1.amount }
                    if totalAmount > 0 {
                        Text(formatAmount(totalAmount, currency: projectTotals.first?.currency ?? "USD"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(MetridayTheme.success)
                    }
                }
            }

            if projectTotals.isEmpty {
                Text("No project-assigned activity yet. Assign activities from the Activities screen to build this report.")
                    .font(.system(size: 12))
                    .foregroundStyle(MetridayTheme.secondary)
            } else {
                ForEach(projectTotals) { total in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(total.color)
                            .frame(width: 8, height: 8)
                        Text(total.name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatSeconds(total.seconds))
                                .font(.system(size: 12, weight: .semibold))
                            if total.amount > 0 {
                                Text(formatAmount(total.amount, currency: total.currency))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(MetridayTheme.success)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
    }

    private var reviewNotes: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Next actions", systemImage: "wand.and.stars")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(MetridayTheme.accent)
            insight("Assign recurring activities to a project, then create a rule from the activity row.")
            insight("Use New Time Entry for meetings or time away from the Mac.")
            insight("Reports will use these same local activities and entries as their source.")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
    }

    private var applicationBreakdown: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Applications & Websites", systemImage: "rectangle.on.rectangle")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text("Top 8")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)
            }

            if applicationTotals.isEmpty {
                Text("No active application time in this week yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(MetridayTheme.secondary)
            } else {
                let maximum = applicationTotals.first?.seconds ?? 1
                ForEach(applicationTotals) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            AppIdentityIcon(
                                symbol: "rectangle.on.rectangle",
                                bundleIdentifier: item.bundleIdentifier,
                                size: 22
                            )
                            Text(item.name)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Text(item.category.name)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(categoryColor(for: item.category))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(categoryColor(for: item.category).opacity(0.10))
                                .clipShape(Capsule())
                            Spacer()
                            Text(formatSeconds(item.seconds))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(MetridayTheme.secondary)
                        }
                        ProgressView(value: Double(item.seconds), total: Double(maximum))
                            .tint(categoryColor(for: item.category))
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
    }

    private var categoryPulse: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Category pulse")
                        .font(.system(size: 17, weight: .bold))
                    Text("App and website time grouped by your custom Activity Categories")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                Text(formatSeconds(categoryTotals.reduce(0) { $0 + $1.seconds }))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)
            }

            if categoryTotals.isEmpty {
                Text("No categorized active time in this week yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(MetridayTheme.secondary)
            } else {
                let totalSeconds = max(1, categoryTotals.reduce(0) { $0 + $1.seconds })
                ForEach(categoryTotals) { total in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(categoryColor(for: total.category))
                                .frame(width: 8, height: 8)
                            Text(total.category.name)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int((Double(total.seconds) / Double(totalSeconds) * 100).rounded()))%")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(MetridayTheme.graphite)
                            Text(formatSeconds(total.seconds))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(MetridayTheme.secondary)
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(MetridayTheme.line.opacity(0.35))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(categoryColor(for: total.category))
                                        .frame(width: proxy.size.width * CGFloat(total.seconds) / CGFloat(totalSeconds))
                                }
                        }
                        .frame(height: 7)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
    }

    private var hourlyBreakdown: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Activity by Hour", systemImage: "clock")
                .font(.system(size: 15, weight: .bold))

            Chart {
                ForEach(hourlyTotals) { item in
                    BarMark(
                        x: .value("Hour", item.hour),
                        y: .value("Minutes", item.minutes)
                    )
                    .foregroundStyle(item.minutes > 0 ? MetridayTheme.accent : MetridayTheme.line)
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
            .frame(height: 205)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
    }

    private func metricCard(
        title: String,
        value: String,
        note: String,
        color: Color,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)
                Spacer()
                Image(systemName: symbol)
                    .foregroundStyle(color)
            }
            Text(value)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(MetridayTheme.graphite)
            Text(note)
                .font(.system(size: 10))
                .foregroundStyle(color)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
    }

    private func insight(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(MetridayTheme.line)
                .frame(width: 5, height: 5)
                .padding(.top, 5)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(MetridayTheme.secondary)
        }
    }

    private var currentSummary: ActivitySummary {
        ActivitySummary(segments: activitySegments(for: selectedDate))
    }

    private var productivityScore: Int {
        let segments = activitySegments(for: selectedDate).filter { $0.relevance != .idle }
        let totalSeconds = segments.reduce(0) { $0 + $1.durationSeconds }
        guard totalSeconds > 0 else { return 0 }
        let weighted = segments.reduce(0.0) { total, segment in
            let score: Double
            if let project = projectStore.project(segment.projectID) {
                score = Double(project.productivity)
            } else {
                switch segment.relevance {
                case .related:
                    score = 100
                case .distracted:
                    score = 0
                case .other:
                    score = 50
                case .idle:
                    score = 0
                }
            }
            return total + score * Double(segment.durationSeconds)
        }
        return Int((weighted / Double(totalSeconds)).rounded()).clamped(to: -100...100)
    }

    private var manualMinutes: Int {
        let dayStart = calendar.startOfDay(for: selectedDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let seconds = timeEntryStore.materializedEntries()
            .filter { $0.start < dayEnd && $0.end > dayStart }
            .reduce(0) { total, entry in
                let clippedStart = max(entry.start, dayStart)
                let clippedEnd = min(entry.end, dayEnd)
                return total + max(0, Int(clippedEnd.timeIntervalSince(clippedStart)))
            }
        return Int((Double(seconds) / 60.0).rounded())
    }

    private var weekDates: [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            return [selectedDate]
        }
        return (0..<7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
    }

    private var weeklyDays: [ReportDay] {
        weekDates.map { date in
            let summary = ActivitySummary(segments: activitySegments(for: date))
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE"
            return ReportDay(
                id: date,
                label: formatter.string(from: date),
                relatedMinutes: summary.relatedMinutes,
                distractedMinutes: summary.distractedMinutes
            )
        }
    }

    private var weekRangeLabel: String {
        guard let first = weekDates.first, let last = weekDates.last else {
            return "This week"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: first))–\(formatter.string(from: last))"
    }

    private var projectTotals: [ProjectTotal] {
        var totals: [UUID?: (seconds: Int, amount: Double)] = [:]
        let entries = timeEntryStore.materializedEntries()
        for date in weekDates {
            for segment in activitySegments(for: date) {
                guard segment.relevance != .idle else { continue }
                let rate = projectStore.project(segment.projectID)?.billingRate ?? 0
                totals[segment.projectID, default: (seconds: 0, amount: 0)].seconds += segment.durationSeconds
                totals[segment.projectID, default: (seconds: 0, amount: 0)].amount += rate * Double(segment.durationSeconds) / 3_600.0
            }
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            for entry in entries where entry.start < dayEnd && entry.end > dayStart {
                let clippedStart = max(entry.start, dayStart)
                let clippedEnd = min(entry.end, dayEnd)
                let clippedSeconds = max(0, Int(clippedEnd.timeIntervalSince(clippedStart)))
                let rate = entry.billingStatus == .notBillable
                    ? 0
                    : projectStore.project(entry.projectID)?.billingRate ?? 0
                totals[entry.projectID, default: (seconds: 0, amount: 0)].seconds += clippedSeconds
                totals[entry.projectID, default: (seconds: 0, amount: 0)].amount += rate * Double(clippedSeconds) / 3_600.0
            }
        }

        return totals
            .filter { $0.value.seconds > 0 }
            .map { projectID, total in
                ProjectTotal(
                    id: projectID?.uuidString ?? "unassigned",
                    name: projectStore.name(for: projectID),
                    seconds: total.seconds,
                    amount: total.amount,
                    currency: projectStore.project(projectID)?.currency ?? "USD",
                    color: projectColor(for: projectID)
                )
            }
            .sorted { $0.seconds > $1.seconds }
    }

    private var applicationTotals: [ApplicationTotal] {
        var totals: [String: (bundleIdentifier: String, seconds: Int, categories: [UUID: (category: ActivityCategoryDefinition, seconds: Int)])] = [:]
        for date in weekDates {
            let sourceSegments = monitor.segments(for: date) + screenTimeStore.segments(for: date)
            for segment in sourceSegments {
                let category = categoryStore.category(for: segment, filterStore: filterStore, date: date)
                guard category.role != .idle else { continue }
                let name = segment.displayTitle
                var existing = totals[name, default: (
                    bundleIdentifier: segment.bundleIdentifier,
                    seconds: 0,
                    categories: [:]
                )]
                if existing.bundleIdentifier.isEmpty {
                    existing.bundleIdentifier = segment.bundleIdentifier
                }
                existing.seconds += segment.durationSeconds
                existing.categories[category.id, default: (category: category, seconds: 0)].seconds += segment.durationSeconds
                totals[name] = existing
            }
        }
        return totals.map { name, value in
            let primary = value.categories.values.max { left, right in left.seconds < right.seconds }?.category
                ?? ActivityCategoryDefinition(name: "Other", role: .other, isSystem: true)
            return ApplicationTotal(
                name: name,
                bundleIdentifier: value.bundleIdentifier,
                seconds: value.seconds,
                category: primary
            )
        }
        .sorted { $0.seconds > $1.seconds }
        .prefix(8)
        .map { $0 }
    }

    private var categoryTotals: [CategoryTotal] {
        var totals: [UUID: (category: ActivityCategoryDefinition, seconds: Int)] = [:]
        for date in weekDates {
            let sourceSegments = monitor.segments(for: date) + screenTimeStore.segments(for: date)
            for segment in sourceSegments {
                let category = categoryStore.category(for: segment, filterStore: filterStore, date: date)
                guard category.role != .idle, segment.durationSeconds > 0 else { continue }
                totals[category.id, default: (category: category, seconds: 0)].seconds += segment.durationSeconds
            }
        }
        return totals.values
            .map { CategoryTotal(category: $0.category, seconds: $0.seconds) }
            .sorted { $0.seconds > $1.seconds }
    }

    private var hourlyTotals: [HourlyTotal] {
        var totals = Array(repeating: 0, count: 24)
        for date in weekDates {
            for segment in activitySegments(for: date) {
                guard segment.relevance != .idle else { continue }
                let hour = min(23, max(0, segment.startSecond / 3600))
                totals[hour] += segment.durationSeconds
            }
        }
        return totals.enumerated().map { hour, seconds in
            HourlyTotal(hour: hour, minutes: Int((Double(seconds) / 60.0).rounded()))
        }
    }

    private func projectColor(for projectID: UUID?) -> Color {
        guard let project = projectStore.project(projectID) else {
            return MetridayTheme.secondary
        }
        switch project.color {
        case .blue:
            return MetridayTheme.accent
        case .green:
            return MetridayTheme.success
        case .orange:
            return MetridayTheme.warning
        case .purple:
            return Color.purple
        case .red:
            return MetridayTheme.danger
        case .graphite:
            return MetridayTheme.graphite
        }
    }

    private func categoryColor(for category: ActivityCategoryDefinition) -> Color {
        switch category.color {
        case .blue:
            return MetridayTheme.accent
        case .green:
            return MetridayTheme.success
        case .orange:
            return MetridayTheme.warning
        case .purple:
            return Color.purple
        case .red:
            return MetridayTheme.danger
        case .graphite:
            return MetridayTheme.graphite
        }
    }

    private func percentage(_ value: Int) -> String {
        currentSummary.activeMinutes > 0 ? "\(value)%" : "—"
    }

    private func formatMinutes(_ minutes: Int) -> String {
        if minutes < 1 { return "<1m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }

    private func formatSeconds(_ seconds: Int) -> String {
        formatMinutes(Int((Double(seconds) / 60.0).rounded()))
    }

    private func formatAmount(_ amount: Double, currency: String) -> String {
        String(format: "%@ %.2f", currency, amount)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "metriday-\(weekRangeLabel.replacingOccurrences(of: "–", with: "-")).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let activityDays = weekDates.map { date in
            (date: date, segments: activitySegments(for: date))
        }
        let rangeStart = calendar.startOfDay(for: weekDates.first ?? selectedDate)
        let rangeEnd = calendar.date(byAdding: .day, value: weekDates.count, to: rangeStart) ?? rangeStart
        let entries = timeEntryStore.materializedEntries().filter {
            $0.start < rangeEnd && $0.end > rangeStart
        }
        var options = ReportOptions()
        options.deviceName = appState.syncStore.deviceName
        try? ReportExporter.write(
            to: url,
            activityDays: activityDays,
            timeEntries: entries,
            projectStore: projectStore,
            options: options
        )
    }

    private func activitySegments(for date: Date) -> [ActivitySegment] {
        categoryStore.applyingCategories(
            to: monitor.segments(for: date) + screenTimeStore.segments(for: date),
            filterStore: filterStore,
            date: date
        ).filter(matchesSelectedDevice)
    }

    private func matchesSelectedDevice(_ segment: ActivitySegment) -> Bool {
        let selectedDevice = appState.activitiesPreferences.selectedDevice
        return selectedDevice == "All Devices" || selectedDevice == "all" || segment.deviceName == selectedDevice
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private struct ReportDay: Identifiable {
    let id: Date
    let label: String
    let relatedMinutes: Int
    let distractedMinutes: Int
}

private struct ProjectTotal: Identifiable {
    let id: String
    let name: String
    let seconds: Int
    let amount: Double
    let currency: String
    let color: Color
}

private struct ApplicationTotal: Identifiable {
    var id: String { name }
    let name: String
    let bundleIdentifier: String
    let seconds: Int
    let category: ActivityCategoryDefinition
}

private struct CategoryTotal: Identifiable {
    var id: UUID { category.id }
    let category: ActivityCategoryDefinition
    let seconds: Int
}

private struct HourlyTotal: Identifiable {
    var id: Int { hour }
    let hour: Int
    let minutes: Int
}

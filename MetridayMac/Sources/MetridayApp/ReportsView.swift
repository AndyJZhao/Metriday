import SwiftUI

struct ReportsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var monitor: AppActivityMonitor
    @ObservedObject var filterStore: ActivityFilterStore
    @ObservedObject var categoryStore: ActivityCategoryStore
    @ObservedObject var screenTimeStore: ScreenTimeStore
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var timeEntryStore: TimeEntryStore
    let selectedDate: Date

    @State private var selectedPreset: ReportPreset?
    @State private var expandedReportProjectIDs: Set<String> = []
    @State private var expandedReportTitleIDs: Set<String> = []
    @State private var reportPreviewProjects: [ReportPreviewProject] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageDateHeader(
                    title: "Reports",
                    subtitle: "Build, preview, and export detailed time reports",
                    showsDateControls: true
                )

                HStack(spacing: 14) {
                    reportMetric(
                        title: "Tracked time",
                        value: formatSeconds(activeSeconds),
                        note: dateRangeLabel,
                        color: MetridayTheme.accent,
                        symbol: "clock"
                    )
                    reportMetric(
                        title: "Time entries",
                        value: formatSeconds(entrySeconds),
                        note: "Manual + timer",
                        color: MetridayTheme.warning,
                        symbol: "list.bullet.rectangle"
                    )
                    reportMetric(
                        title: "Export formats",
                        value: "5",
                        note: "CSV · XLSX · JSON · HTML · PDF",
                        color: MetridayTheme.success,
                        symbol: "square.and.arrow.up"
                    )
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Report Builder")
                                .font(.system(size: 17, weight: .bold))
                            Text("Timing-style presets with custom date, project, grouping, billing, and duration options.")
                                .font(.system(size: 11))
                                .foregroundStyle(MetridayTheme.secondary)
                        }
                        Spacer()
                        Button("Open Builder") {
                            selectedPreset = .custom
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("reports.open-builder")
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180), spacing: 10)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(ReportPreset.allCases.filter { $0 != .custom }) { preset in
                            Button {
                                selectedPreset = preset
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: reportPresetIcon(preset))
                                        .frame(width: 24, height: 24)
                                        .foregroundStyle(MetridayTheme.accent)
                                        .background(MetridayTheme.accentSoft)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    Text(preset.label)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(MetridayTheme.graphite)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(MetridayTheme.secondary)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .background(MetridayTheme.canvas)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .accessibilityIdentifier("reports.preset.\(preset.rawValue)")
                        }
                    }
                }
                .padding(18)
                .metridayPanel()

                reportOutline
            }
            .padding(28)
        }
        .sheet(item: $selectedPreset) { preset in
            ReportBuilderSheet(
                initialStartDate: weekDates.first ?? selectedDate,
                initialEndDate: weekDates.last ?? selectedDate,
                monitor: monitor,
                filterStore: filterStore,
                categoryStore: categoryStore,
                screenTimeStore: screenTimeStore,
                timeEntryStore: timeEntryStore,
                projectStore: projectStore,
                trackingPreferences: appState.preferences,
                initialPreset: preset
            )
        }
        .task(id: selectedDate) {
            reportPreviewProjects = makeReportPreviewProjects()
        }
    }

    private func reportMetric(
        title: String,
        value: String,
        note: String,
        color: Color,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
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
            Text(note)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
    }

    private var reportOutline: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Report Outline")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Text("Project → Title → Entry")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MetridayTheme.secondary)
            }

            if reportPreviewProjects.isEmpty {
                Text("No activity or time entry has been recorded in this week yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(MetridayTheme.secondary)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .foregroundStyle(MetridayTheme.accent)
                            .frame(width: 18)
                        Text(dateRangeLabel)
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(formatSeconds(reportPreviewProjects.reduce(0) { $0 + $1.seconds }))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(MetridayTheme.canvas)

                    ForEach(reportPreviewProjects) { project in
                        reportProjectRow(project)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
        .accessibilityIdentifier("reports.report-outline")
    }

    private func reportProjectRow(_ project: ReportPreviewProject) -> some View {
        VStack(spacing: 0) {
            Button {
                if expandedReportProjectIDs.contains(project.id) {
                    expandedReportProjectIDs.remove(project.id)
                } else {
                    expandedReportProjectIDs.insert(project.id)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expandedReportProjectIDs.contains(project.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(MetridayTheme.secondary)
                        .frame(width: 12)
                    Circle()
                        .fill(project.color)
                        .frame(width: 8, height: 8)
                    Text(project.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(formatSeconds(project.seconds))
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reports.outline.project.\(project.id)")

            if expandedReportProjectIDs.contains(project.id) {
                ForEach(project.titles) { title in
                    reportTitleRow(title, projectID: project.id)
                }
            }
        }
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func reportTitleRow(_ title: ReportPreviewTitle, projectID: String) -> some View {
        VStack(spacing: 0) {
            Button {
                if expandedReportTitleIDs.contains(title.id) {
                    expandedReportTitleIDs.remove(title.id)
                } else {
                    expandedReportTitleIDs.insert(title.id)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expandedReportTitleIDs.contains(title.id) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(MetridayTheme.secondary)
                        .frame(width: 12)
                    Image(systemName: title.kind == "Time Entry" ? "clock" : "rectangle.on.rectangle")
                        .font(.system(size: 10))
                        .foregroundStyle(MetridayTheme.secondary)
                        .frame(width: 14)
                    Text(title.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Text(formatSeconds(title.seconds))
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.leading, 38)
                .padding(.trailing, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reports.outline.title.\(projectID).\(title.id)")

            if expandedReportTitleIDs.contains(title.id) {
                ForEach(title.details) { detail in
                    Button {
                        appState.selectDate(detail.date)
                        appState.section = .activities
                    } label: {
                        HStack(spacing: 8) {
                            Color.clear
                                .frame(width: 12)
                            Text(detail.kind)
                                .font(.system(size: 10))
                                .foregroundStyle(MetridayTheme.secondary)
                                .frame(width: 68, alignment: .leading)
                            Text(detail.dateLabel)
                                .font(.system(size: 10))
                                .foregroundStyle(MetridayTheme.graphite)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(formatSeconds(detail.seconds))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.leading, 68)
                        .padding(.trailing, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("reports.outline.entry.\(detail.id)")
                }
            }
        }
    }

    private var weekDates: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else { return [selectedDate] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private var dateRangeLabel: String {
        guard let first = weekDates.first, let last = weekDates.last else { return "This week" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: first))–\(formatter.string(from: last))"
    }

    private var reportStart: Date {
        Calendar.current.startOfDay(for: weekDates.first ?? selectedDate)
    }

    private var reportEnd: Date {
        let calendar = Calendar.current
        let lastDay = calendar.startOfDay(for: weekDates.last ?? selectedDate)
        return calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
    }

    private func secondsInReportRange(for entry: TimeEntry) -> Int {
        let start = max(entry.start, reportStart)
        let end = min(entry.end, reportEnd)
        guard end > start else { return 0 }
        return max(1, Int(end.timeIntervalSince(start).rounded()))
    }

    private var activityDays: [[ActivitySegment]] {
        weekDates.map { date in
            categoryStore.applyingCategories(
                to: monitor.segments(for: date) + screenTimeStore.segments(for: date),
                filterStore: filterStore,
                date: date
            ).filter(matchesSelectedDevice)
        }
    }

    private func matchesSelectedDevice(_ segment: ActivitySegment) -> Bool {
        let selectedDevice = appState.activitiesPreferences.selectedDevice
        return selectedDevice == "All Devices" || selectedDevice == "all" || segment.deviceName == selectedDevice
    }

    private var activeSeconds: Int {
        activityDays.flatMap { $0 }
            .filter { $0.relevance != .idle }
            .reduce(0) { $0 + $1.durationSeconds }
    }

    private var entrySeconds: Int {
        return timeEntryStore.materializedEntries()
            .reduce(0) { $0 + secondsInReportRange(for: $1) }
    }

    private func makeReportPreviewProjects() -> [ReportPreviewProject] {
        var detailsByProject: [String: [ReportPreviewDetail]] = [:]
        var projectIDs: [String: UUID?] = [:]

        for (dayIndex, date) in weekDates.enumerated() {
            let segments = dayIndex < activityDays.count ? activityDays[dayIndex] : []
            let dayStart = Calendar.current.startOfDay(for: date)
            for segment in segments where segment.relevance != .idle {
                let projectKey = segment.projectID?.uuidString ?? "unassigned"
                projectIDs[projectKey] = segment.projectID
                let start = dayStart.addingTimeInterval(TimeInterval(segment.startSecond))
                let end = dayStart.addingTimeInterval(TimeInterval(segment.endSecond))
                let detail = ReportPreviewDetail(
                    id: "app-\(segment.id.uuidString)",
                    kind: "App Usage",
                    title: segment.displayTitle,
                    date: date,
                    start: start,
                    end: end,
                    seconds: segment.durationSeconds
                )
                detailsByProject[projectKey, default: []].append(detail)
            }
        }

        for entry in timeEntryStore.materializedEntries() {
            let seconds = secondsInReportRange(for: entry)
            guard seconds > 0 else { continue }
            let projectKey = entry.projectID?.uuidString ?? "unassigned"
            projectIDs[projectKey] = entry.projectID
            let start = max(entry.start, reportStart)
            let end = min(entry.end, reportEnd)
            let detail = ReportPreviewDetail(
                id: "entry-\(entry.id.uuidString)",
                kind: entry.isManual ? "Time Entry" : "Timer",
                title: entry.title.isEmpty ? "Untitled time entry" : entry.title,
                date: start,
                start: start,
                end: end,
                seconds: seconds
            )
            detailsByProject[projectKey, default: []].append(detail)
        }

        return detailsByProject.compactMap { key, details in
            guard !details.isEmpty else { return nil }
            let groupedTitles = Dictionary(grouping: details) { detail in
                "\(detail.kind)|\(detail.title)"
            }
            let titles = groupedTitles.map { groupKey, groupedDetails in
                let sortedDetails = groupedDetails.sorted { $0.start < $1.start }
                let components = groupKey.split(separator: "|", maxSplits: 1).map(String.init)
                return ReportPreviewTitle(
                    id: "\(key)-\(groupKey)",
                    kind: components.first ?? "App Usage",
                    title: components.count > 1 ? components[1] : groupKey,
                    seconds: groupedDetails.reduce(0) { $0 + $1.seconds },
                    details: sortedDetails
                )
            }
            .sorted { $0.seconds > $1.seconds }
            let projectID = projectIDs[key] ?? nil
            return ReportPreviewProject(
                id: key,
                name: projectStore.name(for: projectID),
                seconds: details.reduce(0) { $0 + $1.seconds },
                color: projectColor(for: projectID),
                titles: titles
            )
        }
        .sorted { $0.seconds > $1.seconds }
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

    private func reportPresetIcon(_ preset: ReportPreset) -> String {
        switch preset {
        case .timesheet, .timesheetWeekDay, .timesheetWeekDayNotes, .weeklySnippet: return "calendar"
        case .timePerProject: return "folder"
        case .timePerApplication: return "rectangle.on.rectangle"
        case .timePerDocument: return "doc.text"
        case .ultraDetailed: return "list.bullet.rectangle"
        case .rawTimeEntries: return "clock"
        case .rawAppUsage: return "waveform.path"
        case .custom: return "slider.horizontal.3"
        }
    }

    private func formatSeconds(_ seconds: Int) -> String {
        let minutes = Int((Double(seconds) / 60.0).rounded())
        if minutes < 1 { return "<1m" }
        let hours = minutes / 60
        return hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
    }
}

private struct ReportPreviewProject: Identifiable {
    let id: String
    let name: String
    let seconds: Int
    let color: Color
    let titles: [ReportPreviewTitle]
}

private struct ReportPreviewTitle: Identifiable {
    let id: String
    let kind: String
    let title: String
    let seconds: Int
    let details: [ReportPreviewDetail]
}

private struct ReportPreviewDetail: Identifiable {
    let id: String
    let kind: String
    let title: String
    let date: Date
    let start: Date
    let end: Date
    let seconds: Int

    var dateLabel: String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "MMM d"
        return "\(dateFormatter.string(from: date)) · \(timeString(start))–\(timeString(end))"
    }

    private func timeString(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: value)
    }
}

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
                            .accessibilityIdentifier("reports.preset.\(preset.rawValue)")
                        }
                    }
                }
                .padding(18)
                .metridayPanel()

                projectSummary
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
                initialPreset: preset
            )
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

    private var projectSummary: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Projects & Time Entries")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Text("Preview source")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MetridayTheme.secondary)
            }

            if projectTotals.isEmpty {
                Text("No activity or time entry has been recorded in this week yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(MetridayTheme.secondary)
            } else {
                ForEach(projectTotals) { total in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(total.color)
                            .frame(width: 8, height: 8)
                        Text(total.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text(formatSeconds(total.seconds))
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
        .accessibilityIdentifier("reports.project-summary")
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

    private var projectTotals: [ReportProjectTotal] {
        var totals: [UUID?: Int] = [:]
        for segment in activityDays.flatMap({ $0 }) where segment.relevance != .idle {
            totals[segment.projectID, default: 0] += segment.durationSeconds
        }
        for entry in timeEntryStore.materializedEntries() {
            let seconds = secondsInReportRange(for: entry)
            if seconds > 0 {
                totals[entry.projectID, default: 0] += seconds
            }
        }
        return totals
            .filter { $0.value > 0 }
            .map { projectID, seconds in
                ReportProjectTotal(
                    id: projectID?.uuidString ?? "unassigned",
                    name: projectStore.name(for: projectID),
                    seconds: seconds,
                    color: projectColor(for: projectID)
                )
            }
            .sorted { $0.seconds > $1.seconds }
            .prefix(10)
            .map { $0 }
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
        case .timesheet, .timesheetWeekDay, .weeklySnippet: return "calendar"
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

private struct ReportProjectTotal: Identifiable {
    let id: String
    let name: String
    let seconds: Int
    let color: Color
}

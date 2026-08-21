import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ReportBuilderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @ObservedObject var monitor: AppActivityMonitor
    @ObservedObject var filterStore: ActivityFilterStore
    @ObservedObject var categoryStore: ActivityCategoryStore
    @ObservedObject var screenTimeStore: ScreenTimeStore
    @ObservedObject var timeEntryStore: TimeEntryStore
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var trackingPreferences: PreferencesStore

    @State private var options = ReportOptions()
    @State private var preset: ReportPreset = .custom
    @State private var advancedMode = true
    @State private var format: ReportFileFormat = .csv
    @State private var rangePreset: ReportDateRangePreset
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isApplyingRangePreset = false
    @State private var statusMessage = "Choose what to include and export a report."

    init(
        initialStartDate: Date,
        initialEndDate: Date,
        monitor: AppActivityMonitor,
        filterStore: ActivityFilterStore,
        categoryStore: ActivityCategoryStore,
        screenTimeStore: ScreenTimeStore,
        timeEntryStore: TimeEntryStore,
        projectStore: ProjectStore,
        trackingPreferences: PreferencesStore,
        initialPreset: ReportPreset = .custom
    ) {
        self.monitor = monitor
        self.filterStore = filterStore
        self.categoryStore = categoryStore
        self.screenTimeStore = screenTimeStore
        self.timeEntryStore = timeEntryStore
        self.projectStore = projectStore
        self.trackingPreferences = trackingPreferences
        _rangePreset = State(initialValue: .custom)
        _startDate = State(initialValue: Calendar.current.startOfDay(for: initialStartDate))
        _endDate = State(initialValue: Calendar.current.startOfDay(for: initialEndDate))
        _preset = State(initialValue: initialPreset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Report Builder")
                        .font(.system(size: 20, weight: .bold))
                    Text("\(dateRangeLabel) · Timing-style report options")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.borderless)
            }

            Picker("Report builder mode", selection: $advancedMode) {
                Text("Easy").tag(false)
                Text("Advanced").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
            .accessibilityLabel("Report builder mode")
            .accessibilityIdentifier("reports.builder-mode")
            .onChange(of: advancedMode) { _, isAdvanced in
                if !isAdvanced {
                    applyPreset(preset)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    presetPanel
                    dateRangePanel
                    if advancedMode {
                        projectPanel
                        settingsPanel
                        columnsPanel
                    } else {
                        easySettingsPanel
                        columnsPanel
                    }
                    previewPanel
                }
            }

            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(MetridayTheme.accent)
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(MetridayTheme.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Export") { export() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("reports.export")
            }
        }
        .padding(24)
        .frame(width: 620, height: 660)
        .onAppear {
            options.deviceName = appState.syncStore.deviceName
            options.includeSubprojects = trackingPreferences.includeSubprojectsWhenSelectingProject
            if preset != .custom, options.groupBy == .none {
                applyPreset(preset)
            }
        }
        .onChange(of: trackingPreferences.includeSubprojectsWhenSelectingProject) { _, value in
            options.includeSubprojects = value
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Report contents")
                .font(.system(size: 15, weight: .bold))
                .padding(.bottom, 12)

            settingRow("Include") {
                Picker("Include", selection: $options.include) {
                    ForEach(ReportIncludeMode.allCases) { value in
                        Text(value.label).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
            }

            settingRow("Group by") {
                Picker("Group by", selection: $options.groupBy) {
                    ForEach(ReportGroupBy.allCases) { value in
                        Text(value.label).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
            }

            settingRow("Billing status") {
                Picker("Billing status", selection: $options.billingFilter) {
                    ForEach(ReportBillingFilter.allCases) { value in
                        Text(value.label).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
            }

            settingRow("Rounding") {
                HStack(spacing: 8) {
                    Picker("Rounding", selection: $options.rounding) {
                        ForEach(ReportRoundingMode.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)

                    Picker("Interval", selection: $options.roundingMinutes) {
                        ForEach([1, 5, 6, 10, 12, 15, 30, 60], id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                    .disabled(options.rounding == .none)
                }
            }

            settingRow("Duration format") {
                Picker("Duration format", selection: $options.durationFormat) {
                    ForEach(ReportDurationFormat.allCases) { value in
                        Text(value.label).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
            }

            settingRow("File format") {
                Picker("File format", selection: $format) {
                    ForEach(ReportFileFormat.allCases) { value in
                        Text(value.label).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
            }

            Divider().padding(.vertical, 8)

            Toggle("Round individual entries", isOn: $options.roundIndividualEntries)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .disabled(options.rounding == .none)

            Toggle(
                "Include app usage already covered by time entries",
                isOn: $options.includeCoveredAppUsage
            )
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            .disabled(options.include == .timeEntries)

            Text("By default, app usage inside a time entry is absorbed so the report does not double-count that period.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .lineSpacing(2)

            Toggle("Include app usage shorter than 1 minute", isOn: $options.includeShortEntries)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .disabled(options.include == .timeEntries)

            Text("Turn this off for cleaner advanced reports; manual time entries are never removed by this filter.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .lineSpacing(2)
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MetridayTheme.line, lineWidth: 1)
        )
    }

    private var easySettingsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Easy report options")
                .font(.system(size: 15, weight: .bold))
                .padding(.bottom, 12)

            settingRow("Include") {
                Picker("Include", selection: $options.include) {
                    ForEach(ReportIncludeMode.allCases) { value in
                        Text(value.label).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
            }

            settingRow("Rounding") {
                HStack(spacing: 8) {
                    Picker("Rounding", selection: $options.rounding) {
                        ForEach(ReportRoundingMode.allCases) { value in
                            Text(value.label).tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)

                    Picker("Interval", selection: $options.roundingMinutes) {
                        ForEach([1, 5, 6, 10, 12, 15, 30, 60], id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                    .disabled(options.rounding == .none)
                }
            }

            settingRow("File format") {
                Picker("File format", selection: $format) {
                    ForEach(ReportFileFormat.allCases) { value in
                        Text(value.label).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
            }

            Text("Easy reports keep the common Timing workflow visible while Advanced mode exposes project, billing, grouping, and duration controls.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .lineSpacing(2)
                .padding(.top, 8)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MetridayTheme.line, lineWidth: 1)
        )
    }

    private var projectPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Projects", systemImage: "folder")
                .font(.system(size: 14, weight: .bold))

            Toggle("All projects", isOn: Binding(
                get: { options.projectIDs.isEmpty },
                set: { enabled in
                    if enabled {
                        options.projectIDs.removeAll()
                    } else if let first = projectStore.activeProjects.first {
                        options.projectIDs = [first.id]
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 11))

            ForEach(projectStore.activeProjects) { project in
                Toggle(project.name, isOn: Binding(
                    get: { options.projectIDs.contains(project.id) },
                    set: { selected in
                        if selected {
                            options.projectIDs.insert(project.id)
                        } else {
                            options.projectIDs.remove(project.id)
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .padding(.leading, 16)
            }

            Text(projectScopeDescription)
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MetridayTheme.line, lineWidth: 1)
        )
    }

    private var dateRangePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Date range", systemImage: "calendar")
                .font(.system(size: 14, weight: .bold))

            Picker("Range", selection: $rangePreset) {
                ForEach(ReportDateRangePreset.allCases) { value in
                    Text(value.label).tag(value)
                }
            }
            .labelsHidden()
            .frame(width: 260)

            HStack(spacing: 18) {
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                DatePicker("To", selection: $endDate, displayedComponents: .date)
            }

            Text("\(reportDates.count) day\(reportDates.count == 1 ? "" : "s") included · \(dateRangeLabel)")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MetridayTheme.line, lineWidth: 1)
        )
        .onChange(of: rangePreset) { _, newPreset in
            applyDateRangePreset(newPreset)
        }
        .onChange(of: startDate) { _, newDate in
            let normalized = Calendar.current.startOfDay(for: newDate)
            if normalized != newDate { startDate = normalized }
            if normalized > endDate { endDate = normalized }
            if !isApplyingRangePreset && rangePreset != .custom { rangePreset = .custom }
        }
        .onChange(of: endDate) { _, newDate in
            let normalized = Calendar.current.startOfDay(for: newDate)
            if normalized != newDate { endDate = normalized }
            if normalized < startDate { startDate = normalized }
            if !isApplyingRangePreset && rangePreset != .custom { rangePreset = .custom }
        }
    }

    private var columnsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Columns", systemImage: "rectangle.split.3x1")
                .font(.system(size: 14, weight: .bold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 7) {
                ForEach(ReportColumn.allCases) { column in
                    Toggle(column.label, isOn: Binding(
                        get: { options.columns.contains(column) },
                        set: { enabled in
                            if enabled {
                                options.columns.insert(column)
                            } else {
                                options.columns.remove(column)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                }
            }
            Text("Choose the fields delivered to CSV, XLSX, HTML, and PDF tables.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MetridayTheme.line, lineWidth: 1)
        )
    }

    private var presetPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Preset", systemImage: "wand.and.stars")
                .font(.system(size: 15, weight: .bold))
            Picker("Preset", selection: $preset) {
                ForEach(ReportPreset.allCases) { value in
                    Text(value.label).tag(value)
                }
            }
            .labelsHidden()
            .frame(width: 260)
            Text("Presets are starting points; you can still adjust every report option below.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MetridayTheme.line, lineWidth: 1)
        )
        .onChange(of: preset) { _, newPreset in
            applyPreset(newPreset)
        }
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Preview", systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("\(previewRowCount) rows · \(format.label)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)
            }
            Text("Reports use the same local activities, projects, and time entries shown in Review. Filtering and rounding apply only to the exported copy.")
                .font(.system(size: 11))
                .foregroundStyle(MetridayTheme.secondary)
                .lineSpacing(3)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MetridayTheme.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var previewRowCount: Int {
        max(0, ReportExporter.csv(
            activityDays: reportActivityDays,
            timeEntries: reportTimeEntries,
            projectStore: projectStore,
            options: options
        ).split(separator: "\n", omittingEmptySubsequences: true).count - 1)
    }

    private var projectScopeDescription: String {
        if options.projectIDs.isEmpty {
            return "Exporting all active projects and unassigned time."
        }
        return options.includeSubprojects
            ? "Selected projects include their active subprojects."
            : "Only the selected project levels are included."
    }

    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 125, alignment: .leading)
            content()
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func applyPreset(_ preset: ReportPreset) {
        switch preset {
        case .custom:
            return
        case .timesheet:
            options.include = .both
            options.groupBy = .project
        case .timesheetWeekDay:
            options.include = .both
            options.groupBy = .weekAndDay
        case .timesheetWeekDayNotes:
            options.include = .both
            options.groupBy = .weekAndDay
            options.columns.insert(.notes)
        case .weeklySnippet:
            options.include = .both
            options.groupBy = .week
        case .timePerProject:
            options.include = .both
            options.groupBy = .project
        case .timePerApplication:
            options.include = .appUsage
            options.groupBy = .application
        case .timePerDocument:
            options.include = .appUsage
            options.groupBy = .document
        case .ultraDetailed:
            options.include = .both
            options.groupBy = .none
            options.columns = Set(ReportColumn.allCases)
            options.includeShortEntries = true
        case .rawTimeEntries:
            options.include = .timeEntries
            options.groupBy = .none
        case .rawAppUsage:
            options.include = .appUsage
            options.groupBy = .none
        }
    }

    private func export() {
        let panel = NSSavePanel()
        switch format {
        case .csv:
            panel.allowedContentTypes = [.commaSeparatedText]
        case .xlsx:
            panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        case .json:
            panel.allowedContentTypes = [.json]
        case .html:
            panel.allowedContentTypes = [.html]
        case .pdf:
            panel.allowedContentTypes = [.pdf]
        }
        panel.nameFieldStringValue = "metriday-report-\(dateRangeLabel.replacingOccurrences(of: "–", with: "-"))" + "." + format.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ReportExporter.write(
                to: url,
                format: format,
                activityDays: reportActivityDays,
                timeEntries: reportTimeEntries,
                projectStore: projectStore,
                options: options
            )
            statusMessage = "Exported \(url.lastPathComponent)"
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private var reportDates: [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(startDate, endDate))
        let end = calendar.startOfDay(for: max(startDate, endDate))
        var dates: [Date] = []
        var cursor = start
        while cursor <= end, dates.count < 3_650 {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return dates
    }

    private var reportActivityDays: [(date: Date, segments: [ActivitySegment])] {
        reportDates.map { date in
            let rawSegments = monitor.segments(for: date) + screenTimeStore.segments(for: date)
            return (
                date: date,
                segments: categoryStore.applyingCategories(
                    to: rawSegments,
                    filterStore: filterStore,
                    date: date
                ).filter(matchesSelectedDevice)
            )
        }
    }

    private func matchesSelectedDevice(_ segment: ActivitySegment) -> Bool {
        let selectedDevice = appState.activitiesPreferences.selectedDevice
        return selectedDevice == "All Devices" || selectedDevice == "all" || segment.deviceName == selectedDevice
    }

    private var reportTimeEntries: [TimeEntry] {
        let calendar = Calendar.current
        guard let first = reportDates.first,
              let last = reportDates.last,
              let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: last) else {
            return []
        }
        let rangeStart = calendar.startOfDay(for: first)
        return timeEntryStore.materializedEntries().filter {
            $0.start < exclusiveEnd && $0.end > rangeStart
        }
    }

    private var dateRangeLabel: String {
        guard let first = reportDates.first, let last = reportDates.last else { return "No dates" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        if Calendar.current.isDate(first, inSameDayAs: last) {
            return formatter.string(from: first)
        }
        return "\(formatter.string(from: first))–\(formatter.string(from: last))"
    }

    private func applyDateRangePreset(_ preset: ReportDateRangePreset) {
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: endDate)
        guard preset != .custom else { return }
        isApplyingRangePreset = true
        defer { isApplyingRangePreset = false }
        switch preset {
        case .custom:
            return
        case .thisWeek:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: anchor) else { return }
            startDate = calendar.startOfDay(for: interval.start)
            endDate = calendar.startOfDay(for: interval.end.addingTimeInterval(-1))
        case .lastSevenDays:
            startDate = calendar.date(byAdding: .day, value: -6, to: anchor) ?? anchor
            endDate = anchor
        case .thisMonth:
            guard let interval = calendar.dateInterval(of: .month, for: anchor) else { return }
            startDate = calendar.startOfDay(for: interval.start)
            endDate = calendar.startOfDay(for: interval.end.addingTimeInterval(-1))
        }
    }
}

private enum ReportDateRangePreset: String, CaseIterable, Identifiable {
    case custom
    case thisWeek
    case lastSevenDays
    case thisMonth

    var id: Self { self }

    var label: String {
        switch self {
        case .custom: return "Custom"
        case .thisWeek: return "This week"
        case .lastSevenDays: return "Last 7 days"
        case .thisMonth: return "This month"
        }
    }
}

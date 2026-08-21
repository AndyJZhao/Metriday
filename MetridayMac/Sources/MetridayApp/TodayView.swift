import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: MarkdownStore
    @ObservedObject var monitor: AppActivityMonitor
    @ObservedObject var filterStore: ActivityFilterStore
    @ObservedObject var categoryStore: ActivityCategoryStore
    @ObservedObject var timeEntryStore: TimeEntryStore
    @ObservedObject var screenTimeStore: ScreenTimeStore
    @ObservedObject var calendarStore: CalendarEventStore
    @State private var selectedActivity: ActivitySegment?
    @State private var selectedTimeEntry: TimeEntry?
    @State private var selectedCalendarEvent: CalendarEventItem?

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 55)
                            TimelineGrid(showLabels: true)
                        }
                        .frame(width: 76)
                        plannedColumn
                            .frame(width: max(340, (proxy.size.width - 76) * 0.44))
                        Divider()
                        actualColumn
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            insightBar
                .padding(12)
        }
        .background(.white)
        .sheet(item: $selectedActivity) { activity in
            ActivityDetailSheet(
                activity: activity,
                category: category(for: activity),
                projectName: appState.projectStore.name(for: activity.projectID),
                billingStatus: appState.projectStore.resolvedBillingStatus(for: activity.projectID),
                timeEntryStore: timeEntryStore,
                selectedDate: appState.selectedDate
            )
        }
        .sheet(item: $selectedTimeEntry) { entry in
            TodayTimeEntryDetailSheet(
                entry: entry,
                projects: appState.projectStore.activeProjects,
                timeEntryStore: timeEntryStore
            )
        }
        .sheet(item: $selectedCalendarEvent) { event in
            CalendarEventDetailSheet(
                event: event,
                projectID: appState.suggestedProjectID(for: event),
                timeEntryStore: timeEntryStore
            )
        }
    }

    private var plannedColumn: some View {
        VStack(spacing: 0) {
            TimelineColumnHeader(title: "Plan", subtitle: "What I planned")
            ZStack(alignment: .topLeading) {
                TimelineGrid()
                ForEach(calendarEventTimelineItems(events: calendarStore.events, date: appState.selectedDate)) { item in
                    CalendarEventTimelineBlock(item: item) {
                        selectedCalendarEvent = item.event
                    }
                    .padding(.horizontal, 10)
                    .zIndex(1)
                }
                ForEach(scheduledTasks) { task in
                    if let start = task.startMinute, let end = task.endMinute {
                        StaticTimelineBlock(
                            title: task.title,
                            start: start,
                            end: end,
                            symbol: symbol(for: task),
                            isCurrent: appState.currentTask?.id == task.id,
                            actual: timeBlockExecutionSummary(
                                taskID: task.id,
                                entries: timeEntryStore.materializedEntries(),
                                runningTimer: timeEntryStore.runningTimer,
                                date: appState.selectedDate
                            )
                        )
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appState.section = .plan
                            appState.selectedTaskID = task.id
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Plan \(task.title), \(TimeFormat.range(start: start, end: end))\(executionAccessibilitySuffix(for: task))")
                    }
                }
                if Calendar.current.isDateInToday(appState.selectedDate) {
                    currentTimeLine
                }
            }
            .frame(height: TimelineMetrics.totalHeight)
        }
    }

    private var scheduledTasks: [PlanTask] {
        store.tasks
            .filter { $0.startMinute != nil && $0.endMinute != nil }
            .sorted { ($0.startMinute ?? 0) < ($1.startMinute ?? 0) }
    }

    private func symbol(for task: PlanTask) -> String {
        let title = task.title.lowercased()
        if title.contains("lunch") || title.contains("break") { return "fork.knife" }
        if title.contains("read") || title.contains("review") { return "doc.text" }
        if title.contains("write") || title.contains("draft") { return "square.and.pencil" }
        if title.contains("experiment") || title.contains("research") { return "flask" }
        return "checkmark.circle"
    }

    private func executionAccessibilitySuffix(for task: PlanTask) -> String {
        let summary = timeBlockExecutionSummary(
            taskID: task.id,
            entries: timeEntryStore.materializedEntries(),
            runningTimer: timeEntryStore.runningTimer,
            date: appState.selectedDate
        )
        return summary.hasExecution ? ", \(summary.statusLabel)" : ""
    }

    private var actualColumn: some View {
        VStack(spacing: 0) {
            ActivityColumnHeader(monitor: monitor, recordedEntryCount: visibleTimeEntries.count)
            ZStack(alignment: .topLeading) {
                TimelineGrid()
                ForEach(visibleActivitySegments) { segment in
                    actualBlock(segment: segment) {
                        ActivityRow(
                            minutes: segment.duration,
                            title: segment.displayTitle,
                            range: TimeFormat.range(start: segment.startMinute, end: segment.endMinute),
                            symbol: symbol(for: segment),
                            bundleIdentifier: segment.bundleIdentifier,
                            relevance: segment.relevance,
                            categoryColor: categoryColor(for: category(for: segment))
                        )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedActivity = segment }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Actual \(segment.displayTitle), \(TimeFormat.range(start: segment.startMinute, end: segment.endMinute))")
                }
                ForEach(visibleTimeEntries) { entry in
                    recordedTimeBlock(entry)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedTimeEntry = timeEntryStore.materializedEntries().first(where: { $0.id == entry.id })
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Recorded \(entry.title), \(TimeFormat.range(start: entry.startSecond / 60, end: Int(ceil(Double(entry.endSecond) / 60.0))))")
                }
                if Calendar.current.isDateInToday(appState.selectedDate) {
                    currentTimeLine
                }
            }
            .frame(height: TimelineMetrics.totalHeight)
        }
    }

    private var visibleTimeEntries: [VisibleTimeEntry] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: appState.selectedDate)
        let timelineStart = dayStart.addingTimeInterval(TimeInterval(TimelineMetrics.startMinute * 60))
        let timelineEnd = dayStart.addingTimeInterval(TimeInterval(TimelineMetrics.endMinute * 60))

        return timeEntryStore.materializedEntries().compactMap { entry in
            let start = max(entry.start, timelineStart)
            let end = min(entry.end, timelineEnd)
            guard end > start else { return nil }
            return VisibleTimeEntry(
                id: entry.id,
                title: entry.title,
                startSecond: Int(start.timeIntervalSince(dayStart)),
                endSecond: Int(end.timeIntervalSince(dayStart)),
                isRunning: timeEntryStore.runningTimer?.id == entry.id
            )
        }
        .sorted { $0.startSecond < $1.startSecond }
    }

    private func recordedTimeBlock(_ entry: VisibleTimeEntry) -> some View {
        let height = TimelineMetrics.height(startSecond: entry.startSecond, endSecond: entry.endSecond)
        return HStack {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: entry.isRunning ? "timer" : "clock")
                    Text(entry.title)
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold))
                Text(TimeFormat.range(
                    start: entry.startSecond / 60,
                    end: Int(ceil(Double(entry.endSecond) / 60.0))
                ))
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
            }
            .padding(.horizontal, 10)
            .frame(width: 188, height: height, alignment: .topLeading)
            .background(Color.white.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(entry.isRunning ? MetridayTheme.accent : MetridayTheme.warning, lineWidth: 1.2)
            )
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, 10)
        .offset(y: TimelineMetrics.y(forSecond: entry.startSecond))
    }

    private var visibleActivitySegments: [ActivitySegment] {
        let sourceSegments = categoryStore.applyingCategories(
            to: monitor.observedSegments + screenTimeStore.segments,
            filterStore: filterStore,
            date: appState.selectedDate
        ).filter(matchesSelectedDevice)
        let clipped: [ActivitySegment] = sourceSegments.compactMap { segment in
            let timelineStart = TimelineMetrics.startMinute * 60
            let timelineEnd = TimelineMetrics.endMinute * 60
            let start = max(timelineStart, segment.startSecond)
            let end = min(timelineEnd, segment.endSecond)
            guard end > start else { return nil }
            return ActivitySegment(
                id: segment.id,
                appName: segment.appName,
                bundleIdentifier: segment.bundleIdentifier,
                deviceName: segment.deviceName,
                windowTitle: segment.windowTitle,
                resource: segment.resource,
                startMinute: start / 60,
                endMinute: Int(ceil(Double(end) / 60.0)),
                startSecond: start,
                endSecond: end,
                relevance: segment.relevance,
                projectID: segment.projectID,
                activityDate: segment.activityDate
            )
        }
        return condensedActivitySegments(clipped)
    }

    private func condensedActivitySegments(_ segments: [ActivitySegment]) -> [ActivitySegment] {
        var result: [ActivitySegment] = []
        let maximumRun = 20 * 60
        let maximumGap = 45

        for segment in segments.sorted(by: { $0.startSecond < $1.startSecond }) {
            guard let lastIndex = result.indices.last else {
                result.append(segment)
                continue
            }

            let last = result[lastIndex]
            let canMerge = category(for: last).id == category(for: segment).id
                && segment.startSecond - last.endSecond <= maximumGap
                && segment.endSecond - last.startSecond <= maximumRun
            guard canMerge else {
                result.append(segment)
                continue
            }

            let sameActivity = last.appName == segment.appName
                && last.bundleIdentifier == segment.bundleIdentifier
                && last.windowTitle == segment.windowTitle
            result[lastIndex].endSecond = max(last.endSecond, segment.endSecond)
            if !sameActivity {
                result[lastIndex].appName = condensedTitle(for: segment.relevance)
                result[lastIndex].bundleIdentifier = "com.metriday.mixed"
                result[lastIndex].windowTitle = ""
            }
        }
        return result
    }

    private func condensedTitle(for relevance: ActivityRelevance) -> String {
        switch relevance {
        case .related:
            return "Mixed work activity"
        case .distracted:
            return "Mixed distraction"
        case .other:
            return "Mixed activity"
        case .idle:
            return "Idle"
        }
    }

    private func symbol(for segment: ActivitySegment) -> String? {
        switch segment.bundleIdentifier {
        case "com.microsoft.VSCode", "com.apple.dt.Xcode":
            return "chevron.left.forwardslash.chevron.right"
        case "com.apple.Terminal", "com.googlecode.iterm2":
            return "terminal"
        case "com.google.Chrome", "com.apple.Safari", "com.brave.Browser", "com.operasoftware.Opera":
            return "globe"
        case "com.apple.Preview":
            return "doc.richtext"
        case "com.apple.Notes", "md.obsidian":
            return "note.text"
        case "com.metriday.idle":
            return nil
        default:
            return "rectangle.on.rectangle"
        }
    }

    @ViewBuilder
    private func actualBlock<Content: View>(segment: ActivitySegment, @ViewBuilder content: () -> Content) -> some View {
        let height = TimelineMetrics.height(startSecond: segment.startSecond, endSecond: segment.endSecond)
        let category = category(for: segment)
        if category.role == .idle {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.black.opacity(0.025))
                if segment.durationSeconds >= 30 * 60 {
                    Text("\(segment.duration)m idle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MetridayTheme.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 5)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: max(3, height))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .padding(.horizontal, 10)
            .offset(y: TimelineMetrics.y(forSecond: segment.startSecond))
            .help("\(segment.displayTitle) · \(segment.duration)m")
        } else if segment.durationSeconds < 30 * 60 {
            Rectangle()
                .fill(categoryColor(for: category))
                .frame(maxWidth: .infinity)
                .frame(height: max(3, height))
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .padding(.horizontal, 10)
                .offset(y: TimelineMetrics.y(forSecond: segment.startSecond))
                .help("\(segment.displayTitle) · \(segment.duration)m")
        } else {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(categoryColor(for: category).opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(MetridayTheme.line, lineWidth: 1))
                .frame(height: height)
                .padding(.horizontal, 10)
                .offset(y: TimelineMetrics.y(forSecond: segment.startSecond))
        }
    }

    private func category(for segment: ActivitySegment) -> ActivityCategoryDefinition {
        categoryStore.category(for: segment, filterStore: filterStore, date: appState.selectedDate)
    }

    private func categoryColor(for category: ActivityCategoryDefinition) -> Color {
        let color: Color
        switch category.color {
        case .blue: color = MetridayTheme.accentDeep
        case .green: color = MetridayTheme.success
        case .orange: color = MetridayTheme.warning
        case .purple: color = .purple
        case .red: color = MetridayTheme.danger
        case .graphite: color = MetridayTheme.secondary
        }
        return color
    }

    private var currentTimeLine: some View {
        Rectangle()
            .fill(MetridayTheme.accent)
            .frame(height: 1)
            .offset(y: TimelineMetrics.y(for: currentMinute))
    }

    private var currentMinute: Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: .now)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private var insightBar: some View {
        let summary = ActivitySummary(segments: effectiveActivitySegments)
        return Button {
            appState.section = .rules
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 23))
                    .foregroundStyle(MetridayTheme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 12) {
                        Text(summary.activeMinutes > 0 ? "\(summary.activeMinutes)m active" : "Waiting for activity")
                            .fontWeight(.semibold)
                        Text("·").foregroundStyle(MetridayTheme.secondary)
                        Text("\(summary.taskRelatedPercentage)% task-related")
                            .fontWeight(.semibold)
                            .foregroundStyle(MetridayTheme.success)
                        Text("·").foregroundStyle(MetridayTheme.secondary)
                        Text("\(summary.distractedMinutes)m distraction")
                            .fontWeight(.semibold)
                            .foregroundStyle(summary.distractedMinutes > 0 ? MetridayTheme.danger : MetridayTheme.secondary)
                    }
                    Text(insightText(summary: summary))
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                Text("Adjust blocklist")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MetridayTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(MetridayTheme.line)
                    }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .metridayPanel(radius: 10)
    }

    private var effectiveActivitySegments: [ActivitySegment] {
        categoryStore.applyingCategories(
            to: monitor.observedSegments + screenTimeStore.segments,
            filterStore: filterStore,
            date: appState.selectedDate
        ).filter(matchesSelectedDevice)
    }

    private func matchesSelectedDevice(_ segment: ActivitySegment) -> Bool {
        let selectedDevice = appState.activitiesPreferences.selectedDevice
        return selectedDevice == "All Devices" || selectedDevice == "all" || segment.deviceName == selectedDevice
    }

    private func insightText(summary: ActivitySummary) -> String {
        if !monitor.accessibilityTrusted {
            return "App usage is being captured locally. Allow Accessibility access to include window titles and document context."
        }
        if summary.totalMinutes == 0 {
            return "Metriday will group foreground app and window activity here as you work."
        }
        if summary.distractedMinutes > 0 {
            return "\(summary.idleMinutes)m idle is excluded from the focus score. Distraction is visible in the actual timeline."
        }
        return "\(summary.idleMinutes)m idle is excluded from the focus score. Activity is grouped locally by app and window title."
    }
}

struct ActivityDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let activity: ActivitySegment
    let category: ActivityCategoryDefinition
    let projectName: String
    let billingStatus: BillingStatus
    @ObservedObject var timeEntryStore: TimeEntryStore
    let selectedDate: Date

    private var categoryColor: Color {
        switch category.color {
        case .blue: return MetridayTheme.accentDeep
        case .green: return MetridayTheme.success
        case .orange: return MetridayTheme.warning
        case .purple: return .purple
        case .red: return MetridayTheme.danger
        case .graphite: return MetridayTheme.secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(MetridayTheme.graphite)
                    .frame(width: 42, height: 42)
                    .background(MetridayTheme.sidebar)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activity detail")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MetridayTheme.accent)
                    Text(activity.appName.isEmpty ? "Unknown App" : activity.appName)
                        .font(.system(size: 19, weight: .bold))
                        .lineLimit(2)
                    Text(TimeFormat.range(start: activity.startMinute, end: activity.endMinute))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 10) {
                detailRow(label: "Category", value: category.name, color: categoryColor)
                detailRow(label: "Project", value: projectName)
                detailRow(label: "Duration", value: formatDuration(activity.durationSeconds))
                if !activity.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailRow(label: "Window", value: activity.windowTitle)
                }
                if let host = URL(string: activity.resource)?.host, !host.isEmpty {
                    detailRow(label: "Website", value: host)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MetridayTheme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Spacer()
                Button("Record Time Entry") {
                    recordTimeEntry()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("today.activity.record-time-entry")
            }
        }
        .padding(24)
        .frame(width: 430)
    }

    private func detailRow(label: String, value: String, color: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MetridayTheme.secondary)
                .frame(width: 72, alignment: .leading)
            if let color {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
            Spacer()
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = Int((Double(seconds) / 60.0).rounded())
        if minutes < 1 { return "<1m" }
        let hours = minutes / 60
        return hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
    }

    private func recordTimeEntry() {
        let day = Calendar.current.startOfDay(for: selectedDate)
        _ = timeEntryStore.addEntry(
            title: activity.appName.isEmpty ? "App activity" : activity.appName,
            projectID: activity.projectID,
            notes: activity.displayTitle,
            start: day.addingTimeInterval(TimeInterval(activity.startSecond)),
            end: day.addingTimeInterval(TimeInterval(activity.endSecond)),
            billingStatus: billingStatus
        )
        dismiss()
    }
}

private struct TodayTimeEntryDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: TimeEntry
    let projects: [TrackingProject]
    @ObservedObject var timeEntryStore: TimeEntryStore

    @State private var title: String
    @State private var projectID: UUID?
    @State private var billingStatus: BillingStatus
    @State private var start: Date
    @State private var end: Date
    @State private var notes: String

    init(entry: TimeEntry, projects: [TrackingProject], timeEntryStore: TimeEntryStore) {
        self.entry = entry
        self.projects = projects
        self.timeEntryStore = timeEntryStore
        _title = State(initialValue: entry.title)
        _projectID = State(initialValue: entry.projectID)
        _billingStatus = State(initialValue: entry.billingStatus)
        _start = State(initialValue: entry.start)
        _end = State(initialValue: entry.end)
        _notes = State(initialValue: entry.notes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Edit Time Entry")
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.borderless)
            }

            TimeEntryTitleField(
                title: $title,
                billingStatus: $billingStatus,
                placeholder: "What did you work on?",
                entries: timeEntryStore.entries,
                projects: projects,
                excludingEntryID: entry.id
            )

            Picker("Project", selection: $projectID) {
                Text("Unassigned").tag(nil as UUID?)
                ForEach(projects) { project in
                    Text(project.name).tag(project.id as UUID?)
                }
            }

            Picker("Billing Status", selection: $billingStatus) {
                ForEach(BillingStatus.allCases) { status in
                    Text(status.label).tag(status)
                }
            }

            DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
            DatePicker("End", selection: $end, displayedComponents: [.date, .hourAndMinute])

            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3, reservesSpace: true)

            HStack {
                Button("Delete", role: .destructive) {
                    timeEntryStore.delete(entry)
                    dismiss()
                }
                Spacer()
                Button("Save") {
                    var updated = entry
                    updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.projectID = projectID
                    updated.billingStatus = billingStatus
                    updated.start = start
                    updated.end = end
                    updated.notes = notes
                    guard !updated.title.isEmpty, updated.end > updated.start else { return }
                    timeEntryStore.update(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || end <= start)
            }
        }
        .padding(24)
        .frame(width: 430)
        .onChange(of: projectID) { _, newProjectID in
            billingStatus = resolvedProjectBillingStatus(for: newProjectID, in: projects)
        }
    }
}

private struct VisibleTimeEntry: Identifiable {
    let id: UUID
    let title: String
    let startSecond: Int
    let endSecond: Int
    let isRunning: Bool
}

struct ActivityColumnHeader: View {
    @ObservedObject var monitor: AppActivityMonitor
    var recordedEntryCount = 0

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Actual").font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(MetridayTheme.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)

            if !monitor.accessibilityTrusted {
                Button {
                    monitor.requestAccessibilityAccess()
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .help("Allow Accessibility access to read window titles")
                .accessibilityIdentifier("activity.accessibility")
            }

            Button {
                monitor.toggleTracking()
            } label: {
                Label(
                    monitor.isTracking ? "Pause" : "Track",
                    systemImage: monitor.isTracking ? "pause.fill" : "play.fill"
                )
                .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("activity.toggle")
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 55)
    }

    private var subtitle: String {
        let recorded = recordedEntryCount > 0 ? " · \(recordedEntryCount) recorded" : ""
        if !monitor.isTracking { return "Tracking paused\(recorded)" }
        if monitor.isIdle { return "Live · Idle detected · \(elapsedLabel)" }
        if monitor.currentWindowTitle.isEmpty {
            return "Live · \(monitor.currentApplication) · \(elapsedLabel)\(recorded)"
        }
        return "Live · \(monitor.currentApplication) · \(elapsedLabel)\(recorded)"
    }

    private var elapsedLabel: String {
        let seconds = max(0, monitor.currentDurationMinutes * 60)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(max(1, minutes))m"
    }
}

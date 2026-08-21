import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 236)
                .fixedSize(horizontal: true, vertical: false)
                .zIndex(2)

            Divider()

            VStack(spacing: 0) {
                GlobalTopHeader(store: appState.markdownStore, monitor: appState.activityMonitor)
                    .zIndex(2)
                Divider()

                Group {
                    switch appState.section {
                    case .today:
                        TodayView(
                            store: appState.markdownStore,
                            monitor: appState.activityMonitor,
                            filterStore: appState.filterStore,
                            categoryStore: appState.categoryStore,
                            timeEntryStore: appState.timeEntryStore,
                            screenTimeStore: appState.screenTimeStore
                        )
                    case .plan:
                        PlanView()
                    case .activities:
                        ActivitiesView(
                            monitor: appState.activityMonitor,
                            projectStore: appState.projectStore,
                            filterStore: appState.filterStore,
                            categoryStore: appState.categoryStore,
                            preferences: appState.activitiesPreferences,
                            trackingPreferences: appState.preferences,
                            timeEntryStore: appState.timeEntryStore,
                            calendarStore: appState.calendarStore,
                            reminderStore: appState.reminderStore,
                            phoneCallStore: appState.phoneCallStore,
                            screenTimeStore: appState.screenTimeStore,
                            teamStore: appState.teamStore,
                            selectedDate: appState.selectedDate
                        )
                    case .stats:
                        StatsView(
                            monitor: appState.activityMonitor,
                            filterStore: appState.filterStore,
                            categoryStore: appState.categoryStore,
                            screenTimeStore: appState.screenTimeStore,
                            projectStore: appState.projectStore,
                            timeEntryStore: appState.timeEntryStore,
                            trackingPreferences: appState.preferences,
                            selectedDate: appState.selectedDate
                        )
                    case .reports:
                        ReportsView(
                            monitor: appState.activityMonitor,
                            filterStore: appState.filterStore,
                            categoryStore: appState.categoryStore,
                            screenTimeStore: appState.screenTimeStore,
                            projectStore: appState.projectStore,
                            timeEntryStore: appState.timeEntryStore,
                            selectedDate: appState.selectedDate
                        )
                    case .teams:
                        TeamsView(
                            teamStore: appState.teamStore,
                            projectStore: appState.projectStore,
                            timeEntryStore: appState.timeEntryStore
                        )
                    case .review:
                        ReviewView(
                            monitor: appState.activityMonitor,
                            filterStore: appState.filterStore,
                            categoryStore: appState.categoryStore,
                            screenTimeStore: appState.screenTimeStore,
                            projectStore: appState.projectStore,
                            timeEntryStore: appState.timeEntryStore,
                            selectedDate: appState.selectedDate
                        )
                    case .rules:
                        RulesView(
                            blocker: appState.blocker,
                            projectStore: appState.projectStore
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MetridayTheme.canvas)
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(MetridayTheme.canvas)
        .tint(MetridayTheme.accent)
        .overlay {
            ZStack {
                IdlePromptPresenter(
                    monitor: appState.activityMonitor,
                    timeEntryStore: appState.timeEntryStore,
                    projectStore: appState.projectStore
                )
                CallPromptPresenter(
                    monitor: appState.activityMonitor,
                    timeEntryStore: appState.timeEntryStore,
                    projectStore: appState.projectStore
                )
                TimerCheckInPresenter(
                    timeEntryStore: appState.timeEntryStore,
                    projectStore: appState.projectStore
                )
            }
        }
    }
}

private struct TimerCheckInPresenter: View {
    @ObservedObject var timeEntryStore: TimeEntryStore
    @ObservedObject var projectStore: ProjectStore

    @State private var pendingTimer: RunningTimer?
    @State private var lastPromptedTimerID: UUID?

    private var timerStateKey: String {
        guard let timer = timeEntryStore.runningTimer else { return "none" }
        let remaining = timeEntryStore.runningTimerRemainingSeconds ?? Int.max
        return "\(timer.id.uuidString)-\(remaining < 0)"
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear(perform: evaluateTimer)
                .onChange(of: timerStateKey) { _, _ in
                    evaluateTimer()
                }
        }
        .sheet(item: $pendingTimer) { timer in
            TimerCheckInSheet(
                timer: timer,
                projectName: projectStore.name(for: timer.projectID),
                timeEntryStore: timeEntryStore
            ) {
                pendingTimer = nil
            }
        }
    }

    private func evaluateTimer() {
        guard let timer = timeEntryStore.runningTimer,
              timeEntryStore.runningTimerRemainingSeconds ?? 0 < 0,
              lastPromptedTimerID != timer.id else { return }
        lastPromptedTimerID = timer.id
        pendingTimer = timer
    }
}

private struct TimerCheckInSheet: View {
    @Environment(\.dismiss) private var dismiss

    let timer: RunningTimer
    let projectName: String
    @ObservedObject var timeEntryStore: TimeEntryStore
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Timer check-in", systemImage: "timer")
                .font(.system(size: 18, weight: .bold))
            Text("Your estimate for \(timer.title) has ended. Are you still working on it?")
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(projectName) · running for \(formatDuration(timeEntryStore.runningDurationSeconds))")
                .font(.system(size: 11))
                .foregroundStyle(MetridayTheme.secondary)

            HStack {
                Button("Dismiss") {
                    close()
                }
                Spacer()
                Button("Stop Timer", role: .destructive) {
                    _ = timeEntryStore.stopTimer()
                    close()
                }
                Button("Keep Working · +15m") {
                    timeEntryStore.setRunningTimerEstimate(
                        to: timeEntryStore.runningDurationSeconds + 15 * 60
                    )
                    close()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 430)
    }

    private func close() {
        onDismiss()
        dismiss()
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }
}

private struct IdlePromptPresenter: View {
    @ObservedObject var monitor: AppActivityMonitor
    @ObservedObject var timeEntryStore: TimeEntryStore
    @ObservedObject var projectStore: ProjectStore

    @State private var pendingInterval: IdleInterval?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(monitor.$pendingIdleInterval) { interval in
                pendingInterval = interval
            }
            .sheet(item: $pendingInterval) { interval in
                IdleTimeEntrySheet(
                    interval: interval,
                    entries: timeEntryStore.entries,
                    projects: projectStore.activeProjects
                ) { title, projectID, notes, billingStatus, start, end in
                    if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        _ = timeEntryStore.addEntry(
                            title: title,
                            projectID: projectID,
                            notes: notes,
                            start: start,
                            end: end,
                            billingStatus: billingStatus
                        )
                    }
                    monitor.dismissPendingIdleInterval()
                    pendingInterval = nil
                } onSkip: {
                    monitor.dismissPendingIdleInterval()
                    pendingInterval = nil
                }
            }
    }
}

private struct IdleTimeEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let interval: IdleInterval
    let entries: [TimeEntry]
    let projects: [TrackingProject]
    let onSave: (String, UUID?, String, BillingStatus, Date, Date) -> Void
    let onSkip: () -> Void

    @State private var title = ""
    @State private var projectID: UUID?
    @State private var notes = ""
    @State private var billingStatus: BillingStatus
    @State private var start: Date
    @State private var end: Date

    init(
        interval: IdleInterval,
        entries: [TimeEntry],
        projects: [TrackingProject],
        onSave: @escaping (String, UUID?, String, BillingStatus, Date, Date) -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.interval = interval
        self.entries = entries
        self.projects = projects
        self.onSave = onSave
        self.onSkip = onSkip
        _billingStatus = State(initialValue: .billable)
        _start = State(initialValue: interval.start)
        _end = State(initialValue: interval.end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("What did you do while away?", systemImage: "moon.zzz")
                .font(.system(size: 18, weight: .bold))
            Text("Idle interval: \(formatTime(start))–\(formatTime(end)) · \(formatDuration(durationSeconds))")
                .font(.system(size: 11))
                .foregroundStyle(MetridayTheme.secondary)

            HStack(spacing: 7) {
                Label("Adjust time", systemImage: "arrow.left.and.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MetridayTheme.secondary)
                Spacer()
                Button("prev") { alignToPreviousEntry() }
                    .buttonStyle(.bordered)
                    .disabled(previousEntryEnd == nil)
                    .help("Align the start to the previous time entry")
                    .accessibilityIdentifier("idle-prompt.previous")
                Button("−5m") { shift(by: -adjustmentMinutes) }
                    .buttonStyle(.bordered)
                    .help("Shift both times by 5 minutes (⌥ 1 minute, ⌘ 15 minutes)")
                    .accessibilityIdentifier("idle-prompt.minus-five")
                Button("+5m") { shift(by: adjustmentMinutes) }
                    .buttonStyle(.bordered)
                    .help("Shift both times by 5 minutes (⌥ 1 minute, ⌘ 15 minutes)")
                    .accessibilityIdentifier("idle-prompt.plus-five")
                Button("next") { alignToNextEntry() }
                    .buttonStyle(.bordered)
                    .disabled(nextEntryStart == nil)
                    .help("Align the end to the next time entry")
                    .accessibilityIdentifier("idle-prompt.next")
            }

            Text("⌥ 1m · ⌘ 15m")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)

            TimeEntryTitleField(
                title: $title,
                billingStatus: $billingStatus,
                placeholder: "Time entry title",
                entries: entries,
                projects: projects
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

            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3, reservesSpace: true)

            HStack {
                Button("Skip") {
                    onSkip()
                    dismiss()
                }
                Spacer()
                Button("Save Time Entry") {
                    onSave(title, projectID, notes, billingStatus, start, end)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || end <= start
                    )
            }
        }
        .padding(24)
        .frame(width: 440)
        .onChange(of: projectID) { _, newProjectID in
            billingStatus = resolvedProjectBillingStatus(for: newProjectID, in: projects)
        }
    }

    private var durationSeconds: Int {
        max(1, Int(end.timeIntervalSince(start).rounded()))
    }

    private var adjustmentMinutes: Int {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) { return 15 }
        if modifiers.contains(.option) { return 1 }
        return 5
    }

    private var previousEntryEnd: Date? {
        entries
            .filter { $0.end <= start }
            .max { $0.end < $1.end }?
            .end
    }

    private var nextEntryStart: Date? {
        entries
            .filter { $0.start >= end }
            .min { $0.start < $1.start }?
            .start
    }

    private func shift(by minutes: Int) {
        let delta = TimeInterval(minutes * 60)
        start = start.addingTimeInterval(delta)
        end = end.addingTimeInterval(delta)
    }

    private func alignToPreviousEntry() {
        guard let boundary = previousEntryEnd else { return }
        shiftInterval(toStart: boundary)
    }

    private func alignToNextEntry() {
        guard let boundary = nextEntryStart else { return }
        shiftInterval(toEnd: boundary)
    }

    private func shiftInterval(toStart target: Date? = nil, toEnd endTarget: Date? = nil) {
        let delta: TimeInterval
        if let target {
            delta = target.timeIntervalSince(start)
        } else if let endTarget {
            delta = endTarget.timeIntervalSince(end)
        } else {
            return
        }
        start = start.addingTimeInterval(delta)
        end = end.addingTimeInterval(delta)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }
}

private struct CallPromptPresenter: View {
    @ObservedObject var monitor: AppActivityMonitor
    @ObservedObject var timeEntryStore: TimeEntryStore
    @ObservedObject var projectStore: ProjectStore

    @State private var pendingInterval: CallInterval?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(monitor.$pendingCallInterval) { interval in
                pendingInterval = interval
            }
            .sheet(item: $pendingInterval) { interval in
                CallTimeEntrySheet(
                    interval: interval,
                    entries: timeEntryStore.entries,
                    projects: projectStore.activeProjects
                ) { title, projectID, notes, billingStatus in
                    if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        _ = timeEntryStore.addEntry(
                            title: title,
                            projectID: projectID,
                            notes: notes,
                            start: interval.start,
                            end: interval.end,
                            billingStatus: billingStatus
                        )
                    }
                    monitor.dismissPendingCallInterval()
                    pendingInterval = nil
                } onSkip: {
                    monitor.dismissPendingCallInterval()
                    pendingInterval = nil
                }
            }
    }
}

private struct CallTimeEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let interval: CallInterval
    let entries: [TimeEntry]
    let projects: [TrackingProject]
    let onSave: (String, UUID?, String, BillingStatus) -> Void
    let onSkip: () -> Void

    @State private var title: String
    @State private var projectID: UUID?
    @State private var notes = ""
    @State private var billingStatus: BillingStatus

    init(
        interval: CallInterval,
        entries: [TimeEntry],
        projects: [TrackingProject],
        onSave: @escaping (String, UUID?, String, BillingStatus) -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.interval = interval
        self.entries = entries
        self.projects = projects
        self.onSave = onSave
        self.onSkip = onSkip
        let inferredTitle = interval.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        _title = State(initialValue: inferredTitle.isEmpty ? "\(interval.appName) call" : inferredTitle)
        _billingStatus = State(initialValue: .billable)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("Record call time?", systemImage: "phone.badge.waveform")
                .font(.system(size: 18, weight: .bold))
            Text("\(interval.appName) · \(formatTime(interval.start))–\(formatTime(interval.end)) · \(formatDuration(interval.durationSeconds))")
                .font(.system(size: 11))
                .foregroundStyle(MetridayTheme.secondary)

            TimeEntryTitleField(
                title: $title,
                billingStatus: $billingStatus,
                placeholder: "Time entry title",
                entries: entries,
                projects: projects
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

            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3, reservesSpace: true)

            HStack {
                Button("Skip") {
                    onSkip()
                    dismiss()
                }
                Spacer()
                Button("Save Time Entry") {
                    onSave(title, projectID, notes, billingStatus)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .onChange(of: projectID) { _, newProjectID in
            billingStatus = resolvedProjectBillingStatus(for: newProjectID, in: projects)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
    }
}

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Metriday 日衡")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(MetridayTheme.graphite)
                Text("Local-first · On this Mac")
                    .font(.system(size: 12))
                    .foregroundStyle(MetridayTheme.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 34)
            .padding(.bottom, 48)

            VStack(spacing: 8) {
                ForEach(AppSection.allCases) { section in
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { appState.section = section }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: section.symbol)
                                .font(.system(size: 19, weight: .medium))
                                .frame(width: 24)
                            Text(section.rawValue)
                                .font(.system(size: 16, weight: appState.section == section ? .semibold : .regular))
                            Spacer()
                            if appState.section == section {
                                Capsule().fill(MetridayTheme.accent).frame(width: 3, height: 22)
                            }
                        }
                            .foregroundStyle(appState.section == section ? MetridayTheme.accent : MetridayTheme.graphite)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 15)
                            .frame(height: 52)
                            .background(appState.section == section ? MetridayTheme.accentSoft : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("sidebar.\(section.rawValue.lowercased())")
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Divider().padding(.horizontal, 16)

            VStack(spacing: 18) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([appState.markdownStore.fileURL])
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "laptopcomputer")
                        Text("Data on this Mac")
                        Spacer()
                        Circle().fill(MetridayTheme.success).frame(width: 8, height: 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("sidebar.data")

                Button {
                    showingSettings = true
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "gearshape")
                        Text("Settings")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("sidebar.settings")
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(appState.syncStore.isEnabled ? MetridayTheme.success : MetridayTheme.secondary)
                    Text(appState.syncStore.isEnabled ? "Data synced" : "Local data only")
                    Spacer()
                }
                .font(.system(size: 12))
                .foregroundStyle(MetridayTheme.secondary)
            }
            .font(.system(size: 13))
            .foregroundStyle(MetridayTheme.secondary)
            .padding(20)
        }
        .background(MetridayTheme.sidebar)
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(
                preferences: appState.preferences,
                monitor: appState.activityMonitor,
                exclusionStore: appState.exclusionStore,
                projectStore: appState.projectStore,
                timeEntryStore: appState.timeEntryStore,
                calendarStore: appState.calendarStore,
                reminderStore: appState.reminderStore,
                phoneCallStore: appState.phoneCallStore,
                screenTimeStore: appState.screenTimeStore,
                localAPIServer: appState.localAPIServer,
                loginItemManager: appState.loginItemManager,
                syncStore: appState.syncStore,
                integrationStore: appState.integrationStore,
                teamStore: appState.teamStore,
                reviewReminderService: appState.reviewReminderService
            )
        }
    }
}

struct GlobalTopHeader: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: MarkdownStore
    @ObservedObject var monitor: AppActivityMonitor

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(dateTitle)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(MetridayTheme.graphite)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                ZStack(alignment: .leading) {
                    Color.clear
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .onTapGesture { appState.goToToday() }
                    .accessibilityHidden(true)

                    HStack(spacing: 12) {
                        Button {
                            appState.section = .plan
                        } label: {
                            Image(systemName: "calendar")
                        }
                        .buttonStyle(.plain)
                        .help("Open Plan")

                        Button("Today") { appState.goToToday() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("header.today")

                        Button { appState.moveSelectedDate(byDays: -1) } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("header.previous-day")

                        Button { appState.moveSelectedDate(byDays: 1) } label: {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("header.next-day")
                    }
                    .padding(.horizontal, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 34)
                .background(MetridayTheme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(MetridayTheme.line.opacity(0.7), lineWidth: 1)
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Date navigation; click empty space for Today")
                .accessibilityAction(named: "Go to Today") { appState.goToToday() }
                .accessibilityIdentifier("header.today-banner")
                .foregroundStyle(MetridayTheme.secondary)
            }
            .frame(width: 250, alignment: .leading)

            Spacer(minLength: 8)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current block")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                    Text(appState.currentTask?.title ?? "No scheduled block")
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(blockSubtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(appState.focusIsActive ? MetridayTheme.accent : MetridayTheme.secondary)
                }
                .frame(width: 210, alignment: .leading)

                Button {
                    appState.focusIsActive.toggle()
                } label: {
                    Label(
                        appState.focusIsActive ? "Pause focus" : "Resume focus",
                        systemImage: appState.focusIsActive ? "pause.fill" : "play.fill"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 10)
                    .frame(height: 42)
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.currentTask == nil)
                .accessibilityIdentifier("header.focus")

                Divider().frame(height: 50)

                Button {
                    appState.section = .rules
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 30))
                            .foregroundStyle(MetridayTheme.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Research Focus").font(.system(size: 13, weight: .semibold))
                            Text(appState.focusIsActive ? "Blocklist active" : "Blocklist ready")
                                .font(.system(size: 11))
                                .foregroundStyle(MetridayTheme.secondary)
                            Text("Adjust allowed sites")
                                .font(.system(size: 11))
                                .foregroundStyle(MetridayTheme.accent)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityIdentifier("header.research-focus")
                .accessibilityLabel("Research Focus; open Rules")
            }
            .padding(.horizontal, 12)
            .frame(height: 90)
            .metridayPanel(radius: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(.white)
    }

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: appState.selectedDate)
    }

    private var blockSubtitle: String {
        guard let task = appState.currentTask, let range = task.timeRange else {
            return store.fileURL.lastPathComponent
        }
        return "\(range)  ·  \(appState.focusIsActive ? "In progress" : "Ready")"
    }
}

struct PageDateHeader: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingDatePicker = false

    var title: String
    var subtitle: String? = nil
    var showsDateControls = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(MetridayTheme.graphite)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(MetridayTheme.secondary)
                }
            }
            Spacer()
            if showsDateControls {
                ZStack(alignment: .leading) {
                    Button {
                        appState.goToToday()
                    } label: {
                        Rectangle()
                            .fill(.clear)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel("Today")
                    .accessibilityIdentifier("\(title.lowercased()).date-today-banner")

                    HStack(spacing: 7) {
                        Button {
                            showingDatePicker.toggle()
                        } label: {
                            Image(systemName: "calendar")
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Choose date")
                        .accessibilityIdentifier("\(title.lowercased()).date-picker")
                        .popover(isPresented: $showingDatePicker, arrowEdge: .bottom) {
                            DatePicker(
                                "Choose date",
                                selection: Binding(
                                    get: { appState.selectedDate },
                                    set: { appState.selectDate($0); showingDatePicker = false }
                                ),
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .padding(12)
                        }

                        HStack(spacing: 0) {
                            Button {
                                appState.moveSelectedDate(byDays: -1)
                            } label: {
                                Image(systemName: "chevron.left")
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Previous day")
                            .accessibilityIdentifier("\(title.lowercased()).date-previous")

                            Divider()
                                .frame(height: 19)

                            Button {
                                appState.goToToday()
                            } label: {
                                Text(dateRangeTitle)
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(minWidth: 86, minHeight: 30)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .accessibilityLabel("Today")
                            .accessibilityIdentifier("\(title.lowercased()).date-today")

                            Divider()
                                .frame(height: 19)

                            Button {
                                appState.moveSelectedDate(byDays: 1)
                            } label: {
                                Image(systemName: "chevron.right")
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Next day")
                            .accessibilityIdentifier("\(title.lowercased()).date-next")
                        }
                    }
                }
                .padding(.horizontal, 4)
                .background(MetridayTheme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(MetridayTheme.line, lineWidth: 1)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Date range")
                .accessibilityIdentifier("\(title.lowercased()).date-range")
            }
        }
    }

    private var dateRangeTitle: String {
        if Calendar.current.isDateInToday(appState.selectedDate) {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter.string(from: appState.selectedDate)
    }
}

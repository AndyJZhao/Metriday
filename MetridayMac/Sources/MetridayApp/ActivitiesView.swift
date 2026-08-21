import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum ActivityDeviceFilter {
    static let all = "All Devices"
}

/// RescueTime-style activity categories. The palette is intentionally owned by
/// the category rather than the application: the same app can be focused in
/// one context and distracting in another.
private enum ActivityCategoryKind: String, CaseIterable, Hashable, Identifiable {
    case focused
    case distracting
    case other
    case idle

    var id: Self { self }

    var label: String {
        switch self {
        case .focused: return "Focused"
        case .distracting: return "Distracting"
        case .other: return "Other"
        case .idle: return "Idle"
        }
    }

    var color: Color {
        switch self {
        case .focused:
            return MetridayTheme.accentDeep
        case .distracting:
            return MetridayTheme.danger
        case .other:
            return MetridayTheme.secondary
        case .idle:
            return MetridayTheme.line
        }
    }

    init(relevance: ActivityRelevance) {
        switch relevance {
        case .related: self = .focused
        case .distracted: self = .distracting
        case .other: self = .other
        case .idle: self = .idle
        }
    }
}

/// The timeline normally spans the whole day. When the Timing-style working
/// hours zoom is enabled, this window keeps the configured interval in view,
/// including overnight windows such as 22:00–06:00.
private struct ActivityTimelineWindow: Equatable {
    let startMinute: Int
    let endMinute: Int
    let wrapAtMinute: Int

    init(
        zoomed: Bool,
        workingHoursStartMinute: Int,
        workingHoursEndMinute: Int,
        wrapAtMinute rawWrapAtMinute: Int = 0
    ) {
        wrapAtMinute = TrackingDay.clampedWrapMinute(rawWrapAtMinute)
        guard zoomed else {
            startMinute = 0
            endMinute = 1_440
            return
        }
        let startWall = min(1_439, max(0, workingHoursStartMinute))
        let endWall = min(1_439, max(0, workingHoursEndMinute))
        let start = startWall >= wrapAtMinute
            ? startWall - wrapAtMinute
            : startWall - wrapAtMinute + 1_440
        var end = endWall >= wrapAtMinute
            ? endWall - wrapAtMinute
            : endWall - wrapAtMinute + 1_440
        if end <= start { end += 1_440 }
        startMinute = start
        endMinute = max(start + 15, end)
    }

    var spanMinutes: Int { max(15, endMinute - startMinute) }

    var tickMinutes: [Int] {
        let step = spanMinutes <= 12 * 60 ? 60 : 120
        var ticks = Array(stride(from: startMinute, through: endMinute, by: step))
        if ticks.last != endMinute { ticks.append(endMinute) }
        return ticks
    }

    func absoluteMinute(for second: Int, roundingUp: Bool = false) -> Int {
        let clampedSecond = max(0, min(86_400, second))
        if clampedSecond == 86_400 { return 1_440 }
        let raw = roundingUp
            ? Int(ceil(Double(clampedSecond) / 60.0))
            : clampedSecond / 60
        if endMinute > 1_440, raw < startMinute {
            return raw + 1_440
        }
        return raw
    }

    func clippedRange(startSecond: Int, endSecond: Int) -> (start: Int, end: Int)? {
        let start = max(startMinute, absoluteMinute(for: startSecond))
        let end = min(endMinute, absoluteMinute(for: endSecond, roundingUp: true))
        guard end > start else { return nil }
        return (start, end)
    }

    func x(for minute: Int, width: CGFloat) -> CGFloat {
        width * CGFloat(minute - startMinute) / CGFloat(spanMinutes)
    }

    func minute(at x: CGFloat, width: CGFloat) -> Int {
        let normalized = min(1, max(0, x / max(1, width)))
        let absolute = startMinute + Int((normalized * CGFloat(spanMinutes)).rounded())
        // Selection and entry APIs use minutes within the selected calendar day.
        return min(endMinute, max(startMinute, (absolute / 15) * 15))
    }

    func label(for minute: Int) -> String {
        let wallMinute = (minute + wrapAtMinute) % 1_440
        return String(format: "%02d", wallMinute / 60)
    }
}

private final class LockedArray<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Element] = []

    func append(_ value: Element) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func append(contentsOf newValues: [Element]) {
        lock.lock()
        values.append(contentsOf: newValues)
        lock.unlock()
    }

    var snapshot: [Element] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

struct ActivitiesView: View {
    private struct DeletedActivityRecord: Identifiable {
        let segment: ActivitySegment
        let date: Date
        let isScreenTime: Bool

        var id: String {
            "\(segment.id.uuidString)-\(date.timeIntervalSince1970)"
        }
    }

    private enum UnifiedGroupHeaderKind {
        case project
        case device
        case none

        var key: String {
            switch self {
            case .project: return "project"
            case .device: return "device"
            case .none: return "all"
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @ObservedObject var monitor: AppActivityMonitor
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var filterStore: ActivityFilterStore
    @ObservedObject var categoryStore: ActivityCategoryStore
    @ObservedObject var preferences: ActivitiesPreferencesStore
    @ObservedObject var trackingPreferences: PreferencesStore
    @ObservedObject var timeEntryStore: TimeEntryStore
    @ObservedObject var calendarStore: CalendarEventStore
    @ObservedObject var reminderStore: ReminderStore
    @ObservedObject var phoneCallStore: PhoneCallStore
    @ObservedObject var screenTimeStore: ScreenTimeStore
    @ObservedObject var teamStore: TeamStore
    let selectedDate: Date

    @State private var filter: ActivityFilter = .all
    @State private var includeIdle = false
    @State private var searchText = ""
    @State private var activityMode: ActivityDisplayMode = .chronological
    @State private var groupActivitiesByProject = true
    @State private var groupActivitiesByDevice = false
    @State private var collapsedProjectGroups: Set<String> = []
    @State private var collapsedDeviceGroups: Set<String> = []
    @State private var collapsedUnifiedAppGroups: Set<String> = []
    @State private var collapsedProjectIDs: Set<UUID> = []
    @State private var selectedDevice = ActivityDeviceFilter.all
    @State private var timelineOrientation: ActivityTimelineOrientation = .vertical
    @State private var showingDevicesPopover = false
    @State private var showingFiltersPopover = false
    @State private var hideDevicesWithoutTime = false
    @State private var selectedBuiltinFilter: ActivityBuiltinFilter?
    @State private var timelineSelectionStart: Int?
    @State private var timelineSelectionEnd: Int?
    @State private var showingArchivedProjects = false
    @State private var showingNewProject = false
    @State private var showingNewEntry = false
    @State private var showingTimerStart = false
    @State private var showingEntryOMatic = false
    @State private var newProjectName = ""
    @State private var newProjectParentID: UUID?
    @State private var newProjectTeamID: UUID?
    @State private var addProjectNameRules = true
    @State private var newEntryTitle = ""
    @State private var newEntryNotes = ""
    @State private var newEntryProjectID: UUID?
    @State private var newEntryBillingStatus: BillingStatus = .billable
    @State private var newEntryStart = Date().addingTimeInterval(-3600)
    @State private var newEntryEnd = Date()
    @State private var editingProject: TrackingProject?
    @State private var editingEntry: TimeEntry?
    @State private var editingTitleGroup: TimeEntry?
    @State private var selectedTimeEntryIDs: Set<UUID> = []
    @State private var selectedActivityIDs: Set<UUID> = []
    @State private var selectedActivity: ActivitySegment?
    @State private var pendingActivityDeletion: [DeletedActivityRecord] = []
    @State private var lastDeletedActivities: [DeletedActivityRecord] = []
    @State private var showingActivityDeletionConfirmation = false
    @State private var editingFilter: ActivityFilterDefinition?
    @State private var showingFilterEditor = false
    @State private var showingActivitySettings = false
    @State private var isProjectDropTargeted = false
    @State private var overlappingEntries: [TimeEntry] = []
    @State private var showingOverlapConfirmation = false
    @State private var displayPreferencesRestored = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageDateHeader(
                    title: "Activities",
                    subtitle: "Review, assign, and automate the time Timing captures"
                )

                activitiesToolbar

                HStack(alignment: .top, spacing: 18) {
                    projectSidebar
                        .frame(width: 236)
                    VStack(alignment: .leading, spacing: 18) {
                        ActivityTimelinePanel(
                            segments: timelineScopedSegments,
                            calendarEvents: calendarStore.events,
                            timeEntries: preferences.includeTimeEntries ? [] : timelineTimeEntries,
                            suggestions: timelineSuggestions,
                            selectedDate: selectedDate,
                            deviceName: appState.syncStore.deviceName,
                            wrapAtMinute: appState.preferences.wrapDaysAtMinute,
                            project: { projectStore.project($0) },
                            orientation: timelineOrientation,
                            timelineWindow: activityTimelineWindow,
                            activityColor: { categoryColor(for: category(for: $0)) },
                            categoryName: { category(for: $0).name },
                            selectedActivityIDs: $selectedActivityIDs,
                            onToggleOrientation: {
                                timelineOrientation = timelineOrientation == .horizontal ? .vertical : .horizontal
                            },
                            selectionStart: $timelineSelectionStart,
                            selectionEnd: $timelineSelectionEnd,
                            onCreateTimeEntry: { startMinute, endMinute in
                                prepareNewEntry(startMinute: startMinute, endMinute: endMinute)
                                showingNewEntry = true
                            },
                            onSelectTimelineSuggestion: { suggestion, immediate in
                                prepareNewEntry(for: suggestion)
                                if immediate {
                                    addNewEntry()
                                } else {
                                    showingNewEntry = true
                                }
                            },
                            onRecordCalendarEvent: { event, immediate in
                                prepareNewEntry(for: event)
                                if immediate {
                                    addNewEntry()
                                } else {
                                    showingNewEntry = true
                                }
                            },
                            onSelectActivity: { activity in
                                selectedActivity = activity
                            },
                            onCreateSelectedTimeEntries: {
                                showingEntryOMatic = true
                            },
                            onDeleteActivities: { segments in
                                requestDeleteActivities(segments)
                            },
                            onEditTimeEntry: { entry in
                                editingEntry = entry
                            },
                            onDeleteTimeEntry: { entry in
                                timeEntryStore.delete(entry)
                            }
                        )
                        CalendarEventsPanel(
                            store: calendarStore,
                            selectedDate: selectedDate,
                            onRecord: { event in
                                prepareNewEntry(for: event)
                                showingNewEntry = true
                            }
                        )
                        RemindersPanel(
                            store: reminderStore,
                            selectedDate: selectedDate,
                            onRecord: { reminder in
                                prepareNewEntry(for: reminder)
                                showingNewEntry = true
                            }
                        )
                        PhoneCallsPanel(
                            store: phoneCallStore,
                            selectedDate: selectedDate,
                            onRecord: { call in
                                prepareNewEntry(for: call)
                                showingNewEntry = true
                            }
                        )
                        ScreenTimePanel(store: screenTimeStore, selectedDate: selectedDate)
                        activityList
                        if !preferences.includeTimeEntries {
                            timeEntryList
                        }
                    }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(28)
        }
        .sheet(isPresented: $showingNewProject) {
            newProjectSheet
        }
        .sheet(isPresented: $showingNewEntry) {
            newEntrySheet
        }
        .sheet(isPresented: $showingTimerStart) {
            TimerStartSheet(
                projects: projectStore.activeProjects,
                initialProjectID: selectedProjectID,
                recentEntries: timeEntryStore.recentTimerEntries(),
                recentCalendarEvents: calendarStore.events,
                suggestedProjectID: { event in appState.suggestedProjectID(for: event) }
            ) { title, projectID, notes, billingStatus, estimatedDurationSeconds in
                timeEntryStore.startTimer(
                    title: title,
                    projectID: projectID,
                    notes: notes,
                    estimatedDurationSeconds: estimatedDurationSeconds,
                    billingStatus: billingStatus
                )
                showingTimerStart = false
            }
        }
        .sheet(isPresented: $showingEntryOMatic) {
            EntryOMaticSheet(
                selectedDate: selectedDate,
                segments: entryOMaticSegments,
                sourceDescription: selectedActivityIDs.isEmpty ? "visible app usage" : "the selected activities",
                existingEntries: timeEntryStore.entries(
                    overlapping: selectedDate,
                    wrapAtMinute: appState.preferences.wrapDaysAtMinute
                ),
                wrapAtMinute: appState.preferences.wrapDaysAtMinute,
                projects: projectStore.activeProjects,
                initialProjectID: selectedProjectID
            ) { intervals, title, projectID, notes, billingStatus, overwriteExisting in
                var replacedEntries: [TimeEntry] = []
                var splitFragments: [TimeEntry] = []
                if overwriteExisting {
                    let generatedRanges = intervals.map { interval in
                        return (
                            start: TrackingDay.date(
                                forAxisSeconds: interval.startSecond,
                                logicalDayLabel: selectedDate,
                                wrapAtMinute: appState.preferences.wrapDaysAtMinute
                            ),
                            end: TrackingDay.date(
                                forAxisSeconds: interval.endSecond,
                                logicalDayLabel: selectedDate,
                                wrapAtMinute: appState.preferences.wrapDaysAtMinute
                            )
                        )
                    }
                    let existingEntries = timeEntryStore.entries(
                        overlapping: selectedDate,
                        wrapAtMinute: appState.preferences.wrapDaysAtMinute
                    )
                    replacedEntries = existingEntries.filter { existing in
                        generatedRanges.contains { range in
                            existing.start < range.end && existing.end > range.start
                        }
                    }
                    splitFragments = timeEntryStore.splitOverlappingEntries(
                        replacedEntries,
                        excluding: generatedRanges
                    )
                }
                var createdEntries: [TimeEntry] = []
                for interval in intervals {
                    let start = TrackingDay.date(
                        forAxisSeconds: interval.startSecond,
                        logicalDayLabel: selectedDate,
                        wrapAtMinute: appState.preferences.wrapDaysAtMinute
                    )
                    let end = TrackingDay.date(
                        forAxisSeconds: interval.endSecond,
                        logicalDayLabel: selectedDate,
                        wrapAtMinute: appState.preferences.wrapDaysAtMinute
                    )
                    guard let id = timeEntryStore.addEntry(
                        title: title,
                        projectID: projectID,
                        notes: notes,
                        start: start,
                        end: end,
                        billingStatus: billingStatus
                    ) else { continue }
                    guard let entry = timeEntryStore.entries.first(where: { $0.id == id }) else { continue }
                    createdEntries.append(entry)
                }
                timeEntryStore.recordEntryOMaticCreation(
                    created: createdEntries,
                    replaced: replacedEntries,
                    splitFragments: splitFragments
                )
                showingEntryOMatic = false
            }
        }
        .sheet(item: $editingProject) { project in
            ProjectEditorSheet(
                project: project,
                projects: projectStore.validParentProjects(for: project.id),
                teamStore: teamStore
            ) { updatedProject in
                projectStore.updateProject(updatedProject)
                editingProject = nil
            }
        }
        .sheet(isPresented: $showingFilterEditor) {
            ActivityFilterEditorSheet(filter: editingFilter) { definition in
                filterStore.save(definition)
                filter = .saved(definition.id)
                appState.activityScope = .all
                editingFilter = nil
                showingFilterEditor = false
            }
        }
        .sheet(isPresented: $showingActivitySettings) {
            ActivityDisplaySettingsSheet(
                preferences: preferences,
                categoryStore: categoryStore,
                filterStore: filterStore
            )
        }
        .sheet(item: $editingEntry) { entry in
            TimeEntryEditorSheet(entry: entry, projects: projectStore.activeProjects, existingEntries: timeEntryStore.entries) { updatedEntry, replacements in
                _ = timeEntryStore.splitOverlappingEntries(
                    replacements,
                    excluding: [(start: updatedEntry.start, end: updatedEntry.end)]
                )
                timeEntryStore.update(updatedEntry)
                editingEntry = nil
            }
        }
        .sheet(item: $editingTitleGroup) { entry in
            TimeEntryTitleGroupSheet(
                entry: entry,
                occurrences: sameTitleEntries(for: entry),
                timeEntryStore: timeEntryStore
            )
        }
        .sheet(item: $selectedActivity) { activity in
            ActivityDetailSheet(
                activity: activity,
                category: category(for: activity),
                projectName: projectStore.name(for: activity.projectID),
                billingStatus: projectStore.resolvedBillingStatus(for: activity.projectID),
                timeEntryStore: timeEntryStore,
                selectedDate: selectedDate
            )
        }
        .alert("Overlapping Time Entry", isPresented: $showingOverlapConfirmation) {
            Button("Cancel", role: .cancel) {
                overlappingEntries = []
            }
            Button("Keep Both") {
                commitNewEntry(replacing: false)
            }
            Button("Replace Existing", role: .destructive) {
                commitNewEntry(replacing: true)
            }
        } message: {
            Text(overlapMessage)
        }
        .alert("Delete App Usage?", isPresented: $showingActivityDeletionConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingActivityDeletion = []
            }
            Button("Delete", role: .destructive) {
                deletePendingActivities()
            }
        } message: {
            Text("Delete \(pendingActivityDeletion.count) captured activit\(pendingActivityDeletion.count == 1 ? "y" : "ies")? This only removes the local activity record and can be undone.")
        }
        .onAppear {
            restoreDisplayPreferences()
            restoreActivityScope()
        }
        .onChange(of: activityMode) { _, newMode in
            guard displayPreferencesRestored else { return }
            preferences.activityDisplayMode = newMode.rawValue
        }
        .onChange(of: groupActivitiesByProject) { _, enabled in
            guard displayPreferencesRestored else { return }
            preferences.groupByProject = enabled
        }
        .onChange(of: groupActivitiesByDevice) { _, enabled in
            guard displayPreferencesRestored else { return }
            preferences.groupByDevice = enabled
        }
        .onChange(of: includeIdle) { _, enabled in
            guard displayPreferencesRestored else { return }
            preferences.includeIdle = enabled
        }
        .onChange(of: selectedDevice) { _, device in
            guard displayPreferencesRestored else { return }
            preferences.selectedDevice = device
        }
        .onChange(of: timelineOrientation) { _, orientation in
            guard displayPreferencesRestored else { return }
            preferences.timelineOrientation = orientation
        }
        .onChange(of: searchText) { _, _ in
            selectedActivityIDs.removeAll()
        }
        .onChange(of: selectedBuiltinFilter) { _, _ in
            selectedActivityIDs.removeAll()
        }
        .onChange(of: selectedDate) { _, _ in
            selectedTimeEntryIDs.removeAll()
            selectedActivityIDs.removeAll()
        }
    }

    private func restoreDisplayPreferences() {
        guard !displayPreferencesRestored else { return }
        activityMode = ActivityDisplayMode(rawValue: preferences.activityDisplayMode) ?? .chronological
        groupActivitiesByProject = preferences.groupByProject
        groupActivitiesByDevice = preferences.groupByDevice
        includeIdle = preferences.includeIdle
        timelineOrientation = preferences.timelineOrientation
        selectedDevice = availableDevices.contains(preferences.selectedDevice)
            ? preferences.selectedDevice
            : ActivityDeviceFilter.all
        displayPreferencesRestored = true
    }

    private func restoreActivityScope() {
        switch appState.activityScope {
        case .all:
            filter = .all
        case .unassigned:
            filter = .unassigned
        case .project(let id):
            filter = projectStore.project(id) == nil ? .all : .project(id)
            if case .all = filter, appState.activityScope != .all {
                appState.activityScope = .all
            }
        }
    }

    private func selectActivityFilter(_ target: ActivityFilter) {
        filter = target
        selectedActivityIDs.removeAll()
        switch target {
        case .all:
            appState.activityScope = .all
        case .unassigned:
            appState.activityScope = .unassigned
        case .project(let id):
            appState.activityScope = .project(id)
        case .saved:
            appState.activityScope = .all
        case .category:
            appState.activityScope = .all
        }
    }

    private var activitiesToolbar: some View {
        HStack(spacing: 8) {
            Button {
                newProjectName = ""
                newProjectParentID = nil
                newProjectTeamID = nil
                addProjectNameRules = true
                showingNewProject = true
            } label: {
                Label("New Project", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("activities.toolbar.new-project")

            Button {
                prepareNewEntry()
                showingNewEntry = true
            } label: {
                Label("New Time Entry", systemImage: "clock.badge.plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("activities.toolbar.new-entry")

            Button {
                if timeEntryStore.runningTimer == nil {
                    showingTimerStart = true
                } else {
                    _ = timeEntryStore.stopTimer()
                }
            } label: {
                Label(
                    timeEntryStore.runningTimer == nil ? "Start Timer" : "Stop Timer",
                    systemImage: timeEntryStore.runningTimer == nil ? "play.fill" : "stop.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier("activities.toolbar.timer")

            Spacer(minLength: 8)

            dateRangeToolbar

            Button {
                showingDevicesPopover.toggle()
            } label: {
                Label(deviceToolbarTitle, systemImage: "macbook.and.iphone")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Choose devices")
            .accessibilityIdentifier("activities.toolbar.devices")
            .popover(isPresented: $showingDevicesPopover, arrowEdge: .bottom) {
                devicesPopover
            }

            Button {
                showingFiltersPopover.toggle()
            } label: {
                Label(filterToolbarTitle, systemImage: "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Choose an activity filter")
            .accessibilityIdentifier("activities.toolbar.filters")
            .popover(isPresented: $showingFiltersPopover, arrowEdge: .bottom) {
                filtersPopover
            }

            Button {
                timelineOrientation = timelineOrientation == .horizontal ? .vertical : .horizontal
            } label: {
                Image(systemName: timelineOrientation.icon)
                    .frame(minWidth: 20)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Toggle timeline orientation")
            .accessibilityLabel("Toggle Timeline Orientation")
            .accessibilityIdentifier("activities.toolbar.timeline-orientation")

            activitySearchField
        }
        .padding(10)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MetridayTheme.line, lineWidth: 1)
        )
    }

    private var dateRangeToolbar: some View {
        ZStack {
            Color.clear
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .onTapGesture { appState.goToToday() }
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                Button {
                    appState.moveSelectedDate(byDays: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Previous day")
                .accessibilityLabel("Previous")
                .accessibilityIdentifier("activities.toolbar.previous")

                Divider()
                    .frame(height: 18)

                Button {
                    appState.goToToday()
                } label: {
                    Text(dateRangeTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(minWidth: 76, minHeight: 28, maxHeight: 28)
                }
                .buttonStyle(.plain)
                .help("Go to today")
                .accessibilityLabel("Today")
                .accessibilityIdentifier("activities.toolbar.today")

                Divider()
                    .frame(height: 18)

                Button {
                    appState.moveSelectedDate(byDays: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Next day")
                .accessibilityLabel("Next")
                .accessibilityIdentifier("activities.toolbar.next")
            }
        }
        .padding(.horizontal, 4)
        .background(MetridayTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Date Range")
        .accessibilityAction(named: "Go to Today") { appState.goToToday() }
        .accessibilityIdentifier("activities.toolbar.date-range")
    }

    private var activitySearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MetridayTheme.secondary)
            TextField("Search", text: $searchText)
                .textFieldStyle(.plain)
                .frame(width: 120)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MetridayTheme.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(MetridayTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search activities")
        .accessibilityIdentifier("activities.toolbar.search")
    }

    private var devicesPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Devices")
                .font(.system(size: 13, weight: .bold))

            devicePopoverRow(
                title: "All Mac devices",
                icon: "macbook",
                isSelected: selectedDevice == ActivityDeviceFilter.all
            ) {
                selectedDevice = ActivityDeviceFilter.all
                showingDevicesPopover = false
            }

            Divider()

            ForEach(availableDevices.dropFirst(), id: \.self) { device in
                devicePopoverRow(
                    title: device,
                    icon: device == appState.syncStore.deviceName ? "macbook" : "desktopcomputer",
                    isSelected: selectedDevice == device
                ) {
                    selectedDevice = device
                    showingDevicesPopover = false
                }
            }

            if availableDevices.count == 1 {
                Text("No other devices have recorded time yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(MetridayTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Toggle("Hide devices without time", isOn: $hideDevicesWithoutTime)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.system(size: 11))
                .disabled(availableDevices.count == 1)
        }
        .padding(14)
        .frame(width: 250, alignment: .leading)
    }

    private func devicePopoverRow(
        title: String,
        icon: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 18)
                Text(title)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var filtersPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Filters")
                .font(.system(size: 13, weight: .bold))

            toolbarFilterRow(
                title: "No Filter",
                icon: "line.3.horizontal.decrease.circle",
                isSelected: selectedBuiltinFilter == nil
            ) {
                selectedBuiltinFilter = nil
                showingFiltersPopover = false
            }

            Divider()

            ForEach(ActivityBuiltinFilter.allCases) { builtin in
                toolbarFilterRow(
                    title: builtin.label,
                    icon: builtin.icon,
                    isSelected: selectedBuiltinFilter == builtin
                ) {
                    selectedBuiltinFilter = builtin
                    showingFiltersPopover = false
                }
            }

            if !categoryStore.customCategories.isEmpty {
                Divider()
                Text("Categories")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)
                ForEach(categoryStore.customCategories) { category in
                    toolbarFilterRow(
                        title: category.name,
                        icon: "circle.fill",
                        isSelected: filter == .category(category.id),
                        tint: categoryColor(for: category)
                    ) {
                        selectedBuiltinFilter = nil
                        selectActivityFilter(.category(category.id))
                        showingFiltersPopover = false
                    }
                }
            }

            if !filterStore.activeFilters.isEmpty {
                Divider()
                Text("Saved Filters")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)
                ForEach(filterStore.activeFilters) { savedFilter in
                    toolbarFilterRow(
                        title: savedFilter.name,
                        icon: "line.3.horizontal.decrease.circle",
                        isSelected: filter == .saved(savedFilter.id),
                        tint: color(for: savedFilter.color)
                    ) {
                        selectedBuiltinFilter = nil
                        filter = .saved(savedFilter.id)
                        showingFiltersPopover = false
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 250, alignment: .leading)
    }

    private func toolbarFilterRow(
        title: String,
        icon: String,
        isSelected: Bool,
        tint: Color = MetridayTheme.accent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 18)
                Text(title)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? tint : MetridayTheme.graphite)
            .frame(maxWidth: .infinity, minHeight: 27, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dateRangeTitle: String {
        if Calendar.current.isDateInToday(selectedDate) {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter.string(from: selectedDate)
    }

    private var deviceToolbarTitle: String {
        selectedDevice == ActivityDeviceFilter.all ? "Devices" : selectedDevice
    }

    private var filterToolbarTitle: String {
        if let selectedBuiltinFilter {
            return selectedBuiltinFilter.label
        }
        switch filter {
        case .all:
            return "Filters"
        case .saved(let id):
            return filterStore.filter(id)?.name ?? "Filters"
        case .category(let id):
            return categoryStore.categories.first(where: { $0.id == id })?.name ?? "Category"
        case .unassigned, .project:
            return "Filters"
        }
    }

    private var projectSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Projects")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button {
                    newProjectName = ""
                    newProjectParentID = nil
                    newProjectTeamID = nil
                    addProjectNameRules = true
                    showingNewProject = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New Project")
                .accessibilityIdentifier("activities.new-project")
            }
            .padding(16)

            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    filterButton(
                        title: "All Activities",
                        icon: "waveform.path",
                        filter: .all,
                        summarySeconds: allActivitySegments.reduce(0) { $0 + $1.durationSeconds }
                    )
                    filterButton(
                        title: "Unassigned",
                        icon: "tray",
                        filter: .unassigned,
                        summarySeconds: allActivitySegments
                            .filter { $0.projectID == nil }
                            .reduce(0) { $0 + $1.durationSeconds }
                    )

                    Divider()
                        .padding(.vertical, 8)

                    HStack {
                        Text("My Projects")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MetridayTheme.secondary)
                        Spacer()
                        if !projectStore.archivedProjects.isEmpty {
                            Button {
                                showingArchivedProjects.toggle()
                            } label: {
                                Image(systemName: showingArchivedProjects ? "archivebox.fill" : "archivebox")
                            }
                            .buttonStyle(.borderless)
                            .help(showingArchivedProjects ? "Hide Archived Projects" : "Show Archived Projects")
                            .accessibilityLabel(showingArchivedProjects ? "Hide Archived Projects" : "Show Archived Projects")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 5)

                    ForEach(projectStore.childProjects(of: nil)) { project in
                        projectTree(project, depth: 0)
                    }

                    if showingArchivedProjects {
                        Divider()
                            .padding(.vertical, 8)
                        Text("Archived Projects")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MetridayTheme.secondary)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 4)
                        ForEach(projectStore.archivedProjects) { project in
                            archivedProjectRow(project)
                        }
                    }

                    projectDropZone

                    Divider()
                        .padding(.vertical, 8)

                    HStack {
                        Text("Filters")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MetridayTheme.secondary)
                        Spacer()
                        Button {
                            editingFilter = nil
                            showingFilterEditor = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help("New Filter")
                        .accessibilityIdentifier("activities.new-filter")
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 5)

                    ForEach(filterStore.activeFilters) { savedFilter in
                        savedFilterButton(savedFilter)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                Text(projectStore.statusMessage)
                    .lineLimit(2)
            }
            .font(.system(size: 10))
            .foregroundStyle(MetridayTheme.secondary)
            .padding(14)
        }
        .frame(height: 560)
        .background(MetridayTheme.sidebar)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MetridayTheme.line, lineWidth: 1)
        )
    }

    private var projectDropZone: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: isProjectDropTargeted ? "arrow.down.circle.fill" : "square.and.arrow.down")
                    .foregroundStyle(isProjectDropTargeted ? MetridayTheme.accent : MetridayTheme.secondary)
                Text(dropZoneTitle)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MetridayTheme.secondary)
            }
            Text(dropZoneSubtitle)
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isProjectDropTargeted ? MetridayTheme.accentSoft : MetridayTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isProjectDropTargeted ? MetridayTheme.accent : MetridayTheme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture { chooseProjectDropItems() }
        .onDrop(
            of: [UTType.fileURL.identifier, UTType.plainText.identifier],
            isTargeted: $isProjectDropTargeted,
            perform: handleProjectDrop
        )
        .contextMenu {
            Button("Choose Files or Folders") {
                chooseProjectDropItems()
            }
        }
        .help("Drop files, folders, or activities here to create a project")
        .accessibilityIdentifier("activities.project-drop-zone")
    }

    private var dropZoneTitle: String {
        if isProjectDropTargeted { return "Release to create project" }
        if selectedProjectID != nil {
            return "Drop to create sub-project"
        }
        return "Create from files or activities"
    }

    private var dropZoneSubtitle: String {
        if isProjectDropTargeted { return "Hold ⌥ to also create matching activity rules." }
        return "Click to choose files or folders · ⌘ splits items · ⌥ adds rules"
    }

    private func chooseProjectDropItems() {
        let panel = NSOpenPanel()
        panel.title = "Create Project from Files or Folders"
        panel.prompt = "Create Project"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let modifiers = NSEvent.modifierFlags
        createProjectsFromURLs(
            panel.urls,
            separateItems: modifiers.contains(.command),
            createActivityRules: modifiers.contains(.option)
        )
    }

    private func handleProjectDrop(_ providers: [NSItemProvider]) -> Bool {
        let modifiers = NSEvent.modifierFlags
        let separateItems = modifiers.contains(.command)
        let createActivityRules = modifiers.contains(.option)
        let supportsFiles = providers.contains {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        if supportsFiles {
            let fileProviders = providers.filter {
                $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            }
            let group = DispatchGroup()
            let urls = LockedArray<URL>()
            for provider in fileProviders {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let itemURL = item as? URL {
                        url = itemURL
                    } else if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let string = item as? String {
                        url = URL(fileURLWithPath: string)
                    } else {
                        url = nil
                    }
                    if let url {
                        urls.append(url)
                    }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                Task { @MainActor in
                    self.createProjectsFromURLs(
                        urls.snapshot,
                        separateItems: separateItems,
                        createActivityRules: createActivityRules
                    )
                }
            }
            return true
        }

        let activityProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }
        guard !activityProviders.isEmpty else { return false }
        let group = DispatchGroup()
        let ids = LockedArray<UUID>()
        for provider in activityProviders {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                if let data, let text = String(data: data, encoding: .utf8) {
                    let loadedIDs = text
                        .split(whereSeparator: \.isNewline)
                        .compactMap { UUID(uuidString: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
                    ids.append(contentsOf: loadedIDs)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            Task { @MainActor in
                self.createProjectFromActivities(
                    Array(Set(ids.snapshot)),
                    separateItems: separateItems,
                    createActivityRules: createActivityRules
                )
            }
        }
        return true
    }

    private func createProjectsFromURLs(
        _ urls: [URL],
        separateItems: Bool = false,
        createActivityRules: Bool = false
    ) {
        let urls = urls.filter { !$0.path.isEmpty }
        guard !urls.isEmpty else { return }
        if separateItems {
            for url in urls {
                createProjectFromURL(url, parentID: selectedProjectID, createActivityRule: createActivityRules)
            }
            return
        }

        let name = urls.count == 1
            ? urls[0].deletingPathExtension().lastPathComponent
            : urls[0].deletingLastPathComponent().lastPathComponent
        guard let projectID = projectStore.createProject(
            name: name.isEmpty ? "New Project" : name,
            parentID: selectedProjectID
        ) else { return }
        for url in urls {
            addProjectDropRule(for: url, projectID: projectID, createActivityRule: createActivityRules)
        }
    }

    private func createProjectFromURL(_ url: URL, parentID: UUID?, createActivityRule: Bool) {
        let name = url.deletingPathExtension().lastPathComponent
        guard let projectID = projectStore.createProject(
            name: name.isEmpty ? "New Project" : name,
            parentID: parentID
        ) else { return }
        addProjectDropRule(for: url, projectID: projectID, createActivityRule: createActivityRule)
    }

    private func addProjectDropRule(for url: URL, projectID: UUID, createActivityRule: Bool) {
        _ = projectStore.addRule(
            projectID: projectID,
            field: .resourceContains,
            pattern: url.path,
            comparison: .beginsWith
        )
        if createActivityRule {
            projectStore.statusMessage = "Project created with activity rule · \(url.lastPathComponent)"
        }
    }

    private func createProjectFromActivities(
        _ ids: [UUID],
        separateItems: Bool = false,
        createActivityRules: Bool = false
    ) {
        let activities = ids.compactMap { id in allActivitySegments.first { $0.id == id } }
        guard let first = activities.first else { return }
        if separateItems {
            for activity in activities {
                let name = URL(string: activity.resource)?.host ?? activity.appName
                guard let projectID = projectStore.createProject(name: name, parentID: selectedProjectID) else { continue }
                assignActivity(activity.id, to: projectID, date: activity.activityDate)
                if createActivityRules {
                    _ = createRule(for: activity, projectID: projectID)
                }
            }
            return
        }

        let host = URL(string: first.resource)?.host
        let name = host ?? first.appName
        guard let projectID = projectStore.createProject(name: name, parentID: selectedProjectID) else { return }
        for activity in activities {
            assignActivity(activity.id, to: projectID, date: activity.activityDate)
            if createActivityRules {
                _ = createRule(for: activity, projectID: projectID)
            }
        }
    }

    private var activityList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(filterTitle)
                        .font(.system(size: 17, weight: .bold))
                    Text("\(filteredSegments.count) activities · \(formatMinutes(totalSeconds)) tracked · \(activityRangeLabel)")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Toggle("Show Idle", isOn: $includeIdle)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.system(size: 10))

                    Toggle("Group by project", isOn: groupByProjectBinding)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.system(size: 10))
                        .disabled(activityMode == .byCategory)

                    Toggle("Group by device", isOn: groupByDeviceBinding)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.system(size: 10))
                        .disabled(activityMode == .byCategory)

                    Picker("Activity view", selection: $activityMode) {
                        ForEach(ActivityDisplayMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityIdentifier("activities.view-mode")

                    Button {
                        showingEntryOMatic = true
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Create Time Entries from activity")
                    .accessibilityLabel(selectedActivityIDs.isEmpty ? "Create Time Entries" : "Create Time Entries from selected activities")
                    .disabled(entryOMaticSegments.allSatisfy { $0.relevance == .idle })
                    .accessibilityIdentifier("activities.entry-o-matic")

                    Button {
                        showingActivitySettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Activity display settings")
                    .accessibilityLabel("Activity display settings")
                    .accessibilityIdentifier("activities.display-settings")
                }
            }
            .padding(18)

            if !selectedActivityIDs.isEmpty {
                HStack(spacing: 8) {
                    Label(
                        "\(selectedActivityIDs.count) activities selected",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MetridayTheme.accent)
                    Spacer()
                    Button("Create from selected") {
                        showingEntryOMatic = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("activities.entry-o-matic-selected")
                    Button("Delete selected", role: .destructive) {
                        requestDeleteSelectedActivities()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("activities.delete-selected")
                    Button("Clear") {
                        selectedActivityIDs.removeAll()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .medium))
                    .help("Clear selected activities")
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }

            if !lastDeletedActivities.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .foregroundStyle(MetridayTheme.danger)
                    Text("Deleted \(lastDeletedActivities.count) app usage record\(lastDeletedActivities.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                    Spacer()
                    Button("Undo") {
                        undoLastActivityDeletion()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut("z", modifiers: [.command])
                    Button("Dismiss") {
                        lastDeletedActivities = []
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }

            if !entryOMaticPreview.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(MetridayTheme.accent)
                    Text(entryOMaticDescription)
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(selectedActivityIDs.isEmpty ? "Create Time Entries" : "Create Selected") {
                        showingEntryOMatic = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(selectedActivityIDs.isEmpty ? "Create Time Entries" : "Create Time Entries from selected activities")
                    .accessibilityIdentifier("activities.entry-o-matic-suggestion")
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }

            Divider()

            if activityMode != .byCategory {
                activityColumnHeader
            }

            if filteredSegments.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 30))
                        .foregroundStyle(MetridayTheme.secondary)
                    Text("No activities in this filter")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Metriday will show app, window, and browser activity here as it is captured.")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else if activityMode == .byCategory {
                categoryCards
            } else if activityMode == .unified {
                unifiedActivityList
            } else if groupActivitiesByProject && groupActivitiesByDevice {
                groupedActivityListByProjectAndDevice
            } else if groupActivitiesByDevice {
                groupedActivityListByDevice
            } else if groupActivitiesByProject {
                groupedActivityList
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(activityListSegments) { segment in
                        activityRow(segment)
                        if segment.id != activityListSegments.last?.id {
                            Divider().padding(.leading, 66)
                        }
                    }
                }
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MetridayTheme.line, lineWidth: 1)
        )
    }

    private var timeEntryList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Time Entries")
                        .font(.system(size: 16, weight: .bold))
                    Text(selectedTimeEntryIDs.isEmpty
                        ? "\(timeEntriesForSelectedDate.count) manual or timer entries"
                        : "\(selectedTimeEntryIDs.count) selected")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                if !timeEntriesForSelectedDate.isEmpty {
                    if selectedTimeEntryIDs.isEmpty {
                        Button("Select all") {
                            selectedTimeEntryIDs = Set(timeEntriesForSelectedDate.map(\.id))
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11, weight: .medium))
                        .help("Select all time entries")
                    } else {
                        Menu {
                            ForEach(BillingStatus.allCases) { status in
                                Button {
                                    applyBulkBillingStatus(status)
                                } label: {
                                    Label(status.label, systemImage: status == .billable ? "checkmark.seal" : "tag")
                                }
                            }
                        } label: {
                            Label("Set billing status", systemImage: "tag")
                        }
                        .menuStyle(.borderlessButton)
                        .help("Set billing status for selected time entries")
                        Button("Clear") {
                            selectedTimeEntryIDs.removeAll()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11, weight: .medium))
                        .help("Clear time entry selection")
                    }
                }
                if let runningTimer = timeEntryStore.runningTimer {
                    RunningTimerStatus(
                        store: timeEntryStore,
                        title: runningTimer.title
                    )
                }
            }
            .padding(18)

            Divider()

            if timeEntryStore.canUndoEntryOMatic {
                HStack(spacing: 8) {
                    Label(
                        "Created \(timeEntryStore.lastEntryOMaticCreationCount) Entry-O-Matic entries",
                        systemImage: "arrow.uturn.backward.circle"
                    )
                    .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Button("Undo") {
                        _ = timeEntryStore.undoEntryOMaticCreation()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .semibold))
                    .help("Undo Entry-O-Matic creation (⌘Z)")
                }
                .foregroundStyle(MetridayTheme.accent)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(MetridayTheme.accentSoft)
            }

            if timeEntriesForSelectedDate.isEmpty {
                Text("Create a manual entry for time away from the Mac, meetings, or a timer session.")
                    .font(.system(size: 11))
                    .foregroundStyle(MetridayTheme.secondary)
                    .padding(18)
            } else {
                VStack(spacing: 0) {
                    ForEach(timeEntriesForSelectedDate) { entry in
                        HStack(spacing: 12) {
                            Button {
                                toggleTimeEntrySelection(entry.id)
                            } label: {
                                Image(systemName: selectedTimeEntryIDs.contains(entry.id)
                                    ? "checkmark.circle.fill"
                                    : "circle")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(selectedTimeEntryIDs.contains(entry.id)
                                        ? MetridayTheme.accent
                                        : MetridayTheme.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Select time entry")
                            .accessibilityLabel(selectedTimeEntryIDs.contains(entry.id)
                                ? "Deselect time entry"
                                : "Select time entry")
                            .accessibilityValue(entry.title)
                            Button {
                                editingEntry = entry
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: entry.isManual ? "clock" : "timer")
                                        .foregroundStyle(MetridayTheme.accent)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.title)
                                            .font(.system(size: 12, weight: .semibold))
                                        Text("\(formatDateRange(entry.start, entry.end)) · \(projectStore.name(for: entry.projectID))")
                                            .font(.system(size: 10))
                                            .foregroundStyle(MetridayTheme.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(formatMinutes(entry.durationSeconds))
                                            .font(.system(size: 12, weight: .semibold))
                                        if let amount = billingAmountLabel(for: entry) {
                                            Text(amount)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(MetridayTheme.success)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .background(selectedTimeEntryIDs.contains(entry.id)
                                ? MetridayTheme.accentSoft
                                : Color.clear)
                            .help("Edit time entry")
                            .accessibilityIdentifier("time-entry.\(entry.id.uuidString)")
                            if sameTitleEntries(for: entry).count > 1 {
                                Button("Edit all") {
                                    editingTitleGroup = entry
                                }
                                .buttonStyle(.borderless)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(MetridayTheme.accent)
                                .help("Edit the title for all same-title entries on the selected day")
                                .accessibilityLabel("Edit title for all occurrences of \(entry.title)")
                                .accessibilityIdentifier("time-entry.edit-all.\(entry.id.uuidString)")
                            }
                            Button {
                                editingEntry = entry
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .help("Edit time entry")
                            Button(role: .destructive) {
                                timeEntryStore.delete(entry)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(selectedTimeEntryIDs.contains(entry.id)
                            ? MetridayTheme.accentSoft.opacity(0.42)
                            : Color.clear)
                        .contextMenu {
                            Button("Edit Time Entry") {
                                editingEntry = entry
                            }
                            if sameTitleEntries(for: entry).count > 1 {
                                Button("Edit Title for All Occurrences") {
                                    editingTitleGroup = entry
                                }
                            }
                            Divider()
                            Button("Delete Time Entry", role: .destructive) {
                                timeEntryStore.delete(entry)
                            }
                        }
                        if entry.id != timeEntriesForSelectedDate.last?.id {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MetridayTheme.line, lineWidth: 1)
        )
    }

    private func toggleTimeEntrySelection(_ id: UUID) {
        if selectedTimeEntryIDs.contains(id) {
            selectedTimeEntryIDs.remove(id)
        } else {
            selectedTimeEntryIDs.insert(id)
        }
    }

    private func applyBulkBillingStatus(_ status: BillingStatus) {
        let selected = selectedTimeEntryIDs
        guard !selected.isEmpty else { return }
        _ = timeEntryStore.updateBillingStatus(for: selected, to: status)
        selectedTimeEntryIDs.removeAll()
    }

    private func sameTitleEntries(for entry: TimeEntry) -> [TimeEntry] {
        let normalizedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedTitle.isEmpty else { return [] }
        return timeEntriesForSelectedDate.filter {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTitle
        }
    }

    private var categoryCards: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 210), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            categoryCard(
                title: "Websites",
                icon: "globe",
                segments: websiteSegments,
                nameFor: { resourceLabel($0.resource) }
            )
            categoryCard(
                title: "Applications",
                icon: "rectangle.on.rectangle",
                segments: applicationSegments,
                nameFor: { appName(for: $0) }
            )
            categoryCard(
                title: "Paths",
                icon: "folder",
                segments: pathSegments,
                rows: pathRows
            )
            categoryCard(
                title: "Keywords",
                icon: "textformat.abc",
                segments: keywordSegments,
                rows: keywordRows
            )
        }
        .padding(14)
    }

    private var groupedActivityList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(activityGroups) { group in
                let isCollapsed = collapsedProjectGroups.contains(group.id)
                Button {
                    if isCollapsed {
                        collapsedProjectGroups.remove(group.id)
                    } else {
                        collapsedProjectGroups.insert(group.id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 10)
                        Label(group.name, systemImage: group.name == "Unassigned" ? "tray" : "folder")
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                        Text(formatMinutes(group.seconds))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MetridayTheme.secondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(MetridayTheme.canvas)

                if !isCollapsed {
                    ForEach(group.segments) { segment in
                        activityRow(segment)
                        if segment.id != group.segments.last?.id {
                            Divider().padding(.leading, 66)
                        }
                    }
                }
                if group.id != activityGroups.last?.id {
                    Divider()
                }
            }
        }
    }

    private var activityColumnHeader: some View {
        HStack(spacing: 12) {
            Text("App")
                .frame(width: 220, alignment: .leading)
            Text("Category")
                .frame(width: 112, alignment: .leading)
            Spacer()
            Text("Time")
                .frame(width: 52, alignment: .trailing)
            Text("Project")
                .frame(width: 122, alignment: .leading)
            Image(systemName: "ellipsis")
                .frame(width: 20)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(MetridayTheme.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(MetridayTheme.canvas.opacity(0.65))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Activity columns: App, Category, Time, Project")
    }

    private var unifiedActivityList: some View {
        let groups: [ActivityGroup]
        let headerKind: UnifiedGroupHeaderKind
        if groupActivitiesByProject && groupActivitiesByDevice {
            groups = activityGroups
            headerKind = .project
        } else if groupActivitiesByDevice {
            groups = deviceActivityGroups
            headerKind = .device
        } else if groupActivitiesByProject {
            groups = activityGroups
            headerKind = .project
        } else {
            groups = [ActivityGroup(
                name: "All Activities",
                segments: activityListSegments,
                seconds: activityListSegments.reduce(0) { $0 + $1.durationSeconds }
            )]
            headerKind = .none
        }

        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                unifiedActivityGroup(group, headerKind: headerKind)
                if index < groups.count - 1 {
                    Divider()
                }
            }
        }
    }

    private func unifiedActivityGroup(
        _ group: ActivityGroup,
        headerKind: UnifiedGroupHeaderKind,
        headerIndent: CGFloat = 0
    ) -> AnyView {
        let isCollapsed: Bool = {
            switch headerKind {
            case .project: return collapsedProjectGroups.contains(group.id)
            case .device: return collapsedDeviceGroups.contains(group.id)
            case .none: return false
            }
        }()
        return AnyView(VStack(alignment: .leading, spacing: 0) {
        if headerKind != .none {
            Button {
                switch headerKind {
                case .project:
                    if isCollapsed { collapsedProjectGroups.remove(group.id) }
                    else { collapsedProjectGroups.insert(group.id) }
                case .device:
                    if isCollapsed { collapsedDeviceGroups.remove(group.id) }
                    else { collapsedDeviceGroups.insert(group.id) }
                case .none:
                    break
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 10)
                    Label(
                        group.name,
                        systemImage: headerKind == .device
                            ? "laptopcomputer.and.iphone"
                            : group.name == "Unassigned" ? "tray" : "folder"
                    )
                    .font(.system(size: 12, weight: .bold))
                    Spacer()
                    Text(formatMinutes(group.seconds))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                .padding(.leading, 18 + headerIndent)
                .padding(.trailing, 18)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(MetridayTheme.canvas)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(headerKind == .device ? "Device" : "Project") \(group.name) \(isCollapsed ? "Expand" : "Collapse")"))
            .accessibilityIdentifier("activities.unified.\(headerKind.key).\(group.id)")
        }

        if !isCollapsed {
            if groupActivitiesByProject && groupActivitiesByDevice && headerKind == .project {
                ForEach(deviceActivityGroups(for: group.segments)) { deviceGroup in
                    unifiedActivityGroup(deviceGroup, headerKind: .device, headerIndent: 24)
                }
            } else {
                ForEach(unifiedAppGroups(for: group)) { appGroup in
                let groupKey = "\(headerKind.key)::\(group.id)::\(appGroup.id)"
                let appCollapsed = collapsedUnifiedAppGroups.contains(groupKey)
                Button {
                    if appCollapsed { collapsedUnifiedAppGroups.remove(groupKey) }
                    else { collapsedUnifiedAppGroups.insert(groupKey) }
                } label: {
                    let appCategories = categories(for: appGroup.segments)
                    HStack(spacing: 8) {
                        Image(systemName: appCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .frame(width: 10)
                        AppIdentityIcon(
                            symbol: icon(for: appGroup.segments[0]),
                            bundleIdentifier: appGroup.segments[0].bundleIdentifier
                        )
                        Text(appGroup.name)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            ForEach(appCategories) { definition in
                                Circle()
                                    .fill(categoryColor(for: definition))
                                    .frame(width: 6, height: 6)
                            }
                            Text(appCategories.count == 1 ? appCategories[0].name : "Multiple categories")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(
                                    appCategories.count == 1
                                        ? categoryColor(for: appCategories[0])
                                        : MetridayTheme.secondary
                                )
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(formatMinutes(appGroup.seconds))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MetridayTheme.secondary)
                    }
                    .padding(.leading, headerKind == .none ? 18 : 42 + headerIndent)
                    .padding(.trailing, 18)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Application \(appGroup.name) \(appCollapsed ? "Expand" : "Collapse")"))
                .accessibilityIdentifier("activities.unified.application.\(groupKey)")

                if !appCollapsed {
                    ForEach(appGroup.segments) { segment in
                        activityRow(segment)
                        if segment.id != appGroup.segments.last?.id {
                            Divider().padding(.leading, headerKind == .none ? 64 : 88 + headerIndent)
                        }
                    }
                }
            }
            }
        }
        })
    }

    private func unifiedAppGroups(for projectGroup: ActivityGroup) -> [ActivityGroup] {
        var grouped: [String: [ActivitySegment]] = [:]
        for segment in projectGroup.segments {
            for name in unifiedGroupNames(for: segment) {
                grouped[name, default: []].append(segment)
            }
        }
        return grouped.map { name, segments in
            ActivityGroup(
                name: name,
                segments: segments.sorted { $0.startSecond < $1.startSecond },
                seconds: segments.reduce(0) { $0 + $1.durationSeconds }
            )
        }
        .sorted { first, second in
            if first.seconds == second.seconds { return first.name < second.name }
            return first.seconds > second.seconds
        }
    }

    private func unifiedGroupNames(for segment: ActivitySegment) -> [String] {
        if preferences.groupWebsitesIndependently,
           let host = URL(string: segment.resource)?.host,
           !host.isEmpty {
            return [host]
        }
        if preferences.groupPathsIndependently,
           !segment.resource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           URL(string: segment.resource)?.host == nil {
            return pathGroupingNames(for: segment.resource)
        }
        return [
            segment.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Unknown application"
                : segment.appName
        ]
    }

    private func deviceActivityGroups(for segments: [ActivitySegment]) -> [ActivityGroup] {
        Dictionary(grouping: segments) { $0.deviceName }
            .map { name, segments in
                ActivityGroup(
                    name: name,
                    segments: segments.sorted { $0.startSecond < $1.startSecond },
                    seconds: segments.reduce(0) { $0 + $1.durationSeconds }
                )
            }
            .sorted { first, second in
                if first.seconds == second.seconds { return first.name < second.name }
                return first.seconds > second.seconds
            }
    }

    private var deviceActivityGroups: [ActivityGroup] {
        deviceActivityGroups(for: activityListSegments)
    }

    private var groupedActivityListByDevice: some View {
        let groups = deviceActivityGroups

        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(groups) { group in
                let isCollapsed = collapsedDeviceGroups.contains(group.id)
                Button {
                    if isCollapsed {
                        collapsedDeviceGroups.remove(group.id)
                    } else {
                        collapsedDeviceGroups.insert(group.id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 10)
                        Label(group.name, systemImage: "laptopcomputer.and.iphone")
                            .font(.system(size: 12, weight: .bold))
                        Spacer()
                        Text(formatMinutes(group.seconds))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MetridayTheme.secondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(MetridayTheme.canvas)

                if !isCollapsed {
                    ForEach(group.segments) { segment in
                        activityRow(segment)
                        if segment.id != group.segments.last?.id {
                            Divider().padding(.leading, 66)
                        }
                    }
                }
                if group.id != groups.last?.id {
                    Divider()
                }
            }
        }
    }

    private var groupedActivityListByProjectAndDevice: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(activityGroups) { projectGroup in
                let projectCollapsed = collapsedProjectGroups.contains(projectGroup.id)
                Button {
                    if projectCollapsed {
                        collapsedProjectGroups.remove(projectGroup.id)
                    } else {
                        collapsedProjectGroups.insert(projectGroup.id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: projectCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 10)
                        Label(
                            projectGroup.name,
                            systemImage: projectGroup.name == "Unassigned" ? "tray" : "folder"
                        )
                        .font(.system(size: 12, weight: .bold))
                        Spacer()
                        Text(formatMinutes(projectGroup.seconds))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MetridayTheme.secondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(MetridayTheme.canvas)

                if !projectCollapsed {
                    ForEach(deviceActivityGroups(for: projectGroup.segments)) { deviceGroup in
                        let deviceCollapsed = collapsedDeviceGroups.contains(deviceGroup.id)
                        Button {
                            if deviceCollapsed {
                                collapsedDeviceGroups.remove(deviceGroup.id)
                            } else {
                                collapsedDeviceGroups.insert(deviceGroup.id)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: deviceCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .frame(width: 10)
                                Label(deviceGroup.name, systemImage: "laptopcomputer.and.iphone")
                                    .font(.system(size: 11, weight: .semibold))
                                Spacer()
                                Text(formatMinutes(deviceGroup.seconds))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(MetridayTheme.secondary)
                            }
                            .padding(.leading, 42)
                            .padding(.trailing, 18)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(MetridayTheme.canvas.opacity(0.7))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("Device \(deviceGroup.name) \(deviceCollapsed ? "Expand" : "Collapse")"))
                        .accessibilityIdentifier("activities.chronological.device.\(projectGroup.id).\(deviceGroup.id)")

                        if !deviceCollapsed {
                            ForEach(deviceGroup.segments) { segment in
                                activityRow(segment)
                                if segment.id != deviceGroup.segments.last?.id {
                                    Divider().padding(.leading, 88)
                                }
                            }
                        }
                    }
                }
                if projectGroup.id != activityGroups.last?.id {
                    Divider()
                }
            }
        }
    }

    private func categoryCard(
        title: String,
        icon: String,
        segments: [ActivitySegment],
        rows: [CategoryRow]? = nil,
        nameFor: ((ActivitySegment) -> String)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text(formatMinutes(segments.reduce(0) { $0 + $1.durationSeconds }))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)
            }

            if segments.isEmpty {
                Text("No matching activity")
                    .font(.system(size: 11))
                    .foregroundStyle(MetridayTheme.secondary)
            } else {
                ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(rows ?? categoryRows(segments, nameFor: nameFor)) { row in
                            let firstActivity = row.segments.first
                            let firstSymbol = firstActivity.map { self.icon(for: $0) }
                            HStack(spacing: 7) {
                                AppIdentityIcon(
                                    symbol: firstSymbol,
                                    bundleIdentifier: firstActivity?.bundleIdentifier,
                                    size: 22
                                )
                                Circle()
                                    .fill(categoryColor(for: row.category))
                                    .frame(width: 6, height: 6)
                                Text(row.name)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                Spacer()
                                Text(formatMinutes(row.seconds))
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .contentShape(Rectangle())
                            .gesture(
                                TapGesture(count: 2)
                                    .exclusively(before: TapGesture())
                                    .onEnded { result in
                                        guard let activity = row.segments.first else { return }
                                        switch result {
                                        case .first:
                                            prepareNewEntry(for: activity)
                                            showingNewEntry = true
                                        case .second:
                                            selectedActivity = activity
                                        }
                                    }
                            )
                            .onDrag {
                                let ids = row.segments.map(\.id.uuidString).joined(separator: "\n")
                                return NSItemProvider(object: NSString(string: ids))
                            }
                            .contextMenu {
                                if let activity = row.segments.first {
                                    Button("Select \(row.segments.count) activities") {
                                        selectedActivityIDs.formUnion(row.segments.map(\.id))
                                    }
                                    if !selectedActivityIDs.isEmpty {
                                        Button("Create Time Entries from Selected Activities") {
                                            showingEntryOMatic = true
                                        }
                                    }
                                    Divider()
                                    Button("Create Time Entry") {
                                        prepareNewEntry(for: activity)
                                        showingNewEntry = true
                                    }
                                    Button("Delete \(row.segments.count) Activities", role: .destructive) {
                                        requestDeleteActivities(row.segments)
                                    }
                                }
                            }
                            .help("Click for details · double-click to create a time entry")
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Open \(row.name) in \(title)")
                            .accessibilityHint("Double-click to create a time entry")
                            .accessibilityAddTraits(.isButton)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 184)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(MetridayTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(MetridayTheme.line, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func activityRow(_ segment: ActivitySegment) -> some View {
        if segment.isCollapsedSummary {
            collapsedActivityRow(segment)
        } else {
            normalActivityRow(segment)
        }
    }

    private func collapsedActivityRow(_ segment: ActivitySegment) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 30, height: 30)
                    .background(MetridayTheme.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(segment.appName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("\(segment.collapsedActivityIDs.count) activities · Display-only summary")
                        .font(.system(size: 10))
                        .foregroundStyle(MetridayTheme.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 220, alignment: .leading)

            HStack(spacing: 6) {
                Circle()
                    .fill(MetridayTheme.secondary)
                    .frame(width: 7, height: 7)
                Text("Collapsed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(width: 112, height: 24, alignment: .leading)
            .background(MetridayTheme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Spacer(minLength: 10)

            Text(formatMinutes(segment.durationSeconds))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MetridayTheme.graphite)
                .frame(width: 52, alignment: .trailing)

            Label(projectStore.name(for: segment.projectID), systemImage: "folder")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .frame(width: 122, alignment: .leading)
                .foregroundStyle(MetridayTheme.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(MetridayTheme.canvas.opacity(0.45))
        .help("Collapsed short activities; change the threshold in Activity Display Settings")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Collapsed short activities, \(segment.collapsedActivityIDs.count) activities, \(formatMinutes(segment.durationSeconds))")
    }

    private func normalActivityRow(_ segment: ActivitySegment) -> some View {
        let category = category(for: segment)
        return HStack(spacing: 12) {
            Button {
                toggleActivitySelection(segment.id)
            } label: {
                Image(systemName: selectedActivityIDs.contains(segment.id)
                    ? "checkmark.circle.fill"
                    : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(selectedActivityIDs.contains(segment.id)
                        ? MetridayTheme.accent
                        : MetridayTheme.secondary)
            }
            .buttonStyle(.plain)
            .help(selectedActivityIDs.contains(segment.id) ? "Deselect activity" : "Select activity")
            .accessibilityLabel(selectedActivityIDs.contains(segment.id)
                ? "Deselect activity"
                : "Select activity")
            .accessibilityIdentifier("activity.select.\(segment.id.uuidString)")

            Button {
                selectedActivity = segment
            } label: {
                HStack(spacing: 12) {
                    HStack(spacing: 9) {
                        AppIdentityIcon(
                            symbol: icon(for: segment),
                            bundleIdentifier: segment.bundleIdentifier,
                            size: 30
                        )

                        VStack(alignment: .leading, spacing: 3) {
                            Text(appName(for: segment))
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            if let context = appContext(for: segment) {
                                Text(context)
                                    .font(.system(size: 10))
                                    .foregroundStyle(MetridayTheme.secondary)
                                    .lineLimit(1)
                            }
                            if preferences.showActivityDateRanges {
                                Text(activityDateRangeLabel(for: segment))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(MetridayTheme.secondary.opacity(0.82))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(width: 208, alignment: .leading)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(categoryColor(for: category))
                            .frame(width: 7, height: 7)
                        Text(category.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(categoryColor(for: category))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .frame(width: 112, height: 24, alignment: .leading)
                    .background(categoryColor(for: category).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Spacer(minLength: 10)

                    Text(formatMinutes(segment.durationSeconds))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MetridayTheme.graphite)
                        .frame(width: 52, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        prepareNewEntry(startMinute: segment.startMinute, endMinute: segment.endMinute)
                        showingNewEntry = true
                    }
            )
            .help("Click for details · double-click to create a time entry")
            .accessibilityLabel("Open \(appName(for: segment)) activity")
            .accessibilityHint("Double-click to create a time entry")
            .accessibilityIdentifier("activity.open.\(segment.id.uuidString)")

            Menu {
                Button("Unassigned") {
                    assignActivity(segment.id, to: nil, date: segment.activityDate)
                }
                Divider()
                ForEach(projectStore.activeProjects) { project in
                    Button {
                        assignActivity(segment.id, to: project.id, date: segment.activityDate)
                    } label: {
                        Label(project.name, systemImage: project.id == segment.projectID ? "checkmark" : "folder")
                    }
                }
            } label: {
                Label(projectStore.name(for: segment.projectID), systemImage: "folder")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .frame(width: 122, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .accessibilityIdentifier("activity.project.\(segment.id.uuidString)")

            if let projectID = segment.projectID {
                Button {
                    _ = createRule(for: segment, projectID: projectID)
                } label: {
                    Image(systemName: "wand.and.stars")
                }
                .buttonStyle(.borderless)
                .help("Create a rule from this activity")
                .accessibilityIdentifier("activity.create-rule.\(segment.id.uuidString)")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(selectedActivityIDs.contains(segment.id)
            ? MetridayTheme.accentSoft.opacity(0.52)
            : Color.clear)
        .onDrag {
            NSItemProvider(object: segment.id.uuidString as NSString)
        }
        .contextMenu {
            Button(selectedActivityIDs.contains(segment.id) ? "Deselect Activity" : "Select Activity") {
                toggleActivitySelection(segment.id)
            }
            if !selectedActivityIDs.isEmpty {
                Button("Create Time Entries from Selected Activities") {
                    showingEntryOMatic = true
                }
            }
            Divider()
            Button("Create Time Entry") {
                prepareNewEntry(startMinute: segment.startMinute, endMinute: segment.endMinute)
                showingNewEntry = true
            }
            Button("Delete Activity", role: .destructive) {
                requestDeleteActivities([segment])
            }
        }
        .help("Double-click or right-click to create a time entry")
}

    private func category(for segment: ActivitySegment) -> ActivityCategoryDefinition {
        categoryStore.category(
            for: segment,
            filterStore: filterStore,
            date: segment.activityDate ?? selectedDate
        )
    }

    private func categories(for segments: [ActivitySegment]) -> [ActivityCategoryDefinition] {
        var definitions: [UUID: ActivityCategoryDefinition] = [:]
        var seconds: [UUID: Int] = [:]
        for segment in segments {
            let definition = category(for: segment)
            definitions[definition.id] = definition
            seconds[definition.id, default: 0] += segment.durationSeconds
        }
        return definitions.values.sorted {
            let firstSeconds = seconds[$0.id, default: 0]
            let secondSeconds = seconds[$1.id, default: 0]
            if firstSeconds == secondSeconds { return $0.name < $1.name }
            return firstSeconds > secondSeconds
        }
    }

    private func categoryColor(for category: ActivityCategoryDefinition) -> Color {
        switch category.color {
        case .blue:
            return MetridayTheme.accentDeep
        case .green:
            return MetridayTheme.success
        case .orange:
            return MetridayTheme.warning
        case .purple:
            return .purple
        case .red:
            return MetridayTheme.danger
        case .graphite:
            return MetridayTheme.secondary
        }
    }

    private func appName(for segment: ActivitySegment) -> String {
        let name = segment.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Unknown App" : name
    }

    private func appContext(for segment: ActivitySegment) -> String? {
        let title = segment.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let usefulTitle = title.isEmpty || title.caseInsensitiveCompare(segment.appName) == .orderedSame ? nil : title
        let path = preferences.showResourcePaths && !segment.resource.isEmpty
            ? resourceLabel(segment.resource)
            : nil
        let context: String?
        if let path {
            if preferences.showWindowTitles,
               let usefulTitle,
               preferences.includeTitlesInAdditionToPaths {
                context = "\(path) · \(usefulTitle)"
            } else {
                context = path
            }
        } else if preferences.showWindowTitles, let usefulTitle {
            context = usefulTitle
        } else if segment.deviceName != appState.syncStore.deviceName {
            context = segment.deviceName
        } else {
            context = nil
        }
        guard let activityDate = segment.activityDate,
              !Calendar.current.isDate(activityDate, inSameDayAs: selectedDate) else {
            return context
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return [formatter.string(from: activityDate), context]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func activityDateRangeLabel(for segment: ActivitySegment) -> String {
        let calendar = Calendar.current
        let logicalDay = calendar.startOfDay(for: segment.activityDate ?? selectedDate)
        let start = TrackingDay.date(
            forAxisSeconds: segment.startSecond,
            logicalDayLabel: logicalDay,
            wrapAtMinute: trackingPreferences.wrapDaysAtMinute,
            calendar: calendar
        )
        let end = TrackingDay.date(
            forAxisSeconds: segment.endSecond,
            logicalDayLabel: logicalDay,
            wrapAtMinute: trackingPreferences.wrapDaysAtMinute,
            calendar: calendar
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }

    private func filterButton(
        title: String,
        icon: String,
        filter target: ActivityFilter,
        tint: Color? = nil,
        summarySeconds: Int? = nil,
        onDoubleTap: (() -> Void)? = nil
    ) -> some View {
        let button = Button {
            selectActivityFilter(target)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 18)
                Text(title)
                Spacer()
                if let summarySeconds {
                    Text(formatMinutes(summarySeconds))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                if filter == target {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .font(.system(size: 12, weight: filter == target ? .semibold : .regular))
            .foregroundStyle(filter == target ? (tint ?? MetridayTheme.accent) : MetridayTheme.graphite)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 38)
            .background(filter == target ? MetridayTheme.accentSoft : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        if let onDoubleTap {
            return AnyView(
                button.gesture(
                    TapGesture(count: 2)
                        .exclusively(before: TapGesture())
                        .onEnded { result in
                            switch result {
                            case .first:
                                onDoubleTap()
                            case .second:
                                selectActivityFilter(target)
                            }
                        }
                )
            )
        }

        return AnyView(button)
    }

    private func savedFilterButton(_ savedFilter: ActivityFilterDefinition) -> some View {
        filterButton(
            title: savedFilter.name,
            icon: "line.3.horizontal.decrease.circle",
            filter: .saved(savedFilter.id),
            tint: color(for: savedFilter.color),
            onDoubleTap: {
                editingFilter = savedFilter
                showingFilterEditor = true
            }
        )
        .contextMenu {
            Button("Edit Filter") {
                editingFilter = savedFilter
                showingFilterEditor = true
            }
            Button("Archive Filter") {
                filterStore.archive(savedFilter)
                if filter == .saved(savedFilter.id) {
                    filter = .all
                }
            }
            Button("Delete Filter", role: .destructive) {
                filterStore.delete(savedFilter)
                if filter == .saved(savedFilter.id) {
                    filter = .all
                }
            }
        }
    }

    private func projectDurationSeconds(for projectID: UUID) -> Int {
        let projectIDs = descendantProjectIDs(including: projectID)
        return allActivitySegments
            .filter { segment in
                guard let segmentProjectID = segment.projectID else { return false }
                return projectIDs.contains(segmentProjectID)
            }
            .reduce(0) { $0 + $1.durationSeconds }
    }

    private func descendantProjectIDs(including projectID: UUID) -> Set<UUID> {
        projectStore.descendantProjectIDs(including: projectID)
    }

    private func selectedProjectIDs(including projectID: UUID) -> Set<UUID> {
        trackingPreferences.includeSubprojectsWhenSelectingProject
            ? descendantProjectIDs(including: projectID)
            : [projectID]
    }

    private func projectTree(_ project: TrackingProject, depth: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 0) {
                projectButton(project, depth: depth)
                if !collapsedProjectIDs.contains(project.id) {
                    ForEach(projectStore.childProjects(of: project.id)) { child in
                        projectTree(child, depth: depth + 1)
                    }
                }
            }
        )
    }

    private func archivedProjectRow(_ project: TrackingProject) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color(for: project.color).opacity(0.55))
                .frame(width: 8, height: 8)
            Text(project.name)
                .lineLimit(1)
            Spacer()
            Button {
                projectStore.restore(project)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("Restore \(project.name)")
            .accessibilityLabel("Restore \(project.name)")
        }
        .font(.system(size: 11))
        .foregroundStyle(MetridayTheme.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Restore Project") {
                projectStore.restore(project)
            }
        }
    }

    private func projectButton(_ project: TrackingProject, depth: Int = 0) -> some View {
        let target = ActivityFilter.project(project.id)
        let children = projectStore.childProjects(of: project.id)
        let isCollapsed = collapsedProjectIDs.contains(project.id)
        return HStack(spacing: 0) {
            if !children.isEmpty {
                Button {
                    if isCollapsed {
                        collapsedProjectIDs.remove(project.id)
                    } else {
                        collapsedProjectIDs.insert(project.id)
                    }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 14, height: 26)
                }
                .buttonStyle(.borderless)
                .help(isCollapsed ? "Expand \(project.name)" : "Collapse \(project.name)")
                .accessibilityLabel(isCollapsed ? "Expand \(project.name)" : "Collapse \(project.name)")
            } else {
                Spacer()
                    .frame(width: 14)
            }

            Button {
                selectActivityFilter(target)
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(color(for: project.color))
                        .frame(width: 9, height: 9)
                    Text(project.name)
                        .lineLimit(1)
                    Spacer()
                    Text(formatMinutes(projectDurationSeconds(for: project.id)))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MetridayTheme.secondary)
                    if filter == target {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                .font(.system(size: 12, weight: filter == target ? .semibold : .regular))
                .foregroundStyle(filter == target ? MetridayTheme.accent : MetridayTheme.graphite)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.leading, 14 + CGFloat(depth * 16))
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded { editingProject = project }
            )
        }
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background(filter == target ? MetridayTheme.accentSoft : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onDrag {
            NSItemProvider(object: NSString(string: "metriday-project:\(project.id.uuidString)"))
        }
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers, _ in
            handleProjectOrActivityDrop(providers, onto: project)
        }
        .contextMenu {
            Button("Edit Project") {
                editingProject = project
            }
            Divider()
            Button("Order Subprojects Alphabetically") {
                projectStore.orderSubprojectsAlphabetically(of: project)
            }
            Button("Reassign Subproject Colors") {
                projectStore.reassignSubprojectColors(of: project)
            }
            Button("Archive Project", role: .destructive) {
                projectStore.archive(project)
                if filter == target {
                filter = .all
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activities.project.\(project.id.uuidString)")
        .accessibilityLabel("Project \(project.name), \(formatMinutes(projectDurationSeconds(for: project.id)))")
    }

    }

    private func handleProjectOrActivityDrop(
        _ providers: [NSItemProvider],
        onto project: TrackingProject
    ) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.text.identifier) }) else {
            return handleActivityDrop(providers, onto: project)
        }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.text.identifier) { data, _ in
            guard let data,
                  let rawValue = String(data: data, encoding: .utf8) else {
                return
            }
            if rawValue.hasPrefix("metriday-project:") {
                let sourceID = String(rawValue.dropFirst("metriday-project:".count))
                guard let sourceProjectID = UUID(uuidString: sourceID) else { return }
                Task { @MainActor in
                    guard sourceProjectID != project.id,
                          !projectStore.descendantProjectIDs(including: sourceProjectID).contains(project.id),
                          var sourceProject = projectStore.project(sourceProjectID) else { return }
                    sourceProject.parentID = project.id
                    projectStore.updateProject(sourceProject)
                }
            } else {
                let activityIDs = rawValue
                    .split(whereSeparator: \.isNewline)
                    .compactMap { UUID(uuidString: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
                let shouldCreateRule = NSEvent.modifierFlags.contains(.option)
                let targetProjectID = project.id
                Task { @MainActor in
                    self.applyActivityIDs(activityIDs, to: targetProjectID, shouldCreateRule: shouldCreateRule)
                }
            }
        }
        return true
    }

    private func applyActivityIDs(_ activityIDs: [UUID], to projectID: UUID, shouldCreateRule: Bool) {
        for activityID in Set(activityIDs) {
            guard let activity = allActivitySegments.first(where: { $0.id == activityID }) else { continue }
            if shouldCreateRule {
                _ = createRule(for: activity, projectID: projectID)
            } else {
                assignActivity(activityID, to: projectID)
            }
        }
    }

    private func handleActivityDrop(
        _ providers: [NSItemProvider],
        onto project: TrackingProject
    ) -> Bool {
        guard !providers.isEmpty else { return false }
        let shouldCreateRule = NSEvent.modifierFlags.contains(.option)
        let group = DispatchGroup()
        let ids = LockedArray<UUID>()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                if let data,
                   let rawIDs = String(data: data, encoding: .utf8) {
                    let loadedIDs = rawIDs
                        .split(whereSeparator: \.isNewline)
                        .compactMap { UUID(uuidString: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
                    ids.append(contentsOf: loadedIDs)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            Task { @MainActor in
                self.applyActivityIDs(ids.snapshot, to: project.id, shouldCreateRule: shouldCreateRule)
            }
        }
        return true
    }

    private var allActivitySegments: [ActivitySegment] {
        segmentsForSelectedRange
            .sorted {
                let firstDate = $0.activityDate ?? selectedDate
                let secondDate = $1.activityDate ?? selectedDate
                if firstDate != secondDate { return firstDate < secondDate }
                if $0.startSecond == $1.startSecond { return $0.endSecond < $1.endSecond }
                return $0.startSecond < $1.startSecond
            }
    }

    private var activityTimelineWindow: ActivityTimelineWindow {
        ActivityTimelineWindow(
            zoomed: appState.preferences.automaticallyZoomTimelineToWorkingHours,
            workingHoursStartMinute: appState.preferences.workingHoursStartMinute,
            workingHoursEndMinute: appState.preferences.workingHoursEndMinute,
            wrapAtMinute: appState.preferences.wrapDaysAtMinute
        )
    }

    private var segmentsForSelectedRange: [ActivitySegment] {
        let calendar = Calendar.current
        let dates: [Date]
        switch preferences.activityTimeRange {
        case .selectedDay:
            dates = [selectedDate]
        case .lastSevenDays:
            dates = (0..<7).compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: selectedDate)
            }
        case .lastThirtyDays:
            dates = (0..<30).compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: selectedDate)
            }
        case .lastNinetyDays:
            dates = (0..<90).compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: selectedDate)
            }
        }
        return dates.flatMap { date in
            let rawSegments = calendar.isDate(date, inSameDayAs: selectedDate)
                ? monitor.observedSegments + screenTimeStore.segments
                : monitor.segments(for: date) + screenTimeStore.segments(for: date)
            let taggedSegments = rawSegments.map { segment in
                var tagged = segment
                tagged.activityDate = calendar.startOfDay(for: date)
                return tagged
            }
            return categoryStore.applyingCategories(to: taggedSegments, filterStore: filterStore, date: date)
        }
    }

    private var activityRangeLabel: String {
        switch preferences.activityTimeRange {
        case .selectedDay: return "Selected day"
        case .lastSevenDays: return "Last 7 days"
        case .lastThirtyDays: return "Last 30 days"
        case .lastNinetyDays: return "Last 90 days"
        }
    }

    private var filteredSegments: [ActivitySegment] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return filterScopedSegments
            .filter { segment in
                guard let start = timelineSelectionStart, let end = timelineSelectionEnd else {
                    return true
                }
                return segment.startSecond < end * 60 && segment.endSecond > start * 60
            }
            .filter { segment in
                guard !query.isEmpty else { return true }
                return [
                    segment.appName,
                    segment.windowTitle,
                    segment.resource,
                    segment.displayTitle
                ].contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            }
            .sorted { first, second in
            if first.startSecond == second.startSecond {
                return first.endSecond < second.endSecond
            }
            return first.startSecond < second.startSecond
        }
    }

    private struct CollapsedActivityKey: Hashable {
        let projectID: UUID?
        let activityDate: Date?
        let deviceName: String
    }

    private var activityListSegments: [ActivitySegment] {
        let threshold = preferences.collapseActivitiesShorterThanSeconds
        guard threshold > 0 else { return filteredSegments }

        let shortSegments = filteredSegments.filter { $0.durationSeconds < threshold }
        guard shortSegments.count > 1 else { return filteredSegments }
        let longSegments = filteredSegments.filter { $0.durationSeconds >= threshold }
        let groups = Dictionary(grouping: shortSegments) { segment in
            CollapsedActivityKey(
                projectID: segment.projectID,
                activityDate: segment.activityDate.map { Calendar.current.startOfDay(for: $0) },
                deviceName: segment.deviceName
            )
        }
        let displaySegments = groups.values.flatMap { segments -> [ActivitySegment] in
            let ordered = segments.sorted { $0.startSecond < $1.startSecond }
            guard ordered.count > 1, let first = ordered.first else { return ordered }
            var summary = ActivitySegment(
                id: first.id,
                appName: "(Entries shorter than \(shortActivityThresholdLabel(threshold)) each)",
                deviceName: first.deviceName,
                windowTitle: "\(ordered.count) activities",
                startMinute: first.startMinute,
                endMinute: first.endMinute,
                startSecond: first.startSecond,
                endSecond: first.endSecond,
                relevance: .other,
                projectID: first.projectID,
                activityDate: first.activityDate
            )
            summary.collapsedActivityIDs = ordered.map(\.id)
            summary.collapsedDurationSeconds = ordered.reduce(0) { $0 + $1.durationSeconds }
            return [summary]
        }
        return (longSegments + displaySegments).sorted {
            if $0.startSecond == $1.startSecond { return $0.endSecond < $1.endSecond }
            return $0.startSecond < $1.startSecond
        }
    }

    private func shortActivityThresholdLabel(_ seconds: Int) -> String {
        seconds >= 60 ? "\(seconds / 60)m" : "\(seconds)s"
    }

    private var filterScopedSegments: [ActivitySegment] {
        let scoped = scopedSegments(from: segmentsForSelectedRange)
        guard let selectedBuiltinFilter else { return scoped }
        return scoped.filter { selectedBuiltinFilter.matches($0) }
    }

    private var timelineScopedSegments: [ActivitySegment] {
        let resolved = categoryStore.applyingCategories(
            to: monitor.observedSegments + screenTimeStore.segments,
            filterStore: filterStore,
            date: selectedDate
        )
        let scoped = scopedSegments(from: resolved)
        guard let selectedBuiltinFilter else { return scoped }
        return scoped.filter { selectedBuiltinFilter.matches($0) }
    }

    private func scopedSegments(from sourceSegments: [ActivitySegment]) -> [ActivitySegment] {
        let source = sourceSegments
            .filter { includeIdle || $0.relevance != .idle }
            .filter { selectedDevice == ActivityDeviceFilter.all || $0.deviceName == selectedDevice }
        switch filter {
        case .all:
            return source
        case .unassigned:
            return source.filter { $0.projectID == nil }
        case .project(let id):
            let projectIDs = selectedProjectIDs(including: id)
            return source.filter { segment in
                guard let projectID = segment.projectID else { return false }
                return projectIDs.contains(projectID)
            }
        case .saved(let id):
            guard let savedFilter = filterStore.filter(id) else { return [] }
            return source.filter { filterStore.matches(savedFilter, activity: $0, date: $0.activityDate ?? selectedDate) }
        case .category(let id):
            guard categoryStore.categories.contains(where: { $0.id == id && !$0.isArchived }) else { return [] }
            return source.filter {
                categoryStore.category(for: $0, filterStore: filterStore, date: $0.activityDate ?? selectedDate).id == id
            }
        }
    }

    private var filterTitle: String {
        let baseTitle: String
        switch filter {
        case .all:
            baseTitle = "All Activities"
        case .unassigned:
            baseTitle = "Unassigned"
        case .project(let id):
            baseTitle = projectStore.name(for: id)
        case .saved(let id):
            baseTitle = filterStore.filter(id)?.name ?? "Filter"
        case .category(let id):
            baseTitle = categoryStore.categories.first(where: { $0.id == id })?.name ?? "Category"
        }
        if let selectedBuiltinFilter {
            return "\(baseTitle) · \(selectedBuiltinFilter.label)"
        }
        return baseTitle
    }

    private var availableDevices: [String] {
        let devices = Set(allActivitySegments.map(\.deviceName)).sorted()
        return [ActivityDeviceFilter.all] + devices
    }

    private var groupByProjectBinding: Binding<Bool> {
        Binding(
            get: { groupActivitiesByProject },
            set: { enabled in
                groupActivitiesByProject = enabled
            }
        )
    }

    private var groupByDeviceBinding: Binding<Bool> {
        Binding(
            get: { groupActivitiesByDevice },
            set: { enabled in
                groupActivitiesByDevice = enabled
            }
        )
    }

    private func assignActivity(_ id: UUID, to projectID: UUID?, date: Date? = nil) {
        if screenTimeStore.contains(id) {
            screenTimeStore.assignActivity(id, to: projectID, date: date)
        } else {
            monitor.assignActivity(id, to: projectID, date: date)
        }
    }

    private func requestDeleteSelectedActivities() {
        let selected = allActivitySegments.filter { selectedActivityIDs.contains($0.id) }
        requestDeleteActivities(selected)
    }

    private func requestDeleteActivities(_ segments: [ActivitySegment]) {
        let records = segments.compactMap { segment -> DeletedActivityRecord? in
            let date = Calendar.current.startOfDay(for: segment.activityDate ?? selectedDate)
            let isScreenTime = screenTimeStore.segments(for: date).contains { $0.id == segment.id }
            return DeletedActivityRecord(
                segment: segment,
                date: date,
                isScreenTime: isScreenTime
            )
        }
        guard !records.isEmpty else { return }
        pendingActivityDeletion = records
        showingActivityDeletionConfirmation = true
    }

    private func deletePendingActivities() {
        let records = pendingActivityDeletion
        guard !records.isEmpty else { return }
        var deleted: [DeletedActivityRecord] = []
        for record in records {
            let result: [ActivitySegment]
            if record.isScreenTime {
                result = screenTimeStore.deleteActivities([record.segment.id], date: record.date)
            } else {
                result = monitor.deleteActivities([record.segment.id], date: record.date)
            }
            if !result.isEmpty {
                deleted.append(record)
            }
        }
        pendingActivityDeletion = []
        selectedActivityIDs.subtract(deleted.map { $0.segment.id })
        lastDeletedActivities = deleted
    }

    private func undoLastActivityDeletion() {
        let records = lastDeletedActivities
        guard !records.isEmpty else { return }
        let groups = Dictionary(grouping: records) {
            "\($0.isScreenTime)|\(Calendar.current.startOfDay(for: $0.date).timeIntervalSince1970)"
        }
        for records in groups.values {
            guard let first = records.first else { continue }
            let segments = records.map(\.segment)
            if first.isScreenTime {
                screenTimeStore.restoreActivities(segments, date: first.date)
            } else {
                monitor.restoreActivities(segments, date: first.date)
            }
        }
        lastDeletedActivities = []
    }

    @discardableResult
    private func createRule(for activity: ActivitySegment, projectID: UUID) -> UUID? {
        let ruleID = monitor.createRule(for: activity, projectID: projectID)
        if screenTimeStore.contains(activity.id) {
            screenTimeStore.assignActivity(activity.id, to: projectID, date: activity.activityDate)
        }
        return ruleID
    }

    private var totalSeconds: Int {
        filteredSegments.reduce(0) { $0 + $1.durationSeconds }
    }

    private var entryOMaticPreview: [EntryOMaticInterval] {
        EntryOMaticGenerator.intervals(
            from: entryOMaticSegments,
            dayStart: TrackingDay.startDate(
                for: selectedDate,
                wrapAtMinute: appState.preferences.wrapDaysAtMinute
            ),
            existingEntries: timeEntriesForSelectedDate,
            minimumDurationSeconds: 5 * 60,
            maximumGapSeconds: 60
        )
    }

    private var entryOMaticPreviewDuration: Int {
        entryOMaticPreview.reduce(0) { $0 + $1.durationSeconds }
    }

    private var entryOMaticSegments: [ActivitySegment] {
        guard !selectedActivityIDs.isEmpty else { return filteredSegments }
        return filteredSegments.filter { selectedActivityIDs.contains($0.id) }
    }

    private var entryOMaticDescription: String {
        let scope = selectedActivityIDs.isEmpty ? "this app usage" : "the selected activities"
        return "Metriday can automatically create \(entryOMaticPreview.count) time entries with a total duration of \(formatMinutes(entryOMaticPreviewDuration)) to cover \(scope)."
    }

    private func toggleActivitySelection(_ id: UUID) {
        if selectedActivityIDs.contains(id) {
            selectedActivityIDs.remove(id)
        } else {
            selectedActivityIDs.insert(id)
        }
    }

    private var activityGroups: [ActivityGroup] {
        let grouped = Dictionary(grouping: activityListSegments) { projectStore.name(for: $0.projectID) }
        return grouped.map { name, segments in
            ActivityGroup(
                name: name,
                segments: segments.sorted { $0.startSecond < $1.startSecond },
                seconds: segments.reduce(0) { $0 + $1.durationSeconds }
            )
        }
        .sorted { first, second in
            if first.seconds == second.seconds { return first.name < second.name }
            return first.seconds > second.seconds
        }
    }

    private var selectedProjectID: UUID? {
        if case .project(let id) = filter {
            return id
        }
        return nil
    }

    private var timeEntriesForSelectedDate: [TimeEntry] {
        timeEntryStore.entries(
            overlapping: selectedDate,
            wrapAtMinute: appState.preferences.wrapDaysAtMinute
        )
    }

    private var timelineTimeEntries: [TimeEntry] {
        let range = TrackingDay.range(
            for: selectedDate,
            wrapAtMinute: appState.preferences.wrapDaysAtMinute
        )
        return timeEntryStore.materializedEntries().filter {
            $0.start < range.end && $0.end > range.start
        }
    }

    private var timelineSuggestions: [ActivityTimelineSuggestion] {
        ActivityInsights.generateTimelineSuggestions(from: timelineScopedSegments)
    }

    private var newProjectSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Project")
                .font(.system(size: 18, weight: .bold))
            TextField("Project name", text: $newProjectName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(createProject)
            Picker("Parent project", selection: $newProjectParentID) {
                Text("Top level").tag(nil as UUID?)
                ForEach(projectStore.activeProjects) { project in
                    Text(project.name).tag(project.id as UUID?)
                }
            }
            if !teamStore.activeTeams.isEmpty {
                Picker("Team", selection: $newProjectTeamID) {
                    Text("Personal project").tag(nil as UUID?)
                    ForEach(teamStore.activeTeams) { team in
                        Text(team.name).tag(team.id as UUID?)
                    }
                }
            }
            Toggle("Automatically match this project's title and path", isOn: $addProjectNameRules)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
            Text("Adds rules for future activities whose title or file path contains the project name.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { showingNewProject = false }
                Button("Create", action: createProject)
                    .buttonStyle(.borderedProminent)
                    .disabled(newProjectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private var newEntrySheet: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("New Time Entry")
                .font(.system(size: 18, weight: .bold))

            TimeEntryTitleField(
                title: $newEntryTitle,
                billingStatus: $newEntryBillingStatus,
                placeholder: "What did you work on?",
                entries: timeEntryStore.entries,
                projects: projectStore.activeProjects
            )

            if !reminderStore.reminders.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Completed reminders")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MetridayTheme.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(reminderStore.reminders.prefix(5)) { reminder in
                                Button {
                                    prepareNewEntry(for: reminder)
                                } label: {
                                    Text(reminder.title)
                                        .lineLimit(1)
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(MetridayTheme.canvas)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .help("Use reminder as title")
                            }
                        }
                    }
                }
            }

            if !calendarStore.events.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent calendar events")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MetridayTheme.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(calendarStore.events.prefix(5)) { event in
                                Button {
                                    applyCalendarSuggestion(event)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.title)
                                            .lineLimit(1)
                                        Text("\(event.start.formatted(date: .omitted, time: .shortened)) · \(event.calendarTitle)")
                                            .font(.system(size: 9))
                                            .foregroundStyle(MetridayTheme.secondary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(MetridayTheme.canvas)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .help("Use calendar event as a time-entry suggestion")
                            }
                        }
                    }
                }
            }

            Picker("Project", selection: $newEntryProjectID) {
                Text("Unassigned").tag(nil as UUID?)
                ForEach(projectStore.activeProjects) { project in
                    Text(project.name).tag(project.id as UUID?)
                }
            }

            Picker("Billing Status", selection: $newEntryBillingStatus) {
                ForEach(BillingStatus.allCases) { status in
                    Text(status.label).tag(status)
                }
            }

            DatePicker("Start", selection: $newEntryStart, displayedComponents: [.date, .hourAndMinute])
            DatePicker("End", selection: $newEntryEnd, displayedComponents: [.date, .hourAndMinute])

            TextField("Notes (optional)", text: $newEntryNotes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3, reservesSpace: true)

            HStack {
                Spacer()
                Button("Cancel") { showingNewEntry = false }
                Button("Add Time Entry", action: addNewEntry)
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        newEntryTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || newEntryEnd <= newEntryStart
                    )
            }
        }
        .padding(24)
        .frame(width: 420)
        .onChange(of: newEntryProjectID) { _, projectID in
            newEntryBillingStatus = projectStore.resolvedBillingStatus(for: projectID)
        }
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let projectID = projectStore.createProject(
            name: name,
            parentID: newProjectParentID,
            teamID: newProjectTeamID
        ) else { return }
        if addProjectNameRules {
            _ = projectStore.addDefaultNameRules(projectID: projectID, projectName: name)
        }
        filter = .project(projectID)
        newProjectName = ""
        newProjectParentID = nil
        newProjectTeamID = nil
        addProjectNameRules = true
        showingNewProject = false
    }

    private func prepareNewEntry(
        for event: CalendarEventItem? = nil,
        startMinute: Int? = nil,
        endMinute: Int? = nil,
        date: Date? = nil
    ) {
        newEntryTitle = ""
        newEntryNotes = ""
        newEntryProjectID = selectedProjectID
        newEntryBillingStatus = projectStore.resolvedBillingStatus(for: selectedProjectID)
        if let event {
            newEntryTitle = event.title
            newEntryNotes = [event.calendarTitle, event.location, event.notes]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " · ")
            if selectedProjectID == nil {
                newEntryProjectID = suggestedProjectID(for: event)
                newEntryBillingStatus = projectStore.resolvedBillingStatus(for: newEntryProjectID)
            }
            newEntryStart = event.start
            newEntryEnd = event.end
            return
        }
        if let startMinute, let endMinute, endMinute > startMinute {
            let day = Calendar.current.startOfDay(for: date ?? selectedDate)
            let wrapAtMinute = appState.preferences.wrapDaysAtMinute
            newEntryStart = TrackingDay.date(
                forAxisSeconds: startMinute * 60,
                logicalDayLabel: day,
                wrapAtMinute: wrapAtMinute
            )
            newEntryEnd = TrackingDay.date(
                forAxisSeconds: endMinute * 60,
                logicalDayLabel: day,
                wrapAtMinute: wrapAtMinute
            )
            return
        }
        if let timelineSelectionStart, let timelineSelectionEnd,
           timelineSelectionEnd > timelineSelectionStart {
            let wrapAtMinute = appState.preferences.wrapDaysAtMinute
            newEntryStart = TrackingDay.date(
                forAxisSeconds: timelineSelectionStart * 60,
                logicalDayLabel: selectedDate,
                wrapAtMinute: wrapAtMinute
            )
            newEntryEnd = TrackingDay.date(
                forAxisSeconds: timelineSelectionEnd * 60,
                logicalDayLabel: selectedDate,
                wrapAtMinute: wrapAtMinute
            )
            return
        }
        let calendar = Calendar.current
        let baseDate: Date
        let logicalToday = TrackingDay.logicalDayLabel(
            for: .now,
            wrapAtMinute: appState.preferences.wrapDaysAtMinute
        )
        if calendar.isDate(selectedDate, inSameDayAs: logicalToday) {
            baseDate = Date()
        } else {
            baseDate = calendar.date(
                bySettingHour: 12,
                minute: 0,
                second: 0,
                of: selectedDate
            ) ?? selectedDate
        }
        newEntryEnd = baseDate
        newEntryStart = newEntryEnd.addingTimeInterval(-3600)
    }

    private func prepareNewEntry(for activity: ActivitySegment) {
        prepareNewEntry(startMinute: activity.startMinute, endMinute: activity.endMinute, date: activity.activityDate)
        newEntryTitle = activity.appName.isEmpty ? "App activity" : activity.appName
        newEntryNotes = activity.displayTitle
        newEntryProjectID = activity.projectID ?? selectedProjectID
        newEntryBillingStatus = projectStore.resolvedBillingStatus(for: newEntryProjectID)
    }

    private func prepareNewEntry(for suggestion: ActivityTimelineSuggestion) {
        prepareNewEntry(
            startMinute: suggestion.startMinute,
            endMinute: suggestion.endMinute
        )
        newEntryTitle = suggestion.title
        newEntryNotes = suggestion.notes
        newEntryProjectID = suggestion.projectID ?? selectedProjectID
        newEntryBillingStatus = projectStore.resolvedBillingStatus(for: newEntryProjectID)
    }

    private func prepareNewEntry(for reminder: ReminderItem) {
        newEntryTitle = reminder.title
        newEntryNotes = [reminder.listTitle, reminder.notes]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " · ")
        newEntryProjectID = selectedProjectID
        newEntryBillingStatus = projectStore.resolvedBillingStatus(for: selectedProjectID)
        newEntryEnd = reminder.completedAt
        newEntryStart = reminder.completedAt.addingTimeInterval(-30 * 60)
    }

    private func applyCalendarSuggestion(_ event: CalendarEventItem) {
        newEntryTitle = event.title
        newEntryNotes = [event.calendarTitle, event.location, event.notes]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " · ")
        if selectedProjectID == nil {
            newEntryProjectID = suggestedProjectID(for: event)
        }
        newEntryBillingStatus = projectStore.resolvedBillingStatus(for: newEntryProjectID)
    }

    private func prepareNewEntry(for call: PhoneCallItem) {
        newEntryTitle = call.title
        newEntryNotes = [call.serviceProvider, call.address]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " · ")
        newEntryProjectID = selectedProjectID
        newEntryBillingStatus = projectStore.resolvedBillingStatus(for: selectedProjectID)
        newEntryStart = call.start
        newEntryEnd = call.end
    }

    private func suggestedProjectID(for event: CalendarEventItem) -> UUID? {
        appState.suggestedProjectID(for: event)
    }

    private func addNewEntry() {
        overlappingEntries = timeEntryStore.entries(
            overlapping: newEntryStart,
            end: newEntryEnd
        )
        if !overlappingEntries.isEmpty {
            showingOverlapConfirmation = true
            return
        }
        commitNewEntry(replacing: false)
    }

    private func commitNewEntry(replacing: Bool) {
        if replacing {
            _ = timeEntryStore.splitOverlappingEntries(
                overlappingEntries,
                excluding: [(start: newEntryStart, end: newEntryEnd)]
            )
        }
        guard timeEntryStore.addEntry(
            title: newEntryTitle,
            projectID: newEntryProjectID,
            notes: newEntryNotes,
            start: newEntryStart,
            end: newEntryEnd,
            billingStatus: newEntryBillingStatus
        ) != nil else { return }
        overlappingEntries = []
        showingNewEntry = false
    }

    private var overlapMessage: String {
        let noun = overlappingEntries.count == 1 ? "entry" : "entries"
        return "This range overlaps \(overlappingEntries.count) existing time \(noun). Replace the selected range or keep parallel entries? Time outside the range is preserved."
    }

    private func formatMinutes(_ seconds: Int) -> String {
        let minutes = Double(seconds) / 60.0
        if minutes < 1 { return "<1m" }
        let rounded = Int(minutes.rounded())
        let hours = rounded / 60
        let remainder = rounded % 60
        if hours > 0 {
            return "\(hours)h \(remainder)m"
        }
        return "\(remainder)m"
    }

    private func resourceLabel(_ value: String) -> String {
        if let url = URL(string: value), let host = url.host {
            return host
        }
        return value
    }

    private func displayTitle(for segment: ActivitySegment) -> String {
        guard preferences.showWindowTitles else {
            if preferences.showResourcePaths,
               let host = URL(string: segment.resource)?.host,
               !host.isEmpty {
                return "\(segment.appName) · \(host)"
            }
            return segment.appName
        }
        return segment.displayTitle
    }

    private func formatDateRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }

    private func billingAmountLabel(for entry: TimeEntry) -> String? {
        guard entry.billingStatus != .notBillable,
              let project = projectStore.project(entry.projectID),
              project.billingRate > 0 else { return nil }
        let amount = project.billingRate * Double(entry.durationSeconds) / 3_600.0
        return String(format: "%@ %.2f", project.currency, amount)
    }

    private var websiteSegments: [ActivitySegment] {
        filteredSegments.filter { URL(string: $0.resource)?.host != nil }
    }

    private var applicationSegments: [ActivitySegment] {
        filteredSegments.filter { !$0.appName.isEmpty }
    }

    private var pathSegments: [ActivitySegment] {
        filteredSegments.filter {
            !$0.resource.isEmpty && URL(string: $0.resource)?.host == nil
        }
    }

    private var pathRows: [CategoryRow] {
        categoryRows(pathSegments, namesFor: { segment in
            pathGroupingNames(for: segment.resource)
        })
    }

    private func pathGroupingNames(for resource: String) -> [String] {
        preferences.groupPathsBy.groupNames(for: resource)
    }

    private var keywordSegments: [ActivitySegment] {
        filteredSegments.filter { !$0.windowTitle.isEmpty }
    }

    private var keywordRows: [CategoryRow] {
        let stopWords: Set<String> = [
            "the", "and", "for", "with", "from", "http", "https", "www", "com"
        ]
        var values: [String: CategoryAggregation] = [:]
        for segment in keywordSegments {
            let category = category(for: segment)
            let source = "\(segment.windowTitle) \(segment.resource)"
            let words = source
                .split { character in
                    !(character.isLetter || character.isNumber || character == "_" || character == "-")
                }
                .map { $0.lowercased() }
                .filter { $0.count >= 3 && !stopWords.contains($0) }
            for word in Set(words) {
                values[word, default: CategoryAggregation()].add(
                    seconds: segment.durationSeconds,
                    category: category,
                    segment: segment
                )
            }
        }
        return values.map { name, value in
            CategoryRow(
                name: name,
                seconds: value.seconds,
                category: value.primaryCategory ?? ActivityCategoryDefinition(
                    name: "Other",
                    role: .other,
                    isSystem: true
                ),
                segments: value.segments
            )
        }
        .sorted { $0.seconds > $1.seconds }
    }

    private func categoryRows(
        _ segments: [ActivitySegment],
        nameFor: ((ActivitySegment) -> String)? = nil,
        namesFor: ((ActivitySegment) -> [String])? = nil
    ) -> [CategoryRow] {
        var values: [String: CategoryAggregation] = [:]
        for segment in segments {
            let names = namesFor?(segment) ?? [nameFor?(segment) ?? categoryName(for: segment)]
            for name in names.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
                values[name, default: CategoryAggregation()].add(
                    seconds: segment.durationSeconds,
                    category: category(for: segment),
                    segment: segment
                )
            }
        }
        return values.map { name, value in
            CategoryRow(
                name: name,
                seconds: value.seconds,
                category: value.primaryCategory ?? ActivityCategoryDefinition(
                    name: "Other",
                    role: .other,
                    isSystem: true
                ),
                segments: value.segments
            )
        }
        .sorted { $0.seconds > $1.seconds }
    }

    private func categoryName(for segment: ActivitySegment) -> String {
        switch activityMode {
        case .unified:
            return segment.displayTitle
        case .chronological:
            return segment.displayTitle
        case .byCategory:
            if let host = URL(string: segment.resource)?.host, !host.isEmpty {
                return host
            }
            return segment.appName
        }
    }

    private func icon(for segment: ActivitySegment) -> String {
        switch segment.bundleIdentifier {
        case "com.microsoft.VSCode", "com.apple.dt.Xcode":
            return "chevron.left.forwardslash.chevron.right"
        case "com.apple.Terminal", "com.googlecode.iterm2":
            return "terminal"
        case "com.google.Chrome", "com.apple.Safari":
            return "globe"
        case "com.apple.Preview":
            return "doc.richtext"
        case "com.metriday.idle":
            return "moon.zzz"
        default:
            return "rectangle.on.rectangle"
        }
    }

    private func color(for relevance: ActivityRelevance) -> Color {
        ActivityCategoryKind(relevance: relevance).color
    }

    private func color(for projectColor: ProjectColor) -> Color {
        switch projectColor {
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
}

private enum ActivityFilter: Hashable {
    case all
    case unassigned
    case project(UUID)
    case saved(UUID)
    case category(UUID)
}

private enum ActivityBuiltinFilter: String, CaseIterable, Hashable, Identifiable {
    case webBrowsing
    case media
    case communication
    case officeBusiness
    case readingWriting
    case fileManagement
    case graphics
    case development
    case finance
    case gaming
    case socialMedia

    var id: Self { self }

    var label: String {
        switch self {
        case .webBrowsing: return "Web Browsing"
        case .media: return "Media"
        case .communication: return "Communication"
        case .officeBusiness: return "Office & Business"
        case .readingWriting: return "Reading & Writing"
        case .fileManagement: return "File Management"
        case .graphics: return "Graphics"
        case .development: return "Development"
        case .finance: return "Finance"
        case .gaming: return "Gaming"
        case .socialMedia: return "Social Media"
        }
    }

    var icon: String {
        switch self {
        case .webBrowsing: return "globe"
        case .media: return "play.rectangle"
        case .communication: return "message"
        case .officeBusiness: return "briefcase"
        case .readingWriting: return "book"
        case .fileManagement: return "folder"
        case .graphics: return "paintpalette"
        case .development: return "hammer"
        case .finance: return "dollarsign.circle"
        case .gaming: return "gamecontroller"
        case .socialMedia: return "person.2"
        }
    }

    func matches(_ segment: ActivitySegment) -> Bool {
        let app = segment.appName.lowercased()
        let bundle = segment.bundleIdentifier.lowercased()
        let title = segment.windowTitle.lowercased()
        let resource = segment.resource.lowercased()
        let haystack = "\(app) \(bundle) \(title) \(resource)"
        let host = URL(string: segment.resource)?.host?.lowercased() ?? ""

        func containsAny(_ terms: [String]) -> Bool {
            terms.contains { haystack.contains($0) }
        }

        switch self {
        case .webBrowsing:
            return !host.isEmpty || containsAny([
                "safari", "chrome", "firefox", "brave", "arc", "edge", "opera", "vivaldi", "browser"
            ])
        case .media:
            return containsAny([
                "music", "spotify", "podcast", "tv", "youtube", "netflix", "vlc", "video", "plex", "twitch"
            ])
        case .communication:
            return containsAny([
                "slack", "messages", "mail", "outlook", "teams", "zoom", "discord", "wechat", "telegram", "signal", "skype", "whatsapp"
            ])
        case .officeBusiness:
            return containsAny([
                "word", "excel", "powerpoint", "keynote", "numbers", "notion", "linear", "clickup", "asana", "office", "spreadsheet", "invoice", "salesforce"
            ])
        case .readingWriting:
            return containsAny([
                "books", "kindle", "reader", "preview", "notes", "textedit", "ulysses", "ia writer", "obsidian", "scrivener", "writer", "medium", "wikipedia"
            ])
        case .fileManagement:
            return containsAny([
                "finder", "file manager", "path finder", "transmit", "dropbox", "google drive", "onedrive", "files", "folder"
            ])
        case .graphics:
            return containsAny([
                "figma", "sketch", "photoshop", "illustrator", "affinity", "pixelmator", "blender", "design", "paint", "canva"
            ])
        case .development:
            return containsAny([
                "xcode", "terminal", "iterm", "visual studio", "code", "cursor", "sublime", "intellij", "pycharm", "android studio", "git", "github", "developer", "console"
            ])
        case .finance:
            return containsAny([
                "bank", "finance", "budget", "money", "mint", "quickbooks", "coinbase", "paypal", "stripe", "invoice", "accounting", "trading"
            ])
        case .gaming:
            return containsAny([
                "steam", "game", "gaming", "epic games", "battle.net", "minecraft", "playstation", "xbox", "roblox"
            ])
        case .socialMedia:
            return containsAny([
                "facebook", "instagram", "twitter", "x.com", "reddit", "linkedin", "tiktok", "mastodon", "social", "threads", "snapchat", "pinterest"
            ])
        }
    }
}

private struct ActivityFilterEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onSave: (ActivityFilterDefinition) -> Void
    @State private var draft: ActivityFilterDefinition
    @State private var newField: ActivityFilterField = .application
    @State private var newComparison: ProjectRuleComparison = .contains
    @State private var newPattern = ""
    @State private var newCaseSensitive = false

    init(
        filter: ActivityFilterDefinition?,
        onSave: @escaping (ActivityFilterDefinition) -> Void
    ) {
        self.title = filter == nil ? "New Filter" : "Filter Editor"
        self.onSave = onSave
        _draft = State(initialValue: filter ?? ActivityFilterDefinition(name: "New Filter"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 18, weight: .bold))

            TextField("Filter name", text: $draft.name)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Picker("Match", selection: $draft.matchMode) {
                    ForEach(ActivityFilterMatchMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Picker("Color", selection: $draft.color) {
                    ForEach(ProjectColor.allCases, id: \.self) { value in
                        Text(value.rawValue.capitalized).tag(value)
                    }
                }
            }

            Text("Activities match this filter when \(draft.matchMode == .any ? "any" : "all") of its rules match. Filters never change project assignments.")
                .font(.system(size: 11))
                .foregroundStyle(MetridayTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if draft.rules.isEmpty {
                Text("Add at least one rule to make this filter active.")
                    .font(.system(size: 11))
                    .foregroundStyle(MetridayTheme.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(draft.rules.enumerated()), id: \.element.id) { index, rule in
                        if draft.rules.indices.contains(index) {
                            let binding = Binding<ActivityFilterRule>(
                                get: { draft.rules[index] },
                                set: { draft.rules[index] = $0 }
                            )
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(spacing: 8) {
                                    Picker("Field", selection: binding.field) {
                                        ForEach(ActivityFilterField.allCases) { field in
                                            Text(field.label).tag(field)
                                        }
                                    }
                                    Picker("Relation", selection: binding.comparison) {
                                        ForEach(ProjectRuleComparison.allCases) { comparison in
                                            Text(comparison.label).tag(comparison)
                                        }
                                    }
                                    Button(role: .destructive) {
                                        draft.rules.remove(at: index)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                HStack(spacing: 8) {
                                    TextField("Value", text: binding.pattern)
                                        .textFieldStyle(.roundedBorder)
                                    Toggle("Case-sensitive", isOn: binding.isCaseSensitive)
                                        .toggleStyle(.checkbox)
                                        .controlSize(.small)
                                        .font(.system(size: 10))
                                }
                            }
                            .padding(10)
                            .background(MetridayTheme.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }

            Divider()

            Text("Add rule")
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                Picker("Field", selection: $newField) {
                    ForEach(ActivityFilterField.allCases) { field in
                        Text(field.label).tag(field)
                    }
                }
                Picker("Relation", selection: $newComparison) {
                    ForEach(ProjectRuleComparison.allCases) { comparison in
                        Text(comparison.label).tag(comparison)
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Value", text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                Toggle("Case-sensitive", isOn: $newCaseSensitive)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .font(.system(size: 10))
                Button {
                    addRule()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(newPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save Filter") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || draft.rules.isEmpty
                )
            }
        }
        .padding(24)
        .frame(width: 620)
    }

    private func addRule() {
        let pattern = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        draft.rules.append(
            ActivityFilterRule(
                field: newField,
                pattern: pattern,
                isCaseSensitive: newCaseSensitive,
                comparison: newComparison
            )
        )
        newPattern = ""
        newCaseSensitive = false
    }
}

private struct ActivityDisplaySettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var preferences: ActivitiesPreferencesStore
    @ObservedObject var categoryStore: ActivityCategoryStore
    @ObservedObject var filterStore: ActivityFilterStore
    @State private var showingCategories = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activity Display Settings")
                .font(.system(size: 18, weight: .bold))
            Text("These options change how captured activity is shown. They do not change tracking or previously stored data.")
                .font(.system(size: 11))
                .foregroundStyle(MetridayTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Include time entries in the timeline", isOn: $preferences.includeTimeEntries)
                .toggleStyle(.checkbox)
            Text("When enabled, show only App Usage. Leave this off to include manual and timer entries.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Show window titles", isOn: $preferences.showWindowTitles)
                .toggleStyle(.checkbox)
            Toggle("Show website hosts and file paths", isOn: $preferences.showResourcePaths)
                .toggleStyle(.checkbox)
            Toggle("Show app-usage date ranges", isOn: $preferences.showActivityDateRanges)
                .toggleStyle(.checkbox)
            Text("Adds the exact start and end time below each activity, matching Timing's detailed activity list.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Create entries for titles in addition to paths", isOn: $preferences.includeTitlesInAdditionToPaths)
                .toggleStyle(.checkbox)
            Text("When an activity has both a path and a window title, keep both visible in the activity row.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Collapse activities shorter than", selection: $preferences.collapseActivitiesShorterThanSeconds) {
                Text("Never").tag(0)
                Text("5 seconds").tag(5)
                Text("15 seconds").tag(15)
                Text("30 seconds").tag(30)
                Text("1 minute").tag(60)
            }
            .pickerStyle(.menu)
            Text("Short app-usage rows are summarized in the activity list; the timeline keeps the original evidence.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Group websites independently of their browser", isOn: $preferences.groupWebsitesIndependently)
                .toggleStyle(.checkbox)
            Toggle("Group file paths independently of their app", isOn: $preferences.groupPathsIndependently)
                .toggleStyle(.checkbox)
            Picker("Group file paths by", selection: $preferences.groupPathsBy) {
                ForEach(ActivityPathGrouping.allCases) { grouping in
                    Text(grouping.label).tag(grouping)
                }
            }
            .pickerStyle(.menu)
            Text("All directories includes the parent folders of each file; File path only keeps each file as its own group.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Activity usage range", selection: $preferences.activityTimeRange) {
                ForEach(ActivityTimeRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.menu)

            if preferences.activityTimeRange != .selectedDay {
                Label("The timeline stays on the selected day; the activity list includes the chosen history range.", systemImage: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(MetridayTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Categories")
                        .font(.system(size: 12, weight: .semibold))
                    Text("App, website, and item colors come from their matched category.")
                        .font(.system(size: 10))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                Button("Manage Categories") {
                    showingCategories = true
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("activities.manage-categories")
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 430)
        .sheet(isPresented: $showingCategories) {
            ActivityCategoriesSheet(
                categoryStore: categoryStore,
                filterStore: filterStore
            )
        }
    }
}

private struct ActivityCategoriesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var categoryStore: ActivityCategoryStore
    @ObservedObject var filterStore: ActivityFilterStore
    @State private var showingEditor = false
    @State private var editingCategory: ActivityCategoryDefinition?
    @State private var creatingCategory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Activity Categories")
                        .font(.system(size: 18, weight: .bold))
                    Text("The first matching App, Website, or Item rule owns the color in Activities.")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                Button {
                    creatingCategory = true
                    editingCategory = nil
                    showingEditor = true
                } label: {
                    Label("New Category", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("activities.categories.new")
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(categoryStore.activeCategories) { category in
                        categoryRow(category)
                    }
                }
            }

            HStack {
                Text(categoryStore.statusMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(MetridayTheme.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 520, height: 470)
        .sheet(isPresented: $showingEditor) {
            ActivityCategoryEditorSheet(category: creatingCategory ? nil : editingCategory) { definition in
                if creatingCategory {
                    _ = categoryStore.createCategory(
                        name: definition.name,
                        role: definition.role,
                        color: definition.color,
                        matchMode: definition.matchMode,
                        rules: definition.rules
                    )
                } else {
                    categoryStore.save(definition)
                }
                showingEditor = false
            }
        }
    }

    private func categoryRow(_ category: ActivityCategoryDefinition) -> some View {
        let detail = category.isSystem
            ? "Built-in fallback · \(category.role.label)"
            : "\(category.rules.count) rule\(category.rules.count == 1 ? "" : "s") · \(category.role.label)"
        let priorityIndex = categoryStore.customCategories.firstIndex(where: { $0.id == category.id })
        let customCount = categoryStore.customCategories.count
        return HStack(spacing: 10) {
            Circle()
                .fill(categoryColor(for: category))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(MetridayTheme.secondary)
            }
            Spacer()
            if category.isSystem {
                Text("Built-in")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MetridayTheme.secondary)
            } else {
                HStack(spacing: 2) {
                    Button {
                        _ = categoryStore.move(category, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.borderless)
                    .disabled(priorityIndex == nil || priorityIndex == 0)
                    .help("Move category priority up")
                    Button {
                        _ = categoryStore.move(category, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .disabled(priorityIndex == nil || priorityIndex == customCount - 1)
                    .help("Move category priority down")
                }
                Button("Edit") {
                    creatingCategory = false
                    editingCategory = category
                    showingEditor = true
                }
                .buttonStyle(.borderless)
                Button(role: .destructive) {
                    categoryStore.archive(category)
                } label: {
                    Image(systemName: "archivebox")
                }
                .buttonStyle(.borderless)
                .help("Archive category")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MetridayTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
}

private struct ActivityCategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (ActivityCategoryDefinition) -> Void
    @State private var draft: ActivityCategoryDefinition
    @State private var newField: ActivityFilterField = .application
    @State private var newComparison: ProjectRuleComparison = .contains
    @State private var newPattern = ""
    @State private var newCaseSensitive = false

    init(
        category: ActivityCategoryDefinition?,
        onSave: @escaping (ActivityCategoryDefinition) -> Void
    ) {
        self.onSave = onSave
        _draft = State(initialValue: category ?? ActivityCategoryDefinition(name: "New Category", role: .focused, color: .blue))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Category Editor")
                .font(.system(size: 18, weight: .bold))

            TextField("Category name", text: $draft.name)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Picker("Role", selection: $draft.role) {
                    ForEach(ActivityCategoryRole.allCases) { role in
                        Text(role.label).tag(role)
                    }
                }
                Picker("Color", selection: $draft.color) {
                    ForEach(ProjectColor.allCases, id: \.self) { color in
                        Text(color.rawValue.capitalized).tag(color)
                    }
                }
                .disabled(draft.role == .focused || draft.role == .distracting)
            }
            .onChange(of: draft.role) { _, role in
                switch role {
                case .focused:
                    draft.color = .blue
                case .distracting:
                    draft.color = .red
                case .other, .idle:
                    break
                }
            }

            Picker("Match", selection: $draft.matchMode) {
                ForEach(ActivityFilterMatchMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Text("Rules are evaluated before the built-in Focused, Distracting, Other, and Idle fallbacks. Use Application, Domain, URL, Window title, or Keyword to classify a source.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(draft.rules.enumerated()), id: \.element.id) { index, rule in
                        if draft.rules.indices.contains(index) {
                            let binding = Binding<ActivityFilterRule>(
                                get: { draft.rules[index] },
                                set: { draft.rules[index] = $0 }
                            )
                            HStack(spacing: 7) {
                                Picker("Field", selection: binding.field) {
                                    ForEach(ActivityFilterField.allCases) { field in
                                        Text(field.label).tag(field)
                                    }
                                }
                                Picker("Relation", selection: binding.comparison) {
                                    ForEach(ProjectRuleComparison.allCases) { comparison in
                                        Text(comparison.label).tag(comparison)
                                    }
                                }
                                TextField("Value", text: binding.pattern)
                                    .textFieldStyle(.roundedBorder)
                                Button(role: .destructive) {
                                    draft.rules.remove(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 90, maxHeight: 140)

            HStack(spacing: 7) {
                Picker("Field", selection: $newField) {
                    ForEach(ActivityFilterField.allCases) { field in
                        Text(field.label).tag(field)
                    }
                }
                Picker("Relation", selection: $newComparison) {
                    ForEach(ProjectRuleComparison.allCases) { comparison in
                        Text(comparison.label).tag(comparison)
                    }
                }
                TextField("Value", text: $newPattern)
                    .textFieldStyle(.roundedBorder)
                Button {
                    addRule()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(newPattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save Category") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || draft.rules.isEmpty
                )
            }
        }
        .padding(24)
        .frame(width: 650, height: 520)
    }

    private func addRule() {
        let pattern = newPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return }
        draft.rules.append(
            ActivityFilterRule(
                field: newField,
                pattern: pattern,
                isCaseSensitive: newCaseSensitive,
                comparison: newComparison
            )
        )
        newPattern = ""
        newCaseSensitive = false
    }
}

private enum ActivityDisplayMode: String, CaseIterable, Identifiable {
    case unified
    case byCategory
    case chronological

    var id: Self { self }

    var label: String {
        switch self {
        case .unified:
            return "Unified"
        case .chronological:
            return "Chronological"
        case .byCategory:
            return "By Category"
        }
    }
}

private struct ActivityGroup: Identifiable {
    var id: String { name }
    let name: String
    let segments: [ActivitySegment]
    let seconds: Int
}

private struct CategoryRow: Identifiable {
    var id: String { name }
    let name: String
    let seconds: Int
    let category: ActivityCategoryDefinition
    let segments: [ActivitySegment]
}

private struct CategoryAggregation {
    private struct Bucket {
        let category: ActivityCategoryDefinition
        var seconds: Int
    }

    private(set) var seconds = 0
    private(set) var segments: [ActivitySegment] = []
    private var buckets: [UUID: Bucket] = [:]

    mutating func add(seconds: Int, category: ActivityCategoryDefinition, segment: ActivitySegment) {
        self.seconds += seconds
        segments.append(segment)
        if var bucket = buckets[category.id] {
            bucket.seconds += seconds
            buckets[category.id] = bucket
        } else {
            buckets[category.id] = Bucket(category: category, seconds: seconds)
        }
    }

    var primaryCategory: ActivityCategoryDefinition? {
        buckets.values.max { first, second in first.seconds < second.seconds }?.category
    }
}

private struct CalendarEventsPanel: View {
    @ObservedObject var store: CalendarEventStore
    let selectedDate: Date
    let onRecord: (CalendarEventItem) -> Void

    @State private var editingEvent: CalendarEventItem?
    @State private var eventPendingDeletion: CalendarEventItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Calendar Events", systemImage: "calendar.badge.clock")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                if store.isAuthorized {
                    Button {
                        store.loadEvents(for: selectedDate)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh calendar events")
                } else {
                    Button("Connect Calendar") {
                        store.requestAccess()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("calendar.request-access")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, 9)

            Divider()

            if !store.isAuthorized {
                HStack(spacing: 9) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(MetridayTheme.secondary)
                    Text("Connect a calendar to show meetings on the timeline and record offline time with one click.")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                        .lineSpacing(2)
                }
                .padding(15)
            } else if store.events.isEmpty {
                Text(store.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(MetridayTheme.secondary)
                    .padding(15)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.events) { event in
                        HStack(spacing: 10) {
                            Button {
                                onRecord(event)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "calendar")
                                        .foregroundStyle(MetridayTheme.accent)
                                        .frame(width: 23)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(event.title)
                                            .font(.system(size: 12, weight: .semibold))
                                            .lineLimit(1)
                                        Text("\(formatTime(event.start))–\(formatTime(event.end)) · \(event.calendarTitle)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(MetridayTheme.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .accessibilityLabel("Record calendar event \(event.title)")
                            Button("Record") {
                                onRecord(event)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("calendar.record.\(event.id)")
                            Button {
                                editingEvent = event
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!event.isEditable)
                            .help(event.isEditable ? "Edit event" : "This calendar is read-only")
                            .accessibilityIdentifier("calendar.edit.\(event.id)")
                            Button {
                                eventPendingDeletion = event
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(event.isEditable ? MetridayTheme.danger : MetridayTheme.secondary)
                            }
                            .buttonStyle(.borderless)
                            .disabled(!event.isEditable)
                            .help(event.isEditable ? "Delete event" : "This calendar is read-only")
                            .accessibilityIdentifier("calendar.delete.\(event.id)")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        if event.id != store.events.last?.id {
                            Divider().padding(.leading, 49)
                        }
                    }
                }
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MetridayTheme.line, lineWidth: 1)
        )
        .onAppear {
            store.loadEvents(for: selectedDate)
        }
        .onChange(of: selectedDate) { _, newDate in
            store.loadEvents(for: newDate)
        }
        .sheet(item: $editingEvent) { event in
            CalendarEventEditorSheet(event: event) { updated in
                if store.updateEvent(
                    id: event.id,
                    title: updated.title,
                    start: updated.start,
                    end: updated.end,
                    notes: updated.notes
                ) {
                    editingEvent = nil
                }
            }
        }
        .alert(
            "Delete Calendar Event?",
            isPresented: Binding(
                get: { eventPendingDeletion != nil },
                set: { if !$0 { eventPendingDeletion = nil } }
            ),
            presenting: eventPendingDeletion
        ) { event in
            Button("Cancel", role: .cancel) { eventPendingDeletion = nil }
            Button("Delete", role: .destructive) {
                _ = store.deleteEvent(id: event.id)
                eventPendingDeletion = nil
            }
        } message: { event in
            Text("This removes \"\(event.title)\" from \(event.calendarTitle).")
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct RemindersPanel: View {
    @ObservedObject var store: ReminderStore
    let selectedDate: Date
    let onRecord: (ReminderItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Completed Reminders", systemImage: "checklist")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                if store.isAuthorized {
                    Button {
                        store.loadCompleted(for: selectedDate)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh completed reminders")
                } else {
                    Button("Connect Reminders") {
                        store.requestAccess()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("reminders.request-access")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, 9)

            Divider()

            if !store.isAuthorized {
                HStack(spacing: 9) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(MetridayTheme.secondary)
                    Text("Connect Reminders to show completed tasks and use their titles as time-entry suggestions.")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                        .lineSpacing(2)
                }
                .padding(15)
            } else if store.reminders.isEmpty {
                Text(store.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(MetridayTheme.secondary)
                    .padding(15)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.reminders) { reminder in
                        HStack(spacing: 10) {
                            Button {
                                onRecord(reminder)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: reminder.isRecurring ? "repeat.circle" : "checkmark.circle")
                                        .foregroundStyle(MetridayTheme.success)
                                        .frame(width: 23)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(reminder.title)
                                            .font(.system(size: 12, weight: .semibold))
                                            .lineLimit(1)
                                        Text("\(formatTime(reminder.completedAt)) · \(reminder.listTitle)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(MetridayTheme.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .accessibilityLabel("Record completed reminder \(reminder.title)")
                            Button("Record") {
                                onRecord(reminder)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("reminder.record.\(reminder.id)")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        if reminder.id != store.reminders.last?.id {
                            Divider().padding(.leading, 49)
                        }
                    }
                }
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MetridayTheme.line, lineWidth: 1)
        )
        .onAppear {
            store.loadCompleted(for: selectedDate)
        }
        .onChange(of: selectedDate) { _, newDate in
            store.loadCompleted(for: newDate)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct PhoneCallsPanel: View {
    @ObservedObject var store: PhoneCallStore
    let selectedDate: Date
    let onRecord: (PhoneCallItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Phone Calls", systemImage: "phone.arrow.up.right")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                if store.databaseAvailable {
                    Button {
                        store.loadCalls(for: selectedDate)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh call history")
                } else {
                    Button("Connect Phone Calls") {
                        store.openAccessSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("phone-calls.request-access")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, 9)

            Divider()

            if !store.databaseAvailable {
                HStack(spacing: 9) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(MetridayTheme.secondary)
                    Text("Grant Full Disk Access to read the local Mac call history and record phone or FaceTime calls.")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                        .lineSpacing(2)
                }
                .padding(15)
            } else if store.calls.isEmpty {
                Text(store.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(MetridayTheme.secondary)
                    .padding(15)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.calls) { call in
                        HStack(spacing: 10) {
                            Button {
                                onRecord(call)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "phone.fill")
                                        .foregroundStyle(MetridayTheme.accent)
                                        .frame(width: 23)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(call.title)
                                            .font(.system(size: 12, weight: .semibold))
                                            .lineLimit(1)
                                        Text(rangeLabel(for: call))
                                            .font(.system(size: 10))
                                            .foregroundStyle(MetridayTheme.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .accessibilityLabel("Record phone call \(call.title)")
                            Button("Record") {
                                onRecord(call)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("phone-call.record.\(call.id)")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .contextMenu {
                            if !call.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button {
                                    store.setAddressHidden(call.address, hidden: true)
                                } label: {
                                    Label("Hide calls from this number", systemImage: "eye.slash")
                                }
                            }
                        }
                        if call.id != store.calls.last?.id {
                            Divider().padding(.leading, 49)
                        }
                    }
                }
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MetridayTheme.line, lineWidth: 1)
        )
        .onAppear {
            store.loadCalls(for: selectedDate)
        }
        .onChange(of: selectedDate) { _, newDate in
            store.loadCalls(for: newDate)
        }
    }

    private func rangeLabel(for call: PhoneCallItem) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        if call.isPointInTime {
            return "\(formatter.string(from: call.start)) · Point-in-time call"
        }
        return "\(formatter.string(from: call.start))–\(formatter.string(from: call.end))"
    }
}

private struct ScreenTimePanel: View {
    @ObservedObject var store: ScreenTimeStore
    let selectedDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Screen Time", systemImage: "iphone")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                if store.databaseAvailable {
                    Button {
                        store.load(for: selectedDate)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh Screen Time")
                } else {
                    Button("Connect Screen Time") {
                        store.openAccessSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("screen-time.request-access")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 13)
            .padding(.bottom, 9)

            Divider()

            if !store.databaseAvailable && store.segments.isEmpty {
                HStack(spacing: 9) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(MetridayTheme.secondary)
                    Text("Grant Full Disk Access to import read-only iPhone, iPad, and Mac Screen Time usage. Imported records are archived locally.")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                        .lineSpacing(2)
                }
                .padding(15)
            } else {
                HStack(spacing: 9) {
                    Image(systemName: "iphone")
                        .foregroundStyle(MetridayTheme.accent)
                    Text(store.statusMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                    Spacer()
                    Text("\(store.segments.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MetridayTheme.graphite)
                }
                .padding(15)
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MetridayTheme.line, lineWidth: 1)
        )
        .onAppear {
            store.load(for: selectedDate)
        }
        .onChange(of: selectedDate) { _, newDate in
            store.load(for: newDate)
        }
    }
}

private struct CalendarEventEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: CalendarEventItem
    let onSave: (CalendarEventItem) -> Void

    @State private var title: String
    @State private var notes: String
    @State private var start: Date
    @State private var end: Date

    init(event: CalendarEventItem, onSave: @escaping (CalendarEventItem) -> Void) {
        self.event = event
        self.onSave = onSave
        _title = State(initialValue: event.title)
        _notes = State(initialValue: event.notes)
        _start = State(initialValue: event.start)
        _end = State(initialValue: event.end)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Edit Calendar Event")
                        .font(.system(size: 18, weight: .bold))
                    Text(event.calendarTitle)
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
            }

            TextField("Event title", text: $title)
                .textFieldStyle(.roundedBorder)
            DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
            DatePicker("End", selection: $end, displayedComponents: [.date, .hourAndMinute])
            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4, reservesSpace: true)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(
                        CalendarEventItem(
                            id: event.id,
                            title: title,
                            calendarTitle: event.calendarTitle,
                            location: event.location,
                            notes: notes,
                            urlString: event.urlString,
                            start: start,
                            end: end,
                            calendarIdentifier: event.calendarIdentifier,
                            isEditable: event.isEditable
                        )
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || end <= start
                        || !event.isEditable
                )
            }
        }
        .padding(24)
        .frame(width: 430)
    }
}

private struct EntryOMaticSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selectedDate: Date
    let wrapAtMinute: Int
    let segments: [ActivitySegment]
    let sourceDescription: String
    let existingEntries: [TimeEntry]
    let projects: [TrackingProject]
    let initialProjectID: UUID?
    let onCreate: ([EntryOMaticInterval], String, UUID?, String, BillingStatus, Bool) -> Void

    @State private var projectID: UUID?
    @State private var minimumDurationMinutes = 5
    @State private var maximumGapSeconds = 60
    @State private var overwriteExisting = false
    @State private var title: String
    @State private var notes = ""
    @State private var billingStatus: BillingStatus

    init(
        selectedDate: Date,
        segments: [ActivitySegment],
        sourceDescription: String,
        existingEntries: [TimeEntry],
        wrapAtMinute: Int = 0,
        projects: [TrackingProject],
        initialProjectID: UUID?,
        onCreate: @escaping ([EntryOMaticInterval], String, UUID?, String, BillingStatus, Bool) -> Void
    ) {
        self.selectedDate = selectedDate
        self.wrapAtMinute = wrapAtMinute
        self.segments = segments
        self.sourceDescription = sourceDescription
        self.existingEntries = existingEntries
        self.projects = projects
        self.initialProjectID = initialProjectID
        self.onCreate = onCreate
        _projectID = State(initialValue: initialProjectID)
        _title = State(initialValue: initialProjectID
            .flatMap { id in projects.first(where: { $0.id == id })?.name }
            ?? "Work session")
        _billingStatus = State(initialValue: resolvedProjectBillingStatus(for: initialProjectID, in: projects))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Create Time Entries")
                .font(.system(size: 18, weight: .bold))
            Text("Turn \(sourceDescription) into reviewable time entries for \(dateLabel).")
                .font(.system(size: 11))
                .foregroundStyle(MetridayTheme.secondary)

            Picker("Project", selection: $projectID) {
                Text("All visible activity").tag(nil as UUID?)
                ForEach(projects) { project in
                    Text(project.name).tag(project.id as UUID?)
                }
            }

            HStack(spacing: 12) {
                Picker("Minimum duration", selection: $minimumDurationMinutes) {
                    ForEach([1, 5, 10, 15], id: \.self) { minutes in
                        Text("Min \(minutes)m").tag(minutes)
                    }
                }
                .labelsHidden()

                Picker("Maximum gap", selection: $maximumGapSeconds) {
                    ForEach([0, 5, 30, 60, 300], id: \.self) { seconds in
                        Text(seconds == 0 ? "No gap" : "Gap ≤ \(seconds)s").tag(seconds)
                    }
                }
                .labelsHidden()
            }

            Toggle("Replace overlapping time entries", isOn: $overwriteExisting)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
            Text("Without replacement, already recorded time is subtracted from the generated intervals. Replacement preserves time outside the generated ranges.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)

            TextField("Time entry title", text: $title)
                .textFieldStyle(.roundedBorder)

            Picker("Billing Status", selection: $billingStatus) {
                ForEach(BillingStatus.allCases) { status in
                    Text(status.label).tag(status)
                }
            }

            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3, reservesSpace: true)

            VStack(alignment: .leading, spacing: 5) {
                Label("Preview", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                if previewIntervals.isEmpty {
                    Text("No intervals meet the current minimum duration and coverage settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                } else {
                    Text("\(previewIntervals.count) entries · \(durationLabel)")
                        .font(.system(size: 13, weight: .semibold))
                    Text(previewIntervals.map { interval in
                        "\(TimeFormat.string(interval.startSecond / 60))–\(TimeFormat.string(Int(ceil(Double(interval.endSecond) / 60.0))))"
                    }.joined(separator: " · "))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MetridayTheme.secondary)
                    .lineLimit(2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MetridayTheme.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create \(previewIntervals.count) Time Entries") {
                    onCreate(previewIntervals, title.trimmingCharacters(in: .whitespacesAndNewlines), projectID, notes, billingStatus, overwriteExisting)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(previewIntervals.isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500)
        .onChange(of: projectID) { _, newProjectID in
            billingStatus = resolvedProjectBillingStatus(for: newProjectID, in: projects)
        }
    }

    private var previewIntervals: [EntryOMaticInterval] {
        let scopedSegments = projectID.map { id in
            segments.filter { $0.projectID == id }
        } ?? segments
        return EntryOMaticGenerator.intervals(
            from: scopedSegments,
            dayStart: TrackingDay.startDate(for: selectedDate, wrapAtMinute: wrapAtMinute),
            existingEntries: existingEntries,
            minimumDurationSeconds: minimumDurationMinutes * 60,
            maximumGapSeconds: maximumGapSeconds,
            overwriteExisting: overwriteExisting
        )
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: selectedDate)
    }

    private var durationLabel: String {
        let seconds = previewIntervals.reduce(0) { $0 + $1.durationSeconds }
        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(remainder)m" : "\(minutes)m"
    }
}

private struct TimerStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    let projects: [TrackingProject]
    let recentEntries: [TimeEntry]
    let recentCalendarEvents: [CalendarEventItem]
    let suggestedProjectID: ((CalendarEventItem) -> UUID?)?
    let onStart: (String, UUID?, String, BillingStatus, Int?) -> Void

    @State private var title: String
    @State private var projectID: UUID?
    @State private var notes = ""
    @State private var estimatedDurationMinutes: Int?
    @State private var billingStatus: BillingStatus

    init(
        projects: [TrackingProject],
        initialProjectID: UUID? = nil,
        recentEntries: [TimeEntry] = [],
        recentCalendarEvents: [CalendarEventItem] = [],
        suggestedProjectID: ((CalendarEventItem) -> UUID?)? = nil,
        onStart: @escaping (String, UUID?, String, BillingStatus, Int?) -> Void
    ) {
        self.projects = projects
        self.recentEntries = recentEntries
        self.recentCalendarEvents = recentCalendarEvents
        self.suggestedProjectID = suggestedProjectID
        self.onStart = onStart
        let resolvedProjectID = initialProjectID ?? projects.first?.id
        _projectID = State(initialValue: resolvedProjectID)
        _title = State(initialValue: resolvedProjectID
            .flatMap { id in projects.first(where: { $0.id == id })?.name }
            ?? "Focused work")
        _estimatedDurationMinutes = State(initialValue: nil)
        _billingStatus = State(initialValue: resolvedProjectBillingStatus(for: resolvedProjectID, in: projects))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Start Timer")
                .font(.system(size: 18, weight: .bold))
            Text("The timer will capture activity until you stop it.")
                .font(.system(size: 11))
                .foregroundStyle(MetridayTheme.secondary)

            TimeEntryTitleField(
                title: $title,
                billingStatus: $billingStatus,
                placeholder: "What are you working on?",
                entries: recentEntries,
                projects: projects
            )

            if !recentEntries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent timers")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MetridayTheme.secondary)
                    ForEach(recentEntries) { entry in
                        Button {
                            title = entry.title
                            projectID = entry.projectID
                            notes = entry.notes
                            billingStatus = entry.billingStatus
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                        .lineLimit(1)
                                    Text(projectName(for: entry.projectID))
                                        .font(.system(size: 10))
                                        .foregroundStyle(MetridayTheme.secondary)
                                }
                                Spacer()
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(MetridayTheme.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !recentCalendarEvents.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent calendar events")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MetridayTheme.secondary)
                    ForEach(Array(recentCalendarEvents.prefix(5))) { event in
                        Button {
                            title = event.title
                            if let suggested = suggestedProjectID?(event) {
                                projectID = suggested
                            }
                            notes = [event.calendarTitle, event.location, event.notes]
                                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                                .joined(separator: " · ")
                            billingStatus = resolvedProjectBillingStatus(for: projectID, in: projects)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "calendar.badge.clock")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .lineLimit(1)
                                    Text("\(formatCalendarTime(event.start)) · \(event.calendarTitle)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(MetridayTheme.secondary)
                                }
                                Spacer()
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(MetridayTheme.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

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

            Picker("Estimated duration", selection: $estimatedDurationMinutes) {
                Text("No estimate").tag(nil as Int?)
                ForEach([15, 30, 45, 60, 90, 120, 180, 240], id: \.self) { minutes in
                    Text(minutes >= 60 ? "\(minutes / 60)h\(minutes % 60 == 0 ? "" : " \(minutes % 60)m")" : "\(minutes)m")
                        .tag(minutes as Int?)
                }
            }

            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3, reservesSpace: true)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Start Timer") {
                    onStart(
                        title.trimmingCharacters(in: .whitespacesAndNewlines),
                        projectID,
                        notes,
                        billingStatus,
                        estimatedDurationMinutes.map { $0 * 60 }
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 430)
        .onChange(of: projectID) { _, newProjectID in
            billingStatus = resolvedProjectBillingStatus(for: newProjectID, in: projects)
        }
    }

    private func projectName(for id: UUID?) -> String {
        projects.first(where: { $0.id == id })?.name ?? "Unassigned"
    }

    private func formatCalendarTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private struct RunningTimerStatus: View {
    @ObservedObject var store: TimeEntryStore
    let title: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 7) {
                Label(
                    "\(title) · \(formatMinutes(store.runningDurationSeconds))",
                    systemImage: "timer"
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MetridayTheme.accent)

                if let remaining = store.runningTimerRemainingSeconds {
                    Text(remaining >= 0 ? "\(formatMinutes(remaining)) left" : "Over by \(formatMinutes(-remaining))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(remaining >= 0 ? MetridayTheme.secondary : MetridayTheme.danger)
                }

                Menu {
                    Section("Adjust start") {
                        Button("15 minutes earlier") { store.adjustRunningTimerStart(by: -15 * 60) }
                        Button("5 minutes earlier") { store.adjustRunningTimerStart(by: -5 * 60) }
                        Button("1 minute earlier") { store.adjustRunningTimerStart(by: -60) }
                        Button("1 minute later") { store.adjustRunningTimerStart(by: 60) }
                        Button("5 minutes later") { store.adjustRunningTimerStart(by: 5 * 60) }
                        Button("15 minutes later") { store.adjustRunningTimerStart(by: 15 * 60) }
                        Button("Align to previous entry") {
                            _ = store.moveRunningTimerStartToPreviousEntryBoundary()
                        }
                    }
                    Section("Estimate") {
                        Button("Add 15 minutes") { store.adjustRunningTimerEstimate(by: 15 * 60) }
                        Button("Add 30 minutes") { store.adjustRunningTimerEstimate(by: 30 * 60) }
                        Button("Add 1 hour") { store.adjustRunningTimerEstimate(by: 60 * 60) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .help("Adjust timer")
                .accessibilityLabel("Adjust timer")
                .accessibilityIdentifier("activities.timer-adjust")
            }
        }
    }

    private func formatMinutes(_ seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 { return "\(hours)h \(remainder)m" }
        return "\(remainder)m"
    }
}

private struct TimelineHoverDetail {
    let id: String
    let sourceLabel: String
    let sourceColor: Color?
    let title: String
    let timeRange: String
    let duration: String
    let projectName: String
    let projectColor: Color
    let projectQualifier: String?
    let categoryLabel: String?
    let categoryColor: Color?
}

private struct TimelineHoverBanner: View {
    let detail: TimelineHoverDetail

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(detail.timeRange)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(MetridayTheme.graphite)

            detailRow(
                label: detail.sourceLabel,
                color: detail.sourceColor,
                value: detail.title,
                suffix: detail.duration
            )
            if let categoryLabel = detail.categoryLabel {
                detailRow(
                    label: "Category",
                    color: detail.categoryColor,
                    value: categoryLabel,
                    suffix: ""
                )
            }
            detailRow(
                label: "Project",
                color: detail.projectColor,
                value: detail.projectName,
                suffix: detail.projectQualifier ?? ""
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MetridayTheme.graphite.opacity(0.24), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline details")
    }

    private func detailRow(
        label: String,
        color: Color?,
        value: String,
        suffix: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(label):")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MetridayTheme.secondary)
                .frame(width: 55, alignment: .trailing)
            if let color {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
            }
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MetridayTheme.graphite)
                .lineLimit(1)
            if !suffix.isEmpty {
                Text("· \(suffix)")
                    .font(.system(size: 11))
                    .foregroundStyle(MetridayTheme.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct TimelineLegendEntry: Identifiable {
    let id: String
    let label: String
    let color: Color
}

private struct TimelineLegend: View {
    let activityCategories: [TimelineLegendEntry]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(activityCategories) { category in
                item(category.label, color: category.color)
            }
            item("Summary", color: MetridayTheme.accent, outlined: true)
            item("Time entry", color: MetridayTheme.warning, outlined: true)
            item("Calendar", color: MetridayTheme.accent, outlined: true)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(MetridayTheme.secondary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Timeline color legend")
    }

    private func item(
        _ label: String,
        color: Color,
        outlined: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(outlined ? color.opacity(0.14) : color.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(outlined ? color : .clear, lineWidth: 1)
                )
                .frame(width: 12, height: 7)
            Text(label)
        }
    }
}

private struct ActivityTimelinePanel: View {
    let segments: [ActivitySegment]
    let calendarEvents: [CalendarEventItem]
    let timeEntries: [TimeEntry]
    let suggestions: [ActivityTimelineSuggestion]
    let selectedDate: Date
    let deviceName: String
    let wrapAtMinute: Int
    let project: (UUID?) -> TrackingProject?
    let orientation: ActivityTimelineOrientation
    let timelineWindow: ActivityTimelineWindow
    let activityColor: (ActivitySegment) -> Color
    let categoryName: (ActivitySegment) -> String
    @Binding var selectedActivityIDs: Set<UUID>
    let onToggleOrientation: () -> Void
    @Binding var selectionStart: Int?
    @Binding var selectionEnd: Int?
    let onCreateTimeEntry: (Int?, Int?) -> Void
    let onSelectTimelineSuggestion: (ActivityTimelineSuggestion, Bool) -> Void
    let onRecordCalendarEvent: (CalendarEventItem, Bool) -> Void
    let onSelectActivity: (ActivitySegment) -> Void
    let onCreateSelectedTimeEntries: () -> Void
    let onDeleteActivities: ([ActivitySegment]) -> Void
    let onEditTimeEntry: (TimeEntry) -> Void
    let onDeleteTimeEntry: (TimeEntry) -> Void

    @State private var dragAnchorMinute: Int?
    @State private var hoveredSegmentID: UUID?
    @State private var hoveredTimeEntryID: UUID?
    @State private var hoveredCalendarEventID: String?
    @State private var hoveredSuggestionID: String?

    private var timelineGaps: [(start: Int, end: Int)] {
        let ranges = segments.compactMap { segment -> (start: Int, end: Int)? in
            guard let range = timelineWindow.clippedRange(
                startSecond: segment.startSecond,
                endSecond: segment.endSecond
            ) else { return nil }
            return range
        }
        .sorted { left, right in
            left.start == right.start ? left.end < right.end : left.start < right.start
        }
        var merged: [(start: Int, end: Int)] = []
        for range in ranges {
            if let last = merged.last, range.start <= last.end {
                merged[merged.count - 1].end = max(last.end, range.end)
            } else {
                merged.append(range)
            }
        }
        var gaps: [(start: Int, end: Int)] = []
        var cursor = timelineWindow.startMinute
        for range in merged {
            if range.start - cursor >= 15 {
                gaps.append((start: cursor, end: range.start))
            }
            cursor = max(cursor, range.end)
        }
        if timelineWindow.endMinute - cursor >= 15 {
            gaps.append((start: cursor, end: timelineWindow.endMinute))
        }
        return gaps
    }

    @ViewBuilder
    private func activityContextMenu(for segment: ActivitySegment) -> some View {
        Button(selectedActivityIDs.contains(segment.id) ? "Deselect Activity" : "Select Activity") {
            if selectedActivityIDs.contains(segment.id) {
                selectedActivityIDs.remove(segment.id)
            } else {
                selectedActivityIDs.insert(segment.id)
            }
        }
        if !selectedActivityIDs.isEmpty {
            Button("Create Time Entries from Selected Activities") {
                onCreateSelectedTimeEntries()
            }
        }
        Divider()
        Button("Create Time Entry") {
            let start = max(0, segment.startMinute)
            let end = min(1_440, max(start + 15, segment.endMinute))
            onCreateTimeEntry(start, end)
        }
        Button("Delete Activity", role: .destructive) {
            onDeleteActivities([segment])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Timeline")
                        .font(.system(size: 16, weight: .bold))
                    Text(selectionLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                Button(action: onToggleOrientation) {
                    Image(systemName: orientation.icon)
                }
                .buttonStyle(.borderless)
                .help("Toggle timeline orientation (\(orientation.label))")
                .accessibilityLabel("Toggle timeline orientation")
                .accessibilityIdentifier("activities.timeline-orientation")
                if selectionStart != nil, selectionEnd != nil {
                    Button("Create Time Entry") {
                        onCreateTimeEntry(selectionStart, selectionEnd)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button("Clear") {
                        selectionStart = nil
                        selectionEnd = nil
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            TimelineLegend(activityCategories: activityLegend)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            if orientation == .horizontal {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ForEach(timelineWindow.tickMinutes, id: \.self) { minute in
                        Rectangle()
                            .fill(MetridayTheme.line.opacity(minute % 360 == 0 ? 0.9 : 0.45))
                            .frame(width: 1, height: 106)
                            .position(
                                x: timelineWindow.x(for: minute, width: proxy.size.width),
                                y: 53
                            )
                    }

                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        if let second = currentTimeSecond(at: context.date) {
                            let x = timelineWindow.x(
                                for: timelineWindow.absoluteMinute(for: second),
                                width: proxy.size.width
                            )
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(MetridayTheme.accentDeep)
                                    .frame(width: 8, height: 8)
                                Rectangle()
                                    .fill(MetridayTheme.accentDeep)
                                    .frame(width: 2, height: 104)
                            }
                            .frame(width: 8, height: 112, alignment: .top)
                            .position(x: x, y: 56)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        }
                    }

                    ForEach(Array(timelineGaps.enumerated()), id: \.offset) { _, gap in
                        Button {
                            onCreateTimeEntry(gap.start, gap.end)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 28, height: 22)
                                .background(MetridayTheme.canvas)
                                .foregroundStyle(MetridayTheme.secondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(MetridayTheme.line, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .position(
                            x: timelineWindow.x(for: (gap.start + gap.end) / 2, width: proxy.size.width),
                            y: 53
                        )
                        .accessibilityLabel("Create time entry for \(TimeFormat.range(start: gap.start, end: gap.end))")
                        .accessibilityIdentifier("activities.timeline.gap.\(gap.start)-\(gap.end)")
                        .help("Create time entry · \(TimeFormat.range(start: gap.start, end: gap.end))")
                    }

                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        if let range = timelineWindow.clippedRange(startSecond: segment.startSecond, endSecond: segment.endSecond) {
                        let left = timelineWindow.x(for: range.start, width: proxy.size.width)
                        let width = max(3, timelineWindow.x(for: range.end, width: proxy.size.width) - left)
                        let hitWidth = max(12, width)
                        ZStack(alignment: .trailing) {
                            Button {
                                onSelectActivity(segment)
                            } label: {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(activityColor(segment).opacity(0.82))
                                    .frame(width: width, height: 18)
                                    .offset(x: -(hitWidth - width) / 2)
                                    .frame(width: hitWidth, height: 18)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                TapGesture(count: 2)
                                    .onEnded {
                                        let start = max(0, segment.startMinute)
                                        let end = min(1_440, max(start + 15, segment.endMinute))
                                        onCreateTimeEntry(start, end)
                                    }
                            )
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("\(segment.displayTitle) · \(TimeFormat.range(start: segment.startMinute, end: segment.endMinute))")
                            .accessibilityIdentifier("activities.timeline.activity.\(segment.id.uuidString)")
                            if hoveredSegmentID == segment.id {
                                Button {
                                    let start = max(0, segment.startMinute)
                                    let end = min(1_440, max(start + 15, segment.endMinute))
                                    onCreateTimeEntry(start, end)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 17, height: 17)
                                        .background(.black.opacity(0.55))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 2)
                            }
                        }
                        .frame(width: hitWidth, height: 18)
                        .contentShape(Rectangle())
                        .help("\(segment.displayTitle) · \(TimeFormat.range(start: segment.startMinute, end: segment.endMinute))\(segment.resource.isEmpty ? "" : " · \(segment.resource)")")
                        .onHover { isHovered in
                            // Timeline blocks can overlap. Clearing the shared
                            // hover state from every block on exit causes
                            // SwiftUI/AppKit to oscillate between overlapping
                            // hit regions and repeatedly invalidate layout.
                            // Only promote the block currently under the pointer;
                            // the next positive hover replaces it naturally.
                            if isHovered, hoveredSegmentID != segment.id {
                                hoveredSegmentID = segment.id
                                hoveredTimeEntryID = nil
                                hoveredCalendarEventID = nil
                                hoveredSuggestionID = nil
                            }
                        }
                        .contextMenu {
                            activityContextMenu(for: segment)
                        }
                            .position(
                                x: left + width / 2,
                                y: 24 + CGFloat(index % 4) * 22
                            )
                    }
                        }

                    ForEach(calendarEvents) { event in
                        let startSecond = TrackingDay.axisSeconds(
                            for: event.start,
                            logicalDayLabel: selectedDate,
                            wrapAtMinute: wrapAtMinute
                        )
                        let endSecond = max(
                            startSecond + 900,
                            min(
                                86_400,
                                TrackingDay.axisSeconds(
                                    for: event.end,
                                    logicalDayLabel: selectedDate,
                                    wrapAtMinute: wrapAtMinute
                                )
                            )
                        )
                        if let range = timelineWindow.clippedRange(startSecond: startSecond, endSecond: endSecond) {
                        let left = timelineWindow.x(for: range.start, width: proxy.size.width)
                        let width = max(4, timelineWindow.x(for: range.end, width: proxy.size.width) - left)
                        let hitWidth = max(12, width)
                        ZStack {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(MetridayTheme.accent.opacity(0.13))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .strokeBorder(
                                            MetridayTheme.accent,
                                            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                                        )
                                )
                                .frame(width: width, height: 12)
                                .offset(x: -(hitWidth - width) / 2)
                        }
                            .frame(width: hitWidth, height: 12)
                            .position(x: left + width / 2, y: 96)
                            .contentShape(Rectangle())
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("Calendar event · \(event.title)")
                            .accessibilityIdentifier("activities.timeline.calendar.\(event.id)")
                            .onHover { isHovered in
                                if isHovered {
                                    hoveredCalendarEventID = event.id
                                    hoveredSegmentID = nil
                                    hoveredTimeEntryID = nil
                                    hoveredSuggestionID = nil
                                }
                            }
                            .onTapGesture {
                                onRecordCalendarEvent(event, NSEvent.modifierFlags.contains(.option))
                            }
                            .contextMenu {
                                Button("Record Time Entry") {
                                    onRecordCalendarEvent(event, false)
                                }
                            }
                            .help("Click to record offline time · ⌥-click to record immediately")
                    }
                        }

                    ForEach(timeEntries) { entry in
                        if let entryRange = clippedRange(for: entry),
                           let range = timelineWindow.clippedRange(startSecond: entryRange.start, endSecond: entryRange.end) {
                            let left = timelineWindow.x(for: range.start, width: proxy.size.width)
                            let width = max(4, timelineWindow.x(for: range.end, width: proxy.size.width) - left)
                            let hitWidth = max(12, width)
                            ZStack {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(MetridayTheme.warning.opacity(0.22))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .stroke(MetridayTheme.warning, lineWidth: 1)
                                    )
                                    .frame(width: width, height: 12)
                                    .offset(x: -(hitWidth - width) / 2)
                            }
                                .frame(width: hitWidth, height: 12)
                                .position(x: left + width / 2, y: 114)
                                .contentShape(Rectangle())
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel("Recorded time · \(entry.title)")
                                .accessibilityIdentifier("activities.timeline.time-entry.\(entry.id.uuidString)")
                                .onHover { isHovered in
                                    if isHovered {
                                        hoveredTimeEntryID = entry.id
                                        hoveredSegmentID = nil
                                        hoveredCalendarEventID = nil
                                        hoveredSuggestionID = nil
                                    }
                                }
                                .onTapGesture {
                                    onEditTimeEntry(entry)
                                }
                                .contextMenu {
                                    Button("Edit Time Entry") {
                                        onEditTimeEntry(entry)
                                    }
                                    Button("Delete Time Entry", role: .destructive) {
                                        onDeleteTimeEntry(entry)
                                    }
                                }
                                .help("Recorded time · \(entry.title)")
                        }
                    }

                    if let start = selectionStart, let end = selectionEnd {
                        let left = timelineWindow.x(for: start, width: proxy.size.width)
                        let width = max(2, timelineWindow.x(for: end, width: proxy.size.width) - left)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(MetridayTheme.accent.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(MetridayTheme.accent, lineWidth: 1)
                            )
                            .frame(width: width, height: 100)
                            .position(x: left + width / 2, y: 53)
                    }

                    HStack(spacing: 0) {
                        ForEach(timelineWindow.tickMinutes, id: \.self) { minute in
                            Text(timelineWindow.label(for: minute))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(MetridayTheme.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 134)

                    if let detail = hoveredTimelineDetail {
                        TimelineHoverBanner(detail: detail)
                            .padding(.horizontal, 16)
                            .allowsHitTesting(false)
                            .zIndex(10)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            let minute = timelineWindow.minute(at: value.location.x, width: proxy.size.width)
                            if dragAnchorMinute == nil {
                                dragAnchorMinute = minute
                            }
                            guard let anchor = dragAnchorMinute else { return }
                            selectionStart = min(anchor, minute)
                            selectionEnd = max(anchor + 15, minute)
                            selectionEnd = min(timelineWindow.endMinute, selectionEnd ?? timelineWindow.endMinute)
                        }
                        .onEnded { _ in
                            dragAnchorMinute = nil
                        }
                )
                .onHover { isInside in
                    if !isInside {
                        hoveredSegmentID = nil
                        hoveredTimeEntryID = nil
                        hoveredCalendarEventID = nil
                        hoveredSuggestionID = nil
                    }
                }
            }
            .frame(height: 156)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            } else {
                verticalTimeline
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MetridayTheme.line, lineWidth: 1)
        )
    }

    private var verticalTimeline: some View {
        GeometryReader { proxy in
            let labelWidth: CGFloat = 64
            let chartWidth = max(1, proxy.size.width - labelWidth - 16)
            VStack(alignment: .leading, spacing: 5) {
                verticalLane(label: deviceName.uppercased(), chartWidth: chartWidth) {
                    ForEach(Array(timelineGaps.enumerated()), id: \.offset) { _, gap in
                        Button {
                            onCreateTimeEntry(gap.start, gap.end)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 28, height: 18)
                                .background(MetridayTheme.canvas)
                                .foregroundStyle(MetridayTheme.secondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .stroke(MetridayTheme.line, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .offset(x: timelineWindow.x(for: (gap.start + gap.end) / 2, width: chartWidth) - 14)
                        .accessibilityLabel("Create time entry for \(TimeFormat.range(start: gap.start, end: gap.end))")
                        .accessibilityIdentifier("activities.vertical-timeline.gap.\(gap.start)-\(gap.end)")
                        .help("Create time entry · \(TimeFormat.range(start: gap.start, end: gap.end))")
                    }

                    ForEach(segments) { segment in
                        if let range = timelineWindow.clippedRange(startSecond: segment.startSecond, endSecond: segment.endSecond) {
                        let left = timelineWindow.x(for: range.start, width: chartWidth)
                        let width = max(2, timelineWindow.x(for: range.end, width: chartWidth) - left)
                        let hitWidth = max(12, width)
                        ZStack(alignment: .topTrailing) {
                            Button {
                                onSelectActivity(segment)
                            } label: {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(activityColor(segment).opacity(0.72))
                                    .frame(width: width, height: 16)
                                    .frame(width: hitWidth, height: 16, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                TapGesture(count: 2)
                                    .onEnded {
                                        let start = max(0, segment.startMinute)
                                        let end = min(1_440, max(start + 15, segment.endMinute))
                                        onCreateTimeEntry(start, end)
                                    }
                            )
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("\(segment.displayTitle) · \(TimeFormat.range(start: segment.startMinute, end: segment.endMinute))")
                            .accessibilityIdentifier("activities.vertical-timeline.activity.\(segment.id.uuidString)")
                            if hoveredSegmentID == segment.id {
                                Button {
                                    let start = max(0, segment.startMinute)
                                    let end = min(1_440, max(start + 15, segment.endMinute))
                                    onCreateTimeEntry(start, end)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 16, height: 16)
                                        .background(.black.opacity(0.55))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 1)
                            }
                        }
                        .frame(width: hitWidth, height: 16, alignment: .leading)
                        .offset(x: left)
                            .contentShape(Rectangle())
                            .onHover { isHovered in
                                if isHovered, hoveredSegmentID != segment.id {
                                    hoveredSegmentID = segment.id
                                    hoveredTimeEntryID = nil
                                    hoveredCalendarEventID = nil
                                    hoveredSuggestionID = nil
                                }
                            }
                            .contextMenu {
                                activityContextMenu(for: segment)
                            }
                            .help("\(segment.displayTitle) · \(TimeFormat.range(start: segment.startMinute, end: segment.endMinute))")
                    }
                        }
                }

                verticalLane(label: "PROJECT", chartWidth: chartWidth) {
                    ForEach(segments) { segment in
                        if let range = timelineWindow.clippedRange(startSecond: segment.startSecond, endSecond: segment.endSecond) {
                        let left = timelineWindow.x(for: range.start, width: chartWidth)
                        let width = max(2, timelineWindow.x(for: range.end, width: chartWidth) - left)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(color(for: project(segment.projectID)?.color).opacity(0.62))
                            .frame(width: width, height: 16)
                            .offset(x: left)
                            .help("Project: \(project(segment.projectID)?.name ?? "None")")
                    }
                        }
                }

                if !suggestions.isEmpty {
                    verticalLane(label: "SUMMARY", chartWidth: chartWidth) {
                        ForEach(suggestions) { suggestion in
                            if let range = timelineWindow.clippedRange(startSecond: suggestion.startSecond, endSecond: suggestion.endSecond) {
                            let left = timelineWindow.x(for: range.start, width: chartWidth)
                            let width = max(2, timelineWindow.x(for: range.end, width: chartWidth) - left)
                            let hitWidth = max(12, width)
                            ZStack(alignment: .topTrailing) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(MetridayTheme.accent.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .strokeBorder(
                                                MetridayTheme.accent,
                                                style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                                            )
                                    )
                                    .frame(width: width, height: 16)
                                    .offset(x: -(hitWidth - width) / 2)
                                Image(systemName: "sparkles")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(MetridayTheme.accent)
                                    .padding(.trailing, 2)
                            }
                            .frame(width: hitWidth, height: 16, alignment: .leading)
                            .offset(x: left)
                            .contentShape(Rectangle())
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(
                                "Summary suggestion · \(suggestion.title) · \(TimeFormat.range(start: suggestion.startMinute, end: suggestion.endMinute))"
                            )
                            .accessibilityIdentifier("activities.vertical-timeline.summary.\(suggestion.id)")
                            .onHover { isHovered in
                                if isHovered {
                                    hoveredSuggestionID = suggestion.id
                                    hoveredSegmentID = nil
                                    hoveredTimeEntryID = nil
                                    hoveredCalendarEventID = nil
                                }
                            }
                            .onTapGesture {
                                onSelectTimelineSuggestion(
                                    suggestion,
                                    NSEvent.modifierFlags.contains(.option)
                                )
                            }
                            .help(
                                "\(suggestion.title) · \(TimeFormat.range(start: suggestion.startMinute, end: suggestion.endMinute)) · ⌥-click to create immediately"
                            )
                        }
                            }
                    }
                }

                verticalLane(label: "TIME ENTRIES", chartWidth: chartWidth) {
                    ForEach(timeEntries) { entry in
                        if let entryRange = clippedRange(for: entry),
                           let range = timelineWindow.clippedRange(startSecond: entryRange.start, endSecond: entryRange.end) {
                            let left = timelineWindow.x(for: range.start, width: chartWidth)
                        let width = max(2, timelineWindow.x(for: range.end, width: chartWidth) - left)
                        let hitWidth = max(12, width)
                        ZStack {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(MetridayTheme.warning.opacity(0.18))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .stroke(MetridayTheme.warning, lineWidth: 1)
                                    )
                                    .frame(width: width, height: 16)
                                    .offset(x: -(hitWidth - width) / 2)
                            }
                                .frame(width: hitWidth, height: 16, alignment: .leading)
                                .offset(x: left)
                                .contentShape(Rectangle())
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel("Recorded time · \(entry.title)")
                                .accessibilityIdentifier("activities.vertical-timeline.time-entry.\(entry.id.uuidString)")
                                .onTapGesture { onEditTimeEntry(entry) }
                                .contextMenu {
                                    Button("Edit Time Entry") {
                                        onEditTimeEntry(entry)
                                    }
                                    Button("Delete Time Entry", role: .destructive) {
                                        onDeleteTimeEntry(entry)
                                    }
                                }
                                .help("Recorded time · \(entry.title)")
                        }
                    }
                    ForEach(calendarEvents) { event in
                        let start = TrackingDay.axisSeconds(
                            for: event.start,
                            logicalDayLabel: selectedDate,
                            wrapAtMinute: wrapAtMinute
                        )
                        let end = max(
                            start + 900,
                            min(
                                86_400,
                                TrackingDay.axisSeconds(
                                    for: event.end,
                                    logicalDayLabel: selectedDate,
                                    wrapAtMinute: wrapAtMinute
                                )
                            )
                        )
                        if let clipped = timelineWindow.clippedRange(startSecond: start, endSecond: end) {
                        let left = timelineWindow.x(for: clipped.start, width: chartWidth)
                        let width = max(2, timelineWindow.x(for: clipped.end, width: chartWidth) - left)
                        let hitWidth = max(12, width)
                        ZStack {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(MetridayTheme.accent.opacity(0.10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .strokeBorder(
                                            MetridayTheme.accent,
                                            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                                        )
                                )
                                .frame(width: width, height: 16)
                                .offset(x: -(hitWidth - width) / 2)
                        }
                            .frame(width: hitWidth, height: 16, alignment: .leading)
                            .offset(x: left)
                            .contentShape(Rectangle())
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("Calendar event · \(event.title)")
                            .accessibilityIdentifier("activities.vertical-timeline.calendar.\(event.id)")
                            .onTapGesture {
                                onRecordCalendarEvent(event, NSEvent.modifierFlags.contains(.option))
                            }
                            .help("Calendar event · \(event.title)")
                        }
                        }
                    }

                HStack(spacing: 0) {
                    Color.clear.frame(width: labelWidth)
                    ForEach(timelineWindow.tickMinutes, id: \.self) { minute in
                        Text(timelineWindow.label(for: minute))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(MetridayTheme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(width: proxy.size.width - 16, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        let minute = timelineWindow.minute(
                            at: value.location.x - labelWidth - 16,
                            width: chartWidth
                        )
                        if dragAnchorMinute == nil {
                            dragAnchorMinute = minute
                        }
                        guard let anchor = dragAnchorMinute else { return }
                        selectionStart = min(anchor, minute)
                        selectionEnd = min(timelineWindow.endMinute, max(anchor + 15, minute))
                    }
                    .onEnded { _ in
                        dragAnchorMinute = nil
                    }
            )
            .onHover { isInside in
                if !isInside {
                    hoveredSegmentID = nil
                    hoveredTimeEntryID = nil
                    hoveredCalendarEventID = nil
                    hoveredSuggestionID = nil
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Vertical activity timeline")
            .accessibilityIdentifier("activities.vertical-timeline")
            .overlay(alignment: .topLeading) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    if let second = currentTimeSecond(at: context.date) {
                        let x = 16 + labelWidth + 6 + timelineWindow.x(
                            for: timelineWindow.absoluteMinute(for: second),
                            width: chartWidth
                        )
                        VStack(spacing: 0) {
                            Circle()
                                .fill(MetridayTheme.accentDeep)
                                .frame(width: 8, height: 8)
                            Rectangle()
                                .fill(MetridayTheme.accentDeep)
                                .frame(width: 2, height: 60)
                        }
                        .frame(width: 8, height: 68, alignment: .top)
                        .position(x: x, y: 38)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
            }
            .overlay(alignment: .top) {
                if let detail = hoveredTimelineDetail {
                    TimelineHoverBanner(detail: detail)
                        .padding(.horizontal, 16)
                        .allowsHitTesting(false)
                        .zIndex(10)
                }
            }
        }
        .frame(height: suggestions.isEmpty ? 156 : 180)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func verticalLane<Content: View>(
        label: String,
        chartWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(MetridayTheme.secondary)
                .frame(width: 58, alignment: .leading)
            ZStack(alignment: .topLeading) {
                ForEach(timelineWindow.tickMinutes, id: \.self) { minute in
                    Rectangle()
                        .fill(MetridayTheme.line.opacity(minute % 360 == 0 ? 0.9 : 0.4))
                        .frame(width: 1, height: 18)
                        .offset(x: timelineWindow.x(for: minute, width: chartWidth))
                }
                content()
            }
            .frame(width: chartWidth, height: 18, alignment: .topLeading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
        }
    }

    private var selectionLabel: String {
        guard let selectionStart, let selectionEnd else {
            return "Drag across the day to inspect a time range"
        }
        let entries = timeEntries.filter {
            $0.start < endOfSelection && $0.end > startOfSelection
        }.count
        return "Selected \(secondRange(start: selectionStart * 60, end: selectionEnd * 60)) · \(segmentsInSelection) activities · \(entries) entries"
    }

    private func currentTimeSecond(at date: Date) -> Int? {
        let logicalToday = TrackingDay.logicalDayLabel(
            for: date,
            wrapAtMinute: wrapAtMinute
        )
        guard Calendar.current.isDate(selectedDate, inSameDayAs: logicalToday) else { return nil }
        return TrackingDay.axisSeconds(
            for: date,
            logicalDayLabel: selectedDate,
            wrapAtMinute: wrapAtMinute
        )
    }

    private var startOfSelection: Date {
        TrackingDay.date(
            forAxisSeconds: (selectionStart ?? 0) * 60,
            logicalDayLabel: selectedDate,
            wrapAtMinute: wrapAtMinute
        )
    }

    private var endOfSelection: Date {
        TrackingDay.date(
            forAxisSeconds: (selectionEnd ?? 0) * 60,
            logicalDayLabel: selectedDate,
            wrapAtMinute: wrapAtMinute
        )
    }

    private var segmentsInSelection: Int {
        guard let selectionStart, let selectionEnd else { return 0 }
        return segments.filter {
            $0.startSecond < selectionEnd * 60 && $0.endSecond > selectionStart * 60
        }.count
    }

    private var hoveredTimelineDetail: TimelineHoverDetail? {
        if let hoveredSegmentID,
           let segment = segments.first(where: { $0.id == hoveredSegmentID }) {
            let project = project(segment.projectID)
            return TimelineHoverDetail(
                id: "activity-\(segment.id.uuidString)",
                sourceLabel: "App",
                sourceColor: nil,
                title: segment.displayTitle,
                timeRange: secondRange(start: segment.startSecond, end: segment.endSecond),
                duration: durationLabel(segment.durationSeconds),
                projectName: project?.name ?? "None",
                projectColor: color(for: project?.color),
                projectQualifier: project == nil ? "From the app usage" : nil,
                categoryLabel: categoryName(segment),
                categoryColor: activityColor(segment)
            )
        }

        if let hoveredSuggestionID,
           let suggestion = suggestions.first(where: { $0.id == hoveredSuggestionID }) {
            let project = project(suggestion.projectID)
            return TimelineHoverDetail(
                id: "summary-\(suggestion.id)",
                sourceLabel: "Summary",
                sourceColor: MetridayTheme.accent,
                title: suggestion.title,
                timeRange: secondRange(start: suggestion.startSecond, end: suggestion.endSecond),
                duration: durationLabel(suggestion.endSecond - suggestion.startSecond),
                projectName: project?.name ?? "None",
                projectColor: color(for: project?.color),
                projectQualifier: "⌥-click to create immediately",
                categoryLabel: nil,
                categoryColor: nil
            )
        }

        if let hoveredTimeEntryID,
           let entry = timeEntries.first(where: { $0.id == hoveredTimeEntryID }),
           let range = clippedRange(for: entry) {
            let project = project(entry.projectID)
            return TimelineHoverDetail(
                id: "entry-\(entry.id.uuidString)",
                sourceLabel: "Entry",
                sourceColor: MetridayTheme.warning,
                title: entry.title,
                timeRange: secondRange(start: range.start, end: range.end),
                duration: durationLabel(range.end - range.start),
                projectName: project?.name ?? "None",
                projectColor: color(for: project?.color),
                projectQualifier: project == nil ? "Manual time entry" : nil,
                categoryLabel: nil,
                categoryColor: nil
            )
        }

        if let hoveredCalendarEventID,
           let event = calendarEvents.first(where: { $0.id == hoveredCalendarEventID }) {
            let start = TrackingDay.axisSeconds(
                for: event.start,
                logicalDayLabel: selectedDate,
                wrapAtMinute: wrapAtMinute
            )
            let end = max(
                start + 900,
                TrackingDay.axisSeconds(
                    for: event.end,
                    logicalDayLabel: selectedDate,
                    wrapAtMinute: wrapAtMinute
                )
            )
            return TimelineHoverDetail(
                id: "calendar-\(event.id)",
                sourceLabel: "Calendar",
                sourceColor: MetridayTheme.accent,
                title: event.title,
                timeRange: secondRange(start: start, end: end),
                duration: durationLabel(event.durationSeconds),
                projectName: "None",
                projectColor: color(for: nil),
                projectQualifier: "Offline calendar event",
                categoryLabel: nil,
                categoryColor: nil
            )
        }

        return nil
    }

    private var activityLegend: [TimelineLegendEntry] {
        var entries: [TimelineLegendEntry] = []
        var seen = Set<String>()
        for segment in segments {
            let label = categoryName(segment)
            guard seen.insert(label).inserted else { continue }
            entries.append(
                TimelineLegendEntry(
                    id: "\(label)-\(segment.id.uuidString)",
                    label: label,
                    color: activityColor(segment)
                )
            )
        }
        if entries.isEmpty {
            return [
                TimelineLegendEntry(id: "focused", label: "Focused", color: ActivityCategoryKind.focused.color),
                TimelineLegendEntry(id: "distracting", label: "Distracting", color: ActivityCategoryKind.distracting.color),
                TimelineLegendEntry(id: "other-idle", label: "Other / idle", color: ActivityCategoryKind.other.color)
            ]
        }
        return entries
    }

    private func minute(at x: CGFloat, width: CGFloat) -> Int {
        let normalized = min(1, max(0, x / max(1, width)))
        let raw = Int((normalized * 1_440).rounded())
        return min(1_425, max(0, (raw / 15) * 15))
    }

    private func second(of date: Date) -> Int {
        let calendar = Calendar.current
        return calendar.component(.hour, from: date) * 3_600
            + calendar.component(.minute, from: date) * 60
            + calendar.component(.second, from: date)
    }

    private func secondRange(start: Int, end: Int) -> String {
        "\(clock(start))–\(clock(end))"
    }

    private func clock(_ second: Int) -> String {
        let clamped = max(0, min(86_400, second))
        if clamped == 86_400 { return "24:00:00" }
        let wallSecond = (wrapAtMinute * 60 + clamped) % 86_400
        return String(
            format: "%02d:%02d:%02d",
            wallSecond / 3_600,
            (wallSecond % 3_600) / 60,
            wallSecond % 60
        )
    }

    private func durationLabel(_ seconds: Int) -> String {
        let total = max(1, seconds)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remainingSeconds = total % 60
        if hours > 0 {
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return remainingSeconds == 0 ? "\(minutes)m" : "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }

    private func clippedRange(for entry: TimeEntry) -> (start: Int, end: Int)? {
        let dayRange = TrackingDay.range(for: selectedDate, wrapAtMinute: wrapAtMinute)
        let dayStart = dayRange.start
        let dayEnd = dayRange.end
        let start = max(entry.start, dayStart)
        let end = min(entry.end, dayEnd)
        guard end > start else { return nil }
        let startSecond = TrackingDay.axisSeconds(
            for: start,
            logicalDayLabel: selectedDate,
            wrapAtMinute: wrapAtMinute
        )
        let endSecond = end >= dayEnd
            ? 86_400
            : max(
                startSecond + 900,
                min(
                    86_400,
                    TrackingDay.axisSeconds(
                        for: end,
                        logicalDayLabel: selectedDate,
                        wrapAtMinute: wrapAtMinute
                    )
                )
            )
        guard endSecond > startSecond else { return nil }
        return (startSecond, endSecond)
    }

    private func color(for relevance: ActivityRelevance) -> Color {
        ActivityCategoryKind(relevance: relevance).color
    }

    private func color(for projectColor: ProjectColor?) -> Color {
        guard let projectColor else { return MetridayTheme.secondary }
        switch projectColor {
        case .blue:
            return MetridayTheme.accent
        case .green:
            return MetridayTheme.success
        case .orange:
            return MetridayTheme.warning
        case .purple:
            return .purple
        case .red:
            return MetridayTheme.danger
        case .graphite:
            return MetridayTheme.graphite
        }
    }
}

private struct ProjectEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let project: TrackingProject
    let projects: [TrackingProject]
    @ObservedObject var teamStore: TeamStore
    let onSave: (TrackingProject) -> Void

    @State private var name: String
    @State private var parentID: UUID?
    @State private var teamID: UUID?
    @State private var color: ProjectColor
    @State private var productivity: Double
    @State private var notes: String
    @State private var defaultBillingStatus: BillingStatus
    @State private var inheritsBillingStatus: Bool
    @State private var billingRate: Double
    @State private var currency: String

    init(
        project: TrackingProject,
        projects: [TrackingProject],
        teamStore: TeamStore,
        onSave: @escaping (TrackingProject) -> Void
    ) {
        self.project = project
        self.projects = projects
        self.teamStore = teamStore
        self.onSave = onSave
        _name = State(initialValue: project.name)
        _parentID = State(initialValue: project.parentID)
        _teamID = State(initialValue: project.teamID)
        _color = State(initialValue: project.color)
        _productivity = State(initialValue: Double(project.productivity))
        _notes = State(initialValue: project.notes)
        _defaultBillingStatus = State(initialValue: project.defaultBillingStatus.explicitStatus ?? .billable)
        _inheritsBillingStatus = State(initialValue: project.defaultBillingStatus == .automatic)
        _billingRate = State(initialValue: project.billingRate)
        _currency = State(initialValue: project.currency)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Project")
                .font(.system(size: 18, weight: .bold))

            TextField("Project name", text: $name)
                .textFieldStyle(.roundedBorder)

            Picker("Parent project", selection: $parentID) {
                Text("Top level").tag(nil as UUID?)
                ForEach(projects.filter { $0.id != project.id }) { parent in
                    Text(parent.name).tag(parent.id as UUID?)
                }
            }

            if !teamStore.activeTeams.isEmpty {
                Picker("Team", selection: $teamID) {
                    Text("Personal project").tag(nil as UUID?)
                    ForEach(teamStore.activeTeams) { team in
                        Text(team.name).tag(team.id as UUID?)
                    }
                }
            }

            Picker("Color", selection: $color) {
                ForEach(ProjectColor.allCases, id: \.self) { value in
                    Text(value.rawValue.capitalized).tag(value)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Productivity")
                    Spacer()
                    Text("\(Int(productivity))")
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Slider(value: $productivity, in: -100...100, step: 1)
            }

            Toggle("Automatic (inherit from parent)", isOn: $inheritsBillingStatus)
                .toggleStyle(.checkbox)

            Picker("Default billing status", selection: $defaultBillingStatus) {
                ForEach(BillingStatus.allCases.filter { $0 != .undetermined }) { status in
                    Text(status.label).tag(status)
                }
            }
            .disabled(inheritsBillingStatus)

            HStack(spacing: 10) {
                TextField("Hourly billing rate", value: $billingRate, format: .number)
                    .textFieldStyle(.roundedBorder)
                TextField("Currency", text: $currency)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 82)
            }
            Text("Used for billable report totals; set to 0 to hide project revenue.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)

            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3, reservesSpace: true)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    var updated = project
                    updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.parentID = parentID
                    updated.teamID = teamID
                    updated.color = color
                    updated.productivity = Int(productivity.rounded())
                    updated.notes = notes
                    updated.defaultBillingStatus = inheritsBillingStatus
                        ? .automatic
                        : ProjectBillingStatus(rawValue: defaultBillingStatus.rawValue) ?? .billable
                    updated.billingRate = max(0, billingRate)
                    updated.currency = currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "USD"
                        : currency.uppercased()
                    guard !updated.name.isEmpty else { return }
                    onSave(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

private struct TimeEntryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: TimeEntry
    let projects: [TrackingProject]
    let existingEntries: [TimeEntry]
    let onSave: (TimeEntry, [TimeEntry]) -> Void

    @State private var title: String
    @State private var projectID: UUID?
    @State private var billingStatus: BillingStatus
    @State private var start: Date
    @State private var end: Date
    @State private var notes: String
    @State private var overlappingEntries: [TimeEntry] = []
    @State private var showingOverlapConfirmation = false

    init(
        entry: TimeEntry,
        projects: [TrackingProject],
        existingEntries: [TimeEntry],
        onSave: @escaping (TimeEntry, [TimeEntry]) -> Void
    ) {
        self.entry = entry
        self.projects = projects
        self.existingEntries = existingEntries
        self.onSave = onSave
        _title = State(initialValue: entry.title)
        _projectID = State(initialValue: entry.projectID)
        _billingStatus = State(initialValue: entry.billingStatus)
        _start = State(initialValue: entry.start)
        _end = State(initialValue: entry.end)
        _notes = State(initialValue: entry.notes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Edit Time Entry")
                .font(.system(size: 18, weight: .bold))

            TimeEntryTitleField(
                title: $title,
                billingStatus: $billingStatus,
                placeholder: "What did you work on?",
                entries: existingEntries,
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
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save", action: requestSave)
                .buttonStyle(.borderedProminent)
                .disabled(
                    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || end <= start
                )
            }
        }
        .padding(24)
        .frame(width: 420)
        .alert("Overlapping Time Entry", isPresented: $showingOverlapConfirmation) {
            Button("Cancel", role: .cancel) {
                overlappingEntries = []
            }
            Button("Keep Both") {
                commitSave(replacing: false)
            }
            Button("Replace Existing", role: .destructive) {
                commitSave(replacing: true)
            }
        } message: {
            let noun = overlappingEntries.count == 1 ? "entry" : "entries"
            Text("This range overlaps \(overlappingEntries.count) existing time \(noun). Replace the selected range or keep parallel entries? Time outside the range is preserved.")
        }
    }

    private func requestSave() {
        var updated = entry
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.projectID = projectID
        updated.billingStatus = billingStatus
        updated.start = start
        updated.end = end
        updated.notes = notes
        guard !updated.title.isEmpty, updated.end > updated.start else { return }
        overlappingEntries = existingEntries.filter { existing in
            existing.id != entry.id && existing.start < updated.end && existing.end > updated.start
        }
        if !overlappingEntries.isEmpty {
            showingOverlapConfirmation = true
            return
        }
        onSave(updated, [])
        dismiss()
    }

    private func commitSave(replacing: Bool) {
        var updated = entry
        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.projectID = projectID
        updated.billingStatus = billingStatus
        updated.start = start
        updated.end = end
        updated.notes = notes
        guard !updated.title.isEmpty, updated.end > updated.start else { return }
        onSave(updated, replacing ? overlappingEntries : [])
        overlappingEntries = []
        showingOverlapConfirmation = false
        dismiss()
    }
}

private struct TimeEntryTitleGroupSheet: View {
    @Environment(\.dismiss) private var dismiss

    let entry: TimeEntry
    let occurrences: [TimeEntry]
    @ObservedObject var timeEntryStore: TimeEntryStore

    @State private var title: String

    init(entry: TimeEntry, occurrences: [TimeEntry], timeEntryStore: TimeEntryStore) {
        self.entry = entry
        self.occurrences = occurrences
        self.timeEntryStore = timeEntryStore
        _title = State(initialValue: entry.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Title for All Occurrences")
                .font(.system(size: 18, weight: .bold))

            Text("Update the title for \(occurrences.count) entries named \"\(entry.title)\" on the selected day.")
                .font(.system(size: 12))
                .foregroundStyle(MetridayTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Time entry title", text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func save() {
        let ids = Set(occurrences.map(\.id))
        guard timeEntryStore.renameEntries(ids, to: title) > 0 else { return }
        dismiss()
    }
}

import SwiftUI
import UniformTypeIdentifiers

private enum ActivityDeviceFilter {
    static let all = "All Devices"
    static let local = "This Mac"
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
    @ObservedObject var monitor: AppActivityMonitor
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var filterStore: ActivityFilterStore
    @ObservedObject var preferences: ActivitiesPreferencesStore
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
    @State private var selectedDevice = ActivityDeviceFilter.all
    @State private var timelineSelectionStart: Int?
    @State private var timelineSelectionEnd: Int?
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

                HStack(alignment: .top, spacing: 18) {
                    projectSidebar
                        .frame(width: 236)
                    VStack(alignment: .leading, spacing: 18) {
                        ActivityTimelinePanel(
                            segments: timelineScopedSegments,
                            calendarEvents: calendarStore.events,
                            timeEntries: preferences.includeTimeEntries ? timelineTimeEntries : [],
                            selectedDate: selectedDate,
                            project: { projectStore.project($0) },
                            selectionStart: $timelineSelectionStart,
                            selectionEnd: $timelineSelectionEnd,
                            onCreateTimeEntry: { startMinute, endMinute in
                                prepareNewEntry(startMinute: startMinute, endMinute: endMinute)
                                showingNewEntry = true
                            },
                            onRecordCalendarEvent: { event, immediate in
                                prepareNewEntry(for: event)
                                if immediate {
                                    addNewEntry()
                                } else {
                                    showingNewEntry = true
                                }
                            },
                            onEditTimeEntry: { entry in
                                editingEntry = entry
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
                        timeEntryList
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
                recentCalendarEvents: calendarStore.events
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
                segments: filteredSegments,
                existingEntries: timeEntryStore.entries(overlapping: selectedDate),
                projects: projectStore.activeProjects,
                initialProjectID: selectedProjectID
            ) { intervals, title, projectID, notes, billingStatus, overwriteExisting in
                if overwriteExisting {
                    let generatedRanges = intervals.map { interval in
                        let day = Calendar.current.startOfDay(for: selectedDate)
                        return (
                            start: day.addingTimeInterval(TimeInterval(interval.startSecond)),
                            end: day.addingTimeInterval(TimeInterval(interval.endSecond))
                        )
                    }
                    timeEntryStore.entries(overlapping: selectedDate).filter { existing in
                        generatedRanges.contains { range in
                            existing.start < range.end && existing.end > range.start
                        }
                    }.forEach { timeEntryStore.delete($0) }
                }
                let day = Calendar.current.startOfDay(for: selectedDate)
                for interval in intervals {
                    _ = timeEntryStore.addEntry(
                        title: title,
                        projectID: projectID,
                        notes: notes,
                        start: day.addingTimeInterval(TimeInterval(interval.startSecond)),
                        end: day.addingTimeInterval(TimeInterval(interval.endSecond)),
                        billingStatus: billingStatus
                    )
                }
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
                editingFilter = nil
                showingFilterEditor = false
            }
        }
        .sheet(isPresented: $showingActivitySettings) {
            ActivityDisplaySettingsSheet(preferences: preferences)
        }
        .sheet(item: $editingEntry) { entry in
            TimeEntryEditorSheet(entry: entry, projects: projectStore.activeProjects) { updatedEntry in
                timeEntryStore.update(updatedEntry)
                editingEntry = nil
            }
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
        .onAppear {
            restoreDisplayPreferences()
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
    }

    private func restoreDisplayPreferences() {
        guard !displayPreferencesRestored else { return }
        activityMode = ActivityDisplayMode(rawValue: preferences.activityDisplayMode) ?? .chronological
        groupActivitiesByProject = preferences.groupByProject
        groupActivitiesByDevice = preferences.groupByDevice
        includeIdle = preferences.includeIdle
        selectedDevice = availableDevices.contains(preferences.selectedDevice)
            ? preferences.selectedDevice
            : ActivityDeviceFilter.all
        displayPreferencesRestored = true
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

            filterButton(title: "All Activities", icon: "waveform.path", filter: .all)
            filterButton(title: "Unassigned", icon: "tray", filter: .unassigned)

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

            Divider()
                .padding(.vertical, 8)

            ForEach(projectStore.childProjects(of: nil)) { project in
                projectTree(project, depth: 0)
            }

            projectDropZone

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                Text(projectStore.statusMessage)
                    .lineLimit(2)
            }
            .font(.system(size: 10))
            .foregroundStyle(MetridayTheme.secondary)
            .padding(14)
        }
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
                assignActivity(activity.id, to: projectID)
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
            assignActivity(activity.id, to: projectID)
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
                    Text("\(filteredSegments.count) activities · \(formatMinutes(totalSeconds)) tracked")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(MetridayTheme.secondary)
                        TextField("Search activities", text: $searchText)
                            .textFieldStyle(.plain)
                            .frame(width: 150)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(MetridayTheme.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(MetridayTheme.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Toggle("Show Idle", isOn: $includeIdle)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.system(size: 10))

                    Picker("Device", selection: $selectedDevice) {
                        ForEach(availableDevices, id: \.self) { device in
                            Text(device).tag(device)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 125, alignment: .leading)
                    .accessibilityIdentifier("activities.device-filter")

                    Toggle("Group by project", isOn: groupByProjectBinding)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.system(size: 10))
                        .disabled(activityMode != .chronological)

                    Toggle("Group by device", isOn: groupByDeviceBinding)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .font(.system(size: 10))
                        .disabled(activityMode != .chronological)

                    Picker("Activity view", selection: $activityMode) {
                        ForEach(ActivityDisplayMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .accessibilityIdentifier("activities.view-mode")

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
                    .accessibilityIdentifier("activities.timer")

                    Button {
                        prepareNewEntry()
                        showingNewEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("New Time Entry")
                    .accessibilityLabel("New Time Entry")
                    .accessibilityIdentifier("activities.new-entry")

                    Button {
                        showingEntryOMatic = true
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Create Time Entries")
                    .accessibilityLabel("Create Time Entries")
                    .disabled(filteredSegments.allSatisfy { $0.relevance == .idle })
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

            Divider()

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
            } else if groupActivitiesByDevice {
                groupedActivityListByDevice
            } else if groupActivitiesByProject {
                groupedActivityList
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredSegments) { segment in
                        activityRow(segment)
                        if segment.id != filteredSegments.last?.id {
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
                    Text("\(timeEntriesForSelectedDate.count) manual or timer entries")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                if let runningTimer = timeEntryStore.runningTimer {
                    RunningTimerStatus(
                        store: timeEntryStore,
                        title: runningTimer.title
                    )
                }
            }
            .padding(18)

            Divider()

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
                            .contentShape(Rectangle())
                            .help("Edit time entry")
                            .accessibilityIdentifier("time-entry.\(entry.id.uuidString)")
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

    private var categoryCards: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 210), spacing: 12)],
            alignment: .leading,
            spacing: 12
        ) {
            categoryCard(title: "Websites", icon: "globe", segments: websiteSegments)
            categoryCard(title: "Applications", icon: "rectangle.on.rectangle", segments: applicationSegments)
            categoryCard(title: "Paths", icon: "folder", segments: pathSegments)
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

    private var unifiedActivityList: some View {
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
                        Label(projectGroup.name, systemImage: projectGroup.name == "Unassigned" ? "tray" : "folder")
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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Project \(projectGroup.name) \(projectCollapsed ? "Expand" : "Collapse")"))
                .accessibilityIdentifier("activities.unified.project.\(projectGroup.id)")

                if !projectCollapsed {
                    ForEach(unifiedAppGroups(for: projectGroup)) { appGroup in
                        let groupKey = "\(projectGroup.id)::\(appGroup.id)"
                        let appCollapsed = collapsedUnifiedAppGroups.contains(groupKey)
                        Button {
                            if appCollapsed {
                                collapsedUnifiedAppGroups.remove(groupKey)
                            } else {
                                collapsedUnifiedAppGroups.insert(groupKey)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: appCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .frame(width: 10)
                                Image(systemName: icon(for: appGroup.segments[0]))
                                    .foregroundStyle(color(for: appGroup.segments[0].relevance))
                                    .frame(width: 18)
                                Text(appGroup.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(formatMinutes(appGroup.seconds))
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
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("Application \(appGroup.name) \(appCollapsed ? "Expand" : "Collapse")"))
                        .accessibilityIdentifier("activities.unified.application.\(groupKey)")

                        if !appCollapsed {
                            ForEach(appGroup.segments) { segment in
                                activityRow(segment)
                                if segment.id != appGroup.segments.last?.id {
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

    private func unifiedAppGroups(for projectGroup: ActivityGroup) -> [ActivityGroup] {
        Dictionary(grouping: projectGroup.segments) { segment in
            segment.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Unknown application"
                : segment.appName
        }
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

    private var groupedActivityListByDevice: some View {
        let groups = Dictionary(grouping: filteredSegments) { $0.deviceName }
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

    private func categoryCard(
        title: String,
        icon: String,
        segments: [ActivitySegment],
        rows: [CategoryRow]? = nil
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
                ForEach((rows ?? categoryRows(segments)).prefix(6)) { row in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(row.isDistracted ? MetridayTheme.danger : MetridayTheme.accent)
                            .frame(width: 6, height: 6)
                        Text(row.name)
                            .font(.system(size: 11))
                            .lineLimit(1)
                        Spacer()
                        Text(formatMinutes(row.seconds))
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
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

    private func activityRow(_ segment: ActivitySegment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: segment))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(color(for: segment.relevance))
                .frame(width: 28, height: 28)
                .background(color(for: segment.relevance).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle(for: segment))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(TimeFormat.range(start: segment.startMinute, end: segment.endMinute))
                    if segment.deviceName != ActivityDeviceFilter.local {
                        Text(segment.deviceName)
                    }
                    if preferences.showResourcePaths, !segment.resource.isEmpty {
                        Text(resourceLabel(segment.resource))
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
            }

            Spacer(minLength: 10)

            Text(formatMinutes(segment.durationSeconds))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(MetridayTheme.graphite)
                .frame(width: 52, alignment: .trailing)

            Menu {
                Button("Unassigned") {
                    assignActivity(segment.id, to: nil)
                }
                Divider()
                ForEach(projectStore.activeProjects) { project in
                    Button {
                        assignActivity(segment.id, to: project.id)
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
        .contentShape(Rectangle())
        .onDrag {
            NSItemProvider(object: segment.id.uuidString as NSString)
        }
        .onTapGesture(count: 2) {
            prepareNewEntry(startMinute: segment.startMinute, endMinute: segment.endMinute)
            showingNewEntry = true
        }
        .contextMenu {
            Button("Create Time Entry") {
                prepareNewEntry(startMinute: segment.startMinute, endMinute: segment.endMinute)
                showingNewEntry = true
            }
        }
        .help("Double-click or right-click to create a time entry")
    }

    private func filterButton(
        title: String,
        icon: String,
        filter target: ActivityFilter,
        tint: Color? = nil
    ) -> some View {
        Button {
            filter = target
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 18)
                Text(title)
                Spacer()
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
    }

    private func savedFilterButton(_ savedFilter: ActivityFilterDefinition) -> some View {
        filterButton(
            title: savedFilter.name,
            icon: "line.3.horizontal.decrease.circle",
            filter: .saved(savedFilter.id),
            tint: color(for: savedFilter.color)
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
        .onTapGesture(count: 2) {
            editingFilter = savedFilter
            showingFilterEditor = true
        }
    }

    private func projectTree(_ project: TrackingProject, depth: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 0) {
                projectButton(project, depth: depth)
                ForEach(projectStore.childProjects(of: project.id)) { child in
                    projectTree(child, depth: depth + 1)
                }
            }
        )
    }

    private func projectButton(_ project: TrackingProject, depth: Int = 0) -> some View {
        let target = ActivityFilter.project(project.id)
        return Button {
            filter = target
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(color(for: project.color))
                    .frame(width: 9, height: 9)
                Text(project.name)
                    .lineLimit(1)
                Spacer()
                if filter == target {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .font(.system(size: 12, weight: filter == target ? .semibold : .regular))
            .foregroundStyle(filter == target ? MetridayTheme.accent : MetridayTheme.graphite)
            .padding(.leading, 14 + CGFloat(depth * 16))
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 38)
            .background(filter == target ? MetridayTheme.accentSoft : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onTapGesture(count: 2) {
            editingProject = project
        }
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers, _ in
            handleActivityDrop(providers, onto: project)
        }
        .contextMenu {
            Button("Edit Project") {
                editingProject = project
            }
            Button("Archive Project", role: .destructive) {
                projectStore.archive(project)
                if filter == target {
                    filter = .all
                }
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
                   let rawID = String(data: data, encoding: .utf8),
                   let activityID = UUID(uuidString: rawID.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    ids.append(activityID)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            Task { @MainActor in
                for activityID in Set(ids.snapshot) {
                    guard let activity = self.allActivitySegments.first(where: { $0.id == activityID }) else { continue }
                    if shouldCreateRule {
                        _ = self.createRule(for: activity, projectID: project.id)
                    } else {
                        self.assignActivity(activityID, to: project.id)
                    }
                }
            }
        }
        return true
    }

    private var allActivitySegments: [ActivitySegment] {
        segmentsForSelectedRange
            .sorted {
                if $0.startSecond == $1.startSecond { return $0.endSecond < $1.endSecond }
                return $0.startSecond < $1.startSecond
            }
    }

    private var segmentsForSelectedRange: [ActivitySegment] {
        switch preferences.activityTimeRange {
        case .selectedDay:
            return monitor.observedSegments + screenTimeStore.segments
        case .lastSevenDays:
            let calendar = Calendar.current
            return (0..<7).flatMap { offset in
                let date = calendar.date(byAdding: .day, value: -offset, to: selectedDate) ?? selectedDate
                return monitor.segments(for: date) + screenTimeStore.segments(for: date)
            }
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

    private var filterScopedSegments: [ActivitySegment] {
        scopedSegments(from: segmentsForSelectedRange)
    }

    private var timelineScopedSegments: [ActivitySegment] {
        scopedSegments(from: monitor.observedSegments + screenTimeStore.segments)
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
            return source.filter { $0.projectID == id }
        case .saved(let id):
            guard let savedFilter = filterStore.filter(id) else { return [] }
            return source.filter { filterStore.matches(savedFilter, activity: $0, date: selectedDate) }
        }
    }

    private var filterTitle: String {
        switch filter {
        case .all:
            return "All Activities"
        case .unassigned:
            return "Unassigned"
        case .project(let id):
            return projectStore.name(for: id)
        case .saved(let id):
            return filterStore.filter(id)?.name ?? "Filter"
        }
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
                if enabled { groupActivitiesByDevice = false }
            }
        )
    }

    private var groupByDeviceBinding: Binding<Bool> {
        Binding(
            get: { groupActivitiesByDevice },
            set: { enabled in
                groupActivitiesByDevice = enabled
                if enabled { groupActivitiesByProject = false }
            }
        )
    }

    private func assignActivity(_ id: UUID, to projectID: UUID?) {
        if screenTimeStore.contains(id) {
            screenTimeStore.assignActivity(id, to: projectID)
        } else {
            monitor.assignActivity(id, to: projectID)
        }
    }

    @discardableResult
    private func createRule(for activity: ActivitySegment, projectID: UUID) -> UUID? {
        let ruleID = monitor.createRule(for: activity, projectID: projectID)
        if screenTimeStore.contains(activity.id) {
            screenTimeStore.assignActivity(activity.id, to: projectID)
        }
        return ruleID
    }

    private var totalSeconds: Int {
        filteredSegments.reduce(0) { $0 + $1.durationSeconds }
    }

    private var activityGroups: [ActivityGroup] {
        let grouped = Dictionary(grouping: filteredSegments) { projectStore.name(for: $0.projectID) }
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
        timeEntryStore.entries(overlapping: selectedDate)
    }

    private var timelineTimeEntries: [TimeEntry] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selectedDate)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return timeEntryStore.materializedEntries().filter {
            $0.start < dayEnd && $0.end > dayStart
        }
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

            TextField("What did you work on?", text: $newEntryTitle)
                .textFieldStyle(.roundedBorder)

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
            newEntryBillingStatus = projectID
                .flatMap { projectStore.project($0)?.defaultBillingStatus }
                ?? .billable
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
        endMinute: Int? = nil
    ) {
        newEntryTitle = ""
        newEntryNotes = ""
        newEntryProjectID = selectedProjectID
        newEntryBillingStatus = selectedProjectID
            .flatMap { projectStore.project($0)?.defaultBillingStatus }
            ?? .billable
        if let event {
            newEntryTitle = event.title
            newEntryNotes = [event.calendarTitle, event.location, event.notes]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " · ")
            if selectedProjectID == nil {
                newEntryProjectID = suggestedProjectID(for: event)
                newEntryBillingStatus = newEntryProjectID
                    .flatMap { projectStore.project($0)?.defaultBillingStatus }
                    ?? .billable
            }
            newEntryStart = event.start
            newEntryEnd = event.end
            return
        }
        let calendar = Calendar.current
        if let startMinute, let endMinute, endMinute > startMinute {
            let day = calendar.startOfDay(for: selectedDate)
            newEntryStart = day.addingTimeInterval(TimeInterval(startMinute * 60))
            newEntryEnd = day.addingTimeInterval(TimeInterval(endMinute * 60))
            return
        }
        if let timelineSelectionStart, let timelineSelectionEnd,
           timelineSelectionEnd > timelineSelectionStart {
            let day = calendar.startOfDay(for: selectedDate)
            newEntryStart = day.addingTimeInterval(TimeInterval(timelineSelectionStart * 60))
            newEntryEnd = day.addingTimeInterval(TimeInterval(timelineSelectionEnd * 60))
            return
        }
        let baseDate: Date
        if calendar.isDateInToday(selectedDate) {
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

    private func prepareNewEntry(for reminder: ReminderItem) {
        newEntryTitle = reminder.title
        newEntryNotes = [reminder.listTitle, reminder.notes]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " · ")
        newEntryProjectID = selectedProjectID
        newEntryBillingStatus = selectedProjectID
            .flatMap { projectStore.project($0)?.defaultBillingStatus }
            ?? .billable
        newEntryEnd = reminder.completedAt
        newEntryStart = reminder.completedAt.addingTimeInterval(-30 * 60)
    }

    private func prepareNewEntry(for call: PhoneCallItem) {
        newEntryTitle = call.title
        newEntryNotes = [call.serviceProvider, call.address]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " · ")
        newEntryProjectID = selectedProjectID
        newEntryBillingStatus = selectedProjectID
            .flatMap { projectStore.project($0)?.defaultBillingStatus }
            ?? .billable
        newEntryStart = call.start
        newEntryEnd = call.end
    }

    private func suggestedProjectID(for event: CalendarEventItem) -> UUID? {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: event.start)
        let startMinute = max(0, calendar.dateComponents([.minute], from: day, to: event.start).minute ?? 0)
        let endMinute = max(startMinute + 1, calendar.dateComponents([.minute], from: day, to: event.end).minute ?? startMinute + 1)
        let activity = ActivitySegment(
            appName: "Calendar",
            windowTitle: event.title,
            resource: event.urlString.isEmpty ? event.calendarTitle : event.urlString,
            startMinute: min(1_439, startMinute),
            endMinute: min(1_440, endMinute),
            relevance: .other
        )
        return projectStore.matchingProjectID(for: activity, date: event.start)
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
            overlappingEntries.forEach { timeEntryStore.delete($0) }
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
        return "This range overlaps \(overlappingEntries.count) existing time \(noun). Replace them or keep parallel entries?"
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

    private var keywordSegments: [ActivitySegment] {
        filteredSegments.filter { !$0.windowTitle.isEmpty }
    }

    private var keywordRows: [CategoryRow] {
        let stopWords: Set<String> = [
            "the", "and", "for", "with", "from", "http", "https", "www", "com"
        ]
        var values: [String: (seconds: Int, distracted: Bool)] = [:]
        for segment in keywordSegments {
            let source = "\(segment.windowTitle) \(segment.resource)"
            let words = source
                .split { character in
                    !(character.isLetter || character.isNumber || character == "_" || character == "-")
                }
                .map { $0.lowercased() }
                .filter { $0.count >= 3 && !stopWords.contains($0) }
            for word in Set(words) {
                let current = values[word, default: (seconds: 0, distracted: false)]
                values[word] = (
                    seconds: current.seconds + segment.durationSeconds,
                    distracted: current.distracted || segment.relevance == .distracted
                )
            }
        }
        return values.map { name, value in
            CategoryRow(name: name, seconds: value.seconds, isDistracted: value.distracted)
        }
        .sorted { $0.seconds > $1.seconds }
    }

    private func categoryRows(_ segments: [ActivitySegment]) -> [CategoryRow] {
        var values: [String: (seconds: Int, distracted: Bool)] = [:]
        for segment in segments {
            let name = categoryName(for: segment)
            guard !name.isEmpty else { continue }
            let current = values[name, default: (seconds: 0, distracted: false)]
            values[name] = (
                seconds: current.seconds + segment.durationSeconds,
                distracted: current.distracted || segment.relevance == .distracted
            )
        }
        return values.map { name, value in
            CategoryRow(name: name, seconds: value.seconds, isDistracted: value.distracted)
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
        switch relevance {
        case .related:
            return MetridayTheme.success
        case .distracted:
            return MetridayTheme.danger
        case .other:
            return MetridayTheme.secondary
        case .idle:
            return MetridayTheme.secondary
        }
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
            Toggle("Show window titles", isOn: $preferences.showWindowTitles)
                .toggleStyle(.checkbox)
            Toggle("Show website hosts and file paths", isOn: $preferences.showResourcePaths)
                .toggleStyle(.checkbox)

            Picker("Activity usage range", selection: $preferences.activityTimeRange) {
                ForEach(ActivityTimeRange.allCases) { range in
                    Text(range.label).tag(range)
                }
            }
            .pickerStyle(.menu)

            if preferences.activityTimeRange == .lastSevenDays {
                Label("The timeline stays on the selected day; the activity list includes the previous seven days.", systemImage: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(MetridayTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 430)
    }
}

private enum ActivityDisplayMode: String, CaseIterable, Identifiable {
    case unified
    case chronological
    case byCategory

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
    let isDistracted: Bool
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
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onRecord(event)
                        }
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
                            Button("Record") {
                                onRecord(reminder)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("reminder.record.\(reminder.id)")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onRecord(reminder)
                        }
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
                            Button("Record") {
                                onRecord(call)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("phone-call.record.\(call.id)")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onRecord(call)
                        }
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
    let segments: [ActivitySegment]
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
        existingEntries: [TimeEntry],
        projects: [TrackingProject],
        initialProjectID: UUID?,
        onCreate: @escaping ([EntryOMaticInterval], String, UUID?, String, BillingStatus, Bool) -> Void
    ) {
        self.selectedDate = selectedDate
        self.segments = segments
        self.existingEntries = existingEntries
        self.projects = projects
        self.initialProjectID = initialProjectID
        self.onCreate = onCreate
        _projectID = State(initialValue: initialProjectID)
        _title = State(initialValue: initialProjectID
            .flatMap { id in projects.first(where: { $0.id == id })?.name }
            ?? "Work session")
        _billingStatus = State(initialValue: initialProjectID
            .flatMap { id in projects.first(where: { $0.id == id })?.defaultBillingStatus }
            ?? .billable)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Create Time Entries")
                .font(.system(size: 18, weight: .bold))
            Text("Turn visible app usage into reviewable time entries for \(dateLabel).")
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
            Text("Without replacement, already recorded time is subtracted from the generated intervals.")
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
            billingStatus = newProjectID
                .flatMap { id in projects.first(where: { $0.id == id })?.defaultBillingStatus }
                ?? .billable
        }
    }

    private var previewIntervals: [EntryOMaticInterval] {
        let scopedSegments = projectID.map { id in
            segments.filter { $0.projectID == id }
        } ?? segments
        return EntryOMaticGenerator.intervals(
            from: scopedSegments,
            dayStart: Calendar.current.startOfDay(for: selectedDate),
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
        onStart: @escaping (String, UUID?, String, BillingStatus, Int?) -> Void
    ) {
        self.projects = projects
        self.recentEntries = recentEntries
        self.recentCalendarEvents = recentCalendarEvents
        self.onStart = onStart
        let resolvedProjectID = initialProjectID ?? projects.first?.id
        _projectID = State(initialValue: resolvedProjectID)
        _title = State(initialValue: resolvedProjectID
            .flatMap { id in projects.first(where: { $0.id == id })?.name }
            ?? "Focused work")
        _estimatedDurationMinutes = State(initialValue: nil)
        _billingStatus = State(initialValue: resolvedProjectID
            .flatMap { id in projects.first(where: { $0.id == id })?.defaultBillingStatus }
            ?? .billable)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Start Timer")
                .font(.system(size: 18, weight: .bold))
            Text("The timer will capture activity until you stop it.")
                .font(.system(size: 11))
                .foregroundStyle(MetridayTheme.secondary)

            TextField("What are you working on?", text: $title)
                .textFieldStyle(.roundedBorder)

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
                            notes = [event.calendarTitle, event.location]
                                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                                .joined(separator: " · ")
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
            billingStatus = newProjectID
                .flatMap { id in projects.first(where: { $0.id == id })?.defaultBillingStatus }
                ?? .billable
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
    let sourceColor: Color
    let title: String
    let timeRange: String
    let duration: String
    let projectName: String
    let projectColor: Color
    let projectQualifier: String?
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
        color: Color,
        value: String,
        suffix: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(label):")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MetridayTheme.secondary)
                .frame(width: 55, alignment: .trailing)
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
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

private struct TimelineLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            item("App usage", color: MetridayTheme.warning)
            item("Related", color: MetridayTheme.success)
            item("Distracted", color: MetridayTheme.danger)
            item("Other / idle", color: MetridayTheme.secondary)
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
    let selectedDate: Date
    let project: (UUID?) -> TrackingProject?
    @Binding var selectionStart: Int?
    @Binding var selectionEnd: Int?
    let onCreateTimeEntry: (Int?, Int?) -> Void
    let onRecordCalendarEvent: (CalendarEventItem, Bool) -> Void
    let onEditTimeEntry: (TimeEntry) -> Void

    @State private var dragAnchorMinute: Int?
    @State private var hoveredSegmentID: UUID?
    @State private var hoveredTimeEntryID: UUID?
    @State private var hoveredCalendarEventID: String?

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

            TimelineLegend()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ForEach(0...24, id: \.self) { hour in
                        Rectangle()
                            .fill(MetridayTheme.line.opacity(hour % 6 == 0 ? 0.9 : 0.45))
                            .frame(width: 1, height: 106)
                            .position(
                                x: proxy.size.width * CGFloat(hour) / 24,
                                y: 53
                            )
                    }

                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        let left = proxy.size.width * CGFloat(segment.startSecond) / 86_400
                        let width = max(
                            3,
                            proxy.size.width * CGFloat(segment.durationSeconds) / 86_400
                        )
                        ZStack(alignment: .trailing) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(color(for: segment.relevance).opacity(0.82))
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
                        .frame(width: width, height: 18)
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
                            }
                        }
                        .contextMenu {
                            Button("Create Time Entry") {
                                let start = max(0, segment.startMinute)
                                let end = min(1_440, max(start + 15, segment.endMinute))
                                onCreateTimeEntry(start, end)
                            }
                        }
                            .position(
                                x: left + width / 2,
                                y: 24 + CGFloat(index % 4) * 22
                            )
                    }

                    ForEach(calendarEvents) { event in
                        let startSecond = max(0, min(86_400, second(of: event.start)))
                        let endSecond = max(startSecond + 900, min(86_400, second(of: event.end)))
                        let left = proxy.size.width * CGFloat(startSecond) / 86_400
                        let width = max(
                            4,
                            proxy.size.width * CGFloat(endSecond - startSecond) / 86_400
                        )
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
                            .position(x: left + width / 2, y: 96)
                            .contentShape(Rectangle())
                            .onHover { isHovered in
                                if isHovered {
                                    hoveredCalendarEventID = event.id
                                    hoveredSegmentID = nil
                                    hoveredTimeEntryID = nil
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

                    ForEach(timeEntries) { entry in
                        if let range = clippedRange(for: entry) {
                            let left = proxy.size.width * CGFloat(range.start) / 86_400
                            let width = max(
                                4,
                                proxy.size.width * CGFloat(range.end - range.start) / 86_400
                            )
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(MetridayTheme.warning.opacity(0.22))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .stroke(MetridayTheme.warning, lineWidth: 1)
                                )
                                .frame(width: width, height: 12)
                                .position(x: left + width / 2, y: 114)
                                .contentShape(Rectangle())
                                .onHover { isHovered in
                                    if isHovered {
                                        hoveredTimeEntryID = entry.id
                                        hoveredSegmentID = nil
                                        hoveredCalendarEventID = nil
                                    }
                                }
                                .onTapGesture {
                                    onEditTimeEntry(entry)
                                }
                                .contextMenu {
                                    Button("Edit Time Entry") {
                                        onEditTimeEntry(entry)
                                    }
                                }
                                .help("Recorded time · \(entry.title)")
                        }
                    }

                    if let start = selectionStart, let end = selectionEnd {
                        let left = proxy.size.width * CGFloat(start) / 1_440
                        let width = max(2, proxy.size.width * CGFloat(end - start) / 1_440)
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
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d", hour))
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
                            let minute = minute(at: value.location.x, width: proxy.size.width)
                            if dragAnchorMinute == nil {
                                dragAnchorMinute = minute
                            }
                            guard let anchor = dragAnchorMinute else { return }
                            selectionStart = min(anchor, minute)
                            selectionEnd = max(anchor + 15, minute)
                            selectionEnd = min(1_440, selectionEnd ?? 1_440)
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
                    }
                }
            }
            .frame(height: 156)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MetridayTheme.line, lineWidth: 1)
        )
    }

    private var selectionLabel: String {
        guard let selectionStart, let selectionEnd else {
            return "Drag across the day to inspect a time range"
        }
        let entries = timeEntries.filter {
            $0.start < endOfSelection && $0.end > startOfSelection
        }.count
        return "Selected \(TimeFormat.range(start: selectionStart, end: selectionEnd)) · \(segmentsInSelection) activities · \(entries) entries"
    }

    private var startOfSelection: Date {
        Calendar.current.startOfDay(for: selectedDate)
            .addingTimeInterval(TimeInterval((selectionStart ?? 0) * 60))
    }

    private var endOfSelection: Date {
        Calendar.current.startOfDay(for: selectedDate)
            .addingTimeInterval(TimeInterval((selectionEnd ?? 0) * 60))
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
                sourceColor: MetridayTheme.warning,
                title: segment.displayTitle,
                timeRange: secondRange(start: segment.startSecond, end: segment.endSecond),
                duration: durationLabel(segment.durationSeconds),
                projectName: project?.name ?? "None",
                projectColor: color(for: project?.color),
                projectQualifier: project == nil ? "From the app usage" : nil
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
                projectQualifier: project == nil ? "Manual time entry" : nil
            )
        }

        if let hoveredCalendarEventID,
           let event = calendarEvents.first(where: { $0.id == hoveredCalendarEventID }) {
            let start = second(of: event.start)
            let end = max(start + 900, second(of: event.end))
            return TimelineHoverDetail(
                id: "calendar-\(event.id)",
                sourceLabel: "Calendar",
                sourceColor: MetridayTheme.accent,
                title: event.title,
                timeRange: secondRange(start: start, end: end),
                duration: durationLabel(event.durationSeconds),
                projectName: "None",
                projectColor: color(for: nil),
                projectQualifier: "Offline calendar event"
            )
        }

        return nil
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
        return String(
            format: "%02d:%02d:%02d",
            clamped / 3_600,
            (clamped % 3_600) / 60,
            clamped % 60
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
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selectedDate)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let start = max(entry.start, dayStart)
        let end = min(entry.end, dayEnd)
        guard end > start else { return nil }
        let startSecond = max(0, min(86_400, second(of: start)))
        let endSecond = end >= dayEnd
            ? 86_400
            : max(startSecond + 900, min(86_400, second(of: end)))
        guard endSecond > startSecond else { return nil }
        return (startSecond, endSecond)
    }

    private func color(for relevance: ActivityRelevance) -> Color {
        switch relevance {
        case .related:
            return MetridayTheme.success
        case .distracted:
            return MetridayTheme.danger
        case .other, .idle:
            return MetridayTheme.secondary
        }
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
        _defaultBillingStatus = State(initialValue: project.defaultBillingStatus)
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

            Picker("Default billing status", selection: $defaultBillingStatus) {
                ForEach(BillingStatus.allCases) { status in
                    Text(status.label).tag(status)
                }
            }

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
                    updated.defaultBillingStatus = defaultBillingStatus
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
    let onSave: (TimeEntry) -> Void

    @State private var title: String
    @State private var projectID: UUID?
    @State private var billingStatus: BillingStatus
    @State private var start: Date
    @State private var end: Date
    @State private var notes: String

    init(
        entry: TimeEntry,
        projects: [TrackingProject],
        onSave: @escaping (TimeEntry) -> Void
    ) {
        self.entry = entry
        self.projects = projects
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

            TextField("What did you work on?", text: $title)
                .textFieldStyle(.roundedBorder)

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
                Button("Save") {
                    var updated = entry
                    updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.projectID = projectID
                    updated.billingStatus = billingStatus
                    updated.start = start
                    updated.end = end
                    updated.notes = notes
                    guard !updated.title.isEmpty, updated.end > updated.start else { return }
                    onSave(updated)
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
        .frame(width: 420)
    }
}

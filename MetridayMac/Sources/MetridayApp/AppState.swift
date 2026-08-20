import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var section: AppSection = .today
    @Published private(set) var selectedDate: Date
    @Published var activityScope: ActivityProjectScope = ActivityProjectScope(
        persistedValue: UserDefaults.standard.string(forKey: "Metriday.activityScope")
    ) {
        didSet {
            UserDefaults.standard.set(activityScope.persistedValue, forKey: "Metriday.activityScope")
        }
    }
    @Published var focusIsActive = false {
        didSet { blocker.isActive = focusIsActive }
    }
    @Published var selectedTaskID: UUID?
    @Published var draggingTaskID: UUID?
    @Published var dragLocation: CGPoint = .zero
    @Published var calendarTimelineFrame: CGRect = .zero
    @Published var calendarTimelineScreenFrame: CGRect = .zero
    @Published var timelineDropIntent: TimelineDropIntent = .choose
    @Published var pendingTimelineDrop: PendingTimelineDrop?

    let markdownStore: MarkdownStore
    let projectStore: ProjectStore
    let filterStore: ActivityFilterStore
    let categoryStore: ActivityCategoryStore
    let activitiesPreferences: ActivitiesPreferencesStore
    let timeEntryStore: TimeEntryStore
    let preferences: PreferencesStore
    let exclusionStore: ExclusionStore
    let calendarStore: CalendarEventStore
    let reminderStore: ReminderStore
    let phoneCallStore: PhoneCallStore
    let screenTimeStore: ScreenTimeStore
    let localAPIServer: LocalAPIServer
    let loginItemManager: LoginItemManager
    let syncStore: SyncStore
    let integrationStore: IntegrationStore
    let teamStore: TeamStore
    let activityMonitor: AppActivityMonitor
    let blocker: WebBlockerService
    private var workspaceCancellables = Set<AnyCancellable>()

    init() {
        let initialDate = Calendar.current.startOfDay(for: .now)
        self.selectedDate = initialDate
        self.markdownStore = MarkdownStore(date: initialDate)
        self.projectStore = ProjectStore()
        self.filterStore = ActivityFilterStore()
        self.categoryStore = ActivityCategoryStore()
        self.activitiesPreferences = ActivitiesPreferencesStore()
        self.timeEntryStore = TimeEntryStore()
        self.preferences = PreferencesStore()
        self.exclusionStore = ExclusionStore()
        self.calendarStore = CalendarEventStore()
        self.reminderStore = ReminderStore()
        self.phoneCallStore = PhoneCallStore()
        self.screenTimeStore = ScreenTimeStore()
        self.localAPIServer = LocalAPIServer()
        self.loginItemManager = LoginItemManager()
        self.blocker = WebBlockerService()
        self.teamStore = TeamStore()
        self.activityMonitor = AppActivityMonitor(
            projectStore: projectStore,
            preferences: preferences,
            exclusionStore: exclusionStore
        )
        self.syncStore = SyncStore(
            projectStore: projectStore,
            filterStore: filterStore,
            timeEntryStore: timeEntryStore,
            activityMonitor: activityMonitor,
            markdownStore: markdownStore,
            screenTimeStore: screenTimeStore,
            webBlocker: blocker,
            exclusionStore: exclusionStore,
            teamStore: teamStore
        )
        self.integrationStore = IntegrationStore()
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                guard let self, self.preferences.autoStopTimerOnSleep else { return }
                _ = self.timeEntryStore.stopTimer()
            }
            .store(in: &workspaceCancellables)
        timeEntryStore.$canUndoEntryOMatic
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &workspaceCancellables)
        self.calendarStore.loadEvents(for: initialDate)
        self.reminderStore.loadCompleted(for: initialDate)
        self.phoneCallStore.loadCalls(for: initialDate)
        self.screenTimeStore.load(for: initialDate)
        self.localAPIServer.start(handler: { [weak self] request in
            guard let self else {
                return .error("Metriday is unavailable", statusCode: 503)
            }
            return self.handle(localAPI: request)
        }, allowLAN: preferences.allowLocalNetworkAPI)
        self.syncStore.start()
        if preferences.startTrackingWhenAppOpens {
            self.activityMonitor.start()
        }
    }

    var currentTask: PlanTask? {
        if let selectedTaskID, let selected = markdownStore.task(selectedTaskID), selected.startMinute != nil {
            return selected
        }

        let scheduled = markdownStore.tasks
            .filter { $0.startMinute != nil && $0.endMinute != nil }
            .sorted { ($0.startMinute ?? 0) < ($1.startMinute ?? 0) }

        if Calendar.current.isDateInToday(selectedDate) {
            let components = Calendar.current.dateComponents([.hour, .minute], from: .now)
            let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            if let active = scheduled.first(where: {
                guard let start = $0.startMinute, let end = $0.endMinute else { return false }
                return start <= minute && minute < end
            }) {
                return active
            }
            return nil
        }
        return scheduled.first
    }

    func selectDate(_ date: Date) {
        let normalized = Calendar.current.startOfDay(for: date)
        guard !Calendar.current.isDate(normalized, inSameDayAs: selectedDate) else { return }
        selectedDate = normalized
        selectedTaskID = nil
        pendingTimelineDrop = nil
        draggingTaskID = nil
        _ = markdownStore.load(date: normalized)
        activityMonitor.selectDate(normalized)
        calendarStore.loadEvents(for: normalized)
        reminderStore.loadCompleted(for: normalized)
        phoneCallStore.loadCalls(for: normalized)
        screenTimeStore.load(for: normalized)
    }

    /// Mirrors Timing's quick-start timer workflow used from the tracker and
    /// keyboard shortcut: reuse the most recent timer context when available,
    /// otherwise fall back to the current planned task.
    func quickStartTimer() {
        if timeEntryStore.runningTimer != nil {
            _ = timeEntryStore.stopTimer()
            return
        }
        let recent = timeEntryStore.recentTimerEntries(limit: 1).first
        let projectID = recent?.projectID
        let title = recent?.title
            ?? currentTask?.title
            ?? projectID.flatMap { projectStore.project($0)?.name }
            ?? "Manual timer"
        if let recent {
            timeEntryStore.startTimer(reusing: recent)
            return
        }
        timeEntryStore.startTimer(
            title: title,
            projectID: projectID,
            notes: recent?.notes ?? "",
            billingStatus: recent?.billingStatus
                ?? projectStore.resolvedBillingStatus(for: projectID),
            customFields: recent?.customFields ?? [:]
        )
    }

    func startTimer(reusing entry: TimeEntry) {
        guard timeEntryStore.runningTimer == nil else { return }
        timeEntryStore.startTimer(reusing: entry)
    }

    private func handle(localAPI request: LocalAPIRequest) -> LocalAPIResponse {
        if request.method == "OPTIONS" {
            return .empty()
        }

        let rawPath = request.path.hasPrefix("/") ? request.path : "/\(request.path)"
        if rawPath == "/mcp" {
            return handleMCP(request)
        }
        let timingWebAPI = rawPath == "/api/v1" || rawPath.hasPrefix("/api/v1/")
        let path = timingWebAPI
            ? String(rawPath.dropFirst("/api".count))
            : rawPath
        guard path == "/v1" || path.hasPrefix("/v1/") else {
            return .error("Unknown API version", statusCode: 404)
        }

        if request.method == "GET", path == "/v1/plans" {
            let date = apiDate(from: request.query["date"]) ?? selectedDate
            return .jsonObject(planAPIResponse(for: date))
        }
        if (request.method == "PUT" || request.method == "POST"), path == "/v1/plans" {
            guard let body = apiBody(request), let markdown = body["markdown"] as? String else {
                return .error("Plan body needs a markdown string", statusCode: 400)
            }
            let date = apiDate(from: request.query["date"] ?? body["date"] as? String) ?? selectedDate
            guard markdownStore.replaceMarkdown(markdown, for: date) else {
                return .error("Plan could not be saved", statusCode: 500)
            }
            if Calendar.current.isDate(date, inSameDayAs: selectedDate) {
                _ = markdownStore.load(date: date, createIfMissing: false)
            }
            return .jsonObject(planAPIResponse(for: date))
        }

        if request.method == "GET", path == "/v1/status" {
            var response: [String: Any] = [
                "tracking": activityMonitor.isTracking,
                "section": section.rawValue,
                "selectedDate": apiDate(selectedDate),
                "currentApplication": activityMonitor.currentApplication,
                "currentWindowTitle": activityMonitor.currentWindowTitle,
                "api": localAPIServer.endpoint
            ]
            if let task = currentTask {
                response["currentTask"] = [
                    "id": task.id.uuidString,
                    "title": task.title,
                    "startMinute": apiValue(task.startMinute),
                    "endMinute": apiValue(task.endMinute)
                ]
            }
            if let timer = timeEntryStore.runningTimer {
                response["timer"] = [
                    "id": timer.id.uuidString,
                    "title": timer.title,
                    "projectID": timer.projectID.map { $0.uuidString } ?? NSNull(),
                    "notes": timer.notes,
                    "startedAt": apiDate(timer.startedAt),
                    "billingStatus": entryBillingStatusRaw(timer.billingStatus),
                    "durationSeconds": timeEntryStore.runningDurationSeconds,
                    "estimatedDurationSeconds": timer.estimatedDurationSeconds.map { $0 as Any } ?? NSNull(),
                    "remainingSeconds": timeEntryStore.runningTimerRemainingSeconds.map { $0 as Any } ?? NSNull()
                ]
            } else {
                response["timer"] = NSNull()
            }
            return .jsonObject(response)
        }

        if request.method == "GET", path == "/v1/preferences" {
            return .jsonObject(preferencesAPI())
        }

        if (request.method == "PATCH" || request.method == "PUT"), path == "/v1/preferences" {
            guard let body = apiBody(request) else {
                return .error("Preferences body is invalid", statusCode: 400)
            }
            if let value = body["idle_threshold_seconds"] as? Int {
                preferences.idleThresholdSeconds = min(max(value, 30), 3600)
            }
            if let value = body["track_weekends"] as? Bool {
                preferences.trackWeekends = value
            }
            if let value = body["track_only_during_working_hours"] as? Bool {
                preferences.trackOnlyDuringWorkingHours = value
            }
            if let value = body["working_hours_start_minute"] as? Int {
                preferences.workingHoursStartMinute = min(max(value, 0), 1439)
            }
            if let value = body["working_hours_end_minute"] as? Int {
                preferences.workingHoursEndMinute = min(max(value, 0), 1439)
            }
            if let value = body["start_tracking_when_app_opens"] as? Bool {
                preferences.startTrackingWhenAppOpens = value
            }
            if let value = body["auto_stop_timer_on_sleep"] as? Bool {
                preferences.autoStopTimerOnSleep = value
            }
            if let value = body["allow_local_network_api"] as? Bool {
                preferences.allowLocalNetworkAPI = value
                localAPIServer.setAllowsLAN(value)
            }
            if let value = body["launch_at_login"] as? Bool {
                if value == loginItemManager.isEnabled {
                    loginItemManager.refresh()
                } else {
                    loginItemManager.setEnabled(value)
                }
            }
            return .jsonObject(preferencesAPI())
        }

        if request.method == "GET", path == "/v1/activity-preferences" {
            return .jsonObject(activityPreferencesAPI())
        }

        if (request.method == "PATCH" || request.method == "PUT"), path == "/v1/activity-preferences" {
            guard let body = apiBody(request) else {
                return .error("Activity preferences body is invalid", statusCode: 400)
            }
            if let value = body["include_time_entries"] as? Bool {
                activitiesPreferences.includeTimeEntries = value
            }
            if let value = body["show_window_titles"] as? Bool {
                activitiesPreferences.showWindowTitles = value
            }
            if let value = body["show_resource_paths"] as? Bool {
                activitiesPreferences.showResourcePaths = value
            }
            if let value = body["group_websites_independently"] as? Bool {
                activitiesPreferences.groupWebsitesIndependently = value
            }
            if let value = body["group_paths_independently"] as? Bool {
                activitiesPreferences.groupPathsIndependently = value
            }
            if let value = body["activity_time_range"] as? String,
               let range = ActivityTimeRange(rawValue: value) {
                activitiesPreferences.activityTimeRange = range
            }
            if let value = body["activity_display_mode"] as? String {
                activitiesPreferences.activityDisplayMode = value
            }
            if let value = body["group_by_project"] as? Bool {
                activitiesPreferences.groupByProject = value
                if value { activitiesPreferences.groupByDevice = false }
            }
            if let value = body["group_by_device"] as? Bool {
                activitiesPreferences.groupByDevice = value
                if value { activitiesPreferences.groupByProject = false }
            }
            if let value = body["include_idle"] as? Bool {
                activitiesPreferences.includeIdle = value
            }
            if let value = body["selected_device"] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                activitiesPreferences.selectedDevice = value
            }
            if let value = body["timeline_orientation"] as? String,
               let orientation = ActivityTimelineOrientation(rawValue: value) {
                activitiesPreferences.timelineOrientation = orientation
            }
            return .jsonObject(activityPreferencesAPI())
        }

        if request.method == "GET", path == "/v1/source-preferences" {
            return .jsonObject(sourcePreferencesAPI())
        }

        if (request.method == "PATCH" || request.method == "PUT"), path == "/v1/source-preferences" {
            guard let body = apiBody(request) else {
                return .error("Source preferences body is invalid", statusCode: 400)
            }
            if let titles = apiStringArray(body["calendar_included_titles"]) {
                calendarStore.setIncludedCalendarTitles(titles)
            }
            if let titles = apiStringArray(body["reminder_included_list_titles"]) {
                reminderStore.setIncludedListTitles(titles)
            }
            if let value = body["reminder_hide_recurring"] as? Bool {
                reminderStore.hideRecurringReminders = value
            }
            return .jsonObject(sourcePreferencesAPI())
        }

        if request.method == "POST", path == "/v1/source-preferences/access" {
            guard let body = apiBody(request), let source = body["source"] as? String else {
                return .error("Source access request needs a source", statusCode: 400)
            }
            switch source {
            case "accessibility":
                activityMonitor.requestAccessibilityAccess()
            case "calendar":
                calendarStore.requestAccess()
            case "reminders":
                reminderStore.requestAccess()
            case "phone-calls":
                phoneCallStore.openAccessSettings()
            case "screen-time":
                screenTimeStore.openAccessSettings()
            default:
                return .error("Unknown source", statusCode: 400)
            }
            return .jsonObject(sourcePreferencesAPI())
        }

        if request.method == "GET", path == "/v1/project-rules" {
            return .jsonObject([
                "data": projectStore.rules.map(apiProjectRule),
                "status": projectStore.statusMessage
            ])
        }

        if request.method == "POST", path == "/v1/project-rules" {
            guard let body = apiBody(request),
                  let projectID = apiProjectID((body["project_id"] as? String) ?? (body["project"] as? String) ?? ""),
                  let field = (body["field"] as? String).flatMap(ProjectRuleField.init(rawValue:)),
                  let pattern = body["pattern"] as? String,
                  let comparison = (body["comparison"] as? String).flatMap(ProjectRuleComparison.init(rawValue:)),
                  let ruleID = projectStore.addRule(
                    projectID: projectID,
                    field: field,
                    pattern: pattern,
                    isCaseSensitive: body["case_sensitive"] as? Bool ?? false,
                    comparison: comparison
                  ),
                  let rule = projectStore.rules.first(where: { $0.id == ruleID }) else {
                return .error("Project rule needs a project, field, comparison, and pattern", statusCode: 400)
            }
            return .jsonObject(["data": apiProjectRule(rule)], statusCode: 201)
        }

        if request.method == "POST", path == "/v1/project-rules/reapply" {
            let date = apiDate(from: apiBody(request)?["date"] as? String) ?? selectedDate
            activityMonitor.reapplyRules(for: date)
            return .jsonObject([
                "date": apiDate(date),
                "status": projectStore.statusMessage
            ])
        }

        if request.method == "POST", path == "/v1/project-rules/reapply-all" {
            activityMonitor.reapplyRulesForAllStoredDays()
            return .jsonObject(["status": projectStore.statusMessage])
        }

        if path.hasPrefix("/v1/project-rules/") {
            let rawID = String(path.dropFirst("/v1/project-rules/".count))
            guard let ruleID = UUID(uuidString: rawID),
                  let rule = projectStore.rules.first(where: { $0.id == ruleID }) else {
                return .error("Project rule not found", statusCode: 404)
            }
            if request.method == "PATCH" || request.method == "PUT" {
                let offset = (apiBody(request)?["offset"] as? Int) ?? 0
                if offset != 0 { projectStore.moveRule(rule, by: offset) }
                return .jsonObject(["data": apiProjectRule(rule)])
            }
            if request.method == "DELETE" {
                projectStore.removeRule(rule)
                return .empty()
            }
        }

        if request.method == "GET", path == "/v1/rules" {
            return .jsonObject([
                "data": blocker.rules.map(officialWebRule),
                "focusActive": focusIsActive,
                "status": blocker.status
            ])
        }

        if request.method == "POST", path == "/v1/rules" {
            guard let body = apiBody(request),
                  let domain = body["domain"] as? String,
                  !domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .error("Rule needs a domain", statusCode: 400)
            }
            blocker.add(domain: domain, allowed: body["allowed"] as? Bool ?? false)
            return .jsonObject([
                "data": blocker.rules.map(officialWebRule),
                "focusActive": focusIsActive,
                "status": blocker.status
            ], statusCode: 201)
        }

        if request.method == "POST", path == "/v1/focus" {
            guard let active = apiBody(request)?["active"] as? Bool else {
                return .error("Focus body needs an active boolean", statusCode: 400)
            }
            focusIsActive = active
            return .jsonObject(["active": focusIsActive, "status": blocker.status])
        }

        if request.method == "GET", path == "/v1/filters" {
            return .jsonObject([
                "data": filterStore.activeFilters.map(apiActivityFilter),
                "status": filterStore.statusMessage
            ])
        }

        if request.method == "POST", path == "/v1/filters" {
            guard let body = apiBody(request),
                  let definition = activityFilter(from: body) else {
                return .error("Filter needs a name and at least one valid rule", statusCode: 400)
            }
            filterStore.save(definition)
            return .jsonObject(["data": apiActivityFilter(definition)], statusCode: 201)
        }

        if path.hasPrefix("/v1/filters/") {
            let rawID = String(path.dropFirst("/v1/filters/".count))
            guard let filterID = UUID(uuidString: rawID),
                  let existing = filterStore.filter(filterID) else {
                return .error("Filter not found", statusCode: 404)
            }
            if request.method == "GET" {
                return .jsonObject(["data": apiActivityFilter(existing)])
            }
            if request.method == "PATCH" || request.method == "PUT" {
                guard let body = apiBody(request),
                      let updated = activityFilter(from: body, existing: existing) else {
                    return .error("Filter body is invalid", statusCode: 400)
                }
                filterStore.save(updated)
                return .jsonObject(["data": apiActivityFilter(updated)])
            }
            if request.method == "DELETE" {
                filterStore.delete(existing)
                return .empty()
            }
        }

        if request.method == "GET", path == "/v1/categories" {
            return .jsonObject([
                "data": categoryStore.activeCategories.map(apiActivityCategory),
                "status": categoryStore.statusMessage
            ])
        }

        if request.method == "POST", path == "/v1/categories" {
            guard let body = apiBody(request),
                  let draft = activityCategory(from: body),
                  !draft.isSystem,
                  let categoryID = categoryStore.createCategory(
                    name: draft.name,
                    role: draft.role,
                    color: draft.color,
                    matchMode: draft.matchMode,
                    rules: draft.rules
                  ),
                  let created = categoryStore.categories.first(where: { $0.id == categoryID }) else {
                return .error("Category needs a name and at least one valid rule", statusCode: 400)
            }
            return .jsonObject(["data": apiActivityCategory(created)], statusCode: 201)
        }

        if path.hasPrefix("/v1/categories/") {
            let rawID = String(path.dropFirst("/v1/categories/".count))
            guard let categoryID = UUID(uuidString: rawID),
                  let existing = categoryStore.categories.first(where: { $0.id == categoryID }) else {
                return .error("Category not found", statusCode: 404)
            }
            if request.method == "PATCH" || request.method == "PUT" {
                guard let body = apiBody(request), let updated = activityCategory(from: body, existing: existing) else {
                    return .error("Category body is invalid", statusCode: 400)
                }
                categoryStore.save(updated)
                let current = categoryStore.categories.first(where: { $0.id == categoryID }) ?? existing
                return .jsonObject(["data": apiActivityCategory(current)])
            }
            if request.method == "DELETE" {
                categoryStore.archive(existing)
                return .empty()
            }
        }

        if request.method == "GET", path == "/v1/exclusions" {
            return .jsonObject([
                "data": exclusionStore.rules.map(apiActivityExclusion),
                "status": exclusionStore.statusMessage
            ])
        }

        if request.method == "POST", path == "/v1/exclusions" {
            guard let body = apiBody(request),
                  let field = (body["field"] as? String).flatMap(ActivityExclusionField.init(rawValue:)),
                  let pattern = body["pattern"] as? String,
                  let comparison = (body["comparison"] as? String).flatMap(ProjectRuleComparison.init(rawValue:)),
                  let ruleID = exclusionStore.addRule(
                      field: field,
                      pattern: pattern,
                      isCaseSensitive: body["case_sensitive"] as? Bool ?? false,
                      comparison: comparison
                  ),
                  let rule = exclusionStore.rules.first(where: { $0.id == ruleID }) else {
                return .error("Exclusion needs a field, comparison, and pattern", statusCode: 400)
            }
            return .jsonObject(["data": apiActivityExclusion(rule)], statusCode: 201)
        }

        if path.hasPrefix("/v1/exclusions/") {
            let rawID = String(path.dropFirst("/v1/exclusions/".count))
            guard let ruleID = UUID(uuidString: rawID),
                  let rule = exclusionStore.rules.first(where: { $0.id == ruleID }) else {
                return .error("Exclusion not found", statusCode: 404)
            }
            if request.method == "GET" {
                return .jsonObject(["data": apiActivityExclusion(rule)])
            }
            if request.method == "DELETE" {
                exclusionStore.remove(rule)
                return .empty()
            }
        }

        if path.hasPrefix("/v1/rules/") {
            let rawID = String(path.dropFirst("/v1/rules/".count))
            guard let ruleID = UUID(uuidString: rawID),
                  let rule = blocker.rules.first(where: { $0.id == ruleID }) else {
                return .error("Rule not found", statusCode: 404)
            }
            if request.method == "PATCH" || request.method == "PUT" {
                guard let allowed = apiBody(request)?["allowed"] as? Bool else {
                    return .error("Rule body needs an allowed boolean", statusCode: 400)
                }
                blocker.setAllowed(rule, allowed: allowed)
                return .jsonObject(["data": blocker.rules.map(officialWebRule), "focusActive": focusIsActive])
            }
            if request.method == "DELETE" {
                blocker.remove(rule)
                return .empty()
            }
        }

        // Mirror the public Timing Web API resource shapes on the local
        // loopback server. The local namespace remains available below for
        // full-fidelity archive/import operations.
        if timingWebAPI, request.method == "GET", path == "/v1/activity-hierarchy" {
            let calendar = Calendar.current
            let requestedStart = apiDate(
                from: request.query["start_date"] ?? request.query["start"]
            ) ?? selectedDate
            let requestedEnd = apiDate(
                from: request.query["end_date"] ?? request.query["end"]
            ) ?? requestedStart
            let startDate = calendar.startOfDay(for: min(requestedStart, requestedEnd))
            let endDate = calendar.startOfDay(for: max(requestedStart, requestedEnd))
            let dates = reportDates(from: startDate, through: endDate)
            guard dates.count <= 32 else {
                return .error("Activity hierarchy supports at most 32 days", statusCode: 400)
            }

            var options = ActivityHierarchyBuilder.Options()
            options.blockSize = request.query["block_size"] ?? "total"
            options.minimumDurationSeconds = max(
                0,
                Int(request.query["minimum_duration_seconds"] ?? "60") ?? 60
            )
            options.groupByProject = apiBoolean(request.query["group_by_project"], default: true)
            options.maxDepth = max(0, Int(request.query["max_depth"] ?? "0") ?? 0)
            options.maxLines = max(1, min(1_000, Int(request.query["max_lines"] ?? "100") ?? 100))
            options.includeMobileDevices = apiBoolean(
                request.query["include_mobile_devices"],
                default: false
            )
            options.includeSubprojects = apiBoolean(
                request.query["include_subprojects"],
                default: true
            )
            options.includeUnassigned = apiBoolean(
                request.query["include_unassigned"],
                default: true
            )
            if let rawProjectIDs = request.query["project_ids"] ?? request.query["projects"] {
                for rawProjectID in rawProjectIDs.split(separator: ",") {
                    let value = String(rawProjectID).trimmingCharacters(in: .whitespacesAndNewlines)
                    if value == "0" {
                        options.onlyUnassigned = true
                    } else if let projectID = apiProjectID(value) {
                        options.projectIDs.insert(projectID)
                    }
                }
            }

            let activityDays = dates.map { date in
                (
                    date: date,
                    segments: effectiveActivitySegments(for: date)
                )
            }
            return .text(
                ActivityHierarchyBuilder.render(
                    activityDays: activityDays,
                    projectStore: projectStore,
                    options: options
                )
            )
        }

        if timingWebAPI, request.method == "GET", path == "/v1/projects/hierarchy" {
            let roots = projectStore.activeProjects
                .filter { $0.parentID == nil }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map(projectHierarchy)
            return .jsonObject([
                "data": roots,
                "links": ["self": "\(localAPIServer.baseEndpoint)/api/v1/projects/hierarchy"]
            ])
        }

        if request.method == "GET", path == "/v1/teams" {
            let teamsPath = timingWebAPI ? "/api/v1/teams" : "/v1/teams"
            return .jsonObject([
                "data": teamStore.activeTeams.map(officialTeam),
                "links": ["self": "\(localAPIServer.baseEndpoint)\(teamsPath)"]
            ])
        }

        if request.method == "GET", path.hasPrefix("/v1/teams/"), path.hasSuffix("/members") {
            let rawTeamID = String(path.dropFirst("/v1/teams/".count))
                .replacingOccurrences(of: "/members", with: "")
            guard let teamID = apiTeamID(rawTeamID), let team = teamStore.team(teamID) else {
                return .error("Team not found", statusCode: 404)
            }
            return .jsonObject([
                "data": team.members.filter(\.isActive).map(officialTeamMember),
                "links": ["self": "\(localAPIServer.baseEndpoint)\(path)"]
            ])
        }

        if request.method == "POST", path == "/v1/teams" {
            guard let body = apiBody(request),
                  let name = body["name"] as? String ?? body["title"] as? String,
                  let teamID = teamStore.createTeam(name: name),
                  let team = teamStore.team(teamID) else {
                return .error("Team needs a name", statusCode: 400)
            }
            return .jsonObject(["data": officialTeam(team)], statusCode: 201)
        }

        if request.method == "POST", path.hasPrefix("/v1/teams/"), path.hasSuffix("/members") {
            let rawTeamID = String(path.dropFirst("/v1/teams/".count))
                .replacingOccurrences(of: "/members", with: "")
            guard let teamID = apiTeamID(rawTeamID), teamStore.team(teamID) != nil,
                  let body = apiBody(request),
                  let name = body["name"] as? String else {
                return .error("Member body needs a team and name", statusCode: 400)
            }
            guard let memberID = teamStore.addMember(
                to: teamID,
                name: name,
                email: body["email"] as? String ?? ""
            ),
            let member = teamStore.team(teamID)?.members.first(where: { $0.id == memberID }) else {
                return .error("Team member could not be added", statusCode: 400)
            }
            return .jsonObject(["data": officialTeamMember(member)], statusCode: 201)
        }

        if request.method == "DELETE", path.hasPrefix("/v1/teams/"), !path.hasSuffix("/members") {
            let rawTeamID = String(path.dropFirst("/v1/teams/".count))
            guard let teamID = apiTeamID(rawTeamID), let team = teamStore.team(teamID) else {
                return .error("Team not found", statusCode: 404)
            }
            teamStore.archive(team)
            return .empty()
        }

        if timingWebAPI, request.method == "GET", path == "/v1/projects" {
            let includeArchived = apiBoolean(request.query["include_archived"], default: false)
            let projects = includeArchived ? projectStore.projects : projectStore.activeProjects
            return .jsonObject([
                "data": projects.map(officialProject),
                "links": ["self": "\(localAPIServer.baseEndpoint)/api/v1/projects"]
            ])
        }

        if timingWebAPI, request.method == "POST", path == "/v1/projects" {
            guard let body = apiBody(request),
                  let title = (body["title"] as? String ?? body["name"] as? String),
                  let projectID = projectStore.createProject(
                      name: title,
                      parentID: (body["parent"] as? String).flatMap(apiProjectID),
                      teamID: (body["team_id"] as? String).flatMap(apiTeamID)
                  ),
                  var project = projectStore.project(projectID) else {
                return .error("Project needs a title", statusCode: 400)
            }
            if let notes = body["notes"] as? String { project.notes = notes }
            if let color = body["color"] as? String, let value = projectColor(from: color) { project.color = value }
            if let productivity = body["productivity"] as? Int { project.productivity = productivity }
            if let productivityScore = body["productivity_score"] as? Double {
                project.productivity = Int((productivityScore * 100).rounded())
            }
            if let rate = body["billing_rate"] as? Double { project.billingRate = rate }
            if let currency = body["currency"] as? String { project.currency = currency }
            if let archived = body["is_archived"] as? Bool { project.isArchived = archived }
            if let fields = validatedCustomFields(body["custom_fields"]) { project.customFields = fields }
            if let billing = (body["default_billing_status"] as? String ?? body["billing_status"] as? String),
               let status = projectBillingStatus(from: billing) {
                project.defaultBillingStatus = status
            }
            projectStore.updateProject(project)
            if body["add_default_name_rules"] as? Bool == true {
                _ = projectStore.addDefaultNameRules(projectID: projectID, projectName: title)
            }
            return .jsonObject(["data": officialProject(projectStore.project(projectID) ?? project)], statusCode: 201)
        }

        if timingWebAPI, path.hasPrefix("/v1/projects/") {
            let rawID = String(path.dropFirst("/v1/projects/".count))
                .replacingOccurrences(of: "/projects/", with: "")
            guard let projectID = apiProjectID(rawID),
                  let project = projectStore.project(projectID) else {
                return .error("Project not found", statusCode: 404)
            }
            if request.method == "GET" {
                return .jsonObject(["data": officialProject(project)])
            }
            if request.method == "PATCH" || request.method == "PUT" {
                guard let body = apiBody(request) else {
                    return .error("Project body is invalid", statusCode: 400)
                }
                var updated = project
                if let title = body["title"] as? String { updated.name = title }
                if let notes = body["notes"] as? String { updated.notes = notes }
                if let color = body["color"] as? String, let value = projectColor(from: color) { updated.color = value }
                if let productivity = body["productivity"] as? Int { updated.productivity = productivity }
                if let productivityScore = body["productivity_score"] as? Double {
                    updated.productivity = Int((productivityScore * 100).rounded())
                }
                if let rate = body["billing_rate"] as? Double { updated.billingRate = rate }
                if let currency = body["currency"] as? String { updated.currency = currency }
                if let archived = body["is_archived"] as? Bool { updated.isArchived = archived }
                if body.keys.contains("team_id") {
                    updated.teamID = apiTeamIDValue(body["team_id"])
                }
                applyCustomFieldPatch(&updated.customFields, rawValue: body["custom_fields"])
                if let billing = body["default_billing_status"] as? String,
                   let status = projectBillingStatus(from: billing) {
                    updated.defaultBillingStatus = status
                }
                if body.keys.contains("parent") {
                    updated.parentID = apiProjectIDValue(body["parent"])
                }
                projectStore.updateProject(updated)
                return .jsonObject(["data": officialProject(projectStore.project(projectID) ?? updated)])
            }
            if request.method == "DELETE" {
                projectStore.archive(project)
                return .empty()
            }
        }

        if timingWebAPI, request.method == "GET", path == "/v1/time-entries/latest" {
            guard let entry = timeEntryStore.materializedEntries().max(by: { $0.end < $1.end }) else {
                return .error("No time entries found", statusCode: 404)
            }
            return .jsonObject(["data": officialEntry(entry)])
        }

        if timingWebAPI, request.method == "GET", path == "/v1/time-entries/running" {
            guard let timer = timeEntryStore.runningTimer else {
                return .error("No running timer found", statusCode: 404)
            }
            let entry = TimeEntry(
                id: timer.id,
                projectID: timer.projectID,
                title: timer.title,
                notes: timer.notes,
                start: timer.startedAt,
                end: max(.now, timer.startedAt.addingTimeInterval(60)),
                billingStatus: timer.billingStatus,
                isManual: false,
                customFields: timer.customFields
            )
            return .jsonObject(["data": officialEntry(entry, isRunning: true)])
        }

        if timingWebAPI, request.method == "GET", path == "/v1/time-entries" {
            let calendar = Calendar.current
            let defaultStart = calendar.date(byAdding: .day, value: -30, to: .now) ?? .now
            let startDate = apiDate(from: request.query["start_date_min"]) ?? defaultStart
            let endDate = apiDate(from: request.query["start_date_max"])
                .flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
                ?? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
            let requestedProject = request.query["project"] ?? request.query["projects"]
            let requestedBilling = request.query["billing_status"]
            let search = request.query["search_query"]?.lowercased()
            let entries = timeEntryStore.materializedEntries().filter { entry in
                guard entry.start >= startDate, entry.start < endDate else { return false }
                if let requestedProject, !requestedProject.isEmpty,
                   apiProjectID(requestedProject) != entry.projectID {
                    return false
                }
                if let requestedBilling, !requestedBilling.isEmpty,
                   entryBillingStatus(from: requestedBilling) != entry.billingStatus {
                    return false
                }
                if let search, !search.isEmpty,
                   !"\(entry.title) \(entry.notes)".lowercased().contains(search) {
                    return false
                }
                return true
            }
            .sorted { $0.start > $1.start }
            return .jsonObject([
                "data": entries.map { officialEntry($0, isRunning: $0.id == timeEntryStore.runningTimer?.id) },
                "links": ["self": "\(localAPIServer.baseEndpoint)/api/v1/time-entries"]
            ])
        }

        if timingWebAPI, request.method == "PATCH", path == "/v1/time-entries/batch-update" {
            guard let body = apiBody(request),
                  let rawTimeEntries = body["time_entries"] as? [Any],
                  !rawTimeEntries.isEmpty else {
                return .error("Batch update needs a time_entries array", statusCode: 400)
            }
            let ids = rawTimeEntries.compactMap { value -> UUID? in
                if let rawID = value as? String {
                    return UUID(uuidString: rawID.replacingOccurrences(of: "/time-entries/", with: ""))
                }
                if let object = value as? [String: Any], let rawID = object["id"] as? String {
                    return UUID(uuidString: rawID.replacingOccurrences(of: "/time-entries/", with: ""))
                }
                return nil
            }
            guard !ids.isEmpty else {
                return .error("Batch update contains no valid time-entry IDs", statusCode: 400)
            }
            let updateData = body["data"] as? [String: Any] ?? [:]
            let matches = timeEntryStore.entries.filter { ids.contains($0.id) }
            guard !matches.isEmpty else {
                return .error("No matching time entries found", statusCode: 404)
            }
            var updatedEntries: [TimeEntry] = []
            for entry in matches {
                var updated = entry
                if let title = updateData["title"] as? String { updated.title = title }
                if let notes = updateData["notes"] as? String { updated.notes = notes }
                if updateData.keys.contains("project") {
                    updated.projectID = apiProjectIDValue(updateData["project"])
                }
                if updateData["billing_status"] != nil || updateData["billingStatus"] != nil {
                    updated.billingStatus = entryBillingStatus(
                        from: updateData["billing_status"] as? String ?? updateData["billingStatus"] as? String,
                        projectID: updated.projectID
                    )
                }
                applyCustomFieldPatch(&updated.customFields, rawValue: updateData["custom_fields"])
                timeEntryStore.update(updated)
                updatedEntries.append(updated)
            }
            return .jsonObject([
                "data": updatedEntries.map { officialEntry($0) },
                "message": "Updated \(updatedEntries.count) time entries."
            ])
        }

        if timingWebAPI, path.hasPrefix("/v1/time-entries/") {
            let rawID = String(path.dropFirst("/v1/time-entries/".count))
                .replacingOccurrences(of: "/time-entries/", with: "")
            guard let id = UUID(uuidString: rawID),
                  let existing = timeEntryStore.entries.first(where: { $0.id == id }) else {
                return .error("Time entry not found", statusCode: 404)
            }
            if request.method == "GET" {
                return .jsonObject(["data": officialEntry(existing)])
            }
            if request.method == "PATCH" || request.method == "PUT" {
                guard let body = apiBody(request) else {
                    return .error("Time-entry body is invalid", statusCode: 400)
                }
                var updated = existing
                if let title = body["title"] as? String { updated.title = title }
                if let notes = body["notes"] as? String { updated.notes = notes }
                if let rawStart = body["start_date"] as? String,
                   let start = parseCommandDate(rawStart) { updated.start = start }
                if let rawEnd = body["end_date"] as? String,
                   let end = parseCommandDate(rawEnd) { updated.end = end }
                if body.keys.contains("project") {
                    updated.projectID = apiProjectIDValue(body["project"])
                }
                if body["billing_status"] != nil || body["billingStatus"] != nil {
                    updated.billingStatus = entryBillingStatus(
                        from: body["billing_status"] as? String ?? body["billingStatus"] as? String,
                        projectID: updated.projectID
                    )
                }
                applyCustomFieldPatch(&updated.customFields, rawValue: body["custom_fields"])
                guard updated.end > updated.start else {
                    return .error("Time entry has an invalid time range", statusCode: 400)
                }
                var splitFragments: [TimeEntry] = []
                if body["replace_overlapping"] as? Bool == true {
                    let overlapping = timeEntryStore.entries(
                        overlapping: updated.start,
                        end: updated.end,
                        excluding: existing.id
                    )
                    splitFragments = timeEntryStore.splitOverlappingEntries(
                        overlapping,
                        excluding: [(start: updated.start, end: updated.end)]
                    )
                }
                timeEntryStore.update(updated)
                return .jsonObject([
                    "data": officialEntry(updated),
                    "split_fragments": splitFragments.map { officialEntry($0) }
                ])
            }
            if request.method == "DELETE" {
                timeEntryStore.delete(existing)
                return .empty()
            }
        }

        if timingWebAPI, request.method == "POST", path == "/v1/time-entries" {
            guard let body = apiBody(request) else {
                return .error("Time-entry body is invalid", statusCode: 400)
            }
            let title = body["title"] as? String ?? ""
            let project = (body["project"] as? String).flatMap(apiProjectID)
                ?? projectID(for: body["projectID"] as? String)
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || project != nil else {
                return .error("Time entry needs a title", statusCode: 400)
            }
            let notes = body["notes"] as? String ?? ""
            let customFields = validatedCustomFields(body["custom_fields"]) ?? [:]
            let billing = entryBillingStatus(
                from: body["billing_status"] as? String ?? body["billingStatus"] as? String,
                projectID: project
            )
            let start = (body["start_date"] as? String).flatMap(parseCommandDate)
                ?? (body["start"] as? String).flatMap(parseCommandDate)
                ?? .now
            let estimatedDurationSeconds = (body["estimated_duration_seconds"] as? Int)
                ?? (body["estimatedDurationSeconds"] as? Int)
                ?? (body["estimated_minutes"] as? Int).map { $0 * 60 }
            if body["is_running"] as? Bool == true {
                timeEntryStore.startTimer(
                    title: title,
                    projectID: project,
                    notes: notes,
                    startedAt: start,
                    estimatedDurationSeconds: estimatedDurationSeconds,
                    billingStatus: billing,
                    customFields: customFields
                )
                guard let timer = timeEntryStore.runningTimer else {
                    return .error("Timer could not be started", statusCode: 500)
                }
                return .jsonObject([
                    "data": officialEntry(
                        TimeEntry(
                            id: timer.id,
                            projectID: timer.projectID,
                            title: timer.title,
                            notes: timer.notes,
                            start: timer.startedAt,
                            end: max(.now, timer.startedAt.addingTimeInterval(60)),
                            billingStatus: timer.billingStatus,
                            isManual: false,
                            customFields: timer.customFields
                        ),
                        isRunning: true
                    )
                ], statusCode: 201)
            }
            let end = (body["end_date"] as? String).flatMap(parseCommandDate)
                ?? (body["end"] as? String).flatMap(parseCommandDate)
                ?? start.addingTimeInterval(TimeInterval(max(1, body["minutes"] as? Int ?? 60) * 60))
            var splitFragments: [TimeEntry] = []
            if body["replace_overlapping"] as? Bool == true {
                let overlapping = timeEntryStore.entries(overlapping: start, end: end)
                splitFragments = timeEntryStore.splitOverlappingEntries(
                    overlapping,
                    excluding: [(start: start, end: end)]
                )
            }
            guard let id = timeEntryStore.addEntry(
                title: title,
                projectID: project,
                notes: notes,
                start: start,
                end: end,
                billingStatus: billing,
                customFields: customFields
            ), let entry = timeEntryStore.entries.first(where: { $0.id == id }) else {
                return .error("Time entry has an invalid time range", statusCode: 400)
            }
            return .jsonObject([
                "data": officialEntry(entry),
                "split_fragments": splitFragments.map { officialEntry($0) }
            ], statusCode: 201)
        }

        if request.method == "GET", path == "/v1/sync/status" {
            return .jsonObject([
                "enabled": syncStore.isEnabled,
                "deviceID": syncStore.deviceID,
                "deviceName": syncStore.deviceName,
                "folder": syncStore.folderURL?.path ?? NSNull(),
                "lastSyncAt": syncStore.lastSyncAt.map(apiDate) ?? NSNull(),
                "backupCount": syncStore.backupCount,
                "status": syncStore.statusMessage
            ])
        }

        if request.method == "GET", path == "/v1/integrations" {
            let integrations = ExternalIntegrationProvider.allCases.map { provider -> [String: Any] in
                let configuration = integrationStore.configuration(for: provider)
                var result: [String: Any] = [
                    "provider": provider.rawValue,
                    "title": provider.title,
                    "workspace": configuration.workspace,
                    "endpoint": configuration.endpoint,
                    "connected": configuration.connected,
                    "last_sync_at": configuration.lastSyncAt.map(apiDate) ?? NSNull(),
                    "status": configuration.statusMessage,
                    "token_stored_in_keychain": !integrationStore.token(for: provider).isEmpty,
                    "last_sync_conflict_count": configuration.lastSyncConflictCount ?? 0
                ]
                for (key, value) in integrationStore.syncStatus(for: provider) {
                    result[key] = value
                }
                return result
            }
            return .jsonObject([
                "data": integrations,
                "status": integrationStore.statusMessage,
                "network_access": "on demand"
            ])
        }

        if request.method == "GET", path.hasPrefix("/v1/integrations/"), !path.hasSuffix("/sync") {
            let rawProvider = String(path.dropFirst("/v1/integrations/".count))
            guard let provider = ExternalIntegrationProvider(rawValue: rawProvider) else {
                return .error("Integration provider not found", statusCode: 404)
            }
            let configuration = integrationStore.configuration(for: provider)
            var response: [String: Any] = [
                "provider": provider.rawValue,
                "title": provider.title,
                "workspace": configuration.workspace,
                "endpoint": configuration.endpoint,
                "connected": configuration.connected,
                "last_sync_at": configuration.lastSyncAt.map(apiDate) ?? NSNull(),
                "status": configuration.statusMessage,
                "token_stored_in_keychain": !integrationStore.token(for: provider).isEmpty,
                "last_sync_conflict_count": configuration.lastSyncConflictCount ?? 0
            ]
            for (key, value) in integrationStore.syncStatus(for: provider) {
                response[key] = value
            }
            return .jsonObject(["data": response])
        }

        if request.method == "POST", path.hasPrefix("/v1/integrations/"), path.hasSuffix("/sync") {
            let prefix = "/v1/integrations/"
            let rawProvider = String(path.dropFirst(prefix.count)).replacingOccurrences(of: "/sync", with: "")
            guard let provider = ExternalIntegrationProvider(rawValue: rawProvider) else {
                return .error("Integration provider not found", statusCode: 404)
            }
            guard !integrationStore.isWorking else {
                return .error("Another integration request is already running", statusCode: 409)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                _ = await self.integrationStore.syncProjects(from: provider, with: self.projectStore)
            }
            return .jsonObject([
                "provider": provider.rawValue,
                "accepted": true,
                "status": "sync started",
                "poll": "/v1/integrations/\(provider.rawValue)"
            ], statusCode: 202)
        }

        if request.method == "POST", path == "/v1/sync/now" {
            let succeeded = syncStore.syncNow()
            return .jsonObject(["synced": succeeded, "status": syncStore.statusMessage])
        }

        if request.method == "POST", path == "/v1/sync/restore" {
            let restored = syncStore.restoreLatestBackup()
            return .jsonObject([
                "restored": restored,
                "backupCount": syncStore.backupCount,
                "status": syncStore.statusMessage
            ], statusCode: restored ? 200 : 409)
        }

        if request.method == "GET", (path == "/v1/projects" || path == "/v1/projects/export") {
            do {
                return .json(try projectStore.exportArchiveData())
            } catch {
                return .error("Projects could not be exported", statusCode: 500)
            }
        }

        if request.method == "POST", path == "/v1/projects/import" {
            do {
                let result = try projectStore.importArchiveData(request.body)
                return .jsonObject([
                    "projectsImported": result.projects,
                    "rulesImported": result.rules
                ], statusCode: 201)
            } catch {
                return .error("Project archive is invalid", statusCode: 400)
            }
        }

        if (request.method == "PATCH" || request.method == "PUT"), path.hasPrefix("/v1/activities/") {
            let rawID = String(path.dropFirst("/v1/activities/".count))
            guard let activityID = UUID(uuidString: rawID), let body = apiBody(request) else {
                return .error("Activity assignment body is invalid", statusCode: 400)
            }
            let rawProject = (body["projectID"] as? String) ?? (body["project_id"] as? String) ?? (body["project"] as? String)
            let resolvedProjectID: UUID?
            if let rawProject, !rawProject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let resolved = projectID(for: rawProject) else {
                    return .error("Project not found", statusCode: 404)
                }
                resolvedProjectID = resolved
            } else {
                resolvedProjectID = nil
            }
            let date = apiDate(from: request.query["date"]) ?? selectedDate
            if activityMonitor.segments(for: date).contains(where: { $0.id == activityID }) {
                activityMonitor.assignActivity(activityID, to: resolvedProjectID, date: date)
            } else if screenTimeStore.segments(for: date).contains(where: { $0.id == activityID }) {
                screenTimeStore.assignActivity(activityID, to: resolvedProjectID, date: date)
            } else {
                return .error("Activity not found", statusCode: 404)
            }
            guard let updated = rawActivitySegments(for: date).first(where: { $0.id == activityID }) else {
                return .error("Activity could not be reloaded", statusCode: 500)
            }
            return .jsonObject(apiActivity(updated, date: date))
        }

        if request.method == "DELETE", path.hasPrefix("/v1/activities/") {
            let rawID = String(path.dropFirst("/v1/activities/".count))
            guard let activityID = UUID(uuidString: rawID) else {
                return .error("Activity ID is invalid", statusCode: 400)
            }
            let date = apiDate(from: request.query["date"]) ?? selectedDate
            let deleted: [ActivitySegment]
            if activityMonitor.segments(for: date).contains(where: { $0.id == activityID }) {
                deleted = activityMonitor.deleteActivities([activityID], date: date)
            } else if screenTimeStore.segments(for: date).contains(where: { $0.id == activityID }) {
                deleted = screenTimeStore.deleteActivities([activityID], date: date)
            } else {
                return .error("Activity not found", statusCode: 404)
            }
            guard !deleted.isEmpty else {
                return .error("Activity could not be deleted", statusCode: 500)
            }
            return .jsonObject([
                "deleted": deleted.map { $0.id.uuidString },
                "date": apiDayKey(date)
            ])
        }

        if request.method == "GET", path == "/v1/activities" {
            let date = apiDate(from: request.query["date"]) ?? selectedDate
            do {
                let activities = rawActivitySegments(for: date).sorted {
                    if $0.startSecond == $1.startSecond { return $0.endSecond < $1.endSecond }
                    return $0.startSecond < $1.startSecond
                }
                return .json(try JSONSerialization.data(withJSONObject: activities.map { apiActivity($0, date: date) }))
            } catch {
                return .error("Activities could not be encoded", statusCode: 500)
            }
        }

        if request.method == "GET", path == "/v1/phone-calls" {
            let date = apiDate(from: request.query["date"]) ?? selectedDate
            let calls = phoneCallStore.calls(for: date)
            return .jsonObject([
                "date": apiDayKey(date),
                "data": calls.map(apiPhoneCall),
                "hidden_addresses": Array(phoneCallStore.hiddenAddresses).sorted(),
                "source": "macOS CallHistory",
                "read_only": true
            ])
        }

        if request.method == "GET", path == "/v1/calendar-events" {
            let date = apiDate(from: request.query["date"]) ?? selectedDate
            calendarStore.loadEvents(for: date)
            return .jsonObject([
                "date": apiDayKey(date),
                "data": calendarStore.events.map(apiCalendarEvent),
                "authorized": calendarStore.isAuthorized,
                "status": calendarStore.statusMessage,
                "read_only": true
            ])
        }

        if request.method == "POST", path == "/v1/calendar-events" {
            guard let body = apiBody(request),
                  let title = stringArgument(body, "title"),
                  let startValue = stringArgument(body, "start"),
                  let endValue = stringArgument(body, "end"),
                  let start = parseCommandDate(startValue),
                  let end = parseCommandDate(endValue),
                  end > start else {
                return .error("Calendar event needs a title and valid start/end", statusCode: 400)
            }
            let notes = stringArgument(body, "notes") ?? ""
            guard calendarStore.createEvent(title: title, start: start, end: end, notes: notes) else {
                return .error(calendarStore.statusMessage, statusCode: 403)
            }
            let date = apiDate(from: stringArgument(body, "date")) ?? start
            calendarStore.loadEvents(for: date)
            return .jsonObject([
                "date": apiDayKey(date),
                "data": calendarStore.events.map(apiCalendarEvent),
                "authorized": calendarStore.isAuthorized,
                "status": calendarStore.statusMessage
            ])
        }

        if path.hasPrefix("/v1/calendar-events/"),
           let eventID = path.split(separator: "/").last.map(String.init),
           (request.method == "PATCH" || request.method == "PUT") {
            guard let body = apiBody(request),
                  let title = stringArgument(body, "title"),
                  let startValue = stringArgument(body, "start"),
                  let endValue = stringArgument(body, "end"),
                  let start = parseCommandDate(startValue),
                  let end = parseCommandDate(endValue),
                  end > start else {
                return .error("Calendar event needs a title and valid start/end", statusCode: 400)
            }
            guard calendarStore.updateEvent(
                id: eventID,
                title: title,
                start: start,
                end: end,
                notes: stringArgument(body, "notes") ?? ""
            ) else {
                return .error(calendarStore.statusMessage, statusCode: 403)
            }
            let date = apiDate(from: stringArgument(body, "date")) ?? start
            calendarStore.loadEvents(for: date)
            return .jsonObject([
                "date": apiDayKey(date),
                "data": calendarStore.events.map(apiCalendarEvent),
                "authorized": calendarStore.isAuthorized,
                "status": calendarStore.statusMessage
            ])
        }

        if request.method == "DELETE", path.hasPrefix("/v1/calendar-events/"),
           let eventID = path.split(separator: "/").last.map(String.init) {
            guard calendarStore.deleteEvent(id: eventID) else {
                return .error(calendarStore.statusMessage, statusCode: 403)
            }
            let date = apiDate(from: request.query["date"]) ?? selectedDate
            calendarStore.loadEvents(for: date)
            return .jsonObject([
                "date": apiDayKey(date),
                "data": calendarStore.events.map(apiCalendarEvent),
                "authorized": calendarStore.isAuthorized,
                "status": calendarStore.statusMessage
            ])
        }

        if request.method == "GET", path == "/v1/reminders" {
            let date = apiDate(from: request.query["date"]) ?? selectedDate
            reminderStore.loadCompleted(for: date)
            return .jsonObject([
                "date": apiDayKey(date),
                "data": reminderStore.reminders.map(apiReminder),
                "authorized": reminderStore.isAuthorized,
                "status": reminderStore.statusMessage,
                "read_only": true
            ])
        }

        if request.method == "GET", path == "/v1/screen-time" {
            let date = apiDate(from: request.query["date"]) ?? selectedDate
            screenTimeStore.load(for: date)
            let segments = screenTimeStore.segments(for: date)
            return .jsonObject([
                "date": apiDayKey(date),
                "data": segments.map { apiActivity($0, date: date) },
                "database_available": screenTimeStore.databaseAvailable,
                "status": screenTimeStore.statusMessage,
                "read_only": true
            ])
        }

        if request.method == "POST", path == "/v1/phone-calls/hide" {
            guard let body = apiBody(request),
                  let address = body["address"] as? String,
                  !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .error("Phone-call hide body needs an address", statusCode: 400)
            }
            phoneCallStore.setAddressHidden(address, hidden: body["hidden"] as? Bool ?? true)
            return .jsonObject([
                "address": address,
                "hidden": phoneCallStore.isAddressHidden(address),
                "hidden_addresses": Array(phoneCallStore.hiddenAddresses).sorted()
            ])
        }

        if request.method == "POST", path == "/v1/phone-calls/hide-all" {
            phoneCallStore.showAllAddresses()
            return .jsonObject([
                "hidden_addresses": Array(phoneCallStore.hiddenAddresses).sorted()
            ])
        }

        if request.method == "GET", path == "/v1/insights" {
            let date = apiDate(from: request.query["date"]) ?? selectedDate
            let segments = effectiveActivitySegments(for: date)
            let insights = ActivityInsights.generate(from: segments)
            let data = insights.map { insight -> [String: Any] in
                let sourceLabel: String
                switch insight.source {
                case "screen_time": sourceLabel = "Screen Time import"
                case "mixed_sources": sourceLabel = "Local activity + Screen Time"
                default: sourceLabel = "Local activity monitor"
                }
                return [
                    "id": insight.id,
                    "title": insight.title,
                    "detail": insight.detail,
                    "symbol": insight.symbol,
                    "source": insight.source,
                    "source_label": sourceLabel,
                    "duration_seconds": insight.durationSeconds.map { $0 } ?? NSNull(),
                    "date": apiDayKey(date),
                    "scope": "selected_day",
                    "generated_by": "metriday.local.activity-insights"
                ]
            }
            return .jsonObject([
                "date": apiDayKey(date),
                "data": data,
                "generated_by": "metriday.local.activity-insights",
                "network_access": false
            ])
        }

        if request.method == "GET", path == "/v1/reports" {
            let calendar = Calendar.current
            let requestedStart = apiDate(
                from: request.query["start_date"] ?? request.query["start"]
            ) ?? selectedDate
            let requestedEnd = apiDate(
                from: request.query["end_date"] ?? request.query["end"]
            ) ?? requestedStart
            let startDate = calendar.startOfDay(for: min(requestedStart, requestedEnd))
            let endDate = calendar.startOfDay(for: max(requestedStart, requestedEnd))
            let dates = reportDates(from: startDate, through: endDate)
            let options = reportOptions(from: request.query)
            let activityDays = dates.map { date in
                (
                    date: date,
                    segments: effectiveActivitySegments(for: date)
                )
            }
            let reportEnd = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
            let entries = timeEntryStore.materializedEntries().filter {
                $0.start < reportEnd && $0.end > startDate
            }
            let format = ReportFileFormat(rawValue: request.query["format"]?.lowercased() ?? "json") ?? .json
            do {
                let body: Data
                let contentType: String
                switch format {
                case .csv:
                    body = Data(ReportExporter.csv(
                        activityDays: activityDays,
                        timeEntries: entries,
                        projectStore: projectStore,
                        options: options
                    ).utf8)
                    contentType = "text/csv; charset=utf-8"
                case .json:
                    body = try ReportExporter.json(
                        activityDays: activityDays,
                        timeEntries: entries,
                        projectStore: projectStore,
                        options: options
                    )
                    contentType = "application/json; charset=utf-8"
                case .html:
                    body = Data(ReportExporter.html(
                        activityDays: activityDays,
                        timeEntries: entries,
                        projectStore: projectStore,
                        options: options
                    ).utf8)
                    contentType = "text/html; charset=utf-8"
                case .xlsx, .pdf:
                    let temporaryURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("metriday-report-\(UUID().uuidString)")
                        .appendingPathExtension(format.fileExtension)
                    defer { try? FileManager.default.removeItem(at: temporaryURL) }
                    try ReportExporter.write(
                        to: temporaryURL,
                        format: format,
                        activityDays: activityDays,
                        timeEntries: entries,
                        projectStore: projectStore,
                        options: options
                    )
                    body = try Data(contentsOf: temporaryURL)
                    contentType = format == .xlsx
                        ? "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                        : "application/pdf"
                }
                return LocalAPIResponse(statusCode: 200, contentType: contentType, body: body)
            } catch {
                return .error("Report could not be generated", statusCode: 500)
            }
        }

        if request.method == "GET", (path == "/v1/time-entries" || path == "/v1/time-entries/export") {
            if path.hasSuffix("/export") {
                do {
                    return .json(try timeEntryStore.exportArchiveData())
                } catch {
                    return .error("Time entries could not be exported", statusCode: 500)
                }
            }
            let date = apiDate(from: request.query["date"]) ?? selectedDate
            let calendar = Calendar.current
            let dayStart = calendar.startOfDay(for: date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let entries = timeEntryStore.materializedEntries().filter {
                $0.start < dayEnd && $0.end > dayStart
            }
            return .jsonObject(["date": apiDate(date), "entries": entries.map(apiEntry)])
        }

        if request.method == "POST", path == "/v1/time-entries/import" {
            do {
                let imported = try timeEntryStore.importArchiveData(request.body)
                return .jsonObject(["entriesImported": imported], statusCode: 201)
            } catch {
                return .error("Time-entry archive is invalid", statusCode: 400)
            }
        }

        if request.method == "DELETE", path.hasPrefix("/v1/time-entries/") {
            let rawID = String(path.dropFirst("/v1/time-entries/".count))
            guard let id = UUID(uuidString: rawID),
                  let entry = timeEntryStore.entries.first(where: { $0.id == id }) else {
                return .error("Time entry not found", statusCode: 404)
            }
            timeEntryStore.delete(entry)
            return .empty()
        }

        if request.method == "POST", path == "/v1/tracking/pause" {
            if activityMonitor.isTracking { activityMonitor.stop() }
            markdownStore.statusMessage = "Tracking paused by local API"
            return .jsonObject(["tracking": false])
        }
        if request.method == "POST", path == "/v1/tracking/resume" {
            if !activityMonitor.isTracking { activityMonitor.start() }
            markdownStore.statusMessage = "Tracking resumed by local API"
            return .jsonObject(["tracking": true])
        }
        if request.method == "POST", path == "/v1/tracking/toggle" {
            activityMonitor.toggleTracking()
            return .jsonObject(["tracking": activityMonitor.isTracking])
        }

        if request.method == "POST", path == "/v1/timer/stop" {
            guard let id = timeEntryStore.stopTimer() else {
                return .error("No running timer", statusCode: 409)
            }
            return .jsonObject(["id": id.uuidString, "stopped": true])
        }

        if request.method == "POST", path == "/v1/timer/start" {
            guard let body = apiBody(request),
                  let title = body["title"] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .error("Timer start needs a title", statusCode: 400)
            }
            let project = projectID(for: body["projectID"] as? String ?? body["project"] as? String)
            let notes = body["notes"] as? String ?? ""
            let customFields = validatedCustomFields(body["customFields"] ?? body["custom_fields"]) ?? [:]
            let billingStatus = entryBillingStatus(from: body["billingStatus"] as? String, projectID: project)
            let startedAt = (body["startedAt"] as? String).flatMap(parseCommandDate) ?? .now
            let estimatedDurationSeconds = (body["estimatedDurationSeconds"] as? Int)
                ?? (body["estimated_duration_seconds"] as? Int)
                ?? (body["estimatedMinutes"] as? Int).map { $0 * 60 }
            timeEntryStore.startTimer(
                title: title,
                projectID: project,
                notes: notes,
                startedAt: startedAt,
                estimatedDurationSeconds: estimatedDurationSeconds,
                billingStatus: billingStatus,
                customFields: customFields
            )
            guard let timer = timeEntryStore.runningTimer else {
                return .error("Timer could not be started", statusCode: 500)
            }
            return .jsonObject([
                "id": timer.id.uuidString,
                "title": timer.title,
                "startedAt": apiDate(timer.startedAt),
                "estimatedDurationSeconds": timer.estimatedDurationSeconds.map { $0 as Any } ?? NSNull(),
                "billingStatus": entryBillingStatusRaw(timer.billingStatus)
            ], statusCode: 201)
        }

        if request.method == "POST", path == "/v1/timer/adjust" {
            guard timeEntryStore.runningTimer != nil,
                  let body = apiBody(request) else {
                return .error("Timer adjustment needs seconds or minutes", statusCode: 400)
            }
            if body["align_previous_entry"] as? Bool == true {
                guard timeEntryStore.moveRunningTimerStartToPreviousEntryBoundary() else {
                    return .error("No previous time-entry boundary is available", statusCode: 409)
                }
            } else if let seconds = (body["seconds"] as? Int)
                        ?? (body["minutes"] as? Int).map({ $0 * 60 }) {
                timeEntryStore.adjustRunningTimerStart(by: TimeInterval(seconds))
            } else {
                return .error("Timer adjustment needs seconds, minutes, or align_previous_entry", statusCode: 400)
            }
            guard let timer = timeEntryStore.runningTimer else {
                return .error("No running timer", statusCode: 409)
            }
            return .jsonObject([
                "id": timer.id.uuidString,
                "startedAt": apiDate(timer.startedAt),
                "remainingSeconds": timeEntryStore.runningTimerRemainingSeconds.map { $0 as Any } ?? NSNull()
            ])
        }

        if request.method == "POST", path == "/v1/timer/estimate" {
            guard timeEntryStore.runningTimer != nil,
                  let body = apiBody(request) else {
                return .error("No running timer", statusCode: 409)
            }
            if let deltaSeconds = (body["deltaSeconds"] as? Int) ?? (body["delta_seconds"] as? Int) {
                timeEntryStore.adjustRunningTimerEstimate(by: deltaSeconds)
                guard let timer = timeEntryStore.runningTimer else {
                    return .error("No running timer", statusCode: 409)
                }
                return .jsonObject([
                    "id": timer.id.uuidString,
                    "estimatedDurationSeconds": timer.estimatedDurationSeconds.map { $0 as Any } ?? NSNull(),
                    "remainingSeconds": timeEntryStore.runningTimerRemainingSeconds.map { $0 as Any } ?? NSNull()
                ])
            }
            let seconds = (body["estimatedDurationSeconds"] as? Int)
                ?? (body["estimated_duration_seconds"] as? Int)
                ?? (body["estimatedMinutes"] as? Int).map { $0 * 60 }
                ?? (body["estimated_minutes"] as? Int).map { $0 * 60 }
            guard let seconds, seconds > 0 else {
                return .error("Timer estimate needs a positive duration", statusCode: 400)
            }
            timeEntryStore.setRunningTimerEstimate(to: seconds)
            guard let timer = timeEntryStore.runningTimer else {
                return .error("No running timer", statusCode: 409)
            }
            return .jsonObject([
                "id": timer.id.uuidString,
                "estimatedDurationSeconds": timer.estimatedDurationSeconds.map { $0 as Any } ?? NSNull(),
                "remainingSeconds": timeEntryStore.runningTimerRemainingSeconds.map { $0 as Any } ?? NSNull()
            ])
        }

        if request.method == "POST", path == "/v1/time-entries" {
            guard let body = apiBody(request),
                  let title = body["title"] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .error("Time entry needs a title", statusCode: 400)
            }
            let start = (body["start"] as? String).flatMap(parseCommandDate) ?? .now
            let end = (body["end"] as? String).flatMap(parseCommandDate)
                ?? start.addingTimeInterval(TimeInterval(max(1, body["minutes"] as? Int ?? 60) * 60))
            let projectID = projectID(for: body["projectID"] as? String ?? body["project"] as? String)
            var splitFragments: [TimeEntry] = []
            if body["replace_overlapping"] as? Bool == true {
                let overlapping = timeEntryStore.entries(overlapping: start, end: end)
                splitFragments = timeEntryStore.splitOverlappingEntries(
                    overlapping,
                    excluding: [(start: start, end: end)]
                )
            }
            guard let id = timeEntryStore.addEntry(
                title: title,
                projectID: projectID,
                notes: body["notes"] as? String ?? "",
                start: start,
                end: end,
                billingStatus: entryBillingStatus(from: body["billingStatus"] as? String, projectID: projectID),
                customFields: validatedCustomFields(body["customFields"] ?? body["custom_fields"]) ?? [:]
            ) else {
                return .error("Time entry has an invalid time range", statusCode: 400)
            }
            guard let entry = timeEntryStore.entries.first(where: { $0.id == id }) else {
                return .error("Time entry could not be loaded", statusCode: 500)
            }
            return .jsonObject([
                "id": id.uuidString,
                "data": apiEntry(entry),
                "split_fragments": splitFragments.map(apiEntry)
            ], statusCode: 201)
        }

        if request.method == "GET", path == "/v1" {
            return .jsonObject([
                "name": "Metriday Local API",
                "version": "v1",
                "endpoints": [
                    "GET /v1/status",
                    "GET /v1/plans?date=YYYY-MM-DD",
                    "PUT /v1/plans?date=YYYY-MM-DD",
                    "GET /v1/activities?date=YYYY-MM-DD",
                    "PATCH /v1/activities/{id}?date=YYYY-MM-DD",
                    "GET /v1/source-preferences",
                    "PATCH /v1/source-preferences",
                    "POST /v1/source-preferences/access",
                    "GET /v1/phone-calls?date=YYYY-MM-DD",
                    "POST /v1/phone-calls/hide",
                    "POST /v1/phone-calls/hide-all",
                    "GET /v1/calendar-events?date=YYYY-MM-DD",
                    "GET /v1/reminders?date=YYYY-MM-DD",
                    "GET /v1/screen-time?date=YYYY-MM-DD",
                    "GET /v1/reports?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD&format=json",
                    "GET /v1/activity-hierarchy?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD",
                    "GET /v1/rules",
                    "POST /v1/rules",
                    "PATCH /v1/rules/{id}",
                    "DELETE /v1/rules/{id}",
                    "POST /v1/focus",
                    "GET /v1/time-entries?date=YYYY-MM-DD",
                    "POST /v1/time-entries",
                    "POST /v1/timer/start",
                    "POST /v1/timer/stop",
                    "POST /v1/timer/adjust",
                    "POST /v1/timer/estimate",
                    "POST /v1/tracking/pause",
                    "POST /v1/tracking/resume",
                    "GET /v1/projects",
                    "GET /v1/projects/hierarchy",
                    "GET /v1/filters",
                    "POST /v1/filters",
                    "GET /v1/categories",
                    "POST /v1/categories",
                    "PATCH /v1/categories/{id}",
                    "DELETE /v1/categories/{id}",
                    "GET /v1/project-rules",
                    "POST /v1/project-rules",
                    "PATCH /v1/project-rules/{id}",
                    "DELETE /v1/project-rules/{id}",
                    "POST /v1/project-rules/reapply",
                    "POST /v1/project-rules/reapply-all",
                    "GET /v1/exclusions",
                    "POST /v1/exclusions",
                    "GET /v1/teams",
                    "GET /v1/time-entries/export",
                    "GET /v1/sync/status",
                    "GET /v1/integrations",
                    "GET /v1/integrations/{provider}",
                    "POST /v1/integrations/{provider}/sync",
                    "POST /v1/sync/now",
                    "POST /v1/sync/restore"
                ]
            ])
        }

        return request.method == "GET"
            ? .error("Endpoint not found", statusCode: 404)
            : .error("Method not allowed", statusCode: 405)
    }

    private func handleMCP(_ request: LocalAPIRequest) -> LocalAPIResponse {
        guard request.method == "POST" else {
            return .error("MCP endpoint accepts POST JSON-RPC requests", statusCode: 405)
        }
        guard let message = apiBody(request),
              let method = message["method"] as? String else {
            return .error("MCP request must be a JSON-RPC object with a method", statusCode: 400)
        }

        // Notifications intentionally receive an empty response. This is the
        // HTTP equivalent of the MCP transport acknowledging a notification.
        if method.hasPrefix("notifications/") {
            return .empty()
        }

        let id = message["id"] ?? NSNull()
        switch method {
        case "initialize":
            return mcpResponse(id: id, result: [
                "protocolVersion": "2025-06-18",
                "capabilities": ["tools": [:]],
                "serverInfo": [
                    "name": "Metriday",
                    "version": "1.0"
                ],
                "instructions": "Metriday is a local-first Timing-compatible time tracker. Mutating tools change data on this Mac."
            ])
        case "ping":
            return mcpResponse(id: id, result: [:])
        case "tools/list":
            return mcpResponse(id: id, result: [
                "tools": mcpTools()
            ])
        case "tools/call":
            guard let params = message["params"] as? [String: Any],
                  let name = params["name"] as? String else {
                return mcpError(id: id, code: -32602, message: "tools/call needs params.name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            return invokeMCPTool(name: name, arguments: arguments, id: id)
        default:
            return mcpError(id: id, code: -32601, message: "MCP method not found: \(method)")
        }
    }

    private func mcpResponse(id: Any, result: Any) -> LocalAPIResponse {
        .jsonObject([
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ])
    }

    private func mcpError(id: Any, code: Int, message: String) -> LocalAPIResponse {
        .jsonObject([
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": code,
                "message": message
            ]
        ], statusCode: 200)
    }

    private func mcpTools() -> [[String: Any]] {
        let projectID = [
            "type": "string",
            "description": "Metriday project UUID or Timing-style /projects/{uuid} URI"
        ] as [String: Any]
        let entryID = [
            "type": "string",
            "description": "Metriday time-entry UUID or /time-entries/{uuid} URI"
        ] as [String: Any]
        let date = [
            "type": "string",
            "description": "ISO date or ISO-8601 timestamp"
        ] as [String: Any]

        return [
            mcpTool(
                name: "get_activity_hierarchy",
                description: "Review tracked activities grouped by project and application.",
                properties: [
                    "start_date": date,
                    "end_date": date,
                    "project_ids": ["type": "string", "description": "Comma-separated project IDs"],
                    "only_unassigned": ["type": "boolean"]
                ],
                required: []
            ),
            mcpTool(
                name: "list_projects",
                description: "List all active Metriday projects and their hierarchy.",
                properties: [:],
                required: [],
                readOnly: true
            ),
            mcpTool(
                name: "show_project",
                description: "Show one project, including its parents and children.",
                properties: ["project_id": projectID],
                required: ["project_id"],
                readOnly: true
            ),
            mcpTool(
                name: "create_project",
                description: "Create a project, optionally nested below another project or assigned to a team.",
                properties: [
                    "title": ["type": "string"],
                    "parent": projectID,
                    "team_id": ["type": "string"],
                    "notes": ["type": "string"],
                    "billing_rate": ["type": "number"],
                    "currency": ["type": "string"]
                ],
                required: ["title"],
                destructive: true
            ),
            mcpTool(
                name: "update_project",
                description: "Update an existing project's title, notes, billing, team, or custom fields.",
                properties: [
                    "project_id": projectID,
                    "title": ["type": "string"],
                    "notes": ["type": "string"],
                    "team_id": ["type": "string"],
                    "billing_rate": ["type": "number"],
                    "currency": ["type": "string"],
                    "is_archived": ["type": "boolean"],
                    "custom_fields": ["type": "object"]
                ],
                required: ["project_id"],
                destructive: true
            ),
            mcpTool(
                name: "delete_project",
                description: "Archive a project.",
                properties: ["project_id": projectID],
                required: ["project_id"],
                destructive: true
            ),
            mcpTool(
                name: "list_time_entries",
                description: "List manual and timer-created time entries for a date range.",
                properties: [
                    "start_date_min": date,
                    "start_date_max": date,
                    "project": projectID,
                    "billing_status": ["type": "string"]
                ],
                required: [],
                readOnly: true
            ),
            mcpTool(
                name: "show_time_entry",
                description: "Show one time entry.",
                properties: ["time_entry_id": entryID],
                required: ["time_entry_id"],
                readOnly: true
            ),
            mcpTool(
                name: "show_latest_time_entry",
                description: "Show the most recent time entry.",
                properties: [:],
                required: [],
                readOnly: true
            ),
            mcpTool(
                name: "show_running_timer",
                description: "Show the currently running timer.",
                properties: [:],
                required: [],
                readOnly: true
            ),
            mcpTool(
                name: "create_time_entry",
                description: "Create a manual time entry.",
                properties: [
                    "title": ["type": "string"],
                    "project": projectID,
                    "start_date": date,
                    "end_date": date,
                    "minutes": ["type": "integer", "minimum": 1],
                    "notes": ["type": "string"],
                    "billing_status": ["type": "string"],
                    "custom_fields": ["type": "object"]
                ],
                required: ["title"],
                destructive: true
            ),
            mcpTool(
                name: "update_time_entry",
                description: "Edit a time entry.",
                properties: [
                    "time_entry_id": entryID,
                    "title": ["type": "string"],
                    "notes": ["type": "string"],
                    "start_date": date,
                    "end_date": date,
                    "project": projectID,
                    "billing_status": ["type": "string"],
                    "custom_fields": ["type": "object"]
                ],
                required: ["time_entry_id"],
                destructive: true
            ),
            mcpTool(
                name: "delete_time_entry",
                description: "Delete a time entry.",
                properties: ["time_entry_id": entryID],
                required: ["time_entry_id"],
                destructive: true
            ),
            mcpTool(
                name: "batch_update_time_entries",
                description: "Update several time entries with one operation.",
                properties: [
                    "time_entries": ["type": "array", "items": ["type": "string"]],
                    "data": ["type": "object"]
                ],
                required: ["time_entries", "data"],
                destructive: true
            ),
            mcpTool(
                name: "start_timer",
                description: "Start a timer for a title and optional project.",
                properties: [
                    "title": ["type": "string"],
                    "project": projectID,
                    "notes": ["type": "string"],
                    "started_at": date,
                    "billing_status": ["type": "string"]
                ],
                required: ["title"],
                destructive: true
            ),
            mcpTool(
                name: "stop_timer",
                description: "Stop the currently running timer.",
                properties: [:],
                required: [],
                destructive: true
            )
        ]
    }

    private func mcpTool(
        name: String,
        description: String,
        properties: [String: Any],
        required: [String],
        readOnly: Bool = false,
        destructive: Bool = false
    ) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
                "required": required,
                "additionalProperties": false
            ],
            "annotations": [
                "readOnlyHint": readOnly,
                "destructiveHint": destructive
            ]
        ]
    }

    private func invokeMCPTool(
        name: String,
        arguments: [String: Any],
        id: Any
    ) -> LocalAPIResponse {
        let response: LocalAPIResponse
        switch name {
        case "get_activity_hierarchy":
            response = callLocalAPI(
                method: "GET",
                path: "/api/v1/activity-hierarchy",
                query: stringQuery(arguments, keys: ["start_date", "end_date", "project_ids", "only_unassigned"])
            )
        case "list_projects":
            response = callLocalAPI(method: "GET", path: "/api/v1/projects")
        case "show_project":
            guard let rawID = stringArgument(arguments, "project_id") else {
                return mcpError(id: id, code: -32602, message: "project_id is required")
            }
            response = callLocalAPI(method: "GET", path: "/api/v1/projects/\(rawID)")
        case "create_project":
            var body = arguments
            if body["title"] == nil, let name = body["name"] as? String {
                body["title"] = name
            }
            response = callLocalAPI(method: "POST", path: "/api/v1/projects", body: body)
        case "update_project":
            guard let rawID = stringArgument(arguments, "project_id") else {
                return mcpError(id: id, code: -32602, message: "project_id is required")
            }
            var body = arguments
            body.removeValue(forKey: "project_id")
            response = callLocalAPI(method: "PATCH", path: "/api/v1/projects/\(rawID)", body: body)
        case "delete_project":
            guard let rawID = stringArgument(arguments, "project_id") else {
                return mcpError(id: id, code: -32602, message: "project_id is required")
            }
            response = callLocalAPI(method: "DELETE", path: "/api/v1/projects/\(rawID)")
        case "list_time_entries":
            response = callLocalAPI(
                method: "GET",
                path: "/api/v1/time-entries",
                query: stringQuery(arguments, keys: ["start_date_min", "start_date_max", "project", "billing_status"])
            )
        case "show_time_entry":
            guard let rawID = stringArgument(arguments, "time_entry_id") else {
                return mcpError(id: id, code: -32602, message: "time_entry_id is required")
            }
            response = callLocalAPI(method: "GET", path: "/api/v1/time-entries/\(rawID)")
        case "show_latest_time_entry":
            response = callLocalAPI(method: "GET", path: "/api/v1/time-entries/latest")
        case "show_running_timer":
            response = callLocalAPI(method: "GET", path: "/api/v1/time-entries/running")
        case "create_time_entry":
            response = callLocalAPI(method: "POST", path: "/api/v1/time-entries", body: arguments)
        case "update_time_entry":
            guard let rawID = stringArgument(arguments, "time_entry_id") else {
                return mcpError(id: id, code: -32602, message: "time_entry_id is required")
            }
            var body = arguments
            body.removeValue(forKey: "time_entry_id")
            response = callLocalAPI(method: "PATCH", path: "/api/v1/time-entries/\(rawID)", body: body)
        case "delete_time_entry":
            guard let rawID = stringArgument(arguments, "time_entry_id") else {
                return mcpError(id: id, code: -32602, message: "time_entry_id is required")
            }
            response = callLocalAPI(method: "DELETE", path: "/api/v1/time-entries/\(rawID)")
        case "batch_update_time_entries":
            response = callLocalAPI(
                method: "PATCH",
                path: "/api/v1/time-entries/batch-update",
                body: arguments
            )
        case "start_timer":
            var body = arguments
            if let project = body["project"] as? String {
                body["projectID"] = project
                body.removeValue(forKey: "project")
            }
            if let startedAt = body["started_at"] as? String {
                body["startedAt"] = startedAt
                body.removeValue(forKey: "started_at")
            }
            if let billingStatus = body["billing_status"] as? String {
                body["billingStatus"] = billingStatus
                body.removeValue(forKey: "billing_status")
            }
            response = callLocalAPI(method: "POST", path: "/v1/timer/start", body: body)
        case "stop_timer":
            response = callLocalAPI(method: "POST", path: "/v1/timer/stop")
        default:
            return mcpError(id: id, code: -32602, message: "Unknown MCP tool: \(name)")
        }

        let text = String(data: response.body, encoding: .utf8) ?? ""
        var toolResult: [String: Any] = [
            "content": [["type": "text", "text": text]],
            "isError": response.statusCode >= 400
        ]
        if let structured = try? JSONSerialization.jsonObject(with: response.body) {
            toolResult["structuredContent"] = structured
        }
        return mcpResponse(id: id, result: toolResult)
    }

    private func callLocalAPI(
        method: String,
        path: String,
        query: [String: String] = [:],
        body: [String: Any] = [:]
    ) -> LocalAPIResponse {
        let bodyData = body.isEmpty
            ? Data()
            : (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return handle(localAPI: LocalAPIRequest(
            method: method,
            path: path,
            query: query,
            body: bodyData
        ))
    }

    private func stringArgument(_ arguments: [String: Any], _ key: String) -> String? {
        guard let value = arguments[key] else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func stringQuery(_ arguments: [String: Any], keys: [String]) -> [String: String] {
        keys.reduce(into: [String: String]()) { result, key in
            if let value = stringArgument(arguments, key) {
                result[key] = value
            } else if let bool = arguments[key] as? Bool {
                result[key] = bool ? "true" : "false"
            }
        }
    }

    private func apiBody(_ request: LocalAPIRequest) -> [String: Any]? {
        guard !request.body.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: request.body),
              let body = object as? [String: Any] else {
            return nil
        }
        return body
    }

    private func planAPIResponse(for date: Date) -> [String: Any] {
        let normalized = Calendar.current.startOfDay(for: date)
        markdownStore.ensurePlanFile(for: normalized)
        let raw = markdownStore.markdown(for: normalized)
            ?? MarkdownCodec.serialize(MarkdownCodec.blank(for: normalized))
        let taskIDs = Dictionary(
            uniqueKeysWithValues: MarkdownCodec.taskLineIndices(in: raw).map { ($0, UUID()) }
        )
        let document = MarkdownCodec.parse(raw, date: normalized, taskIDsByLine: taskIDs)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let tasks: [[String: Any]] = document.tasks.map { task in
            [
                "id": task.id.uuidString,
                "title": task.title,
                "tags": task.tags,
                "start_minute": task.startMinute.map { $0 } ?? NSNull(),
                "end_minute": task.endMinute.map { $0 } ?? NSNull(),
                "completed": task.isCompleted
            ]
        }
        return [
            "date": formatter.string(from: normalized),
            "file": "Calendar/\(formatter.string(from: normalized)).md",
            "markdown": raw,
            "tasks": tasks,
            "line_count": raw.components(separatedBy: .newlines).count
        ]
    }

    private func apiDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func apiDayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func apiDate(from rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        if let date = parseCommandDate(rawValue) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rawValue)
    }

    private func reportDates(from start: Date, through end: Date) -> [Date] {
        let calendar = Calendar.current
        var dates: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while cursor <= last, dates.count < 3_650 {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return dates
    }

    private func rawActivitySegments(for date: Date) -> [ActivitySegment] {
        activityMonitor.segments(for: date) + screenTimeStore.segments(for: date)
    }

    private func effectiveActivitySegments(for date: Date) -> [ActivitySegment] {
        categoryStore.applyingCategories(
            to: rawActivitySegments(for: date),
            filterStore: filterStore,
            date: date
        )
    }

    private func apiActivity(_ segment: ActivitySegment, date: Date) -> [String: Any] {
        let category = categoryStore.category(for: segment, filterStore: filterStore, date: date)
        return [
            "id": segment.id.uuidString,
            "appName": segment.appName,
            "bundleIdentifier": segment.bundleIdentifier,
            "deviceName": segment.deviceName,
            "windowTitle": segment.windowTitle,
            "resource": segment.resource,
            "startMinute": segment.startMinute,
            "endMinute": segment.endMinute,
            "startSecond": segment.startSecond,
            "endSecond": segment.endSecond,
            "relevance": category.role.relevance.rawValue,
            "categoryName": category.name,
            "categoryRole": category.role.rawValue,
            "categoryColor": category.color.rawValue,
            "projectID": segment.projectID.map { $0.uuidString } ?? NSNull()
        ]
    }

    private func reportOptions(from query: [String: String]) -> ReportOptions {
        var options = ReportOptions()
        switch query["include"]?.lowercased() {
        case "app", "app_usage", "appusage": options.include = .appUsage
        case "time", "time_entries", "timeentries": options.include = .timeEntries
        case "both": options.include = .both
        default: break
        }
        if let rawGroup = query["group_by"]?.lowercased() {
            let normalizedGroup = rawGroup
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: " ", with: "")
            let group: ReportGroupBy?
            switch normalizedGroup {
            case "exact", "none": group = ReportGroupBy.none
            case "day": group = .day
            case "weekandday": group = .weekAndDay
            case "week": group = .week
            case "month": group = .month
            case "year": group = .year
            case "hour": group = .hour
            case "project": group = .project
            case "toplevelproject": group = .topLevelProject
            case "secondlevelproject": group = .secondLevelProject
            case "projecthierarchy", "hierarchical": group = .projectHierarchy
            case "application", "app": group = .application
            case "document", "website", "resource": group = .document
            default: group = nil
            }
            if let group { options.groupBy = group }
        }
        if let rawBilling = query["billing_status"]?.lowercased() {
            switch rawBilling {
            case "all", "": options.billingFilter = .all
            case "billable": options.billingFilter = .billable
            case "not_billable", "not-billable", "notbillable": options.billingFilter = .notBillable
            case "pending": options.billingFilter = .pending
            case "billed": options.billingFilter = .billed
            case "paid": options.billingFilter = .paid
            case "undetermined": options.billingFilter = .undetermined
            default: break
            }
        }
        if let rawRounding = query["rounding"]?.lowercased(),
           let rounding = ReportRoundingMode(rawValue: rawRounding) {
            options.rounding = rounding
        }
        if let interval = Int(query["rounding_minutes"] ?? query["interval"] ?? ""),
           [1, 5, 6, 10, 12, 15, 30, 60].contains(interval) {
            options.roundingMinutes = interval
        }
        if let durationFormat = query["duration_format"].flatMap(ReportDurationFormat.init(rawValue:)) {
            options.durationFormat = durationFormat
        }
        options.includeShortEntries = apiBoolean(query["include_short_entries"], default: true)
        options.includeCoveredAppUsage = apiBoolean(query["include_covered_app_usage"], default: false)
        options.roundIndividualEntries = apiBoolean(query["round_individual_entries"], default: true)
        if let rawColumns = query["columns"] {
            let selected = Set(
                rawColumns
                    .split(separator: ",")
                    .compactMap { ReportColumn(rawValue: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            )
            if !selected.isEmpty { options.columns = selected }
        }
        if let rawProjects = query["projects"] ?? query["project_ids"] {
            options.projectIDs = Set(
                rawProjects
                    .split(separator: ",")
                    .compactMap { UUID(uuidString: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            )
        }
        return options
    }

    private func preferencesAPI() -> [String: Any] {
        [
            "idle_threshold_seconds": preferences.idleThresholdSeconds,
            "track_weekends": preferences.trackWeekends,
            "track_only_during_working_hours": preferences.trackOnlyDuringWorkingHours,
            "working_hours_start_minute": preferences.workingHoursStartMinute,
            "working_hours_end_minute": preferences.workingHoursEndMinute,
            "start_tracking_when_app_opens": preferences.startTrackingWhenAppOpens,
            "auto_stop_timer_on_sleep": preferences.autoStopTimerOnSleep,
            "allow_local_network_api": preferences.allowLocalNetworkAPI,
            "launch_at_login": loginItemManager.isEnabled,
            "launch_at_login_status": loginItemManager.statusMessage,
            "tracking": activityMonitor.isTracking,
            "api_endpoint": localAPIServer.endpoint,
            "api_allows_lan": localAPIServer.allowsLAN,
        ]
    }

    private func activityPreferencesAPI() -> [String: Any] {
        [
            "include_time_entries": activitiesPreferences.includeTimeEntries,
            "show_window_titles": activitiesPreferences.showWindowTitles,
            "show_resource_paths": activitiesPreferences.showResourcePaths,
            "group_websites_independently": activitiesPreferences.groupWebsitesIndependently,
            "group_paths_independently": activitiesPreferences.groupPathsIndependently,
            "activity_time_range": activitiesPreferences.activityTimeRange.rawValue,
            "activity_display_mode": activitiesPreferences.activityDisplayMode,
            "group_by_project": activitiesPreferences.groupByProject,
            "group_by_device": activitiesPreferences.groupByDevice,
            "include_idle": activitiesPreferences.includeIdle,
            "selected_device": activitiesPreferences.selectedDevice,
            "timeline_orientation": activitiesPreferences.timelineOrientation.rawValue,
        ]
    }

    private func sourcePreferencesAPI() -> [String: Any] {
        [
            "calendar": [
                "authorized": calendarStore.isAuthorized,
                "status": calendarStore.statusMessage,
                "available_titles": calendarStore.availableCalendarTitles,
                "included_titles": Array(calendarStore.includedCalendarTitles).sorted()
            ],
            "reminders": [
                "authorized": reminderStore.isAuthorized,
                "status": reminderStore.statusMessage,
                "available_list_titles": reminderStore.availableListTitles,
                "included_list_titles": Array(reminderStore.includedListTitles).sorted(),
                "hide_recurring": reminderStore.hideRecurringReminders
            ],
            "phone_calls": [
                "database_available": phoneCallStore.databaseAvailable,
                "status": phoneCallStore.statusMessage,
                "hidden_addresses": Array(phoneCallStore.hiddenAddresses).sorted()
            ],
            "screen_time": [
                "database_available": screenTimeStore.databaseAvailable,
                "status": screenTimeStore.statusMessage
            ],
            "permissions": [
                "accessibility_trusted": activityMonitor.accessibilityTrusted,
                "status": activityMonitor.accessibilityTrusted
                    ? "Accessibility access available"
                    : "Accessibility access needed for window titles"
            ]
        ]
    }

    private func apiBoolean(_ rawValue: String?, default defaultValue: Bool) -> Bool {
        guard let rawValue else { return defaultValue }
        switch rawValue.lowercased() {
        case "1", "true", "yes", "on": return true
        case "0", "false", "no", "off": return false
        default: return defaultValue
        }
    }

    private func apiStringArray(_ rawValue: Any?) -> [String]? {
        guard let values = rawValue as? [Any] else { return nil }
        return values.compactMap { value in
            guard let string = value as? String else { return nil }
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : normalized
        }
    }

    private func validatedCustomFields(_ rawValue: Any?) -> [String: String]? {
        guard let fields = rawValue as? [String: Any] else { return nil }
        var result: [String: String] = [:]
        for (key, value) in fields {
            guard validCustomFieldName(key), let stringValue = value as? String else { continue }
            result[key] = stringValue
        }
        return result
    }

    private func applyCustomFieldPatch(_ fields: inout [String: String], rawValue: Any?) {
        guard let values = rawValue as? [String: Any] else { return }
        for (key, value) in values where validCustomFieldName(key) {
            if value is NSNull {
                fields.removeValue(forKey: key)
            } else if let stringValue = value as? String {
                fields[key] = stringValue
            }
        }
    }

    private func validCustomFieldName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("_"), name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            return false
        }
        return !name.allSatisfy(\.isNumber)
    }

    private func apiEntry(_ entry: TimeEntry) -> [String: Any] {
        return [
            "id": entry.id.uuidString,
            "projectID": entry.projectID.map { $0.uuidString } ?? NSNull(),
            "title": entry.title,
            "notes": entry.notes,
            "start": apiDate(entry.start),
            "end": apiDate(entry.end),
            "durationSeconds": entry.durationSeconds,
            "billingStatus": entryBillingStatusRaw(entry.billingStatus),
            "isManual": entry.isManual,
            "customFields": entry.customFields
        ]
    }

    private func apiPhoneCall(_ call: PhoneCallItem) -> [String: Any] {
        [
            "id": call.id,
            "address": call.address,
            "service_provider": call.serviceProvider,
            "start": apiDate(call.start),
            "end": apiDate(call.end),
            "duration_seconds": call.durationSeconds,
            "is_point_in_time": call.isPointInTime,
            "read_only": true
        ]
    }

    private func apiCalendarEvent(_ event: CalendarEventItem) -> [String: Any] {
        [
            "id": event.id,
            "title": event.title,
            "calendar": event.calendarTitle,
            "calendar_identifier": event.calendarIdentifier,
            "location": event.location,
            "notes": event.notes,
            "url": event.urlString,
            "start": apiDate(event.start),
            "end": apiDate(event.end),
            "duration_seconds": event.durationSeconds,
            "is_editable": event.isEditable,
            "read_only": true
        ]
    }

    private func apiReminder(_ reminder: ReminderItem) -> [String: Any] {
        [
            "id": reminder.id,
            "title": reminder.title,
            "list": reminder.listTitle,
            "notes": reminder.notes,
            "completed_at": apiDate(reminder.completedAt),
            "is_recurring": reminder.isRecurring,
            "read_only": true
        ]
    }

    private func officialProject(_ project: TrackingProject) -> [String: Any] {
        [
            "id": "/projects/\(project.id.uuidString)",
            "self": "/projects/\(project.id.uuidString)",
            "title": project.name,
            "title_chain": projectStore.hierarchyPath(for: project.id).components(separatedBy: " > "),
            "color": projectColorHex(project.color),
            "parent": project.parentID.map { "/projects/\($0.uuidString)" } ?? NSNull(),
            "children": projectStore.childProjects(of: project.id).map { ["self": "/projects/\($0.id.uuidString)"] },
            "team_id": project.teamID.map { "/teams/\($0.uuidString)" } ?? NSNull(),
            "default_billing_status": projectBillingStatusRaw(project.defaultBillingStatus),
            "productivity_score": Double(project.productivity) / 100.0,
            "productivity": project.productivity,
            "is_archived": project.isArchived,
            "billing_rate": project.billingRate,
            "currency": project.currency,
            "notes": project.notes,
            "custom_fields": project.customFields
        ]
    }

    private func officialTeam(_ team: MetridayTeam) -> [String: Any] {
        let teamProjectIDs = Set(
            projectStore.activeProjects
                .filter { $0.teamID == team.id }
                .map(\.id)
        )
        let teamEntries = timeEntryStore.materializedEntries().filter {
            guard let projectID = $0.projectID else { return false }
            return teamProjectIDs.contains(projectID)
        }
        return [
            "id": "/teams/\(team.id.uuidString)",
            "self": "/teams/\(team.id.uuidString)",
            "name": team.name,
            "members_count": team.members.filter(\.isActive).count,
            "is_archived": team.isArchived,
            "tracked_seconds": teamEntries.reduce(0) { $0 + $1.durationSeconds },
            "billable_seconds": teamEntries
                .filter { $0.billingStatus != .notBillable }
                .reduce(0) { $0 + $1.durationSeconds },
            "time_entry_count": teamEntries.count
        ]
    }

    private func officialTeamMember(_ member: TeamMember) -> [String: Any] {
        [
            "id": "/users/\(member.id.uuidString)",
            "self": "/users/\(member.id.uuidString)",
            "name": member.name,
            "email": member.email,
            "role": member.role,
            "is_active": member.isActive
        ]
    }

    private func projectHierarchy(_ project: TrackingProject) -> [String: Any] {
        var result = officialProject(project)
        result["children"] = projectStore.childProjects(of: project.id)
            .filter { !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map(projectHierarchy)
        return result
    }

    private func projectColorHex(_ color: ProjectColor) -> String {
        switch color {
        case .blue: return "#4E5FF2"
        case .green: return "#399A55"
        case .orange: return "#D77B22"
        case .purple: return "#8656D8"
        case .red: return "#D24B4B"
        case .graphite: return "#555B66"
        }
    }

    private func projectColor(from rawValue: String) -> ProjectColor? {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let direct = ProjectColor(rawValue: normalized) { return direct }
        switch normalized {
        case "#4e5ff2": return .blue
        case "#399a55": return .green
        case "#d77b22": return .orange
        case "#8656d8": return .purple
        case "#d24b4b": return .red
        case "#555b66": return .graphite
        default: return nil
        }
    }

    private func projectBillingStatus(from rawValue: String) -> ProjectBillingStatus? {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        switch normalized {
        case "automatic", "inherit", "inherited": return .automatic
        case "billable": return .billable
        case "notbillable": return .notBillable
        case "pending": return .pending
        case "billed": return .billed
        case "paid": return .paid
        default: return nil
        }
    }

    private func projectBillingStatusRaw(_ status: ProjectBillingStatus) -> String {
        switch status {
        case .notBillable: return "not_billable"
        default: return status.rawValue
        }
    }

    private func entryBillingStatus(from rawValue: String?, projectID: UUID? = nil) -> BillingStatus {
        let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        let explicit: BillingStatus?
        switch normalized {
        case "billable": explicit = .billable
        case "notbillable": explicit = .notBillable
        case "pending": explicit = .pending
        case "billed": explicit = .billed
        case "paid": explicit = .paid
        case "undetermined": explicit = .undetermined
        case "automatic", "inherit", "inherited", nil, "": explicit = nil
        default: explicit = nil
        }
        return explicit ?? projectStore.resolvedBillingStatus(for: projectID)
    }

    private func entryBillingStatusRaw(_ status: BillingStatus) -> String {
        switch status {
        case .notBillable: return "not_billable"
        default: return status.rawValue
        }
    }

    private func officialWebRule(_ rule: WebRule) -> [String: Any] {
        [
            "id": rule.id.uuidString,
            "domain": rule.domain,
            "allowed": rule.isAllowed
        ]
    }

    private func apiProjectRule(_ rule: ProjectRule) -> [String: Any] {
        [
            "id": rule.id.uuidString,
            "project_id": rule.projectID.uuidString,
            "project": "/projects/\(rule.projectID.uuidString)",
            "project_name": projectStore.name(for: rule.projectID),
            "field": rule.field.rawValue,
            "comparison": rule.comparison.rawValue,
            "pattern": rule.pattern,
            "case_sensitive": rule.isCaseSensitive
        ]
    }

    private func apiActivityFilter(_ filter: ActivityFilterDefinition) -> [String: Any] {
        [
            "id": filter.id.uuidString,
            "name": filter.name,
            "color": filter.color.rawValue,
            "match_mode": filter.matchMode.rawValue,
            "is_archived": filter.isArchived,
            "rules": filter.rules.map { rule in
                [
                    "id": rule.id.uuidString,
                    "field": rule.field.rawValue,
                    "comparison": rule.comparison.rawValue,
                    "pattern": rule.pattern,
                    "case_sensitive": rule.isCaseSensitive
                ]
            }
        ]
    }

    private func apiActivityCategory(_ category: ActivityCategoryDefinition) -> [String: Any] {
        var payload = apiActivityFilter(category.filterDefinition)
        payload["role"] = category.role.rawValue
        payload["is_system"] = category.isSystem
        payload["is_archived"] = category.isArchived
        return payload
    }

    private func apiActivityExclusion(_ rule: ActivityExclusionRule) -> [String: Any] {
        [
            "id": rule.id.uuidString,
            "field": rule.field.rawValue,
            "comparison": rule.comparison.rawValue,
            "pattern": rule.pattern,
            "case_sensitive": rule.isCaseSensitive
        ]
    }

    private func activityFilter(
        from body: [String: Any],
        existing: ActivityFilterDefinition? = nil
    ) -> ActivityFilterDefinition? {
        let name = (body["name"] as? String ?? body["title"] as? String ?? existing?.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let color = (body["color"] as? String).flatMap(ProjectColor.init(rawValue:))
            ?? existing?.color
            ?? .purple
        let matchMode = (body["match_mode"] as? String).flatMap(ActivityFilterMatchMode.init(rawValue:))
            ?? existing?.matchMode
            ?? .any
        let rules: [ActivityFilterRule]
        if let rawRules = body["rules"] as? [[String: Any]] {
            rules = rawRules.compactMap { rawRule in
                guard let field = (rawRule["field"] as? String).flatMap(ActivityFilterField.init(rawValue:)),
                      let comparison = (rawRule["comparison"] as? String).flatMap(ProjectRuleComparison.init(rawValue:)),
                      let pattern = rawRule["pattern"] as? String,
                      !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                let id = (rawRule["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
                return ActivityFilterRule(
                    id: id,
                    field: field,
                    pattern: pattern,
                    isCaseSensitive: rawRule["case_sensitive"] as? Bool ?? false,
                    comparison: comparison
                )
            }
        } else {
            rules = existing?.rules ?? []
        }
        guard !name.isEmpty, !rules.isEmpty else { return nil }
        return ActivityFilterDefinition(
            id: existing?.id ?? (body["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID(),
            name: name,
            color: color,
            matchMode: matchMode,
            rules: rules,
            isArchived: body["is_archived"] as? Bool ?? existing?.isArchived ?? false
        )
    }

    private func activityCategory(
        from body: [String: Any],
        existing: ActivityCategoryDefinition? = nil
    ) -> ActivityCategoryDefinition? {
        guard let filter = activityFilter(from: body, existing: existing?.filterDefinition) else { return nil }
        let role = (body["role"] as? String).flatMap(ActivityCategoryRole.init(rawValue:)) ?? existing?.role ?? .other
        return ActivityCategoryDefinition(
            id: existing?.id ?? filter.id,
            name: filter.name,
            role: role,
            color: filter.color,
            matchMode: filter.matchMode,
            rules: filter.rules,
            isSystem: existing?.isSystem ?? false,
            isArchived: body["is_archived"] as? Bool ?? existing?.isArchived ?? false
        )
    }

    private func officialEntry(_ entry: TimeEntry, isRunning: Bool = false) -> [String: Any] {
        [
            "id": "/time-entries/\(entry.id.uuidString)",
            "self": "/time-entries/\(entry.id.uuidString)",
            "start_date": apiDate(entry.start),
            "end_date": apiDate(entry.end),
            "duration": entry.durationSeconds,
            "project": entry.projectID.map { "/projects/\($0.uuidString)" } ?? NSNull(),
            "title": entry.title,
            "notes": entry.notes,
            "is_running": isRunning,
            "billing_status": entryBillingStatusRaw(entry.billingStatus),
            "creator_id": "/users/local",
            "creator_name": NSFullUserName(),
            "custom_fields": entry.customFields
        ]
    }

    private func apiValue(_ value: Int?) -> Any {
        guard let value else { return NSNull() }
        return value
    }

    private func apiProjectID(_ rawValue: String) -> UUID? {
        let cleaned = rawValue
            .replacingOccurrences(of: "/projects/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return projectID(for: cleaned)
    }

    private func apiTeamID(_ rawValue: String) -> UUID? {
        let cleaned = rawValue
            .replacingOccurrences(of: "/teams/", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return UUID(uuidString: cleaned)
    }

    private func apiTeamIDValue(_ rawValue: Any?) -> UUID? {
        if rawValue is NSNull { return nil }
        if let rawString = rawValue as? String { return apiTeamID(rawString) }
        if let object = rawValue as? [String: Any], let rawID = object["id"] as? String {
            return apiTeamID(rawID)
        }
        return nil
    }

    private func apiProjectIDValue(_ rawValue: Any?) -> UUID? {
        if rawValue is NSNull { return nil }
        if let rawString = rawValue as? String { return apiProjectID(rawString) }
        if let object = rawValue as? [String: Any], let rawID = object["id"] as? String {
            return apiProjectID(rawID)
        }
        return nil
    }

    func goToToday() {
        selectDate(.now)
    }

    func moveSelectedDate(byDays offset: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) else { return }
        selectDate(date)
    }

    /// Handles local automation commands such as
    /// `metriday://timer/start?title=Deep%20work`. This keeps the common
    /// Timing-style automation workflow available without a cloud service or
    /// a privileged helper process.
    func handle(url: URL) {
        guard url.scheme?.lowercased() == "metriday" else { return }
        let pathParts = url.pathComponents.filter { $0 != "/" }
        var commandParts: [String] = []
        if let host = url.host, !host.isEmpty {
            commandParts.append(host)
        }
        commandParts.append(contentsOf: pathParts)
        guard !commandParts.isEmpty else {
            markdownStore.statusMessage = "Unknown Metriday command"
            return
        }

        var parameters = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .reduce(into: [String: String]()) { result, item in
                result[item.name] = item.value ?? ""
            }
        let group: String
        let action: String
        if commandParts.count >= 2 {
            group = commandParts[0].lowercased()
            action = commandParts[1].lowercased()
        } else {
            switch commandParts[0].lowercased() {
            case "starttimer":
                group = "timer"
                action = "start"
            case "stoptimer":
                group = "timer"
                action = "stop"
            case "createtimeentry":
                group = "entry"
                action = "add"
            case "hidephonecall":
                group = "phone-calls"
                action = "hide"
            default:
                markdownStore.statusMessage = "Unknown Metriday command"
                return
            }
        }
        // Timing's helper URLs use camelCase names. Normalize them into the
        // local command vocabulary so scripts can be moved over unchanged.
        if parameters["start"] == nil { parameters["start"] = parameters["startDate"] }
        if parameters["end"] == nil { parameters["end"] = parameters["endDate"] }
        if parameters["minutes"] == nil,
           let estimatedDuration = Int(parameters["estimatedDuration"] ?? ""),
           estimatedDuration > 0 {
            parameters["minutes"] = String(max(1, Int(ceil(Double(estimatedDuration) / 60.0))))
        }

        switch (group, action) {
        case ("tracking", "pause"):
            if activityMonitor.isTracking { activityMonitor.stop() }
            markdownStore.statusMessage = "Tracking paused by URL command"
        case ("tracking", "resume"):
            if !activityMonitor.isTracking { activityMonitor.start() }
            markdownStore.statusMessage = "Tracking resumed by URL command"
        case ("tracking", "toggle"):
            activityMonitor.toggleTracking()
            markdownStore.statusMessage = activityMonitor.isTracking
                ? "Tracking resumed by URL command"
                : "Tracking paused by URL command"
        case ("phone-calls", "hide"), ("phone", "hide"):
            guard let address = parameters["address"],
                  !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                markdownStore.statusMessage = "Phone-call hide command needs an address"
                return
            }
            let hidden = parameters["hidden"].map { $0.lowercased() != "false" } ?? true
            phoneCallStore.setAddressHidden(address, hidden: hidden)
            markdownStore.statusMessage = hidden
                ? "Calls from this number hidden by URL command"
                : "Calls from this number restored by URL command"
        case ("timer", "start"):
            let requestedTitle = parameters["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (requestedTitle?.isEmpty == false ? requestedTitle : nil)
                ?? currentTask?.title
                ?? "Manual timer"
            let projectID = projectID(for: parameters["project"] ?? parameters["projectID"])
            let billingStatus = entryBillingStatus(from: parameters["billingStatus"], projectID: projectID)
            let startedAt = parseCommandDate(parameters["start"] ?? parameters["startedAt"]) ?? .now
            timeEntryStore.startTimer(
                title: title,
                projectID: projectID,
                notes: parameters["notes"] ?? "",
                startedAt: startedAt,
                billingStatus: billingStatus
            )
            if let minutes = Int(parameters["minutes"] ?? ""), minutes > 0,
               let timerID = timeEntryStore.runningTimer?.id {
                Task { @MainActor in
                    let boundedMinutes = min(minutes, 7 * 24 * 60)
                    let nanoseconds = UInt64(boundedMinutes) * 60 * 1_000_000_000
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    guard timeEntryStore.runningTimer?.id == timerID else { return }
                    _ = timeEntryStore.stopTimer()
                }
            }
            section = .activities
            markdownStore.statusMessage = "Timer started by URL command · \(title)"
        case ("timer", "stop"):
            guard timeEntryStore.stopTimer() != nil else {
                markdownStore.statusMessage = "No running timer"
                return
            }
            section = .activities
            markdownStore.statusMessage = "Timer stopped by URL command"
        case ("entry", "add"), ("time-entry", "add"):
            addEntry(from: parameters)
        default:
            markdownStore.statusMessage = "Unknown Metriday command · \(group)/\(action)"
        }
    }

    func receiveTimelineDrop(taskID: UUID, start: Int, end: Int, intent: TimelineDropIntent) {
        let drop = PendingTimelineDrop(taskID: taskID, startMinute: start, endMinute: end, intent: intent)
        if intent == .timeBlock {
            addTimeBlock(drop)
        } else if intent == .event && calendarStore.isAuthorized {
            addCalendarEvent(drop)
        } else {
            pendingTimelineDrop = drop
            markdownStore.statusMessage = intent == .event
                ? "Connect Calendar, then choose Add Event"
                : "Choose Time Block or Event"
        }
    }

    func confirmPendingTimeBlock() {
        guard let pendingTimelineDrop else { return }
        addTimeBlock(pendingTimelineDrop)
    }

    func cancelPendingTimelineDrop() {
        pendingTimelineDrop = nil
        markdownStore.statusMessage = "Drop cancelled"
    }

    func confirmPendingEvent() {
        guard let pendingTimelineDrop else { return }
        addCalendarEvent(pendingTimelineDrop)
    }

    private func addCalendarEvent(_ drop: PendingTimelineDrop) {
        guard let task = markdownStore.task(drop.taskID) else { return }
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: selectedDate)
        let start = day.addingTimeInterval(TimeInterval(drop.startMinute * 60))
        let end = day.addingTimeInterval(TimeInterval(drop.endMinute * 60))
        let range = TimeFormat.range(start: drop.startMinute, end: drop.endMinute)
        guard calendarStore.createEvent(title: task.title, start: start, end: end) else {
            markdownStore.statusMessage = calendarStore.statusMessage
            return
        }
        selectedTaskID = task.id
        self.pendingTimelineDrop = nil
        markdownStore.statusMessage = "Event created · \(range)"
    }

    private func addEntry(from parameters: [String: String]) {
        let title = parameters["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else {
            markdownStore.statusMessage = "Time entry URL command needs a title"
            return
        }

        let start = parseCommandDate(parameters["start"]) ?? .now
        let end: Date
        if let parsedEnd = parseCommandDate(parameters["end"]) {
            end = parsedEnd
        } else {
            let minutes = max(1, Int(parameters["minutes"] ?? "60") ?? 60)
            end = start.addingTimeInterval(TimeInterval(minutes * 60))
        }
        let projectID = projectID(for: parameters["project"] ?? parameters["projectID"])
        guard timeEntryStore.addEntry(
            title: title,
            projectID: projectID,
            notes: parameters["notes"] ?? "",
            start: start,
            end: end,
            billingStatus: entryBillingStatus(from: parameters["billingStatus"], projectID: projectID)
        ) != nil else {
            markdownStore.statusMessage = "Time entry URL command has an invalid time range"
            return
        }
        section = .activities
        markdownStore.statusMessage = "Time entry added by URL command · \(title)"
    }

    private func projectID(for rawValue: String?) -> UUID? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !rawValue.isEmpty else {
            return nil
        }
        if let id = UUID(uuidString: rawValue), projectStore.project(id) != nil {
            return id
        }
        return projectStore.projects.first {
            projectStore.hierarchyPath(for: $0.id).caseInsensitiveCompare(rawValue) == .orderedSame
                || $0.name.caseInsensitiveCompare(rawValue) == .orderedSame
        }?.id
    }

    private func parseCommandDate(_ rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: rawValue) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue)
    }

    private func addTimeBlock(_ drop: PendingTimelineDrop) {
        markdownStore.schedule(
            id: drop.taskID,
            start: drop.startMinute,
            end: drop.endMinute,
            message: "Time Block added · \(TimeFormat.range(start: drop.startMinute, end: drop.endMinute))"
        )
        selectedTaskID = drop.taskID
        pendingTimelineDrop = nil
    }
}

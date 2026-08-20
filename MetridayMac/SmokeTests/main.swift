import Foundation
import SQLite3

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func sqliteExec(_ database: OpaquePointer, _ sql: String) -> Bool {
    var errorMessage: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
    if let errorMessage {
        sqlite3_free(errorMessage)
    }
    return result == SQLITE_OK
}

let date = Date(timeIntervalSince1970: 1_786_729_600)
let seeded = MarkdownCodec.seed(for: date)
let markdown = MarkdownCodec.serialize(seeded)
let parsed = MarkdownCodec.parse(markdown, date: date)

expect(parsed.tasks.count == 3, "Markdown should keep all tasks")
expect(parsed.tasks[0].title == "GeneZip rebuttal experiment", "Task title should round-trip")
expect(parsed.tasks[0].timeRange == "14:00 - 16:00", "Time range should round-trip")
expect(parsed.tasks[0].tags == ["research", "important"], "Tags should round-trip")
expect(parsed.tasks[2].timeRange == nil, "Unscheduled task should remain unscheduled")
expect(TimeFormat.parseRange("09:30-10:15")?.start == 570, "ASCII time range should parse")
expect(TimeFormat.parseRange("14:00–16:00")?.end == 960, "En dash time range should parse")
expect(TimeFormat.parseRange("16:00–14:00") == nil, "Reverse range should be rejected")

let samplePath = "/Users/andyzhao/Projects/Metriday/Calendar/2026-08-21.md"
expect(
    ActivityPathGrouping.immediateParentDirectory.groupNames(for: samplePath) == ["/Users/andyzhao/Projects/Metriday/Calendar"],
    "Immediate parent path grouping should return only the containing directory"
)
expect(
    ActivityPathGrouping.filePathOnly.groupNames(for: samplePath) == [samplePath],
    "File path grouping should keep each path as its own group"
)
let allDirectoryNames = ActivityPathGrouping.allDirectories.groupNames(for: samplePath)
expect(
    allDirectoryNames.contains("/Users/andyzhao/Projects/Metriday/Calendar")
        && allDirectoryNames.contains("/Users/andyzhao/Projects/Metriday"),
    "All-directory path grouping should include parent folders"
)
expect(ActivityPathGrouping.allDirectories.groupNames(for: "https://example.com/file").isEmpty, "Path grouping should ignore website URLs")

let wrapCalendar = Calendar.current
let wrapDay = wrapCalendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
let beforeWrap = wrapCalendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 4, minute: 30))!
let afterWrap = wrapCalendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 5))!
expect(
    TrackingDay.logicalDayLabel(for: beforeWrap, wrapAtMinute: 5 * 60) == wrapDay.addingTimeInterval(-86_400),
    "Wrap days should assign pre-boundary time to the previous logical day"
)
expect(
    TrackingDay.logicalDayLabel(for: afterWrap, wrapAtMinute: 5 * 60) == wrapDay,
    "Wrap days should start the new logical day at the configured boundary"
)
let beforeWrapAxis = TrackingDay.axisSeconds(
    for: beforeWrap,
    logicalDayLabel: wrapDay.addingTimeInterval(-86_400),
    wrapAtMinute: 5 * 60
)
expect(beforeWrapAxis == 23 * 3_600 + 30 * 60, "Wrapped axis should place 04:30 at the end of a 05:00 workday")
expect(
    Calendar.current.component(.hour, from: TrackingDay.date(forAxisSeconds: beforeWrapAxis, logicalDayLabel: wrapDay.addingTimeInterval(-86_400), wrapAtMinute: 5 * 60)) == 4,
    "Wrapped axis should convert back to the original wall-clock time"
)

let rules = [
    WebRule(domain: "youtube.com"),
    WebRule(domain: "studio.youtube.com", isAllowed: true)
]
expect(DomainRuleMatcher.shouldBlock(host: "www.youtube.com", rules: rules), "Subdomains should be blocked")
expect(!DomainRuleMatcher.shouldBlock(host: "studio.youtube.com", rules: rules), "Allowlist should win")
expect(!DomainRuleMatcher.shouldBlock(host: "example.com", rules: rules), "Unlisted domain should pass")

let trackedActivities = [
    ActivitySegment(
        appName: "Visual Studio Code",
        bundleIdentifier: "com.microsoft.VSCode",
        windowTitle: "AppActivityMonitor.swift — Metriday",
        startMinute: 540,
        endMinute: 600,
        relevance: .related
    ),
    ActivitySegment(
        appName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome",
        windowTitle: "YouTube",
        startMinute: 600,
        endMinute: 612,
        relevance: ActivityClassifier.relevance(
            appName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            windowTitle: "YouTube"
        )
    ),
    ActivitySegment(
        appName: "Idle",
        bundleIdentifier: "com.metriday.idle",
        windowTitle: "No keyboard or pointer activity",
        startMinute: 612,
        endMinute: 630,
        relevance: .idle
    )
]
let activitySummary = ActivitySummary(segments: trackedActivities)
expect(activitySummary.relatedMinutes == 60, "Activity summary should count related minutes")
expect(activitySummary.distractedMinutes == 12, "Activity summary should count distracted minutes")
expect(activitySummary.idleMinutes == 18, "Activity summary should count idle minutes")
expect(activitySummary.activeMinutes == 72, "Activity summary should exclude idle time from active minutes")
expect(activitySummary.taskRelatedPercentage == 83, "Activity summary should calculate task relevance from active time")

let deletionHistoryRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("MetridaySmoke-\(UUID().uuidString)", isDirectory: true)
let deletionHistory = ActivityHistoryStore(rootDirectory: deletionHistoryRoot)
try! deletionHistory.save(trackedActivities, date: date)
let deletedActivityID = trackedActivities[1].id
deletionHistory.markDeleted([deletedActivityID], date: date)
expect(deletionHistory.isDeleted(deletedActivityID, date: date), "Activity deletion should persist a date-scoped tombstone")
expect(deletionHistory.load(date: date).count == 2, "Deleted activities should stay hidden from history loads")
deletionHistory.restore([deletedActivityID], date: date)
expect(!deletionHistory.isDeleted(deletedActivityID, date: date), "Undo should clear the activity deletion tombstone")
expect(deletionHistory.load(date: date).count == 3, "Restoring an activity should make it visible again")
deletionHistory.markDeleted([deletedActivityID], date: date)
let deletionArchive = try! deletionHistory.exportArchiveData()
let importedDeletionHistory = ActivityHistoryStore(
    rootDirectory: FileManager.default.temporaryDirectory
        .appendingPathComponent("MetridaySmokeImport-\(UUID().uuidString)", isDirectory: true)
)
_ = try! importedDeletionHistory.importArchiveData(deletionArchive)
expect(importedDeletionHistory.isDeleted(deletedActivityID, date: date), "Activity tombstones should survive archive sync")
expect(importedDeletionHistory.load(date: date).count == 2, "Synced activity tombstones should remain hidden")

let suggestionProjectID = UUID()
let timelineSuggestionSegments = [
    ActivitySegment(
        appName: "Visual Studio Code",
        bundleIdentifier: "com.microsoft.VSCode",
        windowTitle: "ActivityInsights.swift",
        startMinute: 540,
        endMinute: 555,
        relevance: .related,
        projectID: suggestionProjectID
    ),
    ActivitySegment(
        appName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome",
        windowTitle: "GitHub",
        startMinute: 557,
        endMinute: 575,
        relevance: .related,
        projectID: suggestionProjectID
    ),
    ActivitySegment(
        appName: "Idle",
        bundleIdentifier: "com.metriday.idle",
        startMinute: 575,
        endMinute: 590,
        relevance: .idle,
        projectID: suggestionProjectID
    )
]
let timelineSuggestions = ActivityInsights.generateTimelineSuggestions(from: timelineSuggestionSegments)
expect(timelineSuggestions.count == 1, "Vertical timeline summaries should merge related app activity")
expect(timelineSuggestions[0].startMinute == 540 && timelineSuggestions[0].endMinute == 575, "Timeline summary should cover active evidence but exclude idle time")
expect(timelineSuggestions[0].projectID == suggestionProjectID, "Timeline summary should preserve the dominant project")
expect(timelineSuggestions[0].title.contains("Focused work"), "Focused timeline summaries should offer a focused title")
expect(timelineSuggestions[0].notes.contains("captured activities"), "Timeline summaries should explain their local evidence")
let titleSuggestionEntries = [
    TimeEntry(
        title: "Write rebuttal",
        start: date,
        end: date.addingTimeInterval(30 * 60)
    ),
    TimeEntry(
        title: "Review experiments",
        start: date.addingTimeInterval(60 * 60),
        end: date.addingTimeInterval(90 * 60)
    )
]
let titleSuggestionProjects = [TrackingProject(name: "Research")]
let titleSuggestions = TimeEntrySuggestionProvider.titles(
    from: titleSuggestionEntries,
    projects: titleSuggestionProjects,
    query: "re"
)
expect(titleSuggestions.contains("Review experiments") && titleSuggestions.contains("Research"), "Time entry titles should suggest matching entries and projects")
expect(TimeEntrySuggestionProvider.titles(from: titleSuggestionEntries, projects: titleSuggestionProjects, query: "$bill").isEmpty, "Billing shortcut text should not become a title suggestion")
expect(TimeEntrySuggestionProvider.billingStatuses(for: "$bill").contains(.billable), "Dollar shortcuts should suggest Billable")
expect(TimeEntrySuggestionProvider.billingStatuses(for: "$paid") == [.paid], "Dollar shortcuts should resolve an exact billing status")
expect(ActivityClassifier.relevance(appName: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode", windowTitle: "") == .related, "Known work apps should be related")
expect(ActivityClassifier.relevance(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome", windowTitle: "YouTube") == .distracted, "Distracting window titles should be classified")
expect(ActivityClassifier.relevance(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome", windowTitle: "") == .distracted, "Browser activity should have a safe default classification")
expect(ActivityClassifier.relevance(appName: "Linear", bundleIdentifier: "com.linear", windowTitle: "") == .other, "Unknown foreground apps should remain tracked as other activity")
expect(trackedActivities[0].displayTitle.contains("AppActivityMonitor.swift"), "Window title should be visible in activity display")
expect(
    ActivityPrivacy.isPrivateBrowserContext(appName: "Google Chrome", windowTitle: "Incognito", resource: "https://example.com"),
    "Incognito browser windows should be discarded from activity history"
)
expect(
    !ActivityPrivacy.isPrivateBrowserContext(appName: "Google Chrome", windowTitle: "Private project notes", resource: "https://example.com"),
    "Ordinary browser titles should not be treated as private windows"
)
expect(
    ActivityPrivacy.isPrivateBrowserContext(appName: "Firefox", windowTitle: "Private Window", resource: "https://example.com"),
    "Firefox private windows should be discarded from activity history"
)
expect(
    ActivityClassifier.relevance(appName: "Firefox", bundleIdentifier: "org.mozilla.firefox", windowTitle: "") == .distracted,
    "Firefox browser activity should have a safe default classification"
)
let calendarProject = TrackingProject(name: "Research")
let calendarClient = TrackingProject(name: "Client Work")
let priorCalendarEntry = TimeEntry(
    projectID: calendarProject.id,
    title: "Weekly Research Sync",
    notes: "Work calendar",
    start: date.addingTimeInterval(-3_600),
    end: date.addingTimeInterval(-1_800)
)
expect(
    CalendarProjectSuggester.suggestedProjectID(
        eventTitle: "Weekly Research Sync",
        calendarTitle: "Work calendar",
        notes: "",
        previousEntries: [priorCalendarEntry],
        projects: [calendarProject, calendarClient],
        ruleProjectID: calendarClient.id
    ) == calendarProject.id,
    "Calendar suggestions should reuse the project from a previous event with the same title"
)
expect(
    CalendarProjectSuggester.suggestedProjectID(
        eventTitle: "Client kickoff",
        calendarTitle: "Work calendar",
        notes: "",
        previousEntries: [],
        projects: [calendarProject, calendarClient],
        ruleProjectID: calendarClient.id
    ) == calendarClient.id,
    "Calendar suggestions should prefer a matching project rule after history"
)
let priorCalendarOnlyEntry = TimeEntry(
    projectID: calendarProject.id,
    title: "Different event",
    notes: "Work calendar",
    start: date.addingTimeInterval(-7_200),
    end: date.addingTimeInterval(-5_400)
)
expect(
    CalendarProjectSuggester.suggestedProjectID(
        eventTitle: "Client kickoff",
        calendarTitle: "Work calendar",
        notes: "",
        previousEntries: [priorCalendarOnlyEntry],
        projects: [calendarProject, calendarClient],
        ruleProjectID: calendarClient.id
    ) == calendarClient.id,
    "Calendar suggestions should prefer a project rule over same-calendar history"
)
expect(
    CalendarProjectSuggester.suggestedProjectID(
        eventTitle: "Research review",
        calendarTitle: "Work calendar",
        notes: "",
        previousEntries: [],
        projects: [calendarProject, calendarClient],
        ruleProjectID: nil
    ) == calendarProject.id,
    "Calendar suggestions should fall back to project-name similarity"
)
expect(
    ActivityCallDetector.isCall(appName: "Zoom", bundleIdentifier: "us.zoom.xos", windowTitle: "Zoom Meeting"),
    "Known call applications should create a record prompt"
)
expect(
    ActivityCallDetector.isCall(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome", windowTitle: "Google Meet · Research"),
    "Browser meeting titles should create a record prompt"
)
expect(
    ActivityCallDetector.isCall(appName: "WhatsApp", bundleIdentifier: "net.whatsapp.WhatsApp", windowTitle: "WhatsApp Voice Call"),
    "WhatsApp calls should create a record prompt"
)
expect(
    !ActivityCallDetector.isCall(appName: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode", windowTitle: "Meeting.swift"),
    "Ordinary editor windows should not be treated as calls"
)
expect(
    !ActivityCallDetector.isCall(appName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", windowTitle: "#general"),
    "Ordinary chat windows should not be treated as calls"
)

let entryOMaticDay = Calendar.current.startOfDay(for: date)
let entryOMaticSegments = [
    ActivitySegment(
        appName: "Editor",
        bundleIdentifier: "com.example.Editor",
        startMinute: 540,
        endMinute: 543,
        startSecond: 540 * 60,
        endSecond: 543 * 60,
        relevance: .related
    ),
    ActivitySegment(
        appName: "Browser",
        bundleIdentifier: "com.example.Browser",
        startMinute: 543,
        endMinute: 550,
        startSecond: 543 * 60 + 20,
        endSecond: 550 * 60,
        relevance: .other
    ),
    ActivitySegment(
        appName: "Chat",
        bundleIdentifier: "com.example.Chat",
        startMinute: 560,
        endMinute: 561,
        relevance: .other
    )
]
let generatedIntervals = EntryOMaticGenerator.intervals(
    from: entryOMaticSegments,
    dayStart: entryOMaticDay,
    existingEntries: [],
    minimumDurationSeconds: 5 * 60,
    maximumGapSeconds: 30
)
expect(generatedIntervals.count == 1 && generatedIntervals[0].durationSeconds == 10 * 60, "Entry-O-Matic should merge short gaps and discard short sessions")
let coveredEntry = TimeEntry(
    title: "Already recorded",
    start: entryOMaticDay.addingTimeInterval(544 * 60),
    end: entryOMaticDay.addingTimeInterval(545 * 60)
)
let uncoveredIntervals = EntryOMaticGenerator.intervals(
    from: entryOMaticSegments,
    dayStart: entryOMaticDay,
    existingEntries: [coveredEntry],
    minimumDurationSeconds: 5 * 60,
    maximumGapSeconds: 30
)
expect(uncoveredIntervals.count == 1 && uncoveredIntervals[0].startSecond == 545 * 60, "Entry-O-Matic should subtract existing time entries")
let overwriteIntervals = EntryOMaticGenerator.intervals(
    from: entryOMaticSegments,
    dayStart: entryOMaticDay,
    existingEntries: [coveredEntry],
    minimumDurationSeconds: 5 * 60,
    maximumGapSeconds: 30,
    overwriteExisting: true
)
expect(overwriteIntervals.count == 1 && overwriteIntervals[0].durationSeconds == 10 * 60, "Entry-O-Matic overwrite mode should retain the full generated interval")

let activityRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MetridayActivitySmoke-(UUID().uuidString)")
let activityHistory = ActivityHistoryStore(rootDirectory: activityRoot)
try! activityHistory.save(trackedActivities, date: date)
expect(activityHistory.load(date: date) == trackedActivities, "Activity history should round-trip through local JSON")
let wrappedActivity = ActivitySegment(
    appName: "Night Editor",
    bundleIdentifier: "com.example.night-editor",
    startMinute: 4 * 60,
    endMinute: 4 * 60 + 30,
    relevance: .related
)
try! activityHistory.save([wrappedActivity], date: wrapDay)
let wrappedLoaded = activityHistory.load(date: wrapDay.addingTimeInterval(-86_400), wrapAtMinute: 5 * 60)
expect(
    wrappedLoaded.contains { $0.id == wrappedActivity.id && $0.startSecond == 23 * 3_600 && $0.endSecond == 23 * 3_600 + 30 * 60 },
    "Wrapped history should load pre-boundary civil activity on the previous logical day axis"
)
let wrappedLogicalActivity = ActivitySegment(
    appName: "Morning Editor",
    bundleIdentifier: "com.example.morning-editor",
    startMinute: 0,
    endMinute: 30,
    startSecond: 0,
    endSecond: 30 * 60,
    relevance: .related
)
try! activityHistory.save([wrappedLogicalActivity], date: wrapDay, wrapAtMinute: 5 * 60)
let wrappedRoundTrip = activityHistory.load(date: wrapDay, wrapAtMinute: 5 * 60)
expect(
    wrappedRoundTrip.contains { $0.id == wrappedLogicalActivity.id && $0.startSecond == 0 && $0.endSecond == 30 * 60 },
    "Wrapped logical activity should round-trip through split civil-day storage"
)
let overlappingDeviceActivities = [
    ActivitySegment(
        appName: "Editor",
        bundleIdentifier: "com.example.Editor",
        deviceName: "MacBook",
        windowTitle: "One",
        startMinute: 800,
        endMinute: 830,
        relevance: .related
    ),
    ActivitySegment(
        appName: "Editor",
        bundleIdentifier: "com.example.Editor",
        deviceName: "iMac",
        windowTitle: "Two",
        startMinute: 810,
        endMinute: 840,
        relevance: .related
    )
]
try! activityHistory.save(overlappingDeviceActivities, date: date.addingTimeInterval(2 * 86400))
expect(
    activityHistory.load(date: date.addingTimeInterval(2 * 86400)).count == 2,
    "Activity history should preserve overlapping activity from different devices"
)
let legacyOtherActivity = ActivitySegment(
    appName: "Linear",
    bundleIdentifier: "com.linear",
    startMinute: 700,
    endMinute: 710,
    relevance: .idle
)
try! activityHistory.save([legacyOtherActivity], date: date.addingTimeInterval(86400))
expect(
    activityHistory.load(date: date.addingTimeInterval(86400)).first?.relevance == .other,
    "Legacy non-idle app activity should migrate away from the idle category"
)
try? FileManager.default.removeItem(at: activityRoot)

Task { @MainActor in
    let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("MetridaySmoke-\(UUID().uuidString)")
    let timeEntryStore = TimeEntryStore(rootDirectory: tempRoot.appendingPathComponent("BulkTimeEntries", isDirectory: true))
    let firstBulkEntryID = timeEntryStore.addEntry(
        title: "Bulk status one",
        projectID: nil,
        start: date.addingTimeInterval(8 * 60 * 60),
        end: date.addingTimeInterval(8 * 60 * 60 + 30 * 60)
    )
    let secondBulkEntryID = timeEntryStore.addEntry(
        title: "Bulk status two",
        projectID: nil,
        start: date.addingTimeInterval(9 * 60 * 60),
        end: date.addingTimeInterval(9 * 60 * 60 + 45 * 60)
    )
    guard let firstBulkEntryID, let secondBulkEntryID else {
        expect(false, "Time entry smoke data should be created")
        return
    }
    expect(
        timeEntryStore.updateBillingStatus(
            for: Set([firstBulkEntryID, secondBulkEntryID]),
            to: .billed
        ) == 2,
        "Bulk billing status update should change every selected time entry"
    )
    let reloadedTimeEntryStore = TimeEntryStore(rootDirectory: tempRoot.appendingPathComponent("BulkTimeEntries", isDirectory: true))
    expect(
        reloadedTimeEntryStore.entries.allSatisfy { $0.billingStatus == .billed },
        "Bulk billing status update should persist to the local archive"
    )
    let renamedEntryID = timeEntryStore.addEntry(
        title: "Repeated title",
        projectID: nil,
        start: date.addingTimeInterval(11 * 60 * 60),
        end: date.addingTimeInterval(11 * 60 * 60 + 15 * 60)
    )
    let secondRenamedEntryID = timeEntryStore.addEntry(
        title: "repeated title",
        projectID: nil,
        start: date.addingTimeInterval(12 * 60 * 60),
        end: date.addingTimeInterval(12 * 60 * 60 + 15 * 60)
    )
    let untouchedEntryID = timeEntryStore.addEntry(
        title: "Keep this title",
        projectID: nil,
        start: date.addingTimeInterval(13 * 60 * 60),
        end: date.addingTimeInterval(13 * 60 * 60 + 15 * 60)
    )
    guard let renamedEntryID, let secondRenamedEntryID, let untouchedEntryID else {
        expect(false, "Batch title smoke data should be created")
        return
    }
    expect(
        timeEntryStore.renameEntries(Set([renamedEntryID, secondRenamedEntryID]), to: "Renamed group") == 2,
        "Batch title update should rename every selected occurrence"
    )
    expect(
        timeEntryStore.entries.first(where: { $0.id == untouchedEntryID })?.title == "Keep this title",
        "Batch title update should leave unselected entries unchanged"
    )
    let reloadedRenamedStore = TimeEntryStore(rootDirectory: tempRoot.appendingPathComponent("BulkTimeEntries", isDirectory: true))
    expect(
        reloadedRenamedStore.entries.filter { $0.id == renamedEntryID || $0.id == secondRenamedEntryID }
            .allSatisfy { $0.title == "Renamed group" },
        "Batch title update should persist to the local archive"
    )
    let reusableTimerEntry = TimeEntry(
        projectID: suggestionProjectID,
        title: "Resume this timer",
        notes: "Timer context",
        start: date.addingTimeInterval(14 * 60 * 60),
        end: date.addingTimeInterval(14 * 60 * 60 + 25 * 60),
        billingStatus: .pending,
        customFields: ["source": "smoke"]
    )
    timeEntryStore.startTimer(reusing: reusableTimerEntry)
    expect(
        timeEntryStore.runningTimer?.title == reusableTimerEntry.title
            && timeEntryStore.runningTimer?.projectID == reusableTimerEntry.projectID
            && timeEntryStore.runningTimer?.billingStatus == .pending
            && timeEntryStore.runningTimer?.customFields["source"] == "smoke",
        "Quick-resume timer should preserve the previous timer context"
    )
    _ = timeEntryStore.stopTimer(at: date.addingTimeInterval(14 * 60 * 60 + 30 * 60))
    expect(
        timeEntryStore.recentTimerEntries(limit: 1).first?.title == reusableTimerEntry.title,
        "Stopped timers should remain available in recent timer suggestions"
    )
    let undoCreatedEntry = timeEntryStore.entries[0]
    let undoReplacedEntry = TimeEntry(
        id: UUID(),
        title: "Restored Entry-O-Matic entry",
        start: date.addingTimeInterval(10 * 60 * 60),
        end: date.addingTimeInterval(10 * 60 * 60 + 15 * 60)
    )
    timeEntryStore.recordEntryOMaticCreation(created: [undoCreatedEntry], replaced: [undoReplacedEntry])
    expect(timeEntryStore.canUndoEntryOMatic, "Entry-O-Matic creation should expose an undo action")
    expect(timeEntryStore.undoEntryOMaticCreation(), "Entry-O-Matic undo should execute")
    expect(!timeEntryStore.entries.contains { $0.id == undoCreatedEntry.id }, "Entry-O-Matic undo should remove generated entries")
    expect(timeEntryStore.entries.contains { $0.id == undoReplacedEntry.id }, "Entry-O-Matic undo should restore replaced entries")
    let categoryFilterStore = ActivityFilterStore(rootDirectory: tempRoot.appendingPathComponent("CategoryFilters", isDirectory: true))
    let categoryStore = ActivityCategoryStore(rootDirectory: tempRoot.appendingPathComponent("Categories", isDirectory: true))
    _ = categoryStore.createCategory(
        name: "Focused coding",
        role: .focused,
        color: .purple,
        matchMode: .any,
        rules: [ActivityFilterRule(field: .application, pattern: "Visual Studio Code")]
    )
    _ = categoryStore.createCategory(
        name: "Distracting video",
        role: .distracting,
        color: .green,
        matchMode: .any,
        rules: [ActivityFilterRule(field: .domain, pattern: "youtube.com")]
    )
    _ = categoryStore.createCategory(
        name: "Focused research",
        role: .focused,
        color: .orange,
        matchMode: .any,
        rules: [ActivityFilterRule(field: .domain, pattern: "github.com")]
    )
    _ = categoryStore.createCategory(
        name: "Two-rule all",
        role: .other,
        color: .purple,
        matchMode: .all,
        rules: [
            ActivityFilterRule(field: .application, pattern: "MultiRule App"),
            ActivityFilterRule(field: .domain, pattern: "example.com")
        ]
    )
    _ = categoryStore.createCategory(
        name: "Two-rule any",
        role: .focused,
        color: .orange,
        matchMode: .any,
        rules: [
            ActivityFilterRule(field: .application, pattern: "AnyRule App"),
            ActivityFilterRule(field: .domain, pattern: "any.example")
        ]
    )
    let allRulesActivity = ActivitySegment(
        appName: "MultiRule App",
        windowTitle: "Example",
        resource: "https://example.com/work",
        startMinute: 630,
        endMinute: 642,
        relevance: .other
    )
    let partialRulesActivity = ActivitySegment(
        appName: "MultiRule App",
        windowTitle: "Other",
        resource: "https://other.example/work",
        startMinute: 642,
        endMinute: 654,
        relevance: .other
    )
    let anyRulesActivity = ActivitySegment(
        appName: "AnyRule App",
        windowTitle: "Any",
        resource: "https://unrelated.example/work",
        startMinute: 654,
        endMinute: 666,
        relevance: .other
    )
    let allRulesCategory = categoryStore.category(for: allRulesActivity, filterStore: categoryFilterStore, date: date)
    let partialRulesCategory = categoryStore.category(for: partialRulesActivity, filterStore: categoryFilterStore, date: date)
    let anyRulesCategory = categoryStore.category(for: anyRulesActivity, filterStore: categoryFilterStore, date: date)
    expect(
        categoryStore.categories.first(where: { $0.name == "Two-rule all" })?.rules.count == 2
            && categoryStore.categories.first(where: { $0.name == "Two-rule any" })?.rules.count == 2,
        "Category creation should preserve every matching rule"
    )
    expect(
        allRulesCategory.name == "Two-rule all"
            && partialRulesCategory.name != "Two-rule all"
            && anyRulesCategory.name == "Two-rule any",
        "Category Any and All matching should evaluate every rule"
    )
    let focusedCategory = categoryStore.category(for: trackedActivities[0], filterStore: categoryFilterStore, date: date)
    let youtubeActivity = ActivitySegment(
        appName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome",
        windowTitle: "YouTube",
        resource: "https://youtube.com/watch?v=1",
        startMinute: 600,
        endMinute: 612,
        relevance: .distracted
    )
    let distractingCategory = categoryStore.category(for: youtubeActivity, filterStore: categoryFilterStore, date: date)
    expect(focusedCategory.role == .focused && focusedCategory.color == .blue, "Focused application rules should resolve to the deep-blue category")
    expect(distractingCategory.role == .distracting && distractingCategory.color == .red, "Distracting domain rules should resolve to the red category")
    let focusedChromeActivity = ActivitySegment(
        appName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome",
        windowTitle: "GitHub",
        resource: "https://github.com/openai",
        startMinute: 612,
        endMinute: 624,
        relevance: .other
    )
    let focusedChromeCategory = categoryStore.category(for: focusedChromeActivity, filterStore: categoryFilterStore, date: date)
    expect(
        focusedChromeActivity.appName == youtubeActivity.appName
            && focusedChromeCategory.role == .focused
            && distractingCategory.role == .distracting,
        "One App source should be able to resolve to different Categories by website rule"
    )
    let categorizedSummary = ActivitySummary(
        segments: categoryStore.applyingCategories(
            to: [youtubeActivity],
            filterStore: categoryFilterStore,
            date: date
        )
    )
    expect(categorizedSummary.distractedMinutes == 12 && categorizedSummary.taskRelatedPercentage == 0, "Category-owned relevance should drive Today and report summaries")
    if let focusedResearch = categoryStore.customCategories.first(where: { $0.name == "Focused research" }) {
        expect(categoryStore.move(focusedResearch, by: -2), "Category priority should move a custom rule ahead of earlier rules")
        expect(categoryStore.customCategories.first?.name == "Focused research", "Category priority should be reflected in first-match order")
    } else {
        expect(false, "Category priority smoke data should exist")
    }
    let categoryArchive = try! categoryStore.exportArchiveData()
    let importedCategoryStore = ActivityCategoryStore(
        rootDirectory: tempRoot.appendingPathComponent("ImportedCategories", isDirectory: true)
    )
    let importedCategoryCount = try! importedCategoryStore.importArchiveData(categoryArchive)
    expect(importedCategoryCount == 5, "Category sync should import custom definitions without duplicating system categories")
    expect(
        importedCategoryStore.categories.contains { $0.name == "Focused coding" && $0.color == .blue }
            && importedCategoryStore.categories.contains { $0.name == "Distracting video" && $0.color == .red },
        "Category sync should preserve matching rules and normalized role colors"
    )
    expect(importedCategoryStore.customCategories.first?.name == "Focused research", "Category sync should preserve custom rule priority")

    let teamRoot = tempRoot.appendingPathComponent("Teams", isDirectory: true)
    let teamStore = TeamStore(rootDirectory: teamRoot)
    guard let teamID = teamStore.createTeam(name: "Smoke Team") else {
        expect(false, "Team store should create a local team")
        return
    }
    guard teamStore.addMember(to: teamID, name: "Teammate", email: "teammate@example.com") != nil else {
        expect(false, "Team store should add a member")
        return
    }
    let teamProjectStore = ProjectStore(rootDirectory: tempRoot.appendingPathComponent("TeamProjects", isDirectory: true))
    guard let teamProjectID = teamProjectStore.createProject(name: "Team Project", teamID: teamID) else {
        expect(false, "Projects should accept a team assignment")
        return
    }
    expect(teamProjectStore.project(teamProjectID)?.teamID == teamID, "Project should preserve its team assignment")
    guard let childProjectID = teamProjectStore.createProject(name: "Child Project", parentID: teamProjectID),
          let nestedProjectID = teamProjectStore.createProject(name: "Nested Project", parentID: childProjectID) else {
        expect(false, "Projects should create nested descendants")
        return
    }
    let nestedScope = teamProjectStore.descendantProjectIDs(including: teamProjectID)
    expect(
        nestedScope == Set([teamProjectID, childProjectID, nestedProjectID]),
        "Selecting a parent project should include every active descendant"
    )
    var nestedReportOptions = ReportOptions()
    nestedReportOptions.projectIDs = [teamProjectID]
    let nestedActivity = ActivitySegment(
        appName: "Nested Editor",
        windowTitle: "Nested activity",
        startMinute: 9 * 60,
        endMinute: 10 * 60,
        relevance: .related,
        projectID: nestedProjectID
    )
    let nestedReport = ReportExporter.csv(
        activityDays: [(date: date, segments: [nestedActivity])],
        timeEntries: [],
        projectStore: teamProjectStore,
        options: nestedReportOptions
    )
    expect(nestedReport.contains("Nested activity"), "Parent project report scope should include nested activity")
    let reloadedTeamStore = TeamStore(rootDirectory: teamRoot)
    expect(reloadedTeamStore.team(teamID)?.members.count == 2, "Teams and members should round-trip through local JSON")

    let preferencesRoot = tempRoot.appendingPathComponent("Preferences", isDirectory: true)
    let preferences = PreferencesStore(rootDirectory: preferencesRoot)
    preferences.trackWeekends = false
    preferences.trackOnlyDuringWorkingHours = true
    preferences.workingHoursStartMinute = 9 * 60
    preferences.workingHoursEndMinute = 18 * 60
    preferences.automaticallyZoomTimelineToWorkingHours = true
    preferences.wrapDaysAtMinute = 5 * 60
    let calendar = Calendar.current
    let weekdayWorkTime = calendar.date(from: DateComponents(year: 2026, month: 8, day: 17, hour: 10))!
    let weekdayEvening = calendar.date(from: DateComponents(year: 2026, month: 8, day: 17, hour: 20))!
    let weekendWorkTime = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 10))!
    expect(preferences.shouldTrack(at: weekdayWorkTime), "Working-hour preferences should allow an in-range weekday")
    expect(!preferences.shouldTrack(at: weekdayEvening), "Working-hour preferences should exclude out-of-range time")
    expect(!preferences.shouldTrack(at: weekendWorkTime), "Working-hour preferences should exclude weekends")
    preferences.workingHoursStartMinute = 22 * 60
    preferences.workingHoursEndMinute = 6 * 60
    preferences.reviewReminderIntervalMinutes = 30
    preferences.includeSubprojectsWhenSelectingProject = false
    let overnightWorkTime = calendar.date(from: DateComponents(year: 2026, month: 8, day: 17, hour: 23))!
    let overnightBreakTime = calendar.date(from: DateComponents(year: 2026, month: 8, day: 17, hour: 12))!
    expect(preferences.shouldTrack(at: overnightWorkTime), "Working-hour preferences should support overnight windows")
    expect(!preferences.shouldTrack(at: overnightBreakTime), "Working-hour preferences should exclude overnight gaps")
    let reloadedPreferences = PreferencesStore(rootDirectory: preferencesRoot)
    expect(reloadedPreferences.trackWeekends == false, "Preferences should round-trip through local JSON")
    expect(reloadedPreferences.automaticallyZoomTimelineToWorkingHours, "Timeline zoom preference should round-trip through local JSON")
    expect(reloadedPreferences.autoStopTimerOnSleep, "Preferences should default to stopping timers on sleep")
    expect(reloadedPreferences.reviewReminderIntervalMinutes == 30, "Review reminder frequency should round-trip through local JSON")
    expect(!reloadedPreferences.includeSubprojectsWhenSelectingProject, "Project selection preference should round-trip through local JSON")
    expect(reloadedPreferences.wrapDaysAtMinute == 5 * 60, "Wrap-days preference should round-trip through local JSON")

    let reminderPreferencesRoot = tempRoot.appendingPathComponent("ReminderPreferences", isDirectory: true)
    let reminderStore = ReminderStore(rootDirectory: reminderPreferencesRoot)
    reminderStore.hideRecurringReminders = true
    reminderStore.setListIncluded("Work", included: true)
    let reloadedReminderStore = ReminderStore(rootDirectory: reminderPreferencesRoot)
    expect(reloadedReminderStore.hideRecurringReminders, "Reminder filters should persist recurring-item preference")
    expect(reloadedReminderStore.includedListTitles.contains("Work"), "Reminder filters should persist selected lists")

    let calendarPreferencesRoot = tempRoot.appendingPathComponent("CalendarPreferences", isDirectory: true)
    let calendarStore = CalendarEventStore(rootDirectory: calendarPreferencesRoot)
    calendarStore.setCalendarIncluded("Work", included: true)
    let reloadedCalendarStore = CalendarEventStore(rootDirectory: calendarPreferencesRoot)
    expect(reloadedCalendarStore.includedCalendarTitles.contains("Work"), "Calendar filters should persist selected calendars")

    let calendarEvent = CalendarEventItem(
        id: "calendar-smoke",
        title: "Research meeting",
        calendarTitle: "Work",
        location: "Room 1",
        notes: "Agenda",
        urlString: "https://example.com/meeting",
        start: weekdayWorkTime,
        end: weekdayWorkTime.addingTimeInterval(45 * 60)
    )
    expect(calendarEvent.durationSeconds == 45 * 60, "Calendar events should expose offline duration")

    let phoneCallRoot = tempRoot.appendingPathComponent("CallHistoryDB", isDirectory: true)
    try! FileManager.default.createDirectory(at: phoneCallRoot, withIntermediateDirectories: true)
    let phoneCallDatabaseURL = phoneCallRoot.appendingPathComponent("CallHistory.storedata")
    var phoneDatabase: OpaquePointer?
    expect(
        sqlite3_open_v2(
            phoneCallDatabaseURL.path,
            &phoneDatabase,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
            nil
        ) == SQLITE_OK,
        "Phone call smoke database should open"
    )
    if let phoneDatabase {
        expect(
            sqliteExec(
                phoneDatabase,
                "CREATE TABLE ZCALLRECORD (Z_PK INTEGER PRIMARY KEY, ZDATE REAL, ZDURATION REAL, ZADDRESS TEXT, ZSERVICE_PROVIDER TEXT)"
            ),
            "Phone call smoke database should create its call table"
        )
        let phoneCallStart = calendar.date(bySettingHour: 11, minute: 30, second: 0, of: date)!
        var insertStatement: OpaquePointer?
        expect(
            sqlite3_prepare_v2(
                phoneDatabase,
                "INSERT INTO ZCALLRECORD (ZDATE, ZDURATION, ZADDRESS, ZSERVICE_PROVIDER) VALUES (?, ?, ?, ?)",
                -1,
                &insertStatement,
                nil
            ) == SQLITE_OK,
            "Phone call smoke insert should prepare"
        )
        if let insertStatement {
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_double(insertStatement, 1, phoneCallStart.timeIntervalSinceReferenceDate)
            sqlite3_bind_double(insertStatement, 2, 30 * 60)
            sqlite3_bind_text(insertStatement, 3, "555-0100", -1, transient)
            sqlite3_bind_text(insertStatement, 4, "FaceTime", -1, transient)
            expect(sqlite3_step(insertStatement) == SQLITE_DONE, "Phone call smoke insert should succeed")
            sqlite3_finalize(insertStatement)
        }
        sqlite3_close(phoneDatabase)
    }
    let phoneCallStore = PhoneCallStore(databaseURL: phoneCallDatabaseURL)
    phoneCallStore.loadCalls(for: date)
    expect(phoneCallStore.databaseAvailable, "Phone call store should recognize a readable call history database")
    expect(phoneCallStore.calls.count == 1, "Phone call store should load calls for the selected day")
    expect(phoneCallStore.calls.first?.serviceProvider == "FaceTime", "Phone call store should preserve service provider")
    expect(phoneCallStore.calls.first?.durationSeconds == 30 * 60, "Phone call store should preserve call duration")
    let phoneCallPreferencesRoot = tempRoot.appendingPathComponent("PhoneCallPreferences", isDirectory: true)
    let filteredPhoneCallStore = PhoneCallStore(
        databaseURL: phoneCallDatabaseURL,
        rootDirectory: phoneCallPreferencesRoot
    )
    filteredPhoneCallStore.loadCalls(for: date)
    filteredPhoneCallStore.setAddressHidden("555-0100", hidden: true)
    expect(filteredPhoneCallStore.calls.isEmpty, "Phone call filters should hide matching calls from the timeline")
    let reloadedPhoneCallStore = PhoneCallStore(
        databaseURL: phoneCallDatabaseURL,
        rootDirectory: phoneCallPreferencesRoot
    )
    reloadedPhoneCallStore.loadCalls(for: date)
    expect(reloadedPhoneCallStore.isAddressHidden("555-0100"), "Phone call filters should persist hidden addresses")
    expect(reloadedPhoneCallStore.calls.isEmpty, "Persisted phone call filters should apply during reload")
    reloadedPhoneCallStore.showAllAddresses()
    expect(reloadedPhoneCallStore.calls.count == 1, "Phone call filters should support restoring all addresses")
    reloadedPhoneCallStore.setAddressHidden("555-0100", hidden: true)
    reloadedPhoneCallStore.setAddressHidden("555-0100", hidden: false)
    expect(reloadedPhoneCallStore.calls.count == 1, "Phone call filters should support restoring one address")

    let screenTimeRoot = tempRoot.appendingPathComponent("ScreenTime", isDirectory: true)
    try! FileManager.default.createDirectory(at: screenTimeRoot, withIntermediateDirectories: true)
    let screenTimeDatabaseURL = screenTimeRoot.appendingPathComponent("knowledgeC.db")
    var screenTimeDatabase: OpaquePointer?
    expect(
        sqlite3_open_v2(
            screenTimeDatabaseURL.path,
            &screenTimeDatabase,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
            nil
        ) == SQLITE_OK,
        "Screen Time smoke database should open"
    )
    if let screenTimeDatabase {
        expect(
            sqliteExec(
                screenTimeDatabase,
                "CREATE TABLE ZOBJECT (Z_PK INTEGER PRIMARY KEY, ZSTARTDATE REAL, ZENDDATE REAL, ZVALUESTRING TEXT, ZSTREAMNAME TEXT)"
            ),
            "Screen Time smoke database should create its object table"
        )
        let screenTimeStart = calendar.date(bySettingHour: 13, minute: 15, second: 0, of: date)!
        var insertStatement: OpaquePointer?
        expect(
            sqlite3_prepare_v2(
                screenTimeDatabase,
                "INSERT INTO ZOBJECT (ZSTARTDATE, ZENDDATE, ZVALUESTRING, ZSTREAMNAME) VALUES (?, ?, ?, ?)",
                -1,
                &insertStatement,
                nil
            ) == SQLITE_OK,
            "Screen Time smoke insert should prepare"
        )
        if let insertStatement {
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_double(insertStatement, 1, screenTimeStart.timeIntervalSinceReferenceDate)
            sqlite3_bind_double(insertStatement, 2, screenTimeStart.addingTimeInterval(30 * 60).timeIntervalSinceReferenceDate)
            sqlite3_bind_text(insertStatement, 3, "com.apple.Safari", -1, transient)
            sqlite3_bind_text(insertStatement, 4, "/app/usage", -1, transient)
            expect(sqlite3_step(insertStatement) == SQLITE_DONE, "Screen Time smoke insert should succeed")
            sqlite3_finalize(insertStatement)
        }
        sqlite3_close(screenTimeDatabase)
    }
    let screenTimeStore = ScreenTimeStore(
        databaseURL: screenTimeDatabaseURL,
        archiveRootDirectory: screenTimeRoot.appendingPathComponent("Archive", isDirectory: true)
    )
    screenTimeStore.load(for: date)
    expect(screenTimeStore.databaseAvailable, "Screen Time store should recognize a readable knowledge database")
    expect(screenTimeStore.segments.count == 1, "Screen Time store should load usage for the selected day")
    expect(screenTimeStore.segments.first?.appName == "Safari", "Screen Time store should resolve known bundle names")
    expect(screenTimeStore.segments.first?.deviceName == "Screen Time", "Screen Time activities should retain their source device")

    let insightSegments = [
        ActivitySegment(appName: "Xcode", startMinute: 9 * 60, endMinute: 10 * 60, relevance: .related),
        ActivitySegment(appName: "Xcode", startMinute: 10 * 60, endMinute: 10 * 60 + 20, relevance: .related),
        ActivitySegment(appName: "YouTube", startMinute: 10 * 60 + 30, endMinute: 10 * 60 + 40, relevance: .distracted)
    ]
    let insights = ActivityInsights.generate(from: insightSegments)
    expect(insights.count == 3, "Activity insights should generate the configured local highlights")
    expect(insights.contains { $0.id == "top-app" }, "Activity insights should identify the main application")
    expect(insights.contains { $0.id == "distraction" }, "Activity insights should identify distraction evidence")
    expect(insights.first?.source == "local_activity", "Local activity insights should retain an auditable source")
    expect(insights.contains { $0.durationSeconds == 3600 }, "Activity insights should retain evidence duration")

    let exclusionRoot = tempRoot.appendingPathComponent("Exclusions", isDirectory: true)
    let exclusions = ExclusionStore(rootDirectory: exclusionRoot)
    exclusions.add(bundleIdentifier: "com.example.PrivateApp")
    expect(exclusions.isExcluded("com.example.PrivateApp"), "Excluded applications should be recognized")
    let reloadedExclusions = ExclusionStore(rootDirectory: exclusionRoot)
    expect(reloadedExclusions.isExcluded("com.example.PrivateApp"), "Exclusions should round-trip through local JSON")
    _ = exclusions.addRule(
        field: .domain,
        pattern: "private.example",
        comparison: .equals
    )
    expect(
        exclusions.isExcluded(
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Private",
            resource: "https://private.example/report",
            deviceName: "This Mac"
        ),
        "Exclusion rules should match browser domains"
    )
    exclusions.remove(bundleIdentifier: "com.example.PrivateApp")

    let projectRoot = tempRoot.appendingPathComponent("Projects", isDirectory: true)
    let projectStore = ProjectStore(rootDirectory: projectRoot)
    guard let researchProjectID = projectStore.createProject(name: "Smoke Research") else {
        expect(false, "Project store should create a project")
        return
    }
    guard let childProjectID = projectStore.createProject(
        name: "Smoke Subproject",
        parentID: researchProjectID
    ) else {
        expect(false, "Project store should create a child project")
        return
    }
    let automaticRuleCount = projectStore.addDefaultNameRules(
        projectID: childProjectID,
        projectName: "Smoke Subproject"
    )
    expect(automaticRuleCount == 2, "New projects should offer title and path matching rules")
    expect(
        projectStore.rules(for: childProjectID).contains { $0.field == .titleContains }
            && projectStore.rules(for: childProjectID).contains { $0.field == .resourceContains },
        "Default project name rules should cover titles and paths"
    )
    expect(
        projectStore.hierarchyPath(for: childProjectID) == "Smoke Research > Smoke Subproject",
        "Project hierarchy paths should include parent projects"
    )
    expect(
        projectStore.project(researchProjectID)?.defaultBillingStatus == .automatic
            && projectStore.project(childProjectID)?.defaultBillingStatus == .automatic,
        "New project defaults should inherit billing status automatically"
    )
    expect(
        projectStore.resolvedBillingStatus(for: childProjectID) == .billable,
        "Automatic billing should use the local Billable fallback when no ancestor is explicit"
    )
    if var parentProject = projectStore.project(researchProjectID) {
        parentProject.defaultBillingStatus = .notBillable
        projectStore.updateProject(parentProject)
    }
    expect(
        projectStore.resolvedBillingStatus(for: childProjectID) == .notBillable,
        "Automatic child billing should inherit an explicit parent status"
    )
    if var childProject = projectStore.project(childProjectID) {
        childProject.defaultBillingStatus = .paid
        projectStore.updateProject(childProject)
    }
    expect(
        projectStore.resolvedBillingStatus(for: childProjectID) == .paid,
        "Explicit child billing should override an inherited parent status"
    )
    expect(
        !projectStore.validParentProjects(for: researchProjectID).contains { $0.id == childProjectID },
        "Project hierarchies should not allow a descendant to become its parent's parent"
    )
    guard let archivedProjectID = projectStore.createProject(name: "Archived Smoke Project"),
          let archivedProject = projectStore.project(archivedProjectID) else {
        expect(false, "Project store should create an archive smoke project")
        return
    }
    projectStore.archive(archivedProject)
    expect(projectStore.archivedProjects.contains { $0.id == archivedProjectID }, "Archived projects should remain recoverable")
    expect(!projectStore.activeProjects.contains { $0.id == archivedProjectID }, "Archived projects should leave the active list")
    if let archivedProject = projectStore.project(archivedProjectID) {
        projectStore.restore(archivedProject)
    }
    expect(projectStore.activeProjects.contains { $0.id == archivedProjectID }, "Archived projects should be restorable")
    guard let hiddenParentID = projectStore.createProject(name: "Archived Parent"),
          let hiddenChildID = projectStore.createProject(name: "Archived Child", parentID: hiddenParentID),
          let hiddenParent = projectStore.project(hiddenParentID) else {
        expect(false, "Project store should create nested archive smoke data")
        return
    }
    projectStore.archive(hiddenParent)
    if let hiddenChild = projectStore.project(hiddenChildID) {
        projectStore.archive(hiddenChild)
    }
    if let archivedChild = projectStore.project(hiddenChildID) {
        projectStore.restore(archivedChild)
    }
    expect(projectStore.project(hiddenChildID)?.parentID == nil, "Restoring a child of an archived project should promote it safely")
    if var cyclicProject = projectStore.project(researchProjectID) {
        cyclicProject.parentID = childProjectID
        projectStore.updateProject(cyclicProject)
    }
    expect(
        projectStore.project(researchProjectID)?.parentID == nil,
        "Project updates should reject hierarchy cycles"
    )
    if var billableProject = projectStore.project(researchProjectID) {
        billableProject.billingRate = 120
        billableProject.currency = "usd"
        billableProject.defaultBillingStatus = .notBillable
        projectStore.updateProject(billableProject)
    }
    expect(projectStore.project(researchProjectID)?.billingRate == 120, "Projects should store hourly billing rates")
    expect(projectStore.project(researchProjectID)?.currency == "USD", "Project currencies should normalize to uppercase")
    expect(projectStore.project(researchProjectID)?.defaultBillingStatus == .notBillable, "Projects should store a default billing status")
    expect(ProjectStore(rootDirectory: projectRoot).project(researchProjectID)?.billingRate == 120, "Billing rates should persist")
    expect(ProjectStore(rootDirectory: projectRoot).project(researchProjectID)?.defaultBillingStatus == .notBillable, "Project default billing status should persist")
    expect(
        projectStore.addRule(
            projectID: researchProjectID,
            field: .bundleIdentifier,
            pattern: "com.microsoft.VSCode"
        ) != nil,
        "Project store should create an application rule"
    )
    let projectActivity = ActivitySegment(
        appName: "Visual Studio Code",
        bundleIdentifier: "com.microsoft.VSCode",
        windowTitle: "Project.swift",
        resource: "/tmp/Project.swift",
        startMinute: 600,
        endMinute: 630,
        relevance: .related
    )
    expect(
        projectStore.matchingProjectID(for: projectActivity) == researchProjectID,
        "Project rules should assign matching activities"
    )
    guard let timeRuleProjectID = projectStore.createProject(name: "Smoke Time Rules") else {
        expect(false, "Project store should create a time-rule project")
        return
    }
    expect(
        projectStore.addRule(
            projectID: timeRuleProjectID,
            field: .startTime,
            pattern: "08:00",
            comparison: .equals
        ) != nil,
        "Project rules should support start-time matching"
    )
    let tenAMActivity = ActivitySegment(
        appName: "Calendar",
        windowTitle: "Planning",
        startMinute: 480,
        endMinute: 510,
        relevance: .other
    )
    expect(
        projectStore.matchingProjectID(for: tenAMActivity) == timeRuleProjectID,
        "Start-time project rules should assign matching activities"
    )
    expect(
        projectStore.addRule(
            projectID: timeRuleProjectID,
            field: .dayOfWeek,
            pattern: "Monday",
            comparison: .equals
        ) != nil,
        "Project rules should support day-of-week matching"
    )
    var mondayComponents = DateComponents()
    mondayComponents.calendar = Calendar(identifier: .gregorian)
    mondayComponents.timeZone = .current
    mondayComponents.year = 2026
    mondayComponents.month = 8
    mondayComponents.day = 17
    mondayComponents.hour = 10
    let mondayAtTen = mondayComponents.calendar!.date(from: mondayComponents)!
    let mondayActivity = ActivitySegment(
        appName: "Calendar",
        windowTitle: "Planning",
        startMinute: 615,
        endMinute: 645,
        relevance: .other
    )
    expect(
        projectStore.matchingProjectID(for: mondayActivity, date: mondayAtTen) == timeRuleProjectID,
        "Day-of-week project rules should assign matching activities"
    )

    let filterRoot = tempRoot.appendingPathComponent("Filters", isDirectory: true)
    let filterStore = ActivityFilterStore(rootDirectory: filterRoot)
    let savedFilter = ActivityFilterDefinition(
        name: "Editors",
        color: .purple,
        matchMode: .all,
        rules: [
            ActivityFilterRule(
                field: .application,
                pattern: "Visual Studio Code"
            ),
            ActivityFilterRule(
                field: .device,
                pattern: "This Mac"
            )
        ]
    )
    filterStore.save(savedFilter)
    expect(filterStore.matches(savedFilter, activity: projectActivity), "Saved filters should match all configured activity properties")
    expect(
        !filterStore.matches(
            savedFilter,
            activity: ActivitySegment(
                appName: "Google Chrome",
                deviceName: "This Mac",
                startMinute: 600,
                endMinute: 605,
                relevance: .other
            )
        ),
        "Saved filters should exclude non-matching activities"
    )
    let weekdayFormatter = DateFormatter()
    weekdayFormatter.locale = Locale(identifier: "en_US_POSIX")
    weekdayFormatter.dateFormat = "EEEE"
    let scheduleFilter = ActivityFilterDefinition(
        name: "Schedule",
        matchMode: .all,
        rules: [
            ActivityFilterRule(field: .startTime, pattern: "10:00", comparison: .equals),
            ActivityFilterRule(field: .dayOfWeek, pattern: weekdayFormatter.string(from: date), comparison: .equals)
        ]
    )
    expect(
        filterStore.matches(scheduleFilter, activity: projectActivity, date: date),
        "Saved filters should match start time and day of week"
    )
    expect(
        ActivityFilterStore(rootDirectory: filterRoot).filter(savedFilter.id)?.name == "Editors",
        "Saved filters should persist through local JSON"
    )
    let activityPreferencesRoot = tempRoot.appendingPathComponent("ActivityPreferences", isDirectory: true)
    let activityPreferences = ActivitiesPreferencesStore(rootDirectory: activityPreferencesRoot)
    activityPreferences.includeTimeEntries = false
    activityPreferences.showWindowTitles = false
    activityPreferences.showActivityDateRanges = true
    activityPreferences.includeTitlesInAdditionToPaths = false
    activityPreferences.activityTimeRange = .lastSevenDays
    activityPreferences.groupWebsitesIndependently = true
    activityPreferences.groupPathsIndependently = true
    activityPreferences.groupPathsBy = .filePathOnly
    activityPreferences.activityDisplayMode = "unified"
    activityPreferences.groupByProject = false
    activityPreferences.groupByDevice = true
    activityPreferences.includeIdle = true
    activityPreferences.selectedDevice = "Test Mac"
    activityPreferences.timelineOrientation = .vertical
    activityPreferences.collapseActivitiesShorterThanSeconds = 15
    let reloadedActivityPreferences = ActivitiesPreferencesStore(rootDirectory: activityPreferencesRoot)
    expect(!reloadedActivityPreferences.includeTimeEntries, "Activity display preferences should persist timeline visibility")
    expect(!reloadedActivityPreferences.showWindowTitles, "Activity display preferences should persist title visibility")
    expect(reloadedActivityPreferences.showActivityDateRanges, "Activity display preferences should persist app-usage date ranges")
    expect(!reloadedActivityPreferences.includeTitlesInAdditionToPaths, "Activity display preferences should persist title and path composition")
    expect(reloadedActivityPreferences.groupWebsitesIndependently, "Activity display preferences should persist independent website grouping")
    expect(reloadedActivityPreferences.groupPathsIndependently, "Activity display preferences should persist independent path grouping")
    expect(reloadedActivityPreferences.groupPathsBy == .filePathOnly, "Activity display preferences should persist path grouping depth")
    expect(reloadedActivityPreferences.activityTimeRange == .lastSevenDays, "Activity display preferences should persist the selected usage range")
    expect(reloadedActivityPreferences.activityDisplayMode == "unified", "Activity display mode should persist")
    expect(!reloadedActivityPreferences.groupByProject && reloadedActivityPreferences.groupByDevice, "Activity grouping preferences should persist")
    expect(reloadedActivityPreferences.includeIdle && reloadedActivityPreferences.selectedDevice == "Test Mac", "Activity filter preferences should persist")
    expect(reloadedActivityPreferences.timelineOrientation == .vertical, "Timeline orientation should persist")
    expect(reloadedActivityPreferences.collapseActivitiesShorterThanSeconds == 15, "Activity display preferences should persist short-activity collapsing")

    var collapsedSummary = ActivitySegment(
        appName: "(Entries shorter than 15s each)",
        startMinute: 10 * 60,
        endMinute: 10 * 60 + 1,
        relevance: .other
    )
    collapsedSummary.collapsedActivityIDs = [UUID(), UUID()]
    collapsedSummary.collapsedDurationSeconds = 23
    expect(collapsedSummary.isCollapsedSummary && collapsedSummary.durationSeconds == 23, "Collapsed activity summaries should preserve aggregate duration")
    expect(
        projectStore.addRule(
            projectID: researchProjectID,
            field: .domain,
            pattern: "example.com"
        ) != nil,
        "Project store should create a domain rule"
    )
    let domainActivity = ActivitySegment(
        appName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome",
        windowTitle: "Example",
        resource: "https://example.com/docs",
        startMinute: 600,
        endMinute: 630,
        relevance: .other
    )
    expect(
        projectStore.matchingProjectID(for: domainActivity) == researchProjectID,
        "Domain rules should assign matching browser activities"
    )
    _ = projectStore.addRule(
        projectID: researchProjectID,
        field: .titleContains,
        pattern: "Project.swift",
        comparison: .equals
    )
    expect(
        projectStore.matchingProjectID(
            for: ActivitySegment(
                appName: "Unknown Editor",
                bundleIdentifier: "com.example.Editor",
                windowTitle: "Project.swift",
                startMinute: 600,
                endMinute: 630,
                relevance: .other
            )
        ) == researchProjectID,
        "Project rules should support exact title comparisons"
    )
    _ = projectStore.addRule(
        projectID: childProjectID,
        field: .keyword,
        pattern: "docs || article"
    )
    expect(
        projectStore.matchingProjectID(
            for: ActivitySegment(
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                windowTitle: "Article review",
                resource: "https://news.other.com",
                startMinute: 600,
                endMinute: 630,
                relevance: .other
            )
        ) == childProjectID,
        "Project rules should support OR expressions in patterns"
    )
    _ = projectStore.addRule(
        projectID: childProjectID,
        field: .titleContains,
        pattern: "Docs*",
        comparison: .like
    )
    expect(
        projectStore.matchingProjectID(
            for: ActivitySegment(
                appName: "Safari",
                bundleIdentifier: "com.apple.Safari",
                windowTitle: "Docs - project",
                startMinute: 600,
                endMinute: 630,
                relevance: .other
            )
        ) == childProjectID,
        "Project rules should support wildcard comparisons"
    )
    if let firstRule = projectStore.rules.first {
        projectStore.moveRule(firstRule, by: 1)
        expect(projectStore.rules.count > 1 && projectStore.rules[1].id == firstRule.id, "Project rules should support priority reordering")
    }
    expect(
        projectStore.matchingProjectID(
            for: ActivitySegment(
                appName: "Unknown",
                bundleIdentifier: "com.example.Unknown",
                startMinute: 600,
                endMinute: 630,
                relevance: .idle
            )
        ) == nil,
        "Unmatched activities should remain unassigned"
    )

    let projectArchive = try! projectStore.exportArchiveData()
    let importedProjectStore = ProjectStore(rootDirectory: tempRoot.appendingPathComponent("ImportedProjects", isDirectory: true))
    let importedProjectCounts = try! importedProjectStore.importArchiveData(projectArchive)
    let importedChild = importedProjectStore.projects.first { $0.name == "Smoke Subproject" }
    expect(importedProjectCounts.projects >= 2, "Project archives should import new project hierarchies")
    expect(
        importedChild.map { importedProjectStore.hierarchyPath(for: $0.id) } == Optional("Smoke Research > Smoke Subproject"),
        "Project archives should preserve hierarchy paths"
    )
    expect(importedProjectCounts.rules > 0, "Project archives should import project rules")

    let historicalActivityRoot = tempRoot.appendingPathComponent("HistoricalActivity", isDirectory: true)
    let historicalActivity = ActivitySegment(
        id: UUID(),
        appName: "Unknown Editor",
        bundleIdentifier: "com.example.ManualAssignment",
        windowTitle: "A manually assigned activity",
        startMinute: 700,
        endMinute: 730,
        relevance: .other,
        projectID: researchProjectID
    )
    let historicalActivityStore = ActivityHistoryStore(rootDirectory: historicalActivityRoot)
    try! historicalActivityStore.save([historicalActivity], date: date)
    let monitorPreferences = PreferencesStore(rootDirectory: tempRoot.appendingPathComponent("MonitorPreferences", isDirectory: true))
    let monitorExclusions = ExclusionStore(rootDirectory: tempRoot.appendingPathComponent("MonitorExclusions", isDirectory: true))
    let monitor = AppActivityMonitor(
        rootDirectory: historicalActivityRoot,
        projectStore: projectStore,
        preferences: monitorPreferences,
        exclusionStore: monitorExclusions
    )
    monitor.selectDate(date)
    monitor.reapplyRules(for: date)
    expect(
        historicalActivityStore.load(date: date).first?.projectID == researchProjectID,
        "Reapplying rules should preserve manually assigned unmatched activities"
    )

    let overlapDay = Calendar.current.startOfDay(for: date)
    let overlapActivity = ActivitySegment(
        appName: "Research Editor",
        bundleIdentifier: "com.example.ResearchEditor",
        windowTitle: "Overlap.swift",
        startMinute: 10 * 60,
        endMinute: 10 * 60 + 20,
        relevance: .related,
        projectID: researchProjectID
    )
    let overlapEntry = TimeEntry(
        projectID: researchProjectID,
        title: "Research call",
        start: overlapDay.addingTimeInterval(10 * 3_600 + 5 * 60),
        end: overlapDay.addingTimeInterval(10 * 3_600 + 15 * 60)
    )
    var overlapReportOptions = ReportOptions()
    overlapReportOptions.include = .both
    overlapReportOptions.columns = [.type, .duration]
    let absorbedRows = ReportExporter.tableRows(
        activityDays: [(date: overlapDay, segments: [overlapActivity])],
        timeEntries: [overlapEntry],
        projectStore: projectStore,
        options: overlapReportOptions
    )
    let absorbedMinutes = absorbedRows.dropFirst().reduce(0.0) { total, row in
        total + (Double(row[1]) ?? 0)
    }
    expect(abs(absorbedMinutes - 20) < 0.01, "Reports should absorb app usage covered by time entries by default")
    overlapReportOptions.includeCoveredAppUsage = true
    let overlappingRows = ReportExporter.tableRows(
        activityDays: [(date: overlapDay, segments: [overlapActivity])],
        timeEntries: [overlapEntry],
        projectStore: projectStore,
        options: overlapReportOptions
    )
    let overlappingMinutes = overlappingRows.dropFirst().reduce(0.0) { total, row in
        total + (Double(row[1]) ?? 0)
    }
    expect(abs(overlappingMinutes - 30) < 0.01, "Reports should optionally include overlapping app usage")
    overlapReportOptions.include = .appUsage
    let rawAppUsageRows = ReportExporter.tableRows(
        activityDays: [(date: overlapDay, segments: [overlapActivity])],
        timeEntries: [overlapEntry],
        projectStore: projectStore,
        options: overlapReportOptions
    )
    let rawAppUsageMinutes = rawAppUsageRows.dropFirst().reduce(0.0) { total, row in
        total + (Double(row[1]) ?? 0)
    }
    expect(abs(rawAppUsageMinutes - 20) < 0.01, "App-usage-only reports should retain raw activity duration")

    let screenTimeActivity = ActivitySegment(
        appName: "Mobile Safari",
        deviceName: "Screen Time",
        resource: "https://example.com",
        startMinute: 11 * 60,
        endMinute: 11 * 60 + 5,
        relevance: .related
    )
    var screenTimeReportOptions = ReportOptions()
    screenTimeReportOptions.include = .appUsage
    screenTimeReportOptions.columns = [.device, .application, .duration]
    let screenTimeRows = ReportExporter.tableRows(
        activityDays: [(date: overlapDay, segments: [screenTimeActivity])],
        timeEntries: [],
        projectStore: projectStore,
        options: screenTimeReportOptions
    )
    expect(screenTimeRows.dropFirst().contains { $0.contains("Screen Time") }, "Reports should retain imported Screen Time device provenance")

    var monthReportOptions = ReportOptions()
    monthReportOptions.include = .timeEntries
    monthReportOptions.groupBy = .month
    monthReportOptions.columns = [.group, .duration]
    let monthRows = ReportExporter.tableRows(
        activityDays: [(date: overlapDay, segments: [])],
        timeEntries: [overlapEntry],
        projectStore: projectStore,
        options: monthReportOptions
    )
    expect(monthRows.dropFirst().contains { $0.first == "2026-08" }, "Reports should group entries by month")

    var hourReportOptions = ReportOptions()
    hourReportOptions.include = .timeEntries
    hourReportOptions.groupBy = .hour
    hourReportOptions.columns = [.group, .duration]
    let hourRows = ReportExporter.tableRows(
        activityDays: [(date: overlapDay, segments: [])],
        timeEntries: [overlapEntry],
        projectStore: projectStore,
        options: hourReportOptions
    )
    expect(hourRows.dropFirst().contains { $0.first?.contains(":00") == true }, "Reports should group entries by hour")

    var weekDayReportOptions = ReportOptions()
    weekDayReportOptions.include = .timeEntries
    weekDayReportOptions.groupBy = .weekAndDay
    weekDayReportOptions.columns = [.group, .duration]
    let weekDayRows = ReportExporter.tableRows(
        activityDays: [(date: overlapDay, segments: [])],
        timeEntries: [overlapEntry],
        projectStore: projectStore,
        options: weekDayReportOptions
    )
    expect(weekDayRows.dropFirst().contains { $0.first?.contains("/") == true }, "Reports should group entries by week and day")

    var documentReportOptions = ReportOptions()
    documentReportOptions.include = .appUsage
    documentReportOptions.groupBy = .document
    documentReportOptions.columns = [.group, .resource]
    let documentRows = ReportExporter.tableRows(
        activityDays: [(date: overlapDay, segments: [screenTimeActivity])],
        timeEntries: [],
        projectStore: projectStore,
        options: documentReportOptions
    )
    expect(documentRows.dropFirst().contains { $0.first == "https://example.com" }, "Reports should group app usage by document or website")

    let shortActivity = ActivitySegment(
        appName: "Quick Preview",
        startMinute: 12 * 60,
        endMinute: 12 * 60,
        startSecond: 12 * 60 * 60,
        endSecond: 12 * 60 * 60 + 30,
        relevance: .related
    )
    var shortEntryOptions = ReportOptions()
    shortEntryOptions.include = .appUsage
    shortEntryOptions.includeShortEntries = false
    let shortEntryRows = ReportExporter.tableRows(
        activityDays: [(date: overlapDay, segments: [shortActivity])],
        timeEntries: [],
        projectStore: projectStore,
        options: shortEntryOptions
    )
    expect(shortEntryRows.count == 1, "Advanced reports should be able to hide app usage shorter than one minute")

    let overnightEntry = TimeEntry(
        projectID: researchProjectID,
        title: "Overnight review",
        start: overlapDay.addingTimeInterval(23 * 3_600 + 30 * 60),
        end: overlapDay.addingTimeInterval(24 * 3_600 + 30 * 60)
    )
    var overnightOptions = ReportOptions()
    overnightOptions.include = .timeEntries
    overnightOptions.columns = [.date, .duration]
    let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: overlapDay)!
    let overnightRows = ReportExporter.tableRows(
        activityDays: [
            (date: overlapDay, segments: []),
            (date: nextDay, segments: [])
        ],
        timeEntries: [overnightEntry],
        projectStore: projectStore,
        options: overnightOptions
    )
    let overnightMinutes = overnightRows.dropFirst().reduce(0.0) { total, row in
        total + (Double(row[1]) ?? 0)
    }
    expect(overnightRows.count == 3 && abs(overnightMinutes - 60) < 0.01, "Reports should split cross-midnight time entries by day")

    let timeEntryRoot = tempRoot.appendingPathComponent("TimeEntries", isDirectory: true)
    let timeEntries = TimeEntryStore(rootDirectory: timeEntryRoot)
    let entryStart = date.addingTimeInterval(9 * 60 * 60)
    let entryEnd = entryStart.addingTimeInterval(45 * 60)
    guard let manualEntryID = timeEntries.addEntry(
        title: "Offline research call",
        projectID: researchProjectID,
        notes: "Smoke test",
        start: entryStart,
        end: entryEnd,
        billingStatus: .pending
    ) else {
        expect(false, "Time entry store should add a manual entry")
        return
    }
    expect(timeEntries.entries(for: date).contains { $0.id == manualEntryID }, "Manual entries should be queryable by day")
    expect(
        timeEntries.entries(
            overlapping: entryStart.addingTimeInterval(10 * 60),
            end: entryEnd.addingTimeInterval(-10 * 60)
        ).contains { $0.id == manualEntryID },
        "Time entries should detect overlapping ranges"
    )

    let splitTimeEntries = TimeEntryStore(rootDirectory: tempRoot.appendingPathComponent("SplitTimeEntries", isDirectory: true))
    let splitStart = date.addingTimeInterval(9 * 60 * 60)
    let splitEnd = date.addingTimeInterval(12 * 60 * 60)
    guard let splitOriginalID = splitTimeEntries.addEntry(
        title: "Long existing entry",
        projectID: researchProjectID,
        start: splitStart,
        end: splitEnd
    ), let splitOriginal = splitTimeEntries.entries.first(where: { $0.id == splitOriginalID }) else {
        expect(false, "Split test should create an existing time entry")
        return
    }
    let splitFragments = splitTimeEntries.splitOverlappingEntries(
        [splitOriginal],
        excluding: [(start: date.addingTimeInterval(10 * 60 * 60), end: date.addingTimeInterval(11 * 60 * 60))]
    )
    expect(
        splitFragments.count == 2
            && splitFragments.contains { $0.start == splitStart && $0.end == date.addingTimeInterval(10 * 60 * 60) }
            && splitFragments.contains { $0.start == date.addingTimeInterval(11 * 60 * 60) && $0.end == splitEnd },
        "Replacing a range should preserve both outside fragments"
    )
    guard let splitReplacementID = splitTimeEntries.addEntry(
        title: "Replacement entry",
        projectID: researchProjectID,
        start: date.addingTimeInterval(10 * 60 * 60),
        end: date.addingTimeInterval(11 * 60 * 60)
    ), let splitReplacement = splitTimeEntries.entries.first(where: { $0.id == splitReplacementID }) else {
        expect(false, "Split test should create the replacement entry")
        return
    }
    splitTimeEntries.recordEntryOMaticCreation(
        created: [splitReplacement],
        replaced: [splitOriginal],
        splitFragments: splitFragments
    )
    expect(splitTimeEntries.undoEntryOMaticCreation(), "Undo should restore split entries")
    expect(
        splitTimeEntries.entries.count == 1
            && splitTimeEntries.entries.first?.id == splitOriginal.id
            && splitTimeEntries.entries.first?.start == splitOriginal.start
            && splitTimeEntries.entries.first?.end == splitOriginal.end,
        "Undo should remove generated entries and fragments and restore the original entry"
    )

    expect(
        timeEntries.entries.first(where: { $0.id == manualEntryID })?.billingStatus == .pending,
        "Manual entries should preserve billing status"
    )
    if var updatedEntry = timeEntries.entries.first(where: { $0.id == manualEntryID }) {
        updatedEntry.title = "Updated research call"
        updatedEntry.billingStatus = .billable
        timeEntries.update(updatedEntry)
    }
    expect(
        timeEntries.entries.first(where: { $0.id == manualEntryID })?.title == "Updated research call",
        "Time entries should support in-place edits"
    )
    expect(BillingStatus.paid.label == "Paid", "Billing status should include paid entries")
    expect(ReportBillingFilter.paid.matches(.paid), "Reports should filter paid billing status")
    expect(BillingStatus(rawValue: "undetermined")?.label == "Undetermined", "Billing status should preserve undetermined legacy entries")
    expect(ReportBillingFilter.undetermined.matches(.undetermined), "Reports should filter undetermined billing status")

    let timerStart = entryEnd.addingTimeInterval(15 * 60)
    timeEntries.startTimer(
        title: "Focused writing",
        projectID: researchProjectID,
        startedAt: timerStart,
        estimatedDurationSeconds: 30 * 60,
        billingStatus: .notBillable
    )
    expect(timeEntries.runningTimer != nil, "Timer should become active")
    expect(timeEntries.runningTimer?.estimatedDurationSeconds == 30 * 60, "Timers should persist an estimated duration")
    timeEntries.adjustRunningTimerEstimate(by: 15 * 60)
    expect(timeEntries.runningTimer?.estimatedDurationSeconds == 45 * 60, "Running timers should support estimate check-ins")
    timeEntries.setRunningTimerEstimate(to: 60 * 60)
    expect(timeEntries.runningTimer?.estimatedDurationSeconds == 60 * 60, "Running timers should support absolute estimate changes")
    timeEntries.adjustRunningTimerStart(by: -5 * 60)
    expect(
        timeEntries.runningTimer?.startedAt == timerStart.addingTimeInterval(-5 * 60),
        "Running timers should support small start-time corrections"
    )
    expect(timeEntries.moveRunningTimerStartToPreviousEntryBoundary(), "Running timers should align to the previous time-entry boundary")
    expect(timeEntries.runningTimer?.startedAt == entryEnd, "Previous-entry alignment should use the previous entry end")
    timeEntries.moveRunningTimerStart(to: timerStart.addingTimeInterval(-5 * 60))
    expect(
        timeEntries.materializedEntries(at: timerStart.addingTimeInterval(5 * 60)).contains { $0.title == "Focused writing" && !$0.isManual },
        "Live timers should participate in materialized report entries"
    )

    let expiredTimerStore = TimeEntryStore(rootDirectory: tempRoot.appendingPathComponent("ExpiredTimer", isDirectory: true))
    expiredTimerStore.startTimer(
        title: "Expired estimate",
        projectID: researchProjectID,
        startedAt: Date().addingTimeInterval(-2 * 60),
        estimatedDurationSeconds: 60
    )
    expect(
        (expiredTimerStore.runningTimerRemainingSeconds ?? 0) < 0,
        "Running timers should expose an expired estimate for check-in prompts"
    )
    expiredTimerStore.setRunningTimerEstimate(to: expiredTimerStore.runningDurationSeconds + 15 * 60)
    expect(
        (expiredTimerStore.runningTimerRemainingSeconds ?? -1) >= 0,
        "Extending a timer during check-in should restore positive remaining time"
    )
    _ = expiredTimerStore.stopTimer()
    let timerID = timeEntries.stopTimer(at: timerStart.addingTimeInterval(20 * 60))
    expect(timerID != nil, "Stopping a timer should create a time entry")
    expect(timeEntries.runningTimer == nil, "Stopping a timer should clear the active timer")
    expect(
        timeEntries.entries.first(where: { $0.id == timerID })?.billingStatus == .notBillable,
        "Timer entries should preserve their billing status"
    )
    expect(
        timeEntries.recentTimerEntries().first?.title == "Focused writing",
        "Recent timer suggestions should prefer the latest non-manual timer"
    )
    expect(timeEntries.entries(for: date).count == 2, "Manual and timer entries should share the daily time-entry store")

    let reloadedTimeEntries = TimeEntryStore(rootDirectory: timeEntryRoot)
    expect(reloadedTimeEntries.entries.count == 2, "Time entries should round-trip through local JSON")
    let timeEntryArchive = try! timeEntries.exportArchiveData()
    let importedTimeEntries = TimeEntryStore(rootDirectory: tempRoot.appendingPathComponent("ImportedTimeEntries", isDirectory: true))
    expect(try! importedTimeEntries.importArchiveData(timeEntryArchive) == 2, "Time-entry archives should import completed entries")
    let reportCSV = ReportExporter.csv(
        activityDays: [(date: date, segments: [projectActivity])],
        timeEntries: timeEntries.entries,
        projectStore: projectStore
    )
    expect(reportCSV.contains("Date,Type,Project"), "CSV reports should include a stable header")
    expect(reportCSV.contains("Visual Studio Code"), "CSV reports should include app usage")
    expect(reportCSV.contains("Updated research call"), "CSV reports should include manual time entries")
    expect(reportCSV.contains("Amount"), "CSV reports should include billing amount columns")
    expect(reportCSV.contains("USD 90.00"), "Reports should calculate billable amount from project rates")
    var appOnlyOptions = ReportOptions()
    appOnlyOptions.include = .appUsage
    let appOnlyCSV = ReportExporter.csv(
        activityDays: [(date: date, segments: [projectActivity])],
        timeEntries: timeEntries.entries,
        projectStore: projectStore,
        options: appOnlyOptions
    )
    expect(appOnlyCSV.contains("Visual Studio Code"), "App-only reports should include app usage")
    expect(!appOnlyCSV.contains("Updated research call"), "App-only reports should exclude time entries")
    var selectedColumnsOptions = ReportOptions()
    selectedColumnsOptions.includeNotes = false
    selectedColumnsOptions.includeBillingAmount = false
    let selectedColumnsCSV = ReportExporter.csv(
        activityDays: [(date: date, segments: [projectActivity])],
        timeEntries: timeEntries.entries,
        projectStore: projectStore,
        options: selectedColumnsOptions
    )
    expect(!selectedColumnsCSV.split(separator: "\n", maxSplits: 1).first!.contains("Notes"), "Reports should support selectable columns")
    expect(!selectedColumnsCSV.split(separator: "\n", maxSplits: 1).first!.contains("Amount"), "Reports should omit disabled billing columns")

    var projectFilterOptions = ReportOptions()
    projectFilterOptions.projectIDs = [childProjectID]
    let childOnlyCSV = ReportExporter.csv(
        activityDays: [(date: date, segments: [projectActivity])],
        timeEntries: timeEntries.entries,
        projectStore: projectStore,
        options: projectFilterOptions
    )
    expect(!childOnlyCSV.contains("Visual Studio Code"), "Reports should filter activities by selected projects")

    var groupedOptions = ReportOptions()
    groupedOptions.groupBy = .project
    groupedOptions.rounding = .up
    groupedOptions.durationFormat = .hms
    let groupedCSV = ReportExporter.csv(
        activityDays: [(date: date, segments: [projectActivity])],
        timeEntries: timeEntries.entries,
        projectStore: projectStore,
        options: groupedOptions
    )
    expect(groupedCSV.contains("Grouped"), "Grouped reports should aggregate records")
    expect(groupedCSV.contains("01:15:00"), "Report rounding and duration formats should be applied")
    expect((try? ReportExporter.json(
        activityDays: [(date: date, segments: [projectActivity])],
        timeEntries: timeEntries.entries,
        projectStore: projectStore
    )) != nil, "JSON reports should be serializable")
    expect(ReportExporter.html(
        activityDays: [(date: date, segments: [projectActivity])],
        timeEntries: timeEntries.entries,
        projectStore: projectStore
    ).contains("<table>"), "HTML reports should include a table")
    let pdfURL = tempRoot.appendingPathComponent("smoke-report.pdf")
    try! ReportExporter.write(
        to: pdfURL,
        format: .pdf,
        activityDays: [(date: date, segments: [projectActivity])],
        timeEntries: timeEntries.entries,
        projectStore: projectStore
    )
    expect(FileManager.default.fileExists(atPath: pdfURL.path), "PDF reports should be written")
    let xlsxURL = tempRoot.appendingPathComponent("smoke-report.xlsx")
    try! ReportExporter.write(
        to: xlsxURL,
        format: .xlsx,
        activityDays: [(date: date, segments: [projectActivity])],
        timeEntries: timeEntries.entries,
        projectStore: projectStore
    )
    let xlsxData = try! Data(contentsOf: xlsxURL)
    expect(xlsxData.prefix(2) == Data([0x50, 0x4B]), "XLSX reports should be ZIP workbooks")
    let unzipResult = Process()
    unzipResult.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    unzipResult.arguments = ["-t", xlsxURL.path]
    unzipResult.standardOutput = Pipe()
    unzipResult.standardError = Pipe()
    try! unzipResult.run()
    unzipResult.waitUntilExit()
    expect(unzipResult.terminationStatus == 0, "XLSX reports should pass ZIP integrity checks")
    expect(
        xlsxData.range(of: Data("Visual Studio Code".utf8)) != nil,
        "XLSX reports should contain the exported worksheet values"
    )

    // Timing Sync's shared-folder protocol keeps each device's archive
    // separate and remaps foreign project IDs before merging entries and
    // activities into the receiving Mac.
    let sharedSyncRoot = tempRoot.appendingPathComponent("SharedSync", isDirectory: true)
    let deviceARoot = tempRoot.appendingPathComponent("DeviceA", isDirectory: true)
    let deviceBRoot = tempRoot.appendingPathComponent("DeviceB", isDirectory: true)
    let deviceATeams = TeamStore(rootDirectory: deviceARoot.appendingPathComponent("Teams", isDirectory: true))
    let deviceAFilters = ActivityFilterStore(rootDirectory: deviceARoot.appendingPathComponent("Filters", isDirectory: true))
    let deviceACategories = ActivityCategoryStore(rootDirectory: deviceARoot.appendingPathComponent("Categories", isDirectory: true))
    _ = deviceACategories.createCategory(
        name: "Shared Focused Work",
        role: .focused,
        color: .orange,
        matchMode: .any,
        rules: [ActivityFilterRule(field: .application, pattern: "Device A Editor")]
    )
    deviceAFilters.save(ActivityFilterDefinition(
        name: "Shared Browser Work",
        color: .green,
        rules: [ActivityFilterRule(field: .application, pattern: "Safari")]
    ))
    guard let deviceATeamID = deviceATeams.createTeam(name: "Shared Team") else {
        expect(false, "Sync device A should create a team")
        return
    }
    _ = deviceATeams.addMember(to: deviceATeamID, name: "Device B", email: "b@example.com")
    let deviceAProjects = ProjectStore(rootDirectory: deviceARoot.appendingPathComponent("Projects", isDirectory: true))
    let deviceATimeEntries = TimeEntryStore(rootDirectory: deviceARoot.appendingPathComponent("TimeEntries", isDirectory: true))
    let deviceAPreferences = PreferencesStore(rootDirectory: deviceARoot.appendingPathComponent("Preferences", isDirectory: true))
    let deviceAExclusions = ExclusionStore(rootDirectory: deviceARoot.appendingPathComponent("Exclusions", isDirectory: true))
    let deviceAActivity = AppActivityMonitor(
        rootDirectory: deviceARoot.appendingPathComponent("Activity", isDirectory: true),
        projectStore: deviceAProjects,
        preferences: deviceAPreferences,
        exclusionStore: deviceAExclusions
    )
    let deviceAScreenTime = ScreenTimeStore(
        databaseURL: deviceARoot.appendingPathComponent("missing-knowledgeC.db"),
        archiveRootDirectory: deviceARoot.appendingPathComponent("ScreenTime", isDirectory: true)
    )
    try! ActivityHistoryStore(
        rootDirectory: deviceARoot.appendingPathComponent("ScreenTime", isDirectory: true)
    ).save([
        ActivitySegment(
            appName: "Mobile Safari",
            bundleIdentifier: "com.apple.mobilesafari",
            deviceName: "Screen Time",
            windowTitle: "research.example",
            resource: "https://research.example",
            startMinute: 50,
            endMinute: 65,
            relevance: .related
        )
    ], date: date)
    deviceAScreenTime.load(for: date)
    guard let deviceAProjectID = deviceAProjects.createProject(name: "Shared Sync Project", teamID: deviceATeamID) else {
        expect(false, "Sync device A should create a project")
        return
    }
    _ = deviceATimeEntries.addEntry(
        title: "Device A entry",
        projectID: deviceAProjectID,
        start: date.addingTimeInterval(10 * 60),
        end: date.addingTimeInterval(40 * 60)
    )
    _ = deviceAExclusions.addRule(
        field: .application,
        pattern: "Private Browser",
        comparison: .equals
    )
    try! ActivityHistoryStore(rootDirectory: deviceARoot.appendingPathComponent("Activity", isDirectory: true))
        .save([
            ActivitySegment(
                appName: "Device A Editor",
                bundleIdentifier: "com.example.device-a",
                deviceName: "Mac A",
                startMinute: 10,
                endMinute: 40,
                relevance: .related,
                projectID: deviceAProjectID
            )
        ], date: date)
    let deviceASync = SyncStore(
        projectStore: deviceAProjects,
        filterStore: deviceAFilters,
        categoryStore: deviceACategories,
        timeEntryStore: deviceATimeEntries,
        activityMonitor: deviceAActivity,
        markdownStore: MarkdownStore(date: date, rootDirectory: deviceARoot),
        screenTimeStore: deviceAScreenTime,
        exclusionStore: deviceAExclusions,
        teamStore: deviceATeams,
        rootDirectory: deviceARoot.appendingPathComponent("Sync", isDirectory: true)
    )
    deviceASync.deviceName = "Mac A"
    deviceASync.configure(folderURL: sharedSyncRoot)
    expect(deviceASync.syncNow(), "Sync device A should publish an archive")
    let backupDirectory = sharedSyncRoot.appendingPathComponent("backups", isDirectory: true)
    expect(
        (try? FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil))?
            .contains(where: { $0.pathExtension == "json" }) == true,
        "Sync should retain a rolling cloud backup snapshot"
    )

    let deviceBTeams = TeamStore(rootDirectory: deviceBRoot.appendingPathComponent("Teams", isDirectory: true))
    let deviceBFilters = ActivityFilterStore(rootDirectory: deviceBRoot.appendingPathComponent("Filters", isDirectory: true))
    let deviceBCategories = ActivityCategoryStore(rootDirectory: deviceBRoot.appendingPathComponent("Categories", isDirectory: true))
    let deviceBProjects = ProjectStore(rootDirectory: deviceBRoot.appendingPathComponent("Projects", isDirectory: true))
    let deviceBTimeEntries = TimeEntryStore(rootDirectory: deviceBRoot.appendingPathComponent("TimeEntries", isDirectory: true))
    let deviceBPreferences = PreferencesStore(rootDirectory: deviceBRoot.appendingPathComponent("Preferences", isDirectory: true))
    let deviceBExclusions = ExclusionStore(rootDirectory: deviceBRoot.appendingPathComponent("Exclusions", isDirectory: true))
    let deviceBActivity = AppActivityMonitor(
        rootDirectory: deviceBRoot.appendingPathComponent("Activity", isDirectory: true),
        projectStore: deviceBProjects,
        preferences: deviceBPreferences,
        exclusionStore: deviceBExclusions
    )
    let deviceBScreenTime = ScreenTimeStore(
        databaseURL: deviceBRoot.appendingPathComponent("missing-knowledgeC.db"),
        archiveRootDirectory: deviceBRoot.appendingPathComponent("ScreenTime", isDirectory: true)
    )
    let deviceBSync = SyncStore(
        projectStore: deviceBProjects,
        filterStore: deviceBFilters,
        categoryStore: deviceBCategories,
        timeEntryStore: deviceBTimeEntries,
        activityMonitor: deviceBActivity,
        markdownStore: MarkdownStore(date: date, rootDirectory: deviceBRoot),
        screenTimeStore: deviceBScreenTime,
        exclusionStore: deviceBExclusions,
        teamStore: deviceBTeams,
        rootDirectory: deviceBRoot.appendingPathComponent("Sync", isDirectory: true)
    )
    deviceBSync.deviceName = "Mac B"
    deviceBSync.configure(folderURL: sharedSyncRoot)
    expect(deviceBSync.syncNow(), "Sync device B should merge device A")
    expect(deviceBProjects.projects.contains { $0.name == "Shared Sync Project" }, "Sync should merge project hierarchies")
    expect(deviceBProjects.projects.first(where: { $0.name == "Shared Sync Project" })?.teamID == deviceBTeams.activeTeams.first(where: { $0.name == "Shared Team" })?.id, "Sync should remap project team assignments")
    expect(deviceBTimeEntries.entries.contains { $0.title == "Device A entry" }, "Sync should merge time entries")
    expect(deviceBActivity.segments(for: date).contains { $0.deviceName == "Mac A" }, "Sync should preserve source device names on activities")
    expect(deviceBFilters.filters.contains { $0.name == "Shared Browser Work" }, "Sync should merge saved activity filters")
    expect(deviceBCategories.categories.contains { $0.name == "Shared Focused Work" && $0.color == .blue }, "Sync should merge activity categories and preserve focused color semantics")
    expect(deviceBExclusions.rules.contains { $0.pattern == "Private Browser" }, "Sync should merge activity exclusion rules")
    expect(deviceBScreenTime.segments(for: date).contains { $0.resource == "https://research.example" }, "Sync should merge archived Screen Time activity")
    expect(deviceBSync.backupCount > 0, "Sync should expose retained backup count")
    expect(deviceBSync.restoreLatestBackup(), "Sync should restore the latest backup archive")

    guard let deviceBProjectID = deviceBProjects.createProject(name: "Device B Project") else {
        expect(false, "Sync device B should create a project")
        return
    }
    _ = deviceBTimeEntries.addEntry(
        title: "Device B entry",
        projectID: deviceBProjectID,
        start: date.addingTimeInterval(60 * 60),
        end: date.addingTimeInterval(90 * 60)
    )
    expect(deviceBSync.syncNow(), "Sync device B should publish its new entry")
    expect(deviceASync.syncNow(), "Sync device A should merge device B")
    expect(deviceAProjects.projects.contains { $0.name == "Device B Project" }, "Sync should merge projects in both directions")
    expect(deviceATimeEntries.entries.contains { $0.title == "Device B entry" }, "Sync should merge entries in both directions")
    deviceASync.stop()
    deviceBSync.stop()

    let store = MarkdownStore(date: date, rootDirectory: tempRoot)
    guard let draftID = store.tasks.first(where: { $0.title == "Draft response" })?.id else {
        expect(false, "Seed should include Draft response")
        return
    }

    store.schedule(id: draftID, start: 11 * 60, end: 12 * 60)
    expect(store.task(draftID)?.timeRange == "11:00 - 12:00", "Scheduling should update the Markdown model")
    expect(store.markdown.contains("11:00 - 12:00 Draft response"), "Scheduling should rewrite Markdown text")

    store.move(id: draftID, start: 13 * 60 + 30)
    expect(store.task(draftID)?.timeRange == "13:30 - 14:30", "Moving should preserve duration and rewrite time")

    store.resize(id: draftID, end: 15 * 60)
    expect(store.task(draftID)?.timeRange == "13:30 - 15:00", "Resizing should rewrite the end time")

    store.resizeStart(id: draftID, start: 14 * 60)
    expect(store.task(draftID)?.timeRange == "14:00 - 15:00", "Resizing should rewrite the start time")

    store.unschedule(id: draftID)
    expect(store.task(draftID) != nil, "Removing time should preserve the task")
    expect(store.task(draftID)?.timeRange == nil, "Removing time should clear only the range")

    let newTaskID = UUID()
    expect(store.addTask(title: "Fresh draggable task", id: newTaskID) == newTaskID, "New editor task should be committed with its drag identity")
    store.schedule(id: newTaskID, start: 10 * 60, end: 11 * 60)
    expect(store.task(newTaskID)?.timeRange == "10:00 - 11:00", "A newly committed task should be immediately schedulable")
    expect(store.markdown.contains("10:00 - 11:00 Fresh draggable task"), "New task drag should persist its Time Block in Markdown")

    let rawBeforeFreeEdit = store.markdown
    let freelyEdited = "Custom first line\n1. Editable ordered item\n" + rawBeforeFreeEdit
    store.updateRawMarkdown(freelyEdited)
    expect(store.markdown == freelyEdited, "The native editor must preserve arbitrary Markdown exactly")
    expect(store.task(newTaskID)?.title == "Fresh draggable task", "Task identity should survive inserting ordinary lines above it")
    store.move(id: newTaskID, start: 12 * 60)
    expect(store.markdown.hasPrefix("Custom first line\n1. Editable ordered item\n"), "Calendar edits must not rewrite unrelated Markdown lines")
    expect(store.markdown.contains("12:00 - 13:00 Fresh draggable task"), "Calendar edits should replace only the matching task line")

    store.updateRawMarkdown("# An entirely free-form note\n\nParagraph text\n")
    expect(store.markdown == "# An entirely free-form note\n\nParagraph text\n", "A document without task lines must remain valid Markdown")
    expect(store.tasks.isEmpty, "Calendar should simply be empty when the Markdown has no tasks")

    let originalMarkdown = store.markdown
    let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: date)!
    expect(store.load(date: nextDate), "Selecting a missing date should create its daily Markdown")
    expect(store.fileURL.lastPathComponent != "", "The selected date should have a concrete Markdown file")
    expect(store.markdown.contains("## Focus"), "A new day should start with an editable Markdown template")
    expect(store.tasks.isEmpty, "A newly created day must not copy tasks from another date")

    _ = store.addTask(title: "Task on next day")
    expect(store.markdown.contains("Task on next day"), "The newly created daily Markdown should be editable")
    expect(!store.load(date: date), "Returning to an existing date should open instead of recreate it")
    expect(store.markdown == originalMarkdown, "Switching dates must preserve each day's Markdown independently")

    try? FileManager.default.removeItem(at: tempRoot)
    print("Metriday smoke tests passed")
    exit(0)
}

RunLoop.main.run()

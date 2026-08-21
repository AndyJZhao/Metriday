import ApplicationServices
import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class AppActivityMonitor: ObservableObject {
    private static let trackingPauseUntilKey = "Metriday.trackingPauseUntil"
    private static let trackingManuallyPausedKey = "Metriday.trackingManuallyPaused"

    @Published private(set) var currentApplication = "Waiting for activity"
    @Published private(set) var currentBundleIdentifier = ""
    @Published private(set) var currentWindowTitle = ""
    @Published private(set) var observedSegments: [ActivitySegment] = []
    @Published private(set) var isTracking = false
    @Published private(set) var isIdle = false
    @Published private(set) var trackingPausedUntil: Date?
    @Published private(set) var isManuallyPaused = false
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var lastSampleAt: Date?
    @Published private(set) var pendingIdleInterval: IdleInterval?
    @Published private(set) var pendingCallInterval: CallInterval?
    private(set) var deviceName: String

    private let history: ActivityHistoryStore
    let projectStore: ProjectStore
    let preferences: PreferencesStore
    let exclusionStore: ExclusionStore
    private let calendar = Calendar.current
    // Timing samples the frontmost app roughly once per second. Keeping the
    // native loop at that cadence preserves short-lived app and website usage
    // in the local activity history and timeline.
    private let sampleInterval: TimeInterval = 1

    private var timer: Timer?
    private var resumeTimer: Timer?
    private var trackedDate: Date
    private var visibleDate: Date
    private var activeWrapAtMinute: Int
    private var dailySegments: [ActivitySegment] = []
    private var currentObservation: ActivityObservation?
    private var currentStart: Date?
    private var currentSegmentID = UUID()
    private var shouldResumeAfterWake = false
    private var workspaceCancellables = Set<AnyCancellable>()

    init(
        rootDirectory: URL? = nil,
        projectStore: ProjectStore? = nil,
        preferences: PreferencesStore? = nil,
        exclusionStore: ExclusionStore? = nil,
        deviceName: String? = nil
    ) {
        self.history = ActivityHistoryStore(rootDirectory: rootDirectory)
        self.projectStore = projectStore ?? ProjectStore()
        self.preferences = preferences ?? PreferencesStore()
        self.exclusionStore = exclusionStore ?? ExclusionStore()
        self.activeWrapAtMinute = TrackingDay.clampedWrapMinute(self.preferences.wrapDaysAtMinute)
        let configuredDeviceName = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.deviceName = configuredDeviceName?.isEmpty == false
            ? configuredDeviceName!
            : (Host.current().localizedName ?? "This Mac")
        let today = TrackingDay.logicalDayLabel(
            for: .now,
            wrapAtMinute: self.activeWrapAtMinute,
            calendar: calendar
        )
        self.trackedDate = today
        self.visibleDate = today
        self.dailySegments = history.load(date: today, wrapAtMinute: self.activeWrapAtMinute)
        self.accessibilityTrusted = AXIsProcessTrusted()
        self.observedSegments = dailySegments
        self.pendingIdleInterval = nil
        self.pendingCallInterval = nil
        let storedPauseUntil = UserDefaults.standard.object(forKey: Self.trackingPauseUntilKey) as? Date
        self.trackingPausedUntil = storedPauseUntil.flatMap { $0 > .now ? $0 : nil }
        self.isManuallyPaused = UserDefaults.standard.bool(forKey: Self.trackingManuallyPausedKey)
        if storedPauseUntil != nil, self.trackingPausedUntil == nil {
            UserDefaults.standard.removeObject(forKey: Self.trackingPauseUntilKey)
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.pauseForSleep()
                }
            }
            .store(in: &workspaceCancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.resumeAfterWake()
                }
            }
            .store(in: &workspaceCancellables)
        self.preferences.$wrapDaysAtMinute
            .dropFirst()
            .sink { [weak self] newValue in
                Task { @MainActor in
                    self?.applyWrapDayPreference(TrackingDay.clampedWrapMinute(newValue))
                }
            }
            .store(in: &workspaceCancellables)
    }

    func setDeviceName(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "This Mac" : trimmed
        guard resolved != deviceName else { return }
        deviceName = resolved
        if isTracking {
            sample()
        } else {
            refreshObservedSegments()
        }
    }

    var visibleSummary: ActivitySummary {
        ActivitySummary(segments: observedSegments)
    }

    var currentDurationMinutes: Int {
        guard let currentStart else { return 0 }
        return max(1, Int(Date().timeIntervalSince(currentStart) / 60.0))
    }

    func summary(for date: Date) -> ActivitySummary {
        ActivitySummary(segments: segments(for: date))
    }

    func segments(for date: Date) -> [ActivitySegment] {
        let normalized = calendar.startOfDay(for: date)
        if normalized == trackedDate {
            let liveSegments = currentSegment(at: .now).map { [$0] } ?? []
            return dailySegments + liveSegments
        }
        return loadHistory(normalized)
    }

    func exportHistoryArchiveData() throws -> Data {
        try history.exportArchiveData()
    }

    @discardableResult
    func importHistoryArchiveData(_ data: Data) throws -> Int {
        let imported = try history.importArchiveData(data)
        dailySegments = loadHistory(trackedDate)
        refreshObservedSegments()
        return imported
    }

    func start() {
        guard !isTracking else { return }
        if isManuallyPaused {
            currentApplication = "Tracking paused"
            return
        }
        if let trackingPausedUntil {
            guard trackingPausedUntil > .now else {
                clearTrackingPause()
                return start()
            }
            scheduleTrackingResume(at: trackingPausedUntil)
            currentApplication = "Tracking paused"
            return
        }
        isTracking = true
        refreshAccessibilityStatus()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func stop() {
        guard isTracking else {
            shouldResumeAfterWake = false
            return
        }
        shouldResumeAfterWake = false
        finishCurrentSegment(at: .now)
        persistDailySegments()
        timer?.invalidate()
        timer = nil
        isTracking = false
        currentObservation = nil
        currentStart = nil
        currentApplication = "Tracking paused"
        currentBundleIdentifier = ""
        currentWindowTitle = ""
        isIdle = false
        refreshObservedSegments()
    }

    /// Pauses automatic app tracking until the user explicitly resumes it.
    /// This state survives relaunches so a deliberate pause is not undone by
    /// the start-on-launch preference.
    func pauseTracking() {
        clearTrackingPause()
        isManuallyPaused = true
        UserDefaults.standard.set(true, forKey: Self.trackingManuallyPausedKey)
        if isTracking { stop() }
        currentApplication = "Tracking paused"
    }

    /// Pauses automatic app tracking for a bounded interval. The deadline is
    /// persisted and resumed automatically even if Metriday is relaunched.
    func pauseTracking(until date: Date) {
        guard date > .now else {
            resumeTracking()
            return
        }
        isManuallyPaused = false
        UserDefaults.standard.set(false, forKey: Self.trackingManuallyPausedKey)
        trackingPausedUntil = date
        UserDefaults.standard.set(date, forKey: Self.trackingPauseUntilKey)
        if isTracking { stop() }
        scheduleTrackingResume(at: date)
        currentApplication = "Tracking paused"
    }

    /// Clears a manual or timed pause and resumes app tracking immediately.
    func resumeTracking() {
        clearTrackingPause()
        isManuallyPaused = false
        UserDefaults.standard.set(false, forKey: Self.trackingManuallyPausedKey)
        start()
    }

    private func clearTrackingPause() {
        resumeTimer?.invalidate()
        resumeTimer = nil
        trackingPausedUntil = nil
        UserDefaults.standard.removeObject(forKey: Self.trackingPauseUntilKey)
    }

    private func scheduleTrackingResume(at date: Date) {
        resumeTimer?.invalidate()
        let delay = max(0.1, date.timeIntervalSinceNow)
        resumeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.resumeTracking()
            }
        }
    }

    private func pauseForSleep() {
        shouldResumeAfterWake = isTracking
        guard isTracking else { return }
        finishCurrentSegment(at: .now)
        persistDailySegments()
        timer?.invalidate()
        timer = nil
        isTracking = false
        currentObservation = nil
        currentStart = nil
        currentApplication = "Paused while Mac sleeps"
        currentBundleIdentifier = ""
        currentWindowTitle = ""
        isIdle = false
        refreshObservedSegments()
    }

    private func resumeAfterWake() {
        guard shouldResumeAfterWake else { return }
        shouldResumeAfterWake = false
        start()
    }

    func toggleTracking() {
        if isTracking {
            pauseTracking()
        } else {
            resumeTracking()
        }
    }

    func selectDate(_ date: Date) {
        visibleDate = calendar.startOfDay(for: date)
        refreshObservedSegments()
    }

    func assignActivity(_ id: UUID, to projectID: UUID?, date: Date? = nil) {
        let targetDate = calendar.startOfDay(for: date ?? visibleDate)
        if targetDate == trackedDate, let index = dailySegments.firstIndex(where: { $0.id == id }) {
            dailySegments[index].projectID = projectID
            persistDailySegments()
            refreshObservedSegments()
            return
        }

        if targetDate == trackedDate, currentSegmentID == id {
            currentObservation?.projectID = projectID
            persistSnapshot(at: .now)
            refreshObservedSegments()
            return
        }

        var historicalSegments = loadHistory(targetDate)
        guard let index = historicalSegments.firstIndex(where: { $0.id == id }) else { return }
        historicalSegments[index].projectID = projectID
        try? saveHistory(historicalSegments, date: targetDate)
        if targetDate == visibleDate { refreshObservedSegments() }
    }

    @discardableResult
    func deleteActivities(_ ids: Set<UUID>, date: Date? = nil) -> [ActivitySegment] {
        guard !ids.isEmpty else { return [] }
        let targetDate = calendar.startOfDay(for: date ?? visibleDate)

        if targetDate == trackedDate {
            var deleted = dailySegments.filter { ids.contains($0.id) }
            if ids.contains(currentSegmentID),
               let liveSegment = currentSegment(at: .now) {
                deleted.append(liveSegment)
                currentStart = .now
                currentSegmentID = UUID()
            }
            guard !deleted.isEmpty else { return [] }
            let deletedIDs = Set(deleted.map(\.id))
            history.markDeleted(deletedIDs, date: targetDate)
            dailySegments.removeAll { deletedIDs.contains($0.id) }
            persistDailySegments()
            refreshObservedSegments()
            return deleted
        }

        let historicalSegments = loadHistory(targetDate)
        let deleted = historicalSegments.filter { ids.contains($0.id) }
        guard !deleted.isEmpty else { return [] }
        let deletedIDs = Set(deleted.map(\.id))
        history.markDeleted(deletedIDs, date: targetDate)
        try? saveHistory(historicalSegments.filter { !deletedIDs.contains($0.id) }, date: targetDate)
        if targetDate == visibleDate { refreshObservedSegments() }
        return deleted
    }

    func restoreActivities(_ segments: [ActivitySegment], date: Date? = nil) {
        guard !segments.isEmpty else { return }
        let targetDate = calendar.startOfDay(for: date ?? visibleDate)
        let ids = Set(segments.map(\.id))
        history.restore(ids, date: targetDate)

        var restored: [UUID: ActivitySegment]
        if targetDate == trackedDate {
            restored = Dictionary(uniqueKeysWithValues: dailySegments.map { ($0.id, $0) })
        } else {
            restored = Dictionary(uniqueKeysWithValues: loadHistory(targetDate).map { ($0.id, $0) })
        }
        for segment in segments { restored[segment.id] = segment }
        try? saveHistory(Array(restored.values), date: targetDate)
        if targetDate == trackedDate {
            dailySegments = loadHistory(targetDate)
        }
        if targetDate == visibleDate { refreshObservedSegments() }
    }

    @discardableResult
    func createRule(for activity: ActivitySegment, projectID: UUID) -> UUID? {
        let field: ProjectRuleField
        let pattern: String
        if let host = URL(string: activity.resource)?.host, !host.isEmpty {
            field = .domain
            pattern = host
        } else if !activity.bundleIdentifier.isEmpty {
            field = .bundleIdentifier
            pattern = activity.bundleIdentifier
        } else {
            field = .titleContains
            pattern = activity.windowTitle
        }

        guard let ruleID = projectStore.addRule(
            projectID: projectID,
            field: field,
            pattern: pattern
        ) else { return nil }
        // Creating a rule from an existing activity should keep the current
        // activity assignment intact. Historical activity changes only when
        // the user explicitly chooses a Reapply action in Rules.
        assignActivity(activity.id, to: projectID)
        return ruleID
    }

    func reapplyRules(for date: Date) {
        let normalized = calendar.startOfDay(for: date)
        if normalized == trackedDate {
            var changed = applyRules(to: &dailySegments, date: normalized)
            if let liveSegment = currentSegment(at: .now),
               let matchedProjectID = projectStore.matchingProjectID(for: liveSegment, date: .now),
               currentObservation?.projectID != matchedProjectID {
                currentObservation?.projectID = matchedProjectID
                changed = true
            }
            guard changed else { return }
            persistDailySegments()
            persistSnapshot(at: .now)
            refreshObservedSegments()
            return
        }

        var segments = loadHistory(normalized)
        var changed = false
        changed = applyRules(to: &segments, date: normalized)
        guard changed else { return }
        try? saveHistory(segments, date: normalized)
        if normalized == visibleDate {
            observedSegments = segments
        }
    }

    @discardableResult
    private func applyRules(to segments: inout [ActivitySegment], date: Date) -> Bool {
        var changed = false
        for index in segments.indices {
            // Do not erase manual assignments for activities which do not
            // match a rule. This preserves the bucket semantics of Timing's
            // explicit reapply flow.
            guard let matchedProjectID = projectStore.matchingProjectID(for: segments[index], date: date) else {
                continue
            }
            guard segments[index].projectID != matchedProjectID else { continue }
            segments[index].projectID = matchedProjectID
            changed = true
        }
        return changed
    }

    func reapplyRulesForAllStoredDays() {
        var dates = Set(history.logicalStoredDates(wrapAtMinute: activeWrapAtMinute))
        // The current day can contain a live in-memory segment before the
        // next persistence tick, so it must participate even without a file.
        dates.insert(trackedDate)
        for date in dates.sorted() {
            reapplyRules(for: date)
        }
        refreshObservedSegments()
    }

    func refreshAccessibilityStatus() {
        accessibilityTrusted = AXIsProcessTrusted()
    }

    func requestAccessibilityAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshAccessibilityStatus()
    }

    func dismissPendingIdleInterval() {
        pendingIdleInterval = nil
    }

    func dismissPendingCallInterval() {
        pendingCallInterval = nil
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func sample() {
        guard isTracking else { return }
        let now = Date()
        lastSampleAt = now
        refreshAccessibilityStatus()
        rotateDayIfNeeded(at: now)

        guard let observation = currentObservationSnapshot(at: now) else {
            capturePendingIdleInterval(at: now)
            finishCurrentSegment(at: now)
            currentObservation = nil
            currentStart = nil
            currentApplication = "Tracking filtered"
            currentBundleIdentifier = ""
            currentWindowTitle = ""
            isIdle = false
            refreshObservedSegments()
            return
        }
        if observation != currentObservation {
            capturePendingIdleInterval(at: now)
            finishCurrentSegment(at: now)
            currentObservation = observation
            currentStart = now
            currentSegmentID = UUID()
        }

        currentApplication = observation.appName
        currentBundleIdentifier = observation.bundleIdentifier
        currentWindowTitle = observation.windowTitle
        isIdle = observation.isIdle
        refreshObservedSegments()
        persistSnapshot(at: now)
    }

    private func capturePendingIdleInterval(at end: Date) {
        guard pendingIdleInterval == nil,
              currentObservation?.isIdle == true,
              let currentStart,
              end.timeIntervalSince(currentStart) >= TimeInterval(preferences.idleThresholdSeconds) else {
            return
        }
        pendingIdleInterval = IdleInterval(start: currentStart, end: end)
    }

    private func currentObservationSnapshot(at date: Date) -> ActivityObservation? {
        guard preferences.shouldTrack(at: date) else { return nil }
        let idle = secondsSinceLastInput >= TimeInterval(preferences.idleThresholdSeconds)
        if idle {
            return ActivityObservation(
                appName: "Idle",
                bundleIdentifier: "com.metriday.idle",
                deviceName: deviceName,
                windowTitle: "No keyboard or pointer activity",
                resource: "",
                relevance: .idle,
                projectID: nil,
                isIdle: true,
                isCall: false
            )
        }

        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let bundleIdentifier = app.bundleIdentifier ?? "unknown"
        let appName = app.localizedName ?? "Unknown application"
        let windowTitle = frontmostWindowTitle(for: app) ?? ""
        let resource = trackedResource(for: app)
        guard !exclusionStore.isExcluded(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            resource: resource,
            deviceName: deviceName
        ) else { return nil }
        guard !ActivityPrivacy.isPrivateBrowserContext(
            appName: appName,
            windowTitle: windowTitle,
            resource: resource
        ) else {
            return nil
        }
        let relevance = ActivityClassifier.relevance(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            resource: resource
        )
        let startMinute = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        let candidate = ActivitySegment(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            deviceName: deviceName,
            windowTitle: windowTitle,
            resource: resource,
            startMinute: min(1_439, startMinute),
            endMinute: min(1_440, max(startMinute + 1, startMinute)),
            relevance: relevance
        )
        return ActivityObservation(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            deviceName: deviceName,
            windowTitle: windowTitle,
            resource: resource,
            relevance: relevance,
            projectID: projectStore.matchingProjectID(for: candidate, date: date),
            isIdle: false,
            isCall: ActivityCallDetector.isCall(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                windowTitle: windowTitle
            )
        )
    }

    private func trackedResource(for application: NSRunningApplication) -> String {
        let script: String
        switch application.bundleIdentifier {
        case "com.apple.Safari":
            script = #"tell application "Safari" to return URL of current tab of front window"#
        case "com.google.Chrome":
            script = #"tell application "Google Chrome" to return URL of active tab of front window"#
        case "org.mozilla.firefox":
            script = #"tell application "Firefox" to return URL of active tab of front window"#
        case "com.brave.Browser":
            script = #"tell application "Brave Browser" to return URL of active tab of front window"#
        default:
            return documentResource(for: application)
        }

        var error: NSDictionary?
        guard let value = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue else {
            return documentResource(for: application)
        }
        let resource = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return resource.isEmpty ? documentResource(for: application) : resource
    }

    /// Timing records the document currently being viewed, not merely the
    /// foreground application. Accessibility exposes that value on the
    /// focused window for many native document-based apps (Xcode, Preview,
    /// TextEdit, Pages, and similar applications).
    private func documentResource(for application: NSRunningApplication) -> String {
        guard accessibilityTrusted else { return "" }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        ) == .success,
        let focusedWindow,
        CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() else { return "" }

        let windowElement = focusedWindow as! AXUIElement
        var document: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            windowElement,
            kAXDocumentAttribute as CFString,
            &document
        ) == .success,
           let value = document as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success,
        let focusedElement,
        CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else { return "" }
        let element = focusedElement as! AXUIElement
        document = nil
        guard AXUIElementCopyAttributeValue(
            element,
            kAXDocumentAttribute as CFString,
            &document
        ) == .success,
        let value = document as? String else { return "" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func frontmostWindowTitle(for application: NSRunningApplication) -> String? {
        guard accessibilityTrusted else { return nil }
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        ) == .success,
        let focusedWindow,
        CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() else { return nil }
        let focusedWindowElement = focusedWindow as! AXUIElement

        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedWindowElement,
            kAXTitleAttribute as CFString,
            &title
        ) == .success else { return nil }
        return (title as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var secondsSinceLastInput: TimeInterval {
        let eventTypes: [CGEventType] = [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .mouseMoved,
            .scrollWheel
        ]
        let ages = eventTypes.map {
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0)
        }
        return ages.min() ?? 0
    }

    private func rotateDayIfNeeded(at date: Date) {
        let normalized = TrackingDay.logicalDayLabel(
            for: date,
            wrapAtMinute: activeWrapAtMinute,
            calendar: calendar
        )
        guard normalized != trackedDate else { return }
        finishCurrentSegment(at: date)
        persistDailySegments()
        trackedDate = normalized
        dailySegments = loadHistory(normalized)
        currentObservation = nil
        currentStart = nil
        refreshObservedSegments()
    }

    private func finishCurrentSegment(at end: Date) {
        guard let observation = currentObservation, let start = currentStart else { return }
        let startSecond = TrackingDay.axisSeconds(
            for: start,
            logicalDayLabel: trackedDate,
            wrapAtMinute: activeWrapAtMinute,
            calendar: calendar
        )
        let endLogicalDay = TrackingDay.logicalDayLabel(
            for: end,
            wrapAtMinute: activeWrapAtMinute,
            calendar: calendar
        )
        let endSecond = endLogicalDay == trackedDate
            ? TrackingDay.axisSeconds(
                for: end,
                logicalDayLabel: trackedDate,
                wrapAtMinute: activeWrapAtMinute,
                calendar: calendar
            )
            : TrackingDay.secondsPerDay
        let boundedEndSecond = max(startSecond + 1, min(TrackingDay.secondsPerDay, endSecond))
        guard boundedEndSecond > startSecond else { return }

        let segment = ActivitySegment(
            id: currentSegmentID,
            appName: observation.appName,
            bundleIdentifier: observation.bundleIdentifier,
            deviceName: observation.deviceName,
            windowTitle: observation.windowTitle,
            resource: observation.resource,
            startMinute: startSecond / 60,
            endMinute: Int(ceil(Double(boundedEndSecond) / 60.0)),
            startSecond: startSecond,
            endSecond: boundedEndSecond,
            relevance: observation.relevance,
            projectID: observation.projectID
        )
        append(segment)
        if observation.isCall,
           end.timeIntervalSince(start) >= 60,
           pendingCallInterval == nil {
            pendingCallInterval = CallInterval(
                appName: observation.appName,
                windowTitle: observation.windowTitle,
                start: start,
                end: end
            )
        }
        persistDailySegments()
    }

    private func append(_ segment: ActivitySegment) {
        if let index = dailySegments.indices.last,
           dailySegments[index].appName == segment.appName,
           dailySegments[index].bundleIdentifier == segment.bundleIdentifier,
           dailySegments[index].deviceName == segment.deviceName,
           dailySegments[index].windowTitle == segment.windowTitle,
           dailySegments[index].resource == segment.resource,
           dailySegments[index].relevance == segment.relevance,
           dailySegments[index].projectID == segment.projectID,
           segment.startSecond <= dailySegments[index].endSecond + 5 {
            dailySegments[index].endSecond = max(dailySegments[index].endSecond, segment.endSecond)
        } else {
            dailySegments.append(segment)
        }
    }

    private func persistDailySegments() {
        try? saveHistory(dailySegments, date: trackedDate)
    }

    private func persistSnapshot(at date: Date) {
        var snapshot = dailySegments
        if let current = currentSegment(at: date) {
            snapshot.append(current)
        }
        try? saveHistory(snapshot, date: trackedDate)
    }

    private func refreshObservedSegments() {
        if visibleDate == trackedDate {
            var segments = dailySegments
            if let current = currentSegment(at: .now) {
                segments.append(current)
            }
            observedSegments = segments
        } else {
            observedSegments = loadHistory(visibleDate)
        }
    }

    private func currentSegment(at date: Date) -> ActivitySegment? {
        guard let observation = currentObservation,
              let start = currentStart,
              TrackingDay.logicalDayLabel(
                  for: date,
                  wrapAtMinute: activeWrapAtMinute,
                  calendar: calendar
              ) == trackedDate else { return nil }
        let startSecond = TrackingDay.axisSeconds(
            for: start,
            logicalDayLabel: trackedDate,
            wrapAtMinute: activeWrapAtMinute,
            calendar: calendar
        )
        let endSecond = max(
            startSecond + 1,
            TrackingDay.axisSeconds(
                for: date,
                logicalDayLabel: trackedDate,
                wrapAtMinute: activeWrapAtMinute,
                calendar: calendar
            )
        )
        return ActivitySegment(
            id: currentSegmentID,
            appName: observation.appName,
            bundleIdentifier: observation.bundleIdentifier,
            deviceName: observation.deviceName,
            windowTitle: observation.windowTitle,
            resource: observation.resource,
            startMinute: startSecond / 60,
            endMinute: Int(ceil(Double(endSecond) / 60.0)),
            startSecond: startSecond,
            endSecond: endSecond,
            relevance: observation.relevance,
            projectID: observation.projectID
        )
    }

    private func loadHistory(_ date: Date) -> [ActivitySegment] {
        history.load(date: date, wrapAtMinute: activeWrapAtMinute)
    }

    private func saveHistory(_ segments: [ActivitySegment], date: Date) throws {
        try history.save(segments, date: date, wrapAtMinute: activeWrapAtMinute)
    }

    private func applyWrapDayPreference(_ newWrapAtMinute: Int) {
        guard newWrapAtMinute != activeWrapAtMinute else { return }
        let wasTracking = isTracking
        if wasTracking {
            finishCurrentSegment(at: .now)
            persistDailySegments()
        }
        activeWrapAtMinute = newWrapAtMinute
        trackedDate = TrackingDay.logicalDayLabel(
            for: .now,
            wrapAtMinute: activeWrapAtMinute,
            calendar: calendar
        )
        visibleDate = calendar.startOfDay(for: visibleDate)
        dailySegments = loadHistory(trackedDate)
        currentObservation = nil
        currentStart = nil
        if wasTracking {
            sample()
        } else {
            refreshObservedSegments()
        }
    }
}

private struct ActivityObservation: Equatable {
    let appName: String
    let bundleIdentifier: String
    let deviceName: String
    let windowTitle: String
    let resource: String
    let relevance: ActivityRelevance
    var projectID: UUID?
    let isIdle: Bool
    let isCall: Bool
}

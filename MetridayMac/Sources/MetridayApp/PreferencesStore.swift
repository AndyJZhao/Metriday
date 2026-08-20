import Combine
import Foundation

@MainActor
final class PreferencesStore: ObservableObject {
    @Published var idleThresholdSeconds: Int {
        didSet { persist() }
    }
    @Published var trackWeekends: Bool {
        didSet { persist() }
    }
    @Published var trackOnlyDuringWorkingHours: Bool {
        didSet { persist() }
    }
    @Published var workingHoursStartMinute: Int {
        didSet { persist() }
    }
    @Published var workingHoursEndMinute: Int {
        didSet { persist() }
    }
    @Published var automaticallyZoomTimelineToWorkingHours: Bool {
        didSet { persist() }
    }
    @Published var wrapDaysAtMinute: Int {
        didSet { persist() }
    }
    @Published var startTrackingWhenAppOpens: Bool {
        didSet { persist() }
    }
    @Published var autoStopTimerOnSleep: Bool {
        didSet { persist() }
    }
    @Published var reviewReminderIntervalMinutes: Int {
        didSet { persist() }
    }
    @Published var callNotificationsEnabled: Bool {
        didSet { persist() }
    }
    @Published var includeSubprojectsWhenSelectingProject: Bool {
        didSet { persist() }
    }
    @Published var allowLocalNetworkAPI: Bool {
        didSet { persist() }
    }

    let fileURL: URL

    init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? Self.defaultRootDirectory()
        self.fileURL = root.appendingPathComponent("Preferences.json")

        if let data = try? Data(contentsOf: fileURL),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            self.idleThresholdSeconds = payload.idleThresholdSeconds
            self.trackWeekends = payload.trackWeekends
            self.trackOnlyDuringWorkingHours = payload.trackOnlyDuringWorkingHours
            self.workingHoursStartMinute = payload.workingHoursStartMinute
            self.workingHoursEndMinute = payload.workingHoursEndMinute
            self.automaticallyZoomTimelineToWorkingHours = payload.automaticallyZoomTimelineToWorkingHours
            self.wrapDaysAtMinute = payload.wrapDaysAtMinute
            self.startTrackingWhenAppOpens = payload.startTrackingWhenAppOpens
            self.autoStopTimerOnSleep = payload.autoStopTimerOnSleep
            self.reviewReminderIntervalMinutes = payload.reviewReminderIntervalMinutes
            self.callNotificationsEnabled = payload.callNotificationsEnabled
            self.includeSubprojectsWhenSelectingProject = payload.includeSubprojectsWhenSelectingProject
            self.allowLocalNetworkAPI = payload.allowLocalNetworkAPI
        } else {
            self.idleThresholdSeconds = 120
            self.trackWeekends = true
            self.trackOnlyDuringWorkingHours = false
            self.workingHoursStartMinute = 9 * 60
            self.workingHoursEndMinute = 18 * 60
            self.automaticallyZoomTimelineToWorkingHours = false
            self.wrapDaysAtMinute = 0
            self.startTrackingWhenAppOpens = true
            self.autoStopTimerOnSleep = true
            self.reviewReminderIntervalMinutes = 0
            self.callNotificationsEnabled = true
            self.includeSubprojectsWhenSelectingProject = true
            self.allowLocalNetworkAPI = false
            persist()
        }
    }

    var idleThresholdMinutes: Int {
        max(1, Int((Double(idleThresholdSeconds) / 60.0).rounded()))
    }

    func shouldTrack(at date: Date) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let isWeekend = weekday == 1 || weekday == 7
        if isWeekend && !trackWeekends { return false }
        guard trackOnlyDuringWorkingHours else { return true }
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let current = hour * 60 + minute
        if workingHoursStartMinute < workingHoursEndMinute {
            return current >= workingHoursStartMinute && current < workingHoursEndMinute
        }
        // A reversed range represents an overnight working window, e.g. 22:00–06:00.
        return current >= workingHoursStartMinute || current < workingHoursEndMinute
    }

    private func persist() {
        guard !fileURL.path.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let payload = Payload(
                idleThresholdSeconds: idleThresholdSeconds,
                trackWeekends: trackWeekends,
                trackOnlyDuringWorkingHours: trackOnlyDuringWorkingHours,
                workingHoursStartMinute: workingHoursStartMinute,
                workingHoursEndMinute: workingHoursEndMinute,
                automaticallyZoomTimelineToWorkingHours: automaticallyZoomTimelineToWorkingHours,
                wrapDaysAtMinute: wrapDaysAtMinute,
                startTrackingWhenAppOpens: startTrackingWhenAppOpens,
                autoStopTimerOnSleep: autoStopTimerOnSleep,
                reviewReminderIntervalMinutes: reviewReminderIntervalMinutes,
                callNotificationsEnabled: callNotificationsEnabled,
                includeSubprojectsWhenSelectingProject: includeSubprojectsWhenSelectingProject,
                allowLocalNetworkAPI: allowLocalNetworkAPI
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(payload).write(to: fileURL, options: .atomic)
        } catch {
            // Preferences are best effort; tracking can continue with in-memory values.
        }
    }

    private static func defaultRootDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport.appendingPathComponent("Metriday", isDirectory: true)
    }

    private struct Payload: Codable {
        let idleThresholdSeconds: Int
        let trackWeekends: Bool
        let trackOnlyDuringWorkingHours: Bool
        let workingHoursStartMinute: Int
        let workingHoursEndMinute: Int
        let automaticallyZoomTimelineToWorkingHours: Bool
        let wrapDaysAtMinute: Int
        let startTrackingWhenAppOpens: Bool
        let autoStopTimerOnSleep: Bool
        let reviewReminderIntervalMinutes: Int
        let callNotificationsEnabled: Bool
        let includeSubprojectsWhenSelectingProject: Bool
        let allowLocalNetworkAPI: Bool

        init(
            idleThresholdSeconds: Int,
            trackWeekends: Bool,
            trackOnlyDuringWorkingHours: Bool,
            workingHoursStartMinute: Int,
            workingHoursEndMinute: Int,
            automaticallyZoomTimelineToWorkingHours: Bool,
            wrapDaysAtMinute: Int,
            startTrackingWhenAppOpens: Bool,
            autoStopTimerOnSleep: Bool,
            reviewReminderIntervalMinutes: Int,
            callNotificationsEnabled: Bool,
            includeSubprojectsWhenSelectingProject: Bool,
            allowLocalNetworkAPI: Bool
        ) {
            self.idleThresholdSeconds = idleThresholdSeconds
            self.trackWeekends = trackWeekends
            self.trackOnlyDuringWorkingHours = trackOnlyDuringWorkingHours
            self.workingHoursStartMinute = workingHoursStartMinute
            self.workingHoursEndMinute = workingHoursEndMinute
            self.automaticallyZoomTimelineToWorkingHours = automaticallyZoomTimelineToWorkingHours
            self.wrapDaysAtMinute = TrackingDay.clampedWrapMinute(wrapDaysAtMinute)
            self.startTrackingWhenAppOpens = startTrackingWhenAppOpens
            self.autoStopTimerOnSleep = autoStopTimerOnSleep
            self.reviewReminderIntervalMinutes = reviewReminderIntervalMinutes
            self.callNotificationsEnabled = callNotificationsEnabled
            self.includeSubprojectsWhenSelectingProject = includeSubprojectsWhenSelectingProject
            self.allowLocalNetworkAPI = allowLocalNetworkAPI
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            idleThresholdSeconds = try container.decode(Int.self, forKey: .idleThresholdSeconds)
            trackWeekends = try container.decode(Bool.self, forKey: .trackWeekends)
            trackOnlyDuringWorkingHours = try container.decode(Bool.self, forKey: .trackOnlyDuringWorkingHours)
            workingHoursStartMinute = try container.decode(Int.self, forKey: .workingHoursStartMinute)
            workingHoursEndMinute = try container.decode(Int.self, forKey: .workingHoursEndMinute)
            automaticallyZoomTimelineToWorkingHours = try container.decodeIfPresent(Bool.self, forKey: .automaticallyZoomTimelineToWorkingHours) ?? false
            wrapDaysAtMinute = TrackingDay.clampedWrapMinute(try container.decodeIfPresent(Int.self, forKey: .wrapDaysAtMinute) ?? 0)
            startTrackingWhenAppOpens = try container.decode(Bool.self, forKey: .startTrackingWhenAppOpens)
            autoStopTimerOnSleep = try container.decodeIfPresent(Bool.self, forKey: .autoStopTimerOnSleep) ?? true
            reviewReminderIntervalMinutes = max(0, min(24 * 60, try container.decodeIfPresent(Int.self, forKey: .reviewReminderIntervalMinutes) ?? 0))
            callNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .callNotificationsEnabled) ?? true
            includeSubprojectsWhenSelectingProject = try container.decodeIfPresent(Bool.self, forKey: .includeSubprojectsWhenSelectingProject) ?? true
            allowLocalNetworkAPI = try container.decodeIfPresent(Bool.self, forKey: .allowLocalNetworkAPI) ?? false
        }
    }
}

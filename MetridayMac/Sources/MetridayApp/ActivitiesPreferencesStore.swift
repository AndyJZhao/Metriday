import Combine
import Foundation

enum ActivityTimeRange: String, CaseIterable, Codable, Identifiable {
    case selectedDay
    case lastSevenDays
    case lastThirtyDays
    case lastNinetyDays

    var id: Self { self }

    var label: String {
        switch self {
        case .selectedDay: return "Selected day"
        case .lastSevenDays: return "Last 7 days"
        case .lastThirtyDays: return "Last 30 days"
        case .lastNinetyDays: return "Last 90 days"
        }
    }

}

enum ActivityTimelineOrientation: String, CaseIterable, Codable, Identifiable {
    case horizontal
    case vertical

    var id: Self { self }

    var label: String {
        switch self {
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        }
    }

    var icon: String {
        switch self {
        case .horizontal: return "rectangle.split.3x1"
        case .vertical: return "rectangle.split.3x1.fill"
        }
    }
}

enum ActivityPathGrouping: String, CaseIterable, Codable, Identifiable {
    case immediateParentDirectory
    case allDirectories
    case filePathOnly

    var id: Self { self }

    var label: String {
        switch self {
        case .immediateParentDirectory: return "Immediate parent directory"
        case .allDirectories: return "All directories"
        case .filePathOnly: return "File path only"
        }
    }

    func groupNames(for resource: String) -> [String] {
        let value = resource.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        let path: String
        if let url = URL(string: value), url.isFileURL {
            path = url.path
        } else if let url = URL(string: value), url.host != nil {
            return []
        } else {
            path = value
        }
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        let fileURL = URL(fileURLWithPath: normalized)
        switch self {
        case .filePathOnly:
            return [normalized]
        case .immediateParentDirectory:
            return [fileURL.deletingLastPathComponent().path]
        case .allDirectories:
            var names: [String] = []
            var current = fileURL.deletingLastPathComponent().path
            while !current.isEmpty, current != "/" {
                names.append(current)
                let parent = URL(fileURLWithPath: current).deletingLastPathComponent().path
                if parent == current { break }
                current = parent
            }
            return names
        }
    }
}

/// Display-only preferences for Activities. They do not change what the
/// activity monitor captures or what is stored on disk.
@MainActor
final class ActivitiesPreferencesStore: ObservableObject {
    @Published var includeTimeEntries: Bool { didSet { persist() } }
    @Published var showWindowTitles: Bool { didSet { persist() } }
    @Published var showResourcePaths: Bool { didSet { persist() } }
    @Published var showActivityDateRanges: Bool { didSet { persist() } }
    @Published var includeTitlesInAdditionToPaths: Bool { didSet { persist() } }
    @Published var groupWebsitesIndependently: Bool { didSet { persist() } }
    @Published var groupPathsIndependently: Bool { didSet { persist() } }
    @Published var groupPathsBy: ActivityPathGrouping { didSet { persist() } }
    @Published var activityTimeRange: ActivityTimeRange { didSet { persist() } }
    @Published var activityDisplayMode: String { didSet { persist() } }
    @Published var groupByProject: Bool { didSet { persist() } }
    @Published var groupByDevice: Bool { didSet { persist() } }
    @Published var includeIdle: Bool { didSet { persist() } }
    @Published var selectedDevice: String { didSet { persist() } }
    @Published var timelineOrientation: ActivityTimelineOrientation { didSet { persist() } }
    @Published var collapseActivitiesShorterThanSeconds: Int { didSet { persist() } }

    private let fileURL: URL

    init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? Self.defaultRootDirectory()
        self.fileURL = root.appendingPathComponent("ActivitiesPreferences.json")
        if let data = try? Data(contentsOf: fileURL),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            includeTimeEntries = payload.includeTimeEntries
            showWindowTitles = payload.showWindowTitles
            showResourcePaths = payload.showResourcePaths
            showActivityDateRanges = payload.showActivityDateRanges
            includeTitlesInAdditionToPaths = payload.includeTitlesInAdditionToPaths
            groupWebsitesIndependently = payload.groupWebsitesIndependently
            groupPathsIndependently = payload.groupPathsIndependently
            groupPathsBy = payload.groupPathsBy
            activityTimeRange = payload.activityTimeRange
            activityDisplayMode = payload.activityDisplayMode
            groupByProject = payload.groupByProject
            groupByDevice = payload.groupByDevice
            includeIdle = payload.includeIdle
            selectedDevice = payload.selectedDevice
            timelineOrientation = payload.timelineOrientation
            collapseActivitiesShorterThanSeconds = max(0, payload.collapseActivitiesShorterThanSeconds)
        } else {
            includeTimeEntries = true
            showWindowTitles = true
            showResourcePaths = true
            showActivityDateRanges = false
            includeTitlesInAdditionToPaths = true
            groupWebsitesIndependently = false
            groupPathsIndependently = false
            groupPathsBy = .allDirectories
            activityTimeRange = .selectedDay
            activityDisplayMode = "chronological"
            groupByProject = true
            groupByDevice = false
            includeIdle = false
            selectedDevice = "All Devices"
            timelineOrientation = .vertical
            collapseActivitiesShorterThanSeconds = 0
            persist()
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let payload = Payload(
                includeTimeEntries: includeTimeEntries,
                showWindowTitles: showWindowTitles,
                showResourcePaths: showResourcePaths,
                showActivityDateRanges: showActivityDateRanges,
                includeTitlesInAdditionToPaths: includeTitlesInAdditionToPaths,
                groupWebsitesIndependently: groupWebsitesIndependently,
                groupPathsIndependently: groupPathsIndependently,
                groupPathsBy: groupPathsBy,
                activityTimeRange: activityTimeRange,
                activityDisplayMode: activityDisplayMode,
                groupByProject: groupByProject,
                groupByDevice: groupByDevice,
                includeIdle: includeIdle,
                selectedDevice: selectedDevice,
                timelineOrientation: timelineOrientation,
                collapseActivitiesShorterThanSeconds: collapseActivitiesShorterThanSeconds
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(payload).write(to: fileURL, options: .atomic)
        } catch {
            // Display preferences are best effort; tracking can continue.
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
        let includeTimeEntries: Bool
        let showWindowTitles: Bool
        let showResourcePaths: Bool
        let showActivityDateRanges: Bool
        let includeTitlesInAdditionToPaths: Bool
        let groupWebsitesIndependently: Bool
        let groupPathsIndependently: Bool
        let groupPathsBy: ActivityPathGrouping
        let activityTimeRange: ActivityTimeRange
        let activityDisplayMode: String
        let groupByProject: Bool
        let groupByDevice: Bool
        let includeIdle: Bool
        let selectedDevice: String
        let timelineOrientation: ActivityTimelineOrientation
        let collapseActivitiesShorterThanSeconds: Int

        init(
            includeTimeEntries: Bool,
            showWindowTitles: Bool,
            showResourcePaths: Bool,
            showActivityDateRanges: Bool,
            includeTitlesInAdditionToPaths: Bool,
            groupWebsitesIndependently: Bool,
            groupPathsIndependently: Bool,
            groupPathsBy: ActivityPathGrouping,
            activityTimeRange: ActivityTimeRange,
            activityDisplayMode: String,
            groupByProject: Bool,
            groupByDevice: Bool,
            includeIdle: Bool,
            selectedDevice: String,
            timelineOrientation: ActivityTimelineOrientation,
            collapseActivitiesShorterThanSeconds: Int
        ) {
            self.includeTimeEntries = includeTimeEntries
            self.showWindowTitles = showWindowTitles
            self.showResourcePaths = showResourcePaths
            self.showActivityDateRanges = showActivityDateRanges
            self.includeTitlesInAdditionToPaths = includeTitlesInAdditionToPaths
            self.groupWebsitesIndependently = groupWebsitesIndependently
            self.groupPathsIndependently = groupPathsIndependently
            self.groupPathsBy = groupPathsBy
            self.activityTimeRange = activityTimeRange
            self.activityDisplayMode = activityDisplayMode
            self.groupByProject = groupByProject
            self.groupByDevice = groupByDevice
            self.includeIdle = includeIdle
            self.selectedDevice = selectedDevice
            self.timelineOrientation = timelineOrientation
            self.collapseActivitiesShorterThanSeconds = max(0, collapseActivitiesShorterThanSeconds)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            includeTimeEntries = try container.decodeIfPresent(Bool.self, forKey: .includeTimeEntries) ?? true
            showWindowTitles = try container.decodeIfPresent(Bool.self, forKey: .showWindowTitles) ?? true
            showResourcePaths = try container.decodeIfPresent(Bool.self, forKey: .showResourcePaths) ?? true
            showActivityDateRanges = try container.decodeIfPresent(Bool.self, forKey: .showActivityDateRanges) ?? false
            includeTitlesInAdditionToPaths = try container.decodeIfPresent(Bool.self, forKey: .includeTitlesInAdditionToPaths) ?? true
            groupWebsitesIndependently = try container.decodeIfPresent(Bool.self, forKey: .groupWebsitesIndependently) ?? false
            groupPathsIndependently = try container.decodeIfPresent(Bool.self, forKey: .groupPathsIndependently) ?? false
            groupPathsBy = try container.decodeIfPresent(ActivityPathGrouping.self, forKey: .groupPathsBy) ?? .allDirectories
            activityTimeRange = try container.decodeIfPresent(ActivityTimeRange.self, forKey: .activityTimeRange) ?? .selectedDay
            activityDisplayMode = try container.decodeIfPresent(String.self, forKey: .activityDisplayMode) ?? "chronological"
            groupByProject = try container.decodeIfPresent(Bool.self, forKey: .groupByProject) ?? true
            groupByDevice = try container.decodeIfPresent(Bool.self, forKey: .groupByDevice) ?? false
            includeIdle = try container.decodeIfPresent(Bool.self, forKey: .includeIdle) ?? false
            selectedDevice = try container.decodeIfPresent(String.self, forKey: .selectedDevice) ?? "All Devices"
            timelineOrientation = try container.decodeIfPresent(ActivityTimelineOrientation.self, forKey: .timelineOrientation) ?? .vertical
            collapseActivitiesShorterThanSeconds = max(0, try container.decodeIfPresent(Int.self, forKey: .collapseActivitiesShorterThanSeconds) ?? 0)
        }
    }
}

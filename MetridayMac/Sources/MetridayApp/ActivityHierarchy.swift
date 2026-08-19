import Foundation

/// Local implementation of Timing's token-efficient Activity Hierarchy API.
/// It deliberately emits stable plain text so scripts and AI tools can consume
/// the same evidence as Review without requiring a cloud account.
@MainActor
enum ActivityHierarchyBuilder {
    struct Options {
        var blockSize = "total"
        var minimumDurationSeconds = 60
        var groupByProject = true
        var maxDepth = 0
        var maxLines = 100
        var includeMobileDevices = false
        var includeSubprojects = true
        var projectIDs: Set<UUID> = []
        var includeUnassigned = true
        var onlyUnassigned = false
    }

    private final class Node {
        let title: String
        var seconds = 0
        var children: [String: Node] = [:]

        init(title: String) {
            self.title = title
        }
    }

    static func render(
        activityDays: [(date: Date, segments: [ActivitySegment])],
        projectStore: ProjectStore,
        options: Options
    ) -> String {
        let sortedDays = activityDays.sorted { $0.date < $1.date }
        let root = Node(title: "")
        var totalSeconds = 0
        let calendar = Calendar.current

        for day in sortedDays {
            let dayStart = calendar.startOfDay(for: day.date)
            for segment in day.segments {
                guard segment.durationSeconds >= max(1, options.minimumDurationSeconds) else { continue }
                if !options.includeMobileDevices && isMobileDevice(segment.deviceName) { continue }
                if !matchesProjectFilter(segment.projectID, options: options) { continue }

                let absoluteStart = dayStart.addingTimeInterval(TimeInterval(segment.startSecond))
                let duration = segment.durationSeconds
                let projectPath: String
                if let projectID = segment.projectID {
                    projectPath = options.includeSubprojects
                        ? projectStore.hierarchyPath(for: projectID)
                        : projectStore.name(for: projectID)
                } else {
                    guard options.includeUnassigned else { continue }
                    projectPath = "(Unassigned)"
                }
                var levels: [String] = []
                if options.blockSize != "total" {
                    levels.append(bucketLabel(for: absoluteStart, blockSize: options.blockSize))
                }
                if options.groupByProject {
                    levels.append(projectPath)
                }
                levels.append(segment.appName.isEmpty ? "Activity" : segment.appName)
                if let detail = detailLabel(for: segment), !detail.isEmpty {
                    levels.append(detail)
                }
                let limitedLevels = options.maxDepth > 0
                    ? Array(levels.prefix(options.maxDepth))
                    : levels
                add(duration: duration, levels: limitedLevels, to: root)
                totalSeconds += duration
            }
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let firstDate = sortedDays.first.map { dateFormatter.string(from: $0.date) } ?? dateFormatter.string(from: .now)
        let lastDate = sortedDays.last.map { dateFormatter.string(from: $0.date) } ?? firstDate
        var lines = [
            "Date range: \(firstDate) 00:00 – \(lastDate) 23:59",
            "Total tracked: \(durationLabel(totalSeconds)) (\(totalSeconds) seconds)",
            ""
        ]
        let budget = max(1, min(options.maxLines, 1_000))
        append(nodes: root.children.values.sorted(by: sortNodes), to: &lines, indent: 0, budget: budget)
        if lines.count > budget + 3 {
            lines = Array(lines.prefix(budget + 3))
            lines.append("…")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func add(duration: Int, levels: [String], to root: Node) {
        root.seconds += duration
        var node = root
        for level in levels {
            let key = level.isEmpty ? "(Unassigned)" : level
            let child = node.children[key] ?? Node(title: key)
            node.children[key] = child
            child.seconds += duration
            node = child
        }
    }

    private static func append(
        nodes: [Node],
        to lines: inout [String],
        indent: Int,
        budget: Int
    ) {
        guard lines.count < budget + 3 else { return }
        for node in nodes {
            guard lines.count < budget + 3 else { return }
            lines.append(String(repeating: "\t", count: indent) + "\(durationLabel(node.seconds)) \(node.title)")
            if !node.children.isEmpty {
                append(
                    nodes: node.children.values.sorted(by: sortNodes),
                    to: &lines,
                    indent: indent + 1,
                    budget: budget
                )
            }
        }
    }

    private static func sortNodes(_ lhs: Node, _ rhs: Node) -> Bool {
        if lhs.seconds == rhs.seconds { return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
        return lhs.seconds > rhs.seconds
    }

    private static func matchesProjectFilter(_ projectID: UUID?, options: Options) -> Bool {
        if options.onlyUnassigned { return projectID == nil }
        guard !options.projectIDs.isEmpty else { return true }
        return projectID.map(options.projectIDs.contains) ?? false
    }

    private static func isMobileDevice(_ deviceName: String) -> Bool {
        let value = deviceName.lowercased()
        return value.contains("iphone")
            || value.contains("ipad")
            || value.contains("mobile")
            || value.contains("ios")
            || value.contains("screen time")
    }

    private static func bucketLabel(for date: Date, blockSize: String) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        switch blockSize.lowercased() {
        case "day":
            return String(format: "%04d-%02d-%02d", year, month, day)
        case "hour":
            return String(format: "%04d-%02d-%02d %02d:00", year, month, day, hour)
        case "15min", "15_min", "quarter":
            return String(format: "%04d-%02d-%02d %02d:%02d", year, month, day, hour, (minute / 15) * 15)
        case "5min", "5_min":
            return String(format: "%04d-%02d-%02d %02d:%02d", year, month, day, hour, (minute / 5) * 5)
        default:
            return String(format: "%04d-%02d-%02d", year, month, day)
        }
    }

    private static func detailLabel(for segment: ActivitySegment) -> String? {
        let resource = segment.resource.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: resource), let host = url.host, !host.isEmpty {
            let path = url.path == "/" ? "" : url.path
            return host + path
        }
        let title = segment.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, title.caseInsensitiveCompare(segment.appName) != .orderedSame {
            return title
        }
        return resource.isEmpty ? nil : resource
    }

    private static func durationLabel(_ seconds: Int) -> String {
        let total = max(0, seconds)
        return String(format: "%d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
    }
}

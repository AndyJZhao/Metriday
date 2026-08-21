import Foundation

enum TimeBlockRelevance {
    private static let ignoredKeywords: Set<String> = [
        "a", "an", "and", "for", "from", "into", "of", "on", "or", "the", "to", "with"
    ]

    static func explanation(
        task: PlanTask,
        activity: ActivitySegment,
        category: ActivityCategoryDefinition
    ) -> String {
        let keywords = keywords(for: task)
        let activityText = [activity.appName, activity.windowTitle, activity.resource]
            .joined(separator: " ")
            .lowercased()
        if let keyword = keywords.first(where: { activityText.contains($0) }) {
            return "Task keyword \u{201C}\(keyword)\u{201D} matched activity"
        }

        switch category.role {
        case .focused:
            return "Focused category"
        case .distracting:
            return "Distracting category"
        case .other, .idle:
            return "Overlapped planned time"
        }
    }

    private static func keywords(for task: PlanTask) -> [String] {
        let source = ([task.title] + task.tags)
            .joined(separator: " ")
            .lowercased()
        let parts = source.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 && !ignoredKeywords.contains($0) }
            .reduce(into: [String]()) { result, keyword in
                if !result.contains(keyword) { result.append(keyword) }
            }
    }
}

struct TimeBlockExecutionSummary: Hashable {
    let durationSeconds: Int
    let intervalCount: Int
    let isRunning: Bool

    static let empty = TimeBlockExecutionSummary(durationSeconds: 0, intervalCount: 0, isRunning: false)

    var hasExecution: Bool {
        durationSeconds > 0
    }

    var durationLabel: String {
        let minutes = max(0, Int((Double(durationSeconds) / 60.0).rounded()))
        if minutes < 1 { return "<1m" }
        let hours = minutes / 60
        return hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
    }

    var statusLabel: String {
        isRunning ? "In progress · \(durationLabel)" : "Actual \(durationLabel)"
    }
}

func timeBlockExecutionSummary(
    taskID: UUID,
    entries: [TimeEntry],
    runningTimer: RunningTimer?,
    date: Date
) -> TimeBlockExecutionSummary {
    let calendar = Calendar.current
    let dayStart = calendar.startOfDay(for: date)
    guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
        return .empty
    }
    let taskIDValue = taskID.uuidString.lowercased()
    let linkedEntries = entries.filter { entry in
        guard entry.customFields["metriday_plan_task_id"]?.lowercased() == taskIDValue else { return false }
        return entry.start < dayEnd && entry.end > dayStart
    }
    let durationSeconds = linkedEntries.reduce(0) { total, entry in
        let start = max(entry.start, dayStart)
        let end = min(entry.end, dayEnd)
        return total + max(0, Int(end.timeIntervalSince(start)))
    }
    let isRunning = runningTimer?.customFields["metriday_plan_task_id"]?.lowercased() == taskIDValue
    return TimeBlockExecutionSummary(
        durationSeconds: durationSeconds,
        intervalCount: linkedEntries.count,
        isRunning: isRunning
    )
}

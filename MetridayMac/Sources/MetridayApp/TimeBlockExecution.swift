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

struct TimeBlockActivityQuality: Hashable {
    let focusedSeconds: Int
    let distractedSeconds: Int
    let otherSeconds: Int
    let idleSeconds: Int

    static let empty = TimeBlockActivityQuality(
        focusedSeconds: 0,
        distractedSeconds: 0,
        otherSeconds: 0,
        idleSeconds: 0
    )

    var activeSeconds: Int {
        focusedSeconds + distractedSeconds + otherSeconds
    }

    var hasActivity: Bool {
        activeSeconds + idleSeconds > 0
    }

    var focusedPercentage: Int {
        percentage(focusedSeconds, of: activeSeconds)
    }

    var distractedPercentage: Int {
        percentage(distractedSeconds, of: activeSeconds)
    }

    private func percentage(_ value: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(value) / Double(total) * 100).rounded())
    }
}

func timeBlockActivityQuality(
    segments: [ActivitySegment],
    plannedStartSecond: Int,
    plannedEndSecond: Int
) -> TimeBlockActivityQuality {
    guard plannedEndSecond > plannedStartSecond else { return .empty }
    var focusedSeconds = 0
    var distractedSeconds = 0
    var otherSeconds = 0
    var idleSeconds = 0

    for segment in segments {
        let overlapStart = max(plannedStartSecond, segment.startSecond)
        let overlapEnd = min(plannedEndSecond, segment.endSecond)
        guard overlapEnd > overlapStart else { continue }
        let seconds = overlapEnd - overlapStart
        switch segment.relevance {
        case .related:
            focusedSeconds += seconds
        case .distracted:
            distractedSeconds += seconds
        case .other:
            otherSeconds += seconds
        case .idle:
            idleSeconds += seconds
        }
    }

    return TimeBlockActivityQuality(
        focusedSeconds: focusedSeconds,
        distractedSeconds: distractedSeconds,
        otherSeconds: otherSeconds,
        idleSeconds: idleSeconds
    )
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

/// Returns the countdown to use when Focus is resumed for a planned task.
///
/// A resumed Focus Session should continue from the task's accumulated
/// execution instead of resetting to the full Markdown block duration. Once
/// the planned duration has already been reached, the next session is open
/// ended so the countdown does not pretend that the task has time remaining.
func timeBlockFocusEstimateSeconds(
    task: PlanTask,
    entries: [TimeEntry],
    date: Date
) -> Int? {
    guard task.isScheduled else { return nil }
    let plannedSeconds = task.duration * 60
    let executedSeconds = timeBlockExecutionSummary(
        taskID: task.id,
        entries: entries,
        runningTimer: nil,
        date: date
    ).durationSeconds
    guard executedSeconds < plannedSeconds else { return nil }
    return max(60, plannedSeconds - executedSeconds)
}

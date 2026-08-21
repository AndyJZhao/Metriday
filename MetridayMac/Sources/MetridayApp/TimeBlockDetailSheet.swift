import SwiftUI

struct TimeBlockDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    let task: PlanTask
    let selectedDate: Date

    private var linkedEntries: [TimeEntry] {
        let taskID = task.id.uuidString.lowercased()
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selectedDate)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        return appState.timeEntryStore
            .materializedEntries()
            .filter { entry in
                entry.customFields["metriday_plan_task_id"]?.lowercased() == taskID
                    && entry.start < dayEnd
                    && entry.end > dayStart
            }
            .sorted { $0.start < $1.start }
    }

    private var execution: TimeBlockExecutionSummary {
        timeBlockExecutionSummary(
            taskID: task.id,
            entries: appState.timeEntryStore.materializedEntries(),
            runningTimer: appState.timeEntryStore.runningTimer,
            date: selectedDate
        )
    }

    private var isFocused: Bool {
        guard appState.focusSessionActive else { return false }
        return appState.timeEntryStore.runningTimer?.customFields["metriday_plan_task_id"]?.lowercased()
            == task.id.uuidString.lowercased()
    }

    private var anotherFocusSessionIsActive: Bool {
        appState.focusSessionActive && !isFocused
    }

    private var effectiveActivitySegments: [ActivitySegment] {
        appState.categoryStore.applyingCategories(
            to: appState.activityMonitor.segments(for: selectedDate) + appState.screenTimeStore.segments(for: selectedDate),
            filterStore: appState.filterStore,
            date: selectedDate
        )
    }

    private var activityQuality: TimeBlockActivityQuality {
        guard let startMinute = task.startMinute, let endMinute = task.endMinute else { return .empty }
        return timeBlockActivityQuality(
            segments: effectiveActivitySegments,
            plannedStartSecond: startMinute * 60,
            plannedEndSecond: endMinute * 60
        )
    }

    private var evidenceRows: [TimeBlockEvidence] {
        guard let startMinute = task.startMinute, let endMinute = task.endMinute else { return [] }
        let plannedStart = startMinute * 60
        let plannedEnd = endMinute * 60

        var grouped: [String: TimeBlockEvidence] = [:]
        for segment in effectiveActivitySegments {
            let overlapStart = max(plannedStart, segment.startSecond)
            let overlapEnd = min(plannedEnd, segment.endSecond)
            guard overlapEnd > overlapStart else { continue }
            let category = appState.categoryStore.category(
                for: segment,
                filterStore: appState.filterStore,
                date: selectedDate
            )
            let reason = TimeBlockRelevance.explanation(
                task: task,
                activity: segment,
                category: category
            )
            let website = URL(string: segment.resource)?.host
            let detail = website ?? segment.windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = "\(segment.appName)|\(detail)|\(category.id.uuidString)"
            let row = grouped[key] ?? TimeBlockEvidence(
                id: key,
                appName: segment.appName.isEmpty ? "Unknown App" : segment.appName,
                detail: detail,
                seconds: 0,
                categoryName: category.name,
                color: color(for: category),
                reason: reason
            )
            grouped[key] = TimeBlockEvidence(
                id: row.id,
                appName: row.appName,
                detail: row.detail,
                seconds: row.seconds + overlapEnd - overlapStart,
                categoryName: row.categoryName,
                color: row.color,
                reason: row.reason
            )
        }
        return grouped.values.sorted { $0.seconds > $1.seconds }.prefix(8).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            executionSummary

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intervalsSection
                    evidenceSection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            actions
        }
        .padding(24)
        .frame(width: 540, height: 610)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(MetridayTheme.accent)
                .frame(width: 42, height: 42)
                .background(MetridayTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Time Block")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MetridayTheme.accent)
                Text(task.title)
                    .font(.system(size: 19, weight: .bold))
                    .lineLimit(2)
                HStack(spacing: 7) {
                    Text(task.timeRange ?? "Unscheduled")
                    if !task.tags.isEmpty {
                        Text("·")
                        Text(task.tags.map { "#\($0)" }.joined(separator: " "))
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MetridayTheme.secondary)
            }
            Spacer()
            Button("Close") { dismiss() }
                .buttonStyle(.borderless)
        }
    }

    private var executionSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                summaryMetric(label: "Planned", value: plannedDurationLabel)
                summaryMetric(label: "Actual", value: execution.hasExecution ? execution.durationLabel : "—")
                summaryMetric(label: "Intervals", value: execution.intervalCount > 0 ? "\(execution.intervalCount)" : "—")
                Spacer()
            }
            if let startMinute = task.startMinute, let endMinute = task.endMinute {
                let plannedSeconds = max(1, (endMinute - startMinute) * 60)
                let progress = min(1, Double(execution.durationSeconds) / Double(plannedSeconds))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(MetridayTheme.line.opacity(0.6))
                        Capsule().fill(execution.isRunning ? MetridayTheme.accent : MetridayTheme.success)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 6)
            }
            Text(execution.isRunning ? "Focus is running for this block." : execution.hasExecution ? "Actual time is linked to this Markdown task." : "Start Focus to link the actual interval to this Time Block.")
                .font(.system(size: 11))
                .foregroundStyle(MetridayTheme.secondary)
            if activityQuality.hasActivity {
                activityQualityView
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MetridayTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func summaryMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(MetridayTheme.secondary)
            Text(value)
                .font(.system(size: 15, weight: .bold))
        }
        .frame(minWidth: 76, alignment: .leading)
    }

    private var activityQualityView: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Focus quality · \(activityQuality.focusedPercentage)% focused")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MetridayTheme.graphite)
            HStack(spacing: 12) {
                qualityMetric(label: "Focused", seconds: activityQuality.focusedSeconds, color: MetridayTheme.accentDeep)
                qualityMetric(label: "Distracting", seconds: activityQuality.distractedSeconds, color: MetridayTheme.danger)
                qualityMetric(label: "Other", seconds: activityQuality.otherSeconds, color: MetridayTheme.secondary)
                if activityQuality.idleSeconds > 0 {
                    qualityMetric(label: "Idle", seconds: activityQuality.idleSeconds, color: MetridayTheme.line)
                }
            }
        }
        .padding(.top, 2)
    }

    private func qualityMetric(label: String, seconds: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(label) \(formatDuration(seconds: seconds))")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MetridayTheme.secondary)
        }
    }

    private var plannedDurationLabel: String {
        guard let start = task.startMinute, let end = task.endMinute else { return "—" }
        return formatDuration(seconds: max(0, (end - start) * 60))
    }

    private var intervalsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("Execution intervals", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
            if linkedEntries.isEmpty {
                Text("No linked execution intervals yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(MetridayTheme.secondary)
            } else {
                ForEach(linkedEntries) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.customFields["metriday_focus_session"] == "true" ? "target" : "clock")
                            .foregroundStyle(entry.customFields["metriday_focus_session"] == "true" ? MetridayTheme.accent : MetridayTheme.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dateRange(entry.start, entry.end))
                                .font(.system(size: 12, weight: .semibold))
                            Text(entry.isManual ? "Manual time entry" : "Focus Session")
                                .font(.system(size: 10))
                                .foregroundStyle(MetridayTheme.secondary)
                        }
                        Spacer()
                        Text(formatDuration(seconds: entry.durationSeconds))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MetridayTheme.secondary)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("App & website evidence", systemImage: "rectangle.on.rectangle")
            Text("Observed inside the planned Time Block window; this evidence does not rewrite Markdown.")
                .font(.system(size: 11))
                .foregroundStyle(MetridayTheme.secondary)
            if evidenceRows.isEmpty {
                Text("No App or website evidence overlaps this block yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(MetridayTheme.secondary)
            } else {
                ForEach(evidenceRows) { row in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(row.color)
                            .frame(width: 7, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.appName)
                                .font(.system(size: 12, weight: .semibold))
                            Text(row.detail.isEmpty ? row.categoryName : "\(row.detail) · \(row.categoryName)")
                                .font(.system(size: 10))
                                .foregroundStyle(MetridayTheme.secondary)
                                .lineLimit(1)
                            Text(row.reason)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(MetridayTheme.accentDeep)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(formatDuration(seconds: row.seconds))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(MetridayTheme.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(MetridayTheme.graphite)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(task.isCompleted ? "Mark incomplete" : "Mark complete") {
                appState.markdownStore.toggleCompleted(id: task.id)
            }
            .buttonStyle(.bordered)

            Button {
                appState.selectedTaskID = task.id
                if isFocused {
                    _ = appState.stopFocusSession()
                } else {
                    _ = appState.startFocusSession(taskID: task.id, date: selectedDate)
                }
            } label: {
                Label(isFocused ? "Pause Focus" : "Start Focus", systemImage: isFocused ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(anotherFocusSessionIsActive || !task.isScheduled)

            Spacer()
            Button("Remove time", role: .destructive) {
                appState.markdownStore.unschedule(id: task.id)
                dismiss()
            }
            .buttonStyle(.borderless)
        }
        .font(.system(size: 12, weight: .semibold))
    }

    private func color(for category: ActivityCategoryDefinition) -> Color {
        switch category.color {
        case .blue: return MetridayTheme.accentDeep
        case .green: return MetridayTheme.success
        case .orange: return MetridayTheme.warning
        case .purple: return .purple
        case .red: return MetridayTheme.danger
        case .graphite: return MetridayTheme.secondary
        }
    }

    private func formatDuration(seconds: Int) -> String {
        let minutes = Int((Double(max(0, seconds)) / 60.0).rounded())
        if minutes < 1 { return "<1m" }
        let hours = minutes / 60
        return hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
    }

    private func dateRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }
}

private struct TimeBlockEvidence: Identifiable {
    let id: String
    let appName: String
    let detail: String
    let seconds: Int
    let categoryName: String
    let color: Color
    let reason: String
}

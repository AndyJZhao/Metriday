import AppKit
import SwiftUI

/// A single floating surface for the existing Timer / Focus state.
///
/// The panel intentionally owns no timer or activity data. It observes
/// AppState and TimeEntryStore, so closing it only hides the window and never
/// changes the running session.
@MainActor
final class FocusCompanionController: NSObject, NSWindowDelegate {
    private weak var appState: AppState?
    private var panel: FocusCompanionPanel?

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        guard let appState else { return }
        if panel == nil {
            let panel = FocusCompanionPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 370),
                styleMask: [.borderless, .resizable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.delegate = self
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.isMovableByWindowBackground = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.minSize = NSSize(width: 390, height: 330)
            panel.maxSize = NSSize(width: 520, height: 460)
            panel.contentView = NSHostingView(
                rootView: FocusCompanionView(appState: appState)
            )
            self.panel = panel

            if let visibleFrame = NSScreen.main?.visibleFrame {
                let origin = NSPoint(
                    x: visibleFrame.maxX - panel.frame.width - 24,
                    y: visibleFrame.maxY - panel.frame.height - 24
                )
                panel.setFrameOrigin(origin)
            }
        }

        panel?.orderFrontRegardless()
        panel?.makeKey()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

private final class FocusCompanionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct FocusCompanionView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var timeEntryStore: TimeEntryStore
    @ObservedObject private var blocker: WebBlockerService
    @ObservedObject private var projectStore: ProjectStore
    @State private var metrics = FocusCompanionMetrics.empty

    private static let metricsClock = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    init(appState: AppState) {
        self.appState = appState
        self._timeEntryStore = ObservedObject(wrappedValue: appState.timeEntryStore)
        self._blocker = ObservedObject(wrappedValue: appState.blocker)
        self._projectStore = ObservedObject(wrappedValue: appState.projectStore)
    }

    var body: some View {
        TimelineView(.periodic(from: MetridayTimeline.anchor, by: 1)) { context in
            let timer = timeEntryStore.runningTimer
            let snapshot = snapshot(for: timer, now: context.date, metrics: metrics)

            VStack(alignment: .leading, spacing: 0) {
                header(snapshot: snapshot)
                Divider().opacity(0.7)
                currentBlock(snapshot: snapshot)
                timerSummary(snapshot: snapshot)
                activityBreakdown(snapshot: snapshot)
                Divider().opacity(0.7)
                footer(timer: timer, snapshot: snapshot)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.78), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            .padding(1)
        }
        .frame(minWidth: 390, minHeight: 330)
        .onExitCommand {
            appState.hideFocusCompanion()
        }
        .onAppear {
            refreshMetrics()
        }
        .onReceive(Self.metricsClock) { _ in
            refreshMetrics()
        }
    }

    private func header(snapshot: FocusCompanionSnapshot) -> some View {
        HStack(spacing: 9) {
            Image(systemName: snapshot.isFocus ? "target" : "timer")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(snapshot.isFocus ? MetridayTheme.accentDeep : MetridayTheme.secondary)
                .frame(width: 24, height: 24)
                .background((snapshot.isFocus ? MetridayTheme.accent : MetridayTheme.line).opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.isFocus ? snapshot.isPaused ? "Focus Session · Paused" : "Focus Session" : "Timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)
                Text(snapshot.timerTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MetridayTheme.graphite)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Button {
                appState.hideFocusCompanion()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MetridayTheme.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.black.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Hide Focus companion")
            .accessibilityLabel("Hide Focus companion")
            .accessibilityIdentifier("focus-companion.hide")
        }
        .padding(.bottom, 11)
    }

    private func currentBlock(snapshot: FocusCompanionSnapshot) -> some View {
        Button {
            appState.openCurrentFocusBlock()
            appState.hideFocusCompanion()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: snapshot.hasTask ? "checkmark.circle" : "folder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(snapshot.hasTask ? MetridayTheme.accentDeep : MetridayTheme.secondary)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.hasTask ? "Current Block" : "Timer context")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MetridayTheme.secondary)
                    Text(snapshot.hasTask ? snapshot.taskTitle : snapshot.projectPath)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MetridayTheme.graphite)
                        .lineLimit(1)
                    Text(snapshot.hasTask
                         ? "\(snapshot.projectPath) · \(snapshot.plannedRange)"
                         : snapshot.plannedRange)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MetridayTheme.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MetridayTheme.secondary)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(!snapshot.hasTask)
        .accessibilityLabel(snapshot.hasTask ? "Open current Block \(snapshot.taskTitle)" : "Timer context")
        .accessibilityIdentifier("focus-companion.current-block")
        .padding(.vertical, 9)
    }

    private func timerSummary(snapshot: FocusCompanionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.statusLabel)
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(snapshot.isOverdue ? MetridayTheme.danger : MetridayTheme.graphite)
                    Text(snapshot.detailLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MetridayTheme.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(snapshot.plannedLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MetridayTheme.secondary)
                    Text(snapshot.actualLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(snapshot.execution.isRunning ? MetridayTheme.accentDeep : MetridayTheme.secondary)
                    blocklistBadge(snapshot.blocklist)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.07))
                    Capsule()
                        .fill(snapshot.isOverdue ? MetridayTheme.danger : MetridayTheme.accent)
                        .frame(width: proxy.size.width * snapshot.progress)
                }
            }
            .frame(height: 5)
        }
        .padding(.bottom, 10)
    }

    private func blocklistBadge(_ state: FocusCompanionBlocklistState) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(state.color)
                .frame(width: 6, height: 6)
            Text(state.title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(state.color)
        }
        .help(state.detail)
        .accessibilityLabel("Blocklist \(state.title). \(state.detail)")
        .accessibilityIdentifier("focus-companion.blocklist")
    }

    private func activityBreakdown(snapshot: FocusCompanionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Activity breakdown")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)
                Spacer()
                Text(snapshot.quality.hasActivity ? "\(snapshot.qualityPercentage)% focused" : "No evidence yet")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MetridayTheme.secondary)
            }

            qualityBar(snapshot.quality)

            HStack(spacing: 8) {
                qualityMetric("Focused", seconds: snapshot.quality.focusedSeconds, color: MetridayTheme.accentDeep, total: snapshot.qualityTotalSeconds)
                qualityMetric("Distracting", seconds: snapshot.quality.distractedSeconds, color: MetridayTheme.danger, total: snapshot.qualityTotalSeconds)
                qualityMetric("Other", seconds: snapshot.quality.otherSeconds, color: MetridayTheme.secondary, total: snapshot.qualityTotalSeconds)
                qualityMetric("Idle", seconds: snapshot.quality.idleSeconds, color: MetridayTheme.line, total: snapshot.qualityTotalSeconds)
            }
        }
        .padding(.bottom, 10)
    }

    private func qualityBar(_ quality: TimeBlockActivityQuality) -> some View {
        let total = max(1, quality.focusedSeconds + quality.distractedSeconds + quality.otherSeconds + quality.idleSeconds)
        return GeometryReader { proxy in
            HStack(spacing: 1) {
                qualitySegment(quality.focusedSeconds, total: total, width: proxy.size.width, color: MetridayTheme.accentDeep)
                qualitySegment(quality.distractedSeconds, total: total, width: proxy.size.width, color: MetridayTheme.danger)
                qualitySegment(quality.otherSeconds, total: total, width: proxy.size.width, color: MetridayTheme.secondary)
                qualitySegment(quality.idleSeconds, total: total, width: proxy.size.width, color: MetridayTheme.line)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 7)
        .background(MetridayTheme.line.opacity(0.25))
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity breakdown: \(percentage(quality.focusedSeconds, of: total)) percent focused, \(percentage(quality.distractedSeconds, of: total)) percent distracting, \(percentage(quality.otherSeconds, of: total)) percent other, \(percentage(quality.idleSeconds, of: total)) percent idle")
    }

    private func qualitySegment(_ seconds: Int, total: Int, width: CGFloat, color: Color) -> some View {
        color
            .frame(width: max(0, width * CGFloat(seconds) / CGFloat(total)))
            .opacity(seconds > 0 ? 1 : 0)
    }

    private func qualityMetric(_ title: String, seconds: Int, color: Color, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)
            }
            Text("\(percentage(seconds, of: total))% · \(durationLabel(seconds))")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(MetridayTheme.graphite)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(percentage(seconds, of: total)) percent, \(durationLabel(seconds))")
    }

    private func footer(timer: RunningTimer?, snapshot: FocusCompanionSnapshot) -> some View {
        HStack(spacing: 7) {
            if snapshot.isFocus && !snapshot.isPaused {
                Button {
                    _ = appState.pauseFocusSession()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("focus-companion.pause")

                Button {
                    _ = appState.stopFocusSession()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("focus-companion.stop")
            } else if snapshot.isFocus && snapshot.isPaused {
                Button {
                    _ = appState.resumeFocusSession()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("focus-companion.resume")

                Button {
                    _ = appState.stopFocusSession()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("focus-companion.stop")
            } else if timer != nil {
                Button {
                    _ = appState.stopTimer()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("focus-companion.stop")
            } else {
                Button {
                    _ = appState.resumeFocusSession()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appState.focusIsPaused)
                .accessibilityIdentifier("focus-companion.resume")
            }

            Button(snapshot.hasTask ? "Open Block" : "Open") {
                if snapshot.hasTask {
                    appState.openCurrentFocusBlock()
                } else {
                    appState.section = .activities
                    activateMainWindow()
                }
                appState.hideFocusCompanion()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("focus-companion.open")

            Spacer(minLength: 0)

            Menu {
                Button("Open Metriday") {
                    activateMainWindow()
                    appState.hideFocusCompanion()
                }
                Button("Open Rules") {
                    appState.section = .rules
                    activateMainWindow()
                    appState.hideFocusCompanion()
                }
                if snapshot.hasTask {
                    Button("Open current Block") {
                        appState.openCurrentFocusBlock()
                        appState.hideFocusCompanion()
                    }
                }
                Divider()
                Button("Hide Companion") {
                    appState.hideFocusCompanion()
                }
                if snapshot.isFocus && !snapshot.isPaused {
                    Button("Pause Focus") {
                        _ = appState.pauseFocusSession()
                    }
                    Button("Stop Focus", role: .destructive) {
                        _ = appState.stopFocusSession()
                    }
                } else if snapshot.isFocus && snapshot.isPaused {
                    Button("Resume Focus") {
                        _ = appState.resumeFocusSession()
                    }
                    Button("Stop Focus", role: .destructive) {
                        _ = appState.stopFocusSession()
                    }
                } else if timer != nil {
                    Button("Stop Timer", role: .destructive) {
                        _ = appState.stopTimer()
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .help("Companion actions")
            .accessibilityLabel("Companion actions")
            .accessibilityIdentifier("focus-companion.actions")
        }
        .padding(.top, 10)
    }

    private func snapshot(
        for timer: RunningTimer?,
        now: Date,
        metrics: FocusCompanionMetrics
    ) -> FocusCompanionSnapshot {
        let isFocus = timer?.customFields["metriday_focus_session"] == "true" || appState.focusIsPaused
        let taskID = timer?.customFields["metriday_plan_task_id"].flatMap(UUID.init(uuidString:))
            ?? appState.pausedFocusTaskID
        let taskDate = timer?.customFields["metriday_plan_date"].flatMap(dayDate(from:))
            ?? appState.pausedFocusDate
            ?? appState.selectedDate
        let task = taskID.flatMap { appState.markdownStore.task($0, on: taskDate) }
        let timerTitle = timer?.title ?? task?.title ?? (isFocus ? "Focus Session" : "No active timer")
        let plannedSeconds = task.map { $0.duration * 60 } ?? timer?.estimatedDurationSeconds
        let currentRunSeconds = timer.map { max(0, Int(now.timeIntervalSince($0.startedAt))) } ?? 0
        let isLinkedRunning = timer != nil && taskID != nil
        let actualSeconds = metrics.execution.durationSeconds + (isLinkedRunning ? currentRunSeconds : 0)
        let intervalCount = metrics.execution.intervalCount + (isLinkedRunning ? 1 : 0)
        let actualExecution = TimeBlockExecutionSummary(
            durationSeconds: actualSeconds,
            intervalCount: intervalCount,
            isRunning: isLinkedRunning
        )
        let remainingSeconds: Int?
        if isFocus, task != nil {
            remainingSeconds = plannedSeconds.map { $0 - actualSeconds }
        } else {
            remainingSeconds = plannedSeconds.map { $0 - currentRunSeconds }
        }
        let isOverdue = remainingSeconds.map { $0 < 0 } ?? false
        let progress = plannedSeconds.map {
            min(1, max(0, Double(isFocus && task != nil ? actualSeconds : currentRunSeconds) / Double(max(1, $0))))
        } ?? 0
        let plannedRange = task?.timeRange ?? "Open-ended"
        let actualLabel = actualExecution.hasExecution ? "Actual \(actualExecution.durationLabel)" : "No actual time"
        let detailLabel: String
        if isFocus && appState.focusIsPaused {
            detailLabel = "Paused · \(actualExecution.intervalCount) interval\(actualExecution.intervalCount == 1 ? "" : "s")"
        } else if isFocus && task != nil {
            detailLabel = task?.timeRange ?? "Running now"
        } else {
            detailLabel = "Running now"
        }
        return FocusCompanionSnapshot(
            timerTitle: timerTitle,
            taskTitle: task?.title ?? timerTitle,
            projectPath: projectStore.hierarchyPath(for: timer?.projectID),
            plannedRange: plannedRange,
            statusLabel: statusLabel(remainingSeconds: remainingSeconds, elapsedSeconds: currentRunSeconds, isPaused: appState.focusIsPaused),
            detailLabel: detailLabel,
            plannedLabel: plannedSeconds.map { "Planned \(durationLabel($0))" } ?? "Open-ended",
            actualLabel: actualLabel,
            progress: progress,
            isOverdue: isOverdue,
            isFocus: isFocus,
            isPaused: appState.focusIsPaused,
            hasTask: task != nil,
            quality: metrics.quality,
            execution: actualExecution,
            blocklist: blocklistState()
        )
    }

    private func refreshMetrics() {
        let timer = timeEntryStore.runningTimer
        let taskID = timer?.customFields["metriday_plan_task_id"].flatMap(UUID.init(uuidString:))
            ?? appState.pausedFocusTaskID
        let taskDate = timer?.customFields["metriday_plan_date"].flatMap(dayDate(from:))
            ?? appState.pausedFocusDate
            ?? appState.selectedDate
        let task = taskID.flatMap { appState.markdownStore.task($0, on: taskDate) }
        let quality = task.map { activityQuality(for: $0, date: taskDate) } ?? .empty
        let execution = task.map {
            timeBlockExecutionSummary(
                taskID: $0.id,
                entries: timeEntryStore.entries,
                runningTimer: nil,
                date: taskDate
            )
        } ?? .empty
        metrics = FocusCompanionMetrics(quality: quality, execution: execution)
    }

    private func activityQuality(for task: PlanTask, date: Date) -> TimeBlockActivityQuality {
        guard let start = task.startMinute, let end = task.endMinute else {
            return .empty
        }
        let segments = appState.categoryStore.applyingCategories(
            to: appState.activityMonitor.segments(for: date)
                + appState.screenTimeStore.segments(for: date),
            filterStore: appState.filterStore,
            date: date
        )
        return timeBlockActivityQuality(
            segments: segments,
            plannedStartSecond: start * 60,
            plannedEndSecond: end * 60
        )
    }

    private func blocklistState() -> FocusCompanionBlocklistState {
        let status = blocker.status.lowercased()
        if status.contains("permission") || status.contains("automation") {
            return .permissionRequired(blocker.status)
        }
        if let domain = blocker.lastBlockedDomain, blocker.isActive {
            return .blocked(domain)
        }
        return blocker.isActive ? .active : .ready
    }

    private func statusLabel(remainingSeconds: Int?, elapsedSeconds: Int, isPaused: Bool) -> String {
        if isPaused { return "Paused" }
        guard let remainingSeconds else { return durationLabel(elapsedSeconds) }
        if remainingSeconds < 0 {
            return "Over by \(durationLabel(-remainingSeconds))"
        }
        return durationLabel(remainingSeconds)
    }

    private func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeKey && !$0.isKind(of: NSPanel.self) })?.makeKeyAndOrderFront(nil)
    }

    private func dayDate(from rawValue: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rawValue)
    }

    private func percentage(_ value: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(value) / Double(total) * 100).rounded())
    }

    private func durationLabel(_ seconds: Int) -> String {
        let absolute = max(0, seconds)
        let hours = absolute / 3_600
        let minutes = (absolute % 3_600) / 60
        let remainder = absolute % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }
}

private struct FocusCompanionMetrics {
    let quality: TimeBlockActivityQuality
    let execution: TimeBlockExecutionSummary

    static let empty = FocusCompanionMetrics(quality: .empty, execution: .empty)
}

private struct FocusCompanionSnapshot {
    let timerTitle: String
    let taskTitle: String
    let projectPath: String
    let plannedRange: String
    let statusLabel: String
    let detailLabel: String
    let plannedLabel: String
    let actualLabel: String
    let progress: Double
    let isOverdue: Bool
    let isFocus: Bool
    let isPaused: Bool
    let hasTask: Bool
    let quality: TimeBlockActivityQuality
    let execution: TimeBlockExecutionSummary
    let blocklist: FocusCompanionBlocklistState

    var qualityTotalSeconds: Int {
        quality.focusedSeconds + quality.distractedSeconds + quality.otherSeconds + quality.idleSeconds
    }

    var qualityPercentage: Int {
        guard qualityTotalSeconds > 0 else { return 0 }
        return Int((Double(quality.focusedSeconds) / Double(qualityTotalSeconds) * 100).rounded())
    }
}

private enum FocusCompanionBlocklistState: Hashable {
    case ready
    case active
    case blocked(String)
    case permissionRequired(String)

    var title: String {
        switch self {
        case .ready: return "Ready"
        case .active: return "Active"
        case .blocked(let domain): return "Blocked · \(domain)"
        case .permissionRequired: return "Permission needed"
        }
    }

    var detail: String {
        switch self {
        case .ready: return "Focus protection is ready to start"
        case .active: return "Safari and Chrome are being monitored"
        case .blocked(let domain): return "\(domain) was redirected by the active blocklist"
        case .permissionRequired(let status): return status
        }
    }

    var color: Color {
        switch self {
        case .ready: return MetridayTheme.secondary
        case .active: return MetridayTheme.success
        case .blocked: return MetridayTheme.danger
        case .permissionRequired: return MetridayTheme.warning
        }
    }
}

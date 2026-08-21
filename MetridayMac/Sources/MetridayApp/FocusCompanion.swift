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
                contentRect: NSRect(x: 0, y: 0, width: 372, height: 248),
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
            panel.minSize = NSSize(width: 340, height: 228)
            panel.maxSize = NSSize(width: 460, height: 330)
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
    @State private var metrics = FocusCompanionMetrics.empty

    private static let metricsClock = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    init(appState: AppState) {
        self.appState = appState
        self._timeEntryStore = ObservedObject(wrappedValue: appState.timeEntryStore)
    }

    var body: some View {
        TimelineView(.periodic(from: MetridayTimeline.anchor, by: 1)) { context in
            let timer = timeEntryStore.runningTimer
            let isFocus = timer?.customFields["metriday_focus_session"] == "true"
            let snapshot = snapshot(for: timer, now: context.date, metrics: metrics)

            VStack(alignment: .leading, spacing: 0) {
                header(isFocus: isFocus, timer: timer)
                Divider().opacity(0.7)
                timerSummary(snapshot: snapshot)
                Divider().opacity(0.7)
                breakdown(snapshot: snapshot)
                Divider().opacity(0.7)
                footer(timer: timer, isFocus: isFocus)
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
        .frame(minWidth: 340, minHeight: 228)
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

    private func header(isFocus: Bool, timer: RunningTimer?) -> some View {
        HStack(spacing: 9) {
            Image(systemName: isFocus ? "target" : "timer")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isFocus ? MetridayTheme.accentDeep : MetridayTheme.secondary)
                .frame(width: 24, height: 24)
                .background((isFocus ? MetridayTheme.accent : MetridayTheme.line).opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(isFocus ? "Focus Session" : timer == nil ? "Focus Companion" : "Timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)
                Text(timer?.title ?? "No active timer")
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
        }
        .padding(.bottom, 12)
    }

    private func timerSummary(snapshot: FocusCompanionSnapshot) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(snapshot.statusLabel)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(snapshot.isOverdue ? MetridayTheme.danger : MetridayTheme.graphite)
                Text(snapshot.detailLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MetridayTheme.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(snapshot.plannedLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MetridayTheme.secondary)
                HStack(spacing: 5) {
                    Circle()
                        .fill(appState.focusIsActive ? MetridayTheme.success : MetridayTheme.secondary)
                        .frame(width: 7, height: 7)
                    Text(appState.focusIsActive ? "Blocklist active" : "Blocklist ready")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(appState.focusIsActive ? MetridayTheme.success : MetridayTheme.secondary)
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.black.opacity(0.07))
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(snapshot.isOverdue ? MetridayTheme.danger : MetridayTheme.accent)
                            .frame(width: proxy.size.width * snapshot.progress, height: 4)
                    }
            }
            .frame(height: 4)
        }
    }

    private func breakdown(snapshot: FocusCompanionSnapshot) -> some View {
        HStack(spacing: 8) {
            breakdownItem("Focused", seconds: snapshot.quality.focusedSeconds, color: MetridayTheme.accentDeep)
            breakdownItem("Distracting", seconds: snapshot.quality.distractedSeconds, color: MetridayTheme.danger)
            breakdownItem("Other", seconds: snapshot.quality.otherSeconds + snapshot.quality.idleSeconds, color: MetridayTheme.secondary)
        }
        .padding(.vertical, 11)
    }

    private func breakdownItem(_ title: String, seconds: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)
            }
            Text(durationLabel(seconds))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(MetridayTheme.graphite)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func footer(timer: RunningTimer?, isFocus: Bool) -> some View {
        HStack(spacing: 8) {
            Button {
                if isFocus {
                    _ = appState.toggleFocusSession()
                } else if timer != nil {
                    _ = appState.stopTimer()
                }
            } label: {
                Label(isFocus ? "Pause" : "Stop", systemImage: isFocus ? "pause.fill" : "stop.fill")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(timer == nil)

            Button("Open") {
                if let taskID = timer?.customFields["metriday_plan_task_id"].flatMap(UUID.init(uuidString:)) {
                    appState.selectedTaskID = taskID
                    appState.section = .plan
                } else {
                    appState.section = .activities
                }
                appState.hideFocusCompanion()
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)

            Menu {
                Button("Open Metriday") {
                    NSApp.activate(ignoringOtherApps: true)
                    appState.hideFocusCompanion()
                }
                Button("Open Plan") {
                    appState.section = .plan
                    appState.hideFocusCompanion()
                }
                Divider()
                Button("Hide Companion") {
                    appState.hideFocusCompanion()
                }
                if timer != nil {
                    Button(isFocus ? "Stop Focus" : "Stop Timer", role: .destructive) {
                        if isFocus { _ = appState.stopFocusSession() } else { _ = appState.stopTimer() }
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
        }
        .padding(.top, 11)
    }

    private func snapshot(
        for timer: RunningTimer?,
        now: Date,
        metrics: FocusCompanionMetrics
    ) -> FocusCompanionSnapshot {
        guard let timer else {
            return .empty
        }

        let taskID = timer.customFields["metriday_plan_task_id"].flatMap(UUID.init(uuidString:))
        let task = taskID.flatMap { appState.markdownStore.task($0) }
        let plannedSeconds = task.map { $0.duration * 60 } ?? timer.estimatedDurationSeconds
        let elapsedSeconds = max(0, Int(now.timeIntervalSince(timer.startedAt)))
        let remainingSeconds = plannedSeconds.map { $0 - elapsedSeconds }
        let isOverdue = remainingSeconds.map { $0 < 0 } ?? false
        return FocusCompanionSnapshot(
            statusLabel: statusLabel(remainingSeconds: remainingSeconds, elapsedSeconds: elapsedSeconds),
            detailLabel: task?.timeRange ?? "Running now",
            plannedLabel: plannedSeconds.map { "Planned \(durationLabel($0))" } ?? "Open-ended",
            progress: plannedSeconds.map { min(1, max(0, Double(elapsedSeconds) / Double(max(1, $0)))) } ?? 0,
            isOverdue: isOverdue,
            quality: metrics.quality,
            execution: metrics.execution
        )
    }

    private func refreshMetrics() {
        guard let timer = timeEntryStore.runningTimer else {
            metrics = .empty
            return
        }
        let taskID = timer.customFields["metriday_plan_task_id"].flatMap(UUID.init(uuidString:))
        let task = taskID.flatMap { appState.markdownStore.task($0) }
        let quality: TimeBlockActivityQuality
        if let task {
            quality = activityQuality(for: task)
        } else {
            quality = .empty
        }
        let execution = task.map {
            timeBlockExecutionSummary(
                taskID: $0.id,
                entries: timeEntryStore.materializedEntries(),
                runningTimer: timer,
                date: appState.selectedDate
            )
        } ?? .empty
        metrics = FocusCompanionMetrics(quality: quality, execution: execution)
    }

    private func activityQuality(for task: PlanTask) -> TimeBlockActivityQuality {
        guard let start = task.startMinute, let end = task.endMinute else {
            return .empty
        }
        let segments = appState.categoryStore.applyingCategories(
            to: appState.activityMonitor.segments(for: appState.selectedDate)
                + appState.screenTimeStore.segments(for: appState.selectedDate),
            filterStore: appState.filterStore,
            date: appState.selectedDate
        )
        return timeBlockActivityQuality(
            segments: segments,
            plannedStartSecond: start * 60,
            plannedEndSecond: end * 60
        )
    }

    private func statusLabel(remainingSeconds: Int?, elapsedSeconds: Int) -> String {
        guard let remainingSeconds else { return durationLabel(elapsedSeconds) }
        if remainingSeconds < 0 {
            return "Over by \(durationLabel(-remainingSeconds))"
        }
        return durationLabel(remainingSeconds)
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
    let statusLabel: String
    let detailLabel: String
    let plannedLabel: String
    let progress: Double
    let isOverdue: Bool
    let quality: TimeBlockActivityQuality
    let execution: TimeBlockExecutionSummary

    static let empty = FocusCompanionSnapshot(
        statusLabel: "No timer",
        detailLabel: "Start a Timer or Focus Session from Metriday",
        plannedLabel: "",
        progress: 0,
        isOverdue: false,
        quality: .empty,
        execution: .empty
    )
}

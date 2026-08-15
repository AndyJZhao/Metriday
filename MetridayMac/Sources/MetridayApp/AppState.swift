import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var section: AppSection = .today
    @Published private(set) var selectedDate: Date
    @Published var focusIsActive = false {
        didSet { blocker.isActive = focusIsActive }
    }
    @Published var selectedTaskID: UUID?
    @Published var draggingTaskID: UUID?
    @Published var dragLocation: CGPoint = .zero
    @Published var calendarTimelineFrame: CGRect = .zero
    @Published var calendarTimelineScreenFrame: CGRect = .zero
    @Published var timelineDropIntent: TimelineDropIntent = .choose
    @Published var pendingTimelineDrop: PendingTimelineDrop?

    let markdownStore: MarkdownStore
    let activityMonitor: AppActivityMonitor
    let blocker: WebBlockerService

    init() {
        let initialDate = Calendar.current.startOfDay(for: .now)
        self.selectedDate = initialDate
        self.markdownStore = MarkdownStore(date: initialDate)
        self.activityMonitor = AppActivityMonitor()
        self.blocker = WebBlockerService()
        self.activityMonitor.start()
    }

    var currentTask: PlanTask? {
        if let selectedTaskID, let selected = markdownStore.task(selectedTaskID), selected.startMinute != nil {
            return selected
        }

        let scheduled = markdownStore.tasks
            .filter { $0.startMinute != nil && $0.endMinute != nil }
            .sorted { ($0.startMinute ?? 0) < ($1.startMinute ?? 0) }

        if Calendar.current.isDateInToday(selectedDate) {
            let components = Calendar.current.dateComponents([.hour, .minute], from: .now)
            let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            if let active = scheduled.first(where: {
                guard let start = $0.startMinute, let end = $0.endMinute else { return false }
                return start <= minute && minute < end
            }) {
                return active
            }
        }
        return scheduled.first
    }

    func selectDate(_ date: Date) {
        let normalized = Calendar.current.startOfDay(for: date)
        guard !Calendar.current.isDate(normalized, inSameDayAs: selectedDate) else { return }
        selectedDate = normalized
        selectedTaskID = nil
        pendingTimelineDrop = nil
        draggingTaskID = nil
        _ = markdownStore.load(date: normalized)
    }

    func goToToday() {
        selectDate(.now)
    }

    func moveSelectedDate(byDays offset: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) else { return }
        selectDate(date)
    }

    func receiveTimelineDrop(taskID: UUID, start: Int, end: Int, intent: TimelineDropIntent) {
        let drop = PendingTimelineDrop(taskID: taskID, startMinute: start, endMinute: end, intent: intent)
        if intent == .timeBlock {
            addTimeBlock(drop)
        } else {
            pendingTimelineDrop = drop
            markdownStore.statusMessage = intent == .event
                ? "Event creation comes next · choose Time Block for now"
                : "Choose Time Block or Event"
        }
    }

    func confirmPendingTimeBlock() {
        guard let pendingTimelineDrop else { return }
        addTimeBlock(pendingTimelineDrop)
    }

    func cancelPendingTimelineDrop() {
        pendingTimelineDrop = nil
        markdownStore.statusMessage = "Drop cancelled"
    }

    private func addTimeBlock(_ drop: PendingTimelineDrop) {
        markdownStore.schedule(
            id: drop.taskID,
            start: drop.startMinute,
            end: drop.endMinute,
            message: "Time Block added · \(TimeFormat.range(start: drop.startMinute, end: drop.endMinute))"
        )
        selectedTaskID = drop.taskID
        pendingTimelineDrop = nil
    }
}

@MainActor
final class AppActivityMonitor: ObservableObject {
    @Published private(set) var currentApplication = "Metriday"
    @Published private(set) var observedSegments: [ActivitySegment] = []

    private var timer: Timer?
    private var currentBundleIdentifier = ""
    private var currentStart = Date()

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let bundleID = app.bundleIdentifier ?? "unknown"
        let name = app.localizedName ?? "Unknown"
        currentApplication = name

        guard bundleID != currentBundleIdentifier else { return }
        closeCurrentSegment(at: Date())
        currentBundleIdentifier = bundleID
        currentStart = Date()
    }

    private func closeCurrentSegment(at end: Date) {
        guard !currentBundleIdentifier.isEmpty else { return }
        let calendar = Calendar.current
        let startMinute = calendar.component(.hour, from: currentStart) * 60 + calendar.component(.minute, from: currentStart)
        let endMinute = max(startMinute + 1, calendar.component(.hour, from: end) * 60 + calendar.component(.minute, from: end))
        let relatedIDs = ["com.microsoft.VSCode", "com.apple.dt.Xcode", "com.apple.Terminal", "com.googlecode.iterm2", "md.obsidian"]
        let distractedIDs = ["com.google.Chrome", "com.apple.Safari"]
        let relevance: ActivityRelevance = relatedIDs.contains(currentBundleIdentifier) ? .related : (distractedIDs.contains(currentBundleIdentifier) ? .distracted : .idle)
        observedSegments.append(ActivitySegment(appName: currentApplication, bundleIdentifier: currentBundleIdentifier, startMinute: startMinute, endMinute: endMinute, relevance: relevance))
    }
}

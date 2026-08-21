import AppKit
import Combine
import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    MarkdownEditorPane(store: appState.markdownStore)
                        .frame(width: max(540, proxy.size.width * 0.66))
                    Divider()
                    PlanCalendarPane(store: appState.markdownStore)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background(.white)
        .clipped()
        .coordinateSpace(name: "planRoot")
        .overlay(alignment: .bottom) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(MetridayTheme.success)
                Text(appState.markdownStore.statusMessage)
                Spacer(minLength: 10)
                Text(appState.markdownStore.fileURL.lastPathComponent)
                    .foregroundStyle(MetridayTheme.secondary)
                Image(systemName: "xmark")
                    .foregroundStyle(MetridayTheme.secondary)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 15)
            .frame(width: 430, height: 48)
            .metridayPanel(radius: 10)
            .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
            .padding(.bottom, 22)
        }
    }
}

struct MarkdownEditorPane: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: MarkdownStore
    @State private var newTaskTitle = ""
    @State private var draftTaskID = UUID()
    @FocusState private var draftIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(store.fileURL.lastPathComponent, systemImage: "doc.text")
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(MetridayTheme.secondary)
                Spacer()
                Menu {
                    Button("Reveal in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                    }
                    Button("Copy Markdown", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.markdown, forType: .string)
                        store.statusMessage = "Markdown copied"
                    }
                    Divider()
                    Button("Reload from disk", systemImage: "arrow.clockwise") {
                        _ = store.load(date: appState.selectedDate, createIfMissing: false)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Plan actions")
                .accessibilityIdentifier("plan.actions")
            }
            .padding(.horizontal, 20)
            .frame(height: 50)
            .background(MetridayTheme.canvas)

            Divider()
            lineEditor
            Divider()

            HStack(spacing: 18) {
                Text("\(store.lineCount) lines")
                Spacer()
                Text("UTF-8")
                Text("Markdown")
                Text("Local file")
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(MetridayTheme.success)
            }
            .font(.system(size: 10))
            .foregroundStyle(MetridayTheme.secondary)
            .padding(.horizontal, 18)
            .frame(height: 34)
        }
        .background(.white)
        .clipped()
    }

    private var lineEditor: some View {
        NativeMarkdownEditor(
            text: store.markdown,
            taskLineIDs: store.taskLineIDs,
            taskTitles: Dictionary(uniqueKeysWithValues: store.tasks.map { ($0.id, $0.title) }),
            selectedTaskID: appState.selectedTaskID,
            onTextChange: { store.updateRawMarkdown($0) },
            onSelectTask: { appState.selectedTaskID = $0 },
            onToggleTask: { store.toggleCompleted(id: $0) },
            onDragStateChange: { id, isDragging in
                appState.draggingTaskID = isDragging ? id : nil
                if !isDragging {
                    appState.dragLocation = .zero
                    appState.timelineDropIntent = .choose
                }
            },
            onDragEnded: { id, screenPoint, flags in
                let frame = appState.calendarTimelineScreenFrame
                guard frame.contains(screenPoint) else { return }
                let yFromTop = frame.maxY - screenPoint.y
                let minute = TimelineMetrics.startMinute + Int((yFromTop / TimelineMetrics.hourHeight) * 60)
                let start = Int((Double(minute) / 15).rounded()) * 15
                let duration = store.task(id)?.duration ?? 60
                let intent: TimelineDropIntent = flags.contains(.command)
                    ? .timeBlock
                    : (flags.contains(.option) ? .event : .choose)
                appState.receiveTimelineDrop(
                    taskID: id,
                    start: start,
                    end: start + duration,
                    intent: intent
                )
            }
        )
        .clipped()
    }

    private var legacyLineEditor: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                MarkdownStaticLine(number: 1) {
                    Text("#").foregroundStyle(MetridayTheme.accent)
                    Text("Saturday, August 15, 2026").fontWeight(.bold)
                }
                MarkdownStaticLine(number: 2) {
                    Text(">").foregroundStyle(MetridayTheme.accent)
                    Text(store.quote).italic().foregroundStyle(MetridayTheme.secondary)
                }
                MarkdownStaticLine(number: 3) { EmptyView() }
                MarkdownStaticLine(number: 4) {
                    Text("##").foregroundStyle(MetridayTheme.accent)
                    Text("Focus").fontWeight(.bold)
                }

                ForEach(Array(store.tasks.enumerated()), id: \.element.id) { index, task in
                    MarkdownTaskRow(
                        store: store,
                        task: task,
                        lineNumber: 5 + index,
                        onCreateNextLine: focusDraftLine
                    )
                }

                draftTaskRow(lineNumber: 5 + store.tasks.count)

                MarkdownStaticLine(number: 6 + store.tasks.count) { EmptyView() }
                MarkdownStaticLine(number: 7 + store.tasks.count) {
                    Text("##").foregroundStyle(MetridayTheme.accent)
                    Text("Notes").fontWeight(.bold)
                }
                ForEach(Array(store.notes.enumerated()), id: \.offset) { index, note in
                    MarkdownStaticLine(number: 8 + store.tasks.count + index) {
                        Text("-")
                        Text(note)
                    }
                }

                Color.clear
                    .frame(height: 160)
                    .contentShape(Rectangle())
                    .onTapGesture { focusDraftLine() }
            }
            .padding(.vertical, 18)
        }
    }

    private func draftTaskRow(lineNumber: Int) -> some View {
        HStack(spacing: 7) {
            Text("\(lineNumber)")
                .foregroundStyle(MetridayTheme.secondary.opacity(0.65))
                .frame(width: 30, alignment: .trailing)

            SixDotDragHandle(isActive: appState.draggingTaskID == draftTaskID)
                .frame(width: 30, height: 34)
                .contentShape(Rectangle())
                .opacity(newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.28 : 1)
                .draggable(draftTaskID.uuidString) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.badge.plus")
                            .foregroundStyle(MetridayTheme.accent)
                        Text(newTaskTitle.isEmpty ? "New task" : newTaskTitle)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(width: 220, height: 38, alignment: .leading)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

            Text("- [")
                .foregroundStyle(MetridayTheme.secondary)
            RoundedRectangle(cornerRadius: 2)
                .stroke(MetridayTheme.secondary, lineWidth: 1)
                .frame(width: 12, height: 12)
            Text("]")
                .foregroundStyle(MetridayTheme.secondary)

            TextField("Type a task, then press Return…", text: $newTaskTitle)
                .textFieldStyle(.plain)
                .focused($draftIsFocused)
                .onSubmit { commitDraftTask() }
                .onKeyPress(.return) {
                    commitDraftTask()
                    return .handled
                }

            Spacer(minLength: 4)
        }
        .font(.system(size: 13, design: .monospaced))
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 52)
        .background(draftIsFocused ? MetridayTheme.accentSoft.opacity(0.52) : .clear)
        .contentShape(Rectangle())
        .simultaneousGesture(draftTaskDragGesture)
        .onTapGesture { draftIsFocused = true }
    }

    private var draftTaskDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("planRoot"))
            .onChanged { value in
                guard ensureDraftTaskCommitted() != nil else { return }
                appState.selectedTaskID = draftTaskID
                appState.draggingTaskID = draftTaskID
                appState.dragLocation = value.location
                appState.timelineDropIntent = currentDropIntent
            }
            .onEnded { value in
                guard store.task(draftTaskID) != nil else { return }
                let frame = appState.calendarTimelineFrame
                if frame.contains(value.location) {
                    let y = value.location.y - frame.minY
                    let minute = TimelineMetrics.startMinute + Int((y / TimelineMetrics.hourHeight) * 60)
                    let start = Int((Double(minute) / 15).rounded()) * 15
                    appState.receiveTimelineDrop(
                        taskID: draftTaskID,
                        start: start,
                        end: start + 60,
                        intent: currentDropIntent
                    )
                }
                resetDraftLine()
                appState.draggingTaskID = nil
                appState.dragLocation = .zero
                appState.timelineDropIntent = .choose
            }
    }

    @discardableResult
    private func ensureDraftTaskCommitted() -> UUID? {
        if store.task(draftTaskID) != nil { return draftTaskID }
        return store.addTask(title: newTaskTitle, id: draftTaskID)
    }

    private func commitDraftTask() {
        guard ensureDraftTaskCommitted() != nil else {
            draftIsFocused = true
            return
        }
        resetDraftLine()
        focusDraftLine()
    }

    private func resetDraftLine() {
        newTaskTitle = ""
        draftTaskID = UUID()
    }

    private func focusDraftLine() {
        Task { @MainActor in draftIsFocused = true }
    }

    private var currentDropIntent: TimelineDropIntent {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) { return .timeBlock }
        if flags.contains(.option) { return .event }
        return .choose
    }
}

struct MarkdownStaticLine<Content: View>: View {
    let number: Int
    @ViewBuilder let content: Content

    init(number: Int, @ViewBuilder content: () -> Content) {
        self.number = number
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .foregroundStyle(MetridayTheme.secondary.opacity(0.65))
                .frame(width: 30, alignment: .trailing)
            content
        }
        .font(.system(size: 13, design: .monospaced))
        .padding(.horizontal, 18)
        .frame(height: 48)
    }
}

struct MarkdownTaskRow: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: MarkdownStore
    let task: PlanTask
    let lineNumber: Int
    let onCreateNextLine: () -> Void
    @State private var timeText = ""

    var body: some View {
        HStack(spacing: 7) {
            Text("\(lineNumber)")
                .foregroundStyle(MetridayTheme.secondary.opacity(0.65))
                .frame(width: 30, alignment: .trailing)

            SixDotDragHandle(isActive: appState.draggingTaskID == task.id)
            .frame(width: 30, height: 34)
            .contentShape(Rectangle())
            .draggable(task.id.uuidString) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundStyle(MetridayTheme.accent)
                    Text(task.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .frame(width: 220, height: 38, alignment: .leading)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .help("Drag this task to the timeline")
            .accessibilityLabel("Drag \(task.title) to timeline")

            Text("- [")
                .foregroundStyle(MetridayTheme.secondary)
            Button {
                store.toggleCompleted(id: task.id)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 2).stroke(MetridayTheme.secondary, lineWidth: 1)
                    if task.isCompleted { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)) }
                }
                .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            Text("]")
                .foregroundStyle(MetridayTheme.secondary)

            if task.startMinute != nil {
                TextField("time", text: $timeText)
                    .textFieldStyle(.plain)
                    .frame(width: 108)
                    .foregroundStyle(MetridayTheme.graphite)
                    .onSubmit { commitTime() }
            }

            TextField("Task title", text: Binding(
                get: { task.title },
                set: { store.updateTitle(id: task.id, title: $0) }
            ))
            .textFieldStyle(.plain)
            .strikethrough(task.isCompleted)
            .foregroundStyle(task.isCompleted ? MetridayTheme.secondary : MetridayTheme.graphite)
            .onSubmit { onCreateNextLine() }
            .onKeyPress(.return) {
                onCreateNextLine()
                return .handled
            }

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                ForEach(task.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .foregroundStyle(MetridayTheme.accent)
                }
            }

            if store.lastUpdatedTaskID == task.id {
                Label("Time Block", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MetridayTheme.success)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(MetridayTheme.successSoft)
                    .clipShape(Capsule())
            }
        }
        .font(.system(size: 13, design: .monospaced))
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 52)
        .background(store.lastUpdatedTaskID == task.id ? MetridayTheme.accentSoft : .clear)
        .contentShape(Rectangle())
        .simultaneousGesture(taskDragGesture)
        .onTapGesture { appState.selectedTaskID = task.id }
        .onChange(of: task.timeRange, initial: true) { _, newValue in
            timeText = newValue ?? ""
        }
    }

    private func commitTime() {
        if !store.applyTimeText(id: task.id, value: timeText) {
            timeText = task.timeRange ?? ""
        }
    }

    private var taskDragGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("planRoot"))
            .onChanged { value in
                appState.selectedTaskID = task.id
                appState.draggingTaskID = task.id
                appState.dragLocation = value.location
                appState.timelineDropIntent = currentDropIntent
            }
            .onEnded { value in
                let frame = appState.calendarTimelineFrame
                if frame.contains(value.location) {
                    let y = value.location.y - frame.minY
                    let minute = TimelineMetrics.startMinute + Int((y / TimelineMetrics.hourHeight) * 60)
                    let start = Int((Double(minute) / 15).rounded()) * 15
                    appState.receiveTimelineDrop(
                        taskID: task.id,
                        start: start,
                        end: start + task.duration,
                        intent: currentDropIntent
                    )
                }
                appState.draggingTaskID = nil
                appState.dragLocation = .zero
                appState.timelineDropIntent = .choose
            }
    }

    private var currentDropIntent: TimelineDropIntent {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) { return .timeBlock }
        if flags.contains(.option) { return .event }
        return .choose
    }
}

private struct SixDotDragHandle: View {
    let isActive: Bool

    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                GridRow {
                    Circle().frame(width: 3, height: 3)
                    Circle().frame(width: 3, height: 3)
                }
            }
        }
        .foregroundStyle(isActive ? MetridayTheme.accent : MetridayTheme.secondary.opacity(0.62))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isActive ? MetridayTheme.accentSoft : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .animation(.easeOut(duration: 0.12), value: isActive)
    }
}

struct PlanCalendarPane: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: MarkdownStore
    @State private var isSystemDropTargeted = false
    @State private var now = Date()
    @State private var selectedCalendarEvent: CalendarEventItem?

    private var visibleDates: [Date] {
        (0..<4).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: appState.selectedDate) }
    }

    private var isDropTargeted: Bool {
        isSystemDropTargeted || (appState.draggingTaskID != nil && appState.calendarTimelineFrame.contains(appState.dragLocation))
    }

    var body: some View {
        VStack(spacing: 0) {
            MiniMonthCalendar(
                selectedDate: appState.selectedDate,
                store: store,
                onSelect: appState.selectDate
            )
            Divider()

            HStack(spacing: 5) {
                Text("Timeline")
                    .font(.system(size: 13, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)
                Spacer()
                Image(systemName: "gearshape")
                    .foregroundStyle(MetridayTheme.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(MetridayTheme.canvas)
            Divider()

            timelineHeader
            Divider()
            timeline

            Divider()
            HStack(spacing: 7) {
                Image(systemName: "circle.grid.2x2.fill")
                Text(dropInstruction)
            }
            .font(.system(size: 10, weight: isDropTargeted ? .semibold : .regular))
            .foregroundStyle(isDropTargeted ? MetridayTheme.accent : MetridayTheme.secondary)
            .frame(height: 36)
        }
        .background(.white)
        .overlay(alignment: .bottomTrailing) {
            if appState.pendingTimelineDrop != nil {
                timeBlockChoice
                    .padding(.trailing, 8)
                    .padding(.bottom, 42)
            }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { value in
            now = value
        }
        .sheet(item: $selectedCalendarEvent) { event in
            CalendarEventDetailSheet(
                event: event,
                projectID: appState.suggestedProjectID(for: event),
                timeEntryStore: appState.timeEntryStore,
                onConvert: { appState.convertCalendarEventToTimeBlock(event) }
            )
        }
    }

    private var currentTimeMinute: Int? {
        guard Calendar.current.isDateInToday(appState.selectedDate) else { return nil }
        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        guard minute >= TimelineMetrics.startMinute, minute <= TimelineMetrics.endMinute else { return nil }
        return minute
    }

    private var dropInstruction: String {
        guard isDropTargeted else { return "⌘-drag: Time Block · ⌥-drag: Event" }
        switch appState.timelineDropIntent {
        case .timeBlock: return "Release to add a Time Block"
        case .event: return "Release to add Event"
        case .choose: return "Release to choose Time Block or Event"
        }
    }

    private var timeBlockChoice: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.task(appState.pendingTimelineDrop?.taskID ?? UUID())?.title ?? "Schedule task")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Button(action: appState.cancelPendingTimelineDrop) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(MetridayTheme.secondary)
            .padding(.horizontal, 12)
            .frame(height: 34)

            Divider()

            Button(action: appState.confirmPendingTimeBlock) {
                HStack(spacing: 9) {
                    Image(systemName: "clock.badge.checkmark")
                        .foregroundStyle(MetridayTheme.accent)
                    Text("Add Time Block")
                    Spacer()
                    Text("⌘+Drop")
                        .foregroundStyle(MetridayTheme.secondary)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            Button {
                if appState.calendarStore.isAuthorized {
                    appState.confirmPendingEvent()
                } else {
                    appState.calendarStore.requestAccess()
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundStyle(MetridayTheme.accent)
                    Text(appState.calendarStore.isAuthorized ? "Add Event" : "Connect Calendar")
                    Spacer()
                    Text(appState.calendarStore.isAuthorized ? "⌥+Drop" : "Permission")
                        .foregroundStyle(MetridayTheme.secondary)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 12))
        .frame(width: 224)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(MetridayTheme.line))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
    }

    private var timelineHeader: some View {
        HStack(spacing: 0) {
            Text("all-day")
                .font(.system(size: 9))
                .foregroundStyle(MetridayTheme.secondary)
                .frame(width: 44)
            ForEach(Array(visibleDates.enumerated()), id: \.element) { index, date in
                Button {
                    appState.selectDate(date)
                } label: {
                    Text(shortDay(date))
                        .font(.system(size: 10, weight: index == 0 ? .semibold : .medium))
                        .foregroundStyle(index == 0 ? MetridayTheme.accent : MetridayTheme.graphite)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(index == 0 ? MetridayTheme.accentSoft.opacity(0.55) : .white)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(MetridayTheme.line).frame(width: 1)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 48)
    }

    private var timeline: some View {
        ScrollView(.vertical) {
            HStack(spacing: 0) {
                TimelineHourLabels()
                    .frame(width: 44)

                ForEach(Array(visibleDates.enumerated()), id: \.element) { index, date in
                    ZStack(alignment: .topLeading) {
                        CompactTimelineGrid()
                            .overlay {
                                if index == 0 {
                                    TimelineDropReceiver(
                                        onTargeted: { isSystemDropTargeted = $0 },
                                        onDrop: { id, y in
                                            receiveDrop(id: id, at: y)
                                            return true
                                        },
                                        onScreenFrameChange: { appState.calendarTimelineScreenFrame = $0 }
                                    )
                                }
                            }
                        if index == 0 {
                            if isDropTargeted {
                                Rectangle()
                                    .fill(MetridayTheme.accentSoft.opacity(0.58))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(MetridayTheme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                            .padding(3)
                                    )
                            }

                            ForEach(calendarEventTimelineItems(events: appState.calendarStore.events, date: appState.selectedDate)) { item in
                                CalendarEventTimelineBlock(item: item) {
                                    selectedCalendarEvent = item.event
                                }
                                .padding(.horizontal, 6)
                                .zIndex(1)
                            }

                            ForEach(store.tasks.filter { $0.startMinute != nil }) { task in
                                CalendarTaskBlock(store: store, task: task, selected: appState.selectedTaskID == task.id)
                                    .padding(.horizontal, 4)
                            }

                            if let markerMinute = currentTimeMinute {
                                PlanCurrentTimeMarker(minute: markerMinute)
                                    .zIndex(8)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: TimelineMetrics.totalHeight)
                    .background {
                        if index == 0 {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: CalendarTimelineFrameKey.self,
                                    value: proxy.frame(in: .named("planRoot"))
                                )
                            }
                        }
                    }
                    .overlay(alignment: .leading) {
                        Rectangle().fill(MetridayTheme.line).frame(width: 1)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if index > 0 {
                            appState.selectDate(date)
                        }
                    }
                    .accessibilityAddTraits(index > 0 ? .isButton : [])
                    .accessibilityLabel(index > 0 ? "Open plan for \(shortDay(date))" : "Selected day timeline")
                    .dropDestination(for: String.self) { identifiers, location in
                        guard index == 0,
                              let identifier = identifiers.first,
                              let id = UUID(uuidString: identifier) else { return false }
                        receiveDrop(id: id, at: location.y)
                        return true
                    } isTargeted: { targeted in
                        if index == 0 {
                            isSystemDropTargeted = targeted
                        }
                        if index == 0, !targeted, appState.draggingTaskID == nil {
                            appState.dragLocation = .zero
                        }
                    }
                }
            }
            .frame(height: TimelineMetrics.totalHeight)
        }
        .defaultScrollAnchor(.bottom)
        .onPreferenceChange(CalendarTimelineFrameKey.self) { frame in
            appState.calendarTimelineFrame = frame
        }
    }

    private func receiveDrop(id: UUID, at y: CGFloat) {
        let minute = TimelineMetrics.startMinute + Int((y / TimelineMetrics.hourHeight) * 60)
        let start = Int((Double(minute) / 15).rounded()) * 15
        let duration = store.task(id)?.duration ?? 60
        appState.receiveTimelineDrop(
            taskID: id,
            start: start,
            end: start + duration,
            intent: currentDropIntent
        )
    }

    private var currentDropIntent: TimelineDropIntent {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) { return .timeBlock }
        if flags.contains(.option) { return .event }
        return .choose
    }

    private func shortDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE d"
        return formatter.string(from: date)
    }
}

private struct PlanCurrentTimeMarker: View {
    let minute: Int

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(MetridayTheme.accent)
                .frame(width: 8, height: 8)
                .offset(x: -4)
            Rectangle()
                .fill(MetridayTheme.accent.opacity(0.72))
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(y: TimelineMetrics.y(for: minute) - 4)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current time")
    }
}

private struct CalendarTimelineFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct MiniMonthCalendar: View {
    let selectedDate: Date
    @ObservedObject var store: MarkdownStore
    let onSelect: (Date) -> Void
    @State private var displayedMonth: Date

    private let weekdays = ["CW", "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    init(selectedDate: Date, store: MarkdownStore, onSelect: @escaping (Date) -> Void) {
        self.selectedDate = selectedDate
        self.store = store
        self.onSelect = onSelect
        _displayedMonth = State(initialValue: Self.startOfMonth(selectedDate))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(monthTitle)
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("calendar.previous-month")
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("calendar.next-month")
            }
            .padding(.horizontal, 12)

            Grid(horizontalSpacing: 1, verticalSpacing: 5) {
                GridRow {
                    ForEach(Array(weekdays.enumerated()), id: \.offset) { index, weekday in
                        Text(weekday)
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(index == 0 ? MetridayTheme.warning : MetridayTheme.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    GridRow {
                        Text("\(weekNumber(for: week[0]))")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(MetridayTheme.warning)
                            .frame(maxWidth: .infinity)

                        ForEach(week, id: \.self) { date in
                            monthCell(date: date)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.top, 10)
        .padding(.bottom, 9)
        .frame(height: 230)
        .background(.white)
        .onChange(of: selectedDate) { _, newDate in
            if !Calendar.current.isDate(newDate, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = Self.startOfMonth(newDate)
            }
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private var weeks: [[Date]] {
        let calendar = Calendar.current
        let monthStart = Self.startOfMonth(displayedMonth)
        let weekday = calendar.component(.weekday, from: monthStart)
        let offsetFromMonday = (weekday + 5) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -offsetFromMonday, to: monthStart) else { return [] }
        let dates = (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
        return stride(from: 0, to: dates.count, by: 7).map { Array(dates[$0..<min($0 + 7, dates.count)]) }
    }

    private func monthCell(date: Date) -> some View {
        let calendar = Calendar.current
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let today = calendar.isDateInToday(date)
        let adjacent = !calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        let hasFile = store.fileExists(for: date)
        let idFormatter = DateFormatter()
        idFormatter.locale = Locale(identifier: "en_US_POSIX")
        idFormatter.dateFormat = "yyyy-MM-dd"

        return Button {
            onSelect(date)
        } label: {
            ZStack(alignment: .bottom) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 10, weight: selected || today ? .bold : .regular))
                    .foregroundStyle(selected ? Color.white : (today ? MetridayTheme.accent : (adjacent ? MetridayTheme.secondary.opacity(0.55) : MetridayTheme.graphite)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if hasFile && !selected {
                    Circle()
                        .fill(MetridayTheme.accent)
                        .frame(width: 3, height: 3)
                        .padding(.bottom, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(selected ? MetridayTheme.accent : (today ? MetridayTheme.accentSoft : .clear))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("calendar.day.\(idFormatter.string(from: date))")
        .help(hasFile ? "Open daily Markdown" : "Create daily Markdown")
    }

    private func weekNumber(for date: Date) -> Int {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar.component(.weekOfYear, from: date)
    }

    private func moveMonth(_ offset: Int) {
        guard let month = Calendar.current.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        displayedMonth = Self.startOfMonth(month)
    }

    private static func startOfMonth(_ date: Date) -> Date {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return Calendar.current.date(from: components) ?? Calendar.current.startOfDay(for: date)
    }
}

private struct TimelineHourLabels: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(8..<20, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: 9))
                    .foregroundStyle(MetridayTheme.secondary)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, minHeight: TimelineMetrics.hourHeight, maxHeight: TimelineMetrics.hourHeight, alignment: .top)
            }
        }
    }
}

private struct CompactTimelineGrid: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(8..<20, id: \.self) { _ in
                Rectangle()
                    .fill(MetridayTheme.line.opacity(0.78))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .frame(height: TimelineMetrics.hourHeight)
            }
            Rectangle().fill(MetridayTheme.line.opacity(0.78)).frame(height: 1)
        }
        .frame(height: TimelineMetrics.totalHeight, alignment: .top)
    }
}

struct CalendarTaskBlock: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: MarkdownStore
    let task: PlanTask
    let selected: Bool
    @State private var isHovering = false

    private var execution: TimeBlockExecutionSummary {
        timeBlockExecutionSummary(
            taskID: task.id,
            entries: appState.timeEntryStore.materializedEntries(),
            runningTimer: appState.timeEntryStore.runningTimer,
            date: appState.selectedDate
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(task.timeRange ?? "")
                .font(.system(size: 9, weight: .medium))
                .opacity(0.78)
            Text(task.title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(3)
            if execution.hasExecution {
                Text(execution.statusLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .opacity(0.86)
            }
            Spacer(minLength: 1)
        }
        .foregroundStyle(task.tone == .accent ? .white : Color(red: 0.20, green: 0.23, blue: 0.42))
        .padding(7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(task.tone == .accent ? MetridayTheme.accent : MetridayTheme.accentSoft)
        .opacity(task.isCompleted ? 0.58 : 1)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? MetridayTheme.accentDeep : MetridayTheme.accent.opacity(0.25), lineWidth: selected ? 2 : 1))
        .overlay(alignment: .top) {
            resizeHandle(symbol: "arrow.up")
                .padding(.horizontal, 8)
                .padding(.top, 2)
        }
        .overlay(alignment: .bottom) {
            resizeHandle(symbol: "arrow.down")
                .padding(.horizontal, 8)
                .padding(.bottom, 3)
        }
        .frame(height: TimelineMetrics.height(start: task.startMinute ?? 0, end: task.endMinute ?? 0))
        .contentShape(Rectangle())
        .overlay {
            if let start = task.startMinute, let end = task.endMinute {
                CalendarBlockInteraction(
                    startMinute: start,
                    endMinute: end,
                    hourHeight: TimelineMetrics.hourHeight,
                    onSelect: { appState.selectedTaskID = task.id },
                    onMove: { store.move(id: task.id, start: $0) },
                    onResizeStart: { store.resizeStart(id: task.id, start: $0) },
                    onResizeEnd: { store.resize(id: task.id, end: $0) }
                )
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if selected {
                Menu {
                    Button(task.isCompleted ? "Mark incomplete" : "Mark complete") { store.toggleCompleted(id: task.id) }
                    Button("Remove time", role: .destructive) { store.unschedule(id: task.id) }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(task.tone == .accent ? .white : MetridayTheme.accent)
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22, height: 22)
                .padding(2)
            }
        }
        .offset(y: TimelineMetrics.y(for: task.startMinute ?? TimelineMetrics.startMinute))
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Time Block \(task.title), \(task.timeRange ?? "unscheduled")\(execution.hasExecution ? ", \(execution.statusLabel)" : "")")
        .accessibilityHint("Select the block; drag the body to move it or its edges to resize it")
        .accessibilityAction { appState.selectedTaskID = task.id }
        .accessibilityIdentifier("calendar.task.\(task.id.uuidString)")
    }

    private func resizeHandle(symbol: String) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(task.tone == .accent ? Color.white.opacity(0.82) : MetridayTheme.accent.opacity(0.60))
                .frame(height: 3)
            if selected {
                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .bold))
            }
        }
        .frame(height: 10)
        .opacity(selected || isHovering ? 1 : 0.28)
        .contentShape(Rectangle())
        .help(symbol == "arrow.up" ? "Drag to change start time" : "Drag to change end time")
    }

}

import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: MarkdownStore

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 55)
                            TimelineGrid(showLabels: true)
                        }
                        .frame(width: 76)
                        plannedColumn
                            .frame(width: max(340, (proxy.size.width - 76) * 0.44))
                        Divider()
                        actualColumn
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            insightBar
                .padding(12)
        }
        .background(.white)
    }

    private var plannedColumn: some View {
        VStack(spacing: 0) {
            TimelineColumnHeader(title: "Plan", subtitle: "What I planned")
            ZStack(alignment: .topLeading) {
                TimelineGrid()
                ForEach(scheduledTasks) { task in
                    if let start = task.startMinute, let end = task.endMinute {
                        StaticTimelineBlock(
                            title: task.title,
                            start: start,
                            end: end,
                            symbol: symbol(for: task),
                            isCurrent: appState.currentTask?.id == task.id
                        )
                        .padding(.horizontal, 10)
                    }
                }
                if Calendar.current.isDateInToday(appState.selectedDate) {
                    currentTimeLine
                }
            }
            .frame(height: TimelineMetrics.totalHeight)
        }
    }

    private var scheduledTasks: [PlanTask] {
        store.tasks
            .filter { $0.startMinute != nil && $0.endMinute != nil }
            .sorted { ($0.startMinute ?? 0) < ($1.startMinute ?? 0) }
    }

    private func symbol(for task: PlanTask) -> String {
        let title = task.title.lowercased()
        if title.contains("lunch") || title.contains("break") { return "fork.knife" }
        if title.contains("read") || title.contains("review") { return "doc.text" }
        if title.contains("write") || title.contains("draft") { return "square.and.pencil" }
        if title.contains("experiment") || title.contains("research") { return "flask" }
        return "checkmark.circle"
    }

    private var actualColumn: some View {
        VStack(spacing: 0) {
            TimelineColumnHeader(title: "Actual", subtitle: "What actually happened")
            ZStack(alignment: .topLeading) {
                TimelineGrid()
                actualBlock(start: 480, end: 540) {
                    ActivityRow(minutes: 60, title: "Idle", range: "08:00–09:00", symbol: nil, relevance: .idle)
                }
                actualBlock(start: 540, end: 625, related: true) {
                    VStack(spacing: 0) {
                        ActivityRow(minutes: 85, title: "VS Code", range: "09:00–09:45", symbol: "chevron.left.forwardslash.chevron.right", relevance: .related)
                        ActivityRow(minutes: nil, title: "Terminal", range: "09:45–10:25", symbol: "terminal", relevance: .related)
                    }
                }
                actualBlock(start: 630, end: 720, related: true) {
                    VStack(spacing: 0) {
                        ActivityRow(minutes: 90, title: "arXiv PDF", range: "10:30–11:15", symbol: "doc.richtext", relevance: .related)
                        ActivityRow(minutes: nil, title: "Notes", range: "11:15–12:00", symbol: "note.text", relevance: .related)
                    }
                }
                actualBlock(start: 720, end: 780) {
                    ActivityRow(minutes: 60, title: "Lunch / Break", range: "12:00–13:00", symbol: nil, relevance: .idle)
                }
                actualBlock(start: 780, end: 835, related: true) {
                    ActivityRow(minutes: 55, title: "VS Code", range: "13:00–13:55", symbol: "chevron.left.forwardslash.chevron.right", relevance: .related)
                }
                currentActualBlock
                actualBlock(start: 960, end: 1080) {
                    ActivityRow(minutes: 120, title: "Idle", range: "16:00–18:00", symbol: nil, relevance: .idle)
                }
                actualBlock(start: 1080, end: 1140) {
                    ActivityRow(minutes: 60, title: "Idle", range: "18:00–19:00", symbol: nil, relevance: .idle)
                }
                currentTimeLine
            }
            .frame(height: TimelineMetrics.totalHeight)
        }
    }

    private func actualBlock<Content: View>(start: Int, end: Int, related: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(related ? MetridayTheme.successSoft : Color(red: 0.976, green: 0.977, blue: 0.982))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(MetridayTheme.line, lineWidth: 1))
            .frame(height: TimelineMetrics.height(start: start, end: end))
            .padding(.horizontal, 10)
            .offset(y: TimelineMetrics.y(for: start))
    }

    private var currentActualBlock: some View {
        VStack(spacing: 0) {
            ActivityRow(minutes: 8, title: "Idle", range: "14:00–14:08", symbol: nil, relevance: .idle)
            ActivityRow(minutes: 71, title: "VS Code", range: "14:08–15:19", symbol: "chevron.left.forwardslash.chevron.right", relevance: .related)
            ActivityRow(minutes: 12, title: "YouTube", range: "15:19–15:31", symbol: "play.rectangle.fill", relevance: .distracted)
            ActivityRow(minutes: 21, title: "Terminal", range: "15:31–15:52", symbol: "terminal", relevance: .related)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(MetridayTheme.accent, lineWidth: 1.5))
        .padding(.horizontal, 10)
        .offset(y: TimelineMetrics.y(for: 840))
    }

    private var currentTimeLine: some View {
        Rectangle()
            .fill(MetridayTheme.accent)
            .frame(height: 1)
            .offset(y: TimelineMetrics.y(for: 952))
    }

    private var insightBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 23))
                .foregroundStyle(MetridayTheme.accent)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 12) {
                    Text("Started 8 min late").fontWeight(.semibold)
                    Text("·").foregroundStyle(MetridayTheme.secondary)
                    Text("82% task-related").fontWeight(.semibold).foregroundStyle(MetridayTheme.success)
                    Text("·").foregroundStyle(MetridayTheme.secondary)
                    Text("Estimate likely +25 min").fontWeight(.semibold).foregroundStyle(MetridayTheme.warning)
                }
                Text("YouTube 12m was outside Research Focus. Blocking is available for the active task.")
                    .font(.system(size: 11))
                    .foregroundStyle(MetridayTheme.secondary)
            }
            Spacer()
            Button("Adjust blocklist") { appState.section = .rules }
                .buttonStyle(.bordered)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 18)
        .frame(height: 68)
        .metridayPanel(radius: 10)
    }
}

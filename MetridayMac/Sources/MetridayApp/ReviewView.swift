import Charts
import SwiftUI

struct ReviewView: View {
    private let days = [
        ("Mon", 68, 24), ("Tue", 74, 18), ("Wed", 61, 31),
        ("Thu", 82, 14), ("Fri", 77, 16), ("Sat", 82, 12), ("Sun", 0, 0)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageDateHeader(title: "Review", subtitle: "Understand where your planned time actually went")

                HStack(spacing: 16) {
                    metricCard(title: "Task-related", value: "82%", note: "+7% vs last week", color: MetridayTheme.success, symbol: "checkmark.seal")
                    metricCard(title: "Deep work", value: "4h 41m", note: "3 focused blocks", color: MetridayTheme.accent, symbol: "timer")
                    metricCard(title: "Distraction", value: "12m", note: "YouTube during focus", color: MetridayTheme.danger, symbol: "exclamationmark.triangle")
                    metricCard(title: "Plan accuracy", value: "+25m", note: "Likely over estimate", color: MetridayTheme.warning, symbol: "chart.line.uptrend.xyaxis")
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Weekly focus quality").font(.system(size: 17, weight: .bold))
                            Text("Task-related time vs distraction").font(.system(size: 11)).foregroundStyle(MetridayTheme.secondary)
                        }
                        Spacer()
                        Picker("Range", selection: .constant("This week")) {
                            Text("This week").tag("This week")
                            Text("Last week").tag("Last week")
                        }
                        .frame(width: 150)
                    }

                    Chart {
                        ForEach(days, id: \.0) { day in
                            BarMark(x: .value("Day", day.0), y: .value("Related", day.1))
                                .foregroundStyle(MetridayTheme.accent)
                            BarMark(x: .value("Day", day.0), y: .value("Distracted", day.2))
                                .foregroundStyle(MetridayTheme.danger.opacity(0.65))
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 280)
                }
                .padding(20)
                .metridayPanel()

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("What helped", systemImage: "arrow.up.right.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(MetridayTheme.success)
                        insight("Starting with a named time block improved task relevance.")
                        insight("Terminal and VS Code switching stayed inside Research Focus.")
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .metridayPanel()

                    VStack(alignment: .leading, spacing: 14) {
                        Label("Try next", systemImage: "wand.and.stars")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(MetridayTheme.accent)
                        insight("Add YouTube to the active blocklist before deep work.")
                        insight("Give analysis a 25-minute buffer after experiments.")
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .metridayPanel()
                }
            }
            .padding(28)
        }
    }

    private func metricCard(title: String, value: String, note: String, color: Color, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(MetridayTheme.secondary)
                Spacer()
                Image(systemName: symbol).foregroundStyle(color)
            }
            Text(value).font(.system(size: 26, weight: .bold)).foregroundStyle(MetridayTheme.graphite)
            Text(note).font(.system(size: 10)).foregroundStyle(color)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
    }

    private func insight(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(MetridayTheme.line).frame(width: 5, height: 5).padding(.top, 5)
            Text(text).font(.system(size: 12)).foregroundStyle(MetridayTheme.secondary)
        }
    }
}

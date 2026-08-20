import SwiftUI

struct ActivityInsightsPanel: View {
    @EnvironmentObject private var appState: AppState
    let segments: [ActivitySegment]

    var body: some View {
        let localDeviceName = appState.syncStore.deviceName
        let insights = ActivityInsights.generate(from: segments, localDeviceName: localDeviceName)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("Smart Activity Summary", systemImage: "sparkles")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MetridayTheme.accent)
                Spacer()
                Text(segments.contains { $0.deviceName != localDeviceName } ? "Local + Screen Time" : "On this Mac")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MetridayTheme.secondary)
            }
            Text("Explainable highlights from the same local activity data used by your reports.")
                .font(.system(size: 11))
                .foregroundStyle(MetridayTheme.secondary)

            ForEach(insights) { insight in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: insight.symbol)
                        .frame(width: 17)
                        .foregroundStyle(MetridayTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(insight.title)
                            .font(.system(size: 12, weight: .semibold))
                        Text(insight.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(MetridayTheme.secondary)
                        Text(sourceLabel(insight.source))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(MetridayTheme.secondary.opacity(0.8))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .metridayPanel()
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "screen_time": return "Screen Time import"
        case "mixed_sources": return "Local activity + Screen Time"
        default: return "Local activity monitor"
        }
    }
}

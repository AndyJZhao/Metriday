import Foundation

struct ActivityInsight: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let source: String
    let durationSeconds: Int?

    init(
        id: String,
        title: String,
        detail: String,
        symbol: String,
        source: String = "local_activity",
        durationSeconds: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.source = source
        self.durationSeconds = durationSeconds
    }
}

/// A private, deterministic summary layer for the same activity evidence used
/// by reports. It intentionally runs without a network model: summaries stay
/// available in the local-first build and remain explainable from the source
/// segments.
enum ActivityInsights {
    static func generate(from segments: [ActivitySegment], limit: Int = 3) -> [ActivityInsight] {
        let active = segments.filter { $0.relevance != .idle && $0.durationSeconds > 0 }
        guard !active.isEmpty else {
            return [ActivityInsight(
                id: "empty",
                title: "No active work recorded yet",
                detail: "Start tracking or add a manual time entry to generate an on-device summary.",
                symbol: "sparkles",
                durationSeconds: 0
            )]
        }

        let totalSeconds = active.reduce(0) { $0 + $1.durationSeconds }
        var insights: [ActivityInsight] = []

        let grouped = Dictionary(grouping: active) { segment in
            let title = segment.appName.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? "Unknown activity" : title
        }
        if let top = grouped
            .map({ entry in
                (
                    name: entry.key,
                    seconds: entry.value.reduce(0) { $0 + $1.durationSeconds },
                    source: source(for: entry.value)
                )
            })
            .max(by: { $0.seconds < $1.seconds }) {
            let percentage = Int((Double(top.seconds) / Double(totalSeconds) * 100).rounded())
            insights.append(ActivityInsight(
                id: "top-app",
                title: String(format: "%@ was your main activity", top.name),
                detail: String(format: "%@ · %d%% of active time", durationLabel(top.seconds), percentage),
                symbol: "app.badge",
                source: top.source,
                durationSeconds: top.seconds
            ))
        }

        let related = active.filter { $0.relevance == .related }
        if let longest = related.max(by: { $0.durationSeconds < $1.durationSeconds }) {
            insights.append(ActivityInsight(
                id: "deep-work",
                title: String(format: "Longest focused stretch: %@", longest.appName),
                detail: String(format: "%@ · %@", durationLabel(longest.durationSeconds), timeRange(longest)),
                symbol: "bolt.fill",
                source: source(for: [longest]),
                durationSeconds: longest.durationSeconds
            ))
        }

        let distracted = active.filter { $0.relevance == .distracted }
        if !distracted.isEmpty {
            let groupedDistractions = Dictionary(grouping: distracted) { $0.appName }
            let top = groupedDistractions
                .map { entry in
                    (
                        name: entry.key,
                        seconds: entry.value.reduce(0) { $0 + $1.durationSeconds },
                        source: source(for: entry.value)
                    )
                }
                .max(by: { $0.seconds < $1.seconds })
            if let top {
                insights.append(ActivityInsight(
                    id: "distraction",
                    title: String(format: "%@ was the largest distraction", top.name),
                    detail: String(format: "%@ across %d captured segment%@", durationLabel(top.seconds), distracted.count, distracted.count == 1 ? "" : "s"),
                    symbol: "exclamationmark.triangle",
                    source: top.source,
                    durationSeconds: top.seconds
                ))
            }
        }

        let mobileSeconds = active
            .filter { $0.deviceName != "This Mac" }
            .reduce(0) { $0 + $1.durationSeconds }
        if mobileSeconds > 0 {
            insights.append(ActivityInsight(
                id: "mobile",
                title: "Activity from another device is included",
                detail: String(format: "%@ imported from Screen Time", durationLabel(mobileSeconds)),
                symbol: "iphone.and.arrow.forward",
                source: "screen_time",
                durationSeconds: mobileSeconds
            ))
        }

        return Array(insights.prefix(max(1, limit)))
    }

    private static func durationLabel(_ seconds: Int) -> String {
        let minutes = Int((Double(seconds) / 60.0).rounded())
        if minutes < 1 { return "<1m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? String(format: "%dh %dm", hours, remainder) : String(format: "%dm", remainder)
    }

    private static func timeRange(_ segment: ActivitySegment) -> String {
        let includesSeconds = segment.durationSeconds < 60
        let start = clockLabel(segment.startSecond, includesSeconds: includesSeconds)
        let end = clockLabel(segment.endSecond, includesSeconds: includesSeconds)
        return String(format: "%@–%@", start, end)
    }

    private static func clockLabel(_ seconds: Int, includesSeconds: Bool) -> String {
        if includesSeconds {
            return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 3600, (seconds / 60) % 60)
    }

    private static func source(for segments: [ActivitySegment]) -> String {
        let sources = Set(segments.map { $0.deviceName == "This Mac" ? "local_activity" : "screen_time" })
        if sources.count == 1 { return sources.first ?? "local_activity" }
        return "mixed_sources"
    }
}

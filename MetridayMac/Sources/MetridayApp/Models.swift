import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case plan = "Plan"
    case review = "Review"
    case rules = "Rules"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .today: "calendar"
        case .plan: "square.and.pencil"
        case .review: "chart.bar.xaxis"
        case .rules: "shield"
        }
    }
}

struct PlanTask: Identifiable, Hashable {
    let id: UUID
    var title: String
    var tags: [String]
    var startMinute: Int?
    var endMinute: Int?
    var isCompleted: Bool
    var tone: TaskTone

    init(
        id: UUID = UUID(),
        title: String,
        tags: [String] = [],
        startMinute: Int? = nil,
        endMinute: Int? = nil,
        isCompleted: Bool = false,
        tone: TaskTone = .soft
    ) {
        self.id = id
        self.title = title
        self.tags = tags
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.isCompleted = isCompleted
        self.tone = tone
    }

    var duration: Int {
        guard let startMinute, let endMinute else { return 60 }
        return max(30, endMinute - startMinute)
    }

    var timeRange: String? {
        guard let startMinute, let endMinute else { return nil }
        return TimeFormat.range(start: startMinute, end: endMinute)
    }
}

enum TimelineDropIntent: Hashable {
    case choose
    case timeBlock
    case event
}

struct PendingTimelineDrop: Identifiable, Hashable {
    var id: UUID { taskID }
    let taskID: UUID
    let startMinute: Int
    let endMinute: Int
    let intent: TimelineDropIntent
}

enum TaskTone: String, Hashable {
    case accent
    case soft
    case neutral
}

enum TimeFormat {
    static func string(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    static func range(start: Int, end: Int) -> String {
        "\(string(start)) - \(string(end))"
    }

    static func parseRange(_ value: String) -> (start: Int, end: Int)? {
        let pattern = #"^(\d{1,2}):(\d{2})\s*[–—-]\s*(\d{1,2}):(\d{2})$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges == 5,
              let h1 = value.capture(match.range(at: 1)).flatMap(Int.init),
              let m1 = value.capture(match.range(at: 2)).flatMap(Int.init),
              let h2 = value.capture(match.range(at: 3)).flatMap(Int.init),
              let m2 = value.capture(match.range(at: 4)).flatMap(Int.init) else { return nil }
        let start = h1 * 60 + m1
        let end = h2 * 60 + m2
        guard h1 < 24, h2 < 24, m1 < 60, m2 < 60, end > start else { return nil }
        return (start, end)
    }
}

struct ActivitySegment: Identifiable, Hashable {
    let id: UUID
    var appName: String
    var bundleIdentifier: String
    var startMinute: Int
    var endMinute: Int
    var relevance: ActivityRelevance

    init(
        id: UUID = UUID(),
        appName: String,
        bundleIdentifier: String = "",
        startMinute: Int,
        endMinute: Int,
        relevance: ActivityRelevance
    ) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.relevance = relevance
    }

    var duration: Int { max(1, endMinute - startMinute) }
}

enum ActivityRelevance: String, Hashable {
    case related
    case distracted
    case idle
}

struct WebRule: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var domain: String
    var isAllowed: Bool = false
}

enum DomainRuleMatcher {
    static func shouldBlock(host rawHost: String, rules: [WebRule]) -> Bool {
        let host = normalizedDomain(rawHost)
        guard !host.isEmpty else { return false }
        let allowMatches = rules.filter(\.isAllowed).contains { matches(host: host, rule: $0.domain) }
        if allowMatches { return false }
        return rules.filter { !$0.isAllowed }.contains { matches(host: host, rule: $0.domain) }
    }

    static func normalizedDomain(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let url = URL(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)"), let host = url.host {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return trimmed.replacingOccurrences(of: "www.", with: "")
    }

    private static func matches(host: String, rule: String) -> Bool {
        host == rule || host.hasSuffix(".\(rule)")
    }
}

extension String {
    fileprivate func capture(_ range: NSRange) -> String? {
        guard let swiftRange = Range(range, in: self) else { return nil }
        return String(self[swiftRange])
    }
}

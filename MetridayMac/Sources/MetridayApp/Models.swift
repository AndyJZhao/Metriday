import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case plan = "Plan"
    case activities = "Activities"
    case stats = "Stats"
    case reports = "Reports"
    case teams = "Teams"
    case review = "Review"
    case rules = "Rules"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .today: "calendar"
        case .plan: "square.and.pencil"
        case .activities: "waveform.path"
        case .stats: "chart.bar.xaxis"
        case .reports: "doc.text"
        case .teams: "person.3"
        case .review: "checkmark.seal"
        case .rules: "shield"
        }
    }
}

/// The project scope selected in the activity browser is shared by the
/// Activities and Stats surfaces, matching Timing's persistent project tree.
enum ActivityProjectScope: Hashable {
    case all
    case unassigned
    case project(UUID)

    init(persistedValue: String?) {
        guard let value = persistedValue else {
            self = .all
            return
        }
        switch value {
        case "all": self = .all
        case "unassigned": self = .unassigned
        default: self = UUID(uuidString: value).map(Self.project) ?? .all
        }
    }

    var persistedValue: String {
        switch self {
        case .all: return "all"
        case .unassigned: return "unassigned"
        case .project(let id): return id.uuidString
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

struct ActivitySegment: Identifiable, Hashable, Codable {
    let id: UUID
    var appName: String
    var bundleIdentifier: String
    var deviceName: String
    var windowTitle: String
    var resource: String
    var startSecond: Int
    var endSecond: Int
    var relevance: ActivityRelevance
    var projectID: UUID?
    /// The day this segment was captured on when Activities is showing a
    /// multi-day history. It is display-only and intentionally not persisted
    /// because the daily history file already provides the source of truth.
    var activityDate: Date?

    init(
        id: UUID = UUID(),
        appName: String,
        bundleIdentifier: String = "",
        deviceName: String = "This Mac",
        windowTitle: String = "",
        resource: String = "",
        startMinute: Int,
        endMinute: Int,
        startSecond: Int? = nil,
        endSecond: Int? = nil,
        relevance: ActivityRelevance,
        projectID: UUID? = nil,
        activityDate: Date? = nil
    ) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.deviceName = deviceName
        self.windowTitle = windowTitle
        self.resource = resource
        self.startSecond = startSecond ?? startMinute * 60
        self.endSecond = endSecond ?? endMinute * 60
        self.relevance = relevance
        self.projectID = projectID
        self.activityDate = activityDate
    }

    var startMinute: Int {
        get { startSecond / 60 }
        set { startSecond = newValue * 60 }
    }

    var endMinute: Int {
        get { Int(ceil(Double(endSecond) / 60.0)) }
        set { endSecond = newValue * 60 }
    }

    var durationSeconds: Int { max(1, endSecond - startSecond) }
    var duration: Int { max(1, Int(ceil(Double(durationSeconds) / 60.0))) }

    var displayTitle: String {
        let title = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, title.caseInsensitiveCompare(appName) != .orderedSame {
            return "\(appName) · \(title)"
        }
        if let host = URL(string: resource)?.host, !host.isEmpty {
            return "\(appName) · \(host)"
        }
        return appName
    }

    private enum CodingKeys: String, CodingKey {
        case id, appName, bundleIdentifier, deviceName, windowTitle, resource, startMinute, endMinute, startSecond, endSecond, relevance, projectID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        appName = try container.decode(String.self, forKey: .appName)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName) ?? "This Mac"
        windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle) ?? ""
        resource = try container.decodeIfPresent(String.self, forKey: .resource) ?? ""
        let legacyStart = try container.decodeIfPresent(Int.self, forKey: .startMinute) ?? 0
        let legacyEnd = try container.decodeIfPresent(Int.self, forKey: .endMinute) ?? legacyStart + 1
        startSecond = try container.decodeIfPresent(Int.self, forKey: .startSecond) ?? legacyStart * 60
        endSecond = try container.decodeIfPresent(Int.self, forKey: .endSecond) ?? legacyEnd * 60
        relevance = try container.decode(ActivityRelevance.self, forKey: .relevance)
        projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
        activityDate = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(appName, forKey: .appName)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(deviceName, forKey: .deviceName)
        try container.encode(windowTitle, forKey: .windowTitle)
        try container.encode(resource, forKey: .resource)
        try container.encode(startMinute, forKey: .startMinute)
        try container.encode(endMinute, forKey: .endMinute)
        try container.encode(startSecond, forKey: .startSecond)
        try container.encode(endSecond, forKey: .endSecond)
        try container.encode(relevance, forKey: .relevance)
        try container.encodeIfPresent(projectID, forKey: .projectID)
    }
}

enum ActivityRelevance: String, Hashable, Codable {
    case related
    case distracted
    case other
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

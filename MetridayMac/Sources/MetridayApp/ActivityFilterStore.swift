import Combine
import Foundation

enum ActivityFilterField: String, CaseIterable, Codable, Identifiable {
    case application
    case bundleIdentifier
    case windowTitle
    case resource
    case domain
    case fullURL
    case keyword
    case device
    case startTime
    case dayOfWeek

    var id: Self { self }

    var label: String {
        switch self {
        case .application: return "Application"
        case .bundleIdentifier: return "Bundle identifier"
        case .windowTitle: return "Window title"
        case .resource: return "URL or path"
        case .domain: return "Domain"
        case .fullURL: return "Full website URL"
        case .keyword: return "Keyword"
        case .device: return "Device"
        case .startTime: return "Start time"
        case .dayOfWeek: return "Day of week"
        }
    }
}

enum ActivityFilterMatchMode: String, CaseIterable, Codable, Identifiable {
    case any
    case all

    var id: Self { self }

    var label: String {
        switch self {
        case .any: return "Any rule"
        case .all: return "All rules"
        }
    }
}

struct ActivityFilterRule: Identifiable, Hashable, Codable {
    let id: UUID
    var field: ActivityFilterField
    var pattern: String
    var isCaseSensitive: Bool
    var comparison: ProjectRuleComparison

    init(
        id: UUID = UUID(),
        field: ActivityFilterField,
        pattern: String,
        isCaseSensitive: Bool = false,
        comparison: ProjectRuleComparison = .contains
    ) {
        self.id = id
        self.field = field
        self.pattern = pattern
        self.isCaseSensitive = isCaseSensitive
        self.comparison = comparison
    }
}

struct ActivityFilterDefinition: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var color: ProjectColor
    var matchMode: ActivityFilterMatchMode
    var rules: [ActivityFilterRule]
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        name: String,
        color: ProjectColor = .purple,
        matchMode: ActivityFilterMatchMode = .any,
        rules: [ActivityFilterRule] = [],
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.matchMode = matchMode
        self.rules = rules
        self.isArchived = isArchived
    }
}

struct ActivityFilterArchive: Codable {
    let version: Int
    let filters: [ActivityFilterDefinition]
}

@MainActor
final class ActivityFilterStore: ObservableObject {
    @Published private(set) var filters: [ActivityFilterDefinition]
    @Published var statusMessage = "Filters ready"

    private let fileURL: URL

    init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? Self.defaultRootDirectory()
        self.fileURL = root.appendingPathComponent("Filters.json")
        if let data = try? Data(contentsOf: fileURL),
           let payload = try? JSONDecoder().decode(ActivityFilterArchive.self, from: data) {
            self.filters = payload.filters
        } else {
            self.filters = []
            persist()
        }
    }

    var activeFilters: [ActivityFilterDefinition] {
        filters.filter { !$0.isArchived }
    }

    func filter(_ id: UUID?) -> ActivityFilterDefinition? {
        guard let id else { return nil }
        return filters.first { $0.id == id }
    }

    @discardableResult
    func createFilter(
        name rawName: String,
        color: ProjectColor = .purple,
        matchMode: ActivityFilterMatchMode = .any,
        rules: [ActivityFilterRule] = []
    ) -> UUID? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let definition = ActivityFilterDefinition(
            name: name,
            color: color,
            matchMode: matchMode,
            rules: normalizedRules(rules)
        )
        filters.append(definition)
        persist()
        statusMessage = "Filter created · \(name)"
        return definition.id
    }

    func save(_ definition: ActivityFilterDefinition) {
        let name = definition.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var updated = definition
        updated.name = name
        updated.rules = normalizedRules(definition.rules)
        if let index = filters.firstIndex(where: { $0.id == definition.id }) {
            filters[index] = updated
            statusMessage = "Filter updated · \(name)"
        } else {
            filters.append(updated)
            statusMessage = "Filter created · \(name)"
        }
        persist()
    }

    func archive(_ definition: ActivityFilterDefinition) {
        guard let index = filters.firstIndex(where: { $0.id == definition.id }) else { return }
        filters[index].isArchived = true
        persist()
        statusMessage = "Filter archived · \(definition.name)"
    }

    func delete(_ definition: ActivityFilterDefinition) {
        filters.removeAll { $0.id == definition.id }
        persist()
        statusMessage = "Filter deleted"
    }

    func matches(
        _ definition: ActivityFilterDefinition,
        activity: ActivitySegment,
        date: Date? = nil
    ) -> Bool {
        guard !definition.rules.isEmpty else { return false }
        switch definition.matchMode {
        case .any:
            return definition.rules.contains { matches($0, activity: activity, date: date) }
        case .all:
            return definition.rules.allSatisfy { matches($0, activity: activity, date: date) }
        }
    }

    func exportArchiveData() throws -> Data {
        let archive = ActivityFilterArchive(version: 1, filters: filters)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    @discardableResult
    func importArchiveData(_ data: Data) throws -> Int {
        let archive = try JSONDecoder().decode(ActivityFilterArchive.self, from: data)
        return mergeArchive(archive)
    }

    @discardableResult
    func mergeArchive(_ archive: ActivityFilterArchive) -> Int {
        var imported = 0
        for candidate in archive.filters {
            if let index = filters.firstIndex(where: { $0.id == candidate.id }) {
                filters[index] = candidate
            } else if let index = filters.firstIndex(where: {
                $0.name.caseInsensitiveCompare(candidate.name) == .orderedSame
            }) {
                filters[index] = candidate
            } else {
                filters.append(candidate)
                imported += 1
            }
        }
        if !archive.filters.isEmpty {
            persist()
            statusMessage = "Merged \(archive.filters.count) filter\(archive.filters.count == 1 ? "" : "s")"
        }
        return imported
    }

    private func normalizedRules(_ rules: [ActivityFilterRule]) -> [ActivityFilterRule] {
        var seen = Set<String>()
        return rules.filter { rule in
            let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty else { return false }
            let key = "\(rule.field.rawValue)|\(rule.comparison.rawValue)|\(rule.isCaseSensitive)|\(pattern.lowercased())"
            guard seen.insert(key).inserted else { return false }
            return true
        }.map { rule in
            var normalized = rule
            normalized.pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized
        }
    }

    private func matches(
        _ rule: ActivityFilterRule,
        activity: ActivitySegment,
        date: Date?
    ) -> Bool {
        let candidate: String
        switch rule.field {
        case .application:
            candidate = activity.appName
        case .bundleIdentifier:
            candidate = activity.bundleIdentifier
        case .windowTitle:
            candidate = activity.windowTitle
        case .resource:
            candidate = activity.resource
        case .domain:
            candidate = URL(string: activity.resource)?.host ?? ""
        case .fullURL:
            candidate = activity.resource
        case .keyword:
            candidate = "\(activity.windowTitle) \(activity.resource)"
        case .device:
            candidate = activity.deviceName
        case .startTime:
            let hour = activity.startMinute / 60
            let minute = activity.startMinute % 60
            candidate = String(format: "%02d:%02d", hour, minute)
        case .dayOfWeek:
            guard let date else { return false }
            let dayStart = Calendar.current.startOfDay(for: date)
            let segmentDate = Calendar.current.date(
                byAdding: .minute,
                value: activity.startMinute,
                to: dayStart
            ) ?? dayStart
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEEE"
            candidate = formatter.string(from: segmentDate)
        }

        let options: String.CompareOptions = rule.isCaseSensitive
            ? []
            : [.caseInsensitive, .diacriticInsensitive]
        if rule.comparison != .matchesRegex,
           rule.pattern.contains("||") || rule.pattern.contains("&&") {
            return rule.pattern
                .components(separatedBy: "||")
                .contains { branch in
                    branch
                        .components(separatedBy: "&&")
                        .allSatisfy { atom in
                            let pattern = atom.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !pattern.isEmpty else { return false }
                            return matchesAtom(
                                candidate: candidate,
                                pattern: pattern,
                                comparison: rule.comparison,
                                options: options,
                                isCaseSensitive: rule.isCaseSensitive,
                                supportsDayGroups: rule.field == .dayOfWeek,
                                supportsKeywordTokens: rule.field == .keyword
                            )
                        }
                }
        }
        return matchesAtom(
            candidate: candidate,
            pattern: rule.pattern,
            comparison: rule.comparison,
            options: options,
            isCaseSensitive: rule.isCaseSensitive,
            supportsDayGroups: rule.field == .dayOfWeek,
            supportsKeywordTokens: rule.field == .keyword
        )
    }

    private func matchesAtom(
        candidate: String,
        pattern: String,
        comparison: ProjectRuleComparison,
        options: String.CompareOptions,
        isCaseSensitive: Bool,
        supportsDayGroups: Bool,
        supportsKeywordTokens: Bool
    ) -> Bool {
        switch comparison {
        case .contains:
            if supportsKeywordTokens {
                return keywordTokens(from: candidate).contains {
                    $0.compare(pattern, options: options) == .orderedSame
                }
            }
            return candidate.range(of: pattern, options: options) != nil
        case .equals:
            if supportsKeywordTokens {
                return keywordTokens(from: candidate).contains {
                    $0.compare(pattern, options: options) == .orderedSame
                }
            }
            if supportsDayGroups, let dayMatch = dayGroupMatch(candidate: candidate, pattern: pattern) {
                return dayMatch
            }
            return candidate.compare(pattern, options: options) == .orderedSame
        case .beginsWith:
            return candidate.range(of: pattern, options: options.union(.anchored)) != nil
        case .endsWith:
            return candidate.range(of: pattern, options: options.union(.anchored).union(.backwards)) != nil
        case .like:
            let regex = wildcardRegex(for: pattern)
            let regexOptions: NSRegularExpression.Options = isCaseSensitive ? [] : [.caseInsensitive]
            guard let expression = try? NSRegularExpression(pattern: regex, options: regexOptions) else { return false }
            return expression.firstMatch(in: candidate, range: NSRange(candidate.startIndex..., in: candidate)) != nil
        case .isNot:
            if supportsKeywordTokens {
                return keywordTokens(from: candidate).allSatisfy {
                    $0.compare(pattern, options: options) != .orderedSame
                }
            }
            if supportsDayGroups, let dayMatch = dayGroupMatch(candidate: candidate, pattern: pattern) {
                return !dayMatch
            }
            return candidate.compare(pattern, options: options) != .orderedSame
        case .isBetween:
            guard let candidateMinute = clockMinute(candidate),
                  let range = clockRange(pattern) else { return false }
            if range.start <= range.end {
                return (range.start...range.end).contains(candidateMinute)
            }
            return candidateMinute >= range.start || candidateMinute <= range.end
        case .matchesRegex:
            let regexOptions: NSRegularExpression.Options = isCaseSensitive ? [] : [.caseInsensitive]
            guard let expression = try? NSRegularExpression(pattern: pattern, options: regexOptions) else { return false }
            return expression.firstMatch(in: candidate, range: NSRange(candidate.startIndex..., in: candidate)) != nil
        }
    }

    private func wildcardRegex(for pattern: String) -> String {
        var result = "^"
        for scalar in pattern.unicodeScalars {
            switch scalar {
            case "*": result += ".*"
            case "?": result += "."
            default: result += NSRegularExpression.escapedPattern(for: String(scalar))
            }
        }
        return result + "$"
    }

    private func clockMinute(_ value: String) -> Int? {
        let pieces = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard pieces.count == 2,
              let hour = Int(pieces[0]),
              let minute = Int(pieces[1]),
              (0..<24).contains(hour),
              (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    private func clockRange(_ value: String) -> (start: Int, end: Int)? {
        let normalized = value
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
        let pieces = normalized.split(separator: "-")
        guard pieces.count == 2,
              let start = clockMinute(String(pieces[0])),
              let end = clockMinute(String(pieces[1])) else { return nil }
        return (start, end)
    }

    private func dayGroupMatch(candidate: String, pattern: String) -> Bool? {
        let day = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let days = Set(["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"])
        guard days.contains(day) else { return nil }
        if value == "weekday" || value == "weekdays" {
            return !["saturday", "sunday"].contains(day)
        }
        if value == "weekend" || value == "weekends" {
            return ["saturday", "sunday"].contains(day)
        }
        return nil
    }

    private func keywordTokens(from value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (try exportArchiveData()).write(to: fileURL, options: .atomic)
        } catch {
            statusMessage = "Could not save filters · \(error.localizedDescription)"
        }
    }

    private static func defaultRootDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Metriday", isDirectory: true)
    }
}

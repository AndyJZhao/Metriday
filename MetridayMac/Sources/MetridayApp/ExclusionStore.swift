import Combine
import Foundation

enum ActivityExclusionField: String, CaseIterable, Codable, Identifiable {
    case application
    case bundleIdentifier
    case windowTitle
    case resource
    case domain
    case fullURL
    case device

    var id: Self { self }

    var label: String {
        switch self {
        case .application: return "Application"
        case .bundleIdentifier: return "Bundle identifier"
        case .windowTitle: return "Window title"
        case .resource: return "URL or path"
        case .domain: return "Domain"
        case .fullURL: return "Full website URL"
        case .device: return "Device"
        }
    }
}

struct ActivityExclusionRule: Identifiable, Hashable, Codable {
    let id: UUID
    var field: ActivityExclusionField
    var pattern: String
    var isCaseSensitive: Bool
    var comparison: ProjectRuleComparison

    init(
        id: UUID = UUID(),
        field: ActivityExclusionField,
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

struct ActivityExclusionArchive: Codable {
    let version: Int
    let rules: [ActivityExclusionRule]
}

@MainActor
final class ExclusionStore: ObservableObject {
    @Published private(set) var rules: [ActivityExclusionRule]
    @Published var statusMessage = "No exclusion rules"

    private let fileURL: URL

    init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? Self.defaultRootDirectory()
        self.fileURL = root.appendingPathComponent("Exclusions.json")
        self.rules = Self.loadRules(from: fileURL)
        updateStatus()
    }

    /// Compatibility projection for the original app-only exclusion model.
    /// Existing callers can still display and remove exact bundle-ID rules.
    var bundleIdentifiers: [String] {
        Array(Set(rules.compactMap { rule in
            guard rule.field == .bundleIdentifier,
                  rule.comparison == .equals else { return nil }
            return rule.pattern
        })).sorted()
    }

    func isExcluded(_ bundleIdentifier: String) -> Bool {
        isExcluded(
            appName: "",
            bundleIdentifier: bundleIdentifier,
            windowTitle: "",
            resource: "",
            deviceName: ""
        )
    }

    func isExcluded(
        appName: String,
        bundleIdentifier: String,
        windowTitle: String,
        resource: String,
        deviceName: String
    ) -> Bool {
        rules.contains { rule in
            matches(
                rule,
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                windowTitle: windowTitle,
                resource: resource,
                deviceName: deviceName
            )
        }
    }

    @discardableResult
    func add(bundleIdentifier: String) -> UUID? {
        addRule(
            field: .bundleIdentifier,
            pattern: bundleIdentifier,
            comparison: .equals
        )
    }

    @discardableResult
    func addRule(
        field: ActivityExclusionField,
        pattern rawPattern: String,
        isCaseSensitive: Bool = false,
        comparison: ProjectRuleComparison = .contains
    ) -> UUID? {
        let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return nil }
        if let existing = rules.first(where: {
            $0.field == field
                && $0.pattern == pattern
                && $0.isCaseSensitive == isCaseSensitive
                && $0.comparison == comparison
        }) {
            return existing.id
        }
        let rule = ActivityExclusionRule(
            field: field,
            pattern: pattern,
            isCaseSensitive: isCaseSensitive,
            comparison: comparison
        )
        rules.append(rule)
        persist()
        updateStatus()
        return rule.id
    }

    func remove(bundleIdentifier: String) {
        rules.removeAll {
            $0.field == .bundleIdentifier
                && $0.comparison == .equals
                && $0.pattern == bundleIdentifier
        }
        persist()
        updateStatus()
    }

    func remove(_ rule: ActivityExclusionRule) {
        rules.removeAll { $0.id == rule.id }
        persist()
        updateStatus()
    }

    func importBundleIdentifiers(_ imported: [String]) {
        for bundleIdentifier in imported {
            _ = add(bundleIdentifier: bundleIdentifier)
        }
        updateStatus()
    }

    func importRules(_ imported: [ActivityExclusionRule]) {
        for rule in imported {
            _ = addRule(
                field: rule.field,
                pattern: rule.pattern,
                isCaseSensitive: rule.isCaseSensitive,
                comparison: rule.comparison
            )
        }
        updateStatus()
    }

    func exportArchiveData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ActivityExclusionArchive(version: 1, rules: rules))
    }

    @discardableResult
    func importArchiveData(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        if let archive = try? decoder.decode(ActivityExclusionArchive.self, from: data) {
            let before = rules.count
            importRules(archive.rules)
            return max(0, rules.count - before)
        }

        // Archives written by the original app were a bare [String] of bundle IDs.
        let legacy = try decoder.decode([String].self, from: data)
        let before = rules.count
        importBundleIdentifiers(legacy)
        return max(0, rules.count - before)
    }

    private func matches(
        _ rule: ActivityExclusionRule,
        appName: String,
        bundleIdentifier: String,
        windowTitle: String,
        resource: String,
        deviceName: String
    ) -> Bool {
        let value: String
        switch rule.field {
        case .application: value = appName
        case .bundleIdentifier: value = bundleIdentifier
        case .windowTitle: value = windowTitle
        case .resource, .fullURL: value = resource
        case .domain: value = URL(string: resource)?.host ?? resource
        case .device: value = deviceName
        }
        return compare(value: value, rule: rule)
    }

    private func compare(value: String, rule: ActivityExclusionRule) -> Bool {
        let options: String.CompareOptions = rule.isCaseSensitive ? [] : [.caseInsensitive]
        switch rule.comparison {
        case .contains:
            return value.range(of: rule.pattern, options: options) != nil
        case .equals:
            return value.compare(rule.pattern, options: options) == .orderedSame
        case .beginsWith:
            return value.range(
                of: "^\(NSRegularExpression.escapedPattern(for: rule.pattern))",
                options: rule.isCaseSensitive ? [.regularExpression] : [.regularExpression, .caseInsensitive]
            ) != nil
        case .endsWith:
            return value.range(
                of: "\(NSRegularExpression.escapedPattern(for: rule.pattern))$",
                options: rule.isCaseSensitive ? [.regularExpression] : [.regularExpression, .caseInsensitive]
            ) != nil
        case .like:
            let pattern = NSRegularExpression.escapedPattern(for: rule.pattern)
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".")
            return regexMatches("^\(pattern)$", value: value, caseSensitive: rule.isCaseSensitive)
        case .isNot:
            return value.compare(rule.pattern, options: options) != .orderedSame
        case .matchesRegex:
            return regexMatches(rule.pattern, value: value, caseSensitive: rule.isCaseSensitive)
        }
    }

    private func regexMatches(_ pattern: String, value: String, caseSensitive: Bool) -> Bool {
        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return false
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regex.firstMatch(in: value, range: range) != nil
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try exportArchiveData().write(to: fileURL, options: .atomic)
        } catch {
            statusMessage = "Could not save exclusion rules"
        }
    }

    private func updateStatus() {
        statusMessage = rules.isEmpty
            ? "No exclusion rules"
            : "\(rules.count) exclusion rule\(rules.count == 1 ? "" : "s")"
    }

    private static func loadRules(from url: URL) -> [ActivityExclusionRule] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        if let archive = try? decoder.decode(ActivityExclusionArchive.self, from: data) {
            return archive.rules
        }
        guard let legacy = try? decoder.decode([String].self, from: data) else { return [] }
        return legacy.map {
            ActivityExclusionRule(field: .bundleIdentifier, pattern: $0, comparison: .equals)
        }
    }

    private static func defaultRootDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport.appendingPathComponent("Metriday", isDirectory: true)
    }
}

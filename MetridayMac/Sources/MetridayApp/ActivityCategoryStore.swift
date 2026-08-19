import Combine
import Foundation

enum ActivityCategoryRole: String, CaseIterable, Codable, Identifiable {
    case focused
    case distracting
    case other
    case idle

    var id: Self { self }

    var label: String {
        switch self {
        case .focused: return "Focused"
        case .distracting: return "Distracting"
        case .other: return "Other"
        case .idle: return "Idle"
        }
    }

    var defaultColor: ProjectColor {
        switch self {
        case .focused: return .blue
        case .distracting: return .red
        case .other, .idle: return .graphite
        }
    }

    var relevance: ActivityRelevance {
        switch self {
        case .focused: return .related
        case .distracting: return .distracted
        case .other: return .other
        case .idle: return .idle
        }
    }
}

struct ActivityCategoryDefinition: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var role: ActivityCategoryRole
    var color: ProjectColor
    var matchMode: ActivityFilterMatchMode
    var rules: [ActivityFilterRule]
    var isSystem: Bool
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        name: String,
        role: ActivityCategoryRole,
        color: ProjectColor? = nil,
        matchMode: ActivityFilterMatchMode = .any,
        rules: [ActivityFilterRule] = [],
        isSystem: Bool = false,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.color = color ?? role.defaultColor
        self.matchMode = matchMode
        self.rules = rules
        self.isSystem = isSystem
        self.isArchived = isArchived
    }

    var filterDefinition: ActivityFilterDefinition {
        ActivityFilterDefinition(
            id: id,
            name: name,
            color: color,
            matchMode: matchMode,
            rules: rules
        )
    }
}

struct ActivityCategoryArchive: Codable {
    let version: Int
    let categories: [ActivityCategoryDefinition]
}

@MainActor
final class ActivityCategoryStore: ObservableObject {
    @Published private(set) var categories: [ActivityCategoryDefinition]
    @Published var statusMessage = "Categories ready"

    private let fileURL: URL

    init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? Self.defaultRootDirectory()
        self.fileURL = root.appendingPathComponent("ActivityCategories.json")
        if let data = try? Data(contentsOf: fileURL),
           let archive = try? JSONDecoder().decode(ActivityCategoryArchive.self, from: data) {
            self.categories = archive.categories
        } else {
            self.categories = Self.defaultCategories
            persist()
        }
    }

    var activeCategories: [ActivityCategoryDefinition] {
        categories.filter { !$0.isArchived }
    }

    var customCategories: [ActivityCategoryDefinition] {
        activeCategories.filter { !$0.isSystem }
    }

    func category(
        for activity: ActivitySegment,
        filterStore: ActivityFilterStore,
        date: Date?
    ) -> ActivityCategoryDefinition {
        if let custom = customCategories.first(where: {
            filterStore.matches($0.filterDefinition, activity: activity, date: date)
        }) {
            return custom
        }

        return activeCategories.first(where: { $0.isSystem && $0.role.relevance == activity.relevance })
            ?? ActivityCategoryDefinition(
                name: activity.relevance == .related ? "Focused" : "Other",
                role: activity.relevance == .related ? .focused : .other,
                isSystem: true
            )
    }

    func applyingCategory(
        to activity: ActivitySegment,
        filterStore: ActivityFilterStore,
        date: Date?
    ) -> ActivitySegment {
        var resolved = activity
        resolved.relevance = category(for: activity, filterStore: filterStore, date: date).role.relevance
        return resolved
    }

    func applyingCategories(
        to activities: [ActivitySegment],
        filterStore: ActivityFilterStore,
        date: Date?
    ) -> [ActivitySegment] {
        activities.map { applyingCategory(to: $0, filterStore: filterStore, date: date) }
    }

    @discardableResult
    func createCategory(
        name rawName: String,
        role: ActivityCategoryRole,
        color: ProjectColor,
        matchMode: ActivityFilterMatchMode,
        rules: [ActivityFilterRule]
    ) -> UUID? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !rules.isEmpty else { return nil }
        let definition = ActivityCategoryDefinition(
            name: name,
            role: role,
            color: color,
            matchMode: matchMode,
            rules: normalizedRules(rules)
        )
        categories.append(definition)
        persist()
        statusMessage = "Category created · \(name)"
        return definition.id
    }

    func save(_ definition: ActivityCategoryDefinition) {
        let name = definition.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !definition.rules.isEmpty else { return }
        guard let index = categories.firstIndex(where: { $0.id == definition.id }), !categories[index].isSystem else {
            return
        }
        var updated = definition
        updated.name = name
        updated.rules = normalizedRules(definition.rules)
        categories[index] = updated
        persist()
        statusMessage = "Category updated · \(name)"
    }

    func archive(_ definition: ActivityCategoryDefinition) {
        guard let index = categories.firstIndex(where: { $0.id == definition.id }), !categories[index].isSystem else {
            return
        }
        categories[index].isArchived = true
        persist()
        statusMessage = "Category archived · \(definition.name)"
    }

    func exportArchiveData() throws -> Data {
        let archive = ActivityCategoryArchive(version: 1, categories: categories)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    private static var defaultCategories: [ActivityCategoryDefinition] {
        [
            ActivityCategoryDefinition(name: "Focused", role: .focused, color: .blue, isSystem: true),
            ActivityCategoryDefinition(name: "Distracting", role: .distracting, color: .red, isSystem: true),
            ActivityCategoryDefinition(name: "Other", role: .other, color: .graphite, isSystem: true),
            ActivityCategoryDefinition(name: "Idle", role: .idle, color: .graphite, isSystem: true)
        ]
    }

    private func normalizedRules(_ rules: [ActivityFilterRule]) -> [ActivityFilterRule] {
        var seen = Set<String>()
        return rules.filter { rule in
            let pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty else { return false }
            let key = "(rule.field.rawValue)|(rule.comparison.rawValue)|(rule.isCaseSensitive)|(pattern.lowercased())"
            guard seen.insert(key).inserted else { return false }
            return true
        }.map { rule in
            var normalized = rule
            normalized.pattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (try exportArchiveData()).write(to: fileURL, options: .atomic)
        } catch {
            statusMessage = "Could not save categories · \(error.localizedDescription)"
        }
    }

    private static func defaultRootDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Metriday", isDirectory: true)
    }
}

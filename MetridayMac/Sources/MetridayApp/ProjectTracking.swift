import Combine
import Foundation

enum ProjectColor: String, CaseIterable, Codable {
    case blue
    case green
    case orange
    case purple
    case red
    case graphite
}

/// A project's billing preference can either be explicit or inherit from its
/// parent. Time entries themselves continue to use `BillingStatus`; the
/// `automatic` value only exists at the project-default layer.
enum ProjectBillingStatus: String, CaseIterable, Codable, Identifiable {
    case automatic
    case billable
    case notBillable
    case pending
    case billed
    case paid

    var id: Self { self }

    var label: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .billable:
            return BillingStatus.billable.label
        case .notBillable:
            return BillingStatus.notBillable.label
        case .pending:
            return BillingStatus.pending.label
        case .billed:
            return BillingStatus.billed.label
        case .paid:
            return BillingStatus.paid.label
        }
    }

    var explicitStatus: BillingStatus? {
        switch self {
        case .automatic:
            return nil
        case .billable:
            return .billable
        case .notBillable:
            return .notBillable
        case .pending:
            return .pending
        case .billed:
            return .billed
        case .paid:
            return .paid
        }
    }
}

struct TrackingProject: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var color: ProjectColor
    var parentID: UUID?
    var teamID: UUID?
    var productivity: Int
    var isArchived: Bool
    var notes: String
    var defaultBillingStatus: ProjectBillingStatus
    var customFields: [String: String]
    var billingRate: Double {
        didSet { billingRate = max(0, billingRate) }
    }
    var currency: String {
        didSet {
            let normalized = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            currency = normalized.isEmpty ? "USD" : normalized
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        color: ProjectColor = .blue,
        parentID: UUID? = nil,
        teamID: UUID? = nil,
        productivity: Int = 0,
        isArchived: Bool = false,
        notes: String = "",
        defaultBillingStatus: ProjectBillingStatus = .automatic,
        billingRate: Double = 0,
        currency: String = "USD",
        customFields: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.parentID = parentID
        self.teamID = teamID
        self.productivity = min(100, max(-100, productivity))
        self.isArchived = isArchived
        self.notes = notes
        self.defaultBillingStatus = defaultBillingStatus
        self.billingRate = max(0, billingRate)
        self.currency = currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "USD"
            : currency.uppercased()
        self.customFields = customFields
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, color, parentID, teamID, productivity, isArchived, notes, defaultBillingStatus, billingRate, currency, customFields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decode(ProjectColor.self, forKey: .color)
        parentID = try container.decodeIfPresent(UUID.self, forKey: .parentID)
        teamID = try container.decodeIfPresent(UUID.self, forKey: .teamID)
        productivity = min(100, max(-100, try container.decodeIfPresent(Int.self, forKey: .productivity) ?? 0))
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        defaultBillingStatus = try container.decodeIfPresent(ProjectBillingStatus.self, forKey: .defaultBillingStatus) ?? .automatic
        billingRate = max(0, try container.decodeIfPresent(Double.self, forKey: .billingRate) ?? 0)
        customFields = try container.decodeIfPresent([String: String].self, forKey: .customFields) ?? [:]
        currency = (try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if currency.isEmpty { currency = "USD" }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(color, forKey: .color)
        try container.encodeIfPresent(parentID, forKey: .parentID)
        try container.encodeIfPresent(teamID, forKey: .teamID)
        try container.encode(productivity, forKey: .productivity)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(notes, forKey: .notes)
        try container.encode(defaultBillingStatus, forKey: .defaultBillingStatus)
        try container.encode(billingRate, forKey: .billingRate)
        try container.encode(currency, forKey: .currency)
        try container.encode(customFields, forKey: .customFields)
    }
}

enum ProjectRuleField: String, CaseIterable, Codable, Identifiable {
    case application
    case bundleIdentifier
    case titleContains
    case resourceContains
    case domain
    case fullURL
    case keyword
    case startTime
    case dayOfWeek

    var id: Self { self }

    var label: String {
        switch self {
        case .application:
            return "Application"
        case .bundleIdentifier:
            return "Bundle identifier"
        case .titleContains:
            return "Title contains"
        case .resourceContains:
            return "URL or path contains"
        case .domain:
            return "Domain"
        case .fullURL:
            return "Full website URL"
        case .keyword:
            return "Keyword"
        case .startTime:
            return "Start time"
        case .dayOfWeek:
            return "Day of week"
        }
    }
}

enum ProjectRuleComparison: String, CaseIterable, Codable, Identifiable {
    case contains
    case equals
    case beginsWith
    case endsWith
    case like
    case isNot
    case matchesRegex

    var id: Self { self }

    var label: String {
        switch self {
        case .contains:
            return "contains"
        case .equals:
            return "is"
        case .beginsWith:
            return "begins with"
        case .endsWith:
            return "ends with"
        case .like:
            return "is like"
        case .isNot:
            return "is not"
        case .matchesRegex:
            return "matches regex"
        }
    }
}

struct ProjectRule: Identifiable, Hashable, Codable {
    let id: UUID
    var projectID: UUID
    var field: ProjectRuleField
    var pattern: String
    var isCaseSensitive: Bool
    var comparison: ProjectRuleComparison

    init(
        id: UUID = UUID(),
        projectID: UUID,
        field: ProjectRuleField,
        pattern: String,
        isCaseSensitive: Bool = false,
        comparison: ProjectRuleComparison = .contains
    ) {
        self.id = id
        self.projectID = projectID
        self.field = field
        self.pattern = pattern
        self.isCaseSensitive = isCaseSensitive
        self.comparison = comparison
    }

    private enum CodingKeys: String, CodingKey {
        case id, projectID, field, pattern, isCaseSensitive, comparison
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectID = try container.decode(UUID.self, forKey: .projectID)
        field = try container.decode(ProjectRuleField.self, forKey: .field)
        pattern = try container.decode(String.self, forKey: .pattern)
        isCaseSensitive = try container.decodeIfPresent(Bool.self, forKey: .isCaseSensitive) ?? false
        comparison = try container.decodeIfPresent(ProjectRuleComparison.self, forKey: .comparison) ?? .contains
    }
}

struct ProjectArchive: Codable {
    let version: Int
    let projects: [TrackingProject]
    let rules: [ProjectRule]
}

func resolvedProjectBillingStatus(
    for projectID: UUID?,
    in projects: [TrackingProject],
    fallback: BillingStatus = .billable
) -> BillingStatus {
    var currentID = projectID
    var visited: Set<UUID> = []
    while let id = currentID,
          visited.insert(id).inserted,
          let project = projects.first(where: { $0.id == id }) {
        if let explicitStatus = project.defaultBillingStatus.explicitStatus {
            return explicitStatus
        }
        currentID = project.parentID
    }
    return fallback
}

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [TrackingProject]
    @Published private(set) var rules: [ProjectRule]
    @Published var statusMessage = "Projects ready"

    private let fileURL: URL

    init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? Self.defaultRootDirectory()
        self.fileURL = root.appendingPathComponent("Projects.json")

        if let data = try? Data(contentsOf: fileURL),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            self.projects = payload.projects
            self.rules = payload.rules
        } else {
            self.projects = Self.seedProjects()
            self.rules = []
            persist()
        }
    }

    var activeProjects: [TrackingProject] {
        projects.filter { !$0.isArchived }
    }

    var archivedProjects: [TrackingProject] {
        projects.filter(\.isArchived)
    }

    func childProjects(of parentID: UUID?) -> [TrackingProject] {
        activeProjects.filter { $0.parentID == parentID }
    }

    /// Returns the selected project plus every active descendant. Selecting a
    /// parent in Activities, Stats, or Reports scopes the whole project tree.
    func descendantProjectIDs(including projectID: UUID) -> Set<UUID> {
        var ids: Set<UUID> = [projectID]
        var pending = [projectID]
        while let parentID = pending.popLast() {
            for child in activeProjects where child.parentID == parentID && ids.insert(child.id).inserted {
                pending.append(child.id)
            }
        }
        return ids
    }

    /// Returns active projects that can safely become the parent of a project.
    /// Excluding descendants prevents hierarchy cycles, which would otherwise
    /// make report paths and project navigation ambiguous.
    func validParentProjects(for projectID: UUID) -> [TrackingProject] {
        let descendants = descendantProjectIDs(including: projectID)
        return activeProjects.filter {
            $0.id != projectID && !descendants.contains($0.id)
        }
    }

    func project(_ id: UUID?) -> TrackingProject? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    /// Resolve a project's billing preference exactly once at entry creation
    /// time. Automatic defaults inherit through the project hierarchy and
    /// finally use the local global fallback, Billable.
    func resolvedBillingStatus(for projectID: UUID?) -> BillingStatus {
        resolvedProjectBillingStatus(for: projectID, in: projects)
    }

    func name(for id: UUID?) -> String {
        project(id)?.name ?? "Unassigned"
    }

    func hierarchyPath(for id: UUID?) -> String {
        guard let id, let current = project(id) else { return "Unassigned" }
        var names = [current.name]
        var parentID = current.parentID
        var visited: Set<UUID> = [id]
        while let currentParentID = parentID,
              !visited.contains(currentParentID),
              let parent = project(currentParentID) {
            names.insert(parent.name, at: 0)
            visited.insert(currentParentID)
            parentID = parent.parentID
        }
        return names.joined(separator: " > ")
    }

    @discardableResult
    func createProject(
        name rawName: String,
        color: ProjectColor = .blue,
        parentID: UUID? = nil,
        teamID: UUID? = nil
    ) -> UUID? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let validParentID = parentID.flatMap { candidateID in
            activeProjects.contains(where: { $0.id == candidateID }) ? candidateID : nil
        }
        let project = TrackingProject(name: name, color: color, parentID: validParentID, teamID: teamID)
        projects.append(project)
        persist()
        statusMessage = "Project created · \(name)"
        return project.id
    }

    func updateProject(_ project: TrackingProject) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        var updated = project
        var removedInvalidParent = false
        if let parentID = updated.parentID,
           parentID == updated.id || !validParentProjects(for: updated.id).contains(where: { $0.id == parentID }) {
            updated.parentID = nil
            removedInvalidParent = true
        }
        projects[index] = updated
        persist()
        statusMessage = removedInvalidParent
            ? "Invalid parent removed · \(updated.name)"
            : "Project updated · \(updated.name)"
    }

    func archive(_ project: TrackingProject) {
        var updated = project
        updated.isArchived = true
        updateProject(updated)
        statusMessage = "Project archived · \(project.name)"
    }

    func restore(_ project: TrackingProject) {
        guard project.isArchived else { return }
        var updated = project
        updated.isArchived = false
        if let parentID = updated.parentID,
           !activeProjects.contains(where: { $0.id == parentID }) {
            updated.parentID = nil
        }
        updateProject(updated)
        statusMessage = "Project restored · \(project.name)"
    }

    @discardableResult
    func addRule(
        projectID: UUID,
        field: ProjectRuleField,
        pattern rawPattern: String,
        isCaseSensitive: Bool = false,
        comparison: ProjectRuleComparison = .contains
    ) -> UUID? {
        let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard project(projectID) != nil, !pattern.isEmpty else { return nil }
        guard !rules.contains(where: {
            $0.projectID == projectID
                && $0.field == field
                && $0.pattern.caseInsensitiveCompare(pattern) == .orderedSame
                && $0.isCaseSensitive == isCaseSensitive
                && $0.comparison == comparison
        }) else {
            return rules.first(where: {
                $0.projectID == projectID
                    && $0.field == field
                    && $0.pattern.caseInsensitiveCompare(pattern) == .orderedSame
                    && $0.isCaseSensitive == isCaseSensitive
                    && $0.comparison == comparison
            })?.id
        }
        let rule = ProjectRule(
            projectID: projectID,
            field: field,
            pattern: pattern,
            isCaseSensitive: isCaseSensitive,
            comparison: comparison
        )
        rules.append(rule)
        persist()
        statusMessage = "Rule added · \(pattern)"
        return rule.id
    }

    /// Adds the two rules Timing offers when a new project is created: future
    /// activity whose title or resource path contains the project name is
    /// assigned to that project.
    @discardableResult
    func addDefaultNameRules(projectID: UUID, projectName rawName: String) -> Int {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return 0 }
        let fields: [ProjectRuleField] = [.titleContains, .resourceContains]
        return fields.compactMap { field in
            addRule(
                projectID: projectID,
                field: field,
                pattern: name,
                comparison: .contains
            )
        }.count
    }

    func removeRule(_ rule: ProjectRule) {
        rules.removeAll { $0.id == rule.id }
        persist()
        statusMessage = "Rule removed"
    }

    func moveRule(_ rule: ProjectRule, by offset: Int) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        let destination = index + offset
        guard rules.indices.contains(destination) else { return }
        rules.swapAt(index, destination)
        persist()
        statusMessage = "Rule priority updated"
    }

    func rules(for projectID: UUID) -> [ProjectRule] {
        rules.filter { $0.projectID == projectID }
    }

    func exportArchiveData() throws -> Data {
        let archive = ProjectArchive(version: 1, projects: projects, rules: rules)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    @discardableResult
    func importArchiveData(_ data: Data) throws -> (projects: Int, rules: Int) {
        let decoder = JSONDecoder()
        let archive = try decoder.decode(ProjectArchive.self, from: data)
        let result = mergeArchive(archive)
        return (result.projects, result.rules)
    }

    /// Merges a project archive and returns the mapping from the archive's
    /// project IDs to this store's IDs. Sync uses that mapping to keep time
    /// entries and activity assignments attached to their projects even when
    /// two Macs created the same hierarchy independently.
    @discardableResult
    func mergeArchive(_ archive: ProjectArchive) -> (projects: Int, rules: Int, idMap: [UUID: UUID]) {
        var remaining = archive.projects
        var idMap: [UUID: UUID] = [:]
        var importedProjects = 0

        while !remaining.isEmpty {
            let readyIndex = remaining.firstIndex { candidate in
                guard let parentID = candidate.parentID else { return true }
                return idMap[parentID] != nil
            }
            let isFallback = readyIndex == nil
            let index = readyIndex ?? remaining.startIndex
            let candidate = remaining.remove(at: index)
            let targetParentID = isFallback ? nil : candidate.parentID.flatMap { idMap[$0] }
            let existing = projects.first {
                $0.parentID == targetParentID
                    && $0.name.caseInsensitiveCompare(candidate.name) == .orderedSame
            }
            let targetID = existing?.id ?? (projects.contains { $0.id == candidate.id } ? UUID() : candidate.id)
            let imported = TrackingProject(
                id: targetID,
                name: candidate.name,
                color: candidate.color,
                parentID: targetParentID,
                teamID: candidate.teamID,
                productivity: candidate.productivity,
                isArchived: candidate.isArchived,
                notes: candidate.notes,
                defaultBillingStatus: candidate.defaultBillingStatus,
                billingRate: candidate.billingRate,
                currency: candidate.currency,
                customFields: candidate.customFields
            )
            if let existingIndex = projects.firstIndex(where: { $0.id == targetID }) {
                projects[existingIndex] = imported
            } else {
                projects.append(imported)
                importedProjects += 1
            }
            idMap[candidate.id] = targetID
        }

        var importedRules = 0
        for rule in archive.rules {
            guard let targetProjectID = idMap[rule.projectID], project(targetProjectID) != nil else { continue }
            let duplicate = rules.contains {
                $0.projectID == targetProjectID
                    && $0.field == rule.field
                    && $0.pattern.caseInsensitiveCompare(rule.pattern) == .orderedSame
                    && $0.isCaseSensitive == rule.isCaseSensitive
                    && $0.comparison == rule.comparison
            }
            guard !duplicate else { continue }
            let ruleID = rules.contains { $0.id == rule.id } ? UUID() : rule.id
            rules.append(ProjectRule(
                id: ruleID,
                projectID: targetProjectID,
                field: rule.field,
                pattern: rule.pattern,
                isCaseSensitive: rule.isCaseSensitive,
                comparison: rule.comparison
            ))
            importedRules += 1
        }
        persist()
        statusMessage = "Imported \(importedProjects) projects and \(importedRules) rules"
        return (importedProjects, importedRules, idMap)
    }

    func matchingProjectID(for activity: ActivitySegment, date: Date? = nil) -> UUID? {
        for rule in rules {
            guard let project = project(rule.projectID), !project.isArchived else { continue }
            if matches(rule: rule, activity: activity, date: date) {
                return project.id
            }
        }
        return nil
    }

    func matchingRule(for activity: ActivitySegment, date: Date? = nil) -> ProjectRule? {
        guard let projectID = matchingProjectID(for: activity, date: date) else { return nil }
        return rules.first { $0.projectID == projectID && matches(rule: $0, activity: activity, date: date) }
    }

    private func matches(rule: ProjectRule, activity: ActivitySegment, date: Date?) -> Bool {
        let candidate: String
        switch rule.field {
        case .application:
            candidate = activity.appName
        case .bundleIdentifier:
            candidate = activity.bundleIdentifier
        case .titleContains:
            candidate = activity.windowTitle
        case .resourceContains:
            candidate = activity.resource
        case .domain:
            candidate = URL(string: activity.resource)?.host ?? ""
        case .fullURL:
            candidate = activity.resource
        case .keyword:
            candidate = "\(activity.windowTitle) \(activity.resource)"
        case .startTime:
            candidate = String(format: "%02d:%02d", activity.startMinute / 60, activity.startMinute % 60)
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
            return matchesLogicalExpression(
                candidate: candidate,
                expression: rule.pattern,
                comparison: rule.comparison,
                options: options
            )
        }
        return matchesAtom(
            candidate: candidate,
            pattern: rule.pattern,
            comparison: rule.comparison,
            options: options,
            isCaseSensitive: rule.isCaseSensitive
        )
    }

    private func matchesLogicalExpression(
        candidate: String,
        expression: String,
        comparison: ProjectRuleComparison,
        options: String.CompareOptions
    ) -> Bool {
        expression
            .components(separatedBy: "||")
            .contains { orBranch in
                orBranch
                    .components(separatedBy: "&&")
                    .allSatisfy { atom in
                        let pattern = atom.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !pattern.isEmpty else { return false }
                        return matchesAtom(
                            candidate: candidate,
                            pattern: pattern,
                            comparison: comparison,
                            options: options,
                            isCaseSensitive: options.isEmpty
                        )
                    }
            }
    }

    private func matchesAtom(
        candidate: String,
        pattern: String,
        comparison: ProjectRuleComparison,
        options: String.CompareOptions,
        isCaseSensitive: Bool
    ) -> Bool {
        switch comparison {
        case .contains:
            return candidate.range(of: pattern, options: options) != nil
        case .equals:
            return candidate.compare(pattern, options: options) == .orderedSame
        case .beginsWith:
            return candidate.range(of: pattern, options: options.union(.anchored)) != nil
        case .endsWith:
            return candidate.range(of: pattern, options: options.union(.anchored).union(.backwards)) != nil
        case .like:
            let regex = wildcardRegex(for: pattern)
            let regexOptions: NSRegularExpression.Options = isCaseSensitive ? [] : [.caseInsensitive]
            guard let expression = try? NSRegularExpression(pattern: regex, options: regexOptions) else {
                return false
            }
            return expression.firstMatch(in: candidate, range: NSRange(candidate.startIndex..., in: candidate)) != nil
        case .isNot:
            return candidate.compare(pattern, options: options) != .orderedSame
        case .matchesRegex:
            let regexOptions: NSRegularExpression.Options = isCaseSensitive ? [] : [.caseInsensitive]
            guard let expression = try? NSRegularExpression(pattern: pattern, options: regexOptions) else {
                return false
            }
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

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let payload = Payload(projects: projects, rules: rules)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(payload).write(to: fileURL, options: .atomic)
        } catch {
            statusMessage = "Could not save projects: \(error.localizedDescription)"
        }
    }

    private static func seedProjects() -> [TrackingProject] {
        [
            TrackingProject(name: "Research", color: .blue, productivity: 80),
            TrackingProject(name: "Writing", color: .purple, productivity: 70),
            TrackingProject(name: "Communication", color: .orange, productivity: 20),
            TrackingProject(name: "Personal", color: .graphite, productivity: 0)
        ]
    }

    private static func defaultRootDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport.appendingPathComponent("Metriday", isDirectory: true)
    }

    private struct Payload: Codable {
        let projects: [TrackingProject]
        let rules: [ProjectRule]
    }
}

import Combine
import Foundation

struct TeamMember: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var email: String
    var role: String
    var isActive: Bool

    init(
        id: UUID = UUID(),
        name: String,
        email: String = "",
        role: String = "member",
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.role = role
        self.isActive = isActive
    }
}

struct MetridayTeam: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var members: [TeamMember]
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        name: String,
        members: [TeamMember] = [],
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.members = members
        self.isArchived = isArchived
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, members, isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        members = try container.decodeIfPresent([TeamMember].self, forKey: .members) ?? []
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}

struct TeamArchive: Codable {
    let version: Int
    let teams: [MetridayTeam]
}

@MainActor
final class TeamStore: ObservableObject {
    @Published private(set) var teams: [MetridayTeam]
    @Published var statusMessage = "Teams ready"

    let currentMemberID: UUID

    private let fileURL: URL
    private let identityURL: URL

    init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? Self.defaultRootDirectory()
        self.fileURL = root.appendingPathComponent("Teams.json")
        self.identityURL = root.appendingPathComponent("TeamIdentity.json")

        if let data = try? Data(contentsOf: fileURL),
           let payload = try? JSONDecoder().decode(TeamArchive.self, from: data) {
            self.teams = payload.teams
        } else {
            self.teams = []
        }
        if let data = try? Data(contentsOf: identityURL),
           let identity = try? JSONDecoder().decode(TeamIdentity.self, from: data) {
            self.currentMemberID = identity.id
        } else {
            self.currentMemberID = UUID()
            persistIdentity()
        }
    }

    var activeTeams: [MetridayTeam] {
        teams.filter { !$0.isArchived }
    }

    func team(_ id: UUID?) -> MetridayTeam? {
        guard let id else { return nil }
        return teams.first { $0.id == id }
    }

    func members(of teamID: UUID) -> [TeamMember] {
        team(teamID)?.members.filter(\.isActive) ?? []
    }

    @discardableResult
    func createTeam(name rawName: String) -> UUID? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        guard !activeTeams.contains(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            statusMessage = "A team with that name already exists"
            return nil
        }
        let owner = TeamMember(
            id: currentMemberID,
            name: NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (Host.current().localizedName ?? "This Mac")
                : NSFullUserName(),
            email: "",
            role: "owner"
        )
        let team = MetridayTeam(name: name, members: [owner])
        teams.append(team)
        persist()
        statusMessage = "Team created · \(name)"
        return team.id
    }

    @discardableResult
    func addMember(
        to teamID: UUID,
        name rawName: String,
        email rawEmail: String
    ) -> UUID? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty, let index = teams.firstIndex(where: { $0.id == teamID }) else {
            return nil
        }
        guard !teams[index].members.contains(where: {
            (!email.isEmpty && $0.email.caseInsensitiveCompare(email) == .orderedSame)
                || $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            statusMessage = "That team member already exists"
            return nil
        }
        let member = TeamMember(name: name, email: email)
        teams[index].members.append(member)
        persist()
        statusMessage = "Member added · \(name)"
        return member.id
    }

    func removeMember(_ memberID: UUID, from teamID: UUID) {
        guard let index = teams.firstIndex(where: { $0.id == teamID }) else { return }
        guard teams[index].members.contains(where: { $0.id == memberID && $0.id != currentMemberID }) else {
            return
        }
        teams[index].members.removeAll { $0.id == memberID }
        persist()
        statusMessage = "Team member removed"
    }

    func archive(_ team: MetridayTeam) {
        guard let index = teams.firstIndex(where: { $0.id == team.id }) else { return }
        teams[index].isArchived = true
        persist()
        statusMessage = "Team archived · \(team.name)"
    }

    func exportArchiveData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(TeamArchive(version: 1, teams: teams))
    }

    @discardableResult
    func importArchiveData(_ data: Data) throws -> Int {
        let archive = try JSONDecoder().decode(TeamArchive.self, from: data)
        return mergeArchive(archive).imported
    }

    @discardableResult
    func mergeArchive(_ archive: TeamArchive) -> (imported: Int, idMap: [UUID: UUID]) {
        var imported = 0
        var idMap: [UUID: UUID] = [:]
        for candidate in archive.teams {
            let existingIndex = teams.firstIndex {
                $0.name.caseInsensitiveCompare(candidate.name) == .orderedSame
            }
            let targetID: UUID
            if let existingIndex {
                targetID = teams[existingIndex].id
                var merged = teams[existingIndex]
                merged.isArchived = candidate.isArchived
                for member in candidate.members where !merged.members.contains(where: {
                    ($0.id == member.id)
                        || (!member.email.isEmpty && $0.email.caseInsensitiveCompare(member.email) == .orderedSame)
                }) {
                    merged.members.append(member)
                }
                teams[existingIndex] = merged
            } else {
                targetID = teams.contains(where: { $0.id == candidate.id }) ? UUID() : candidate.id
                var importedTeam = candidate
                importedTeam = MetridayTeam(
                    id: targetID,
                    name: candidate.name,
                    members: candidate.members,
                    isArchived: candidate.isArchived
                )
                teams.append(importedTeam)
                imported += 1
            }
            idMap[candidate.id] = targetID
        }
        persist()
        statusMessage = "Imported \(imported) teams"
        return (imported, idMap)
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(TeamArchive(version: 1, teams: teams)).write(to: fileURL, options: .atomic)
        } catch {
            statusMessage = "Could not save teams"
        }
    }

    private func persistIdentity() {
        do {
            try FileManager.default.createDirectory(
                at: identityURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            try encoder.encode(TeamIdentity(id: currentMemberID)).write(to: identityURL, options: .atomic)
        } catch {
            statusMessage = "Could not save team identity"
        }
    }

    private static func defaultRootDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport.appendingPathComponent("Metriday", isDirectory: true)
    }

    private struct TeamIdentity: Codable {
        let id: UUID
    }
}

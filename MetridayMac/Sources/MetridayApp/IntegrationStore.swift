import Combine
import Foundation
import Security

enum ExternalIntegrationProvider: String, CaseIterable, Codable, Identifiable {
    case clickUp
    case linear
    case clio

    var id: Self { self }

    var title: String {
        switch self {
        case .clickUp: return "ClickUp"
        case .linear: return "Linear"
        case .clio: return "Clio"
        }
    }

    var subtitle: String {
        switch self {
        case .clickUp: return "Import tasks from a ClickUp list"
        case .linear: return "Import issues from Linear"
        case .clio: return "Import matters from Clio Manage"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .clickUp: return "https://api.clickup.com/api/v2"
        case .linear: return "https://api.linear.app/graphql"
        case .clio: return "https://app.clio.com/api/v4"
        }
    }

    var tokenHint: String {
        switch self {
        case .clickUp: return "Personal API token"
        case .linear: return "Personal API key or OAuth token"
        case .clio: return "OAuth access token"
        }
    }
}

struct ExternalIntegrationConfiguration: Codable, Identifiable {
    let provider: ExternalIntegrationProvider
    var workspace: String
    var endpoint: String
    var connected: Bool
    var lastSyncAt: Date?
    var statusMessage: String
    /// Optional so settings saved by earlier builds continue to decode.
    var lastSyncConflictCount: Int?
    var lastSyncSummary: String?

    var id: ExternalIntegrationProvider { provider }
}

enum IntegrationSyncState: String, Codable {
    case synced
    case imported
    case localChangesPushed
    case remoteChangesApplied
    case conflict
    case remoteMissing
}

struct IntegrationLink: Codable, Identifiable, Hashable {
    let id: UUID
    let provider: ExternalIntegrationProvider
    let externalID: String
    var localProjectID: UUID
    var remoteTitle: String
    var remoteNotes: String
    var remoteStatus: String
    var remoteURL: String
    var remoteVersion: String?
    var syncedLocalTitle: String
    var syncedLocalNotes: String
    var syncedLocalStatus: String
    var lastSyncedAt: Date?
    var state: IntegrationSyncState

    init(
        id: UUID = UUID(),
        provider: ExternalIntegrationProvider,
        externalID: String,
        localProjectID: UUID,
        remoteTitle: String,
        remoteNotes: String,
        remoteStatus: String,
        remoteURL: String,
        remoteVersion: String? = nil,
        syncedLocalTitle: String,
        syncedLocalNotes: String,
        syncedLocalStatus: String,
        lastSyncedAt: Date? = .now,
        state: IntegrationSyncState = .synced
    ) {
        self.id = id
        self.provider = provider
        self.externalID = externalID
        self.localProjectID = localProjectID
        self.remoteTitle = remoteTitle
        self.remoteNotes = remoteNotes
        self.remoteStatus = remoteStatus
        self.remoteURL = remoteURL
        self.remoteVersion = remoteVersion
        self.syncedLocalTitle = syncedLocalTitle
        self.syncedLocalNotes = syncedLocalNotes
        self.syncedLocalStatus = syncedLocalStatus
        self.lastSyncedAt = lastSyncedAt
        self.state = state
    }
}

struct IntegrationSyncResult: Hashable {
    let provider: ExternalIntegrationProvider
    let imported: Int
    let updatedLocal: Int
    let pushedRemote: Int
    let conflicts: Int
    let remoteMissing: Int
    let unchanged: Int
    let completedAt: Date

    var message: String {
        var parts = [
            "\(imported) imported",
            "\(updatedLocal) pulled",
            "\(pushedRemote) pushed",
            "\(unchanged) unchanged"
        ]
        if conflicts > 0 { parts.append("\(conflicts) conflict\(conflicts == 1 ? "" : "s")") }
        if remoteMissing > 0 { parts.append("\(remoteMissing) remote item\(remoteMissing == 1 ? "" : "s") missing") }
        return parts.joined(separator: " · ")
    }
}

struct ExternalTask: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let notes: String
    let url: String
    let status: String
    let remoteVersion: String?
}

@MainActor
final class IntegrationStore: ObservableObject {
    @Published private(set) var configurations: [ExternalIntegrationConfiguration]
    @Published private(set) var links: [IntegrationLink]
    @Published private(set) var isWorking = false
    @Published private(set) var statusMessage = "Integrations are local and disconnected"

    private let settingsURL: URL
    private let linksURL: URL
    private let keychainService = "com.metriday.integrations"

    init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? Self.defaultRootDirectory()
        self.settingsURL = root.appendingPathComponent("Integrations.json")
        self.linksURL = root.appendingPathComponent("IntegrationLinks.json")
        let saved = Self.loadSettings(from: settingsURL)
        self.links = Self.loadLinks(from: linksURL)
        self.configurations = ExternalIntegrationProvider.allCases.map { provider in
            saved.first(where: { $0.provider == provider })
                ?? ExternalIntegrationConfiguration(
                    provider: provider,
                    workspace: "",
                    endpoint: provider.defaultEndpoint,
                    connected: false,
                    lastSyncAt: nil,
                    statusMessage: "Not configured",
                    lastSyncConflictCount: nil,
                    lastSyncSummary: nil
                )
        }
    }

    func configuration(for provider: ExternalIntegrationProvider) -> ExternalIntegrationConfiguration {
        configurations.first(where: { $0.provider == provider })!
    }

    func token(for provider: ExternalIntegrationProvider) -> String {
        KeychainValue.read(service: keychainService, account: provider.rawValue) ?? ""
    }

    func setConfiguration(
        provider: ExternalIntegrationProvider,
        workspace: String,
        endpoint: String,
        token: String
    ) {
        var updated = configuration(for: provider)
        updated.workspace = workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? provider.defaultEndpoint
            : endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.connected = !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        updated.statusMessage = updated.connected ? "Configured · test connection to verify" : "Not configured"
        replace(updated)
        if updated.connected {
            KeychainValue.save(
                token,
                service: keychainService,
                account: provider.rawValue
            )
        } else {
            KeychainValue.delete(service: keychainService, account: provider.rawValue)
        }
        persist()
    }

    func disconnect(_ provider: ExternalIntegrationProvider) {
        var updated = configuration(for: provider)
        updated.connected = false
        updated.statusMessage = "Not configured"
        updated.lastSyncAt = nil
        replace(updated)
        KeychainValue.delete(service: keychainService, account: provider.rawValue)
        persist()
        links.removeAll { $0.provider == provider }
        persistLinks()
        statusMessage = "\(provider.title) disconnected"
    }

    func testConnection(_ provider: ExternalIntegrationProvider) async {
        guard let request = makeRequest(for: provider, testOnly: true) else {
            updateStatus(provider, message: "Enter a token and the required workspace/list ID")
            return
        }
        isWorking = true
        updateStatus(provider, message: "Testing connection…")
        defer { isWorking = false }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw IntegrationError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                throw IntegrationError.http(statusCode: http.statusCode, body: responseMessage(from: data))
            }
            var updated = configuration(for: provider)
            updated.connected = true
            updated.statusMessage = "Connected"
            replace(updated)
            persist()
            statusMessage = "\(provider.title) connection verified"
        } catch {
            updateStatus(provider, message: message(for: error))
            statusMessage = "\(provider.title) connection failed"
        }
    }

    func importProjects(
        from provider: ExternalIntegrationProvider,
        into projectStore: ProjectStore
    ) async -> Int {
        guard let request = makeRequest(for: provider, testOnly: false) else {
            updateStatus(provider, message: "Enter a token and the required workspace/list ID")
            return 0
        }
        isWorking = true
        updateStatus(provider, message: "Loading \(provider.title) items…")
        defer { isWorking = false }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw IntegrationError.invalidResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                throw IntegrationError.http(statusCode: http.statusCode, body: responseMessage(from: data))
            }
            let tasks = try parseTasks(data, provider: provider)
            let imported = importTasks(tasks, provider: provider, into: projectStore)
            var updated = configuration(for: provider)
            updated.connected = true
            updated.lastSyncAt = .now
            updated.statusMessage = "Imported \(imported) project\(imported == 1 ? "" : "s")"
            updated.lastSyncConflictCount = 0
            updated.lastSyncSummary = updated.statusMessage
            replace(updated)
            persist()
            statusMessage = "Imported \(imported) \(provider.title) project\(imported == 1 ? "" : "s")"
            return imported
        } catch {
            updateStatus(provider, message: message(for: error))
            statusMessage = "\(provider.title) import failed"
            return 0
        }
    }

    /// Pulls the provider's current items, compares them with the last
    /// successfully synchronized snapshot, and only writes when one side has
    /// changed. If both sides changed, the project is left untouched and the
    /// link is marked as a conflict for explicit user resolution.
    func syncProjects(
        from provider: ExternalIntegrationProvider,
        with projectStore: ProjectStore
    ) async -> IntegrationSyncResult? {
        guard makeRequest(for: provider, testOnly: false) != nil else {
            updateStatus(provider, message: "Enter a token and the required workspace/list ID")
            return nil
        }
        isWorking = true
        updateStatus(provider, message: "Syncing \(provider.title) changes…")
        defer { isWorking = false }

        do {
            let tasks = try await fetchTasks(for: provider)
            var imported = 0
            var updatedLocal = 0
            var pushedRemote = 0
            var conflicts = 0
            var remoteMissing = 0
            var unchanged = 0
            var seenExternalIDs = Set<String>()

            for task in tasks {
                seenExternalIDs.insert(task.id)
                let existing = projectStore.activeProjects.first {
                    $0.customFields["integration_provider"] == provider.rawValue
                        && $0.customFields["integration_id"] == task.id
                }

                guard let existing else {
                    guard let localProjectID = createLinkedProject(
                        task,
                        provider: provider,
                        into: projectStore
                    ), let localProject = projectStore.project(localProjectID) else { continue }
                    upsertLink(makeLink(
                        provider: provider,
                        task: task,
                        project: localProject,
                        state: .imported
                    ))
                    imported += 1
                    continue
                }

                let existingLink = link(for: provider, externalID: task.id)
                    ?? legacyLink(for: provider, task: task, project: existing)
                guard let baseline = existingLink else { continue }

                let localStatus = existing.customFields["integration_status"] ?? ""
                let localChanged = existing.name != baseline.syncedLocalTitle
                    || existing.notes != baseline.syncedLocalNotes
                    || localStatus != baseline.syncedLocalStatus
                let remoteChanged = task.title != baseline.remoteTitle
                    || task.notes != baseline.remoteNotes
                    || task.status != baseline.remoteStatus
                    || task.url != baseline.remoteURL
                    || task.remoteVersion != baseline.remoteVersion

                if localChanged && remoteChanged {
                    var conflict = baseline
                    conflict.state = .conflict
                    upsertLink(conflict)
                    conflicts += 1
                    continue
                }

                if remoteChanged {
                    var updated = existing
                    applyRemote(task, to: &updated, provider: provider)
                    projectStore.updateProject(updated)
                    let refreshed = projectStore.project(existing.id) ?? updated
                    upsertLink(makeLink(
                        provider: provider,
                        task: task,
                        project: refreshed,
                        state: .remoteChangesApplied
                    ))
                    updatedLocal += 1
                    continue
                }

                if localChanged {
                    do {
                        let pushed = try await pushProject(
                            existing,
                            task: task,
                            provider: provider
                        )
                        var refreshed = existing
                        applyRemote(pushed, to: &refreshed, provider: provider)
                        projectStore.updateProject(refreshed)
                        upsertLink(makeLink(
                            provider: provider,
                            task: pushed,
                            project: refreshed,
                            state: .localChangesPushed
                        ))
                        pushedRemote += 1
                    } catch {
                        var pending = baseline
                        pending.state = .conflict
                        upsertLink(pending)
                        conflicts += 1
                    }
                    continue
                }

                upsertLink(makeLink(
                    provider: provider,
                    task: task,
                    project: existing,
                    state: .synced
                ))
                unchanged += 1
            }

            for index in links.indices where links[index].provider == provider {
                guard !seenExternalIDs.contains(links[index].externalID) else { continue }
                if links[index].state != .remoteMissing {
                    links[index].state = .remoteMissing
                    remoteMissing += 1
                }
            }

            let result = IntegrationSyncResult(
                provider: provider,
                imported: imported,
                updatedLocal: updatedLocal,
                pushedRemote: pushedRemote,
                conflicts: conflicts,
                remoteMissing: remoteMissing,
                unchanged: unchanged,
                completedAt: .now
            )
            var updated = configuration(for: provider)
            updated.connected = true
            updated.lastSyncAt = result.completedAt
            updated.lastSyncConflictCount = conflicts
            updated.lastSyncSummary = result.message
            updated.statusMessage = result.message
            replace(updated)
            persist()
            persistLinks()
            statusMessage = "\(provider.title) sync complete · \(result.message)"
            return result
        } catch {
            updateStatus(provider, message: message(for: error))
            statusMessage = "\(provider.title) sync failed"
            return nil
        }
    }

    func syncStatus(for provider: ExternalIntegrationProvider) -> [String: Any] {
        let providerLinks = links.filter { $0.provider == provider }
        let conflicts = providerLinks.filter { $0.state == .conflict }.count
        let remoteMissing = providerLinks.filter { $0.state == .remoteMissing }.count
        return [
            "linked_projects": providerLinks.count,
            "conflicts": conflicts,
            "remote_missing": remoteMissing,
            "last_sync_summary": configuration(for: provider).lastSyncSummary ?? NSNull()
        ]
    }

    private func fetchTasks(for provider: ExternalIntegrationProvider) async throws -> [ExternalTask] {
        guard let request = makeRequest(for: provider, testOnly: false) else {
            throw IntegrationError.message("Integration is not configured")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw IntegrationError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw IntegrationError.http(statusCode: http.statusCode, body: responseMessage(from: data))
        }
        return try parseTasks(data, provider: provider)
    }

    private func pushProject(
        _ project: TrackingProject,
        task: ExternalTask,
        provider: ExternalIntegrationProvider
    ) async throws -> ExternalTask {
        let config = configuration(for: provider)
        let token = token(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, let baseURL = URL(string: config.endpoint) else {
            throw IntegrationError.message("Integration is not configured")
        }

        var request: URLRequest
        switch provider {
        case .clickUp:
            request = URLRequest(url: baseURL.appendingPathComponent("task").appendingPathComponent(task.id))
            request.httpMethod = "PUT"
            request.setValue(token, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "name": project.name,
                "description": project.notes.isEmpty ? " " : project.notes
            ])
        case .linear:
            guard baseURL.absoluteString.hasSuffix("/graphql") else {
                throw IntegrationError.message("Linear endpoint must end in /graphql")
            }
            request = URLRequest(url: baseURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(token, forHTTPHeaderField: "Authorization")
            let query = """
            mutation UpdateIssue($id: String!, $title: String!, $description: String!) {
              issueUpdate(id: $id, input: { title: $title, description: $description }) {
                success
                issue { id title description url updatedAt state { name } }
              }
            }
            """
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "query": query,
                "variables": [
                    "id": task.id,
                    "title": project.name,
                    "description": project.notes
                ]
            ])
        case .clio:
            request = URLRequest(url: baseURL.appendingPathComponent("matters").appendingPathComponent("\(task.id).json"))
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("4.0.7", forHTTPHeaderField: "X-API-VERSION")
            if let remoteVersion = task.remoteVersion, !remoteVersion.isEmpty {
                request.setValue(remoteVersion, forHTTPHeaderField: "If-Match")
            }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "data": ["description": project.name]
            ])
        }
        request.setValue("Metriday/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw IntegrationError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw IntegrationError.http(statusCode: http.statusCode, body: responseMessage(from: data))
        }
        return ExternalTask(
            id: task.id,
            title: project.name,
            subtitle: task.subtitle,
            notes: provider == .clio ? project.name : project.notes,
            url: task.url,
            status: task.status,
            remoteVersion: task.remoteVersion
        )
    }

    private func ensureRootProject(
        for provider: ExternalIntegrationProvider,
        in projectStore: ProjectStore
    ) -> UUID? {
        if let existing = projectStore.activeProjects.first(where: {
            $0.parentID == nil && $0.customFields["integration_provider"] == provider.rawValue
        }) {
            return existing.id
        }
        guard let created = projectStore.createProject(name: provider.title, color: .purple),
              var root = projectStore.project(created) else { return nil }
        root.customFields["integration_provider"] = provider.rawValue
        projectStore.updateProject(root)
        return created
    }

    private func createLinkedProject(
        _ task: ExternalTask,
        provider: ExternalIntegrationProvider,
        into projectStore: ProjectStore
    ) -> UUID? {
        guard let rootID = ensureRootProject(for: provider, in: projectStore),
              let id = projectStore.createProject(name: task.title, color: .blue, parentID: rootID),
              var project = projectStore.project(id) else { return nil }
        applyRemote(task, to: &project, provider: provider)
        projectStore.updateProject(project)
        return id
    }

    private func applyRemote(
        _ task: ExternalTask,
        to project: inout TrackingProject,
        provider: ExternalIntegrationProvider
    ) {
        project.name = task.title
        project.notes = task.notes
        project.customFields["integration_provider"] = provider.rawValue
        project.customFields["integration_id"] = task.id
        project.customFields["integration_url"] = task.url
        project.customFields["integration_status"] = task.status
    }

    private func makeLink(
        provider: ExternalIntegrationProvider,
        task: ExternalTask,
        project: TrackingProject,
        state: IntegrationSyncState
    ) -> IntegrationLink {
        IntegrationLink(
            id: link(for: provider, externalID: task.id)?.id ?? UUID(),
            provider: provider,
            externalID: task.id,
            localProjectID: project.id,
            remoteTitle: task.title,
            remoteNotes: task.notes,
            remoteStatus: task.status,
            remoteURL: task.url,
            remoteVersion: task.remoteVersion,
            syncedLocalTitle: project.name,
            syncedLocalNotes: project.notes,
            syncedLocalStatus: project.customFields["integration_status"] ?? "",
            lastSyncedAt: .now,
            state: state
        )
    }

    private func legacyLink(
        for provider: ExternalIntegrationProvider,
        task: ExternalTask,
        project: TrackingProject
    ) -> IntegrationLink? {
        guard project.customFields["integration_provider"] == provider.rawValue,
              project.customFields["integration_id"] == task.id else { return nil }
        return IntegrationLink(
            provider: provider,
            externalID: task.id,
            localProjectID: project.id,
            remoteTitle: project.name,
            remoteNotes: project.notes,
            remoteStatus: project.customFields["integration_status"] ?? "",
            remoteURL: project.customFields["integration_url"] ?? "",
            syncedLocalTitle: project.name,
            syncedLocalNotes: project.notes,
            syncedLocalStatus: project.customFields["integration_status"] ?? "",
            lastSyncedAt: nil,
            state: .imported
        )
    }

    private func link(for provider: ExternalIntegrationProvider, externalID: String) -> IntegrationLink? {
        links.first { $0.provider == provider && $0.externalID == externalID }
    }

    private func upsertLink(_ link: IntegrationLink) {
        if let index = links.firstIndex(where: { $0.provider == link.provider && $0.externalID == link.externalID }) {
            links[index] = link
        } else {
            links.append(link)
        }
    }

    private func makeRequest(
        for provider: ExternalIntegrationProvider,
        testOnly: Bool
    ) -> URLRequest? {
        let config = configuration(for: provider)
        let token = token(for: provider).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        let endpoint = config.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: endpoint) else { return nil }

        var request: URLRequest
        switch provider {
        case .clickUp:
            guard !config.workspace.isEmpty else { return nil }
            let path = baseURL
                .appendingPathComponent("list")
                .appendingPathComponent(config.workspace)
                .appendingPathComponent("task")
            var components = URLComponents(url: path, resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "include_closed", value: "true"),
                URLQueryItem(name: "subtasks", value: "true"),
                URLQueryItem(name: "page", value: "0")
            ]
            guard let url = components?.url else { return nil }
            request = URLRequest(url: url)
            request.setValue(token, forHTTPHeaderField: "Authorization")
        case .linear:
            guard baseURL.absoluteString.hasSuffix("/graphql") else { return nil }
            request = URLRequest(url: baseURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(token.hasPrefix("Bearer ") ? token : "Bearer \(token)", forHTTPHeaderField: "Authorization")
            let query: String
            if testOnly {
                query = "query { viewer { id name } }"
            } else {
                query = "query { issues(first: 50, orderBy: updatedAt) { nodes { id identifier title description url updatedAt state { name } } } }"
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query])
        case .clio:
            let url: URL
            if testOnly {
                url = baseURL.appendingPathComponent("users.json")
            } else {
                var components = URLComponents(
                    url: baseURL.appendingPathComponent("matters.json"),
                    resolvingAgainstBaseURL: false
                )
                components?.queryItems = [
                    URLQueryItem(name: "limit", value: "50"),
                    URLQueryItem(name: "fields", value: "id,display_number,description,etag,updated_at")
                ]
                guard let resolved = components?.url else { return nil }
                url = resolved
            }
            request = URLRequest(url: url)
            request.setValue(token.hasPrefix("Bearer ") ? token : "Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("4.0.7", forHTTPHeaderField: "X-API-VERSION")
        }
        request.setValue("Metriday/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func parseTasks(
        _ data: Data,
        provider: ExternalIntegrationProvider
    ) throws -> [ExternalTask] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IntegrationError.invalidResponse
        }
        switch provider {
        case .clickUp:
            let rows = object["tasks"] as? [[String: Any]] ?? []
            return rows.compactMap { row in
                guard let id = row["id"] as? String,
                      let title = row["name"] as? String else { return nil }
                let status = (row["status"] as? [String: Any])?["status"] as? String ?? ""
                return ExternalTask(
                    id: id,
                    title: title,
                    subtitle: "ClickUp · \(status)",
                    notes: row["description"] as? String ?? "",
                    url: row["url"] as? String ?? "",
                    status: status,
                    remoteVersion: row["date_updated"] as? String
                )
            }
        case .linear:
            if let errors = object["errors"] as? [[String: Any]],
               let first = errors.first?["message"] as? String {
                throw IntegrationError.message(first)
            }
            let rows = ((object["data"] as? [String: Any])?["issues"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
            return rows.compactMap { row in
                guard let id = row["id"] as? String,
                      let title = row["title"] as? String else { return nil }
                let identifier = row["identifier"] as? String ?? "Linear"
                let status = ((row["state"] as? [String: Any])?["name"] as? String) ?? ""
                return ExternalTask(
                    id: id,
                    title: title,
                    subtitle: "\(identifier) · \(status)",
                    notes: row["description"] as? String ?? "",
                    url: row["url"] as? String ?? "",
                    status: status,
                    remoteVersion: row["updatedAt"] as? String
                )
            }
        case .clio:
            let rows = object["data"] as? [[String: Any]] ?? []
            return rows.compactMap { row in
                guard let rawID = row["id"] else { return nil }
                let id = String(describing: rawID)
                let number = row["display_number"] as? String ?? id
                let description = row["description"] as? String ?? "Matter \(number)"
                return ExternalTask(
                    id: id,
                    title: description.isEmpty ? "Matter \(number)" : description,
                    subtitle: "Clio · \(number)",
                    notes: description,
                    url: "",
                    status: "matter",
                    remoteVersion: row["etag"] as? String
                )
            }
        }
    }

    private func importTasks(
        _ tasks: [ExternalTask],
        provider: ExternalIntegrationProvider,
        into projectStore: ProjectStore
    ) -> Int {
        guard !tasks.isEmpty else { return 0 }
        guard ensureRootProject(for: provider, in: projectStore) != nil else { return 0 }

        var imported = 0
        for task in tasks {
            if let existing = projectStore.activeProjects.first(where: {
                $0.customFields["integration_provider"] == provider.rawValue
                    && $0.customFields["integration_id"] == task.id
            }) {
                var updated = existing
                applyRemote(task, to: &updated, provider: provider)
                projectStore.updateProject(updated)
                upsertLink(makeLink(provider: provider, task: task, project: updated, state: .imported))
                continue
            }
            guard let id = createLinkedProject(task, provider: provider, into: projectStore),
                  let project = projectStore.project(id) else { continue }
            upsertLink(makeLink(provider: provider, task: task, project: project, state: .imported))
            imported += 1
        }
        persistLinks()
        return imported
    }

    private func replace(_ configuration: ExternalIntegrationConfiguration) {
        guard let index = configurations.firstIndex(where: { $0.provider == configuration.provider }) else { return }
        configurations[index] = configuration
    }

    private func updateStatus(_ provider: ExternalIntegrationProvider, message: String) {
        var updated = configuration(for: provider)
        updated.statusMessage = message
        replace(updated)
    }

    private func responseMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Unexpected response"
        }
        return (object["err"] as? String)
            ?? (object["error"] as? String)
            ?? (object["message"] as? String)
            ?? "HTTP request failed"
    }

    private func message(for error: Error) -> String {
        if let integrationError = error as? IntegrationError {
            switch integrationError {
            case .invalidResponse: return "Invalid response"
            case .http(let statusCode, let body): return "HTTP \(statusCode) · \(body)"
            case .message(let message): return message
            }
        }
        return error.localizedDescription
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configurations).write(to: settingsURL, options: .atomic)
        } catch {
            statusMessage = "Could not save integrations"
        }
    }

    private func persistLinks() {
        do {
            try FileManager.default.createDirectory(
                at: linksURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(links).write(to: linksURL, options: .atomic)
        } catch {
            statusMessage = "Could not save integration links"
        }
    }

    private static func loadSettings(from url: URL) -> [ExternalIntegrationConfiguration] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ExternalIntegrationConfiguration].self, from: data)) ?? []
    }

    private static func loadLinks(from url: URL) -> [IntegrationLink] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([IntegrationLink].self, from: data)) ?? []
    }

    private static func defaultRootDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport.appendingPathComponent("Metriday", isDirectory: true)
    }
}

private enum IntegrationError: Error {
    case invalidResponse
    case http(statusCode: Int, body: String)
    case message(String)
}

private enum KeychainValue {
    static func save(_ value: String, service: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) != errSecSuccess {
            var item = query
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

import Combine
import Foundation

/// A portable, device-partitioned sync archive. The selected folder can be an
/// iCloud Drive, Dropbox, NAS, or any other directory shared by the user's
/// Macs. Each device writes its own file, so two Macs never overwrite each
/// other's local changes while offline.
struct MetridaySyncArchive: Codable {
    let version: Int
    let deviceID: String
    let deviceName: String
    let updatedAt: Date
    let projects: ProjectArchive
    /// Optional keeps archives written before saved activity filters readable.
    let filters: ActivityFilterArchive?
    let timeEntries: TimeEntryArchive
    let activities: ActivityHistoryArchive
    /// Optional keeps archives written before Screen Time sync forward-compatible.
    let screenTime: ActivityHistoryArchive?
    let plans: MarkdownPlanArchive
    /// Optional keeps archives written before focus/exclusion sync readable.
    let webRules: [WebRule]?
    let excludedBundleIdentifiers: [String]?
    /// Optional keeps archives written before rule-based exclusions readable.
    let exclusionRules: [ActivityExclusionRule]?
    /// Optional keeps archives written before local team support readable.
    let teams: TeamArchive?
}

@MainActor
final class SyncStore: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var folderURL: URL?
    @Published var deviceName: String {
        didSet { persistSettings() }
    }
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var backupCount = 0
    @Published private(set) var statusMessage = "Timing Sync is not configured"

    let deviceID: String

    private let projectStore: ProjectStore
    private let filterStore: ActivityFilterStore?
    private let timeEntryStore: TimeEntryStore
    private let activityMonitor: AppActivityMonitor
    private let screenTimeStore: ScreenTimeStore?
    private let webBlocker: WebBlockerService?
    private let exclusionStore: ExclusionStore?
    private let teamStore: TeamStore?
    private let markdownStore: MarkdownStore
    private let settingsURL: URL
    private let identityURL: URL
    private var automaticTimer: Timer?

    init(
        projectStore: ProjectStore,
        filterStore: ActivityFilterStore? = nil,
        timeEntryStore: TimeEntryStore,
        activityMonitor: AppActivityMonitor,
        markdownStore: MarkdownStore,
        screenTimeStore: ScreenTimeStore? = nil,
        webBlocker: WebBlockerService? = nil,
        exclusionStore: ExclusionStore? = nil,
        teamStore: TeamStore? = nil,
        rootDirectory: URL? = nil
    ) {
        let root = rootDirectory ?? Self.defaultRootDirectory()
        self.projectStore = projectStore
        self.filterStore = filterStore
        self.timeEntryStore = timeEntryStore
        self.activityMonitor = activityMonitor
        self.screenTimeStore = screenTimeStore
        self.webBlocker = webBlocker
        self.exclusionStore = exclusionStore
        self.teamStore = teamStore
        self.markdownStore = markdownStore
        self.settingsURL = root.appendingPathComponent("SyncSettings.json")
        self.identityURL = root.appendingPathComponent("SyncIdentity.json")

        let settings = Self.loadSettings(from: settingsURL)
        self.deviceName = settings?.deviceName
            ?? Host.current().localizedName
            ?? "This Mac"
        self.isEnabled = settings?.isEnabled ?? false
        self.folderURL = settings?.folderPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
        self.lastSyncAt = settings?.lastSyncAt

        if let data = try? Data(contentsOf: identityURL),
           let identity = try? JSONDecoder().decode(SyncIdentity.self, from: data) {
            self.deviceID = identity.deviceID
        } else {
            self.deviceID = UUID().uuidString
            persistIdentity()
        }
    }

    func start() {
        guard isEnabled, folderURL != nil else { return }
        _ = syncNow()
        automaticTimer?.invalidate()
        automaticTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                _ = self?.syncNow()
            }
        }
    }

    func stop() {
        automaticTimer?.invalidate()
        automaticTimer = nil
    }

    func configure(folderURL: URL) {
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            self.folderURL = folderURL
            self.isEnabled = true
            persistSettings()
            statusMessage = "Timing Sync enabled · \(folderURL.lastPathComponent)"
            start()
        } catch {
            statusMessage = "Could not use sync folder · \(error.localizedDescription)"
        }
    }

    func disable() {
        isEnabled = false
        stop()
        persistSettings()
        statusMessage = "Timing Sync disabled"
    }

    @discardableResult
    func syncNow() -> Bool {
        guard isEnabled, let folderURL else {
            statusMessage = "Choose a shared folder to enable Timing Sync"
            return false
        }

        do {
            let fileManager = FileManager.default
            let devicesURL = folderURL.appendingPathComponent("devices", isDirectory: true)
            try fileManager.createDirectory(at: devicesURL, withIntermediateDirectories: true)

            // Write this device's current state first. A device-specific file
            // makes offline edits mergeable instead of last-writer-wins.
            let localArchive = try makeArchive()
            try writeBackup(localArchive, in: folderURL)
            try write(localArchive, to: archiveURL(in: devicesURL))

            let archives = try loadArchives(from: devicesURL)
                .sorted { $0.updatedAt < $1.updatedAt }
            let stats = try mergeArchives(archives)

            // Persist the merged view into this device's archive so a newly
            // connected Mac can bootstrap from any one current device file.
            let consolidated = try makeArchive()
            try write(consolidated, to: archiveURL(in: devicesURL))
            try writeManifest(archives: archives, in: folderURL)

            lastSyncAt = .now
            backupCount = backupURLs(in: folderURL).count
            persistSettings()
            let devicePlural = archives.count == 1 ? "" : "s"
            let screenTimeSuffix = stats.importedScreenTime > 0
                ? " · \(stats.importedScreenTime) Screen Time rows"
                : ""
            let filterSuffix = stats.importedFilters > 0
                ? " · \(stats.importedFilters) filters"
                : ""
            statusMessage = "Synced \(archives.count) device\(devicePlural) · \(stats.importedEntries) new entries · \(stats.importedActivities) new activities\(screenTimeSuffix)\(filterSuffix) · \(stats.importedPlans) plans · \(backupCount) backups"
            return true
        } catch {
            statusMessage = "Sync failed · \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func restoreLatestBackup() -> Bool {
        guard isEnabled, let folderURL, let backupURL = backupURLs(in: folderURL).last else {
            statusMessage = "No cloud backup is available"
            return false
        }
        do {
            guard let data = try? Data(contentsOf: backupURL) else {
                statusMessage = "Cloud backup could not be read"
                return false
            }
            let archive = try Self.decoder().decode(MetridaySyncArchive.self, from: data)
            let currentArchive = try makeArchive()
            try writeBackup(currentArchive, in: folderURL)
            let stats = try mergeArchives([archive])
            if let devicesURL = try? makeDevicesDirectory(in: folderURL) {
                try write(try makeArchive(), to: archiveURL(in: devicesURL))
            }
            backupCount = backupURLs(in: folderURL).count
            lastSyncAt = .now
            persistSettings()
            statusMessage = "Restored backup · \(stats.importedEntries) entries · \(stats.importedPlans) plans"
            return true
        } catch {
            statusMessage = "Backup restore failed · \(error.localizedDescription)"
            return false
        }
    }

    private func makeDevicesDirectory(in folderURL: URL) throws -> URL {
        let devicesURL = folderURL.appendingPathComponent("devices", isDirectory: true)
        try FileManager.default.createDirectory(at: devicesURL, withIntermediateDirectories: true)
        return devicesURL
    }

    private struct MergeStats {
        var importedEntries = 0
        var importedActivities = 0
        var importedScreenTime = 0
        var importedFilters = 0
        var importedPlans = 0
    }

    private func mergeArchives(_ archives: [MetridaySyncArchive]) throws -> MergeStats {
        var stats = MergeStats()
        var projectMaps: [String: [UUID: UUID]] = [:]

        // Projects are merged before entries and activities so foreign
        // project IDs can be translated to this Mac's IDs.
        for archive in archives {
            if let archiveFilters = archive.filters, let filterStore {
                stats.importedFilters += filterStore.mergeArchive(archiveFilters)
            }
            let teamMap: [UUID: UUID]
            if let teamArchive = archive.teams, let teamStore {
                teamMap = teamStore.mergeArchive(teamArchive).idMap
            } else {
                teamMap = [:]
            }
            let mappedProjects = ProjectArchive(
                version: archive.projects.version,
                projects: archive.projects.projects.map { project in
                    var mapped = project
                    if let teamID = project.teamID {
                        mapped.teamID = teamMap[teamID] ?? teamID
                    }
                    return mapped
                },
                rules: archive.projects.rules
            )
            let result = projectStore.mergeArchive(mappedProjects)
            projectMaps[archive.deviceID] = result.idMap
        }

        for archive in archives {
            let projectMap = projectMaps[archive.deviceID] ?? [:]
            stats.importedPlans += try markdownStore.importArchiveData(encode(archive.plans))
            let mappedEntries = archive.timeEntries.entries.map { entry in
                TimeEntry(
                    id: entry.id,
                    projectID: entry.projectID.flatMap { projectMap[$0] },
                    title: entry.title,
                    notes: entry.notes,
                    start: entry.start,
                    end: entry.end,
                    billingStatus: entry.billingStatus,
                    isManual: entry.isManual,
                    customFields: entry.customFields
                )
            }
            let entryData = try encode(TimeEntryArchive(version: 1, entries: mappedEntries))
            stats.importedEntries += try timeEntryStore.importArchiveData(entryData)

            let mappedDays = archive.activities.days.map { day in
                ActivityHistoryDayArchive(
                    date: day.date,
                    segments: day.segments.map { segment in
                        var mapped = segment
                        mapped.projectID = segment.projectID.flatMap { projectMap[$0] }
                        return mapped
                    }
                )
            }
            let activityData = try encode(ActivityHistoryArchive(version: 1, days: mappedDays))
            stats.importedActivities += try activityMonitor.importHistoryArchiveData(activityData)
            if let screenTimeArchive = archive.screenTime,
               let screenTimeStore {
                stats.importedScreenTime += try screenTimeStore.importArchiveData(
                    encode(screenTimeArchive)
                )
            }
            if let webRules = archive.webRules, let webBlocker {
                webBlocker.importRules(webRules)
            }
            if let excludedBundleIdentifiers = archive.excludedBundleIdentifiers, let exclusionStore {
                exclusionStore.importBundleIdentifiers(excludedBundleIdentifiers)
            }
            if let exclusionRules = archive.exclusionRules, let exclusionStore {
                exclusionStore.importRules(exclusionRules)
            }
        }
        return stats
    }

    private func makeArchive() throws -> MetridaySyncArchive {
        let decoder = Self.decoder()
        let projects = try decoder.decode(ProjectArchive.self, from: projectStore.exportArchiveData())
        let filters = try filterStore.map {
            try decoder.decode(ActivityFilterArchive.self, from: $0.exportArchiveData())
        }
        let timeEntries = try decoder.decode(TimeEntryArchive.self, from: timeEntryStore.exportArchiveData())
        let activities = try decoder.decode(ActivityHistoryArchive.self, from: activityMonitor.exportHistoryArchiveData())
        let screenTime = try screenTimeStore.map {
            try decoder.decode(ActivityHistoryArchive.self, from: $0.exportArchiveData())
        }
            let plans = try decoder.decode(MarkdownPlanArchive.self, from: markdownStore.exportArchiveData())
            let teams = try teamStore.map {
                try decoder.decode(TeamArchive.self, from: $0.exportArchiveData())
            }
            return MetridaySyncArchive(
            version: 1,
            deviceID: deviceID,
            deviceName: deviceName,
            updatedAt: .now,
            projects: projects,
            filters: filters,
            timeEntries: timeEntries,
            activities: activities,
            screenTime: screenTime,
                plans: plans,
                webRules: webBlocker?.rules,
                excludedBundleIdentifiers: exclusionStore?.bundleIdentifiers,
                exclusionRules: exclusionStore?.rules,
                teams: teams
            )
    }

    private func loadArchives(from devicesURL: URL) throws -> [MetridaySyncArchive] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: devicesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }
        let decoder = Self.decoder()
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let archive = try? decoder.decode(MetridaySyncArchive.self, from: data),
                  archive.version == 1 else { return nil }
            return archive
        }
    }

    private func archiveURL(in devicesURL: URL) -> URL {
        devicesURL.appendingPathComponent("\(deviceID).json")
    }

    private func writeBackup(_ archive: MetridaySyncArchive, in folderURL: URL) throws {
        let backupsURL = folderURL.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "\(deviceID)-\(formatter.string(from: .now)).json"
        try write(archive, to: backupsURL.appendingPathComponent(filename))
        let urls = backupURLs(in: folderURL)
        if urls.count > 30 {
            for url in urls.dropLast(30) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func backupURLs(in folderURL: URL) -> [URL] {
        let backupsURL = folderURL.appendingPathComponent("backups", isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(
            at: backupsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ))?
        .filter { $0.pathExtension.lowercased() == "json" }
        .sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        } ?? []
    }

    private func write(_ archive: MetridaySyncArchive, to url: URL) throws {
        let data = try encode(archive)
        try data.write(to: url, options: .atomic)
    }

    private func writeManifest(archives: [MetridaySyncArchive], in folderURL: URL) throws {
        let manifest = SyncManifest(
            version: 1,
            updatedAt: .now,
            devices: archives.map {
                SyncDeviceSummary(id: $0.deviceID, name: $0.deviceName, updatedAt: $0.updatedAt)
            }
        )
        try encode(manifest).write(
            to: folderURL.appendingPathComponent("manifest.json"),
            options: .atomic
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = Self.encoder()
        return try encoder.encode(value)
    }

    private func persistSettings() {
        let settings = SyncSettings(
            isEnabled: isEnabled,
            folderPath: folderURL?.path,
            deviceName: deviceName,
            lastSyncAt: lastSyncAt
        )
        do {
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encode(settings).write(to: settingsURL, options: .atomic)
        } catch {
            // Sync failures are surfaced by syncNow; settings are best effort.
        }
    }

    private func persistIdentity() {
        do {
            try FileManager.default.createDirectory(
                at: identityURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encode(SyncIdentity(deviceID: deviceID)).write(to: identityURL, options: .atomic)
        } catch {
            statusMessage = "Could not save sync identity"
        }
    }

    private static func loadSettings(from url: URL) -> SyncSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder().decode(SyncSettings.self, from: data)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func defaultRootDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport.appendingPathComponent("Metriday", isDirectory: true)
    }

    private struct SyncIdentity: Codable {
        let deviceID: String
    }

    private struct SyncSettings: Codable {
        let isEnabled: Bool
        let folderPath: String?
        let deviceName: String
        let lastSyncAt: Date?
    }

    private struct SyncDeviceSummary: Codable {
        let id: String
        let name: String
        let updatedAt: Date
    }

    private struct SyncManifest: Codable {
        let version: Int
        let updatedAt: Date
        let devices: [SyncDeviceSummary]
    }
}

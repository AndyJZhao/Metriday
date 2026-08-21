import Combine
import Foundation

struct CalendarEventLinkArchive: Codable {
    let version: Int
    let taskToEvent: [String: String]
}

/// Keeps the external EventKit identifier beside the Markdown task identity.
/// The link is intentionally not serialized into the Markdown text.
@MainActor
final class CalendarEventLinkStore: ObservableObject {
    @Published private(set) var taskToEvent: [UUID: String]

    private let fileURL: URL

    init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? Self.defaultRootDirectory()
        self.fileURL = root.appendingPathComponent("CalendarEventLinks.json")
        if let data = try? Data(contentsOf: fileURL),
           let archive = try? JSONDecoder().decode(CalendarEventLinkArchive.self, from: data) {
            self.taskToEvent = archive.taskToEvent.reduce(into: [:]) { result, item in
                if let taskID = UUID(uuidString: item.key) {
                    result[taskID] = item.value
                }
            }
        } else {
            self.taskToEvent = [:]
        }
    }

    func link(taskID: UUID, eventID: String) {
        taskToEvent[taskID] = eventID
        persist()
    }

    func eventID(for taskID: UUID) -> String? {
        taskToEvent[taskID]
    }

    func exportArchiveData() throws -> Data {
        let archive = CalendarEventLinkArchive(
            version: 1,
            taskToEvent: Dictionary(uniqueKeysWithValues: taskToEvent.map { ($0.uuidString, $1) })
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    /// Merges links after Markdown task IDs have been reconciled by sync.
    @discardableResult
    func mergeArchive(_ archive: CalendarEventLinkArchive, taskIDMap: [UUID: UUID] = [:]) -> Int {
        var imported = 0
        for (rawTaskID, eventID) in archive.taskToEvent {
            guard let remoteTaskID = UUID(uuidString: rawTaskID) else { continue }
            let localTaskID = taskIDMap[remoteTaskID] ?? remoteTaskID
            if taskToEvent[localTaskID] == nil {
                taskToEvent[localTaskID] = eventID
                imported += 1
            }
        }
        if imported > 0 { persist() }
        return imported
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let values = Dictionary(uniqueKeysWithValues: taskToEvent.map { ($0.uuidString, $1) })
            let archive = CalendarEventLinkArchive(version: 1, taskToEvent: values)
            let data = try JSONEncoder().encode(archive)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // The Markdown conversion itself remains usable if metadata cannot persist.
        }
    }

    private static func defaultRootDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return applicationSupport.appendingPathComponent("Metriday", isDirectory: true)
    }
}

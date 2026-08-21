import Combine
import Foundation

private struct CalendarEventLinkArchive: Codable {
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

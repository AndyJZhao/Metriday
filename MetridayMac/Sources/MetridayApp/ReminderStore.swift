import Combine
import EventKit
import Foundation

struct ReminderItem: Identifiable, Hashable {
    let id: String
    let title: String
    let listTitle: String
    let notes: String
    let completedAt: Date
    let isRecurring: Bool
}

@MainActor
final class ReminderStore: ObservableObject {
    @Published private(set) var reminders: [ReminderItem] = []
    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var statusMessage = "Reminders access not connected"
    @Published private(set) var availableListTitles: [String] = []
    @Published private(set) var includedListTitles: Set<String> = []
    @Published var hideRecurringReminders: Bool {
        didSet { persistPreferences() }
    }

    private let eventStore = EKEventStore()
    private let preferencesURL: URL
    private var selectedDate = Calendar.current.startOfDay(for: .now)

    init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? Self.defaultRootDirectory()
        self.preferencesURL = root.appendingPathComponent("ReminderPreferences.json")
        let preferences = Self.loadPreferences(from: preferencesURL)
        self.includedListTitles = preferences?.includedListTitles ?? []
        self.hideRecurringReminders = preferences?.hideRecurringReminders ?? false
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        if isAuthorized {
            statusMessage = "Reminders ready"
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .fullAccess
    }

    func requestAccess() {
        Task { @MainActor in
            do {
                let granted: Bool
                if #available(macOS 14.0, *) {
                    granted = try await eventStore.requestFullAccessToReminders()
                } else {
                    granted = try await eventStore.requestAccess(to: .reminder)
                }
                authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
                if granted {
                    statusMessage = "Reminders ready"
                    loadCompleted(for: selectedDate)
                } else {
                    statusMessage = "Reminders access was not granted"
                }
            } catch {
                statusMessage = "Reminders access failed · \(error.localizedDescription)"
            }
        }
    }

    func loadCompleted(for date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        guard isAuthorized else {
            reminders = []
            return
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let calendars = eventStore.calendars(for: .reminder)
        availableListTitles = calendars
            .map(\.title)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted()
        let selectedCalendars = includedListTitles.isEmpty
            ? nil
            : calendars.filter { includedListTitles.contains($0.title) }
        let predicate = eventStore.predicateForCompletedReminders(
            withCompletionDateStarting: start,
            ending: end,
            calendars: selectedCalendars
        )
        eventStore.fetchReminders(matching: predicate) { [weak self] fetched in
            let mapped = (fetched ?? []).compactMap { reminder -> ReminderItem? in
                guard let completionDate = reminder.completionDate else { return nil }
                let recurring = reminder.recurrenceRules?.isEmpty == false
                guard !(self?.hideRecurringReminders == true && recurring) else { return nil }
                let identifier = reminder.calendarItemIdentifier
                return ReminderItem(
                    id: identifier,
                    title: reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? reminder.title!
                        : "Untitled reminder",
                    listTitle: reminder.calendar?.title ?? "Reminders",
                    notes: reminder.notes ?? "",
                    completedAt: completionDate,
                    isRecurring: recurring
                )
            }
            .sorted { $0.completedAt < $1.completedAt }
            Task { @MainActor in
                guard let self else { return }
                self.reminders = mapped
                self.statusMessage = mapped.isEmpty
                    ? "No completed reminders for this day"
                    : "Reminders ready · \(mapped.count) completed"
            }
        }
    }

    func setAllListsIncluded(_ included: Bool) {
        includedListTitles = included ? [] : Set(availableListTitles)
        persistPreferences()
        loadCompleted(for: selectedDate)
    }

    func setListIncluded(_ title: String, included: Bool) {
        var selected = includedListTitles
        if selected.isEmpty && !included {
            selected = Set(availableListTitles)
        }
        if included {
            selected.insert(title)
        } else {
            selected.remove(title)
        }
        includedListTitles = selected == Set(availableListTitles) ? [] : selected
        persistPreferences()
        loadCompleted(for: selectedDate)
    }

    func setIncludedListTitles(_ titles: [String]) {
        let available = Set(availableListTitles)
        let selected = Set(titles).intersection(available)
        includedListTitles = selected == available ? [] : selected
        persistPreferences()
        loadCompleted(for: selectedDate)
    }

    private func persistPreferences() {
        do {
            try FileManager.default.createDirectory(
                at: preferencesURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let payload = Preferences(
                includedListTitles: includedListTitles,
                hideRecurringReminders: hideRecurringReminders
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(payload).write(to: preferencesURL, options: .atomic)
        } catch {
            // Reminder filters are best effort and never block the timeline.
        }
    }

    private static func loadPreferences(from url: URL) -> Preferences? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Preferences.self, from: data)
    }

    private static func defaultRootDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport.appendingPathComponent("Metriday", isDirectory: true)
    }

    private struct Preferences: Codable {
        let includedListTitles: Set<String>
        let hideRecurringReminders: Bool
    }
}

import Combine
import EventKit
import Foundation

struct CalendarEventItem: Identifiable, Hashable {
    let id: String
    let title: String
    let calendarTitle: String
    let calendarIdentifier: String
    let isEditable: Bool
    let location: String
    let notes: String
    let urlString: String
    let start: Date
    let end: Date

    init(
        id: String,
        title: String,
        calendarTitle: String,
        location: String,
        notes: String,
        urlString: String,
        start: Date,
        end: Date,
        calendarIdentifier: String = "",
        isEditable: Bool = true
    ) {
        self.id = id
        self.title = title
        self.calendarTitle = calendarTitle
        self.calendarIdentifier = calendarIdentifier
        self.isEditable = isEditable
        self.location = location
        self.notes = notes
        self.urlString = urlString
        self.start = start
        self.end = end
    }

    var durationSeconds: Int {
        max(60, Int(end.timeIntervalSince(start)))
    }
}

@MainActor
final class CalendarEventStore: ObservableObject {
    @Published private(set) var events: [CalendarEventItem] = []
    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var statusMessage = "Calendar access not connected"
    @Published private(set) var availableCalendarTitles: [String] = []
    @Published private(set) var includedCalendarTitles: Set<String> = []

    private let eventStore = EKEventStore()
    private let preferencesURL: URL
    private var selectedDate = Calendar.current.startOfDay(for: .now)

    init(rootDirectory: URL? = nil) {
        let root = rootDirectory ?? Self.defaultRootDirectory()
        self.preferencesURL = root.appendingPathComponent("CalendarPreferences.json")
        let preferences = Self.loadPreferences(from: preferencesURL)
        self.includedCalendarTitles = preferences?.includedCalendarTitles ?? []
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if isAuthorized {
            statusMessage = "Calendar ready"
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
                    granted = try await eventStore.requestFullAccessToEvents()
                } else {
                    granted = try await eventStore.requestAccess(to: .event)
                }
                authorizationStatus = EKEventStore.authorizationStatus(for: .event)
                if granted {
                    statusMessage = "Calendar ready"
                    loadEvents(for: selectedDate)
                } else {
                    statusMessage = "Calendar access was not granted"
                }
            } catch {
                statusMessage = "Calendar access failed · \(error.localizedDescription)"
            }
        }
    }

    func loadEvents(for date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        guard isAuthorized else {
            events = []
            return
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        let calendars = eventStore.calendars(for: .event)
        availableCalendarTitles = calendars
            .map(\.title)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted()
        let selectedCalendars = includedCalendarTitles.isEmpty
            ? nil
            : calendars.filter { includedCalendarTitles.contains($0.title) }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: selectedCalendars)
        events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > start && $0.startDate < end }
            .map { event in
                CalendarEventItem(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? event.title!
                        : "Untitled event",
                    calendarTitle: event.calendar?.title ?? "Calendar",
                    location: event.location ?? "",
                    notes: event.notes ?? "",
                    urlString: event.url?.absoluteString ?? "",
                    start: event.startDate,
                    end: event.endDate,
                    calendarIdentifier: event.calendar?.calendarIdentifier ?? "",
                    isEditable: event.calendar?.allowsContentModifications ?? false
                )
            }
            .sorted { $0.start < $1.start }
        statusMessage = events.isEmpty ? "No calendar events for this day" : "Calendar ready · \(events.count) events"
    }

    func setAllCalendarsIncluded(_ included: Bool) {
        includedCalendarTitles = included ? [] : Set(availableCalendarTitles)
        persistPreferences()
        loadEvents(for: selectedDate)
    }

    func setCalendarIncluded(_ title: String, included: Bool) {
        var selected = includedCalendarTitles
        if selected.isEmpty && !included {
            selected = Set(availableCalendarTitles)
        }
        if included {
            selected.insert(title)
        } else {
            selected.remove(title)
        }
        includedCalendarTitles = selected == Set(availableCalendarTitles) ? [] : selected
        persistPreferences()
        loadEvents(for: selectedDate)
    }

    func setIncludedCalendarTitles(_ titles: [String]) {
        let available = Set(availableCalendarTitles)
        let selected = Set(titles).intersection(available)
        includedCalendarTitles = selected == available ? [] : selected
        persistPreferences()
        loadEvents(for: selectedDate)
    }

    @discardableResult
    func createEvent(
        title rawTitle: String,
        start: Date,
        end: Date,
        notes: String = ""
    ) -> Bool {
        guard isAuthorized else {
            statusMessage = "Connect Calendar before creating events"
            return false
        }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, end > start,
              let calendar = eventStore.defaultCalendarForNewEvents else {
            statusMessage = "No writable calendar is available"
            return false
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.calendar = calendar
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            event.notes = notes
        }
        do {
            try eventStore.save(event, span: .thisEvent)
            statusMessage = "Event created · \(title)"
            loadEvents(for: selectedDate)
            return true
        } catch {
            statusMessage = "Event could not be created · \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func updateEvent(
        id: String,
        title rawTitle: String,
        start: Date,
        end: Date,
        notes: String = ""
    ) -> Bool {
        guard isAuthorized else {
            statusMessage = "Connect Calendar before editing events"
            return false
        }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, end > start else {
            statusMessage = "Enter a title and a valid time range"
            return false
        }
        guard let event = eventStore.event(withIdentifier: id) else {
            statusMessage = "Event is no longer available"
            loadEvents(for: selectedDate)
            return false
        }
        guard event.calendar?.allowsContentModifications == true else {
            statusMessage = "This calendar is read-only"
            return false
        }

        event.title = title
        event.startDate = start
        event.endDate = end
        let cleanedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        event.notes = cleanedNotes.isEmpty ? nil : notes
        do {
            try eventStore.save(event, span: .thisEvent)
            statusMessage = "Event updated · \(title)"
            loadEvents(for: selectedDate)
            return true
        } catch {
            statusMessage = "Event could not be updated · \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func deleteEvent(id: String) -> Bool {
        guard isAuthorized else {
            statusMessage = "Connect Calendar before deleting events"
            return false
        }
        guard let event = eventStore.event(withIdentifier: id) else {
            statusMessage = "Event is no longer available"
            loadEvents(for: selectedDate)
            return false
        }
        guard event.calendar?.allowsContentModifications == true else {
            statusMessage = "This calendar is read-only"
            return false
        }

        do {
            try eventStore.remove(event, span: .thisEvent)
            statusMessage = "Event deleted"
            loadEvents(for: selectedDate)
            return true
        } catch {
            statusMessage = "Event could not be deleted · \(error.localizedDescription)"
            return false
        }
    }

    private func persistPreferences() {
        do {
            try FileManager.default.createDirectory(
                at: preferencesURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Preferences(includedCalendarTitles: includedCalendarTitles))
                .write(to: preferencesURL, options: .atomic)
        } catch {
            // Calendar filters are best effort and never block the timeline.
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
        let includedCalendarTitles: Set<String>
    }
}

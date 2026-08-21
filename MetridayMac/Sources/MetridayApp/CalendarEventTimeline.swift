import AppKit
import SwiftUI

struct CalendarEventTimelineItem: Identifiable {
    let event: CalendarEventItem
    let startMinute: Int
    let endMinute: Int

    var id: String {
        "(event.id)-(startMinute)-(endMinute)"
    }
}

func calendarEventTimelineItems(events: [CalendarEventItem], date: Date) -> [CalendarEventTimelineItem] {
    let calendar = Calendar.current
    let dayStart = calendar.startOfDay(for: date)
    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
    let visibleStart = max(dayStart.addingTimeInterval(TimeInterval(TimelineMetrics.startMinute * 60)), dayStart)
    let visibleEnd = min(nextDay, dayStart.addingTimeInterval(TimeInterval(TimelineMetrics.endMinute * 60)))

    return events.compactMap { event in
        let start = max(event.start, visibleStart)
        let end = min(event.end, visibleEnd)
        guard end > start else { return nil }
        let startMinute = max(
            TimelineMetrics.startMinute,
            Int(floor(start.timeIntervalSince(dayStart) / 60.0))
        )
        let endMinute = min(
            TimelineMetrics.endMinute,
            Int(ceil(end.timeIntervalSince(dayStart) / 60.0))
        )
        guard endMinute > startMinute else { return nil }
        return CalendarEventTimelineItem(event: event, startMinute: startMinute, endMinute: endMinute)
    }
    .sorted { $0.startMinute < $1.startMinute }
}

struct CalendarEventTimelineBlock: View {
    let item: CalendarEventTimelineItem
    let onSelect: () -> Void
    @State private var isHovering = false

    private var eventFill: Color {
        Color(red: 0.96, green: 0.95, blue: 0.92)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .semibold))
                    Text(item.event.title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(2)
                }
                Text("(TimeFormat.string(item.startMinute))–(TimeFormat.string(item.endMinute)) · (item.event.calendarTitle)")
                    .font(.system(size: 9))
                    .foregroundStyle(MetridayTheme.secondary)
                    .lineLimit(1)
            }
            .foregroundStyle(MetridayTheme.graphite)
            .padding(7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(eventFill)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isHovering ? MetridayTheme.warning : MetridayTheme.warning.opacity(0.62), lineWidth: isHovering ? 1.6 : 1)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(height: TimelineMetrics.height(start: item.startMinute, end: item.endMinute), alignment: .top)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .offset(y: TimelineMetrics.y(for: item.startMinute))
        .onHover { isHovering = $0 }
        .help("Calendar Event · (item.event.title)")
        .accessibilityLabel("Calendar Event (item.event.title), (TimeFormat.range(start: item.startMinute, end: item.endMinute))")
        .accessibilityHint("Read-only external event. Select to view details or record time.")
        .accessibilityIdentifier("calendar.event.(item.event.id)")
    }
}

struct CalendarEventDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let event: CalendarEventItem
    let projectID: UUID?
    @ObservedObject var timeEntryStore: TimeEntryStore

    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return "(formatter.string(from: event.start))–(formatter.string(from: event.end))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(MetridayTheme.warning)
                    .frame(width: 42, height: 42)
                    .background(MetridayTheme.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calendar Event")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MetridayTheme.warning)
                    Text(event.title)
                        .font(.system(size: 19, weight: .bold))
                        .lineLimit(3)
                    Text(timeRange)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 9) {
                detailRow(label: "Calendar", value: event.calendarTitle)
                if !event.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailRow(label: "Location", value: event.location)
                }
                if !event.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    detailRow(label: "Notes", value: event.notes)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MetridayTheme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                if let url = URL(string: event.urlString), !event.urlString.isEmpty {
                    Button("Open Link") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.borderless)
                }
                Spacer()
                Button("Record Time Entry") {
                    _ = timeEntryStore.addEntry(
                        title: event.title,
                        projectID: projectID,
                        notes: [event.calendarTitle, event.location, event.notes]
                            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                            .joined(separator: " · "),
                        start: event.start,
                        end: event.end,
                        billingStatus: .billable,
                        customFields: ["metriday_calendar_event_id": event.id]
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MetridayTheme.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(3)
            Spacer()
        }
    }
}

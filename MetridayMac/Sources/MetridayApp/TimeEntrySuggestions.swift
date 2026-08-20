import SwiftUI

struct TimeEntryTitleField: View {
    @Binding var title: String
    @Binding var billingStatus: BillingStatus
    let placeholder: String
    let entries: [TimeEntry]
    let projects: [TrackingProject]
    let excludingEntryID: UUID?

    init(
        title: Binding<String>,
        billingStatus: Binding<BillingStatus>,
        placeholder: String,
        entries: [TimeEntry],
        projects: [TrackingProject],
        excludingEntryID: UUID? = nil
    ) {
        _title = title
        _billingStatus = billingStatus
        self.placeholder = placeholder
        self.entries = entries
        self.projects = projects
        self.excludingEntryID = excludingEntryID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(placeholder, text: $title)
                .textFieldStyle(.roundedBorder)

            TimeEntryTitleSuggestions(
                suggestions: TimeEntrySuggestionProvider.titles(
                    from: entries,
                    projects: projects,
                    query: title,
                    excluding: excludingEntryID
                )
            ) { suggestion in
                title = suggestion
            }

            BillingStatusShortcutSuggestions(
                statuses: TimeEntrySuggestionProvider.billingStatuses(for: title)
            ) { status in
                billingStatus = status
                title = ""
            }
        }
    }
}

struct TimeEntryTitleSuggestions: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Suggestions")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                onSelect(suggestion)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(MetridayTheme.graphite)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(minHeight: 26)
                            .background(MetridayTheme.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .help("Use \(suggestion) as the time entry title")
                        }
                    }
                }
            }
        }
    }
}

struct BillingStatusShortcutSuggestions: View {
    let statuses: [BillingStatus]
    let onSelect: (BillingStatus) -> Void

    var body: some View {
        if !statuses.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Billing shortcuts")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MetridayTheme.secondary)

                HStack(spacing: 6) {
                    ForEach(statuses) { status in
                        Button("$\(status.label)") {
                            onSelect(status)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MetridayTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(minHeight: 26)
                        .background(MetridayTheme.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .help("Set billing status to \(status.label)")
                    }
                }
            }
        }
    }
}

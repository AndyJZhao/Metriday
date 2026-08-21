import AppKit
import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var preferences: PreferencesStore
    @ObservedObject var monitor: AppActivityMonitor
    @ObservedObject var exclusionStore: ExclusionStore
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var timeEntryStore: TimeEntryStore
    @ObservedObject var calendarStore: CalendarEventStore
    @ObservedObject var reminderStore: ReminderStore
    @ObservedObject var phoneCallStore: PhoneCallStore
    @ObservedObject var screenTimeStore: ScreenTimeStore
    @ObservedObject var localAPIServer: LocalAPIServer
    @ObservedObject var loginItemManager: LoginItemManager
    @ObservedObject var syncStore: SyncStore
    @ObservedObject var integrationStore: IntegrationStore
    @ObservedObject var teamStore: TeamStore
    @ObservedObject var reviewReminderService: ReviewReminderService
    @State private var transferStatus = ""
    @State private var showingExclusionEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 20, weight: .bold))
                    Text("Tracking, privacy, and working-hour behavior")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    trackingPanel
                    reviewReminderPanel
                    workingHoursPanel
                    projectSelectionPanel
                    permissionsPanel
                    calendarPreferencesPanel
                    reminderPreferencesPanel
                    phoneCallPreferencesPanel
                    syncPanel
                    integrationsPanel
                    teamsPanel
                    localAPIPanel
                    exclusionsPanel
                    dataPanel
                }
            }
        }
        .padding(24)
        .frame(width: 560, height: 620)
        .sheet(isPresented: $showingExclusionEditor) {
            ExclusionRuleEditorSheet { field, comparison, pattern, caseSensitive in
                _ = exclusionStore.addRule(
                    field: field,
                    pattern: pattern,
                    isCaseSensitive: caseSensitive,
                    comparison: comparison
                )
                showingExclusionEditor = false
            }
        }
    }

    private var trackingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tracking", systemImage: "waveform.path.ecg")
                .font(.system(size: 15, weight: .bold))

            Toggle("Automatic activity tracking", isOn: Binding(
                get: { monitor.isTracking },
                set: { enabled in
                    if enabled {
                        monitor.resumeTracking()
                    } else {
                        monitor.pauseTracking()
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityIdentifier("settings.automatic-tracking")

            Toggle("Start tracking when Metriday opens", isOn: $preferences.startTrackingWhenAppOpens)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

            Toggle("Stop timers when the Mac goes to sleep", isOn: $preferences.autoStopTimerOnSleep)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

            Toggle("Launch Metriday at login", isOn: Binding(
                get: { loginItemManager.isEnabled },
                set: { loginItemManager.setEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            Text(loginItemManager.statusMessage)
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)

            HStack {
                Text("Idle detection")
                    .font(.system(size: 12))
                Spacer()
                Picker("Idle detection", selection: $preferences.idleThresholdSeconds) {
                    ForEach([60, 120, 180, 300, 600], id: \.self) { seconds in
                        Text("\(seconds / 60) min").tag(seconds)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }

            Text("Idle time is stored as evidence in Today but excluded from active productivity totals.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
        }
        .settingsPanel()
    }

    private var workingHoursPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Working hours", systemImage: "clock")
                .font(.system(size: 15, weight: .bold))

            Toggle("Track on weekends", isOn: $preferences.trackWeekends)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

            Toggle("Track only during working hours", isOn: $preferences.trackOnlyDuringWorkingHours)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

            Toggle("Automatically zoom timeline to working hours", isOn: $preferences.automaticallyZoomTimelineToWorkingHours)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

            Text("When enabled, Activities opens the timeline around the configured working-hours window.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)

            HStack(spacing: 8) {
                Text("From")
                    .font(.system(size: 12))
                timePicker(hour: startHour, minute: startMinute, label: "Start") { hour, minute in
                    preferences.workingHoursStartMinute = hour * 60 + minute
                }
                Text("to")
                    .font(.system(size: 12))
                timePicker(hour: endHour, minute: endMinute, label: "End") { hour, minute in
                    preferences.workingHoursEndMinute = hour * 60 + minute
                }
            }
            .disabled(!preferences.trackOnlyDuringWorkingHours)

            HStack(spacing: 8) {
                Text("Wrap days at")
                    .font(.system(size: 12))
                timePicker(hour: wrapDayHour, minute: wrapDayMinute, label: "Wrap days") { hour, minute in
                    preferences.wrapDaysAtMinute = hour * 60 + minute
                }
            }

            Text("Activity after midnight stays with the previous workday until this time. Set 00:00 for ordinary calendar days.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .lineSpacing(2)
        }
        .settingsPanel()
    }

    private var reviewReminderPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Activity review reminders", systemImage: "bell.badge")
                .font(.system(size: 15, weight: .bold))

            HStack {
                Text("Remind to review activities")
                    .font(.system(size: 12))
                Spacer()
                Picker("Review reminder frequency", selection: $preferences.reviewReminderIntervalMinutes) {
                    Text("Never").tag(0)
                    Text("Every 15 minutes").tag(15)
                    Text("Every 30 minutes").tag(30)
                    Text("Every hour").tag(60)
                    Text("Every 2 hours").tag(120)
                }
                .labelsHidden()
                .frame(width: 160)
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(reviewReminderService.notificationsAuthorized ? MetridayTheme.success : MetridayTheme.warning)
                    .frame(width: 7, height: 7)
                Text(reviewReminderService.notificationStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(MetridayTheme.secondary)
                Spacer()
                Button("Allow Notifications") {
                    reviewReminderService.requestAuthorization()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(preferences.reviewReminderIntervalMinutes == 0)
            }

            Text("When enabled, Metriday sends a local notification summarizing today's tracked time. Activity data stays on this Mac.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .lineSpacing(2)
        }
        .settingsPanel()
    }

    private var permissionsPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("Permissions", systemImage: "lock.shield")
                .font(.system(size: 15, weight: .bold))

            HStack {
                Circle()
                    .fill(monitor.accessibilityTrusted ? MetridayTheme.success : MetridayTheme.warning)
                    .frame(width: 8, height: 8)
                Text(monitor.accessibilityTrusted ? "Accessibility access available" : "Accessibility access needed for window titles")
                    .font(.system(size: 11))
                Spacer()
                Button(monitor.accessibilityTrusted ? "Open Settings" : "Request Access") {
                    if monitor.accessibilityTrusted {
                        monitor.openAccessibilitySettings()
                    } else {
                        monitor.requestAccessibilityAccess()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack {
                Circle()
                    .fill(MetridayTheme.accent)
                    .frame(width: 8, height: 8)
                Text("Safari and Chrome URLs use macOS Automation permission when available")
                    .font(.system(size: 11))
                    .foregroundStyle(MetridayTheme.secondary)
            }

            HStack {
                Circle()
                    .fill(reminderStore.isAuthorized ? MetridayTheme.success : MetridayTheme.secondary)
                    .frame(width: 8, height: 8)
                Text(reminderStore.isAuthorized ? "Reminders access available" : "Reminders access not connected")
                    .font(.system(size: 11))
                Spacer()
                Button(reminderStore.isAuthorized ? "Refresh" : "Request Access") {
                    if reminderStore.isAuthorized {
                        reminderStore.loadCompleted(for: .now)
                    } else {
                        reminderStore.requestAccess()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack {
                Circle()
                    .fill(phoneCallStore.databaseAvailable ? MetridayTheme.success : MetridayTheme.secondary)
                    .frame(width: 8, height: 8)
                Text(phoneCallStore.databaseAvailable ? "Phone Calls access available" : "Phone Calls access not connected")
                    .font(.system(size: 11))
                Spacer()
                Button(phoneCallStore.databaseAvailable ? "Refresh" : "Open Settings") {
                    if phoneCallStore.databaseAvailable {
                        phoneCallStore.loadCalls(for: .now)
                    } else {
                        phoneCallStore.openAccessSettings()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack {
                Circle()
                    .fill(screenTimeStore.databaseAvailable ? MetridayTheme.success : MetridayTheme.secondary)
                    .frame(width: 8, height: 8)
                Text(screenTimeStore.databaseAvailable ? "Screen Time access available" : "Screen Time not connected")
                    .font(.system(size: 11))
                Spacer()
                Button(screenTimeStore.databaseAvailable ? "Refresh" : "Open Settings") {
                    if screenTimeStore.databaseAvailable {
                        screenTimeStore.load(for: .now)
                    } else {
                        screenTimeStore.openAccessSettings()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .settingsPanel()
    }

    private var projectSelectionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Project selection", systemImage: "folder.badge.gearshape")
                .font(.system(size: 15, weight: .bold))

            Toggle("Include sub-projects when selecting a project", isOn: $preferences.includeSubprojectsWhenSelectingProject)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

            Text("When enabled, selecting a parent project in Activities or Stats includes activity assigned to its descendants. Collapsed project totals always include their children.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .lineSpacing(2)
        }
        .settingsPanel()
    }

    private var reminderPreferencesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Reminders filters", systemImage: "checklist")
                .font(.system(size: 15, weight: .bold))

            if reminderStore.isAuthorized {
                Toggle("Hide recurring reminders", isOn: $reminderStore.hideRecurringReminders)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())

                Toggle("All reminder lists", isOn: Binding(
                    get: { reminderStore.includedListTitles.isEmpty },
                    set: { reminderStore.setAllListsIncluded($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

                ForEach(reminderStore.availableListTitles, id: \.self) { listTitle in
                    Toggle(listTitle, isOn: Binding(
                        get: {
                            reminderStore.includedListTitles.isEmpty
                                || reminderStore.includedListTitles.contains(listTitle)
                        },
                        set: { reminderStore.setListIncluded(listTitle, included: $0) }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .padding(.leading, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }

                Text(reminderStore.includedListTitles.isEmpty ? "Showing completed reminders from every list." : "Only selected reminder lists are shown on the Activities timeline.")
                    .font(.system(size: 10))
                    .foregroundStyle(MetridayTheme.secondary)
            } else {
                Text("Connect Reminders first to choose lists and filter recurring items.")
                    .font(.system(size: 11))
                    .foregroundStyle(MetridayTheme.secondary)
            }
        }
        .settingsPanel()
    }

    private var calendarPreferencesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Calendar filters", systemImage: "calendar.badge.clock")
                .font(.system(size: 15, weight: .bold))

            if calendarStore.isAuthorized {
                Toggle("All calendars", isOn: Binding(
                    get: { calendarStore.includedCalendarTitles.isEmpty },
                    set: { calendarStore.setAllCalendarsIncluded($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

                ForEach(calendarStore.availableCalendarTitles, id: \.self) { calendarTitle in
                    Toggle(calendarTitle, isOn: Binding(
                        get: {
                            calendarStore.includedCalendarTitles.isEmpty
                                || calendarStore.includedCalendarTitles.contains(calendarTitle)
                        },
                        set: { calendarStore.setCalendarIncluded(calendarTitle, included: $0) }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .padding(.leading, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }

                Text(calendarStore.includedCalendarTitles.isEmpty ? "Showing timed events from every calendar. All-day events stay hidden to keep the timeline focused." : "Only selected calendars are shown; all-day events stay hidden.")
                    .font(.system(size: 10))
                    .foregroundStyle(MetridayTheme.secondary)
            } else {
                Text("Connect Calendar first to choose which calendars appear on the Activities timeline.")
                    .font(.system(size: 11))
                    .foregroundStyle(MetridayTheme.secondary)
            }
        }
        .settingsPanel()
    }

    private var dataPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("Local data", systemImage: "internaldrive")
                .font(.system(size: 15, weight: .bold))
            Text("Activity history, projects, time entries, and preferences stay in ~/Library/Application Support/Metriday.")
                .font(.system(size: 11))
                .foregroundStyle(MetridayTheme.secondary)
                .lineSpacing(3)
            Button("Show Application Support Folder") {
                let folder = FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first!.appendingPathComponent("Metriday", isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            HStack(spacing: 8) {
                Button("Export Projects") { exportProjects() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Import Projects") { importProjects() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Export Time Entries") { exportTimeEntries() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Import Time Entries") { importTimeEntries() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Text("Project imports merge by hierarchy path. Time-entry imports skip duplicate IDs; a running timer is never imported as active.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
            if !transferStatus.isEmpty {
                Text(transferStatus)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MetridayTheme.accent)
            }
        }
        .settingsPanel()
    }

    private var localAPIPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("Local automation API", systemImage: "network")
                .font(.system(size: 15, weight: .bold))
            HStack {
                Circle()
                    .fill(localAPIServer.isRunning ? MetridayTheme.success : MetridayTheme.secondary)
                    .frame(width: 8, height: 8)
                Text(localAPIServer.isRunning ? "Listening on localhost" : "Local API stopped")
                    .font(.system(size: 11))
                Spacer()
                Button(localAPIServer.isRunning ? "Stop" : "Start") {
                    if localAPIServer.isRunning {
                        localAPIServer.stop()
                    } else {
                        localAPIServer.start()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text(localAPIServer.endpoint)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MetridayTheme.secondary)
            Text("MCP endpoint · \(localAPIServer.baseEndpoint)/mcp")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(MetridayTheme.accent)
            Text("Timing-compatible MCP tools expose activity, projects, time entries, and timers to an explicitly connected AI client. The endpoint stays local unless LAN access is enabled below.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .lineSpacing(2)
            Toggle("Allow access from the local network", isOn: Binding(
                get: { preferences.allowLocalNetworkAPI },
                set: { enabled in
                    preferences.allowLocalNetworkAPI = enabled
                    localAPIServer.setAllowsLAN(enabled)
                }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            Text(localAPIServer.allowsLAN
                 ? "LAN access is enabled on port \(localAPIServer.port). Enter this Mac's local IP in the Web App Settings on another device. The API has no login, so use this only on a trusted private network."
                 : "Read activities, projects, and time entries through localhost HTTP. LAN access stays off until you explicitly enable it here.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .lineSpacing(2)
            Text(localAPIServer.statusMessage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MetridayTheme.accent)
        }
        .settingsPanel()
    }

    private var integrationsPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("Project integrations", systemImage: "arrow.triangle.2.circlepath.circle")
                .font(.system(size: 15, weight: .bold))
            Text("Import ClickUp tasks, Linear issues, or Clio matters as local Metriday projects. Sync changes performs a guarded two-way reconciliation; conflicts are left untouched for review. Tokens are stored in the macOS Keychain and network access happens only when you press a button.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .lineSpacing(2)

            ForEach(ExternalIntegrationProvider.allCases) { provider in
                IntegrationProviderRow(
                    provider: provider,
                    integrationStore: integrationStore,
                    projectStore: projectStore
                )
                if provider != .clio {
                    Divider()
                }
            }

            Text("GrandTotal can consume Metriday's CSV/XLSX report exports; use Review → Reports & exports for the billing handoff.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .lineSpacing(2)
        }
        .settingsPanel()
    }

    private var teamsPanel: some View {
        TeamWorkspacePanel(
            teamStore: teamStore,
            projectStore: projectStore,
            timeEntryStore: timeEntryStore
        )
            .settingsPanel()
    }

    private var phoneCallPreferencesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Phone Calls filters", systemImage: "phone.arrow.down.left")
                .font(.system(size: 15, weight: .bold))

            Toggle("Notify when a video or audio call ends", isOn: $preferences.callNotificationsEnabled)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

            Text("After a tracked call lasts at least one minute, show a local notification and open the call time-entry prompt when Metriday is active.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .lineSpacing(2)

            if phoneCallStore.hiddenAddresses.isEmpty {
                Text("Calls are shown by default. Hide a number from the Phone Calls timeline menu; hidden calls stay out of the timeline but remain in macOS CallHistory.")
                    .font(.system(size: 10))
                    .foregroundStyle(MetridayTheme.secondary)
                    .lineSpacing(2)
            } else {
                HStack {
                    Text("Hidden numbers")
                        .font(.system(size: 12))
                    Spacer()
                    Text("\(phoneCallStore.hiddenAddresses.count)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MetridayTheme.secondary)
                    Button("Show All") {
                        phoneCallStore.showAllAddresses()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                ForEach(phoneCallStore.hiddenAddresses.sorted(), id: \.self) { address in
                    HStack(spacing: 8) {
                        Image(systemName: "phone.arrow.down.left")
                            .foregroundStyle(MetridayTheme.secondary)
                            .frame(width: 18)
                        Text(address)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Button("Show") {
                            phoneCallStore.setAddressHidden(address, hidden: false)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                Text("Hidden calls stay in the source database and are excluded only from Metriday's timeline and API.")
                    .font(.system(size: 10))
                    .foregroundStyle(MetridayTheme.secondary)
                    .lineSpacing(2)
            }
        }
        .settingsPanel()
    }

    private var syncPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("Timing Sync", systemImage: "arrow.triangle.2.circlepath.icloud")
                .font(.system(size: 15, weight: .bold))
            HStack {
                Circle()
                    .fill(syncStore.isEnabled ? MetridayTheme.success : MetridayTheme.secondary)
                    .frame(width: 8, height: 8)
                Text(syncStore.isEnabled ? "Sync enabled" : "Sync not configured")
                    .font(.system(size: 11))
                Spacer()
                Button(syncStore.isEnabled ? "Sync Now" : "Choose Folder") {
                    if syncStore.isEnabled {
                        _ = syncStore.syncNow()
                    } else {
                        chooseSyncFolder()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if syncStore.isEnabled {
                    Button("Restore latest") {
                        _ = syncStore.restoreLatestBackup()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(syncStore.backupCount == 0)
                }
            }
            HStack(spacing: 8) {
                Text("Device name")
                    .font(.system(size: 11))
                TextField("This Mac", text: $syncStore.deviceName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }
            if let folderURL = syncStore.folderURL {
                Text(folderURL.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MetridayTheme.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Button("Change Folder") { chooseSyncFolder() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Disable") { syncStore.disable() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else {
                Text("Choose a folder shared by your Macs, such as an iCloud Drive folder. Each device keeps its own archive and merges offline changes.")
                    .font(.system(size: 10))
                    .foregroundStyle(MetridayTheme.secondary)
                    .lineSpacing(2)
            }
            Text(syncStore.statusMessage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MetridayTheme.accent)
            if syncStore.isEnabled {
                Text("\(syncStore.backupCount) rolling cloud backup\(syncStore.backupCount == 1 ? "" : "s") are retained in the shared folder.")
                    .font(.system(size: 10))
                    .foregroundStyle(MetridayTheme.secondary)
            }
        }
        .settingsPanel()
    }

    private func chooseSyncFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use for Sync"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        syncStore.configure(folderURL: url)
    }

    private func exportProjects() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "metriday-projects.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try projectStore.exportArchiveData().write(to: url, options: .atomic)
            transferStatus = "Projects exported · \(url.lastPathComponent)"
        } catch {
            transferStatus = "Project export failed · \(error.localizedDescription)"
        }
    }

    private func importProjects() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = try projectStore.importArchiveData(Data(contentsOf: url))
            transferStatus = "Imported \(result.projects) projects and \(result.rules) rules"
        } catch {
            transferStatus = "Project import failed · \(error.localizedDescription)"
        }
    }

    private func exportTimeEntries() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "metriday-time-entries.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try timeEntryStore.exportArchiveData().write(to: url, options: .atomic)
            transferStatus = "Time entries exported · \(url.lastPathComponent)"
        } catch {
            transferStatus = "Time-entry export failed · \(error.localizedDescription)"
        }
    }

    private func importTimeEntries() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try timeEntryStore.importArchiveData(Data(contentsOf: url))
            transferStatus = "Imported \(count) time entries"
        } catch {
            transferStatus = "Time-entry import failed · \(error.localizedDescription)"
        }
    }

    private var exclusionsPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Excluded activity", systemImage: "eye.slash")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button {
                    showingExclusionEditor = true
                } label: {
                    Label("Add rule", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("settings.new-exclusion-rule")
            }

            Text("Exclude apps, browser pages, windows, paths, or devices before activity is written.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)

            HStack {
                if monitor.currentBundleIdentifier.isEmpty {
                    Text("No frontmost application available")
                        .font(.system(size: 11))
                        .foregroundStyle(MetridayTheme.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(monitor.currentApplication)
                            .font(.system(size: 11, weight: .semibold))
                        Text(monitor.currentBundleIdentifier)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(MetridayTheme.secondary)
                    }
                    Spacer()
                    if exclusionStore.isExcluded(monitor.currentBundleIdentifier) {
                        Button("Remove exclusion") {
                            exclusionStore.remove(bundleIdentifier: monitor.currentBundleIdentifier)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button("Exclude current app") {
                            exclusionStore.add(bundleIdentifier: monitor.currentBundleIdentifier)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            if !exclusionStore.rules.isEmpty {
                Divider()
                ForEach(exclusionStore.rules) { rule in
                    HStack {
                        Image(systemName: "eye.slash")
                            .foregroundStyle(MetridayTheme.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(rule.field.label) \(rule.comparison.label)")
                                .font(.system(size: 10, weight: .semibold))
                            Text(rule.pattern)
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            exclusionStore.remove(rule)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Text(exclusionStore.statusMessage + ". Matching activity is not written to activity history.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
        }
        .settingsPanel()
    }

    private var startHour: Int {
        preferences.workingHoursStartMinute / 60
    }

    private var startMinute: Int {
        preferences.workingHoursStartMinute % 60
    }

    private var endHour: Int {
        preferences.workingHoursEndMinute / 60
    }

    private var endMinute: Int {
        preferences.workingHoursEndMinute % 60
    }

    private var wrapDayHour: Int {
        preferences.wrapDaysAtMinute / 60
    }

    private var wrapDayMinute: Int {
        preferences.wrapDaysAtMinute % 60
    }

    private func timePicker(
        hour: Int,
        minute: Int,
        label: String,
        onChange: @escaping (Int, Int) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            Picker(label, selection: Binding(
                get: { hour },
                set: { onChange($0, minute) }
            )) {
                ForEach(0..<24, id: \.self) { value in
                    Text(String(format: "%02d", value)).tag(value)
                }
            }
            .labelsHidden()
            .frame(width: 58)

            Text(":")
                .foregroundStyle(MetridayTheme.secondary)

            Picker("\(label) minutes", selection: Binding(
                get: { minute },
                set: { onChange(hour, $0) }
            )) {
                ForEach([0, 15, 30, 45], id: \.self) { value in
                    Text(String(format: "%02d", value)).tag(value)
                }
            }
            .labelsHidden()
            .frame(width: 58)
        }
    }
}

private struct IntegrationProviderRow: View {
    let provider: ExternalIntegrationProvider
    @ObservedObject var integrationStore: IntegrationStore
    @ObservedObject var projectStore: ProjectStore

    @State private var workspace: String
    @State private var endpoint: String
    @State private var token: String

    init(
        provider: ExternalIntegrationProvider,
        integrationStore: IntegrationStore,
        projectStore: ProjectStore
    ) {
        self.provider = provider
        self.integrationStore = integrationStore
        self.projectStore = projectStore
        let configuration = integrationStore.configuration(for: provider)
        _workspace = State(initialValue: configuration.workspace)
        _endpoint = State(initialValue: configuration.endpoint)
        _token = State(initialValue: integrationStore.token(for: provider))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(provider.title)
                    .font(.system(size: 12, weight: .semibold))
                Text(provider.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(MetridayTheme.secondary)
                Spacer()
                Circle()
                    .fill(integrationStore.configuration(for: provider).connected ? MetridayTheme.success : MetridayTheme.secondary)
                    .frame(width: 7, height: 7)
            }

            HStack(spacing: 7) {
                TextField(provider == .clickUp ? "List ID" : "Workspace / team (optional)", text: $workspace)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10, design: .monospaced))
                SecureField(provider.tokenHint, text: $token)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))
            }

            TextField("API endpoint", text: $endpoint)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))

            HStack(spacing: 7) {
                Button("Save") {
                    integrationStore.setConfiguration(
                        provider: provider,
                        workspace: workspace,
                        endpoint: endpoint,
                        token: token
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Test connection") {
                    integrationStore.setConfiguration(
                        provider: provider,
                        workspace: workspace,
                        endpoint: endpoint,
                        token: token
                    )
                    Task { await integrationStore.testConnection(provider) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(integrationStore.isWorking)

                Button("Import projects") {
                    integrationStore.setConfiguration(
                        provider: provider,
                        workspace: workspace,
                        endpoint: endpoint,
                        token: token
                    )
                    Task { await integrationStore.importProjects(from: provider, into: projectStore) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(integrationStore.isWorking)

                Button("Sync changes") {
                    integrationStore.setConfiguration(
                        provider: provider,
                        workspace: workspace,
                        endpoint: endpoint,
                        token: token
                    )
                    Task { await integrationStore.syncProjects(from: provider, with: projectStore) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(integrationStore.isWorking)

                if integrationStore.configuration(for: provider).connected {
                    Button("Disconnect") {
                        integrationStore.disconnect(provider)
                        token = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Text(integrationStore.configuration(for: provider).statusMessage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MetridayTheme.accent)
            let conflictCount = integrationStore.syncStatus(for: provider)["conflicts"] as? Int ?? 0
            if conflictCount > 0 {
                Label("\(conflictCount) conflict\(conflictCount == 1 ? "" : "s") preserved; resolve locally or in \(provider.title), then sync again.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MetridayTheme.warning)
            }
        }
    }
}

private struct TeamWorkspacePanel: View {
    @ObservedObject var teamStore: TeamStore
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var timeEntryStore: TimeEntryStore

    @State private var newTeamName = ""
    @State private var selectedTeamID: UUID?
    @State private var newMemberName = ""
    @State private var newMemberEmail = ""

    init(
        teamStore: TeamStore,
        projectStore: ProjectStore,
        timeEntryStore: TimeEntryStore
    ) {
        self.teamStore = teamStore
        self.projectStore = projectStore
        self.timeEntryStore = timeEntryStore
        _selectedTeamID = State(initialValue: teamStore.activeTeams.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("Team workspace", systemImage: "person.3")
                .font(.system(size: 15, weight: .bold))
            Text("Team data stays local or follows the selected Sync folder. Project ownership is explicit, while ordinary activity views remain personal to each device.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .lineSpacing(2)

            HStack(spacing: 7) {
                TextField("New team name", text: $newTeamName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                Button("Create team") {
                    if let teamID = teamStore.createTeam(name: newTeamName) {
                        selectedTeamID = teamID
                        newTeamName = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newTeamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if teamStore.activeTeams.isEmpty {
                Text("No local team yet. Personal projects continue to work without a team.")
                    .font(.system(size: 10))
                    .foregroundStyle(MetridayTheme.secondary)
            } else {
                Picker("Team", selection: $selectedTeamID) {
                    ForEach(teamStore.activeTeams) { team in
                        Text("\(team.name) · \(team.members.count) members")
                            .tag(team.id as UUID?)
                    }
                }
                .labelsHidden()

                if let selectedTeamID,
                   let team = teamStore.team(selectedTeamID) {
                    HStack(spacing: 7) {
                        TextField("Member name", text: $newMemberName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 10))
                        TextField("Email (optional)", text: $newMemberEmail)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 10))
                        Button("Add") {
                            if teamStore.addMember(
                                to: team.id,
                                name: newMemberName,
                                email: newMemberEmail
                            ) != nil {
                                newMemberName = ""
                                newMemberEmail = ""
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(newMemberName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    ForEach(team.members.filter(\.isActive)) { member in
                        HStack(spacing: 7) {
                            Image(systemName: member.id == teamStore.currentMemberID ? "person.crop.circle.fill" : "person.crop.circle")
                                .foregroundStyle(MetridayTheme.secondary)
                            Text(member.name)
                                .font(.system(size: 10, weight: .medium))
                            if !member.email.isEmpty {
                                Text(member.email)
                                    .font(.system(size: 10))
                                    .foregroundStyle(MetridayTheme.secondary)
                            }
                            Text(member.role)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(MetridayTheme.secondary)
                            Spacer()
                            if member.id != teamStore.currentMemberID {
                                Button {
                                    teamStore.removeMember(member.id, from: team.id)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    let projectCount = projectStore.activeProjects.filter { $0.teamID == team.id }.count
                    Text("\(projectCount) project\(projectCount == 1 ? "" : "s") assigned to this team")
                        .font(.system(size: 10))
                        .foregroundStyle(MetridayTheme.secondary)
                    let projectIDs = Set(
                        projectStore.activeProjects
                            .filter { $0.teamID == team.id }
                            .map(\.id)
                    )
                    let trackedSeconds = timeEntryStore.materializedEntries()
                        .filter { entry in
                            guard let projectID = entry.projectID else { return false }
                            return projectIDs.contains(projectID)
                        }
                        .reduce(0) { $0 + $1.durationSeconds }
                    Text("Aggregate tracked: \(formatTeamDuration(trackedSeconds))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MetridayTheme.accent)
                }
            }
            Text(teamStore.statusMessage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MetridayTheme.accent)
        }
    }

    private func formatTeamDuration(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return "\(hours)h \(minutes)m"
    }
}

private struct ExclusionRuleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (ActivityExclusionField, ProjectRuleComparison, String, Bool) -> Void

    @State private var field: ActivityExclusionField = .application
    @State private var comparison: ProjectRuleComparison = .contains
    @State private var pattern = ""
    @State private var caseSensitive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Exclusion Rule")
                .font(.system(size: 18, weight: .bold))
            Text("Matching activity is ignored before it is saved.")
                .font(.system(size: 11))
                .foregroundStyle(MetridayTheme.secondary)

            Picker("Match", selection: $field) {
                ForEach(ActivityExclusionField.allCases) { value in
                    Text(value.label).tag(value)
                }
            }

            Picker("Relation", selection: $comparison) {
                ForEach(ProjectRuleComparison.allCases.filter { $0 != .isBetween }) { value in
                    Text(value.label).tag(value)
                }
            }

            TextField("Pattern or value", text: $pattern)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            Toggle("Case sensitive", isOn: $caseSensitive)
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

            Text("Domain rules compare the browser host. Regex rules compare the selected field directly.")
                .font(.system(size: 10))
                .foregroundStyle(MetridayTheme.secondary)
                .lineSpacing(3)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add Rule", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func save() {
        let value = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onSave(field, comparison, value, caseSensitive)
        dismiss()
    }
}

private extension View {
    func settingsPanel() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(MetridayTheme.line, lineWidth: 1)
            )
    }
}

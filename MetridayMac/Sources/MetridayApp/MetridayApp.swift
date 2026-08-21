import AppKit
import SwiftUI

@main
@MainActor
struct MetridayApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 1080, minHeight: 720)
                .preferredColorScheme(.light)
                .onAppear {
                    MetridayAppleScriptRuntime.appState = appState
                }
                .onOpenURL { url in
                    appState.handle(url: url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 930)
        .commands {
            CommandGroup(after: .undoRedo) {
                Button("Undo Create Time Entries") {
                    _ = appState.timeEntryStore.undoEntryOMaticCreation()
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!appState.timeEntryStore.canUndoEntryOMatic)
            }
            CommandMenu("Navigate") {
                Button("Today") { appState.section = .today }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Plan") { appState.section = .plan }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Activities") { appState.section = .activities }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Stats") { appState.section = .stats }
                    .keyboardShortcut("4", modifiers: [.command])
                Button("Reports") { appState.section = .reports }
                    .keyboardShortcut("5", modifiers: [.command])
                Button("Teams") { appState.section = .teams }
                    .keyboardShortcut("6", modifiers: [.command])
                Button("Review") { appState.section = .review }
                    .keyboardShortcut("7", modifiers: [.command])
                Button("Rules") { appState.section = .rules }
                    .keyboardShortcut("8", modifiers: [.command])
            }
            CommandMenu("Focus") {
                Button(appState.focusSessionActive ? "Pause Focus" : "Start Focus") {
                    _ = appState.toggleFocusSession()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(!appState.focusSessionActive && appState.currentTask == nil)
            }
            CommandMenu("Tracking") {
                Button(appState.activityMonitor.isTracking ? "Pause Tracking" : "Resume Tracking") {
                    appState.activityMonitor.toggleTracking()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                Button(appState.timeEntryStore.runningTimer == nil ? "Quick Start Timer" : "Stop Timer") {
                    appState.quickStartTimer()
                }
                .keyboardShortcut("t", modifiers: [.control, .option, .command])
                let recentTimers = appState.timeEntryStore.recentTimerEntries(limit: 5)
                if !recentTimers.isEmpty {
                    Menu("Resume Recent Timer") {
                        ForEach(recentTimers) { entry in
                            Button {
                                appState.startTimer(reusing: entry)
                            } label: {
                                Text(entry.title)
                            }
                            .disabled(appState.timeEntryStore.runningTimer != nil)
                        }
                    }
                }
            }
        }

        MenuBarExtra {
            MenuBarStatusView(appState: appState)
        } label: {
            Label("Metriday", systemImage: "timer")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarStatusView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        let recentTimers = appState.timeEntryStore.recentTimerEntries(limit: 5)
        VStack(alignment: .leading, spacing: 10) {
            Text("Metriday 日衡")
                .font(.headline)
            Text("Local timer and tracking controls")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if appState.currentTask != nil || appState.focusSessionActive {
                Button(appState.focusSessionActive ? "Pause Focus Session" : "Start Focus Session") {
                    _ = appState.toggleFocusSession()
                }
                .disabled(!appState.focusSessionActive && appState.currentTask == nil)
            }
            Button("Start / Stop Timer") {
                appState.quickStartTimer()
            }
            if appState.timeEntryStore.runningTimer == nil, !recentTimers.isEmpty {
                Menu("Resume Recent Timer") {
                    ForEach(recentTimers) { entry in
                        Button {
                            appState.startTimer(reusing: entry)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(entry.title)
                                Text("\(projectLabel(for: entry.projectID)) · \(durationLabel(entry.durationSeconds))")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Button("−5m") {
                    appState.timeEntryStore.adjustRunningTimerStart(by: -300)
                }
                Button("+5m") {
                    appState.timeEntryStore.adjustRunningTimerStart(by: 300)
                }
            }
            Divider()
            Button("Pause / Resume Tracking") {
                appState.activityMonitor.toggleTracking()
            }

            Button("Open Metriday") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            Button("Quit Metriday") {
                NSApp.terminate(nil)
            }
        }
        .padding(8)
    }

    private func projectLabel(for projectID: UUID?) -> String {
        guard let projectID else { return "Unassigned" }
        return appState.projectStore.name(for: projectID)
    }

    private func durationLabel(_ seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60).rounded()))
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 { return "\(hours)h \(remainder)m" }
        return "\(minutes)m"
    }
}

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
                Button(appState.focusIsActive ? "Pause Focus" : "Start Focus") {
                    appState.focusIsActive.toggle()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
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
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Metriday 日衡")
                .font(.headline)
            Text("Local timer and tracking controls")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Start / Stop Timer") {
                appState.quickStartTimer()
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
}

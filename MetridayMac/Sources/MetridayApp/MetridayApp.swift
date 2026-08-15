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
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 930)
        .commands {
            CommandMenu("Navigate") {
                Button("Today") { appState.section = .today }
                    .keyboardShortcut("1", modifiers: [.command])
                Button("Plan") { appState.section = .plan }
                    .keyboardShortcut("2", modifiers: [.command])
                Button("Review") { appState.section = .review }
                    .keyboardShortcut("3", modifiers: [.command])
                Button("Rules") { appState.section = .rules }
                    .keyboardShortcut("4", modifiers: [.command])
            }
            CommandMenu("Focus") {
                Button(appState.focusIsActive ? "Pause Focus" : "Start Focus") {
                    appState.focusIsActive.toggle()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
    }
}

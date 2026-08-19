import Combine
import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage = "Login item not configured"

    init() {
        refresh()
    }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled:
            isEnabled = true
            statusMessage = "Metriday will open at login"
        case .requiresApproval:
            isEnabled = false
            statusMessage = "Login item needs approval in System Settings"
        case .notRegistered:
            isEnabled = false
            statusMessage = "Metriday will not open at login"
        case .notFound:
            isEnabled = false
            statusMessage = "Metriday login item is unavailable in this build"
        @unknown default:
            isEnabled = false
            statusMessage = "Login item status unavailable"
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
        } catch {
            refresh()
            statusMessage = "Could not update login item · \(error.localizedDescription)"
        }
    }
}

import AppKit

/// Keeps the Quick Start/Stop Timer command available while another app is
/// frontmost. The local monitor covers key events delivered to Metriday itself;
/// the global monitor covers events delivered to other applications.
@MainActor
final class GlobalShortcutMonitor {
    nonisolated(unsafe) private var globalMonitor: Any?
    nonisolated(unsafe) private var localMonitor: Any?
    private let action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
        self.action = action

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isQuickStartShortcut(event) else { return }
            Task { @MainActor [weak self] in
                self?.action()
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isQuickStartShortcut(event) else { return event }
            Task { @MainActor [weak self] in
                self?.action()
            }
            return nil
        }
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    private static func isQuickStartShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers == [.command, .control, .option] else { return false }
        return event.charactersIgnoringModifiers?.lowercased() == "t"
    }
}

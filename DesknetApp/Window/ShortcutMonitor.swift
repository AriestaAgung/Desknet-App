import AppKit

/// Command-Control-Z while Desknet.app is focused toggles the window, matching the
/// Simulator shortcut. Local only: a global hotkey would swallow the key before the Simulator gets it.
final class DesknetShortcutMonitor {
    private var localMonitor: Any?

    func start(action: @escaping () -> Void) {
        stop()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard modifiers == [.command, .control], event.charactersIgnoringModifiers?.lowercased() == "z" else {
                return event
            }
            action()
            return nil
        }
    }

    func stop() {
        guard let localMonitor else { return }
        NSEvent.removeMonitor(localMonitor)
        self.localMonitor = nil
    }
}

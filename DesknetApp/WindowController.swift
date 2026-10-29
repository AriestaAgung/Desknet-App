import AppKit
import SwiftUI

final class DesknetWindowController: NSWindowController {
    private let defaultFrame = NSRect(x: 180, y: 160, width: 1180, height: 760)
    private let minimumWindowSize = NSSize(width: 980, height: 620)

    init(viewModel: DesknetMonitorViewModel) {
        let window = NSWindow(
            contentRect: defaultFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Desknet Network Logs"
        window.minSize = minimumWindowSize
        window.contentViewController = NSHostingController(rootView: DesknetMonitorRootView(viewModel: viewModel))
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("Desknet.Window.v2")

        super.init(window: window)
        shouldCascadeWindows = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showDesknetWindow() {
        guard let window else { return }

        if window.frame.width < minimumWindowSize.width || window.frame.height < minimumWindowSize.height {
            window.setFrame(defaultFrame, display: true, animate: false)
            window.center()
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hideDesknetWindow() {
        window?.orderOut(nil)
    }

    func toggleDesknetWindow() {
        guard let window else { return }
        if window.isVisible, NSApp.isActive {
            hideDesknetWindow()
        } else {
            showDesknetWindow()
        }
    }
}

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

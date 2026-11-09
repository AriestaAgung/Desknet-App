import AppKit

/// Composition root: builds the services, view model and window, routes bridge commands, owns lifecycle.
@main
@MainActor
final class DesknetAppDelegate: NSObject, NSApplicationDelegate {
    private static let delegate = DesknetAppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }

    private let store = DesknetStore()
    private let shortcutMonitor = DesknetShortcutMonitor()
    private let runningApps = RunningAppsMonitor()
    private var windowController: DesknetWindowController?
    private var listener: DesknetBridgeListener?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DesknetAgentInstaller.install()
        runningApps.start()

        let viewModel = MonitorViewModel(store: store, runningApps: runningApps) { text in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        let controller = DesknetWindowController(viewModel: viewModel)
        windowController = controller

        NSApp.mainMenu = MainMenu.make(
            showLogs: { controller.showDesknetWindow() },
            clearLogs: { [store] in store.clear() },
            showHook: { [weak self] in self?.showHookAlert() }
        )

        startListener(controller: controller)
        shortcutMonitor.start { controller.toggleDesknetWindow() }
        controller.showDesknetWindow()
        if !DesknetHookInstaller.isInstalled { showHookAlert() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Remove the socket file so the next launch doesn't find a stale one.
        listener?.stop()
    }

    /// Dock click with the window hidden brings it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.showDesknetWindow()
        return true
    }

    private func startListener(controller: DesknetWindowController) {
        let listener = DesknetBridgeListener(store: store) { message in
            Task { @MainActor in
                switch message {
                case .show: controller.showDesknetWindow()
                case .hide: controller.hideDesknetWindow()
                case .toggle: controller.toggleDesknetWindow()
                case .entry: break
                }
            }
        }
        self.listener = listener
        if listener.start() != .listening {
            showListenerAlert()
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in listener.repairIfNeeded() }
    }

    /// Install when missing, Remove when present. Also offered on launch while missing.
    private func showHookAlert() {
        let installed = DesknetHookInstaller.isInstalled
        let prompt = HookPrompt(isInstalled: installed)
        let alert = NSAlert()
        alert.messageText = prompt.title
        alert.informativeText = prompt.message
        alert.addButton(withTitle: prompt.confirm)
        alert.addButton(withTitle: prompt.cancel)
        alert.buttons[0].hasDestructiveAction = prompt.isDestructive
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try installed ? DesknetHookInstaller.uninstall() : DesknetHookInstaller.install()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func showListenerAlert() {
        let alert = NSAlert()
        alert.messageText = "Desknet can't receive logs"
        alert.informativeText = "Another Desknet viewer is already using \(DesknetBridgeSocket.path()), or the socket couldn't be created. Quit the other viewer and reopen Desknet."
        alert.runModal()
    }
}

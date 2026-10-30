import AppKit

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
        NSApp.mainMenu = makeMainMenu()
        DesknetAgentInstaller.install()

        runningApps.start()
        let controller = DesknetWindowController(
            viewModel: DesknetMonitorViewModel(store: store),
            runningApps: runningApps
        )
        windowController = controller

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

        shortcutMonitor.start { controller.toggleDesknetWindow() }
        controller.showDesknetWindow()
        if !DesknetHookInstaller.isInstalled { showHookAlert(nil) }
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

    @objc private func clearLogs(_ sender: Any?) {
        store.clear()
    }

    @objc private func showLogs(_ sender: Any?) {
        windowController?.showDesknetWindow()
    }

    /// Install when missing, Remove when present. Also offered on launch while missing.
    @objc private func showHookAlert(_ sender: Any?) {
        let installed = DesknetHookInstaller.isInstalled
        let alert = NSAlert()
        alert.messageText = installed ? "Xcode hook is installed" : "Install the Xcode hook?"
        alert.informativeText = installed
            ? "Remove it before you delete Desknet. Apps run from Xcode will no longer load the Desknet agent."
            : "Desknet adds one import line to ~/.lldbinit-Xcode and ~/.lldbinit-lldb-rpc-server so apps you run from Xcode send their network logs here. Restart Xcode afterwards."
        alert.addButton(withTitle: installed ? "Remove" : "Install")
        alert.addButton(withTitle: installed ? "Cancel" : "Not Now")
        if installed { alert.buttons[0].hasDestructiveAction = true }
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

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "About Desknet", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Desknet", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit Desknet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(app, title: "Desknet", to: main)

        // Standard edit actions so Copy/Paste/Select All work in the search field and text views.
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(edit, title: "Edit", to: main)

        let logs = NSMenu(title: "Logs")
        logs.addItem(withTitle: "Show Logs", action: #selector(showLogs(_:)), keyEquivalent: "l").target = self
        let clear = logs.addItem(withTitle: "Clear Logs", action: #selector(clearLogs(_:)), keyEquivalent: "k")
        clear.target = self
        addSubmenu(logs, title: "Logs", to: main)

        let hook = NSMenu(title: "Hook")
        hook.addItem(withTitle: "Xcode Hook…", action: #selector(showHookAlert(_:)), keyEquivalent: "").target = self
        addSubmenu(hook, title: "Hook", to: main)

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(window, title: "Window", to: main)
        NSApp.windowsMenu = window

        return main
    }

    private func addSubmenu(_ submenu: NSMenu, title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }
}

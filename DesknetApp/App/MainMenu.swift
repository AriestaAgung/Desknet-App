import AppKit

/// Desknet's menu bar. App-specific items call the closures passed to `make`.
@MainActor
enum MainMenu {
    static func make(
        showLogs: @escaping () -> Void,
        clearLogs: @escaping () -> Void,
        showHook: @escaping () -> Void
    ) -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(
            withTitle: "About Desknet", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
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
        logs.addItem(ClosureMenuItem(title: "Show Logs", keyEquivalent: "l", action: showLogs))
        logs.addItem(ClosureMenuItem(title: "Clear Logs", keyEquivalent: "k", action: clearLogs))
        addSubmenu(logs, title: "Logs", to: main)

        let hook = NSMenu(title: "Hook")
        hook.addItem(ClosureMenuItem(title: "Xcode Hook…", keyEquivalent: "", action: showHook))
        addSubmenu(hook, title: "Hook", to: main)

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(window, title: "Window", to: main)
        NSApp.windowsMenu = window

        return main
    }

    private static func addSubmenu(_ submenu: NSMenu, title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }
}

/// Menu item that runs a closure. It is its own target, so no responder-chain selector is needed.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run(_:)), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run(_ sender: Any?) {
        handler()
    }
}

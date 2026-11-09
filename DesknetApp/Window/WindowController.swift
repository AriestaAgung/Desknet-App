import AppKit
import SwiftUI

final class DesknetWindowController: NSWindowController {
    private let defaultFrame = NSRect(x: 140, y: 160, width: 1420, height: 780)
    private let minimumWindowSize = NSSize(width: 1100, height: 620)

    init(viewModel: DesknetMonitorViewModel, runningApps: RunningAppsMonitor) {
        let window = NSWindow(
            contentRect: defaultFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Desknet Network Logs"
        window.minSize = minimumWindowSize
        window.contentViewController = NSHostingController(
            rootView: DesknetMonitorRootView(viewModel: viewModel, runningApps: runningApps)
        )
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

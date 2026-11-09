import Combine
import Foundation

/// Keeps the list of Xcode-run apps current.
/// ponytail: rescans every two seconds; switch to kqueue process events if the scan ever shows up in Instruments.
@MainActor
final class RunningAppsMonitor: ObservableObject {
    @Published private(set) var apps: [RunningApp] = []
    /// Polled with the apps, so installing or removing from the Hook menu shows within 2 seconds.
    @Published private(set) var isHookInstalled = true
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        Task.detached(priority: .utility) { [weak self] in
            let apps = RunningAppScanner.scan()
            let isHookInstalled = DesknetHookInstaller.isInstalled
            await self?.update(apps, isHookInstalled: isHookInstalled)
        }
    }

    private func update(_ apps: [RunningApp], isHookInstalled: Bool) {
        if self.apps != apps {
            self.apps = apps
        }
        if self.isHookInstalled != isHookInstalled {
            self.isHookInstalled = isHookInstalled
        }
    }
}

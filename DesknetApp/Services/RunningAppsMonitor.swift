import Foundation
import Observation

/// Keeps the list of Xcode-run apps current.
/// ponytail: rescans every two seconds; switch to kqueue process events if the scan ever shows up in Instruments.
@MainActor
@Observable
final class RunningAppsMonitor {
    private(set) var apps: [RunningApp] = []
    /// Polled with the apps, so installing or removing from the Hook menu shows within 2 seconds.
    private(set) var isHookInstalled = true
    @ObservationIgnored private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        refresh()
        // Scheduled on the main run loop, so the callback is already on the main actor.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Applies a scan result. Internal so checks can feed it without real processes.
    func update(_ apps: [RunningApp], isHookInstalled: Bool) {
        if self.apps != apps {
            self.apps = apps
        }
        if self.isHookInstalled != isHookInstalled {
            self.isHookInstalled = isHookInstalled
        }
    }

    private func refresh() {
        Task.detached(priority: .utility) { [weak self] in
            let apps = RunningAppScanner.scan()
            let isHookInstalled = DesknetHookInstaller.isInstalled
            await self?.update(apps, isHookInstalled: isHookInstalled)
        }
    }
}

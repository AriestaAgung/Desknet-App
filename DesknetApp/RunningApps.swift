import Combine
import Darwin
import Foundation

/// An app Xcode is running: a Mac app from Xcode's build products, or a Mac or
/// Simulator app under a debugger.
/// ponytail: real iOS devices aren't listed; their processes aren't in this Mac's process table.
struct RunningApp: Identifiable, Hashable, Sendable {
    enum Platform: Hashable, Sendable {
        case mac
        case simulator(deviceName: String)
    }

    let pid: pid_t
    let name: String
    let bundleID: String?
    let platform: Platform
    let isDebugged: Bool

    var id: pid_t { pid }

    var platformText: String {
        switch platform {
        case .mac: return "My Mac"
        case let .simulator(deviceName): return deviceName
        }
    }
}

enum RunningAppScanner {
    struct Match: Equatable {
        let bundleURL: URL
        let simulatorUDID: String?
    }

    /// Decides whether a process is an app Xcode runs. Pure, so it can be tested without real processes.
    static func classify(path: String, isTraced: Bool) -> Match? {
        // Previews and test runners are Xcode's own helpers, not the user's app.
        let helpers = ["XCPreviewAgent", "/previews/", "-Runner.app/", ".xctest/"]
        guard !helpers.contains(where: path.contains) else { return nil }

        var bundle = URL(fileURLWithPath: path).deletingLastPathComponent()
        if bundle.lastPathComponent == "MacOS", bundle.deletingLastPathComponent().lastPathComponent == "Contents" {
            bundle = bundle.deletingLastPathComponent().deletingLastPathComponent()
        }
        guard bundle.pathExtension == "app" else { return nil }

        if path.contains("/data/Containers/Bundle/Application/"),
           let devices = path.range(of: "/CoreSimulator/Devices/") {
            // Xcode runs Simulator apps under its debugger; untraced ones were opened from the home screen.
            guard isTraced else { return nil }
            let udid = path[devices.upperBound...].prefix { $0 != "/" }
            return Match(bundleURL: bundle, simulatorUDID: String(udid))
        }
        // Mac: Xcode's build products (with or without the debugger), or any app being debugged.
        guard isTraced || path.contains("/Library/Developer/Xcode/DerivedData/") else { return nil }
        return Match(bundleURL: bundle, simulatorUDID: nil)
    }

    /// This user's processes that are apps Xcode runs, sorted by name.
    static func scan(excluding ownPID: pid_t = getpid()) -> [RunningApp] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: getuid())]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }
        // Processes can start between the two calls, so leave some room.
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 32)
        size = procs.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }

        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4) // PROC_PIDPATHINFO_MAXSIZE
        var apps: [RunningApp] = []
        for proc in procs.prefix(size / MemoryLayout<kinfo_proc>.stride) {
            let pid = proc.kp_proc.p_pid
            guard pid > 0, pid != ownPID, proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { continue }
            let isTraced = proc.kp_proc.p_flag & P_TRACED != 0
            guard let match = classify(path: String(cString: buffer), isTraced: isTraced) else { continue }

            let info = Bundle(url: match.bundleURL)?.infoDictionary
            let name = info?["CFBundleDisplayName"] as? String
                ?? info?["CFBundleName"] as? String
                ?? match.bundleURL.deletingPathExtension().lastPathComponent
            let platform = match.simulatorUDID.map { RunningApp.Platform.simulator(deviceName: simulatorName($0)) } ?? .mac
            apps.append(RunningApp(
                pid: pid, name: name, bundleID: info?["CFBundleIdentifier"] as? String,
                platform: platform, isDebugged: isTraced
            ))
        }
        return apps.sorted { ($0.name, $0.pid) < ($1.name, $1.pid) }
    }

    private static func simulatorName(_ udid: String) -> String {
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices/\(udid)/device.plist")
        return NSDictionary(contentsOf: plist)?["name"] as? String ?? "Simulator"
    }
}

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

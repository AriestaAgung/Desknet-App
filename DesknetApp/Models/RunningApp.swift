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

import Foundation

extension Notification.Name {
    static let desknetStoreDidUpdate = Notification.Name("desknet.store.did.update")
}

/// One captured request. This is also the wire format the Desknet SDKs send,
/// so field names and types must stay as they are.
struct NetworkLogEntry: Identifiable, Sendable, Codable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let method: String
    let url: URL
    let requestHeaders: [String: String]
    let requestBody: Data
    let statusCode: Int?
    let responseHeaders: [String: String]
    let responseBody: Data
    let mimeType: String?
    let errorDescription: String?

    var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }
}

/// Entries received from connected apps, tagged with the process that sent them.
/// Viewer side only; capture lives in `DesknetAgent`.
final class DesknetStore: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [NetworkLogEntry] = []
    private var ids: Set<UUID> = []
    /// Sender of each entry, from the socket's peer PID.
    private var sources: [UUID: pid_t] = [:]
    /// Open connections per process.
    private var connections: [pid_t: Int] = [:]

    /// Entries already stored are skipped, so a sender can replay its history after
    /// reconnecting (the SDK also resends its first entry after connecting).
    func insert(_ entry: NetworkLogEntry, from pid: pid_t? = nil) {
        lock.lock()
        let isNew = ids.insert(entry.id).inserted
        if isNew {
            entries.append(entry)
            sources[entry.id] = pid
        }
        lock.unlock()

        if isNew {
            notifyUpdated()
        }
    }

    /// Lets the UI show which apps are sending logs right now.
    func setConnected(_ isConnected: Bool, pid: pid_t) {
        lock.lock()
        let count = connections[pid, default: 0] + (isConnected ? 1 : -1)
        connections[pid] = count > 0 ? count : nil
        lock.unlock()

        notifyUpdated()
    }

    func connectedPIDs() -> Set<pid_t> {
        lock.lock()
        defer { lock.unlock() }
        return Set(connections.keys)
    }

    /// Request count per sending process.
    func countsByPID() -> [pid_t: Int] {
        lock.lock()
        defer { lock.unlock() }
        var counts: [pid_t: Int] = [:]
        for pid in sources.values {
            counts[pid, default: 0] += 1
        }
        return counts
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        ids.removeAll()
        sources.removeAll()
        lock.unlock()

        notifyUpdated()
        DesknetDiagnostics.log("Store", "cleared all entries")
    }

    /// Newest first. Pass `pid` to get one app's entries only.
    func snapshot(pid: pid_t? = nil) -> [NetworkLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        let selected = pid.map { pid in entries.filter { sources[$0.id] == pid } } ?? entries
        return selected.sorted { $0.startedAt > $1.startedAt }
    }

    private func notifyUpdated() {
        OperationQueue.main.addOperation {
            NotificationCenter.default.post(name: .desknetStoreDidUpdate, object: nil)
        }
    }
}

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

/// Entries received from connected apps.
/// ponytail: viewer side only. Capture (begin/response/finish) arrives with the agent target (PLAN 1.1).
final class DesknetStore: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [NetworkLogEntry] = []
    private var ids: Set<UUID> = []

    /// Entries already stored are skipped, so a sender can replay its history after
    /// reconnecting (the SDK also resends its first entry; see RESEARCH.md item 12).
    func insert(_ entry: NetworkLogEntry) {
        lock.lock()
        let isNew = ids.insert(entry.id).inserted
        if isNew {
            entries.append(entry)
        }
        lock.unlock()

        if isNew {
            notifyUpdated()
        }
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        ids.removeAll()
        lock.unlock()

        notifyUpdated()
        DesknetDiagnostics.log("Store", "cleared all entries")
    }

    /// Newest first.
    func snapshot() -> [NetworkLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.sorted { $0.startedAt > $1.startedAt }
    }

    private func notifyUpdated() {
        OperationQueue.main.addOperation {
            NotificationCenter.default.post(name: .desknetStoreDidUpdate, object: nil)
        }
    }
}

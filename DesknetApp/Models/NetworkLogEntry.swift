import Foundation

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

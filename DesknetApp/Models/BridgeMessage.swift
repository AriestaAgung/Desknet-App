import Foundation

/// Messages from apps to Desknet.app, as newline-delimited JSON over a Unix socket.
/// Same shape the Desknet SDKs send today (Swift's synthesized enum coding:
/// `{"entry":{"_0":{...}}}`, `{"show":{}}`), so SDK apps work unchanged.
/// ponytail: Swift's enum coding isn't a stable format; replace with an explicit `type` field and a
/// `hello` message carrying app and device info (protocol v2) when the SDK can move with it.
enum DesknetBridgeMessage: Codable, Sendable {
    case entry(NetworkLogEntry)
    case show
    case hide
    case toggle

    func encodedLine() throws -> Data {
        var data = try JSONEncoder().encode(self)
        data.append(0x0A)
        return data
    }
}

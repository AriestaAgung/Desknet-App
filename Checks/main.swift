// Self-check for the SDK wire format and the store's duplicate handling. Run from DesknetApp/:
//   swiftc -o /tmp/bridge_check DesknetApp/Store.swift DesknetApp/Bridge.swift DesknetApp/Diagnostics.swift Checks/main.swift && /tmp/bridge_check
import Foundation

let store = DesknetStore()
var commands: [String] = []
let listener = DesknetBridgeListener(store: store, path: "/tmp/desknet-check.sock") { commands.append("\($0)") }

// Exactly what the Desknet SDK sends today (Swift synthesized enum coding).
let entry = NetworkLogEntry(
    id: UUID(), startedAt: Date(), endedAt: Date(), method: "GET",
    url: URL(string: "https://example.com/data")!, requestHeaders: [:], requestBody: Data(),
    statusCode: 200, responseHeaders: ["Content-Type": "application/json"], responseBody: Data("{}".utf8),
    mimeType: "application/json", errorDescription: nil
)
let line = try DesknetBridgeMessage.entry(entry).encodedLine().dropLast()
assert(String(decoding: line, as: UTF8.self).hasPrefix("{\"entry\":{\"_0\":"), "wire format changed")

// The SDK replays history and then resends the live entry: stored once.
listener.handle(line)
listener.handle(line)
assert(store.snapshot().count == 1, "duplicate entry was stored")

listener.handle(Data("{\"toggle\":{}}".utf8))
listener.handle(Data("not json".utf8))
assert(commands == ["toggle"], "commands: \(commands)")

store.clear()
assert(store.snapshot().isEmpty)
print("bridge_check: ok")

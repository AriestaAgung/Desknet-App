// Self-check for the SDK wire format, the store and Xcode app detection. Run from DesknetApp/:
//   swiftc -o /tmp/bridge_check DesknetApp/Store.swift DesknetApp/Bridge.swift DesknetApp/Diagnostics.swift DesknetApp/RunningApps.swift Checks/main.swift && /tmp/bridge_check
import Foundation

let store = DesknetStore()
var commands: [String] = []
let listener = DesknetBridgeListener(store: store, path: "/tmp/desknet-check.sock") { commands.append("\($0)") }

func makeEntry(_ path: String) -> NetworkLogEntry {
    NetworkLogEntry(
        id: UUID(), startedAt: Date(), endedAt: Date(), method: "GET",
        url: URL(string: "https://example.com\(path)")!, requestHeaders: [:], requestBody: Data(),
        statusCode: 200, responseHeaders: ["Content-Type": "application/json"], responseBody: Data("{}".utf8),
        mimeType: "application/json", errorDescription: nil
    )
}

// Exactly what the Desknet SDK sends today (Swift synthesized enum coding).
let line = try DesknetBridgeMessage.entry(makeEntry("/data")).encodedLine().dropLast()
assert(String(decoding: line, as: UTF8.self).hasPrefix("{\"entry\":{\"_0\":"), "wire format changed")

// The SDK replays history and then resends the live entry: stored once.
listener.handle(line, pid: 101)
listener.handle(line, pid: 101)
assert(store.snapshot().count == 1, "duplicate entry was stored")

// Entries are tagged with the sending process, so one app can be picked.
listener.handle(try DesknetBridgeMessage.entry(makeEntry("/other")).encodedLine().dropLast(), pid: 202)
assert(store.snapshot().count == 2)
assert(store.snapshot(pid: 101).map(\.url.path) == ["/data"], "pid filter")
assert(store.countsByPID() == [101: 1, 202: 1])
store.setConnected(true, pid: 202)
store.setConnected(true, pid: 202)
store.setConnected(false, pid: 202)
assert(store.connectedPIDs() == [202], "connection count")
store.setConnected(false, pid: 202)
assert(store.connectedPIDs().isEmpty)

listener.handle(Data("{\"toggle\":{}}".utf8))
listener.handle(Data("not json".utf8))
assert(commands == ["toggle"], "commands: \(commands)")

store.clear()
assert(store.snapshot().isEmpty && store.countsByPID().isEmpty)

// A deleted socket file is re-created, so the viewer doesn't go deaf.
let checkPath = "/tmp/desknet-check.sock"
assert(listener.start() == .listening)
unlink(checkPath)
assert(DesknetBridgeSocket.connect(to: checkPath) == nil)
listener.repairIfNeeded()
let repaired = DesknetBridgeSocket.connect(to: checkPath)
assert(repaired != nil, "socket not re-created")
close(repaired!)
listener.stop()

// Which processes count as "run from Xcode".
let sim = "/Users/u/Library/Developer/CoreSimulator/Devices/57D0AD07-A3AF-45E9-88D3-C0F47DFE3869/data/Containers/Bundle/Application/F10E/Ticker.app/Ticker"
assert(RunningAppScanner.classify(path: sim, isTraced: true)?.simulatorUDID == "57D0AD07-A3AF-45E9-88D3-C0F47DFE3869")
assert(RunningAppScanner.classify(path: sim, isTraced: false) == nil, "home-screen launch is not from Xcode")
let built = "/Users/u/Library/Developer/Xcode/DerivedData/Cleano-abc/Build/Products/Debug/Cleano.app/Contents/MacOS/Cleano"
assert(RunningAppScanner.classify(path: built, isTraced: false)?.bundleURL.lastPathComponent == "Cleano.app")
assert(RunningAppScanner.classify(path: "/Applications/Foo.app/Contents/MacOS/Foo", isTraced: false) == nil)
assert(RunningAppScanner.classify(path: "/Applications/Foo.app/Contents/MacOS/Foo", isTraced: true) != nil)
assert(RunningAppScanner.classify(path: "/usr/bin/swift", isTraced: true) == nil, "not an app")
assert(RunningAppScanner.classify(path: "/x/Previews/XCPreviewAgent.app/Contents/MacOS/XCPreviewAgent", isTraced: true) == nil)
assert(RunningAppScanner.classify(path: "/x/DerivedData/a/Debug/AppUITests-Runner.app/Contents/MacOS/AppUITests-Runner", isTraced: false) == nil)

print("bridge_check: ok")

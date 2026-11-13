import Combine
import Foundation
import XCTest

@testable import DesknetCore

final class BridgeAndStoreTests: XCTestCase {
    func testListenerWireFormatDedupPIDsAndCommands() throws {
        let store = DesknetStore()
        let commands = Recorder()
        let listener = DesknetBridgeListener(store: store, path: socketPath()) { commands.append("\($0)") }

        // Exactly what the Desknet SDK sends today (Swift synthesized enum coding).
        let line = try DesknetBridgeMessage.entry(makeEntry("/data")).encodedLine().dropLast()
        XCTAssertTrue(String(decoding: line, as: UTF8.self).hasPrefix("{\"entry\":{\"_0\":"), "wire format changed")

        // The SDK replays history and then resends the live entry: stored once.
        listener.handle(line, pid: 101)
        listener.handle(line, pid: 101)
        XCTAssertEqual(store.snapshot().count, 1, "duplicate entry was stored")

        listener.handle(try DesknetBridgeMessage.entry(makeEntry("/other")).encodedLine().dropLast(), pid: 202)
        XCTAssertEqual(store.snapshot().count, 2)
        XCTAssertEqual(store.snapshot(pid: 101).map(\.url.path), ["/data"])
        XCTAssertEqual(store.countsByPID(), [101: 1, 202: 1])
        store.setConnected(true, pid: 202)
        store.setConnected(true, pid: 202)
        store.setConnected(false, pid: 202)
        XCTAssertEqual(store.connectedPIDs(), [202], "connection count")
        store.setConnected(false, pid: 202)
        XCTAssertTrue(store.connectedPIDs().isEmpty)

        listener.handle(Data("{\"toggle\":{}}".utf8))
        listener.handle(Data("not json".utf8))
        XCTAssertEqual(commands.values, ["toggle"])

        store.clear()
        XCTAssertTrue(store.snapshot().isEmpty && store.countsByPID().isEmpty)
    }

    func testStorePublishesOncePerRealChange() {
        let store = DesknetStore()
        var changeCount = 0
        let sub = store.changes.sink { changeCount += 1 }
        defer { sub.cancel() }
        let entry = makeEntry("/pub")
        store.insert(entry, from: 1)
        store.insert(entry, from: 1)
        XCTAssertEqual(changeCount, 1, "duplicate insert must not publish")
        store.setConnected(true, pid: 1)
        store.setConnected(false, pid: 1)
        store.clear()
        XCTAssertEqual(changeCount, 4)
    }

    func testChangeEventsSerializedAcrossThreads() {
        let store = DesknetStore()
        var events = 0
        let sub = store.changes.sink { events += 1 }
        defer { sub.cancel() }
        DispatchQueue.concurrentPerform(iterations: 5000) { i in store.insert(makeEntry("/c/\(i)"), from: 1) }
        XCTAssertEqual(events, 5000, "lost change events")
    }

    func testDeletedSocketIsRecreated() throws {
        let path = socketPath()
        let listener = DesknetBridgeListener(store: DesknetStore(), path: path) { _ in }
        XCTAssertEqual(listener.start(), .listening)
        defer { listener.stop() }
        unlink(path)
        XCTAssertNil(DesknetBridgeSocket.connect(to: path))
        listener.repairIfNeeded()
        let repaired = try XCTUnwrap(DesknetBridgeSocket.connect(to: path), "socket not re-created")
        close(repaired)
    }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        var values: [String] { lock.withLock { items } }
        func append(_ value: String) { lock.withLock { items.append(value) } }
    }

    // Short unique path: sun_path is limited to 104 bytes, and the user's live socket must never be touched.
    private func socketPath() -> String {
        "/tmp/desknet-test-\(UUID().uuidString.prefix(8)).sock"
    }
}

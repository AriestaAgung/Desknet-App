import Foundation
import XCTest

@testable import DesknetCore

@MainActor
final class MonitorViewModelTests: XCTestCase {
    func testSelectionSearchAppsSectionsAndCopy() {
        let store = DesknetStore()
        let apps = RunningAppsMonitor()
        var copied: [CopyPayload] = []
        let vm = MonitorViewModel(store: store, runningApps: apps, copy: { copied.append($0) })
        XCTAssertNil(vm.detail)
        XCTAssertTrue(vm.requestRows.isEmpty)
        XCTAssertEqual(vm.emptyStateText, "No requests found.")

        let now = Date()
        let older = makeEntry("/old", startedAt: now)
        let newer = makeEntry("/new", startedAt: now.addingTimeInterval(1))
        store.insert(older, from: 101)
        store.insert(newer, from: 101)
        vm.reload()
        XCTAssertEqual(vm.requestRows.map(\.title), ["/new", "/old"], "newest first")
        XCTAssertEqual(vm.selectedEntryID, newer.id, "first row auto-selected")
        XCTAssertEqual(vm.detail?.id, newer.id)
        XCTAssertEqual(vm.requestCountText, "2 requests")

        // New requests streaming in keep the user's pick.
        vm.select(entry: older.id)
        store.insert(makeEntry("/newest", startedAt: now.addingTimeInterval(2)), from: 202)
        vm.reload()
        XCTAssertEqual(vm.selectedEntryID, older.id, "selection kept")
        XCTAssertEqual(vm.detail?.id, older.id)

        vm.query = "zzz"
        XCTAssertTrue(vm.requestRows.isEmpty)
        XCTAssertNil(vm.selectedEntryID)
        XCTAssertNil(vm.detail)
        XCTAssertEqual(vm.emptyStateText, "No requests found.")
        vm.query = ""

        vm.select(pid: 999)
        XCTAssertTrue(vm.requestRows.isEmpty)
        XCTAssertEqual(
            vm.emptyStateText,
            "This app hasn't sent any requests. If it was started before Desknet, run it again from Xcode.")

        // Apps column: running app row, then the same pid kept as "Ended app" after it quits.
        let ticker = RunningApp(
            pid: 101, name: "Ticker", bundleID: nil, platform: .simulator(deviceName: "iPhone 17"), isDebugged: true)
        apps.update([ticker], isHookInstalled: false)
        vm.select(pid: 101)
        XCTAssertFalse(vm.isHookInstalled)
        XCTAssertEqual(vm.appRows.map(\.title), ["All apps", "Ticker"])
        XCTAssertEqual(vm.appRows[0].subtitle, "3 requests")
        XCTAssertNil(vm.appRows[0].pid)
        XCTAssertEqual(vm.appRows[1].subtitle, "iPhone 17 · 2 requests")
        apps.update([], isHookInstalled: true)
        XCTAssertEqual(vm.appRows.last?.title, "Ended app")
        XCTAssertEqual(vm.appRows.last?.subtitle, "PID 101 · 2 requests")
        let idle = RunningApp(pid: 303, name: "Idle", bundleID: nil, platform: .mac, isDebugged: false)
        apps.update([idle], isHookInstalled: true)
        XCTAssertEqual(vm.appRows.first { $0.pid == 303 }?.subtitle, "My Mac · no logs yet")
        store.setConnected(true, pid: 303)
        vm.reload()
        XCTAssertEqual(vm.appRows.first { $0.pid == 303 }?.subtitle, "My Mac · 0 requests")
        XCTAssertEqual(vm.appRows.first { $0.pid == 303 }?.isLive, true)
        XCTAssertTrue(vm.appRows[0].isLive)

        // Section state is global, not per entry.
        XCTAssertFalse(vm.isSectionExpanded(.requestHeaders))
        XCTAssertFalse(vm.isSectionExpanded(.responseHeaders))
        XCTAssertTrue(vm.isSectionExpanded(.requestBody))
        XCTAssertTrue(vm.isSectionExpanded(.responseBody))
        vm.setSection(.requestBody, expanded: false)
        vm.select(entry: newer.id)
        XCTAssertFalse(vm.isSectionExpanded(.requestBody))

        vm.copy(.text("x"))
        XCTAssertEqual(copied, [.text("x")])
        vm.copy(.image(png))
        XCTAssertEqual(copied.last, .image(png))

        vm.clear()
        vm.reload()
        XCTAssertTrue(vm.requestRows.isEmpty)
        XCTAssertNil(vm.detail)
        XCTAssertEqual(vm.appRows[0].subtitle, "0 requests")

        // Collapsed bodies are not decoded; expanding loads them.
        vm.setSection(.responseBody, expanded: false)
        store.insert(makeEntry("/lazy", startedAt: now.addingTimeInterval(-10)), from: 1)
        vm.select(pid: nil)
        vm.reload()
        vm.select(entry: vm.requestRows.last!.id)
        XCTAssertEqual(vm.detail?.sections[3].content, .body(nil), "collapsed body decoded")
        vm.setSection(.responseBody, expanded: true)
        XCTAssertEqual(
            vm.detail?.sections[3].content, .body(EntryFormatter().bodyText(Data("{}".utf8), contentType: nil)))
    }

    func testStreamingFormatsOnlyNewEntries() {
        let store = DesknetStore()
        let vm = MonitorViewModel(store: store, runningApps: RunningAppsMonitor(), copy: { _ in })
        let now = Date()
        let start = Date()
        for i in 0..<2000 {
            store.insert(makeEntry("/s/\(i)", startedAt: now.addingTimeInterval(Double(i))), from: 1)
            vm.reload()
        }
        let seconds = Date().timeIntervalSince(start)
        XCTAssertEqual(vm.requestRows.count, 2000)
        XCTAssertEqual(vm.requestRows.first?.title, "/s/1999")
        // Generous bound: shared CI runners are slower than a dev Mac; the old full-reformat path took ~0.3s.
        XCTAssertLessThan(seconds, 10, "2000 streamed inserts took \(seconds)s")
    }
}

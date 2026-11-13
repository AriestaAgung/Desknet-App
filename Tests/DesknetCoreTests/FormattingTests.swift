import Foundation
import XCTest

@testable import DesknetCore

final class FormattingTests: XCTestCase {
    let f = EntryFormatter()

    func testStatusAndEndpointText() {
        XCTAssertEqual(f.statusText(makeEntry(status: 200)), "200 OK")
        XCTAssertEqual(f.statusText(makeEntry(status: 404)), "404 Not Found")
        XCTAssertEqual(f.statusText(makeEntry(status: nil, error: "x")), "Failed")
        XCTAssertEqual(f.statusText(makeEntry(status: nil)), "Running")
        XCTAssertTrue(f.isError(makeEntry(status: 500)))
        XCTAssertTrue(f.isError(makeEntry(status: nil, error: "x")))
        XCTAssertFalse(f.isError(makeEntry()))
        XCTAssertEqual(f.endpointTitle(makeEntry(url: "https://h.io/")), "h.io")
        XCTAssertEqual(f.endpointTitle(makeEntry("/users")), "/users")
        XCTAssertEqual(f.baseURLText(makeEntry(url: "http://h.io:8080/p?q=1")), "http://h.io:8080")
        XCTAssertEqual(f.endpointDetailText(makeEntry(url: "http://h.io/p?q=1#f")), "/p?q=1#f")
        XCTAssertEqual(f.durationText(makeEntry(endedAfter: 0.1234)), "123.400ms")
    }

    func testBodyText() {
        XCTAssertEqual(f.bodyText(Data(), contentType: nil), "{}")
        XCTAssertEqual(
            f.bodyText(Data("{\"b\":1,\"a\":2}".utf8), contentType: nil), "{\n  \"a\" : 2,\n  \"b\" : 1\n}")
        XCTAssertEqual(f.bodyText(Data([0xFF, 0xFE]), contentType: nil), "Binary body (2 bytes)")
    }

    func testSearch() {
        XCTAssertTrue(EntryFormatter.matches(makeEntry("/users"), query: "  USERS "))
        XCTAssertTrue(EntryFormatter.matches(makeEntry("/users"), query: ""))
        XCTAssertFalse(EntryFormatter.matches(makeEntry("/users"), query: "orders"))
        XCTAssertEqual(EntryFormatter.normalizedQuery("  USERS \n"), "users")
        XCTAssertTrue(EntryFormatter.matches(makeEntry("/users"), normalizedQuery: "users"))
        XCTAssertTrue(EntryFormatter.matches(makeEntry("/users"), normalizedQuery: ""))
    }

    func testRowsAndDetail() {
        let errorRow = RequestRow(entry: makeEntry("/a", status: 500), formatter: f)
        XCTAssertTrue(errorRow.isError)
        XCTAssertEqual(errorRow.statusCodeText, "500")
        XCTAssertEqual(errorRow.title, "/a")
        XCTAssertTrue(errorRow.accessibilityLabel.hasPrefix("GET /a, 500 Internal Server Error, "))
        XCTAssertEqual(RequestRow(entry: makeEntry(status: nil), formatter: f).statusCodeText, "-")
        let binaryRow = RequestRow(entry: makeEntry(body: Data([0xFF, 0xFE])), formatter: f)
        XCTAssertTrue(binaryRow.metricsText.hasPrefix("◷ ") && binaryRow.metricsText.hasSuffix("   2 bytes"))

        let detail = RequestDetail(entry: makeEntry(requestHeaders: ["b": "2", "A": "1"]), formatter: f)
        XCTAssertEqual(detail.metrics.map(\.title), ["Duration", "Request Size", "Response Size"])
        XCTAssertEqual(detail.sections.map(\.section), DetailSection.allCases)
        guard case let .headers(headers) = detail.sections[0].content else { return XCTFail("request headers") }
        XCTAssertEqual(headers.map(\.key), ["A", "b"])
        guard case let .body(response) = detail.sections[3].content else { return XCTFail("response body") }
        XCTAssertEqual(response, f.bodyText(Data("{}".utf8), contentType: "application/json"))
        guard case let .body(request) = detail.sections[1].content else { return XCTFail("request body") }
        XCTAssertEqual(request, "{}")
        XCTAssertEqual(DetailSection.responseBody.title, "Response Body")
    }

    func testHookPromptCopy() {
        let remove = HookPrompt(isInstalled: true)
        XCTAssertEqual(remove.title, "Xcode hook is installed")
        XCTAssertEqual(remove.confirm, "Remove")
        XCTAssertEqual(remove.cancel, "Cancel")
        XCTAssertTrue(remove.isDestructive)
        let install = HookPrompt(isInstalled: false)
        XCTAssertEqual(install.title, "Install the Xcode hook?")
        XCTAssertEqual(install.confirm, "Install")
        XCTAssertEqual(install.cancel, "Not Now")
        XCTAssertFalse(install.isDestructive)
        XCTAssertTrue(install.message.contains("~/.lldbinit-Xcode"))
    }
}

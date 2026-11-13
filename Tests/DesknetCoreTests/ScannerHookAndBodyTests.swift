import Foundation
import XCTest

@testable import DesknetCore

final class ScannerHookAndBodyTests: XCTestCase {
    func testWhichProcessesCountAsRunFromXcode() {
        let sim =
            "/Users/u/Library/Developer/CoreSimulator/Devices/57D0AD07-A3AF-45E9-88D3-C0F47DFE3869/data/Containers/Bundle/Application/F10E/Ticker.app/Ticker"
        XCTAssertEqual(
            RunningAppScanner.classify(path: sim, isTraced: true)?.simulatorUDID,
            "57D0AD07-A3AF-45E9-88D3-C0F47DFE3869")
        XCTAssertNil(RunningAppScanner.classify(path: sim, isTraced: false), "home-screen launch is not from Xcode")
        let built =
            "/Users/u/Library/Developer/Xcode/DerivedData/Cleano-abc/Build/Products/Debug/Cleano.app/Contents/MacOS/Cleano"
        XCTAssertEqual(
            RunningAppScanner.classify(path: built, isTraced: false)?.bundleURL.lastPathComponent, "Cleano.app")
        XCTAssertNil(RunningAppScanner.classify(path: "/Applications/Foo.app/Contents/MacOS/Foo", isTraced: false))
        XCTAssertNotNil(RunningAppScanner.classify(path: "/Applications/Foo.app/Contents/MacOS/Foo", isTraced: true))
        XCTAssertNil(RunningAppScanner.classify(path: "/usr/bin/swift", isTraced: true), "not an app")
        XCTAssertNil(
            RunningAppScanner.classify(
                path: "/x/Previews/XCPreviewAgent.app/Contents/MacOS/XCPreviewAgent", isTraced: true))
        XCTAssertNil(
            RunningAppScanner.classify(
                path: "/x/DerivedData/a/Debug/AppUITests-Runner.app/Contents/MacOS/AppUITests-Runner", isTraced: false))
    }

    func testHookBlockAddAndRemove() {
        let own = "settings set target.x 1"
        let hooked = DesknetHookInstaller.adding(to: own)
        XCTAssertEqual(hooked, own + "\n" + DesknetHookInstaller.block)
        XCTAssertEqual(DesknetHookInstaller.adding(to: hooked), hooked, "add twice")
        XCTAssertEqual(DesknetHookInstaller.adding(to: ""), DesknetHookInstaller.block)
        XCTAssertEqual(DesknetHookInstaller.removing(from: hooked), own + "\n")
        XCTAssertEqual(DesknetHookInstaller.removing(from: "a\n" + DesknetHookInstaller.block + "b\n"), "a\nb\n")
        XCTAssertEqual(DesknetHookInstaller.removing(from: own), own)
        let unterminated = DesknetHookInstaller.begin + "\nno end"
        XCTAssertEqual(DesknetHookInstaller.removing(from: unterminated), unterminated, "unterminated block kept")
    }

    func testImageDetection() {
        XCTAssertTrue(RequestDetail.isImage(Data(), contentType: "image/jpeg"))
        XCTAssertTrue(RequestDetail.isImage(png, contentType: nil))
        XCTAssertTrue(RequestDetail.isImage(png, contentType: "application/octet-stream"))
        XCTAssertFalse(RequestDetail.isImage(png, contentType: "application/json"), "explicit non-image type wins")
        XCTAssertTrue(RequestDetail.isImage(Data("<svg/>".utf8), contentType: "image/svg+xml"))
        let svg = Data(
            "<?xml version=\"1.0\"?>\n<!-- logo -->\n<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)
        XCTAssertTrue(RequestDetail.isSVG(svg))
        XCTAssertTrue(RequestDetail.isImage(svg, contentType: nil))
        XCTAssertTrue(RequestDetail.isImage(svg, contentType: "application/octet-stream"))
        XCTAssertFalse(RequestDetail.isImage(svg, contentType: "text/html"))
        XCTAssertFalse(RequestDetail.isSVG(Data("{\"svg\": \"<svg>\"}".utf8)))
        XCTAssertFalse(RequestDetail.isSVG(png))
        XCTAssertFalse(RequestDetail.isImage(Data("{}".utf8), contentType: nil))
        XCTAssertEqual(RequestDetail.header("Content-Type", in: ["content-type": "image/png"]), "image/png")
    }

    func testMultipart() throws {
        XCTAssertEqual(MultipartParser.boundary(from: "multipart/form-data; boundary=\"XyZ\""), "XyZ")
        XCTAssertEqual(MultipartParser.boundary(from: "Multipart/Form-Data; charset=utf-8; boundary=abc"), "abc")
        XCTAssertNil(MultipartParser.boundary(from: "application/json"))
        XCTAssertNil(MultipartParser.boundary(from: "multipart/form-data"))

        var form = Data("--abc\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nHello\r\n".utf8)
        form += Data(
            "--abc\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"a;b.png\"\r\nContent-Type: image/png\r\n\r\n"
                .utf8)
        form += png + Data("\r\n".utf8)
        form += Data("--abc\r\nContent-Disposition: form-data; name=\"empty\"\r\n\r\n\r\n--abc--\r\n".utf8)

        let parts = try XCTUnwrap(MultipartParser.parse(form, boundary: "abc"))
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[0], MultipartPart(name: "title", filename: nil, contentType: nil, value: .text("Hello")))
        XCTAssertEqual(parts[1].name, "photo")
        XCTAssertEqual(parts[1].filename, "a;b.png")
        XCTAssertEqual(parts[1].value, .image(png))
        XCTAssertEqual(parts[2].value, .text(""))
        XCTAssertNil(MultipartParser.parse(Data("--abc\r\nno end".utf8), boundary: "abc"), "truncated multipart")

        let entry = NetworkLogEntry(
            id: UUID(), startedAt: Date(), endedAt: nil, method: "POST", url: URL(string: "https://x.test/upload")!,
            requestHeaders: ["content-type": "multipart/form-data; boundary=abc"], requestBody: form,
            statusCode: 200, responseHeaders: [:], responseBody: Data(), mimeType: nil, errorDescription: nil)
        let f = EntryFormatter()
        XCTAssertEqual(
            RequestDetail(entry: entry, formatter: f, decodesBody: { _ in false }).sections[1].content,
            .multipart(nil))
        guard case let .multipart(decoded?) = RequestDetail(entry: entry, formatter: f).sections[1].content else {
            return XCTFail("multipart request body")
        }
        XCTAssertEqual(decoded.count, 3)
    }
}

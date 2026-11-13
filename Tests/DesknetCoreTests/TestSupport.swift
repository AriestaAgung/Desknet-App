import Foundation

@testable import DesknetCore

let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

func makeEntry(
    _ path: String = "/", url: String? = nil, status: Int? = 200, error: String? = nil,
    startedAt: Date = Date(), endedAfter: TimeInterval = 0,
    requestHeaders: [String: String] = [:], body: Data = Data("{}".utf8)
) -> NetworkLogEntry {
    NetworkLogEntry(
        id: UUID(), startedAt: startedAt, endedAt: startedAt.addingTimeInterval(endedAfter), method: "GET",
        url: URL(string: url ?? "https://example.com\(path)")!, requestHeaders: requestHeaders, requestBody: Data(),
        statusCode: status, responseHeaders: ["Content-Type": "application/json"], responseBody: body,
        mimeType: "application/json", errorDescription: error
    )
}

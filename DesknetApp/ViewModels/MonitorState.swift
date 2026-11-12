import Foundation


/// The four collapsible cards under a request's summary, in display order.
enum DetailSection: Int, CaseIterable, Hashable {
    case requestHeaders
    case requestBody
    case responseHeaders
    case responseBody

    var title: String {
        switch self {
        case .requestHeaders: return "Request Headers"
        case .requestBody: return "Request Body"
        case .responseHeaders: return "Response Headers"
        case .responseBody: return "Response Body"
        }
    }
}

/// One row in the apps column. `pid == nil` is the "All apps" row.
struct AppRow: Identifiable, Equatable {
    let pid: pid_t?
    let title: String
    let subtitle: String
    let isLive: Bool

    var id: String { Self.id(for: pid) }

    var accessibilityLabel: String {
        "\(title), \(subtitle)\(isLive ? ", sending logs" : "")"
    }

    static func id(for pid: pid_t?) -> String {
        pid.map { "pid-\($0)" } ?? "all"
    }
}

/// One row in the request list. Built for every entry, so it reads body sizes only, never contents.
struct RequestRow: Identifiable, Equatable {
    let id: UUID
    let method: String
    let statusCodeText: String
    let isError: Bool
    let title: String
    let metricsText: String
    let accessibilityLabel: String

    init(entry: NetworkLogEntry, formatter: EntryFormatter) {
        let duration = formatter.durationText(entry)
        id = entry.id
        method = entry.method
        statusCodeText = entry.statusCode.map(String.init) ?? "-"
        isError = formatter.isError(entry)
        title = formatter.endpointTitle(entry)
        metricsText = "◷ \(duration)   \(formatter.sizeText(entry.responseBody.count))"
        accessibilityLabel = "\(entry.method) \(title), \(formatter.statusText(entry)), \(duration)"
    }
}

/// Everything the detail pane shows for the selected request. Built for one entry at a time.
struct RequestDetail: Identifiable, Equatable {
    struct Metric: Equatable {
        let title: String
        let value: String
    }

    struct Header: Equatable {
        let key: String
        let value: String
    }

    struct SectionContent: Equatable, Identifiable {
        enum Content: Equatable {
            case headers([Header])
            /// nil: not decoded yet because the section was collapsed.
            case body(String?)
            case image(Data?)
            case multipart([MultipartPart]?)

            /// Body skipped while its section was collapsed; decode it on expand.
            var isUndecoded: Bool {
                self == .body(nil) || self == .image(nil) || self == .multipart(nil)
            }
        }

        let section: DetailSection
        let content: Content

        var id: DetailSection { section }
    }

    let id: UUID
    let method: String
    let statusText: String
    let isError: Bool
    let baseURL: String
    let endpoint: String
    let metrics: [Metric]
    let timestamp: String
    let error: String?
    let sections: [SectionContent]

    /// `decodesBody` says which body sections to pretty-print now; bodies can be 64 MB.
    init(entry: NetworkLogEntry, formatter: EntryFormatter, decodesBody: (DetailSection) -> Bool = { _ in true }) {
        id = entry.id
        method = entry.method
        statusText = formatter.statusText(entry)
        isError = formatter.isError(entry)
        baseURL = formatter.baseURLText(entry)
        endpoint = formatter.endpointDetailText(entry)
        metrics = [
            Metric(title: "Duration", value: formatter.durationText(entry)),
            Metric(title: "Request Size", value: formatter.sizeText(entry.requestBody.count)),
            Metric(title: "Response Size", value: formatter.sizeText(entry.responseBody.count)),
        ]
        timestamp = formatter.timestampText(entry)
        error = entry.errorDescription
        sections = DetailSection.allCases.map { section in
            let content: SectionContent.Content
            switch section {
            case .requestHeaders:
                content = .headers(Self.sorted(entry.requestHeaders))
            case .responseHeaders:
                content = .headers(Self.sorted(entry.responseHeaders))
            case .requestBody:
                let type = Self.header("Content-Type", in: entry.requestHeaders)
                content = Self.bodyContent(entry.requestBody, contentType: type,
                                           decode: decodesBody(section), formatter: formatter)
            case .responseBody:
                let type = entry.mimeType ?? Self.header("Content-Type", in: entry.responseHeaders)
                content = Self.bodyContent(entry.responseBody, contentType: type,
                                           decode: decodesBody(section), formatter: formatter)
            }
            return SectionContent(section: section, content: content)
        }
    }

    private static func bodyContent(_ data: Data, contentType: String?, decode: Bool,
                                     formatter: EntryFormatter) -> SectionContent.Content {
        if isImage(data, contentType: contentType) {
            return .image(decode ? data : nil)
        }
        if let boundary = MultipartParser.boundary(from: contentType) {
            guard decode else { return .multipart(nil) }
            // Malformed multipart falls through to plain text.
            if let parts = MultipartParser.parse(data, boundary: boundary) { return .multipart(parts) }
        }
        return .body(decode ? formatter.bodyText(data, contentType: contentType) : nil)
    }

    /// Image if the MIME type says so, else sniff magic bytes (servers often send octet-stream or nothing).
    /// SVG is excluded: it is XML text and NSImage can't reliably decode it.
    static func isImage(_ data: Data, contentType: String?) -> Bool {
        let type = (contentType ?? "").lowercased()
        if type.hasPrefix("image/svg") { return false }
        if type.hasPrefix("image/") { return true }
        if !type.isEmpty, !type.hasPrefix("application/octet-stream") { return false }
        return sniffImage(data)
    }

    /// HTTP header names are case-insensitive; HTTP/2 sends them lowercase.
    static func header(_ name: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private static func sniffImage(_ data: Data) -> Bool {
        let b = [UInt8](data.prefix(12))
        guard b.count >= 4 else { return false }
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true } // PNG
        if b.starts(with: [0xFF, 0xD8, 0xFF]) { return true } // JPEG
        if b.starts(with: [0x47, 0x49, 0x46, 0x38]) { return true } // GIF
        if b.count >= 12, b.starts(with: [0x52, 0x49, 0x46, 0x46]),
           b[8...11].elementsEqual([0x57, 0x45, 0x42, 0x50]) { return true } // WEBP
        return false
    }

    private static func sorted(_ headers: [String: String]) -> [Header] {
        headers
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { Header(key: $0.key, value: $0.value) }
    }
}

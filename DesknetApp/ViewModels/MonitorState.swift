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
            case body(String)
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

    init(entry: NetworkLogEntry, formatter: EntryFormatter) {
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
                content = .body(formatter.bodyText(entry.requestBody, contentType: entry.requestHeaders["Content-Type"]))
            case .responseBody:
                content = .body(formatter.bodyText(entry.responseBody, contentType: entry.responseHeaders["Content-Type"]))
            }
            return SectionContent(section: section, content: content)
        }
    }

    private static func sorted(_ headers: [String: String]) -> [Header] {
        headers
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { Header(key: $0.key, value: $0.value) }
    }
}

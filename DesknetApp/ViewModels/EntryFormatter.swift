import Foundation

/// Turns a captured entry into the text the monitor shows. Pure: no UI framework, no state.
struct EntryFormatter {
    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useBytes, .useKB, .useMB]
        formatter.includesUnit = true
        return formatter
    }()

    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy, hh:mm:ss.SSS a"
        return formatter
    }()

    func isError(_ entry: NetworkLogEntry) -> Bool {
        entry.errorDescription != nil || (entry.statusCode ?? 0) >= 400
    }

    func statusText(_ entry: NetworkLogEntry) -> String {
        if let statusCode = entry.statusCode {
            if isError(entry) {
                return "\(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized)"
            }
            return "\(statusCode) OK"
        }
        // Entries only arrive once finished, so no status means the request failed (BACKLOG).
        return entry.errorDescription != nil ? "Failed" : "Running"
    }

    func endpointTitle(_ entry: NetworkLogEntry) -> String {
        let path = entry.url.path
        if path.isEmpty || path == "/" {
            return entry.url.host ?? entry.url.absoluteString
        }
        return path
    }

    func baseURLText(_ entry: NetworkLogEntry) -> String {
        guard let scheme = entry.url.scheme, let host = entry.url.host else {
            return entry.url.absoluteString
        }
        if let port = entry.url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    func endpointDetailText(_ entry: NetworkLogEntry) -> String {
        var endpoint = entry.url.path.isEmpty ? "/" : entry.url.path
        if let query = entry.url.query, !query.isEmpty {
            endpoint += "?\(query)"
        }
        if let fragment = entry.url.fragment, !fragment.isEmpty {
            endpoint += "#\(fragment)"
        }
        return endpoint
    }

    func durationText(_ entry: NetworkLogEntry) -> String {
        guard let duration = entry.duration else { return "-" }
        return String(format: "%.3fms", duration * 1_000)
    }

    func sizeText(_ bytes: Int) -> String {
        byteFormatter.string(fromByteCount: Int64(bytes))
    }

    func timestampText(_ entry: NetworkLogEntry) -> String {
        timestampFormatter.string(from: entry.startedAt)
    }

    /// Pretty JSON when it parses, else UTF-8 text, else a byte count.
    func bodyText(_ data: Data, contentType: String?) -> String {
        guard !data.isEmpty else { return "{}" }

        if let object = try? JSONSerialization.jsonObject(with: data),
           JSONSerialization.isValidJSONObject(object),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        if (contentType ?? "").localizedCaseInsensitiveContains("json"),
           let text = String(data: data, encoding: .ascii),
           !text.isEmpty {
            return text
        }
        return "Binary body (\(data.count) bytes)"
    }

    /// Trimmed, lowercased search text. Compute once per filter pass, not per entry.
    static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Case-insensitive search over URL, method, status and error. Blank query matches everything.
    static func matches(_ entry: NetworkLogEntry, query: String) -> Bool {
        matches(entry, normalizedQuery: normalizedQuery(query))
    }

    /// `trimmed` must come from `normalizedQuery(_:)`.
    static func matches(_ entry: NetworkLogEntry, normalizedQuery trimmed: String) -> Bool {
        guard !trimmed.isEmpty else { return true }

        let status = entry.statusCode.map(String.init) ?? ""
        let haystack = [
            entry.url.absoluteString,
            entry.url.path,
            entry.url.host ?? "",
            entry.method,
            status,
            entry.errorDescription ?? "",
        ].joined(separator: " ").lowercased()
        return haystack.contains(trimmed)
    }
}

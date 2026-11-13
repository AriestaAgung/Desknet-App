import Foundation

/// One part of a `multipart/form-data` body, as shown in the detail pane.
struct MultipartPart: Equatable {
    enum Value: Equatable {
        case text(String)
        case image(Data)
        /// Not an image and not UTF-8: only the size is shown.
        case binary(Int)
    }

    let name: String?
    let filename: String?
    let contentType: String?
    let value: Value
}

/// Splits multipart bodies (RFC 2046 / RFC 7578) into parts. Returns nil on malformed input so callers fall back to text.
enum MultipartParser {
    /// The `boundary` parameter of a `multipart/*` Content-Type, or nil for any other type.
    static func boundary(from contentType: String?) -> String? {
        guard let contentType, contentType.lowercased().hasPrefix("multipart/") else { return nil }
        guard let boundary = parameters(contentType)["boundary"], !boundary.isEmpty else { return nil }
        return boundary
    }

    static func parse(_ data: Data, boundary: String) -> [MultipartPart]? {
        let delimiter = Data("--\(boundary)".utf8)
        let crlf = Data("\r\n".utf8)
        let headerEnd = Data("\r\n\r\n".utf8)
        let closing = Data("--".utf8)

        guard var cursor = data.range(of: delimiter)?.upperBound else { return nil }
        var parts: [MultipartPart] = []
        while !data[cursor...].starts(with: closing) {
            // Skip the rest of the delimiter line (optional padding, then CRLF).
            guard let lineEnd = data.range(of: crlf, in: cursor..<data.endIndex) else { return nil }
            let partStart = lineEnd.upperBound
            guard let next = data.range(of: crlf + delimiter, in: partStart..<data.endIndex) else { return nil }

            let headerBlock: Data
            let bodyStart: Data.Index
            if data[partStart..<next.lowerBound].starts(with: crlf) {
                // No part headers: the blank line comes first.
                headerBlock = Data()
                bodyStart = partStart + crlf.count
            } else if let end = data.range(of: headerEnd, in: partStart..<next.upperBound),
                end.upperBound <= next.lowerBound + crlf.count
            {
                headerBlock = Data(data[partStart..<end.lowerBound])
                // An empty body leaves the header terminator overlapping the delimiter's CRLF.
                bodyStart = min(end.upperBound, next.lowerBound)
            } else {
                return nil
            }
            parts.append(part(headers: headerBlock, body: Data(data[bodyStart..<next.lowerBound])))
            cursor = next.upperBound
        }
        return parts
    }

    private static func part(headers block: Data, body: Data) -> MultipartPart {
        var headers: [String: String] = [:]
        for line in String(decoding: block, as: UTF8.self).components(separatedBy: "\r\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let disposition = parameters(headers["content-disposition"] ?? "")
        let type = headers["content-type"]

        let value: MultipartPart.Value
        if RequestDetail.isImage(body, contentType: type) {
            value = .image(body)
        } else if let text = String(data: body, encoding: .utf8) {
            value = .text(text)
        } else {
            value = .binary(body.count)
        }
        return MultipartPart(
            name: disposition["name"], filename: disposition["filename"], contentType: type, value: value)
    }

    /// `key=value` parameters after the first `;` of a header value. Keys lowercased, quotes removed.
    /// Splits only on `;` outside quotes, so `filename="a;b.png"` survives.
    static func parameters(_ header: String) -> [String: String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for character in header {
            if character == "\"" { inQuotes.toggle() }
            if character == ";", !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        fields.append(current)

        var result: [String: String] = [:]
        for field in fields.dropFirst() {
            let pair = field.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let key = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
            var value = pair[1].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }
}

import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class DesknetMonitorViewModel: ObservableObject {
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

    @Published var query = "" {
        didSet { applyFilterAndSelection() }
    }
    @Published private(set) var allEntries: [NetworkLogEntry] = []
    @Published private(set) var entries: [NetworkLogEntry] = []
    @Published var selectedEntryID: UUID?
    @Published var collapsedSections: Set<DetailSection> = [.requestHeaders, .responseHeaders]
    /// App picked in the apps column; nil shows every app's requests.
    /// ponytail: keyed by PID, so a relaunch from Xcode is a new row to pick.
    @Published var selectedPID: pid_t? {
        didSet {
            guard oldValue != selectedPID else { return }
            selectedEntryID = nil
            reload()
        }
    }
    @Published private(set) var connectedPIDs: Set<pid_t> = []
    @Published private(set) var countsByPID: [pid_t: Int] = [:]
    @Published private(set) var totalCount = 0

    private let store: DesknetStore
    private var observer: NSObjectProtocol?

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

    init(store: DesknetStore) {
        self.store = store
        observer = NotificationCenter.default.addObserver(
            forName: .desknetStoreDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reload()
            }
        }
        reload()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var selectedEntry: NetworkLogEntry? {
        guard let selectedEntryID else { return nil }
        return entries.first { $0.id == selectedEntryID }
    }

    var requestCountText: String {
        "\(entries.count) requests"
    }

    var emptyStateText: String {
        guard entries.isEmpty else { return "Select an API call from the list to view request/response details." }
        if selectedPID != nil, query.isEmpty {
            // The agent only loads at launch, so an app started before Desknet sends nothing.
            return "This app hasn't sent any requests. If it was started before Desknet, run it again from Xcode."
        }
        return "No requests found."
    }

    func clear() {
        store.clear()
    }

    func reload() {
        allEntries = store.snapshot(pid: selectedPID)
        connectedPIDs = store.connectedPIDs()
        countsByPID = store.countsByPID()
        totalCount = store.count()
        applyFilterAndSelection()
    }

    func setSectionExpanded(_ section: DetailSection, isExpanded: Bool) {
        if isExpanded {
            collapsedSections.remove(section)
        } else {
            collapsedSections.insert(section)
        }
    }

    func isSectionExpanded(_ section: DetailSection) -> Bool {
        !collapsedSections.contains(section)
    }

    func sectionBinding(_ section: DetailSection) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.isSectionExpanded(section) ?? false },
            set: { [weak self] in self?.setSectionExpanded(section, isExpanded: $0) }
        )
    }

    func isError(_ entry: NetworkLogEntry) -> Bool {
        entry.errorDescription != nil || (entry.statusCode ?? 0) >= 400
    }

    func statusText(for entry: NetworkLogEntry) -> String {
        if let statusCode = entry.statusCode {
            if isError(entry) {
                return "\(statusCode) \(HTTPURLResponse.localizedString(forStatusCode: statusCode).capitalized)"
            }
            return "\(statusCode) OK"
        }
        // Entries only arrive once finished, so no status means the request failed (BACKLOG).
        return entry.errorDescription != nil ? "Failed" : "Running"
    }

    func endpointTitle(for entry: NetworkLogEntry) -> String {
        let path = entry.url.path
        if path.isEmpty || path == "/" {
            return entry.url.host ?? entry.url.absoluteString
        }
        return path
    }

    func baseURLText(for entry: NetworkLogEntry) -> String {
        guard let scheme = entry.url.scheme,
              let host = entry.url.host else {
            return entry.url.absoluteString
        }

        if let port = entry.url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    func endpointDetailText(for entry: NetworkLogEntry) -> String {
        var endpoint = entry.url.path.isEmpty ? "/" : entry.url.path

        if let query = entry.url.query, !query.isEmpty {
            endpoint += "?\(query)"
        }
        if let fragment = entry.url.fragment, !fragment.isEmpty {
            endpoint += "#\(fragment)"
        }
        return endpoint
    }

    func durationText(for entry: NetworkLogEntry) -> String {
        guard let duration = entry.duration else { return "-" }
        return String(format: "%.3fms", duration * 1_000)
    }

    func sizeText(for entry: NetworkLogEntry) -> String {
        byteFormatter.string(fromByteCount: Int64(entry.responseBody.count))
    }

    func metricRows(for entry: NetworkLogEntry) -> [(String, String)] {
        [
            ("Duration", durationText(for: entry)),
            ("Request Size", byteFormatter.string(fromByteCount: Int64(entry.requestBody.count))),
            ("Response Size", byteFormatter.string(fromByteCount: Int64(entry.responseBody.count))),
        ]
    }

    func timestampText(for entry: NetworkLogEntry) -> String {
        timestampFormatter.string(from: entry.startedAt)
    }

    func headers(for section: DetailSection, entry: NetworkLogEntry) -> [String: String] {
        switch section {
        case .requestHeaders:
            return entry.requestHeaders
        case .responseHeaders:
            return entry.responseHeaders
        case .requestBody, .responseBody:
            return [:]
        }
    }

    func bodyText(for section: DetailSection, entry: NetworkLogEntry) -> String {
        switch section {
        case .requestBody:
            return bodyText(from: entry.requestBody, contentType: entry.requestHeaders["Content-Type"])
        case .responseBody:
            return bodyText(from: entry.responseBody, contentType: entry.responseHeaders["Content-Type"])
        case .requestHeaders, .responseHeaders:
            return "{}"
        }
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func applyFilterAndSelection() {
        let previousSelection = selectedEntryID
        entries = filteredEntries(from: allEntries, query: query)

        if let previousSelection,
           entries.contains(where: { $0.id == previousSelection }) {
            selectedEntryID = previousSelection
            return
        }

        selectedEntryID = entries.first?.id
    }

    private func filteredEntries(from source: [NetworkLogEntry], query: String) -> [NetworkLogEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return source }

        return source.filter { entry in
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

    private func bodyText(from data: Data, contentType: String?) -> String {
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
}

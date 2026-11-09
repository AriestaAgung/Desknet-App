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
    private var storeChanges: AnyCancellable?

    private let formatter = EntryFormatter()

    init(store: DesknetStore) {
        self.store = store
        storeChanges = store.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.reload() }
            }
        reload()
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

    // Temporary forwards so views compile; removed in Task 5.
    func isError(_ entry: NetworkLogEntry) -> Bool { formatter.isError(entry) }
    func statusText(for entry: NetworkLogEntry) -> String { formatter.statusText(entry) }
    func endpointTitle(for entry: NetworkLogEntry) -> String { formatter.endpointTitle(entry) }
    func baseURLText(for entry: NetworkLogEntry) -> String { formatter.baseURLText(entry) }
    func endpointDetailText(for entry: NetworkLogEntry) -> String { formatter.endpointDetailText(entry) }
    func durationText(for entry: NetworkLogEntry) -> String { formatter.durationText(entry) }
    func sizeText(for entry: NetworkLogEntry) -> String { formatter.sizeText(entry.responseBody.count) }
    func timestampText(for entry: NetworkLogEntry) -> String { formatter.timestampText(entry) }

    func metricRows(for entry: NetworkLogEntry) -> [(String, String)] {
        [
            ("Duration", formatter.durationText(entry)),
            ("Request Size", formatter.sizeText(entry.requestBody.count)),
            ("Response Size", formatter.sizeText(entry.responseBody.count)),
        ]
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
            return formatter.bodyText(entry.requestBody, contentType: entry.requestHeaders["Content-Type"])
        case .responseBody:
            return formatter.bodyText(entry.responseBody, contentType: entry.responseHeaders["Content-Type"])
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
        entries = allEntries.filter { EntryFormatter.matches($0, query: query) }

        if let previousSelection,
           entries.contains(where: { $0.id == previousSelection }) {
            selectedEntryID = previousSelection
            return
        }

        selectedEntryID = entries.first?.id
    }
}

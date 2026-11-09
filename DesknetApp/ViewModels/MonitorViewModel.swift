import Combine
import Foundation
import Observation

/// State and intents for the monitor window. Views render `appRows`, `requestRows` and `detail`
/// and call the intents; they never read the store or format entries themselves.
@MainActor
@Observable
final class MonitorViewModel {
    var query = "" {
        didSet { applyFilterAndSelection() }
    }
    /// App picked in the apps column; nil shows every app's requests.
    /// ponytail: keyed by PID, so a relaunch from Xcode is a new row to pick.
    private(set) var selectedPID: pid_t?
    private(set) var selectedEntryID: UUID?
    private(set) var collapsedSections: Set<DetailSection> = [.requestHeaders, .responseHeaders]

    private(set) var requestRows: [RequestRow] = []
    /// Built only for the selected entry, and only when the selection changes: bodies can be 64 MB.
    private(set) var detail: RequestDetail?

    private var allEntries: [NetworkLogEntry] = []
    private var entries: [NetworkLogEntry] = []
    private var connectedPIDs: Set<pid_t> = []
    private var countsByPID: [pid_t: Int] = [:]
    private var totalCount = 0

    @ObservationIgnored private let store: DesknetStore
    @ObservationIgnored private let runningApps: RunningAppsMonitor
    @ObservationIgnored private let copyText: (String) -> Void
    @ObservationIgnored private let formatter = EntryFormatter()
    /// Stored entries never change, so each row is formatted once. Pruned when the store shrinks (Clear).
    @ObservationIgnored private var rowCache: [UUID: RequestRow] = [:]
    @ObservationIgnored private var storeChanges: AnyCancellable?

    init(store: DesknetStore, runningApps: RunningAppsMonitor, copy: @escaping (String) -> Void) {
        self.store = store
        self.runningApps = runningApps
        self.copyText = copy
        storeChanges = store.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.reload() }
            }
        reload()
    }

    // MARK: Derived state

    var isHookInstalled: Bool { runningApps.isHookInstalled }

    var requestCountText: String { "\(entries.count) requests" }

    var emptyStateText: String {
        guard entries.isEmpty else { return "Select an API call from the list to view request/response details." }
        if selectedPID != nil, query.isEmpty {
            // The agent only loads at launch, so an app started before Desknet sends nothing.
            return "This app hasn't sent any requests. If it was started before Desknet, run it again from Xcode."
        }
        return "No requests found."
    }

    /// "All apps", then each running app, then the selected app if it has quit, so its logs stay reachable.
    var appRows: [AppRow] {
        let apps = runningApps.apps
        var rows = [AppRow(pid: nil, title: "All apps", subtitle: "\(totalCount) requests", isLive: !connectedPIDs.isEmpty)]
        rows += apps.map { app in
            AppRow(pid: app.pid, title: app.name, subtitle: subtitle(for: app), isLive: connectedPIDs.contains(app.pid))
        }
        if let pid = selectedPID, !apps.contains(where: { $0.pid == pid }) {
            rows.append(AppRow(pid: pid, title: "Ended app",
                               subtitle: "PID \(pid) · \(countsByPID[pid, default: 0]) requests", isLive: false))
        }
        return rows
    }

    var hasRunningApps: Bool { !runningApps.apps.isEmpty }

    var selectedAppRowID: String { AppRow.id(for: selectedPID) }

    func isSectionExpanded(_ section: DetailSection) -> Bool {
        !collapsedSections.contains(section)
    }

    // MARK: Intents

    func select(pid: pid_t?) {
        guard pid != selectedPID else { return }
        selectedPID = pid
        selectedEntryID = nil
        reload()
    }

    func select(entry id: UUID) {
        selectedEntryID = id
        updateDetail()
    }

    func setSection(_ section: DetailSection, expanded: Bool) {
        if expanded {
            collapsedSections.remove(section)
        } else {
            collapsedSections.insert(section)
        }
    }

    func clear() {
        store.clear()
    }

    func copy(_ text: String) {
        copyText(text)
    }

    func reload() {
        allEntries = store.snapshot(pid: selectedPID)
        connectedPIDs = store.connectedPIDs()
        countsByPID = store.countsByPID()
        totalCount = store.count()
        applyFilterAndSelection()
    }

    // MARK: Private

    private func subtitle(for app: RunningApp) -> String {
        let count = countsByPID[app.pid, default: 0]
        let logs = count > 0 || connectedPIDs.contains(app.pid) ? "\(count) requests" : "no logs yet"
        return "\(app.platformText) · \(logs)"
    }

    /// Keeps the current pick if it still matches the filter, else selects the newest entry.
    private func applyFilterAndSelection() {
        entries = allEntries.filter { EntryFormatter.matches($0, query: query) }
        if rowCache.count > totalCount {
            rowCache = [:]
        }
        requestRows = entries.map { entry in
            if let row = rowCache[entry.id] { return row }
            let row = RequestRow(entry: entry, formatter: formatter)
            rowCache[entry.id] = row
            return row
        }

        if selectedEntryID.map({ id in !entries.contains { $0.id == id } }) ?? true {
            selectedEntryID = entries.first?.id
        }
        updateDetail()
    }

    /// Entries never change once stored, so a detail for the same id is still current.
    private func updateDetail() {
        guard detail?.id != selectedEntryID else { return }
        detail = selectedEntryID
            .flatMap { id in entries.first { $0.id == id } }
            .map { RequestDetail(entry: $0, formatter: formatter) }
    }
}

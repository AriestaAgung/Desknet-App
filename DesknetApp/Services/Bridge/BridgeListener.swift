import Foundation

/// Accepts connections on the shared socket and feeds entries into the store.
/// show/hide/toggle go to `onCommand`.
final class DesknetBridgeListener: @unchecked Sendable {
    enum StartResult { case listening, alreadyRunning, failed }

    /// A line bigger than this is dropped with its connection, so one bad client
    /// can't grow memory without bound. Bodies arrive base64-encoded inside the JSON.
    static let maxLineBytes = 64 * 1024 * 1024

    private let store: DesknetStore
    private let path: String
    private let onCommand: @Sendable (DesknetBridgeMessage) -> Void
    private let lock = NSLock()
    private var listenFD: Int32?
    private var listenInode: ino_t = 0

    init(
        store: DesknetStore, path: String = DesknetBridgeSocket.path(),
        onCommand: @escaping @Sendable (DesknetBridgeMessage) -> Void
    ) {
        self.store = store
        self.path = path
        self.onCommand = onCommand
    }

    func start() -> StartResult {
        lock.lock()
        defer { lock.unlock() }
        guard listenFD == nil else { return .listening }

        // Another viewer (e.g. `swift run DesknetViewer`) owns the socket; replacing it would orphan that one.
        if let live = DesknetBridgeSocket.connect(to: path) {
            close(live)
            DesknetDiagnostics.log("Bridge", "another viewer is already listening path=\(path)")
            return .alreadyRunning
        }
        guard let fd = DesknetBridgeSocket.listen(at: path) else {
            DesknetDiagnostics.log("Bridge", "listen failed path=\(path) errno=\(errno)")
            return .failed
        }
        listenFD = fd
        var info = stat()
        listenInode = stat(path, &info) == 0 ? info.st_ino : 0
        DesknetDiagnostics.log("Bridge", "listening path=\(path)")

        // ponytail: one thread per client; fine for a handful of debug apps. Move to DispatchSource if that grows.
        Thread.detachNewThread { [weak self] in
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else {
                    if errno == EINTR { continue }
                    return  // listener closed by stop()
                }
                Thread.detachNewThread { self?.read(client) }
            }
        }
        return .listening
    }

    /// Listens again if the socket file was deleted or replaced by a viewer that has since quit.
    /// Without this, Desknet stays open but no app can reach it until it's relaunched.
    /// ponytail: the old fd and its accept thread are left behind, one per repair; fine for a rare event.
    func repairIfNeeded() {
        lock.lock()
        var info = stat()
        let intact = listenFD == nil || (stat(path, &info) == 0 && info.st_ino == listenInode)
        if !intact { listenFD = nil }
        lock.unlock()
        guard !intact else { return }
        DesknetDiagnostics.log("Bridge", "socket file gone, listening again path=\(path)")
        _ = start()
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard let fd = listenFD else { return }
        close(fd)
        unlink(path)
        listenFD = nil
    }

    /// The connecting process. Simulator apps are ordinary Mac processes, so this
    /// matches `RunningApp.pid` without any change to the wire format.
    static func peerPID(_ fd: Int32) -> pid_t? {
        var pid: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) == 0, pid > 0 else { return nil }
        return pid
    }

    private func read(_ fd: Int32) {
        defer { close(fd) }
        let pid = Self.peerPID(fd)
        if let pid { store.setConnected(true, pid: pid) }
        defer { if let pid { store.setConnected(false, pid: pid) } }
        DesknetDiagnostics.log("Bridge", "client connected pid=\(pid.map(String.init) ?? "-")")

        var pending = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            pending.append(contentsOf: chunk[0..<count])

            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<newline]
                pending.removeSubrange(pending.startIndex...newline)
                handle(line, pid: pid)
            }
            if pending.count > Self.maxLineBytes {
                DesknetDiagnostics.log("Bridge", "dropping client: line over \(Self.maxLineBytes) bytes")
                return
            }
        }
        DesknetDiagnostics.log("Bridge", "client disconnected")
    }

    func handle(_ line: Data, pid: pid_t? = nil) {
        guard let message = try? JSONDecoder().decode(DesknetBridgeMessage.self, from: line) else {
            DesknetDiagnostics.log("Bridge", "dropped undecodable message bytes=\(line.count)")
            return
        }
        if case let .entry(entry) = message {
            store.insert(entry, from: pid)
        } else {
            onCommand(message)
        }
    }
}

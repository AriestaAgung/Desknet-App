import Foundation

/// Messages from apps to Desknet.app, as newline-delimited JSON over a Unix socket.
/// Same shape the Desknet SDKs send today (Swift's synthesized enum coding:
/// `{"entry":{"_0":{...}}}`, `{"show":{}}`), so SDK apps work unchanged.
/// ponytail: protocol v2 (explicit `type`, `hello` with source info) replaces this in PLAN 1.2.
enum DesknetBridgeMessage: Codable, Sendable {
    case entry(NetworkLogEntry)
    case show
    case hide
    case toggle

    func encodedLine() throws -> Data {
        var data = try JSONEncoder().encode(self)
        data.append(0x0A)
        return data
    }
}

enum DesknetBridgeSocket {
    /// Simulator apps share the Mac's filesystem, so both sides reach this path.
    static func path(home: String = NSHomeDirectory()) -> String {
        home + "/Library/Caches/desknet.sock"
    }

    static func connect(to path: String) -> Int32? {
        guard var address = address(for: path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    static func listen(at path: String) -> Int32? {
        guard var address = address(for: path) else { return nil }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        // Owner-only: other users on this Mac can't read logs or inject entries.
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 8) == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    static func writeAll(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
    }

    private static func address(for path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }
}

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

    init(store: DesknetStore, path: String = DesknetBridgeSocket.path(),
         onCommand: @escaping @Sendable (DesknetBridgeMessage) -> Void) {
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
        DesknetDiagnostics.log("Bridge", "listening path=\(path)")

        // ponytail: one thread per client; fine for a handful of debug apps. Move to DispatchSource if that grows.
        Thread.detachNewThread { [weak self] in
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else {
                    if errno == EINTR { continue }
                    return // listener closed by stop()
                }
                Thread.detachNewThread { self?.read(client) }
            }
        }
        return .listening
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

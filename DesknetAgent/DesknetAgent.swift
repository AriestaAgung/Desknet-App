@preconcurrency import Foundation
import ObjectiveC

/// Called by `DesknetAgentBootstrap +load` when LLDB loads this framework.
@_cdecl("desknet_agent_start")
func desknet_agent_start() {
    DesknetAgent.start()
}

public enum DesknetAgent {
    private static let lock = NSLock()
    private static var started = false

    public static func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started, dlsym(UnsafeMutableRawPointer(bitPattern: -2), "desknet_sdk_present") == nil else { return }
        started = true
        DesknetAgentRuntime.shared.start()
    }
}

private final class DesknetAgentRuntime: @unchecked Sendable {
    static let shared = DesknetAgentRuntime()

    let sender = DesknetAgentSender()
    let store = DesknetAgentStore()
    let filter = DesknetAgentRequestFilter()
    private let lock = NSLock()
    private var enabled = false

    private init() {}

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return enabled
    }

    func start() {
        lock.lock()
        enabled = true
        lock.unlock()
        store.onComplete = { [sender] entry in sender.send(entry) }
        URLProtocol.registerClass(DesknetAgentURLProtocol.self)
        DesknetAgentSessionHook.install()
    }
}

private final class DesknetAgentRequestFilter {
    func shouldCapture(_ request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

private final class DesknetAgentStore: @unchecked Sendable {
    private struct Pending {
        let id: UUID
        let startedAt: Date
        let method: String
        let url: URL
        let requestHeaders: [String: String]
        let requestBody: Data
        var statusCode: Int?
        var responseHeaders: [String: String] = [:]
        var responseBody = Data()
        var mimeType: String?
    }

    private let lock = NSLock()
    private var pending: [UUID: Pending] = [:]
    var onComplete: (@Sendable (DesknetAgentEntry) -> Void)?

    func begin(_ request: URLRequest) -> UUID? {
        guard let url = request.url else { return nil }
        let entry = Pending(id: UUID(), startedAt: Date(), method: request.httpMethod ?? "GET", url: url,
                            requestHeaders: request.allHTTPHeaderFields ?? [:], requestBody: request.httpBody ?? Data())
        lock.lock()
        pending[entry.id] = entry
        lock.unlock()
        return entry.id
    }

    func response(_ response: URLResponse, for id: UUID?) {
        guard let id, let http = response as? HTTPURLResponse else { return }
        lock.lock()
        guard var entry = pending[id] else { lock.unlock(); return }
        entry.statusCode = http.statusCode
        entry.mimeType = http.mimeType
        entry.responseHeaders = Dictionary(uniqueKeysWithValues: http.allHeaderFields.map { (String(describing: $0.key), String(describing: $0.value)) })
        pending[id] = entry
        lock.unlock()
    }

    func append(_ data: Data, for id: UUID?) {
        guard let id else { return }
        lock.lock()
        guard var entry = pending[id] else { lock.unlock(); return }
        entry.responseBody.append(data)
        pending[id] = entry
        lock.unlock()
    }

    func finish(_ id: UUID?, error: Error?) {
        guard let id else { return }
        lock.lock()
        guard let entry = pending.removeValue(forKey: id) else { lock.unlock(); return }
        let handler = onComplete
        lock.unlock()
        handler?(DesknetAgentEntry(id: entry.id, startedAt: entry.startedAt, endedAt: Date(), method: entry.method,
            url: entry.url, requestHeaders: entry.requestHeaders, requestBody: entry.requestBody, statusCode: entry.statusCode,
            responseHeaders: entry.responseHeaders, responseBody: entry.responseBody, mimeType: entry.mimeType,
            errorDescription: error?.localizedDescription))
    }
}

private final class DesknetAgentURLProtocol: URLProtocol {
    private static let handledKey = "desknet.agent.handled"
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var entryID: UUID?

    static func install(in configuration: URLSessionConfiguration) {
        let classes = configuration.protocolClasses ?? []
        guard !classes.contains(where: { ObjectIdentifier($0) == ObjectIdentifier(self) }) else { return }
        configuration.protocolClasses = [self] + classes
    }

    override class func canInit(with request: URLRequest) -> Bool {
        URLProtocol.property(forKey: handledKey, in: request) == nil && DesknetAgentRuntime.shared.isEnabled && DesknetAgentRuntime.shared.filter.shouldCapture(request)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutable)
        let request = mutable as URLRequest
        entryID = DesknetAgentRuntime.shared.store.begin(request)
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        self.dataTask = task
        task.resume()
    }

    override func stopLoading() {
        // `dataTask`, not `task`: `URLProtocol.task` is the caller's own task, and cancelling it fails their request.
        dataTask?.cancel()
        session?.invalidateAndCancel()
    }
}

extension DesknetAgentURLProtocol: URLSessionDataDelegate {
    func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
        DesknetAgentRuntime.shared.store.append(data, for: entryID)
        client?.urlProtocol(self, didLoad: data)
    }

    func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        DesknetAgentRuntime.shared.store.response(response, for: entryID)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        DesknetAgentRuntime.shared.store.finish(entryID, error: error)
        if let error { client?.urlProtocol(self, didFailWithError: error) } else { client?.urlProtocolDidFinishLoading(self) }
        self.dataTask = nil
        session.invalidateAndCancel()
        self.session = nil
    }
}

private enum DesknetAgentSessionHook {
    private static let installOnce: Void = {
        guard let metaclass = object_getClass(URLSessionConfiguration.self) else { return }
        for (original, replacement) in [
            (#selector(getter: URLSessionConfiguration.default), #selector(URLSessionConfiguration.desknetAgentDefault)),
            (#selector(getter: URLSessionConfiguration.ephemeral), #selector(URLSessionConfiguration.desknetAgentEphemeral))
        ] {
            guard let source = class_getInstanceMethod(metaclass, original), let target = class_getInstanceMethod(metaclass, replacement) else { continue }
            method_exchangeImplementations(source, target)
        }
    }()

    static func install() { _ = installOnce }
}

private extension URLSessionConfiguration {
    @objc dynamic class func desknetAgentDefault() -> URLSessionConfiguration {
        let configuration = desknetAgentDefault()
        DesknetAgentURLProtocol.install(in: configuration)
        return configuration
    }

    @objc dynamic class func desknetAgentEphemeral() -> URLSessionConfiguration {
        let configuration = desknetAgentEphemeral()
        DesknetAgentURLProtocol.install(in: configuration)
        return configuration
    }
}

private struct DesknetAgentEntry: Codable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let method: String
    let url: URL
    let requestHeaders: [String: String]
    let requestBody: Data
    let statusCode: Int?
    let responseHeaders: [String: String]
    let responseBody: Data
    let mimeType: String?
    let errorDescription: String?
}

private enum DesknetAgentMessage: Codable {
    case entry(DesknetAgentEntry)
}

private final class DesknetAgentSender: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.desknet.agent.sender")
    private var pending: [DesknetAgentEntry] = []
    private var fd: Int32 = -1

    func send(_ entry: DesknetAgentEntry) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pending.append(entry)
            if self.pending.count > 500 { self.pending.removeFirst(self.pending.count - 500) }
            self.flush()
        }
    }

    private func flush() {
        if fd < 0 { fd = DesknetAgentSocket.connect(path: NSHomeDirectory() + "/Library/Caches/desknet.sock") ?? -1 }
        guard fd >= 0 else { return }
        while let entry = pending.first {
            guard let data = try? JSONEncoder().encode(DesknetAgentMessage.entry(entry)) + Data([0x0A]), DesknetAgentSocket.write(data, fd: fd) else {
                close(fd); fd = -1; return
            }
            pending.removeFirst()
        }
    }
}

private enum DesknetAgentSocket {
    static func connect(path: String) -> Int32? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        let result = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard result == 0 else { close(fd); return nil }
        return fd
    }

    static func write(_ data: Data, fd: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return false }
                offset += count
            }
            return true
        }
    }
}

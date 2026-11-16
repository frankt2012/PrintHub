import Foundation

/// Minimal WebSocket client for the Creality printer API.
///
/// `URLSessionWebSocketTask` is used because it negotiates the required
/// `wsslicer` subprotocol correctly (verified against a local mock). The event
/// stream is the only API the rest of the app needs.
public final class WebSocketClient: @unchecked Sendable {
    public enum Event: Sendable {
        case ready
        case text(String)
        case binary(Data)
        case closed(code: UInt16?, reason: String)
        case failed(String)
    }

    public let events: AsyncStream<Event>

    private let eventContinuation: AsyncStream<Event>.Continuation
    private let lock = NSLock()

    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var closed = false
    private var readyResolved = false

    public init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        self.events = stream
        self.eventContinuation = continuation
    }

    deinit {
        task?.cancel(with: .goingAway, reason: nil)
        receiveTask?.cancel()
        eventContinuation.finish()
    }

    // MARK: - Public API

    public func connect(
        host: String,
        port: UInt16 = 9999,
        subprotocol: String = "wsslicer",
        timeout: TimeInterval = 5
    ) async throws {
        guard let url = URL(string: "ws://\(host):\(port)") else {
            throw WebSocketError.connectionFailed("Invalid host \(host)")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(subprotocol, forHTTPHeaderField: "Sec-WebSocket-Protocol")
        request.setValue("ChamberSpike/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("http://\(host):\(port)", forHTTPHeaderField: "Origin")

        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        closed = false
        readyResolved = false
        task.resume()

        // The receive loop must be active for URLSession to process WebSocket
        // control frames, including the pong we use as a readiness check.
        startReceiveLoop()

        // A URLSessionWebSocketTask starts in a connecting state; a successful
        // ping is the cheapest way to prove the handshake completed before we
        // report "connected" to the caller.
        do {
            try await ping(task, timeout: timeout)
        } catch {
            shutdown(code: 1006, reason: "handshake failed", emitClosed: false)
            throw error
        }

        resolveReady()
    }

    public func send(text: String) async throws {
        guard let task, !isClosed else {
            throw WebSocketError.notConnected
        }

        do {
            try await task.send(.string(text))
        } catch {
            throw WebSocketError.sendFailed(String(describing: error))
        }
    }

    public func close() {
        shutdown(code: 1000, reason: "client closed", emitClosed: false)
    }

    // MARK: - Readiness

    private func ping(_ task: URLSessionWebSocketTask, timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = PingGate(continuation)

            task.sendPing { error in
                if let error {
                    gate.finish(.failure(
                        WebSocketError.connectionFailed(String(describing: error))
                    ))
                } else {
                    gate.finish(.success(()))
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                gate.finish(.failure(WebSocketError.timeout))
            }
        }
    }

    // MARK: - Receive

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }

            while !self.isClosed {
                guard let task = self.task else { return }

                do {
                    let message = try await task.receive()
                    switch message {
                    case .string(let text):
                        self.eventContinuation.yield(.text(text))
                    case .data(let data):
                        self.eventContinuation.yield(.binary(data))
                    @unknown default:
                        break
                    }
                } catch {
                    if !self.isClosed {
                        let nsError = error as NSError
                        if nsError.code == NSURLErrorCancelled {
                            self.shutdown(code: 1000, reason: "cancelled", emitClosed: true)
                        } else {
                            self.eventContinuation.yield(.failed(String(describing: error)))
                            self.shutdown(code: 1006, reason: "receive failed", emitClosed: false)
                        }
                    }
                    return
                }
            }
        }
    }

    // MARK: - Lifecycle

    private var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    private func resolveReady() {
        lock.lock()
        if readyResolved {
            lock.unlock()
            return
        }
        readyResolved = true
        lock.unlock()

        eventContinuation.yield(.ready)
    }

    private func shutdown(code: UInt16, reason: String, emitClosed: Bool) {
        lock.lock()
        if closed {
            lock.unlock()
            return
        }
        closed = true
        let task = self.task
        self.task = nil
        lock.unlock()

        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)

        if emitClosed {
            eventContinuation.yield(.closed(code: code, reason: reason))
        }
        eventContinuation.finish()
    }
}

private final class PingGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

public enum WebSocketError: Error, CustomStringConvertible {
    case timeout
    case notConnected
    case closed
    case connectionFailed(String)
    case sendFailed(String)

    public var description: String {
        switch self {
        case .timeout:
            return "Connection timed out"
        case .notConnected:
            return "WebSocket is not connected"
        case .closed:
            return "WebSocket closed"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .sendFailed(let reason):
            return "Send failed: \(reason)"
        }
    }
}

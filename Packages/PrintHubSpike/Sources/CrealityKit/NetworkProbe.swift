import Foundation
import Network

public struct HTTPProbe: Sendable {
    public let url: URL
    public let status: Int?
    public let contentType: String?
    public let byteCount: Int
    public let elapsed: TimeInterval
    public let error: String?

    public var isReachable: Bool { status != nil }
}

public struct HandshakeProbe: Sendable {
    public let statusLine: String
    public let headers: [String: String]
    public let elapsed: TimeInterval

    public var statusCode: Int? {
        let parts = statusLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return Int(parts[1])
    }

    public var negotiatedSubprotocol: String? {
        headers["sec-websocket-protocol"]
    }
}

public struct WebSocketProbe: Sendable {
    public let connected: Bool
    public let firstFrame: String?
    public let elapsed: TimeInterval
    public let error: String?
}

public enum NetworkProbe {
    public static func http(
        host: String,
        port: UInt16,
        path: String,
        timeout: TimeInterval = 3
    ) async -> HTTPProbe {
        let started = Date()
        guard let url = URL(string: "http://\(host):\(port)\(path)") else {
            return HTTPProbe(
                url: URL(string: "http://\(host)")!,
                status: nil,
                contentType: nil,
                byteCount: 0,
                elapsed: 0,
                error: "Invalid URL"
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Cache-Control": "no-cache"]

        let session = URLSession(configuration: configuration)

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("PrintHubSpike/0.1", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            return HTTPProbe(
                url: url,
                status: http?.statusCode,
                contentType: http?.value(forHTTPHeaderField: "Content-Type"),
                byteCount: data.count,
                elapsed: Date().timeIntervalSince(started),
                error: nil
            )
        } catch {
            return HTTPProbe(
                url: url,
                status: nil,
                contentType: nil,
                byteCount: 0,
                elapsed: Date().timeIntervalSince(started),
                error: (error as NSError).localizedDescription
            )
        }
    }

    /// Raw HTTP Upgrade probe. This shows whether the printer negotiates the
    /// `wsslicer` subprotocol before we rely on Network.framework's WebSocket.
    public static func websocketHandshake(
        host: String,
        port: UInt16 = 9999,
        path: String = "/",
        subprotocol: String = "wsslicer",
        timeout: TimeInterval = 5
    ) async -> Result<HandshakeProbe, Error> {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.chamber.creality.handshake")
            let lock = NSLock()
            var finished = false
            var buffer = Data()
            let started = Date()

            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: .failure(WebSocketError.connectionFailed("Invalid port")))
                return
            }

            let parameters = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: nwPort,
                using: parameters
            )

            func finish(_ result: Result<HandshakeProbe, Error>) {
                lock.lock()
                if finished {
                    lock.unlock()
                    return
                }
                finished = true
                lock.unlock()
                connection.cancel()
                continuation.resume(returning: result)
            }

            func parseHeaders() {
                let text = String(decoding: buffer, as: UTF8.self)
                guard let range = text.range(of: "\r\n\r\n") else { return }
                let headerBlock = String(text[..<range.lowerBound])
                let lines = headerBlock.components(separatedBy: "\r\n")
                guard let statusLine = lines.first else {
                    finish(.failure(WebSocketError.connectionFailed("Empty handshake response")))
                    return
                }

                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let separator = line.firstIndex(of: ":") else { continue }
                    let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = line[line.index(after: separator)...]
                        .trimmingCharacters(in: .whitespaces)
                    headers[key] = value
                }

                finish(.success(HandshakeProbe(
                    statusLine: statusLine,
                    headers: headers,
                    elapsed: Date().timeIntervalSince(started)
                )))
            }

            func receive() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
                    if let error {
                        finish(.failure(WebSocketError.connectionFailed(String(describing: error))))
                        return
                    }
                    if let data {
                        buffer.append(data)
                    }
                    if String(decoding: buffer, as: UTF8.self).contains("\r\n\r\n") {
                        parseHeaders()
                        return
                    }
                    if isComplete {
                        finish(.failure(WebSocketError.connectionFailed("Connection closed during handshake")))
                        return
                    }
                    receive()
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
                        .base64EncodedString()
                    let request = [
                        "GET \(path) HTTP/1.1",
                        "Host: \(host):\(port)",
                        "Upgrade: websocket",
                        "Connection: Upgrade",
                        "Sec-WebSocket-Key: \(key)",
                        "Sec-WebSocket-Version: 13",
                        "Sec-WebSocket-Protocol: \(subprotocol)",
                        "Origin: http://\(host):\(port)",
                        "",
                        ""
                    ].joined(separator: "\r\n")

                    connection.send(
                        content: Data(request.utf8),
                        completion: .contentProcessed { error in
                            if let error {
                                finish(.failure(WebSocketError.connectionFailed(String(describing: error))))
                            } else {
                                receive()
                            }
                        }
                    )

                case .failed(let error):
                    finish(.failure(WebSocketError.connectionFailed(String(describing: error))))

                case .cancelled:
                    finish(.failure(WebSocketError.closed))

                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                finish(.failure(WebSocketError.timeout))
            }
        }
    }

    /// Connect through the real WebSocket client and wait for the first text
    /// frame. A poll is sent after a short delay because some firmware does not
    /// stream until asked.
    public static func websocket(
        host: String,
        port: UInt16 = 9999,
        subprotocol: String = "wsslicer",
        timeout: TimeInterval = 6
    ) async -> WebSocketProbe {
        let started = Date()
        let client = WebSocketClient()

        do {
            try await client.connect(
                host: host,
                port: port,
                subprotocol: subprotocol,
                timeout: timeout
            )
        } catch {
            client.close()
            return WebSocketProbe(
                connected: false,
                firstFrame: nil,
                elapsed: Date().timeIntervalSince(started),
                error: String(describing: error)
            )
        }

        let pollTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            try? await client.send(text: #"{"method":"get","params":{"ReqPrinterPara":1}}"#)
        }

        enum FirstFrame: Sendable {
            case text(String)
            case failure(String)
            case none
        }

        let first = await withTaskGroup(of: FirstFrame.self) { group in
            group.addTask {
                var lastText: String?

                for await event in client.events {
                    switch event {
                    case .text(let text):
                        if text == "ok" { continue }
                        if text.contains("heart_beat") {
                            try? await client.send(text: "ok")
                            continue
                        }

                        lastText = text
                        // Wait for a frame that identifies the printer; early
                        // frames can be partial progress updates.
                        if text.contains("\"model\"") {
                            return .text(text)
                        }

                    case .failed(let reason):
                        return .failure(reason)
                    case .closed:
                        return lastText.map(FirstFrame.text) ?? .none
                    default:
                        break
                    }
                }

                return lastText.map(FirstFrame.text) ?? .none
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return .none
            }

            let result = await group.next() ?? .none
            group.cancelAll()
            return result
        }

        pollTask.cancel()
        client.close()

        switch first {
        case .text(let text):
            return WebSocketProbe(
                connected: true,
                firstFrame: text,
                elapsed: Date().timeIntervalSince(started),
                error: nil
            )
        case .failure(let reason):
            return WebSocketProbe(
                connected: true,
                firstFrame: nil,
                elapsed: Date().timeIntervalSince(started),
                error: reason
            )
        case .none:
            return WebSocketProbe(
                connected: true,
                firstFrame: nil,
                elapsed: Date().timeIntervalSince(started),
                error: "Connected, but no frame arrived"
            )
        }
    }
}

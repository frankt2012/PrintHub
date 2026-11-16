import Foundation

/// Streams an MJPEG endpoint and calls `onFrame` with complete JPEGs.
///
/// The handler runs on a private serial delegate queue, not the main queue.
public final class MJPEGClient: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    public typealias FrameHandler = (Data) -> Void

    private let onFrame: FrameHandler
    private let onError: ((Error) -> Void)?
    private let onResponse: ((HTTPURLResponse) -> Void)?

    private let delegateQueue: OperationQueue
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var parser = JPEGFrameParser()
    private var stopped = false
    private var receivedResponse = false

    public private(set) var frameCount = 0
    public private(set) var byteCount = 0
    public private(set) var startedAt = Date()

    public init(
        onFrame: @escaping FrameHandler,
        onError: ((Error) -> Void)? = nil,
        onResponse: ((HTTPURLResponse) -> Void)? = nil
    ) {
        self.onFrame = onFrame
        self.onError = onError
        self.onResponse = onResponse

        let queue = OperationQueue()
        queue.name = "com.chamber.camera.mjpeg"
        queue.maxConcurrentOperationCount = 1
        self.delegateQueue = queue

        super.init()
    }

    public func start(url: URL, timeout: TimeInterval = 10) {
        stop()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = .infinity
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Cache-Control": "no-cache"]

        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: delegateQueue
        )
        self.session = session

        startedAt = Date()
        frameCount = 0
        byteCount = 0
        stopped = false
        receivedResponse = false
        parser.reset()

        var request = URLRequest(url: url)
        request.setValue("ChamberSpike/0.1", forHTTPHeaderField: "User-Agent")

        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    public func stop() {
        stopped = true
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
    }

    public var fps: Double {
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > 0 else { return 0 }
        return Double(frameCount) / elapsed
    }

    // MARK: - URLSessionDataDelegate

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if !receivedResponse, let http = response as? HTTPURLResponse {
            receivedResponse = true
            onResponse?(http)
        }
        completionHandler(.allow)
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard !stopped else { return }
        byteCount += data.count

        let frames = parser.append(data)
        for frame in frames {
            frameCount += 1
            onFrame(frame)
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard !stopped, let error else { return }
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled {
            return
        }
        onError?(error)
    }
}

public enum CameraHTTP {
    public static func snapshot(
        host: String,
        port: UInt16 = 8080,
        path: String = "/?action=snapshot",
        timeout: TimeInterval = 6
    ) async throws -> Data {
        guard let url = URL(string: "http://\(host):\(port)\(path)") else {
            throw CameraError.invalidURL
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        let session = URLSession(configuration: configuration)
        var request = URLRequest(url: url)
        request.setValue("ChamberSpike/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CameraError.httpError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        guard data.count > 2, data.starts(with: [0xFF, 0xD8]) else {
            throw CameraError.notJPEG(data.count)
        }
        return data
    }
}

public enum CameraError: Error, CustomStringConvertible {
    case invalidURL
    case httpError(Int)
    case notJPEG(Int)

    public var description: String {
        switch self {
        case .invalidURL:
            return "Invalid camera URL"
        case .httpError(let status):
            return "Camera returned HTTP \(status)"
        case .notJPEG(let bytes):
            return "Camera returned \(bytes) bytes that are not a JPEG"
        }
    }
}

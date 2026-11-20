import Foundation

/// Owns the bundled go2rtc helper. One helper serves all K2 cameras; it
/// re-publishes the printer WebRTC stream as HLS for AVPlayer.
@MainActor
final class Go2RTCSupervisor {
    private let port: UInt16
    private var process: Process?
    private var logHandle: FileHandle?
    private var activeHost: String?

    init(port: UInt16 = 1984) {
        self.port = port
    }

    var isRunning: Bool {
        process?.isRunning == true
    }

    func start(host: String) async throws -> URL {
        if process?.isRunning == true, activeHost == host {
            return try streamURL()
        }

        stop()

        guard let binary = locateBinary() else {
            throw Go2RTCError.binaryMissing
        }

        let support = try supportDirectory()
        let configURL = support.appendingPathComponent("go2rtc.yaml")
        let logURL = support.appendingPathComponent("go2rtc.log")

        // A previous app instance may have left go2rtc orphaned. It holds the
        // fixed local ports, so remove only the helper using this exact config.
        killStaleHelper(configURL)

        let config = """
        api:
          listen: "127.0.0.1:\(port)"
          origin: "*"

        log:
          level: info

        rtsp:
          listen: "127.0.0.1:8554"

        webrtc:
          listen: "127.0.0.1:8555"
          candidates:
            - "127.0.0.1:8555"
          filters:
            loopback: true

        streams:
          k2: webrtc:http://\(host):8000/call/webrtc_local#format=creality
        """

        try config.write(to: configURL, atomically: true, encoding: .utf8)

        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let log = try FileHandle(forWritingTo: logURL)
        try log.seekToEnd()
        logHandle = log

        let process = Process()
        process.executableURL = binary
        process.arguments = ["-config", configURL.path]
        process.standardOutput = log
        process.standardError = log

        try process.run()
        self.process = process
        activeHost = host

        let started = Date()
        while Date().timeIntervalSince(started) < 12 {
            try await Task.sleep(nanoseconds: 250_000_000)
            if await isHealthy() {
                return try streamURL()
            }
            if !process.isRunning {
                break
            }
        }

        stop()
        throw Go2RTCError.failedToStart
    }

    func stop() {
        process?.terminate()
        process = nil
        activeHost = nil
        try? logHandle?.close()
        logHandle = nil
    }

    private func killStaleHelper(_ configURL: URL) {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-f", "go2rtc -config \(configURL.path)"]
        try? pkill.run()
        pkill.waitUntilExit()
    }

    private func streamURL() throws -> URL {
        guard let url = URL(string: "http://127.0.0.1:\(port)/stream.html?src=k2&mode=webrtc&background=false") else {
            throw Go2RTCError.invalidURL
        }
        return url
    }

    private func isHealthy() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/api/streams") else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 1

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func supportDirectory() throws -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let directory = base.appendingPathComponent("PrintHub", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func locateBinary() -> URL? {
        let bundled = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("go2rtc")

        for candidate in [bundled].compactMap({ $0 }) {
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}

enum Go2RTCError: Error, LocalizedError {
    case binaryMissing
    case failedToStart
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "go2rtc is missing from the app bundle."
        case .failedToStart:
            return "go2rtc could not start the camera bridge."
        case .invalidURL:
            return "go2rtc returned an invalid stream URL."
        }
    }
}

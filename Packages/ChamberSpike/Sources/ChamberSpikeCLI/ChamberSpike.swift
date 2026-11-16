import Foundation
import AVFoundation
import CoreImage
import CrealityKit
import CameraKit

#if canImport(Darwin)
import Darwin
#endif

@main
struct ChamberSpike {
    static func main() async {
        var arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            printUsage()
            exit(1)
        }
        arguments.removeFirst()

        do {
            switch command {
            case "discover":
                try await runDiscover(Options(arguments))
            case "probe":
                try await runProbe(Options(arguments))
            case "watch":
                try await runWatch(Options(arguments))
            case "snapshot":
                try await runSnapshot(Options(arguments))
            case "mjpeg":
                try await runMJPEG(Options(arguments))
            case "webrtc":
                try await runWebRTC(Options(arguments))
            case "control":
                try await runControl(Options(arguments))
            case "hostapp":
                try await runHostApp(Options(arguments))
            case "help", "--help", "-h":
                printUsage()
            default:
                fputs("Unknown command: \(command)\n\n", stderr)
                printUsage()
                exit(1)
            }
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }

    // MARK: - discover

    static func runDiscover(_ options: Options) async throws {
        let seconds = options.int("seconds") ?? 5
        print("Browsing Bonjour for \(seconds)s…")

        let names = await Task.detached {
            DNSSDDiscovery.browse(seconds: TimeInterval(seconds))
        }.value

        guard !names.isEmpty else {
            print("No _http._tcp services found.")
            print("Check that the printers are on, on the same LAN, and not on a guest/VLAN-isolated network.")
            return
        }

        print("")
        print("Found \(names.count) service(s):")
        for name in names {
            print("  \(name)")
        }

        let printerLike = names.filter { name in
            let lower = name.lowercased()
            return ["creality", "k1", "k2", "ender", "hi"].contains { lower.contains($0) }
        }
        let candidates = printerLike.isEmpty ? names : printerLike

        print("")
        print("Resolving \(min(candidates.count, 8)) candidate(s)…")

        for name in candidates.prefix(8) {
            guard let service = await Task.detached(operation: {
                DNSSDDiscovery.resolve(name: name, seconds: 2)
            }).value else {
                continue
            }

            let handshake = await NetworkProbe.websocketHandshake(
                host: service.host,
                timeout: 2
            )
            let isPrinter: Bool
            if case .success(let result) = handshake, result.statusCode == 101 {
                isPrinter = true
            } else {
                isPrinter = false
            }

            let marker = isPrinter ? "✓ printer" : "  service"
            print("  \(marker)  \(service.name)  \(service.host)  (HTTP port \(service.servicePort))")
        }
    }

    // MARK: - probe

    static func runProbe(_ options: Options) async throws {
        guard let host = options.positional.first else {
            throw CLIError.missingHost
        }

        let wsPort = UInt16(options.int("ws-port") ?? 9999)
        let cameraPort = UInt16(options.int("camera-port") ?? 8080)
        let webrtcPort = UInt16(options.int("webrtc-port") ?? 8000)
        let fluiddPort = UInt16(options.int("fluidd-port") ?? 4408)

        print("Chamber spike — probing \(host)")
        print("")

        let handshake = await NetworkProbe.websocketHandshake(host: host, port: wsPort)
        switch handshake {
        case .success(let result):
            let code = result.statusCode.map(String.init) ?? "?"
            print("  9999  WS handshake  HTTP \(code)  subprotocol: \(result.negotiatedSubprotocol ?? "none")  \(milliseconds(result.elapsed))")
            if let server = result.headers["server"] {
                print("        server: \(server)")
            }
        case .failure(let error):
            print("  9999  WS handshake  failed: \(error)")
        }

        async let webrtc = NetworkProbe.http(
            host: host, port: webrtcPort, path: "/call/webrtc_local", timeout: 3
        )
        async let mjpeg = NetworkProbe.http(
            host: host, port: cameraPort, path: "/?action=snapshot", timeout: 3
        )
        async let mjpeg4409 = NetworkProbe.http(
            host: host, port: 4409, path: "/webcam/?action=snapshot", timeout: 3
        )
        async let moonraker = NetworkProbe.http(
            host: host, port: 7125, path: "/server/info", timeout: 3
        )
        async let fluidd = NetworkProbe.http(
            host: host, port: fluiddPort, path: "/", timeout: 3
        )

        let (webrtcResult, mjpegResult, mjpeg4409Result, moonrakerResult, fluiddResult) =
            await (webrtc, mjpeg, mjpeg4409, moonraker, fluidd)

        printHTTP("\(webrtcPort)  WebRTC", result: webrtcResult)
        printHTTP("\(cameraPort)  MJPEG", result: mjpegResult)
        printHTTP("4409  MJPEG", result: mjpeg4409Result)
        printHTTP("7125  Moonraker", result: moonrakerResult)
        printHTTP("\(fluiddPort)  Fluidd", result: fluiddResult)

        print("")
        print("  WebSocket probe…")
        let probe = await NetworkProbe.websocket(host: host, port: wsPort, timeout: 6)

        if !probe.connected {
            print("  failed: \(probe.error ?? "unknown error")")
            return
        }

        if let text = probe.firstFrame, let frame = try? JSONValue.decode(text) {
            var snapshot = PrinterSnapshot()
            snapshot.merge(frame)
            print("  connected in \(milliseconds(probe.elapsed))")
            let firmware = snapshot.firmwareVersion.map { "  firmware \($0)" } ?? ""
            print("  model: \(snapshot.friendlyModel ?? "unknown") (\(snapshot.model ?? "unknown board"))\(firmware)")
            print("  hostname: \(snapshot.hostname ?? "unknown")")
            print("  state: \(snapshot.oneLineSummary)")
            if let webrtc = snapshot.webrtcSupported {
                print("  camera: \(webrtc ? "WebRTC (:8000)" : "MJPEG (:8080 / :4409)")")
            }
        } else {
            print("  connected in \(milliseconds(probe.elapsed)), but no state frame arrived")
            if let error = probe.error {
                print("  \(error)")
            }
        }
    }

    // MARK: - watch

    static func runWatch(_ options: Options) async throws {
        guard let host = options.positional.first else {
            throw CLIError.missingHost
        }

        let seconds = options.int("seconds") ?? 60
        let verbose = options.flag("verbose")
        let wsPort = UInt16(options.int("ws-port") ?? 9999)
        let recorder = try options.value("record").map { try JSONLRecorder(path: $0) }

        let started = Date()
        let client = WebSocketClient()
        let events = client.events

        try await client.connect(host: host, port: wsPort, timeout: 6)
        print("Connected to \(host):\(wsPort)")

        let poller = Task {
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                tick += 1
                if tick == 1 || tick % 300 == 0 {
                    try? await client.send(text: #"{"method":"get","params":{"boxsInfo":1}}"#)
                }
                if tick % 2 == 0 {
                    try? await client.send(text: #"{"method":"get","params":{"reqPrintObjects":1}}"#)
                }
                if tick % 5 == 0 {
                    try? await client.send(text: #"{"method":"get","params":{"ReqPrinterPara":1}}"#)
                }
            }
        }

        let consumer = Task {
            var snapshot = PrinterSnapshot()
            var lastSummary = ""
            var frameCount = 0

            for await event in events {
                switch event {
                case .ready:
                    if verbose { print("socket ready") }

                case .text(let text):
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed == "ok" { continue }

                    if trimmed.contains("heart_beat") {
                        try? await client.send(text: "ok")
                        if verbose { print("heartbeat") }
                        continue
                    }

                    let timestamp = String(format: "%.3f", Date().timeIntervalSince(started))
                    recorder?.write("{\"t\":\(timestamp),\"json\":\(text)}\n")

                    guard let frame = try? JSONValue.decode(text) else {
                        if verbose { print("unparsed frame: \(text)") }
                        continue
                    }

                    snapshot.merge(frame)
                    frameCount += 1
                    let summary = snapshot.oneLineSummary

                    if verbose || frameCount == 1 || summary != lastSummary || frameCount % 25 == 0 {
                        let elapsed = PrinterSnapshot.formatDuration(Date().timeIntervalSince(started))
                        print("[\(elapsed)] \(summary)")
                        lastSummary = summary
                    }

                case .binary(let data):
                    if verbose { print("binary frame (\(data.count) bytes)") }

                case .failed(let reason):
                    fputs("socket error: \(reason)\n", stderr)

                case .closed(let code, let reason):
                    if verbose {
                        print("socket closed (\(code.map(String.init) ?? "-") \(reason))")
                    }
                    return
                }
            }
        }

        try await Task.sleep(nanoseconds: UInt64(max(1, seconds)) * 1_000_000_000)

        client.close()
        poller.cancel()
        consumer.cancel()
        _ = try? await Task.sleep(nanoseconds: 200_000_000)
        recorder?.close()

        print("Stopped after \(seconds)s")
    }

    // MARK: - snapshot

    static func runSnapshot(_ options: Options) async throws {
        guard let host = options.positional.first else {
            throw CLIError.missingHost
        }

        let port = UInt16(options.int("port") ?? 8080)
        let path = options.value("path") ?? "/?action=snapshot"
        let output = options.value("out") ?? defaultSnapshotPath(host: host)

        do {
            let data = try await CameraHTTP.snapshot(host: host, port: port, path: path)
            try write(data: data, to: output)
            print("Saved \(data.count) bytes to \(output)")
        } catch {
            // A common K1-family fallback.
            if port == 8080 {
                print("8080 failed (\(error)); trying 4409…")
                let data = try await CameraHTTP.snapshot(
                    host: host, port: 4409, path: "/webcam/?action=snapshot"
                )
                try write(data: data, to: output)
                print("Saved \(data.count) bytes to \(output)")
            } else {
                throw error
            }
        }
    }

    // MARK: - mjpeg

    static func runMJPEG(_ options: Options) async throws {
        guard let host = options.positional.first else {
            throw CLIError.missingHost
        }

        let seconds = options.int("seconds") ?? 30
        let port = UInt16(options.int("port") ?? 8080)
        let path = options.value("path") ?? "/?action=stream"
        let saveDirectory = options.value("save")
        let started = Date()

        if let saveDirectory {
            try FileManager.default.createDirectory(
                atPath: saveDirectory,
                withIntermediateDirectories: true
            )
        }

        let stats = MJPEGStats()
        let client = MJPEGClient(
            onFrame: { jpeg in
                stats.recordFrame(jpeg)
                if let saveDirectory, stats.frameCount % 15 == 0 {
                    let name = String(format: "frame-%05d.jpg", stats.frameCount)
                    try? jpeg.write(to: URL(fileURLWithPath: saveDirectory).appendingPathComponent(name))
                }
            },
            onError: { error in
                fputs("MJPEG error: \(error)\n", stderr)
            },
            onResponse: { response in
                print("  HTTP \(response.statusCode)  \(response.value(forHTTPHeaderField: "Content-Type") ?? "unknown type")")
            }
        )

        guard let url = URL(string: "http://\(host):\(port)\(path)") else {
            throw CLIError.invalidURL
        }

        print("Streaming \(url.absoluteString) for \(seconds)s…")
        client.start(url: url)

        let ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let snapshot = stats.snapshot()
                print(String(
                    format: "  %5.1f fps   %6d frames   %7.1f KB",
                    snapshot.fps,
                    snapshot.frames,
                    Double(snapshot.bytes) / 1024
                ))
            }
        }

        try await Task.sleep(nanoseconds: UInt64(max(1, seconds)) * 1_000_000_000)

        ticker.cancel()
        client.stop()

        let final = stats.snapshot()
        let elapsed = Date().timeIntervalSince(started)
        print(String(
            format: "Done: %d frames, %.1f fps avg, %.1f KB",
            final.frames,
            Double(final.frames) / max(elapsed, 0.001),
            Double(final.bytes) / 1024
        ))
    }

    // MARK: - host app

    /// Runs the full Phase 0 sequence from inside a bundled app, where macOS
    /// can grant Local Network permission. All output goes to a log file so
    /// LaunchServices does not need to capture stdout.
    static func runHostApp(_ options: Options) async throws {
        let host = options.value("host") ?? "192.168.1.50"
        let logPath = options.value("log")
            ?? "/Volumes/HOME 1TB EXT/Documents/Chamber/captures/host-app.log"
        let recordPath = options.value("record")
            ?? "/Volumes/HOME 1TB EXT/Documents/Chamber/captures/k2-live.jsonl"

        let logURL = URL(fileURLWithPath: logPath)
        try FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        logURL.path.withCString { path in
            _ = freopen(path, "a", stdout)
        }
        logURL.path.withCString { path in
            _ = freopen(path, "a", stderr)
        }
        setvbuf(stdout, nil, _IONBF, 0)
        setvbuf(stderr, nil, _IONBF, 0)

        let mode = options.value("mode") ?? "all"
        let seconds = options.int("seconds") ?? 60

        print("")
        print("=== ChamberSpike host app ===")
        print("date: \(Date())")
        print("host: \(host)")
        print("mode: \(mode)")

        switch mode {
        case "probe":
            try await runProbe(Options([host]))
        case "watch":
            try await runWatch(Options([host, "--seconds", String(seconds), "--record", recordPath]))
        case "webrtc":
            try await runWebRTC(Options([host, "--seconds", String(seconds)]))
        case "go2rtc":
            try await runGo2RTC(host: host)
        default:
            try await runProbe(Options([host]))
            try await runWatch(Options([host, "--seconds", String(seconds), "--record", recordPath]))
            try await runWebRTC(Options([host, "--seconds", String(seconds)]))
        }

        print("=== host app finished ===")
        fflush(stdout)
        fflush(stderr)
    }

    // MARK: - go2rtc fallback

    static func runGo2RTC(host: String) async throws {
        let base = URL(fileURLWithPath: "/Volumes/HOME 1TB EXT/Documents/Chamber")
        let configURL = base.appendingPathComponent("captures/go2rtc-app.yaml")
        let frameURL = base.appendingPathComponent("captures/go2rtc-frame.jpg")

        let config = """
        api:
          listen: "127.0.0.1:1984"
          origin: "*"
        log:
          level: info
        ffmpeg:
          bin: /opt/homebrew/bin/ffmpeg
        streams:
          k2: webrtc:http://\(host):8000/call/webrtc_local#format=creality
          k2jpeg: ffmpeg:k2#video=jpeg
        """
        try config.write(to: configURL, atomically: true, encoding: .utf8)

        guard let executable = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("go2rtc") else {
            print("go2rtc binary not found")
            return
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["-config", configURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        print("starting go2rtc: \(executable.path)")
        try process.run()

        // Wait for the API to come up and for go2rtc to negotiate the camera.
        try await Task.sleep(nanoseconds: 8_000_000_000)

        let session = URLSession(configuration: .ephemeral)

        do {
            let (streams, response) = try await session.data(
                from: URL(string: "http://127.0.0.1:1984/api/streams")!
            )
            print("go2rtc streams HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            print(String(decoding: streams, as: UTF8.self).prefix(1000))
        } catch {
            print("go2rtc streams error: \(error)")
        }

        do {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:1984/api/frame.jpeg?src=k2jpeg")!)
            request.timeoutInterval = 30
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("go2rtc frame HTTP \(status), \(data.count) bytes")
            if data.count > 2, data.starts(with: [0xFF, 0xD8]) {
                try data.write(to: frameURL)
                print("saved \(frameURL.path)")
            }
        } catch {
            print("go2rtc frame error: \(error)")
        }

        do {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:1984/api/stream.m3u8?src=k2")!)
            request.timeoutInterval = 10
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("go2rtc HLS HTTP \(status), \(data.count) bytes")
            print(String(decoding: data.prefix(1200), as: UTF8.self))
        } catch {
            print("go2rtc HLS error: \(error)")
        }

        // MJPEG path: go2rtc transcodes H264 to JPEG with ffmpeg.
        let stats = MJPEGStats()
        let live = MJPEGClient(
            onFrame: { jpeg in
                stats.recordFrame(jpeg)
                if stats.frameCount == 1 {
                    try? jpeg.write(to: base.appendingPathComponent("captures/go2rtc-mjpeg-frame.jpg"))
                }
            },
            onError: { error in print("go2rtc live error: \(error)") },
            onResponse: { response in
                print("go2rtc live HTTP \(response.statusCode) \(response.value(forHTTPHeaderField: "Content-Type") ?? "")")
            }
        )
        if let url = URL(string: "http://127.0.0.1:1984/api/stream.mjpeg?src=k2jpeg") {
            print("go2rtc MJPEG stream for 8s…")
            live.start(url: url, timeout: 20)
            try await Task.sleep(nanoseconds: 8_000_000_000)
            live.stop()
            let value = stats.snapshot()
            print(String(
                format: "go2rtc MJPEG: %d frames, %.1f fps, %.1f KB",
                value.frames,
                value.fps,
                Double(value.bytes) / 1024
            ))
        }

        // AVPlayer/HLS path: no ffmpeg needed, H264 is native.
        if let hls = URL(string: "http://127.0.0.1:1984/api/stream.m3u8?src=k2") {
            print("AVPlayer HLS test…")
            let player = AVPlayer(url: hls)
            guard let item = player.currentItem else {
                print("AVPlayer: no item")
                process.terminate()
                return
            }

            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
            item.add(output)

            player.play()
            var frames = 0
            var firstFrameAt: Date?
            var lastPixelBuffer: CVPixelBuffer?

            for _ in 0..<100 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                let time = item.currentTime()
                if output.hasNewPixelBuffer(forItemTime: time),
                   let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                    frames += 1
                    if firstFrameAt == nil { firstFrameAt = Date() }
                    lastPixelBuffer = buffer
                }
            }

            print("AVPlayer status=\(item.status.rawValue) error=\(String(describing: item.error))")
            print("AVPlayer size=\(item.presentationSize.width)x\(item.presentationSize.height) frames=\(frames) current=\(item.currentTime().seconds)")
            print("AVPlayer firstFrame=\(firstFrameAt.map { "\($0.timeIntervalSinceNow * -1)s" } ?? "none")")

            if let buffer = lastPixelBuffer {
                let image = CIImage(cvPixelBuffer: buffer)
                if let jpeg = CIContext().jpegRepresentation(
                    of: image,
                    colorSpace: CGColorSpaceCreateDeviceRGB(),
                    options: [:]
                ) {
                    let url = base.appendingPathComponent("captures/go2rtc-hls-frame.jpg")
                    try? jpeg.write(to: url)
                    print("saved \(url.path)")
                }
            }

            player.pause()
        }

        process.terminate()
        process.waitUntilExit()

        if let data = try? pipe.fileHandleForReading.readDataToEndOfFile(),
           !data.isEmpty {
            print("--- go2rtc log ---")
            print(String(decoding: data, as: UTF8.self))
            print("--- end go2rtc log ---")
        }
    }

    // MARK: - control

    static func runControl(_ options: Options) async throws {
        guard options.positional.count >= 2 else {
            throw CLIError.missingAction
        }

        let host = options.positional[0]
        let action = options.positional[1].lowercased()
        let value = options.positional.count > 2 ? options.positional[2] : nil
        let wsPort = UInt16(options.int("ws-port") ?? 9999)

        if action == "stop" && !options.flag("yes") {
            print("Refusing to stop a print without --yes.")
            print("This is irreversible from the printer's perspective.")
            return
        }

        let command = try controlCommand(action: action, value: value)
        let client = WebSocketClient()
        try await client.connect(host: host, port: wsPort, timeout: 6)
        try await client.send(text: command)
        print("sent: \(command)")

        let consumer = Task {
            var snapshot = PrinterSnapshot()
            for await event in client.events {
                if case .text(let text) = event,
                   !text.contains("heart_beat"),
                   text != "ok",
                   let frame = try? JSONValue.decode(text) {
                    snapshot.merge(frame)
                    print("state: \(snapshot.oneLineSummary)")
                }
            }
        }

        try await Task.sleep(nanoseconds: 2_000_000_000)
        client.close()
        consumer.cancel()
    }

    static func controlCommand(action: String, value: String?) throws -> String {
        var params: [String: Any] = [:]

        switch action {
        case "pause":
            params["pause"] = 1
        case "resume":
            params["pause"] = 0
        case "stop":
            params["stop"] = 1
        case "light-on":
            params["lightSw"] = 1
        case "light-off":
            params["lightSw"] = 0
        case "home":
            params["autohome"] = "X Y"
        case "nozzle":
            params["nozzleTempControl"] = try requiredInt(value, name: "nozzle temperature")
        case "bed":
            params["bedTempControl"] = [
                "num": 0,
                "val": try requiredInt(value, name: "bed temperature")
            ]
        case "chamber":
            params["boxTempControl"] = try requiredInt(value, name: "chamber temperature")
        case "fan":
            let percent = try requiredInt(value, name: "fan percent")
            let speed = max(0, min(255, percent * 255 / 100))
            params["gcodeCmd"] = "M106 P0 S\(speed)"
        case "speed":
            let percent = try requiredInt(value, name: "speed percent")
            params["setFeedratePct"] = percent
            params["setFlowratePct"] = percent
        default:
            throw CLIError.unknownAction(action)
        }

        let object: [String: Any] = ["method": "set", "params": params]
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CLIError.invalidCommand
        }
        return text
    }

    static func requiredInt(_ value: String?, name: String) throws -> Int {
        guard let value, let number = Int(value) else {
            throw CLIError.missingValue(name)
        }
        return number
    }

    // MARK: - webrtc

    static func runWebRTC(_ options: Options) async throws {
        guard let host = options.positional.first else {
            throw CLIError.missingHost
        }

        let seconds = options.int("seconds") ?? 30
        let port = UInt16(options.int("webrtc-port") ?? 8000)
        let output = options.value("out") ?? defaultWebRTCPath(host: host)

        let camera = WebRTCCamera(log: { line in
            print("  \(line)")
        })

        do {
            try await camera.start(host: host, port: port)
        } catch {
            print("WebRTC start failed: \(error)")
            camera.stop()
            return
        }

        print("Signalling complete; waiting for video…")
        let gotFrame = await camera.waitForFirstFrame(timeout: 12)

        if gotFrame {
            let stats = camera.stats
            print(String(
                format: "First frame: %dx%d after %.0f ms",
                stats.width,
                stats.height,
                (stats.firstFrameAt?.timeIntervalSinceNow ?? 0) * -1000
            ))
            if let jpeg = stats.firstFrameJPEG {
                try write(data: jpeg, to: output)
                print("Saved first frame to \(output)")
            }
        } else {
            print("No video frame after 12s (signalling may still have succeeded)")
            print("--- inbound stats ---")
            print(await camera.statisticsSummary())
            print("--- end stats ---")
        }

        let ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let stats = camera.stats
                print(String(
                    format: "  frames %d  %.1f fps  %dx%d  RTP/wall %.2fx  ICE %@",
                    stats.frames,
                    stats.fps,
                    stats.width,
                    stats.height,
                    stats.averageTimestampRatio,
                    stats.iceState as NSString
                ))
            }
        }

        try await Task.sleep(nanoseconds: UInt64(max(1, seconds)) * 1_000_000_000)
        ticker.cancel()

        let final = camera.stats
        print(String(
            format: "Done: %d frames, %.1f fps, RTP/wall %.2fx",
            final.frames,
            final.fps,
            final.averageTimestampRatio
        ))
        camera.stop()
    }

    // MARK: - Helpers

    static func defaultWebRTCPath(host: String) -> String {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("captures")
            .appendingPathComponent("webrtc-\(host.replacingOccurrences(of: ".", with: "-")).jpg")
            .path
    }

    static func printHTTP(_ label: String, result: HTTPProbe) {
        if let status = result.status {
            let type = result.contentType ?? "unknown type"
            print("  \(label)  HTTP \(status)  \(type)  \(result.byteCount) B  \(milliseconds(result.elapsed))")
        } else {
            print("  \(label)  unreachable  \(result.error ?? "")")
        }
    }

    static func milliseconds(_ interval: TimeInterval) -> String {
        String(format: "%.0f ms", interval * 1000)
    }

    static func defaultSnapshotPath(host: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "snapshot-\(host.replacingOccurrences(of: ".", with: "-"))-\(formatter.string(from: Date())).jpg"
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("captures")
            .appendingPathComponent(name)
            .path
    }

    static func write(data: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    static func printUsage() {
        print("""
        chamber-spike — Phase 0 harness for Creality printers

        Usage:
          chamber-spike discover [--seconds <n>]     Find printers with Bonjour
          chamber-spike probe <host>                 Check ports, WebSocket handshake, model
          chamber-spike watch <host> [options]       Stream telemetry and print a summary
          chamber-spike snapshot <host> [options]    Save a camera snapshot (JPEG)
          chamber-spike mjpeg <host> [options]       Stream MJPEG and measure frame rate
          chamber-spike webrtc <host> [options]      Negotiate the K2 WebRTC camera
          chamber-spike hostapp [--host <ip>] [--mode all|probe|watch|webrtc]
                                [--seconds <n>] [--log <path>] [--record <path>]
                                                     Run the Phase 0 sequence from an app bundle
          chamber-spike control <host> <action> [value] [--yes]
                                                     Send a safe control command
             actions: pause, resume, stop, light-on, light-off, home,
                      nozzle <°C>, bed <°C>, chamber <°C>, fan <0-100>, speed <0-100>

        Options:
          --seconds <n>     Duration for watch/mjpeg (default: 60 / 30)
          --record <path>   Write raw telemetry frames as JSONL (watch)
          --verbose         Print heartbeats and unparsed frames
          --ws-port <n>     Printer WebSocket port (default: 9999)
          --camera-port <n> Camera port for probe (default: 8080)
          --webrtc-port <n> WebRTC port for probe (default: 8000)
          --fluidd-port <n> Fluidd port for probe (default: 4408)
          --port <n>        Camera port (snapshot/mjpeg, default: 8080)
          --path <path>     Camera path (default: snapshot or stream)
          --save <dir>      Save every 15th MJPEG frame as JPEG
          --out <path>      Snapshot output path
        """)
    }
}

// MARK: - Options

struct Options {
    private var values: [String: String] = [:]
    private var flags: Set<String> = []
    private(set) var positional: [String] = []

    init(_ arguments: [String]) {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--") {
                let name = String(argument.dropFirst(2))
                if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                    values[name] = arguments[index + 1]
                    index += 2
                } else {
                    flags.insert(name)
                    index += 1
                }
            } else {
                positional.append(argument)
                index += 1
            }
        }
    }

    func value(_ name: String) -> String? { values[name] }
    func int(_ name: String) -> Int? { values[name].flatMap(Int.init) }
    func flag(_ name: String) -> Bool { flags.contains(name) }
}

// MARK: - Recording

final class JSONLRecorder {
    private let handle: FileHandle

    init(path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        self.handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    func write(_ line: String) {
        try? handle.write(contentsOf: Data(line.utf8))
    }

    func close() {
        try? handle.close()
    }
}

// MARK: - MJPEG stats

final class MJPEGStats: @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0
    private var bytes = 0
    private let started = Date()

    func recordFrame(_ data: Data) {
        lock.lock()
        frames += 1
        bytes += data.count
        lock.unlock()
    }

    var frameCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }

    func snapshot() -> (frames: Int, bytes: Int, fps: Double) {
        lock.lock()
        defer { lock.unlock() }
        let elapsed = Date().timeIntervalSince(started)
        return (frames, bytes, elapsed > 0 ? Double(frames) / elapsed : 0)
    }
}

enum CLIError: Error, CustomStringConvertible {
    case missingHost
    case missingAction
    case missingValue(String)
    case unknownAction(String)
    case invalidURL
    case invalidCommand

    var description: String {
        switch self {
        case .missingHost:
            return "Missing printer host (example: 192.168.1.50)"
        case .missingAction:
            return "Missing control action (example: control <host> pause)"
        case .missingValue(let name):
            return "Missing or invalid value: \(name)"
        case .unknownAction(let action):
            return "Unknown control action: \(action)"
        case .invalidURL:
            return "Invalid URL"
        case .invalidCommand:
            return "Could not encode the control command"
        }
    }
}

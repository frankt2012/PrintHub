import Combine
import PrintHubKit
import Foundation

enum ConnectionState: Equatable {
    case idle
    case connecting
    case live
    case offline(String)

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .connecting: return "Connecting"
        case .live: return "Live"
        case .offline: return "Offline"
        }
    }

    var isLive: Bool {
        if case .live = self { return true }
        return false
    }
}

enum CameraState: Equatable {
    case idle
    case starting
    case live
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "Camera idle"
        case .starting: return "Starting camera"
        case .live: return "Live"
        case .failed: return "Camera unavailable"
        }
    }
}

@MainActor
final class PrinterSession: ObservableObject, Identifiable {
    let id = UUID()
    let config: PrinterConfig

    @Published private(set) var snapshot = PrinterSnapshot()
    @Published private(set) var connection: ConnectionState = .idle
    @Published private(set) var camera: CameraState = .idle
    @Published private(set) var cameraURL: URL?
    @Published private(set) var cfs: CFSState?

    private let go2rtc: Go2RTCSupervisor
    private var client: WebSocketClient?
    private var consumeTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var cfsTask: Task<Void, Never>?
    private var lastNotifiedState: PrinterState = .unknown
    private var started = false

    init(config: PrinterConfig, go2rtc: Go2RTCSupervisor) {
        self.config = config
        self.go2rtc = go2rtc
    }

    var name: String { config.name }
    var host: String { config.host }
    var stateLabel: String { snapshot.derivedState.label.capitalized }
    var firmware: String? { snapshot.firmwareVersion }

    func start() {
        guard !started else { return }
        started = true
        connection = .connecting
        camera = .starting

        Task { await connect() }
        Task { await startCamera() }
        startCFSPolling()
    }

    func stop() {
        started = false
        consumeTask?.cancel()
        pollTask?.cancel()
        retryTask?.cancel()
        cfsTask?.cancel()
        consumeTask = nil
        pollTask = nil
        retryTask = nil
        cfsTask = nil
        client?.close()
        client = nil
        cameraURL = nil
        connection = .idle
        camera = .idle
        go2rtc.stop()
    }

    func reconnect() {
        stop()
        snapshot = PrinterSnapshot()
        start()
    }

    func refresh() {
        sendRaw(#"{"method":"get","params":{"ReqPrinterPara":1}}"#)
        sendRaw(#"{"method":"get","params":{"reqPrintObjects":1}}"#)
        Task { await refreshCFS() }
    }

    var cameraSnapshotURL: URL? {
        go2rtc.snapshotURL
    }

    func refreshCFS() async {
        guard let state = try? await MoonrakerClient(host: config.host).fetchCFS() else {
            return
        }
        cfs = state
    }

    func togglePause() {
        let shouldResume = snapshot.derivedState == .paused
        send(["pause": shouldResume ? 0 : 1])
    }

    func stopPrint() {
        send(["stop": 1])
    }

    func toggleLight() {
        send(["lightSw": snapshot.lightOn == true ? 0 : 1])
    }

    var canHome: Bool {
        connection.isLive && !snapshot.isPrinting
    }

    func home(axis: HomeAxis) {
        guard canHome else { return }

        Task { [weak self] in
            guard let self else { return }
            if await self.runMoonrakerScript("G28 \(axis.rawValue)") {
                return
            }
            // K1-family fallback. The K2 path above is the reliable one for
            // individual axes; Creality's `autohome` field only understands
            // the combined XY and Z forms.
            self.send(["autohome": axis.rawValue])
        }
    }

    func homeAll() {
        guard canHome else { return }

        Task { [weak self] in
            guard let self else { return }
            if await self.runMoonrakerScript("G28") {
                return
            }

            // Fallback for printers without Moonraker.
            self.send(["autohome": "X Y"])
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard self.canHome else { return }
            self.send(["autohome": "Z"])
        }
    }

    private func runMoonrakerScript(_ script: String) async -> Bool {
        var components = URLComponents()
        components.scheme = "http"
        components.host = config.host
        components.port = 4408
        components.path = "/printer/gcode/script"
        components.queryItems = [URLQueryItem(name: "script", value: script)]

        guard let url = components.url else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return false
            }
            return true
        } catch {
            return false
        }
    }

    func setNozzleTarget(_ value: Int) {
        let maximum = snapshot.maxNozzleTemp ?? 350
        send(["nozzleTempControl": min(max(value, 0), maximum)])
    }

    func setBedTarget(_ value: Int) {
        let maximum = snapshot.maxBedTemp ?? 120
        send(["bedTempControl": ["num": 0, "val": min(max(value, 0), maximum)]])
    }

    func setChamberTarget(_ value: Int) {
        let maximum = snapshot.maxChamberTemp ?? 60
        send(["boxTempControl": min(max(value, 0), maximum)])
    }

    // MARK: - Connection

    private func connect() async {
        let client = WebSocketClient()
        self.client = client

        do {
            try await client.connect(host: config.host, port: 9999, timeout: 8)
            guard !Task.isCancelled else {
                client.close()
                return
            }

            connection = .live
            startPolling(client)
            startConsuming(client)
        } catch {
            connection = .offline(String(describing: error))
            scheduleRetry()
        }
    }

    private func startConsuming(_ client: WebSocketClient) {
        consumeTask = Task { [weak self] in
            for await event in client.events {
                if Task.isCancelled { return }
                guard let self else { return }

                switch event {
                case .text(let text):
                    if text == "ok" { continue }
                    if text.contains("heart_beat") {
                        try? await client.send(text: "ok")
                        continue
                    }
                    if let frame = try? JSONValue.decode(text) {
                        self.snapshot.merge(frame)
                        self.handleStateNotification()
                    }

                case .failed(let reason):
                    self.connection = .offline(reason)
                    return

                case .closed:
                    if self.connection.isLive {
                        self.connection = .offline("The printer closed the connection.")
                    }
                    return

                default:
                    break
                }
            }
        }
    }

    private func startPolling(_ client: WebSocketClient) {
        pollTask = Task { [weak self] in
            var tick = 0

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                guard self != nil else { return }

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
    }

    private func handleStateNotification() {
        let state = snapshot.derivedState
        let previous = lastNotifiedState
        lastNotifiedState = state

        guard previous != .unknown else { return }

        let file = snapshot.fileName ?? "the current job"

        switch state {
        case .complete where previous == .printing || previous == .processing || previous == .paused:
            NotificationManager.post(
                title: "\(name) finished printing",
                body: "\(file) completed."
            )
        case .error where previous != .error:
            let code = snapshot.errorCode.map { "Error \($0)." } ?? "The printer reported an error."
            NotificationManager.post(
                title: "\(name) reported an error",
                body: "\(code) \(file)"
            )
        case .paused where previous == .printing || previous == .processing:
            NotificationManager.post(
                title: "\(name) paused",
                body: "\(file) is paused."
            )
        default:
            break
        }
    }

    private func startCFSPolling() {
        cfsTask?.cancel()
        cfsTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshCFS()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    // MARK: - Camera

    private func startCamera() async {
        do {
            let url = try await go2rtc.start(host: config.host)
            guard !Task.isCancelled else { return }

            cameraURL = url
            camera = .starting

            // If the WebRTC page never reports a video frame, surface a useful
            // error instead of showing "starting" forever.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self, self.camera != .live else { return }
                self.camera = .failed("The camera did not produce a video frame.")
                self.scheduleRetry()
            }
        } catch {
            camera = .failed(error.localizedDescription)
            scheduleRetry()
        }
    }

    func cameraDidLoad() {
        camera = .live
    }

    func cameraDidFail(_ reason: String) {
        camera = .failed(reason)
        scheduleRetry()
    }

    private func scheduleRetry() {
        guard retryTask == nil, started else { return }

        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil

            guard !self.connection.isLive || self.camera != .live else { return }
            self.reconnect()
        }
    }

    // MARK: - Commands

    private func send(_ params: [String: Any]) {
        guard let client else { return }
        let object: [String: Any] = ["method": "set", "params": params]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        Task {
            try? await client.send(text: text)
        }
    }

    private func sendRaw(_ text: String) {
        guard let client else { return }
        Task {
            try? await client.send(text: text)
        }
    }
}


enum HomeAxis: String {
    case x = "X"
    case y = "Y"
    case z = "Z"
}

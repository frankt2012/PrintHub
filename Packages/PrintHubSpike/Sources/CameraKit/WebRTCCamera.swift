import Foundation
import AVFoundation
import CoreImage
import WebRTC

/// Native WebRTC client for the Creality K2 camera.
///
/// Signalling is the printer's `POST /call/webrtc_local` exchange: base64 JSON
/// offer in, base64 JSON answer out. The camera is receive-only.
public final class WebRTCCamera: NSObject, @unchecked Sendable {
    public typealias LogHandler = @Sendable (String) -> Void

    public struct Stats: Sendable {
        public var frames: Int = 0
        public var firstFrameAt: Date?
        public var lastFrameAt: Date?
        public var lastRTPTimestampNs: Int64 = 0
        public var averageTimestampRatio: Double = 0
        public var width: Int = 0
        public var height: Int = 0
        public var connectionState: String = "new"
        public var iceState: String = "new"
        public var peerConnectionState: String = "new"
        public var firstFrameJPEG: Data?

        public var fps: Double {
            guard let firstFrameAt, let lastFrameAt, frames > 1 else { return 0 }
            let elapsed = lastFrameAt.timeIntervalSince(firstFrameAt)
            return elapsed > 0 ? Double(frames - 1) / elapsed : 0
        }
    }

    private let log: LogHandler?
    private let lock = NSLock()

    private var factory: RTCPeerConnectionFactory?
    private var peerConnection: RTCPeerConnection?
    private var renderer: FrameCaptureRenderer?
    private var logger: RTCCallbackLogger?
    private var started = false
    private var lastConnectionState: RTCIceConnectionState = .new
    private var lastIceGatheringState: RTCIceGatheringState = .new
    private var attachedTrackIDs = Set<String>()

    public init(log: LogHandler? = nil) {
        self.log = log
        super.init()
    }

    deinit {
        stop()
    }

    // MARK: - Public API

    public var stats: Stats {
        var value = renderer?.snapshot() ?? Stats()
        value.connectionState = iceStateDescription(lastConnectionState)
        value.iceState = gatheringStateDescription(lastIceGatheringState)
        value.peerConnectionState = peerConnection.map { String(describing: $0.connectionState) } ?? "none"
        return value
    }

    private func iceStateDescription(_ state: RTCIceConnectionState) -> String {
        switch state {
        case .new: return "new"
        case .checking: return "checking"
        case .connected: return "connected"
        case .completed: return "completed"
        case .failed: return "failed"
        case .disconnected: return "disconnected"
        case .closed: return "closed"
        case .count: return "count"
        @unknown default: return "unknown"
        }
    }

    private func gatheringStateDescription(_ state: RTCIceGatheringState) -> String {
        switch state {
        case .new: return "new"
        case .gathering: return "gathering"
        case .complete: return "complete"
        @unknown default: return "unknown"
        }
    }

    /// Runs the offer/answer exchange. Returns once the answer has been applied;
    /// video may arrive later.
    public func start(host: String, port: UInt16 = 8000) async throws {
        RTCInitializeSSL()

        // Surface DTLS/ICE failures from the native stack. Warnings are enough
        // for the handshake investigation and keep the log readable.
        if let log {
            let logger = RTCCallbackLogger()
            logger.severity = .info
            logger.start { message in
                log("webrtc: \(message)")
            }
            self.logger = logger
        }

        let encoder = RTCDefaultVideoEncoderFactory()
        let decoder = RTCDefaultVideoDecoderFactory()
        let factory = RTCPeerConnectionFactory(encoderFactory: encoder, decoderFactory: decoder)
        self.factory = factory

        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.iceServers = []
        configuration.continualGatheringPolicy = .gatherOnce
        // The printer advertises TCP candidates but does not appear to send
        // media over them; prefer UDP-only like Chrome does.
        configuration.tcpCandidatePolicy = .disabled

        // Do not also set OfferToReceiveVideo: the recvonly transceiver below
        // already creates the single video m-line the printer expects.
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )

        guard let peerConnection = factory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: self
        ) else {
            throw WebRTCError.factoryFailed
        }
        self.peerConnection = peerConnection

        // Receive-only video transceiver.
        let transceiverInit = RTCRtpTransceiverInit()
        transceiverInit.direction = .recvOnly
        _ = peerConnection.addTransceiver(of: .video, init: transceiverInit)

        let renderer = FrameCaptureRenderer()
        self.renderer = renderer

        log?("creating offer")
        let offer = try await peerConnection.offerAsync(constraints)
        log?("offer created (\(offer.sdp.count) bytes), gathering candidates")
        log?("--- offer SDP ---\n\(offer.sdp)\n--- end offer ---")
        try await peerConnection.setLocalDescriptionAsync(offer)

        // The printer accepts a single SDP blob; wait for host candidates to be
        // embedded before posting it.
        try await Task.sleep(nanoseconds: 1_500_000_000)

        log?("posting offer to http://\(host):\(port)/call/webrtc_local")
        let answer = try await negotiate(host: host, port: port, offerSDP: offer.sdp)
        log?("answer received (\(answer.sdp.count) bytes)")
        log?("--- answer SDP ---\n\(answer.sdp)\n--- end answer ---")
        try await peerConnection.setRemoteDescriptionAsync(answer)
        started = true

        attachAvailableVideoTrack()

        // Give the transceiver a moment to expose the receiver track.
        try? await Task.sleep(nanoseconds: 300_000_000)
        attachAvailableVideoTrack()
    }

    public func stop() {
        logger?.stop()
        logger = nil
        peerConnection?.close()
        peerConnection = nil
        renderer = nil
        factory = nil
        started = false
        RTCCleanupSSL()
    }

    public func waitForFirstFrame(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if stats.frames > 0 { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    // MARK: - Signalling

    private func negotiate(
        host: String,
        port: UInt16,
        offerSDP: String
    ) async throws -> RTCSessionDescription {
        guard let url = URL(string: "http://\(host):\(port)/call/webrtc_local") else {
            throw WebRTCError.invalidURL
        }

        let payload: [String: String] = ["type": "offer", "sdp": offerSDP]
        let json = try JSONSerialization.data(withJSONObject: payload)
        let body = json.base64EncodedString()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("plain/text", forHTTPHeaderField: "Content-Type")
        request.setValue("http://\(host):\(port)", forHTTPHeaderField: "Origin")
        request.setValue("http://\(host):\(port)/", forHTTPHeaderField: "Referer")
        request.setValue("PrintHubSpike/0.1", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WebRTCError.badResponse("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WebRTCError.badResponse("HTTP \(http.statusCode)")
        }

        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Typical response: base64(JSON({type, sdp})).
        if let decoded = Data(base64Encoded: text),
           let object = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any],
           let sdp = object["sdp"] as? String {
            let type = (object["type"] as? String) == "offer" ? RTCSdpType.offer : .answer
            return RTCSessionDescription(type: type, sdp: sdp)
        }

        // Some firmware returns base64 of the raw SDP.
        if let decoded = Data(base64Encoded: text),
           let sdp = String(data: decoded, encoding: .utf8),
           sdp.contains("v=0") {
            return RTCSessionDescription(type: .answer, sdp: sdp)
        }

        // Last resort: raw SDP.
        if text.contains("v=0") {
            return RTCSessionDescription(type: .answer, sdp: text)
        }

        throw WebRTCError.badResponse("Unrecognized answer (\(data.count) bytes)")
    }

    // MARK: - Track attachment

    private func attachAvailableVideoTrack() {
        guard let peerConnection else { return }

        if let track = peerConnection.transceivers
            .first(where: { $0.mediaType == .video })?
            .receiver.track as? RTCVideoTrack {
            attach(track)
        }
    }

    private func attach(_ track: RTCVideoTrack) {
        guard let renderer else { return }
        let id = track.trackId
        guard !attachedTrackIDs.contains(id) else { return }
        attachedTrackIDs.insert(id)
        track.isEnabled = true
        track.add(renderer)
        log?("attached video track \(id) enabled=\(track.isEnabled) state=\(track.readyState.rawValue)")
    }

    private func value(_ statistic: RTCStatistics, _ key: String) -> String {
        guard let value = statistic.values[key] else { return "?" }
        return "\(value)"
    }

    /// Human-readable inbound media stats. Useful when signalling succeeds but
    /// no frames reach the renderer.
    public func statisticsSummary() async -> String {
        guard let peerConnection else { return "no peer connection" }

        let report = await withCheckedContinuation { (continuation: CheckedContinuation<RTCStatisticsReport?, Never>) in
            peerConnection.statistics { continuation.resume(returning: $0) }
        }

        guard let report else { return "no statistics" }

        var lines: [String] = []
        for (_, statistic) in report.statistics {
            switch statistic.type {
            case "inbound-rtp":
                let kind = value(statistic, "kind")
                let received = value(statistic, "packetsReceived")
                let bytes = value(statistic, "bytesReceived")
                let frames = value(statistic, "framesReceived")
                let decoded = value(statistic, "framesDecoded")
                let width = value(statistic, "frameWidth")
                let height = value(statistic, "frameHeight")
                lines.append("inbound-rtp \(kind) packets=\(received) bytes=\(bytes) frames=\(frames) decoded=\(decoded) \(width)x\(height)")

            case "candidate-pair":
                let state = value(statistic, "state")
                let nominated = value(statistic, "nominated")
                let bytes = value(statistic, "bytesReceived")
                let local = value(statistic, "localCandidateId")
                let remote = value(statistic, "remoteCandidateId")
                lines.append("candidate-pair state=\(state) nominated=\(nominated) bytes=\(bytes) local=\(local) remote=\(remote)")

            case "transport":
                let selected = value(statistic, "selectedCandidatePairId")
                let bytes = value(statistic, "bytesReceived")
                let dtls = value(statistic, "dtlsState")
                let ice = value(statistic, "iceState")
                lines.append("transport selected=\(selected) bytes=\(bytes) dtls=\(dtls) ice=\(ice)")

            case "local-candidate", "remote-candidate":
                let type = value(statistic, "candidateType")
                let proto = value(statistic, "protocol")
                let address = value(statistic, "address")
                let port = value(statistic, "port")
                lines.append("\(statistic.type) \(type) \(proto) \(address):\(port)")

            default:
                break
            }
        }

        return lines.isEmpty ? "no inbound stats" : lines.joined(separator: "\n")
    }
}

// MARK: - Peer connection delegate

extension WebRTCCamera: RTCPeerConnectionDelegate {
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        log?("signalling state: \(stateChanged.rawValue)")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        log?("stream added (\(stream.videoTracks.count) video tracks)")
        if let track = stream.videoTracks.first {
            attach(track)
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        log?("stream removed")
    }

    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        log?("negotiation needed")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        lastConnectionState = newState
        log?("ICE connection: \(iceLogName(newState))")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        lastIceGatheringState = newState
        log?("ICE gathering: \(gatherLogName(newState))")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        log?("candidate: \(candidate.sdp)")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        log?("removed \(candidates.count) candidates")
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        log?("data channel opened")
    }

    public func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd receiver: RTCRtpReceiver,
        streams: [RTCMediaStream]
    ) {
        log?("receiver added: \(receiver.track?.kind ?? "unknown")")
        if let track = receiver.track as? RTCVideoTrack {
            attach(track)
        }
    }

    private func iceLogName(_ state: RTCIceConnectionState) -> String {
        switch state {
        case .new: return "new"
        case .checking: return "checking"
        case .connected: return "connected"
        case .completed: return "completed"
        case .failed: return "failed"
        case .disconnected: return "disconnected"
        case .closed: return "closed"
        case .count: return "count"
        @unknown default: return "unknown"
        }
    }

    private func gatherLogName(_ state: RTCIceGatheringState) -> String {
        switch state {
        case .new: return "new"
        case .gathering: return "gathering"
        case .complete: return "complete"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Frame renderer

/// Counts decoded frames, measures RTP-vs-wall-clock drift, and keeps the
/// first JPEG for inspection. It deliberately does not display anything.
final class FrameCaptureRenderer: NSObject, RTCVideoRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private let ciContext = CIContext()
    private var frames = 0
    private var firstFrameAt: Date?
    private var lastFrameAt: Date?
    private var lastRTPTimestampNs: Int64 = 0
    private var ratioSum: Double = 0
    private var ratioCount: Int = 0
    private var width = 0
    private var height = 0
    private var firstJPEG: Data?

    func setSize(_ size: CGSize) {
        lock.lock()
        width = Int(size.width.rounded())
        height = Int(size.height.rounded())
        lock.unlock()
    }

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }

        let now = Date()
        lock.lock()
        frames += 1
        if firstFrameAt == nil {
            firstFrameAt = now
            if let pixelBuffer = (frame.buffer as? RTCCVPixelBuffer)?.pixelBuffer {
                let image = CIImage(cvPixelBuffer: pixelBuffer)
                firstJPEG = ciContext.jpegRepresentation(
                    of: image,
                    colorSpace: CGColorSpaceCreateDeviceRGB(),
                    options: [:]
                )
            }
        }

        if let lastFrameAt {
            let wallNs = now.timeIntervalSince(lastFrameAt) * 1_000_000_000
            let rtpNs = Double(frame.timeStampNs - lastRTPTimestampNs)
            if wallNs > 0, lastRTPTimestampNs != 0 {
                ratioSum += (rtpNs / wallNs)
                ratioCount += 1
            }
        }

        lastFrameAt = now
        lastRTPTimestampNs = frame.timeStampNs
        lock.unlock()
    }

    func snapshot() -> WebRTCCamera.Stats {
        lock.lock()
        defer { lock.unlock() }

        var stats = WebRTCCamera.Stats()
        stats.frames = frames
        stats.firstFrameAt = firstFrameAt
        stats.lastFrameAt = lastFrameAt
        stats.lastRTPTimestampNs = lastRTPTimestampNs
        stats.averageTimestampRatio = ratioCount > 0 ? ratioSum / Double(ratioCount) : 0
        stats.width = width
        stats.height = height
        stats.firstFrameJPEG = firstJPEG
        return stats
    }
}

// MARK: - Async wrappers

private extension RTCPeerConnection {
    func offerAsync(_ constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { continuation in
            offer(for: constraints) { description, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let description {
                    continuation.resume(returning: description)
                } else {
                    continuation.resume(throwing: WebRTCError.noOffer)
                }
            }
        }
    }

    func setLocalDescriptionAsync(_ description: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            setLocalDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func setRemoteDescriptionAsync(_ description: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            setRemoteDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

public enum WebRTCError: Error, CustomStringConvertible {
    case factoryFailed
    case noOffer
    case invalidURL
    case badResponse(String)

    public var description: String {
        switch self {
        case .factoryFailed:
            return "Could not create the WebRTC peer connection factory"
        case .noOffer:
            return "WebRTC did not produce an offer"
        case .invalidURL:
            return "Invalid printer URL"
        case .badResponse(let detail):
            return "WebRTC signalling failed: \(detail)"
        }
    }
}

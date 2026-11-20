import SwiftUI
import PrintHubKit

struct PrinterDetailView: View {
    @ObservedObject var session: PrinterSession
    @Binding var showInspector: Bool
    @State private var showStopConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    CameraStageView(session: session)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if case .offline(let reason) = session.connection {
                        connectionBanner(reason)
                    }

                    StatusStripView(snapshot: session.snapshot)

                    ActionRowView(
                        session: session,
                        showStopConfirmation: $showStopConfirmation
                    )
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }

            if showInspector {
                Divider()

                InspectorView(session: session)
                    .frame(width: 310)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Stop this print?", isPresented: $showStopConfirmation) {
            Button("Stop", role: .destructive) {
                session.stopPrint()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The print head will stop and the job cannot be resumed from the printer.")
        }
    }

    private func connectionBanner(_ reason: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Printer offline")
                    .font(.system(.body, weight: .semibold))
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Reconnect") {
                session.reconnect()
            }
        }
        .padding(12)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct CameraStageView: View {
    @ObservedObject var session: PrinterSession

    var body: some View {
        ZStack {
            Color.black

            if let url = session.cameraURL {
                CameraWebView(
                    url: url,
                    onReady: { session.cameraDidLoad() },
                    onFailure: { session.cameraDidFail($0) }
                )
                .transition(.opacity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.35))
                    Text(session.camera.label)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            overlay
        }
        .background(Color.black)
        .overlay(alignment: .center) {
            if session.camera == .starting {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Starting camera…")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var overlay: some View {
        VStack {
            HStack(alignment: .top) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(cameraColor)
                        .frame(width: 7, height: 7)
                    Text(session.name)
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(session.camera.label)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.45), in: Capsule())

                Spacer()

                if session.camera == .live {
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.red.opacity(0.85), in: Capsule())
                }
            }

            Spacer()

            if case .failed(let reason) = session.camera {
                VStack(spacing: 6) {
                    Text("Camera unavailable")
                        .font(.system(.callout, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                    Button("Retry") {
                        session.reconnect()
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
                .padding(14)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
    }

    private var cameraColor: Color {
        switch session.camera {
        case .live: return .green
        case .starting: return .orange
        case .failed: return .red
        case .idle: return .gray
        }
    }
}

struct StatusStripView: View {
    let snapshot: PrinterSnapshot

    var body: some View {
        HStack(spacing: 0) {
            MetricView(
                title: "NOZZLE",
                value: temperature(snapshot.nozzleTemp, target: snapshot.nozzleTarget)
            )
            divider
            MetricView(
                title: "BED",
                value: temperature(snapshot.bedTemp, target: snapshot.bedTarget)
            )
            divider
            MetricView(
                title: "CHAMBER",
                value: temperature(snapshot.chamberTemp, target: snapshot.chamberTarget)
            )
            divider
            MetricView(
                title: "LAYER",
                value: layerText
            )
            divider
            MetricView(
                title: "TIME LEFT",
                value: snapshot.leftTime.map(PrinterSnapshot.formatDuration) ?? "—"
            )
            divider
            MetricView(
                title: "PROGRESS",
                value: snapshot.progress.map { "\(Int($0))%" } ?? "—"
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 28)
    }

    private var layerText: String {
        guard let layer = snapshot.layer else { return "—" }
        if let total = snapshot.totalLayers, total > 0 {
            return "\(layer) / \(total)"
        }
        return "\(layer)"
    }

    private func temperature(_ value: Int?, target: Int?) -> String {
        guard let value else { return "—" }
        if let target, target > 0 {
            return "\(value)° / \(target)°"
        }
        return "\(value)°"
    }
}

struct MetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }
}

struct ActionRowView: View {
    @ObservedObject var session: PrinterSession
    @Binding var showStopConfirmation: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button {
                session.togglePause()
            } label: {
                Label(
                    session.snapshot.derivedState == .paused ? "Resume" : "Pause",
                    systemImage: session.snapshot.derivedState == .paused ? "play.fill" : "pause.fill"
                )
                .frame(minWidth: 74)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(session.snapshot.derivedState == .paused ? .teal : .accentColor)

            Button {
                showStopConfirmation = true
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.red)
            .disabled(!session.snapshot.isPrinting)

            Button {
                session.toggleLight()
            } label: {
                Label(
                    session.snapshot.lightOn == true ? "Light On" : "Light Off",
                    systemImage: session.snapshot.lightOn == true ? "lightbulb.fill" : "lightbulb"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Menu {
                Button("Home X") { session.home(axis: .x) }
                Button("Home Y") { session.home(axis: .y) }
                Button("Home Z") { session.home(axis: .z) }
                Divider()
                Button("Home All") { session.homeAll() }
            } label: {
                Label("Home", systemImage: "house")
            }
            .menuStyle(.button)
            .controlSize(.large)
            .disabled(!session.canHome)
            .help("Home X, Y, Z, or all axes")

            Spacer()

            if case .offline = session.connection {
                Button {
                    session.reconnect()
                } label: {
                    Label("Reconnect", systemImage: "bolt.horizontal")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }
}

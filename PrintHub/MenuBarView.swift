import AppKit
import PrintHubKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: PrintHubModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let session = model.selectedSession {
            MenuBarPrinterView(model: model, session: session)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("No printer selected")
                    .font(.system(.body, weight: .semibold))
                Button("Open PrintHub") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .padding(14)
            .frame(width: 300)
        }
    }
}

/// The menu bar content observes the selected session directly. Without this
/// nested view, the popover only refreshed when the printer list changed.
private struct MenuBarPrinterView: View {
    @ObservedObject var model: PrintHubModel
    @ObservedObject var session: PrinterSession
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CameraThumbnailView(url: session.cameraSnapshotURL)
            header
            metrics
            actions
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.system(.body, weight: .semibold))
                Text(session.stateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let progress = session.snapshot.progress, session.snapshot.isPrinting {
                Text("\(Int(progress))%")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .monospacedDigit()
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: 0) {
            metric("NOZZLE", temperature(session.snapshot.nozzleTemp))
            metric("BED", temperature(session.snapshot.bedTemp))
            metric("CHAMBER", temperature(session.snapshot.chamberTemp))
            metric("LEFT", session.snapshot.leftTime.map(PrinterSnapshot.formatDuration) ?? "—")
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    session.togglePause()
                } label: {
                    Label(
                        session.snapshot.derivedState == .paused ? "Resume" : "Pause",
                        systemImage: session.snapshot.derivedState == .paused ? "play.fill" : "pause.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Open") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            HStack {
                if model.printers.count > 1 {
                    Picker("Printer", selection: $model.selectedID) {
                        ForEach(model.printers) { printer in
                            Text(printer.name).tag(Optional(printer.id))
                        }
                    }
                    .labelsHidden()
                }

                Spacer()

                Button {
                    session.toggleLight()
                } label: {
                    Image(systemName: session.snapshot.lightOn == true ? "lightbulb.fill" : "lightbulb")
                }
                .help("Toggle light")

                Button {
                    session.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func temperature(_ value: Int?) -> String {
        value.map { "\($0)°" } ?? "—"
    }

    private var statusColor: Color {
        guard session.connection.isLive else { return .red }
        switch session.snapshot.derivedState {
        case .printing, .processing: return .teal
        case .paused: return .orange
        case .error: return .red
        case .complete: return .blue
        default: return .gray
        }
    }
}

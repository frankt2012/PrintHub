import SwiftUI
import PrintHubKit

struct InspectorView: View {
    @ObservedObject var session: PrinterSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                jobSection
                temperaturesSection
                machineSection
                cfsSection
            }
            .padding(16)
        }
        .background(.regularMaterial)
    }

    private var jobSection: some View {
        InspectorSection(title: "JOB") {
            VStack(alignment: .leading, spacing: 8) {
                Text(session.snapshot.fileName ?? "No active job")
                    .font(.system(.body, weight: .semibold))
                    .lineLimit(2)

                if let progress = session.snapshot.progress, session.snapshot.isPrinting {
                    ProgressView(value: progress, total: 100)
                        .progressViewStyle(.linear)
                        .tint(.teal)
                }

                HStack {
                    Text(stateText)
                    Spacer()
                    Text(session.snapshot.progress.map { "\(Int($0))%" } ?? "—")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider().padding(.vertical, 2)

                InfoRow("Time left", session.snapshot.leftTime.map(PrinterSnapshot.formatDuration) ?? "—")
                InfoRow("Elapsed", session.snapshot.elapsedTime.map(PrinterSnapshot.formatDuration) ?? "—")
                InfoRow("Layer", layerText)
            }
        }
    }

    private var temperaturesSection: some View {
        InspectorSection(title: "TEMPERATURES") {
            VStack(spacing: 10) {
                InfoRow("Nozzle", temperature(session.snapshot.nozzleTemp, target: session.snapshot.nozzleTarget))
                InfoRow("Bed", temperature(session.snapshot.bedTemp, target: session.snapshot.bedTarget))
                InfoRow("Chamber", temperature(session.snapshot.chamberTemp, target: session.snapshot.chamberTarget))

                Divider().padding(.vertical, 2)

                TemperatureControlRow(
                    title: "Nozzle",
                    actual: session.snapshot.nozzleTemp,
                    target: session.snapshot.nozzleTarget,
                    maximum: session.snapshot.maxNozzleTemp ?? 350
                ) { session.setNozzleTarget($0) }

                TemperatureControlRow(
                    title: "Bed",
                    actual: session.snapshot.bedTemp,
                    target: session.snapshot.bedTarget,
                    maximum: session.snapshot.maxBedTemp ?? 120
                ) { session.setBedTarget($0) }

                if let maximum = session.snapshot.maxChamberTemp {
                    TemperatureControlRow(
                        title: "Chamber",
                        actual: session.snapshot.chamberTemp,
                        target: session.snapshot.chamberTarget,
                        maximum: maximum
                    ) { session.setChamberTarget($0) }
                }
            }
        }
    }

    private var machineSection: some View {
        InspectorSection(title: "MACHINE") {
            VStack(spacing: 7) {
                InfoRow("Model", session.snapshot.friendlyModel ?? session.config.name)
                InfoRow("Firmware", session.firmware ?? "—")
                InfoRow("Address", session.host)
                InfoRow("Connection", session.connection.label)
                InfoRow("Camera", session.camera.label)
            }
        }
    }

    private var cfsSection: some View {
        InspectorSection(title: "FILAMENT") {
            VStack(spacing: 9) {
                CFSPanel(
                    cfs: session.cfs,
                    connectedFromTelemetry: session.snapshot.cfsConnected == true
                ) {
                    Task {
                        await session.refreshCFS()
                    }
                }

                if let status = session.snapshot.materialStatus {
                    InfoRow("Material status", status == 0 ? "OK" : "Check filament")
                }
            }
        }
    }

    private var stateText: String {
        switch session.connection {
        case .live:
            return session.snapshot.derivedState.label.capitalized
        case .connecting:
            return "Connecting…"
        case .offline:
            return "Offline"
        case .idle:
            return "Idle"
        }
    }

    private var layerText: String {
        guard let layer = session.snapshot.layer else { return "—" }
        if let total = session.snapshot.totalLayers, total > 0 {
            return "\(layer) of \(total)"
        }
        return "\(layer)"
    }

    private func temperature(_ actual: Int?, target: Int?) -> String {
        guard let actual else { return "—" }
        if let target, target > 0 {
            return "\(actual)° / \(target)°"
        }
        return "\(actual)°"
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.9)
                .foregroundStyle(.secondary)

            content
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
        }
    }
}


struct TemperatureControlRow: View {
    let title: String
    let actual: Int?
    let target: Int?
    let maximum: Int
    let onSet: (Int) -> Void

    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(display)
                    .font(.caption)
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                TextField("°C", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 58)
                    .focused($focused)
                    .onSubmit(apply)

                Button("Set", action: apply)
                    .controlSize(.small)
                    .disabled(parsedValue == nil)

                Button("Off") {
                    input = "0"
                    onSet(0)
                }
                .controlSize(.small)
            }
        }
        .onAppear(perform: sync)
        .onChange(of: target) { _, _ in
            if !focused { sync() }
        }
    }

    private var display: String {
        guard let actual else { return "—" }
        if let target, target > 0 {
            return "\(actual)° / \(target)°"
        }
        return "\(actual)°"
    }

    private var parsedValue: Int? {
        guard let value = Int(input.trimmingCharacters(in: .whitespaces)) else { return nil }
        return min(max(value, 0), maximum)
    }

    private func apply() {
        guard let value = parsedValue else { return }
        onSet(value)
        focused = false
    }

    private func sync() {
        input = target.map(String.init) ?? ""
    }
}

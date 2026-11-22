import PrintHubKit
import SwiftUI

struct CFSPanel: View {
    let cfs: CFSState?
    let connectedFromTelemetry: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InfoRow("CFS", connected ? "Connected" : "Not detected")

            if let cfs {
                if cfs.units.isEmpty {
                    Text("No CFS units reported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cfs.units) { unit in
                        CFSUnitView(unit: unit)
                    }
                }
            } else if connectedFromTelemetry {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading CFS slots…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh", action: onRefresh)
                        .controlSize(.small)
                }
            } else {
                Text("Connect a CFS to see slots and material.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var connected: Bool {
        cfs?.connected == true || connectedFromTelemetry
    }
}

private struct CFSUnitView: View {
    let unit: CFSUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(unit.label)
                    .font(.caption.weight(.semibold))
                Spacer()
                if let temperature = unit.temperature {
                    Text("\(temperature)°")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let humidity = unit.humidity {
                    Text("RH \(humidity)%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ],
                spacing: 6
            ) {
                ForEach(unit.slots) { slot in
                    CFSSlotView(slot: slot)
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CFSSlotView: View {
    let slot: CFSSlot

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(swatch)
                .frame(width: 18, height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.white.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(slot.id)
                    .font(.system(size: 10, weight: .semibold))
                Text(slot.isPresent ? slot.displayName : "Empty")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .help(slot.isPresent ? slot.displayName : "Empty slot")
                if slot.isPresent, let remaining = slot.remainingValue {
                    Text("Left \(remaining)")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
    }

    private var swatch: Color {
        guard slot.isPresent, let hex = slot.colorHex else {
            return Color.gray.opacity(0.25)
        }
        return Color(hex: hex) ?? .gray
    }
}

private extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let number = UInt64(value, radix: 16) else {
            return nil
        }
        self.init(
            .sRGB,
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255,
            opacity: 1
        )
    }
}

import Foundation

/// Brand and product names for each CFS slot.
///
/// Moonraker's `box` object only carries numeric material codes and colour
/// values. The printer's own filament definition, including the brand and
/// product name shown on its screen and in Creality Print, is served over the
/// printer WebSocket (`get boxsInfo`). This is a read-only lookup.
public struct CFSSlotDetails: Equatable, Sendable {
    public let slotID: String
    public let brand: String?
    public let productName: String?
    public let material: String?
    public let colorHex: String?

    public init(
        slotID: String,
        brand: String?,
        productName: String?,
        material: String?,
        colorHex: String?
    ) {
        self.slotID = slotID
        self.brand = brand
        self.productName = productName
        self.material = material
        self.colorHex = colorHex
    }
}

public struct CFSDetails: Equatable, Sendable {
    public let slots: [String: CFSSlotDetails]

    public init(slots: [String: CFSSlotDetails]) {
        self.slots = slots
    }

    /// Parse a `boxsInfo` frame. Frames without `materialBoxs` are not a
    /// usable read and return nil.
    public static func parse(_ message: JSONValue) -> CFSDetails? {
        let root = message["boxsInfo"] ?? message
        guard let boxes = root["materialBoxs"]?.arrayValue else {
            return nil
        }

        var slots: [String: CFSSlotDetails] = [:]

        for box in boxes {
            // Type 0 is a CFS unit; type 1 is the side spool holder.
            guard box["type"]?.intValue == 0,
                  let unit = box["id"]?.intValue,
                  (1...4).contains(unit) else {
                continue
            }

            for material in box["materials"]?.arrayValue ?? [] {
                guard let index = material["id"]?.intValue,
                      (0..<4).contains(index) else {
                    continue
                }

                let slotID = "T\(unit)\(["A", "B", "C", "D"][index])"
                let color = CFSState.normalizedColor(material["color"]?.stringValue)
                let brand = clean(material["vendor"]?.stringValue)
                let productName = clean(material["name"]?.stringValue)
                let type = clean(material["type"]?.stringValue)

                // Keep a slot when the printer reported any identity at all.
                guard brand != nil || productName != nil || type != nil || color != nil else {
                    continue
                }

                slots[slotID] = CFSSlotDetails(
                    slotID: slotID,
                    brand: brand,
                    productName: productName,
                    material: type,
                    colorHex: color
                )
            }
        }

        return CFSDetails(slots: slots)
    }

    private static func clean(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        switch value.lowercased() {
        case "-1", "none", "unknown", "null":
            return nil
        default:
            return value
        }
    }
}

/// One-shot reader for the printer's `boxsInfo` filament definitions.
public enum CFSPrinterReader {
    public static func fetch(
        host: String,
        port: UInt16 = 9999,
        timeout: TimeInterval = 6
    ) async throws -> CFSDetails {
        let client = WebSocketClient()
        try await client.connect(host: host, port: port, timeout: min(timeout, 5))
        defer { client.close() }

        try await client.send(text: #"{"method":"get","params":{"boxsInfo":1}}"#)

        return try await withThrowingTaskGroup(of: CFSDetails.self) { group in
            group.addTask {
                for await event in client.events {
                    switch event {
                    case .text(let text):
                        if text.contains("heart_beat") {
                            try? await client.send(text: "ok")
                            continue
                        }
                        guard text.contains("\"boxsInfo\""),
                              let message = try? JSONValue.decode(text),
                              let details = CFSDetails.parse(message) else {
                            continue
                        }
                        return details

                    case .failed(let message):
                        throw CFSPrinterError.connection(message)

                    case .closed:
                        throw CFSPrinterError.connection("closed before boxsInfo")

                    case .ready, .binary:
                        continue
                    }
                }

                throw CFSPrinterError.connection("closed before boxsInfo")
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw CFSPrinterError.timeout
            }

            defer { group.cancelAll() }

            guard let details = try await group.next() else {
                throw CFSPrinterError.timeout
            }
            return details
        }
    }
}

public enum CFSPrinterError: Error, CustomStringConvertible {
    case connection(String)
    case timeout

    public var description: String {
        switch self {
        case .connection(let reason): return "CFS detail read failed: \(reason)"
        case .timeout: return "CFS detail read timed out"
        }
    }
}

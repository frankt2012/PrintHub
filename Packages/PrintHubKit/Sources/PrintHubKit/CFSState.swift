import Foundation

public struct CFSSlot: Identifiable, Equatable, Sendable {
    public let id: String
    public let material: String?
    public let colorHex: String?
    public let remaining: String?
    public let isPresent: Bool
    /// Brand and product name come from the printer's own filament definition
    /// on port 9999. Moonraker only reports material codes, so both are nil
    /// when that read is unavailable.
    public let brand: String?
    public let productName: String?

    public init(
        id: String,
        material: String?,
        colorHex: String?,
        remaining: String?,
        isPresent: Bool,
        brand: String? = nil,
        productName: String? = nil
    ) {
        self.id = id
        self.material = material
        self.colorHex = colorHex
        self.remaining = remaining
        self.isPresent = isPresent
        self.brand = brand
        self.productName = productName
    }

    /// Remaining length as reported by the CFS, or nil when the printer uses
    /// 0 or -1 to mean "not reported". The printer does not document the unit.
    public var remainingValue: Int? {
        guard let remaining,
              let value = Int(remaining),
              value > 0 else {
            return nil
        }
        return value
    }

    /// The closest equivalent to the slicer's filament label. "Generic" is a
    /// printer classification, not a brand, so a product name such as
    /// "Kingroon PLA" is shown on its own.
    public var displayName: String {
        let name = productName ?? material
        guard let brand, !brand.isEmpty,
              brand.caseInsensitiveCompare("Generic") != .orderedSame else {
            return name ?? "Material"
        }
        guard let name, !name.isEmpty else {
            return brand
        }
        if name.range(of: brand, options: .caseInsensitive) != nil {
            return name
        }
        return "\(brand) \(name)"
    }
}

public struct CFSUnit: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let state: String?
    public let temperature: Int?
    public let humidity: Int?
    public let slots: [CFSSlot]
}

public struct CFSState: Equatable, Sendable {
    public let connected: Bool
    public let filamentUseUp: Bool
    public let units: [CFSUnit]

    public init(connected: Bool, filamentUseUp: Bool, units: [CFSUnit]) {
        self.connected = connected
        self.filamentUseUp = filamentUseUp
        self.units = units
    }

    public static func parse(_ box: JSONValue) -> CFSState {
        let fields = box.objectValue ?? [:]
        let state = fields["state"]?.stringValue?.lowercased()
        let connected = state == "connect" || (fields["filament"]?.intValue ?? 0) > 0
        let filamentUseUp = fields["filament_useup"]?.boolValue == true

        // Creality maps loaded material/color to CFS slot names in same_material.
        var descriptions: [String: (material: String, color: String?)] = [:]
        for item in fields["same_material"]?.arrayValue ?? [] {
            guard let values = item.arrayValue,
                  values.count >= 4,
                  let material = values[3].stringValue else {
                continue
            }

            let color = values[1].stringValue
            for slot in values[2].arrayValue ?? [] {
                guard let name = slot.stringValue else { continue }
                descriptions[name] = (material, color)
            }
        }

        var units: [CFSUnit] = []

        for unitIndex in 1...4 {
            guard let unit = fields["T\(unitIndex)"]?.objectValue else { continue }

            let unitState = unit["state"]?.stringValue
            if unitState == nil || unitState?.lowercased() == "none" {
                continue
            }

            let colors = unit["color_value"]?.arrayValue ?? []
            let materials = unit["material_type"]?.arrayValue ?? []
            let remain = unit["remain_len"]?.arrayValue ?? []

            var slots: [CFSSlot] = []
            for (index, letter) in ["A", "B", "C", "D"].enumerated() {
                let id = "T\(unitIndex)\(letter)"
                let description = descriptions[id]
                let material = description?.material ?? materialName(materials[safe: index]?.stringValue)
                let color = normalizedColor(description?.color ?? colors[safe: index]?.stringValue)
                let remaining = remain[safe: index]?.stringValue
                let present = material != nil || color != nil

                slots.append(CFSSlot(
                    id: id,
                    material: present ? material : nil,
                    colorHex: present ? color : nil,
                    remaining: present ? remaining : nil,
                    isPresent: present
                ))
            }

            units.append(CFSUnit(
                id: "T\(unitIndex)",
                label: "CFS \(unitIndex)",
                state: unitState,
                temperature: unit["temperature"]?.intValue,
                humidity: unit["dry_and_humidity"]?.intValue,
                slots: slots
            ))
        }

        return CFSState(connected: connected, filamentUseUp: filamentUseUp, units: units)
    }

    /// Merge brand and product names read from the printer's `boxsInfo`.
    /// A color mismatch means the slot changed since that read, so only the
    /// Moonraker data is used rather than showing a stale brand.
    public func applying(_ details: CFSDetails?) -> CFSState {
        guard let details else { return self }

        let mergedUnits = units.map { unit in
            CFSUnit(
                id: unit.id,
                label: unit.label,
                state: unit.state,
                temperature: unit.temperature,
                humidity: unit.humidity,
                slots: unit.slots.map { slot in
                    guard let detail = details.slots[slot.id],
                          detail.colorHex == nil
                            || slot.colorHex == nil
                            || detail.colorHex == slot.colorHex else {
                        return slot
                    }
                    return CFSSlot(
                        id: slot.id,
                        material: slot.material,
                        colorHex: slot.colorHex,
                        remaining: slot.remaining,
                        isPresent: slot.isPresent,
                        brand: detail.brand,
                        productName: detail.productName
                    )
                }
            )
        }

        return CFSState(
            connected: connected,
            filamentUseUp: filamentUseUp,
            units: mergedUnits
        )
    }

    static func normalizedColor(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value != "-1" else {
            return nil
        }

        value = value.replacingOccurrences(of: "#", with: "")
        if value.count == 7 {
            value = String(value.suffix(6))
        }
        guard value.count == 6,
              value.allSatisfy({ $0.isHexDigit }) else {
            return nil
        }
        return "#\(value.uppercased())"
    }

    private static func materialName(_ id: String?) -> String? {
        guard let id, id != "-1" else { return nil }
        switch id {
        case "000001": return "PLA"
        case "000002": return "PETG"
        case "000003": return "ABS"
        case "000004": return "TPU"
        default: return "Material \(id)"
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

public struct MoonrakerClient: Sendable {
    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16 = 4408) {
        self.host = host
        self.port = port
    }

    public func fetchCFS() async throws -> CFSState {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        components.path = "/printer/objects/query"
        components.queryItems = [URLQueryItem(name: "box", value: nil)]

        guard let url = components.url else {
            throw MoonrakerError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw MoonrakerError.badResponse
        }

        let root = try JSONValue.decode(data)
        guard let box = root["result"]?["status"]?["box"] else {
            throw MoonrakerError.missingBox
        }
        return CFSState.parse(box)
    }
}

public enum MoonrakerError: Error, CustomStringConvertible {
    case invalidURL
    case badResponse
    case missingBox

    public var description: String {
        switch self {
        case .invalidURL: return "Invalid Moonraker URL"
        case .badResponse: return "Moonraker returned an error"
        case .missingBox: return "Moonraker did not return CFS data"
        }
    }
}

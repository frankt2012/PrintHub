import Foundation

public enum PrinterState: String, Sendable {
    case idle
    case printing
    case paused
    case processing
    case complete
    case error
    case selfTesting
    case stopped
    case unknown

    public var label: String {
        switch self {
        case .idle: return "idle"
        case .printing: return "printing"
        case .paused: return "paused"
        case .processing: return "processing"
        case .complete: return "complete"
        case .error: return "error"
        case .selfTesting: return "self-test"
        case .stopped: return "stopped"
        case .unknown: return "unknown"
        }
    }
}

/// Normalized view over the printer's cumulative telemetry object.
public struct PrinterSnapshot: Sendable {
    public private(set) var raw: JSONValue = .object([:])

    public init() {}

    public mutating func merge(_ frame: JSONValue) {
        raw = raw.merged(with: frame)
    }

    public subscript(key: String) -> JSONValue? {
        raw[key]
    }

    // MARK: - Identity

    public var currentPosition: String? { nonEmptyString("curPosition") }
    public var model: String? { nonEmptyString("model") }
    public var modelVersion: String? { nonEmptyString("modelVersion") }
    public var hostname: String? { nonEmptyString("hostname") }

    /// Creality reports a board code in `model`; map the known ones to names.
    public var friendlyModel: String? {
        guard let model else { return nil }
        switch model.uppercased() {
        case "F008": return "K2 Plus"
        case "F012": return "K2 Pro"
        case "F021": return "K2"
        case "F018": return "Creality Hi"
        case "F001", "F002", "F005": return "Ender-3 V3"
        default: return model
        }
    }

    // MARK: - Job

    public var stateCode: Int? { raw["state"]?.intValue }

    public var fileName: String? {
        guard let value = nonEmptyString("printFileName") else { return nil }
        // Some firmware reports a full path.
        return (value as NSString).lastPathComponent
    }

    public var rawFileName: String? { nonEmptyString("printFileName") }

    public var progress: Double? {
        if let value = raw["printProgress"]?.doubleValue {
            return min(max(value, 0), 100)
        }
        if let value = raw["dProgress"]?.doubleValue {
            return min(max(value, 0), 100)
        }
        return nil
    }

    public var leftTime: Double? {
        raw["printLeftTime"]?.doubleValue ?? raw["printTimeLeft"]?.doubleValue
    }

    public var elapsedTime: Double? {
        raw["printJobTime"]?.doubleValue
    }

    public var layer: Int? { raw["layer"]?.intValue }
    public var totalLayers: Int? { raw["TotalLayer"]?.intValue }

    // MARK: - Temperatures

    public var nozzleTemp: Int? { temperature("nozzleTemp") }
    public var bedTemp: Int? { temperature("bedTemp0") }
    public var chamberTemp: Int? { temperature("boxTemp") }

    public var nozzleTarget: Int? {
        temperature("targetNozzleTemp")
            ?? temperature("nozzleTargetTemp")
            ?? temperature("nozzleTempTarget")
    }

    public var bedTarget: Int? {
        temperature("targetBedTemp")
            ?? temperature("bedTargetTemp")
            ?? temperature("targetBedTemp0")
            ?? temperature("bedTemp0Target")
    }

    public var chamberTarget: Int? { temperature("targetBoxTemp") }

    public var maxNozzleTemp: Int? { temperature("maxNozzleTemp") }
    public var maxBedTemp: Int? { temperature("maxBedTemp") }
    public var maxChamberTemp: Int? { temperature("maxBoxTemp") }

    /// Extracts the firmware version from Creality's packed `modelVersion`
    /// string, e.g. `...;DWIN sw ver:1.1.8.0;`.
    public var firmwareVersion: String? {
        guard let raw = modelVersion else { return nil }
        for part in raw.split(separator: ";").reversed() {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let range = trimmed.range(of: "sw ver:") else { continue }
            let value = trimmed[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    // MARK: - Hardware

    public var lightOn: Bool? { raw["lightSw"]?.boolValue }
    public var cfsConnected: Bool? { raw["cfsConnect"]?.boolValue }
    public var webrtcSupported: Bool? { raw["webrtcSupport"]?.boolValue }
    public var materialStatus: Int? { raw["materialStatus"]?.intValue }
    public var deviceState: Int? { raw["deviceState"]?.intValue }

    public var errorCode: Int? {
        if let err = raw["err"] {
            if let object = err.objectValue {
                return object["errcode"]?.intValue ?? object["errCode"]?.intValue
            }
            return err.intValue
        }
        return nil
    }

    public var hasError: Bool { (errorCode ?? 0) != 0 }

    public var cfsInfo: JSONValue? { raw["boxsInfo"] }

    // MARK: - Derived state

    public var derivedState: PrinterState {
        if let test = raw["withSelfTest"]?.intValue, (1...99).contains(test) {
            return .selfTesting
        }
        if hasError {
            return .error
        }

        let pausedFlag = raw["pause"]?.boolValue == true
            || raw["paused"]?.boolValue == true
            || raw["isPaused"]?.boolValue == true

        if stateCode == 5 || pausedFlag {
            return .paused
        }

        switch stateCode {
        case 1:
            return .printing
        case 2:
            return .complete
        case 4:
            return .stopped
        case 0, 7, 9:
            if fileName != nil { return .processing }
        default:
            break
        }

        if fileName != nil, let progress, progress >= 100 {
            return .complete
        }

        if fileName != nil {
            return .idle
        }

        return stateCode == nil ? .unknown : .idle
    }

    public var isPrinting: Bool {
        let state = derivedState
        return state == .printing || state == .paused || state == .processing
    }

    // MARK: - Display

    public var oneLineSummary: String {
        var parts: [String] = ["[\(derivedState.label)]"]

        if let progress {
            parts.append(String(format: "%.1f%%", progress))
        }
        if let fileName {
            parts.append(fileName)
        }
        if let leftTime {
            parts.append("\(Self.formatDuration(leftTime)) left")
        }
        if let nozzleTemp {
            parts.append("nozzle \(temperatureText(nozzleTemp, target: nozzleTarget))")
        }
        if let bedTemp {
            parts.append("bed \(temperatureText(bedTemp, target: bedTarget))")
        }
        if let chamberTemp {
            parts.append("chamber \(temperatureText(chamberTemp, target: chamberTarget))")
        }
        if let layer, let totalLayers, totalLayers > 0 {
            parts.append("layer \(layer)/\(totalLayers)")
        }
        if hasError, let errorCode {
            parts.append("error \(errorCode)")
        }
        return parts.joined(separator: " · ")
    }

    public static func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }

    // MARK: - Helpers

    private func nonEmptyString(_ key: String) -> String? {
        guard let value = raw[key]?.stringValue else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func temperature(_ key: String) -> Int? {
        guard let value = raw[key]?.doubleValue, value.isFinite else { return nil }
        return Int(value.rounded())
    }

    private func temperatureText(_ value: Int, target: Int?) -> String {
        guard let target, target > 0 else { return "\(value)°" }
        return "\(value)/\(target)°"
    }
}

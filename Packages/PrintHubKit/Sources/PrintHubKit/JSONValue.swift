import CoreFoundation
import Foundation

/// A tolerant JSON tree for printer telemetry.
///
/// The printer sends loosely typed values (numbers as strings, empty strings,
/// nested objects) and adds keys over time. A dedicated value type keeps the
/// merging and coercion rules in one place.
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(any: Any) throws {
        switch any {
        case is NSNull:
            self = .null

        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }

        case let string as String:
            self = .string(string)

        case let array as [Any]:
            self = .array(try array.map { try JSONValue(any: $0) })

        case let object as [String: Any]:
            self = .object(try object.mapValues { try JSONValue(any: $0) })

        default:
            throw JSONValueError.unsupportedType(String(describing: type(of: any)))
        }
    }

    public static func decode(_ data: Data) throws -> JSONValue {
        let any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try JSONValue(any: any)
    }

    public static func decode(_ string: String) throws -> JSONValue {
        guard let data = string.data(using: .utf8) else {
            throw JSONValueError.notUTF8
        }
        return try decode(data)
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let value):
            // The printer frequently sends numbers as strings.
            return Double(value.trimmingCharacters(in: .whitespaces))
        case .bool(let value):
            return value ? 1 : 0
        default:
            return nil
        }
    }

    public var intValue: Int? {
        guard let value = doubleValue, value.isFinite else { return nil }
        return Int(value)
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .number(let value):
            return value != 0
        case .string(let value):
            switch value.lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    /// Deep-merge objects; any non-object replaces the previous value.
    ///
    /// The printer's state is cumulative, but `boxsInfo` and `err` are nested.
    /// Deep merging preserves slot data when a frame only updates one slot.
    public func merged(with other: JSONValue) -> JSONValue {
        guard case .object(let left) = self, case .object(let right) = other else {
            return other
        }

        var result = left
        for (key, value) in right {
            if let existing = result[key] {
                result[key] = existing.merged(with: value)
            } else {
                result[key] = value
            }
        }
        return .object(result)
    }
}

public enum JSONValueError: Error, CustomStringConvertible {
    case unsupportedType(String)
    case notUTF8

    public var description: String {
        switch self {
        case .unsupportedType(let type):
            return "Unsupported JSON value type: \(type)"
        case .notUTF8:
            return "JSON string is not valid UTF-8"
        }
    }
}

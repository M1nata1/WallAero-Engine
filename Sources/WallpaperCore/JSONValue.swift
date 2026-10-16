import CoreFoundation
import Foundation

/// A value of a JSON file, kept as it was read so that what the app does not know of it is
/// written back as it came. Wallpaper Engine's files are edited this way: a scene, its models,
/// materials and particles.
public enum JSONValue: Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: - Reading and writing

    /// What `JSONSerialization` makes of a file, as a value.
    public init(any: Any?) {
        switch any {
        case let number as NSNumber:
            // In JSON read this way a true is a number too, of a type of its own.
            self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.doubleValue)
        case let text as String:
            self = .string(text)
        case let array as [Any]:
            self = .array(array.map { JSONValue(any: $0) })
        case let dictionary as [String: Any]:
            self = .object(dictionary.mapValues { JSONValue(any: $0) })
        default:
            self = .null
        }
    }

    public init?(data: Data) {
        guard let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        self.init(any: any)
    }

    /// The value as `JSONSerialization` takes it.
    public var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let flag): return flag
        case .number(let number):
            // A whole number is written without a fraction, as Wallpaper Engine writes one.
            if number == number.rounded(), abs(number) < 1e15 {
                return Int64(number)
            }
            return number
        case .string(let text): return text
        case .array(let array): return array.map(\.any)
        case .object(let dictionary): return dictionary.mapValues(\.any)
        }
    }

    /// The value as a file: readable, with its keys in order, so that a change shows as one.
    public func data(readable: Bool = true) -> Data {
        var options: JSONSerialization.WritingOptions = [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]
        if readable {
            options.insert(.prettyPrinted)
        }
        return (try? JSONSerialization.data(withJSONObject: any, options: options)) ?? Data("null".utf8)
    }

    public var text: String {
        String(decoding: data(readable: false), as: UTF8.self)
    }

    // MARK: - Looking inside

    public subscript(key: String) -> JSONValue? {
        get {
            guard case .object(let dictionary) = self else { return nil }
            return dictionary[key]
        }
        set {
            guard case .object(var dictionary) = self else {
                if let newValue { self = .object([key: newValue]) }
                return
            }
            dictionary[key] = newValue
            self = .object(dictionary)
        }
    }

    public subscript(index: Int) -> JSONValue? {
        guard case .array(let array) = self, array.indices.contains(index) else { return nil }
        return array[index]
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let dictionary) = self { return dictionary }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let array) = self { return array }
        return nil
    }

    public var stringValue: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    public var numberValue: Double? {
        switch self {
        case .number(let number): return number
        case .bool(let flag): return flag ? 1 : 0
        case .string(let text): return Double(text.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let flag): return flag
        case .number(let number): return number != 0
        default: return nil
        }
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    // MARK: - Values a scene may tie to something

    /// A value of a scene may stand behind a setting of the wallpaper, a script or an
    /// animation; it is then a dictionary with the value itself under "value". This is that
    /// value, or the value itself.
    public var plain: JSONValue {
        if case .object(let dictionary) = self, let value = dictionary["value"] {
            return value
        }
        return self
    }

    /// The value with its plain value replaced, whatever it stands behind kept.
    public func replacingPlain(with value: JSONValue) -> JSONValue {
        if case .object(var dictionary) = self, dictionary["value"] != nil {
            dictionary["value"] = value
            return .object(dictionary)
        }
        return value
    }

    /// Numbers Wallpaper Engine writes in one text, "1.00000 0.50000 0.00000": a place, a
    /// size, a color.
    public var vector: [Double]? {
        switch plain {
        case .string(let text):
            let parts = text.split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
            return parts.isEmpty ? nil : parts
        case .number(let number):
            return [number]
        default:
            return nil
        }
    }

    /// Numbers as Wallpaper Engine writes them in one text.
    public static func vector(_ numbers: [Double]) -> JSONValue {
        .string(numbers.map { String(format: "%.5f", $0) }.joined(separator: " "))
    }
}

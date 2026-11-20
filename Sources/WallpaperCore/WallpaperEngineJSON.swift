import Foundation

/// A JSON file of a Wallpaper Engine scene read as it is written: its keys in their order, its
/// strings and numbers as they stand in the file, so that what is not changed is written back
/// byte for byte. Files are written by many versions of many programs; a comma before a closing
/// bracket, which some leave, is passed over (docs/we-format.md, row 5).
public indirect enum WallpaperEngineJSON: Equatable, Sendable {
    /// A number, `true`, `false` or `null`, as written.
    case literal(String)
    /// A string as written between its quotes, escapes and all.
    case string(String)
    case array([WallpaperEngineJSON])
    case object([(key: String, value: WallpaperEngineJSON)])

    public static func == (a: Self, b: Self) -> Bool {
        switch (a, b) {
        case (.literal(let x), .literal(let y)), (.string(let x), .string(let y)): return x == y
        case (.array(let x), .array(let y)): return x == y
        case (.object(let x), .object(let y)): return x.count == y.count && zip(x, y).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: return false
        }
    }

    // MARK: - Reading

    public init?(text: String) {
        self.init(data: Data(text.utf8))
    }

    public init?(data: Data) {
        let parsed: WallpaperEngineJSON? = data.withUnsafeBytes { raw in
            var reader = Reader(bytes: raw.bindMemory(to: UInt8.self))
            guard let value = reader.value() else { return nil }
            reader.space()
            return reader.at == reader.bytes.count ? value : nil
        }
        guard let parsed else { return nil }
        self = parsed
    }

    /// One member of an object at the top of `data`, read without reading the others: the
    /// scene's table holds its texts before puppets that may run to hundreds of megabytes.
    static func member(_ name: String, ofObjectIn data: Data) -> WallpaperEngineJSON? {
        data.withUnsafeBytes { raw in
            var reader = Reader(bytes: raw.bindMemory(to: UInt8.self))
            reader.space()
            guard reader.take(UInt8(ascii: "{")) else { return nil }
            while true {
                reader.space()
                guard case .string(let key)? = reader.string() else { return nil }
                reader.space()
                guard reader.take(UInt8(ascii: ":")) else { return nil }
                reader.space()
                if Self.unescaped(key) == name { return reader.value() }
                guard reader.skipValue() else { return nil }
                reader.space()
                guard reader.take(UInt8(ascii: ",")) else { return nil }
            }
        }
    }

    private struct Reader {
        let bytes: UnsafeBufferPointer<UInt8>
        var at = 0

        mutating func space() {
            while at < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[at]) { at += 1 }
        }

        mutating func take(_ byte: UInt8) -> Bool {
            guard at < bytes.count, bytes[at] == byte else { return false }
            at += 1
            return true
        }

        mutating func value() -> WallpaperEngineJSON? {
            space()
            guard at < bytes.count else { return nil }
            switch bytes[at] {
            case UInt8(ascii: "{"): return object()
            case UInt8(ascii: "["): return array()
            case UInt8(ascii: "\""): return string()
            default: return literal()
            }
        }

        mutating func object() -> WallpaperEngineJSON? {
            at += 1
            var members: [(key: String, value: WallpaperEngineJSON)] = []
            while true {
                space()
                if take(UInt8(ascii: "}")) { return .object(members) }
                if !members.isEmpty {
                    guard take(UInt8(ascii: ",")) else { return nil }
                    space()
                    // A comma before the end.
                    if take(UInt8(ascii: "}")) { return .object(members) }
                }
                guard case .string(let key)? = string() else { return nil }
                space()
                guard take(UInt8(ascii: ":")), let value = value() else { return nil }
                members.append((key, value))
            }
        }

        mutating func array() -> WallpaperEngineJSON? {
            at += 1
            var items: [WallpaperEngineJSON] = []
            while true {
                space()
                if take(UInt8(ascii: "]")) { return .array(items) }
                if !items.isEmpty {
                    guard take(UInt8(ascii: ",")) else { return nil }
                    space()
                    if take(UInt8(ascii: "]")) { return .array(items) }
                }
                guard let item = value() else { return nil }
                items.append(item)
            }
        }

        /// The end of the string that starts at `at`, past its closing quote.
        mutating func stringEnd() -> Int? {
            guard at < bytes.count, bytes[at] == UInt8(ascii: "\"") else { return nil }
            var end = at + 1
            while end < bytes.count {
                switch bytes[end] {
                case UInt8(ascii: "\\"): end += 2
                case UInt8(ascii: "\""): return end + 1
                case 0..<0x20: return nil
                default: end += 1
                }
            }
            return nil
        }

        mutating func string() -> WallpaperEngineJSON? {
            guard let end = stringEnd() else { return nil }
            let inside = String(decoding: UnsafeBufferPointer(rebasing: bytes[(at + 1)..<(end - 1)]), as: UTF8.self)
            at = end
            return .string(inside)
        }

        mutating func literal() -> WallpaperEngineJSON? {
            let start = at
            while at < bytes.count, !(bytes[at] == UInt8(ascii: ",") || bytes[at] == UInt8(ascii: "}") || bytes[at] == UInt8(ascii: "]")
                                       || [0x20, 0x0A, 0x0D, 0x09].contains(bytes[at])) {
                at += 1
            }
            let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<at]), as: UTF8.self)
            if text == "true" || text == "false" || text == "null" { return .literal(text) }
            // A number as JSON writes one, and nothing looser: what the player could not read
            // stays unreadable.
            guard text.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
            return .literal(text)
        }

        /// Passes over a value without keeping it.
        mutating func skipValue() -> Bool {
            space()
            var depth = 0
            repeat {
                guard at < bytes.count else { return false }
                switch bytes[at] {
                case UInt8(ascii: "\""):
                    guard let end = stringEnd() else { return false }
                    at = end
                    continue
                case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"): depth -= 1
                case UInt8(ascii: ","), 0x20, 0x0A, 0x0D, 0x09:
                    if depth == 0 { return true }
                default: break
                }
                at += 1
            } while depth > 0
            return true
        }
    }

    // MARK: - Writing

    /// The value as JSON text, without spaces; strings and numbers as they were read.
    public var text: String {
        var out = ""
        write(into: &out)
        return out
    }

    private func write(into out: inout String) {
        switch self {
        case .literal(let text): out += text
        case .string(let inside): out += "\""; out += inside; out += "\""
        case .array(let items):
            out += "["
            for (index, item) in items.enumerated() {
                if index > 0 { out += "," }
                item.write(into: &out)
            }
            out += "]"
        case .object(let members):
            out += "{"
            for (index, member) in members.enumerated() {
                if index > 0 { out += "," }
                out += "\""; out += member.key; out += "\":"
                member.value.write(into: &out)
            }
            out += "}"
        }
    }

    // MARK: - Strings

    /// A string as written, made plain: its escapes undone. One that does not undo is left as written.
    static func unescaped(_ inside: String) -> String {
        guard inside.contains("\\") else { return inside }
        guard let data = "\"\(inside)\"".data(using: .utf8),
              let text = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String
        else { return inside }
        return text
    }

    /// A plain string as it is written in a file.
    static func escaped(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case let c where c.value < 0x20: out += String(format: "\\u%04x", c.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// The text of a string value.
    public var stringValue: String? {
        if case .string(let inside) = self { return Self.unescaped(inside) }
        return nil
    }
}

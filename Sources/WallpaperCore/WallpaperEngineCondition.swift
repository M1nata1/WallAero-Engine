import Foundation

/// When a setting of a wallpaper is shown: a condition on other settings, as Wallpaper Engine
/// writes one, such as `language.value == 2 && !plain.value`. It is an expression of Angular's,
/// so that values compare loosely: "1" equals 1, and true equals 1.
public enum WallpaperEngineCondition {
    public enum Value: Equatable, Sendable {
        case flag(Bool)
        case number(Double)
        case text(String)

        var isTrue: Bool {
            switch self {
            case .flag(let flag): return flag
            case .number(let number): return number != 0
            case .text(let text): return !text.isEmpty
            }
        }

        fileprivate var asNumber: Double? {
            switch self {
            case .flag(let flag): return flag ? 1 : 0
            case .number(let number): return number
            case .text(let text): return Double(text.trimmingCharacters(in: .whitespaces))
            }
        }

        fileprivate var asText: String {
            switch self {
            case .flag(let flag): return flag ? "true" : "false"
            case .number(let number): return String(format: "%g", number)
            case .text(let text): return text
            }
        }
    }

    private enum Token: Equatable {
        case name(String), literal(Value), symbol(String), open, close
    }

    private static func tokens(_ text: String) -> [Token]? {
        var found: [Token] = []
        let characters = Array(text)
        var at = 0
        while at < characters.count {
            let character = characters[at]
            if character.isWhitespace {
                at += 1
            } else if character == "(" {
                found.append(.open)
                at += 1
            } else if character == ")" {
                found.append(.close)
                at += 1
            } else if character == "'" || character == "\"" {
                guard let end = characters[(at + 1)...].firstIndex(of: character) else { return nil }
                found.append(.literal(.text(String(characters[(at + 1)..<end]))))
                at = end + 1
            } else if character.isNumber || (character == "-" && at + 1 < characters.count && characters[at + 1].isNumber) {
                var end = at + 1
                while end < characters.count, characters[end].isNumber || characters[end] == "." { end += 1 }
                guard let number = Double(String(characters[at..<end])) else { return nil }
                found.append(.literal(.number(number)))
                at = end
            } else if character.isLetter || character == "_" || character == "$" {
                var end = at + 1
                while end < characters.count, characters[end].isLetter || characters[end].isNumber || characters[end] == "_" || characters[end] == "." { end += 1 }
                let word = String(characters[at..<end]).replacingOccurrences(of: "$", with: "")
                switch word {
                case "true": found.append(.literal(.flag(true)))
                case "false": found.append(.literal(.flag(false)))
                default: found.append(.name(word))
                }
                at = end
            } else {
                let symbols = ["===", "!==", "==", "!=", "<=", ">=", "&&", "||", "<", ">", "!"]
                guard let symbol = symbols.first(where: { String(characters[at...]).hasPrefix($0) }) else { return nil }
                found.append(.symbol(symbol))
                at += symbol.count
            }
        }
        return found
    }

    /// Reads a condition, working its value out as it goes.
    private struct Reader {
        let tokens: [Token]
        let values: (String) -> Value?
        var at = 0

        private mutating func take(_ symbols: String...) -> String? {
            guard at < tokens.count, case .symbol(let symbol) = tokens[at], symbols.contains(symbol) else { return nil }
            at += 1
            return symbol
        }

        mutating func either() -> Value?? {
            guard var left = both() else { return nil }
            while take("||") != nil {
                guard let right = both() else { return nil }
                left = (left?.isTrue ?? false) ? left : right
            }
            return left
        }

        private mutating func both() -> Value?? {
            guard var left = comparison() else { return nil }
            while take("&&") != nil {
                guard let right = comparison() else { return nil }
                left = (left?.isTrue ?? false) ? right : left
            }
            return left
        }

        private mutating func comparison() -> Value?? {
            guard let left = single() else { return nil }
            guard let symbol = take("===", "!==", "==", "!=", "<=", ">=", "<", ">") else { return left }
            guard let right = single() else { return nil }
            return .flag(Self.compare(left, symbol, right))
        }

        private static func compare(_ left: Value?, _ symbol: String, _ right: Value?) -> Bool {
            var same = left == nil && right == nil
            var order: Double?
            if let left, let right {
                if let a = left.asNumber, let b = right.asNumber {
                    same = a == b
                    order = a - b
                } else {
                    same = left.asText == right.asText
                }
            }
            switch symbol {
            case "==", "===": return same
            case "!=", "!==": return !same
            case "<": return (order ?? 0) < 0
            case ">": return (order ?? 0) > 0
            case "<=": return order.map { $0 <= 0 } ?? same
            default: return order.map { $0 >= 0 } ?? same
            }
        }

        private mutating func single() -> Value?? {
            if take("!") != nil {
                guard let value = single() else { return nil }
                return .flag(!(value?.isTrue ?? false))
            }
            guard at < tokens.count else { return nil }
            let token = tokens[at]
            at += 1
            switch token {
            case .literal(let value):
                return value
            case .name(let name):
                // `language.value`: the setting's value; a setting named alone stands for itself.
                let setting = name.hasSuffix(".value") ? String(name.dropLast(6)) : name
                return .some(values(setting))
            case .open:
                guard let value = either(), at < tokens.count, tokens[at] == .close else { return nil }
                at += 1
                return value
            default:
                return nil
            }
        }
    }

    private static func read(_ text: String, values: @escaping (String) -> Value?) -> Value?? {
        guard let tokens = tokens(text), !tokens.isEmpty else { return nil }
        var reader = Reader(tokens: tokens, values: values)
        guard let value = reader.either(), reader.at == tokens.count else { return nil }
        return value
    }

    /// Whether a text is a condition at all.
    public static func isValid(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty || read(text, values: { _ in nil }) != nil
    }

    /// Whether a setting with this condition is shown. No condition, or one that makes no sense,
    /// hides nothing.
    public static func isMet(_ text: String, values: @escaping (String) -> Value?) -> Bool {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, let value = read(text, values: values) else { return true }
        return value?.isTrue ?? false
    }
}

extension WallpaperScene.Variable {
    /// What the setting is now, as a condition reads it.
    var conditionValue: WallpaperEngineCondition.Value? {
        switch kind {
        case .toggle: return .flag(isOn)
        case .number: return .number(number)
        case .color: return .text(color)
        case .text: return .text(text)
        case .choice:
            guard let index = options.firstIndex(of: text) else { return .text(text) }
            switch values?[safe: index] {
            case .text(let text): return .text(text)
            case .number(let number): return .number(number)
            case .flag(let flag): return .flag(flag)
            case nil: return .text(text)
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

extension WallpaperScene {
    /// The settings to show as they stand now, of those with conditions by their names.
    public func shownVariables(conditions: [String: String]) -> [Variable] {
        var byName: [String: WallpaperEngineCondition.Value] = [:]
        for variable in variables {
            if let name = variable.property, let value = variable.conditionValue { byName[name] = value }
        }
        return variables.filter { variable in
            guard let name = variable.property, let condition = conditions[name] else { return true }
            return WallpaperEngineCondition.isMet(condition) { byName[$0] }
        }
    }
}

extension WallpaperEngineProject {
    /// The conditions of the settings of a project in a folder, by the settings' names.
    public static func conditions(inProject folder: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(projectFileName)),
              let project = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let properties = (project["general"] as? [String: Any])?["properties"] as? [String: Any] else { return [:] }
        return properties.compactMapValues { ($0 as? [String: Any])?["condition"] as? String }.filter { !$0.value.isEmpty }
    }
}

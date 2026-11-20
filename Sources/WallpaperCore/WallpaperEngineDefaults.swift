import Foundation

/// What a value of a scene's file is taken to be when the file does not say it: the player's own
/// table, `Player/defaults.js`, read as it is, so that the editor shows of a value left unsaid
/// what the player plays (docs/we-format.md, rows 6 and 7). The table is kept there once.
public enum WallpaperEngineDefaults {
    /// The whole table.
    public static let table: JSONValue = {
        guard let script = WallpaperEngineRuntime.file(named: "defaults.js"), let json = tableText(of: script),
              let value = JSONValue(data: Data(json.utf8))
        else { fatalError("the scene player's defaults.js is missing or does not read") }
        return value
    }()

    /// The JSON between `var defaults = ` and the `;` that ends it.
    static func tableText(of script: String) -> String? {
        guard let start = script.range(of: "var defaults = "), let end = script.range(of: ";", options: .backwards),
              start.upperBound < end.lowerBound
        else { return nil }
        return String(script[start.upperBound..<end.lowerBound])
    }

    /// A value of an object: what every object takes, or what one of a kind takes (a text, a
    /// sound, a light).
    public static func object(_ key: String) -> JSONValue? {
        for section in ["object", "text", "sound", "light"] {
            if let value = table[section]?[key] { return value }
        }
        return nil
    }

    /// An object's value as so many numbers: a single number stands for all of them, as the
    /// player reads it.
    public static func numbers(_ key: String, count: Int) -> [Double] {
        let value = object(key)
        let said = value?.arrayValue?.compactMap(\.numberValue) ?? value?.numberValue.map { [$0] } ?? [0]
        return (0..<count).map { $0 < said.count ? said[$0] : said[0] }
    }

    /// A value of a part of a system of particles: of its emitters (all take the same), of an
    /// initializer or operator by its name — or what all of them take — or of the system itself
    /// (`section` "system").
    public static func particle(_ section: String, _ name: String?, _ key: String) -> JSONValue? {
        let particles = table["particles"]
        switch section {
        case "emitter", "system": return particles?[section]?[key]
        case "initializer", "operator":
            return particles?[section + "s"]?[name ?? ""]?[key] ?? particles?[section]?[key]
        default: return nil
        }
    }
}

import Foundation

/// What a scene of the app hands the scene player, read from its `scene.json` as the scene's
/// page reads it: the settings by the names Wallpaper Engine's scene has for them, in the form
/// Wallpaper Engine hands them over; what the editor changed of the scene; how it fills the screen.
public struct SceneSettings {
    public var settings: [String: Any] = [:]
    public var changes: [String: Any] = [:]
    public var fit = "cover"
    public var position = 50.0

    public init() {}

    public init(sceneFile: URL) {
        self.init(sceneData: (try? Data(contentsOf: sceneFile)) ?? Data())
    }

    /// From the text of a `scene.json`.
    public init(sceneData data: Data) {
        guard let scene = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let background = scene["background"] as? [String: Any] ?? [:]
        changes = background["engine"] as? [String: Any] ?? [:]
        fit = background["fit"] as? String ?? "cover"
        position = min(100, max(0, (background["position"] as? NSNumber)?.doubleValue ?? 50))
        for variable in scene["variables"] as? [[String: Any]] ?? [] {
            guard let property = variable["property"] as? String, !property.isEmpty else { continue }
            settings[property] = Self.value(of: variable)
        }
    }

    /// A variable's value as Wallpaper Engine hands a setting over (`pageValue` on the page).
    static func value(of variable: [String: Any]) -> Any {
        let kind = variable["kind"] as? String ?? ""
        switch kind {
        case "number": return (variable["number"] as? NSNumber)?.doubleValue ?? 0
        case "toggle": return (variable["isOn"] as? NSNumber)?.boolValue ?? true
        case "color":
            let hex = (variable["color"] as? String ?? "#FFFFFF").trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            let parts = stride(from: 0, to: min(6, hex.count), by: 2).map { offset -> String in
                let start = hex.index(hex.startIndex, offsetBy: offset)
                let value = Double(Int(hex[start..<hex.index(start, offsetBy: 2)], radix: 16) ?? 255) / 255
                return String(format: "%.5f", value).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
            }
            return parts.count == 3 ? parts.joined(separator: " ") : "1 1 1"
        default:
            let text = variable["text"] as? String ?? ""
            if kind == "choice", let values = variable["values"] as? [Any], let options = variable["options"] as? [String],
               let chosen = options.firstIndex(of: text), chosen < values.count {
                return Self.optionValue(values[chosen])
            }
            return text
        }
    }

    /// An option's value as the scene's file stores it: {"text": …}, {"number": …}, {"bool": …}.
    private static func optionValue(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any], let first = dictionary.values.first {
            if let nested = first as? [String: Any], let inner = nested["_0"] { return inner }
            return first
        }
        return value
    }
}

import CoreFoundation
import Foundation

/// A wallpaper made for Wallpaper Engine, as the `project.json` in its folder describes it.
public struct WallpaperEngineProject: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A web page. It is shown as the background of a scene, with its settings as the
        /// scene's variables.
        case web
        /// A video file.
        case video
        /// Anything else, by the name the project gives it: one of Wallpaper Engine's own
        /// scenes, an application. These need Wallpaper Engine itself to draw them.
        case other(String)
    }

    public static let projectFileName = "project.json"

    public let folder: URL
    public let title: String?
    public let kind: Kind
    /// The page or the video, relative to the folder.
    public let file: String?
    /// The preview picture that came with the wallpaper, relative to the folder.
    public let previewFile: String?
    /// The page's own settings — the project's `general.properties` — as variables of a scene.
    public let variables: [WallpaperScene.Variable]

    /// Reads the folder; nil when it holds no Wallpaper Engine project.
    /// - Parameter languages: the languages to name the settings in, the most wanted first.
    public init?(folder: URL, languages: [String] = Locale.preferredLanguages) {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.projectFileName)),
              let project = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return nil
        }
        let files = FileManager.default
        // A name that leads out of the folder is not followed.
        func inside(_ name: Any?) -> String? {
            guard let name = name as? String, !name.isEmpty, Archive.staysInside(name),
                  files.fileExists(atPath: folder.appendingPathComponent(name).path)
            else {
                return nil
            }
            return name
        }
        let file = inside(project["file"])
        let type = (project["type"] as? String)?.lowercased() ?? ""
        switch type {
        case "web":
            kind = .web
        case "video":
            kind = .video
        case "":
            // Old projects do not say; the file does.
            switch (file as NSString?)?.pathExtension.lowercased() {
            case "html", "htm": kind = .web
            case "mp4", "mov", "m4v", "webm": kind = .video
            default: return nil // some other tool's project.json
            }
        default:
            kind = .other(type)
        }

        self.folder = folder
        self.file = file
        title = (project["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        previewFile = inside(project["preview"])
        let general = project["general"] as? [String: Any] ?? [:]
        variables = kind == .web
            ? Self.variables(properties: general["properties"] as? [String: Any] ?? [:],
                             localization: general["localization"] as? [String: Any] ?? [:],
                             languages: languages)
            : []
    }

    /// The project in a folder: the folder's own, or that of a folder right inside it. An
    /// archive of a wallpaper has it in a folder, next to files of the site it came from.
    public static func find(in folder: URL, languages: [String] = Locale.preferredLanguages) -> WallpaperEngineProject? {
        if let project = WallpaperEngineProject(folder: folder, languages: languages) {
            return project
        }
        let inside = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles])) ?? []
        return inside
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .lazy
            .compactMap { WallpaperEngineProject(folder: $0, languages: languages) }
            .first
    }

    // MARK: - Settings

    /// Turns Wallpaper Engine's description of a page's settings into variables: a color, a
    /// slider, a checkbox, a list and a text field each have a kind of variable to match.
    /// Headings, files to pick and the like have no value a variable could hold and are left out.
    static func variables(properties: [String: Any], localization: [String: Any], languages: [String]) -> [WallpaperScene.Variable] {
        let texts = texts(in: localization, for: languages)
        // Wallpaper Engine shows a label as HTML and looks it up among the translations first.
        func label(_ raw: Any?, or fallback: String) -> String {
            guard let raw = raw as? String, !raw.isEmpty else { return fallback }
            if raw == "ui_browse_properties_scheme_color" {
                return NSLocalizedString("Scheme color", comment: "Wallpaper Engine's own setting of every wallpaper")
            }
            let plain = plainText(texts[raw] ?? raw)
            return plain.isEmpty ? fallback : plain
        }
        func order(_ property: [String: Any]) -> Double {
            number(property["order"]) ?? number(property["index"]) ?? .infinity
        }

        let ordered = properties
            .compactMap { name, value in (value as? [String: Any]).map { (name: name, property: $0) } }
            .sorted { order($0.property) != order($1.property) ? order($0.property) < order($1.property) : $0.name < $1.name }

        var scene = WallpaperScene()
        for (name, property) in ordered {
            let value = property["value"]
            let title = label(property["text"], or: name)
            let key = scene.uniqueKey(name)
            var variable: WallpaperScene.Variable
            switch (property["type"] as? String)?.lowercased() {
            case "color":
                variable = .init(kind: .color, title: title, key: key)
                variable.color = hexColor(value as? String) ?? "#FFFFFF"
            case "slider":
                variable = .init(kind: .number, title: title, key: key)
                variable.minimum = number(property["min"]) ?? 0
                variable.maximum = number(property["max"]) ?? 100
                variable.number = number(value) ?? variable.minimum
                // A slider moves by whole numbers unless it says it has fractions.
                let digits = number(property["precision"]) ?? 2
                variable.step = number(property["step"]) ?? ((property["fraction"] as? Bool) == true ? pow(10, -digits) : 1)
            case "bool":
                variable = .init(kind: .toggle, title: title, key: key)
                variable.isOn = (value as? Bool) ?? ((number(value) ?? 0) != 0)
            case "combo":
                variable = .init(kind: .choice, title: title, key: key)
                var labels: [String] = []
                var values: [WallpaperScene.Variable.OptionValue] = []
                for option in property["options"] as? [[String: Any]] ?? [] {
                    guard let optionValue = optionValue(option["value"]) else { continue }
                    var text = label(option["label"], or: plain(option["value"]))
                    // The chosen option is known by its label, so no two may read the same.
                    var copy = 2
                    while labels.contains(text) {
                        text = "\(label(option["label"], or: plain(option["value"]))) (\(copy))"
                        copy += 1
                    }
                    labels.append(text)
                    values.append(optionValue)
                }
                guard !labels.isEmpty else { continue }
                variable.options = labels
                variable.values = values
                let chosen = values.firstIndex { plain($0) == plain(value) } ?? 0
                variable.text = labels[chosen]
            case "textinput":
                variable = .init(kind: .text, title: title, key: key)
                variable.text = value as? String ?? ""
            default:
                continue
            }
            variable.property = name
            scene.variables.append(variable)
        }
        return scene.variables
    }

    /// The translations to use, by the label they stand for: for each label the most wanted
    /// language that has it, then English, then whatever language there is.
    private static func texts(in localization: [String: Any], for languages: [String]) -> [String: String] {
        let tables = localization.compactMapValues { $0 as? [String: Any] }
        var texts: [String: String] = [:]
        func take(_ table: [String: Any]) {
            for (label, text) in table {
                if let text = text as? String, !text.isEmpty {
                    texts[label] = text
                }
            }
        }
        for code in tables.keys.sorted().reversed() {
            take(tables[code]!)
        }
        // "ru-KZ" asks for Russian, which Wallpaper Engine calls "ru-ru".
        let wanted = languages.map { String($0.lowercased().split(separator: "-").first ?? "") } + ["en"]
        for language in wanted.reversed() where !language.isEmpty {
            for code in tables.keys.sorted().reversed() where code.lowercased().hasPrefix(language) {
                take(tables[code]!)
            }
        }
        return texts
    }

    /// A label without the HTML Wallpaper Engine lets it have.
    private static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, character) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return (value as? String).flatMap(Double.init)
    }

    /// Wallpaper Engine writes a color as three numbers from 0 to 1: "0.18 0.55 0.96".
    static func hexColor(_ text: String?) -> String? {
        let parts = (text ?? "").split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
        guard parts.count >= 3 else { return nil }
        let bytes = parts.prefix(3).map { Int((min(1, max(0, $0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }

    private static func optionValue(_ value: Any?) -> WallpaperScene.Variable.OptionValue? {
        if let text = value as? String {
            return .text(text)
        }
        guard let number = value as? NSNumber else { return nil }
        // In JSON read this way a true is a number too, of a type of its own.
        return CFGetTypeID(number) == CFBooleanGetTypeID() ? .flag(number.boolValue) : .number(number.doubleValue)
    }

    /// A value as text, to tell which option a setting is at: 1, 1.0 and "1" are the same choice.
    private static func plain(_ value: Any?) -> String {
        if let value = value as? WallpaperScene.Variable.OptionValue {
            switch value {
            case .text(let text): return text
            case .number(let number): return plain(NSNumber(value: number))
            case .flag(let flag): return flag ? "true" : "false"
            }
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            let double = number.doubleValue
            return double == double.rounded() && abs(double) < 1e15 ? String(Int64(double)) : String(double)
        }
        return value as? String ?? ""
    }
}

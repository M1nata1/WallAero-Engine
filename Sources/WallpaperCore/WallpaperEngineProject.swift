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
        /// One of Wallpaper Engine's own scenes: pictures on a canvas, in `scene.pkg`. It is
        /// played as the background of a scene, see `WallpaperEngineScene`, with its settings
        /// as the scene's variables.
        case scene
        /// Settings alone, made for another wallpaper, which the project names: what the
        /// Workshop calls a preset. It is brought in as that wallpaper with these settings.
        case preset
        /// Anything else, by the name the project gives it: an application. These need
        /// Wallpaper Engine itself to draw them.
        case other(String)
    }

    public static let projectFileName = "project.json"

    public let folder: URL
    public private(set) var title: String?
    public let kind: Kind
    /// The page or the video, relative to the folder.
    public let file: String?
    /// The preview picture that came with the wallpaper, relative to the folder.
    public let previewFile: String?
    /// The wallpaper's own settings — the project's `general.properties` — as variables of a
    /// scene. A page or a scene of Wallpaper Engine's has them; a video has none.
    public private(set) var variables: [WallpaperScene.Variable]
    /// What the wallpaper says of itself, as tags: its genres, its kind and whom it is fit for.
    public private(set) var tags: [Tag]
    /// The pictures chosen for the settings of a scene that take a picture, by the settings' names.
    public private(set) var chosenPictures: [String: URL]
    /// The settings of a scene that take a picture, in the order the wallpaper lists them: each
    /// by its name and by what it is called in the wallpaper's settings.
    public private(set) var pictureSettingTitles: [PictureSetting] = []

    /// A setting of a scene that takes a picture.
    public struct PictureSetting: Equatable, Sendable {
        public let name: String
        public let title: String
    }
    /// The number the Workshop knows the wallpaper by, when the project says it.
    public let workshopID: String?
    /// For settings made for another wallpaper: the Workshop's number of that wallpaper.
    public let dependency: String?

    /// The values settings made for another wallpaper give its settings, by their names.
    private let presetValues: [String: WallpaperScene.Variable.OptionValue]
    /// The names of the settings that take a picture.
    private let pictureSettings: [String]
    private let genres: [String]
    private let rating: String?

    /// A tag a wallpaper comes with, and the category such tags belong to.
    public struct Tag: Equatable, Sendable {
        public let name: String
        public let category: String

        public init(name: String, category: String) {
            self.name = name
            self.category = category
        }
    }

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
        let dependency = (project["dependency"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (project["dependency"] as? NSNumber).map { $0.stringValue }
        let preset = project["preset"] as? [String: Any]
        switch type {
        case _ where dependency != nil && preset != nil && project["file"] == nil:
            kind = .preset
        case "web":
            kind = .web
        case "video":
            kind = .video
        case "scene":
            kind = .scene
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
        self.dependency = dependency
        workshopID = (project["workshopid"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (project["workshopid"] as? NSNumber).map { $0.stringValue }
        title = (project["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        previewFile = inside(project["preview"])
        let general = project["general"] as? [String: Any] ?? [:]
        let properties = general["properties"] as? [String: Any] ?? [:]
        variables = kind == .web || kind == .scene
            ? Self.variables(properties: properties, localization: general["localization"] as? [String: Any] ?? [:], languages: languages)
            : []
        presetValues = (preset ?? [:]).compactMapValues(Self.optionValue)
        // A setting of a scene may take a picture; one may be set from the start.
        var pictureSettings: [String] = []
        var chosenPictures: [String: URL] = [:]
        for (name, property) in properties {
            guard let property = property as? [String: Any], (property["type"] as? String)?.lowercased() == "scenetexture" else { continue }
            pictureSettings.append(name)
            if let picture = inside(property["value"]) {
                chosenPictures[name] = folder.appendingPathComponent(picture)
            }
        }
        self.pictureSettings = pictureSettings.sorted()
        self.chosenPictures = chosenPictures
        let translations = Self.texts(in: general["localization"] as? [String: Any] ?? [:], for: languages)
        pictureSettingTitles = pictureSettings
            .sorted { name, other in
                func order(_ name: String) -> Double {
                    let property = properties[name] as? [String: Any] ?? [:]
                    return Self.number(property["order"]) ?? Self.number(property["index"]) ?? .infinity
                }
                return order(name) != order(other) ? order(name) < order(other) : name < other
            }
            .map { name in
                let raw = (properties[name] as? [String: Any])?["text"] as? String ?? ""
                let title = Self.plainText(translations[raw] ?? raw)
                return PictureSetting(name: name, title: title.isEmpty ? name : title)
            }
        genres = (project["tags"] as? [Any])?.compactMap { $0 as? String } ?? (project["tags"] as? String).map { [$0] } ?? []
        rating = project["contentrating"] as? String
        tags = Self.tags(genres: genres, kind: kind, rating: rating)
    }

    /// The wallpaper as settings made for it have it: under their name, with the values they
    /// give its settings and the pictures they choose, and with what they say of themselves.
    func taking(_ preset: WallpaperEngineProject) -> WallpaperEngineProject {
        var result = self
        result.title = preset.title ?? title
        result.variables = variables.map { variable in
            guard let name = variable.property, let value = preset.presetValues[name] else { return variable }
            var variable = variable
            switch (variable.kind, value) {
            case (.color, .text(let text)):
                variable.color = Self.hexColor(text) ?? variable.color
            case (.number, .number(let number)):
                variable.number = variable.clamped(number)
            case (.toggle, .flag(let flag)):
                variable.isOn = flag
            case (.toggle, .number(let number)):
                variable.isOn = number != 0
            case (.text, .text(let text)):
                variable.text = text
            case (.choice, _):
                if let chosen = variable.values?.firstIndex(where: { Self.plain($0) == Self.plain(value) }), chosen < variable.options.count {
                    variable.text = variable.options[chosen]
                }
            default:
                break
            }
            return variable
        }
        for name in pictureSettings {
            // A name that leads out of the settings' folder is not followed.
            guard case .text(let picture)? = preset.presetValues[name], !picture.isEmpty, Archive.staysInside(picture) else { continue }
            let file = preset.folder.appendingPathComponent(picture)
            if FileManager.default.fileExists(atPath: file.path) {
                result.chosenPictures[name] = file
            }
        }
        result.tags = Self.tags(genres: preset.genres.isEmpty ? genres : preset.genres, kind: kind, rating: preset.rating ?? rating)
        return result
    }

    /// The projects as they are brought in. Settings made for another wallpaper become that
    /// wallpaper with those settings when it lies next to them — sites pack the two together —
    /// and the wallpaper is then not brought in a second time as it was made.
    static func settled(_ projects: [WallpaperEngineProject]) -> [WallpaperEngineProject] {
        func base(of preset: WallpaperEngineProject) -> WallpaperEngineProject? {
            projects.first { $0.kind != .preset && ($0.folder.lastPathComponent == preset.dependency || $0.workshopID == preset.dependency) }
        }
        let used = Set(projects.filter { $0.kind == .preset }.compactMap { base(of: $0)?.folder })
        return projects.compactMap { project in
            if project.kind == .preset {
                return base(of: project)?.taking(project) ?? project
            }
            return used.contains(project.folder) ? nil : project
        }
    }

    /// The projects in a folder: the folder's own, or those of the folders right inside it. An
    /// archive of a wallpaper has it in a folder, next to files of the site it came from, and
    /// may have more than one wallpaper, each in a folder of its own.
    public static func all(in folder: URL, languages: [String] = Locale.preferredLanguages) -> [WallpaperEngineProject] {
        if let project = WallpaperEngineProject(folder: folder, languages: languages) {
            return [project]
        }
        let inside = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles])) ?? []
        return inside
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { WallpaperEngineProject(folder: $0, languages: languages) }
    }

    // MARK: - Tags

    /// The genres of the Workshop, by the names a project has them under, each with its name here.
    private static let genres: [String: String] = [
        "abstract": NSLocalizedString("Abstract", comment: "Wallpaper genre"),
        "animal": NSLocalizedString("Animals", comment: "Wallpaper genre"),
        "anime": NSLocalizedString("Anime", comment: "Wallpaper genre"),
        "cartoon": NSLocalizedString("Cartoons", comment: "Wallpaper genre"),
        "cgi": NSLocalizedString("Computer graphics", comment: "Wallpaper genre"),
        "cyberpunk": NSLocalizedString("Cyberpunk", comment: "Wallpaper genre"),
        "fantasy": NSLocalizedString("Fantasy", comment: "Wallpaper genre"),
        "game": NSLocalizedString("Games", comment: "Wallpaper genre"),
        "girls": NSLocalizedString("Girls", comment: "Wallpaper genre"),
        "guys": NSLocalizedString("Guys", comment: "Wallpaper genre"),
        "landscape": NSLocalizedString("Landscapes", comment: "Wallpaper genre"),
        "medieval": NSLocalizedString("Medieval", comment: "Wallpaper genre"),
        "memes": NSLocalizedString("Memes", comment: "Wallpaper genre"),
        "mmd": NSLocalizedString("MMD", comment: "Wallpaper genre"),
        "music": NSLocalizedString("Music", comment: "Wallpaper genre"),
        "nature": NSLocalizedString("Nature", comment: "Wallpaper genre"),
        "pixel art": NSLocalizedString("Pixel art", comment: "Wallpaper genre"),
        "relaxing": NSLocalizedString("Relaxing", comment: "Wallpaper genre"),
        "retro": NSLocalizedString("Retro", comment: "Wallpaper genre"),
        "sci-fi": NSLocalizedString("Science fiction", comment: "Wallpaper genre"),
        "sports": NSLocalizedString("Sports", comment: "Wallpaper genre"),
        "technology": NSLocalizedString("Technology", comment: "Wallpaper genre"),
        "television": NSLocalizedString("Television", comment: "Wallpaper genre"),
        "vehicle": NSLocalizedString("Vehicles", comment: "Wallpaper genre"),
    ]

    /// The tags of a project. Its genres are named in the app's language where they are the
    /// Workshop's own and left as written where the author made them up; "Unspecified" is no
    /// genre. A project of a kind the app does not take, or without a rating, has no tag for it.
    static func tags(genres: [String], kind: Kind, rating: String?) -> [Tag] {
        var tags: [Tag] = []
        let genreCategory = NSLocalizedString("Genre", comment: "Category of tags a wallpaper comes with")
        for genre in genres {
            let trimmed = genre.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 60, trimmed.lowercased() != "unspecified" else { continue }
            tags.append(Tag(name: Self.genres[trimmed.lowercased()] ?? trimmed, category: genreCategory))
        }

        let kindCategory = NSLocalizedString("Kind", comment: "Category of tags a wallpaper comes with")
        switch kind {
        case .scene: tags.append(Tag(name: NSLocalizedString("Scene", comment: "Kind of wallpaper, as a tag"), category: kindCategory))
        case .video: tags.append(Tag(name: NSLocalizedString("Video", comment: "Kind of wallpaper, as a tag"), category: kindCategory))
        case .web: tags.append(Tag(name: NSLocalizedString("Web page", comment: "Kind of wallpaper, as a tag"), category: kindCategory))
        case .preset, .other: break
        }

        let ratingCategory = NSLocalizedString("Age rating", comment: "Category of tags a wallpaper comes with")
        switch rating?.lowercased() {
        case "everyone": tags.append(Tag(name: NSLocalizedString("For everyone", comment: "Age rating of a wallpaper"), category: ratingCategory))
        case "questionable": tags.append(Tag(name: NSLocalizedString("Questionable", comment: "Age rating of a wallpaper"), category: ratingCategory))
        case "mature": tags.append(Tag(name: NSLocalizedString("For adults", comment: "Age rating of a wallpaper"), category: ratingCategory))
        default: break
        }
        // One name is one tag, whatever it was a tag of first.
        var seen: Set<String> = []
        return tags.filter { seen.insert($0.name.lowercased()).inserted }
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

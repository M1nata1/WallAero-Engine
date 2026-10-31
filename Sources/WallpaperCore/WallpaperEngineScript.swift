import Foundation

/// A value a script can stand behind: of an object, of one of its effects, or of the scene.
public enum WallpaperEngineScriptTarget: Hashable, Sendable {
    case value(object: Int, key: String)
    case effect(object: Int, index: Int, pass: Int, name: String)
    case general(String)
}

/// A setting a script declares for itself with `createScriptProperties()`.
public struct WallpaperEngineScriptSetting: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case slider, checkbox, color, combo, text
    }

    public var kind: Kind
    public var name: String
    public var label: String
    public var number: Double
    public var text: String
    public var isOn: Bool
    public var minimum: Double
    public var maximum: Double
    public var isWhole: Bool
    public var options: [(label: String, value: String)]

    public var id: String { name }

    public static func == (a: Self, b: Self) -> Bool {
        a.kind == b.kind && a.name == b.name && a.label == b.label && a.number == b.number && a.text == b.text && a.isOn == b.isOn
            && a.minimum == b.minimum && a.maximum == b.maximum && a.isWhole == b.isWhole
            && a.options.map(\.label) == b.options.map(\.label) && a.options.map(\.value) == b.options.map(\.value)
    }

    /// From what the player found the script to declare.
    public init?(_ said: [String: Any]) {
        guard let kind = (said["kind"] as? String).flatMap(Kind.init(rawValue:)), let name = said["name"] as? String else { return nil }
        self.kind = kind
        self.name = name
        label = said["label"] as? String ?? name
        number = (said["value"] as? NSNumber)?.doubleValue ?? 0
        text = said["value"] as? String ?? ""
        isOn = (said["value"] as? NSNumber)?.boolValue ?? false
        minimum = (said["min"] as? NSNumber)?.doubleValue ?? 0
        maximum = (said["max"] as? NSNumber)?.doubleValue ?? max(1, number * 2)
        isWhole = (said["integer"] as? NSNumber)?.boolValue ?? false
        options = (said["options"] as? [[String: Any]] ?? []).map { option in
            let value = option["value"].map { "\($0)" } ?? ""
            return (option["label"] as? String ?? value, value)
        }
        // A list that names no value starts on its first choice.
        if kind == .combo, text.isEmpty, let first = options.first { text = first.value }
    }
}

extension WallpaperEngineDocument {
    /// What the scene says of a value a script may stand behind, with whatever else stands there.
    public func rawValue(of target: WallpaperEngineScriptTarget) -> JSONValue? {
        switch target {
        case .value(let object, let key):
            return self.object(object)?[key]
        case .effect(let object, let index, let pass, let name):
            return self.object(object)?["effects"]?[index]?["passes"]?[pass]?["constantshadervalues"]?[name]
        case .general(let key):
            return self[general: key]
        }
    }

    private mutating func setRawValue(_ value: JSONValue?, of target: WallpaperEngineScriptTarget) {
        switch target {
        case .value(let object, let key):
            update(object) { $0[key] = value }
        case .effect(let object, let index, let pass, let name):
            update(object) { object in
                guard var effects = object["effects"]?.arrayValue, effects.indices.contains(index),
                      var passes = effects[index]["passes"]?.arrayValue, passes.indices.contains(pass) else { return }
                var constants = passes[pass]["constantshadervalues"] ?? .object([:])
                constants[name] = value
                passes[pass]["constantshadervalues"] = constants
                effects[index]["passes"] = .array(passes)
                object["effects"] = .array(effects)
            }
        case .general(let key):
            self[general: key] = value
        }
    }

    public func script(of target: WallpaperEngineScriptTarget) -> String? {
        rawValue(of: target)?.objectValue?["script"]?.stringValue
    }

    /// Puts a script behind a value. `fallback` is the value of one the scene does not write down.
    public mutating func setScript(_ text: String, of target: WallpaperEngineScriptTarget, fallback: JSONValue) {
        let raw = rawValue(of: target)
        var value: JSONValue
        if let raw, raw.objectValue != nil {
            value = raw
            if value["value"] == nil { value["value"] = fallback }
        } else {
            value = .object(["value": raw ?? fallback])
        }
        value["script"] = .string(text)
        setRawValue(value, of: target)
    }

    /// Takes a script away: the value is left as the scene says it, and what else stands behind
    /// it, a setting of the wallpaper or an animation, stays.
    public mutating func removeScript(of target: WallpaperEngineScriptTarget) {
        guard var value = rawValue(of: target), value.objectValue != nil else { return }
        value["script"] = nil
        value["scriptproperties"] = nil
        if let keys = value.objectValue?.keys, keys.count == 1, let plain = value["value"] {
            setRawValue(plain, of: target)
        } else {
            setRawValue(value, of: target)
        }
    }

    /// What the scene gives a setting of the script, which may stand on a setting of the wallpaper.
    public func scriptProperty(_ name: String, of target: WallpaperEngineScriptTarget) -> JSONValue? {
        rawValue(of: target)?["scriptproperties"]?[name]
    }

    public mutating func setScriptProperty(_ name: String, to new: JSONValue, of target: WallpaperEngineScriptTarget) {
        guard var value = rawValue(of: target) else { return }
        var properties = value["scriptproperties"] ?? .object([:])
        if var bound = properties[name], bound.objectValue != nil {
            bound["value"] = new
            properties[name] = bound
        } else {
            properties[name] = new
        }
        value["scriptproperties"] = properties
        setRawValue(value, of: target)
    }

    /// The scripts of an object, of its own values and those of its effects.
    public func scriptTargets(of id: Int) -> [WallpaperEngineScriptTarget] {
        guard let object = object(id), let keys = object.objectValue?.keys else { return [] }
        var found = keys.sorted().filter { object[$0]?.objectValue?["script"]?.stringValue != nil }
            .map { WallpaperEngineScriptTarget.value(object: id, key: $0) }
        for (index, effect) in (object["effects"]?.arrayValue ?? []).enumerated() {
            for (pass, step) in (effect["passes"]?.arrayValue ?? []).enumerated() {
                for name in (step["constantshadervalues"]?.objectValue?.keys).map({ $0.sorted() }) ?? []
                where step["constantshadervalues"]?[name]?.objectValue?["script"]?.stringValue != nil {
                    found.append(.effect(object: id, index: index, pass: pass, name: name))
                }
            }
        }
        return found
    }

    /// The scripts of the scene as a whole.
    public var sceneScriptTargets: [WallpaperEngineScriptTarget] {
        (scene["general"]?.objectValue?.keys).map { $0.sorted() }?
            .filter { self[general: $0]?.objectValue?["script"]?.stringValue != nil }
            .map { .general($0) } ?? []
    }
}

/// What the editor knows of the text of scripts: how a new one starts, what can be put in one,
/// and how the names in one are told apart.
public enum WallpaperEngineScriptText {
    /// A new script, as Wallpaper Engine starts one: for a value of a type, by the name it has
    /// in the documentation: Number, Boolean, String, Vec2, Vec3 or Vec4.
    public static func template(type: String, key: String) -> String {
        """
        'use strict';

        /**
         * @param {\(type)} value - for property '\(key)'
         * @return {\(type)} - update current property value
         */
        export function update(value) {
        \t
        \treturn value;
        }

        """
    }

    /// The call that declares a setting, as it stands in the chain of `createScriptProperties()`.
    private static func declaration(_ kind: WallpaperEngineScriptSetting.Kind, name: String) -> String {
        switch kind {
        case .slider: return "\t.addSlider({ name: '\(name)', label: '\(name)', value: 50, min: 0, max: 100, integer: false })"
        case .checkbox: return "\t.addCheckbox({ name: '\(name)', label: '\(name)', value: true })"
        case .color: return "\t.addColor({ name: '\(name)', label: '\(name)', value: '1 1 1' })"
        case .text: return "\t.addText({ name: '\(name)', label: '\(name)', value: '' })"
        case .combo:
            return "\t.addCombo({ name: '\(name)', label: '\(name)', options: [{ label: 'First', value: 'first' }, { label: 'Second', value: 'second' }] })"
        }
    }

    /// The script with one more setting: in its chain of them, or in a new one after its
    /// `'use strict'` and imports.
    public static func adding(_ kind: WallpaperEngineScriptSetting.Kind, name: String, to text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        if let start = lines.firstIndex(where: { $0.contains("createScriptProperties()") }),
           let end = lines[start...].firstIndex(where: { $0.contains(".finish()") }) {
            lines.insert(declaration(kind, name: name), at: end)
            return lines.joined(separator: "\n")
        }
        var after = 0
        for (index, line) in lines.enumerated() {
            let plain = line.trimmingCharacters(in: .whitespaces)
            if plain.hasPrefix("'use strict'") || plain.hasPrefix("\"use strict\"") || plain.hasPrefix("import ") { after = index + 1 }
        }
        lines.insert(contentsOf: ["", "export var scriptProperties = createScriptProperties()", declaration(kind, name: name), "\t.finish();"], at: after)
        return lines.joined(separator: "\n")
    }

    // MARK: - Ready-made scripts

    public struct Example: Identifiable, Sendable {
        public let id: String
        /// The type of value it is for.
        public let type: String
        public let text: String
    }

    public static let examples: [Example] = [
        Example(id: "spin", type: "Vec3", text: """
        'use strict';

        export var scriptProperties = createScriptProperties()
        \t.addSlider({ name: 'speed', label: 'Degrees a second', value: 45, min: -360, max: 360 })
        \t.finish();

        let turned = 0;

        export function update(value) {
        \tturned += scriptProperties.speed * engine.frametime;
        \tvalue.z += turned;
        \treturn value;
        }

        """),
        Example(id: "rainbow", type: "Vec3", text: """
        'use strict';

        export var scriptProperties = createScriptProperties()
        \t.addSlider({ name: 'seconds', label: 'Seconds a round', value: 8, min: 1, max: 60 })
        \t.finish();

        export function update(value) {
        \tconst hue = engine.runtime / scriptProperties.seconds * Math.PI * 2;
        \treturn new Vec3(
        \t\t0.5 + 0.5 * Math.cos(hue),
        \t\t0.5 + 0.5 * Math.cos(hue + Math.PI * 2 / 3),
        \t\t0.5 + 0.5 * Math.cos(hue + Math.PI * 4 / 3)
        \t);
        }

        """),
        Example(id: "flicker", type: "Number", text: """
        'use strict';

        export var scriptProperties = createScriptProperties()
        \t.addSlider({ name: 'depth', label: 'Depth', value: 0.3, min: 0, max: 1 })
        \t.addSlider({ name: 'speed', label: 'Speed', value: 8, min: 0.1, max: 30 })
        \t.finish();

        export function update(value) {
        \tconst time = engine.runtime * scriptProperties.speed;
        \tconst wave = Math.sin(time) * Math.sin(time * 2.3) * Math.sin(time * 0.7);
        \treturn value * (1 - scriptProperties.depth * (0.5 + 0.5 * wave));
        }

        """),
        Example(id: "sound", type: "Number", text: """
        'use strict';

        export var scriptProperties = createScriptProperties()
        \t.addSlider({ name: 'strength', label: 'Strength', value: 1, min: 0, max: 5 })
        \t.finish();

        const audio = engine.registerAudioBuffers(engine.AUDIO_RESOLUTION_16);

        export function update(value) {
        \tlet sum = 0;
        \tfor (let band = 0; band < 4; band++) {
        \t\tsum += audio.average[band];
        \t}
        \treturn value + sum / 4 * scriptProperties.strength;
        }

        """),
        Example(id: "follow", type: "Vec3", text: """
        'use strict';

        export var scriptProperties = createScriptProperties()
        \t.addSlider({ name: 'ease', label: 'Ease', value: 5, min: 0.5, max: 20 })
        \t.finish();

        let place;

        export function update(value) {
        \tconst cursor = input.cursorWorldPosition;
        \tplace = place || value.copy();
        \tconst step = Math.min(1, scriptProperties.ease * engine.frametime);
        \tplace.x += (cursor.x - place.x) * step;
        \tplace.y += (cursor.y - place.y) * step;
        \treturn place.copy();
        }

        """),
        Example(id: "clock", type: "String", text: """
        'use strict';

        export var scriptProperties = createScriptProperties()
        \t.addCheckbox({ name: 'seconds', label: 'With seconds', value: false })
        \t.finish();

        function two(number) {
        \treturn number < 10 ? '0' + number : String(number);
        }

        export function update(value) {
        \tconst now = new Date();
        \tconst time = two(now.getHours()) + ':' + two(now.getMinutes());
        \treturn scriptProperties.seconds ? time + ':' + two(now.getSeconds()) : time;
        }

        """),
        Example(id: "click", type: "Boolean", text: """
        'use strict';

        let shown = true;

        export function update(value) {
        \treturn shown;
        }

        export function cursorClick(event) {
        \tshown = !shown;
        }

        """),
    ]

    // MARK: - Names to offer

    public static let globalNames = [
        "thisLayer", "thisObject", "thisScene", "engine", "input", "shared", "console", "localStorage", "createScriptProperties",
        "Vec2", "Vec3", "Vec4", "Mat3", "Mat4", "Math", "update", "init", "cursorClick", "cursorDown", "cursorUp", "cursorMove",
        "cursorEnter", "cursorLeave", "applyUserProperties", "resizeScreen", "animationEvent",
    ]

    private static let layerNames = [
        "alpha", "angles", "color", "getAnimationLayer", "getAnimationLayerCount", "getChildren", "getEffect", "getEffectCount", "getParent",
        "getTextureAnimation", "getTransformMatrix", "getVideoTexture", "lookAt", "name", "origin", "parallaxDepth", "playSingleAnimation",
        "pointsize", "scale", "setParent", "size", "text", "visible",
    ]

    /// The names to offer after a name and a dot.
    public static func members(of name: String) -> [String] {
        switch name {
        case "thisLayer", "thisObject": return layerNames
        case "thisScene":
            return ["ambientcolor", "bloom", "bloomstrength", "bloomthreshold", "clearcolor", "createLayer", "destroyLayer", "enumerateLayers", "fov",
                    "getAnimation", "getCameraTransforms", "getLayer", "getLayerByID", "getLayerCount", "getLayerIndex", "name", "setCameraTransforms",
                    "skylightcolor", "sortLayer"]
        case "engine":
            return ["AUDIO_RESOLUTION_16", "AUDIO_RESOLUTION_32", "AUDIO_RESOLUTION_64", "canvasSize", "frametime", "isDesktopDevice", "isLandscape",
                    "isMobileDevice", "isPortrait", "isRunningInEditor", "isScreensaver", "isWallpaper", "openUserShortcut", "registerAsset",
                    "registerAudioBuffers", "runtime", "screenResolution", "setInterval", "setTimeout", "timeOfDay", "userProperties"]
        case "input": return ["cursorLeftDown", "cursorScreenPosition", "cursorWorldPosition"]
        case "localStorage": return ["clear", "delete", "get", "set"]
        case "console": return ["error", "log"]
        default: return []
        }
    }

    // MARK: - Telling the text apart

    public enum Token: Sendable {
        case comment, string, number, keyword, known
    }

    private static let keywords: Set<String> = [
        "await", "break", "case", "catch", "class", "const", "continue", "default", "delete", "do", "else", "export", "extends", "false", "finally",
        "for", "from", "function", "if", "import", "in", "instanceof", "let", "new", "null", "of", "return", "static", "super", "switch", "this",
        "throw", "true", "try", "typeof", "undefined", "var", "void", "while", "yield",
    ]
    private static let known = Set(globalNames)

    /// The parts of a text worth a color, as ranges of its UTF-16 units.
    public static func tokens(in text: String) -> [(range: NSRange, kind: Token)] {
        let units = Array(text.utf16)
        var found: [(NSRange, Token)] = []
        var at = 0
        func isWord(_ unit: UInt16) -> Bool {
            (48...57).contains(unit) || (65...90).contains(unit) || (97...122).contains(unit) || unit == 95 || unit == 36
        }
        while at < units.count {
            let unit = units[at], next = at + 1 < units.count ? units[at + 1] : 0
            let start = at
            if unit == 47, next == 47 {
                while at < units.count, units[at] != 10 { at += 1 }
                found.append((NSRange(location: start, length: at - start), .comment))
            } else if unit == 47, next == 42 {
                at += 2
                while at + 1 < units.count, !(units[at] == 42 && units[at + 1] == 47) { at += 1 }
                at = min(units.count, at + 2)
                found.append((NSRange(location: start, length: at - start), .comment))
            } else if unit == 34 || unit == 39 || unit == 96 {
                at += 1
                while at < units.count, units[at] != unit, unit == 96 || units[at] != 10 {
                    at += units[at] == 92 ? 2 : 1
                }
                at = min(units.count, at + 1)
                found.append((NSRange(location: start, length: at - start), .string))
            } else if (48...57).contains(unit) {
                while at < units.count, isWord(units[at]) || units[at] == 46 { at += 1 }
                found.append((NSRange(location: start, length: at - start), .number))
            } else if isWord(unit) {
                while at < units.count, isWord(units[at]) { at += 1 }
                let word = String(decoding: units[start..<at], as: UTF16.self)
                if keywords.contains(word) {
                    found.append((NSRange(location: start, length: at - start), .keyword))
                } else if known.contains(word) {
                    found.append((NSRange(location: start, length: at - start), .known))
                }
            } else {
                at += 1
            }
        }
        return found
    }
}

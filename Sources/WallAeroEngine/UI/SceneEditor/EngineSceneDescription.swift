import WallpaperCore
import Foundation

/// One of Wallpaper Engine's scenes as its player describes it to the editor: the scene's
/// objects as the scene has them, before the editor's changes, which the scene keeps apart
/// (`WallpaperScene.EngineChanges`).
struct EngineSceneDescription: Decodable, Equatable {
    /// The scene's own size, in its pixels.
    var width: Double
    var height: Double
    var parallax: Bool
    var parallaxAmount: Double
    var bloom: Bool
    var bloomStrength: Double
    /// In the order the scene draws them: the last is in front.
    var objects: [Object]

    struct Object: Decodable, Equatable, Identifiable {
        enum Kind: String, Decodable {
            case image, particles, text, sound, model, light, group

            var title: String {
                switch self {
                case .image: return NSLocalizedString("Image", comment: "Kind of an object of a Wallpaper Engine scene")
                case .particles: return NSLocalizedString("Particles", comment: "Kind of an object of a Wallpaper Engine scene")
                case .text: return NSLocalizedString("Text", comment: "Kind of an object of a Wallpaper Engine scene")
                case .sound: return NSLocalizedString("Sound", comment: "Kind of an object of a Wallpaper Engine scene")
                case .model: return NSLocalizedString("3D Model", comment: "Kind of an object of a Wallpaper Engine scene")
                case .light: return NSLocalizedString("Light Source", comment: "Kind of an object of a Wallpaper Engine scene")
                case .group: return NSLocalizedString("Group", comment: "Kind of an object of a Wallpaper Engine scene")
                }
            }

            var symbol: String {
                switch self {
                case .image: return "photo"
                case .particles: return "sparkles"
                case .text: return "textformat"
                case .sound: return "speaker.wave.2"
                case .model: return "cube"
                case .light: return "lightbulb"
                case .group: return "square.dashed"
                }
            }

            /// Whether the object is drawn tinted with a color of its own.
            var isTinted: Bool { self == .image || self == .text || self == .particles }
        }

        var id: Int
        var kind: Kind
        /// The object it hangs on, if any.
        var parent: Int?
        var name: String
        var isVisible: Bool
        var x: Double
        var y: Double
        var scaleX: Double
        var scaleY: Double
        var rotation: Double
        var opacity: Double
        var color: String
        /// The values an animation or a script changes as the scene plays: what the editor
        /// would make of them does not show. Named as the scene names them: "origin", "text".
        var steered: [String]
        var effects: [Effect]
        var text: String?
        var fontSize: Double?
        var volume: Double?
        var particleCount: Double?
        var particleRate: Double?
        var particleSpeed: Double?
        var particleSize: Double?
        var particleLifetime: Double?
        var particleOpacity: Double?
        var particleColor: String?

        func isSteered(_ name: String) -> Bool {
            steered.contains(name)
        }

        /// What the list calls it: its name, or what it is when it has none.
        var title: String { name.isEmpty ? kind.title : name }
    }

    struct Effect: Decodable, Equatable, Identifiable {
        /// Its place among the object's effects.
        var id: Int
        var name: String
        var isVisible: Bool
        var isSteered: Bool
        var values: [Value]
        /// What of it can be painted; old descriptions do not say.
        var masks: [Mask]?
        /// What of its shader can be switched; old descriptions do not say.
        var switches: [Switch]?

        var title: String { EngineSceneDescription.title(of: name, prefix: "ui_editor_effect_", suffix: "_title", table: "effect") }
    }

    /// A switch of an effect's shader: on or off, or one of several.
    struct Switch: Decodable, Equatable, Identifiable {
        struct Option: Decodable, Equatable {
            var label: String
            var value: Double

            var title: String { EngineSceneDescription.title(of: label, prefix: "ui_editor_properties_", suffix: "", table: "property") }
        }

        /// As the shader names it, and as the scene does.
        var name: String
        var label: String
        /// As shaders say: options, imageblending or audioprocessingoptions.
        var kind: String
        var value: Double
        var options: [Option]
        /// The passes of the effect it is in.
        var passes: [Int]

        var id: String { name }
        var title: String { EngineSceneDescription.title(of: label, prefix: "ui_editor_properties_", suffix: "", table: "property") }
    }

    /// A map to paint that an effect's shader asks for.
    struct Mask: Decodable, Equatable, Identifiable {
        var label: String
        /// As shaders say: opacitymask, flowmask, rgbmask or depth.
        var mode: String
        /// The texture slot it goes in, in each of these passes of the effect.
        var slot: Int
        var passes: [Int]
        /// What a new mask is filled with, from 0 to 255.
        var fill: Int

        var id: Int { slot }
        var isFlow: Bool { mode == "flowmask" }
        var isColor: Bool { mode == "rgbmask" }
        /// What a new one is filled with.
        var start: [UInt8] {
            if isFlow { return [WallpaperEngineMask.noDirection, WallpaperEngineMask.noDirection] }
            return [UInt8](repeating: UInt8(min(255, max(0, fill))), count: isColor ? 3 : 1)
        }
        var title: String { EngineSceneDescription.title(of: label, prefix: "ui_editor_properties_", suffix: "", table: "property") }
    }

    /// A value of an effect the scene lets be changed: a number, a point or a color.
    struct Value: Decodable, Equatable, Identifiable {
        /// The name the effect's material gives it.
        var name: String
        var label: String
        /// How many numbers: 1 to 4.
        var count: Int
        var value: [Double]
        var isColor: Bool
        var range: [Double]?
        var isWhole: Bool
        /// The value is an angle in radians, shown in degrees.
        var inDegrees: Bool
        var isSteered: Bool

        var id: String { name }
        var title: String { EngineSceneDescription.title(of: label, prefix: "ui_editor_properties_", suffix: "", table: "property") }
    }

    /// The object with this number.
    func object(_ id: Int) -> Object? {
        objects.first { $0.id == id }
    }

    /// The objects as the editor lists them: the one in front first, each followed by those
    /// that hang on it, one step further in.
    var rows: [(object: Object, depth: Int)] {
        let known = Set(objects.map(\.id))
        var children: [Int: [Object]] = [:]
        var roots: [Object] = []
        for object in objects {
            if let parent = object.parent, parent != object.id, known.contains(parent) {
                children[parent, default: []].append(object)
            } else {
                roots.append(object)
            }
        }
        var result: [(object: Object, depth: Int)] = []
        var seen: Set<Int> = []
        func add(_ object: Object, depth: Int) {
            guard seen.insert(object.id).inserted else { return }
            result.append((object, depth))
            for child in (children[object.id] ?? []).reversed() {
                add(child, depth: depth + 1)
            }
        }
        roots.reversed().forEach { add($0, depth: 0) }
        // Objects that hang on one another in a ring hang on nothing that is listed.
        objects.reversed().forEach { add($0, depth: 0) }
        return result
    }

    /// A name Wallpaper Engine gives in its own words, "ui_editor_properties_noise_speed", as a
    /// name to show: translated if it is a common one, else made readable — “Noise speed”. A
    /// name an author gave, “Bar Color”, is shown as it is.
    static func title(of name: String, prefix: String, suffix: String, table: String) -> String {
        var key = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard key.hasPrefix(prefix) else { return name }
        key.removeFirst(prefix.count)
        if !suffix.isEmpty, key.hasSuffix(suffix) {
            key.removeLast(suffix.count)
        }
        let localizationKey = "\(table).\(key)"
        let localized = NSLocalizedString(localizationKey, comment: "A name Wallpaper Engine gives an effect or a value of one")
        if localized != localizationKey {
            return localized
        }
        let words = key.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

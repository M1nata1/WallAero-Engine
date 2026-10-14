import Foundation

/// A wallpaper put together from a background and layers on top of it — text, pictures, shapes
/// and free-form web code. It is stored as `scene.json` in the wallpaper's folder and drawn by
/// the web runtime (`SceneProject`), so everything the editor makes is plain HTML in the end.
///
/// Positions and sizes are percentages of the screen and lengths are pixels of a 1080-pixel-high
/// screen, so a scene looks the same on every display.
public struct WallpaperScene: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var background: Background
    public var layers: [Layer]
    /// What the scene lets be changed without the editor, see `Variable`.
    public var variables: [Variable]

    public init(background: Background = Background(), layers: [Layer] = [], variables: [Variable] = []) {
        version = Self.currentVersion
        self.background = background
        self.layers = layers
        self.variables = variables
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = values.value(.version, or: Self.currentVersion)
        background = values.value(.background, or: Background())
        layers = values.value(.layers, or: [])
        variables = values.value(.variables, or: [])
    }

    /// A key no other variable of the scene has: the wanted one, or it with a number added.
    public func uniqueKey(_ wanted: String, for id: UUID? = nil) -> String {
        let base = Variable.key(from: wanted)
        let taken = Set(variables.filter { $0.id != id }.map(\.key))
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base)\(number)") {
            number += 1
        }
        return "\(base)\(number)"
    }

    // MARK: - Background

    public struct Background: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, CaseIterable, Sendable {
            case video, image, color
            /// A web page of its own, kept in the scene's folder — a wallpaper made for
            /// Wallpaper Engine, for one. It draws itself; the scene's layers go on top of it.
            case page
            /// One of Wallpaper Engine's own scenes, laid out in the scene's folder and played
            /// by the page; see `WallpaperEngineScene`. The scene's layers go on top of it.
            case engine
        }

        public enum Fit: String, Codable, CaseIterable, Sendable {
            /// Fills the screen, cropping the edges.
            case cover
            /// Shows the whole picture with bars around it.
            case contain
            /// Stretches to the screen.
            case fill
        }

        public var kind: Kind
        /// The video, the picture or the page, relative to the wallpaper's folder.
        public var source: String?
        /// Shown behind the media and wherever it does not reach.
        public var color: String
        public var fit: Fit
        /// Which part stays in view when covering the screen crops the media, in percent:
        /// 0 keeps the left or the top, 100 the right or the bottom.
        public var position: Double
        /// In pixels of a 1080-pixel-high screen.
        public var blur: Double
        /// Percent; 100 leaves the picture as it is.
        public var brightness: Double
        public var contrast: Double
        public var saturation: Double
        /// Degrees around the colour wheel.
        public var hue: Double
        /// What the editor has changed in the scene of Wallpaper Engine's, for `engine`.
        public var engine: EngineChanges

        public init(kind: Kind = .color, source: String? = nil, color: String = "#000000", fit: Fit = .cover,
                    position: Double = 50, blur: Double = 0, brightness: Double = 100, contrast: Double = 100,
                    saturation: Double = 100, hue: Double = 0, engine: EngineChanges = EngineChanges()) {
            self.kind = kind
            self.source = source
            self.color = color
            self.fit = fit
            self.position = position
            self.blur = blur
            self.brightness = brightness
            self.contrast = contrast
            self.saturation = saturation
            self.hue = hue
            self.engine = engine
        }

        /// Whether the background is a video or a picture: a file that can be chosen.
        public var isMedia: Bool { kind == .video || kind == .image }

        /// Whether the background has a size of its own and so has to be fitted to the screen:
        /// a video, a picture, a scene of Wallpaper Engine's. A color has nothing to fit, and a
        /// page lays itself out.
        public var isFitted: Bool { isMedia || kind == .engine }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = Background()
            kind = values.value(.kind, or: defaults.kind)
            source = try? values.decodeIfPresent(String.self, forKey: .source)
            color = values.value(.color, or: defaults.color)
            fit = values.value(.fit, or: defaults.fit)
            position = values.value(.position, or: defaults.position)
            blur = values.value(.blur, or: defaults.blur)
            brightness = values.value(.brightness, or: defaults.brightness)
            contrast = values.value(.contrast, or: defaults.contrast)
            saturation = values.value(.saturation, or: defaults.saturation)
            hue = values.value(.hue, or: defaults.hue)
            engine = values.value(.engine, or: defaults.engine)
        }

        private enum CodingKeys: String, CodingKey {
            case kind, source, color, fit, position, blur, brightness, contrast, saturation, hue, engine
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(kind, forKey: .kind)
            try values.encodeIfPresent(source, forKey: .source)
            try values.encode(color, forKey: .color)
            try values.encode(fit, forKey: .fit)
            try values.encode(position, forKey: .position)
            try values.encode(blur, forKey: .blur)
            try values.encode(brightness, forKey: .brightness)
            try values.encode(contrast, forKey: .contrast)
            try values.encode(saturation, forKey: .saturation)
            try values.encode(hue, forKey: .hue)
            // Only a scene with changes says so.
            if !engine.isEmpty {
                try values.encode(engine, forKey: .engine)
            }
        }
    }

    // MARK: - Changes to a scene of Wallpaper Engine's

    /// What the editor has changed in one of Wallpaper Engine's scenes played as the background.
    /// The scene's own files stay as they came; the player puts these changes over what they
    /// say. A value left nil is the scene's own.
    public struct EngineChanges: Codable, Equatable, Sendable {
        /// Whether the scene moves with the pointer, as through a window, and how much.
        public var parallax: Bool?
        public var parallaxAmount: Double?
        /// Whether what is bright glows, and how strongly.
        public var bloom: Bool?
        public var bloomStrength: Double?
        public var objects: [ObjectChange]

        public init(parallax: Bool? = nil, parallaxAmount: Double? = nil, bloom: Bool? = nil, bloomStrength: Double? = nil,
                    objects: [ObjectChange] = []) {
            self.parallax = parallax
            self.parallaxAmount = parallaxAmount
            self.bloom = bloom
            self.bloomStrength = bloomStrength
            self.objects = objects
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            parallax = try? values.decodeIfPresent(Bool.self, forKey: .parallax)
            parallaxAmount = try? values.decodeIfPresent(Double.self, forKey: .parallaxAmount)
            bloom = try? values.decodeIfPresent(Bool.self, forKey: .bloom)
            bloomStrength = try? values.decodeIfPresent(Double.self, forKey: .bloomStrength)
            objects = values.value(.objects, or: [])
        }

        public var isEmpty: Bool {
            parallax == nil && parallaxAmount == nil && bloom == nil && bloomStrength == nil && objects.allSatisfy(\.isEmpty)
        }

        /// The change to one object; one with nothing changed when there is none. Set, it
        /// takes the place of the one there was; one with nothing changed is dropped.
        public subscript(object id: Int) -> ObjectChange {
            get { objects.first { $0.id == id } ?? ObjectChange(id: id) }
            set {
                let index = objects.firstIndex { $0.id == id }
                if newValue.isEmpty {
                    if let index { objects.remove(at: index) }
                } else if let index {
                    objects[index] = newValue
                } else {
                    objects.append(newValue)
                }
            }
        }
    }

    /// What the editor has changed of one object of the scene: a picture, a text, particles,
    /// a sound or what holds others together.
    public struct ObjectChange: Codable, Equatable, Identifiable, Sendable {
        /// The number the scene knows the object by.
        public var id: Int
        public var isVisible: Bool?
        /// Where its middle is, in pixels of the scene from its bottom left corner, or from the
        /// middle of the object it hangs on.
        public var x: Double?
        public var y: Double?
        /// 1 is the size the scene gives it.
        public var scaleX: Double?
        public var scaleY: Double?
        /// Degrees, clockwise, as the scene's own layers turn.
        public var rotation: Double?
        /// Percent.
        public var opacity: Double?
        /// "#RRGGBB": what the object is tinted with, or a text's color.
        public var color: String?
        public var text: String?
        /// In Wallpaper Engine's points.
        public var fontSize: Double?
        /// Percent, for a sound.
        public var volume: Double?
        /// For particles, percent of what the system itself makes: how many there may be, how
        /// many are made each second, how fast they fly, how large they are, how long they live
        /// and how see-through they are.
        public var particleCount: Double?
        public var particleRate: Double?
        public var particleSpeed: Double?
        public var particleSize: Double?
        public var particleLifetime: Double?
        public var particleOpacity: Double?
        /// "#RRGGBB": the one color all the particles are.
        public var particleColor: String?
        public var effects: [EffectChange]

        public init(id: Int) {
            self.id = id
            effects = []
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(Int.self, forKey: .id)
            func optional<T: Decodable>(_ key: CodingKeys) -> T? {
                (try? values.decodeIfPresent(T.self, forKey: key)) ?? nil
            }
            isVisible = optional(.isVisible)
            x = optional(.x)
            y = optional(.y)
            scaleX = optional(.scaleX)
            scaleY = optional(.scaleY)
            rotation = optional(.rotation)
            opacity = optional(.opacity)
            color = optional(.color)
            text = optional(.text)
            fontSize = optional(.fontSize)
            volume = optional(.volume)
            particleCount = optional(.particleCount)
            particleRate = optional(.particleRate)
            particleSpeed = optional(.particleSpeed)
            particleSize = optional(.particleSize)
            particleLifetime = optional(.particleLifetime)
            particleOpacity = optional(.particleOpacity)
            particleColor = optional(.particleColor)
            effects = values.value(.effects, or: [])
        }

        /// Whether nothing of the object is changed.
        public var isEmpty: Bool {
            var bare = self
            bare.effects = effects.filter { !$0.isEmpty }
            return bare == ObjectChange(id: id)
        }

        /// The change to one of its effects, by its place among them; as `EngineChanges[object:]`.
        public subscript(effect index: Int) -> EffectChange {
            get { effects.first { $0.id == index } ?? EffectChange(id: index) }
            set {
                let found = effects.firstIndex { $0.id == index }
                if newValue.isEmpty {
                    if let found { effects.remove(at: found) }
                } else if let found {
                    effects[found] = newValue
                } else {
                    effects.append(newValue)
                    effects.sort { $0.id < $1.id }
                }
            }
        }
    }

    /// What the editor has changed of one effect on an object.
    public struct EffectChange: Codable, Equatable, Identifiable, Sendable {
        /// Its place among the object's effects, from 0.
        public var id: Int
        public var isVisible: Bool?
        /// The effect's values, by the names its material gives them: one number, or several
        /// for a point or a color (red, green and blue from 0 to 1).
        public var values: [String: [Double]]

        public init(id: Int) {
            self.id = id
            values = [:]
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(Int.self, forKey: .id)
            isVisible = (try? values.decodeIfPresent(Bool.self, forKey: .isVisible)) ?? nil
            self.values = values.value(.values, or: [:])
        }

        public var isEmpty: Bool { isVisible == nil && values.isEmpty }
    }

    // MARK: - Layers

    /// One thing on top of the background. Every kind shares the placement and the look; the rest
    /// of the fields belong to one kind each and are ignored by the others.
    public struct Layer: Codable, Equatable, Identifiable, Sendable {
        public enum Kind: String, Codable, CaseIterable, Sendable {
            case text, image, shape, code
        }

        public var id: UUID
        public var kind: Kind
        public var name: String
        public var isVisible: Bool
        /// Whether the layer is part of the still picture macOS shows on the lock screen and in
        /// Mission Control. A clock is better left out of it: it would stand still there.
        public var showsOnLockScreen: Bool

        /// The centre, in percent of the screen.
        public var x: Double
        public var y: Double
        /// In percent of the screen's width. Text wraps at it; pictures keep their proportions.
        public var width: Double
        /// In percent of the screen's height; used by shapes and code.
        public var height: Double
        public var rotation: Double
        /// Percent.
        public var opacity: Double
        /// A CSS `mix-blend-mode`.
        public var blendMode: String
        /// "none", "pulse", "float", "spin" or "blink".
        public var animation: String
        /// Seconds for one round of the animation.
        public var animationDuration: Double
        public var shadowColor: String
        /// Zero means no shadow.
        public var shadowBlur: Double
        public var shadowX: Double
        public var shadowY: Double

        // Text. `{HH}`, `{mm}`, `{weekday}`, `{date}` and the like are replaced with the time and
        // date; the runtime has the full list.
        public var text: String
        public var fontFamily: String
        /// In percent of the screen's height.
        public var fontSize: Double
        public var fontWeight: Int
        public var isItalic: Bool
        public var color: String
        /// "left", "center" or "right".
        public var alignment: String
        /// In ems.
        public var letterSpacing: Double
        public var lineHeight: Double

        // Image: a file relative to the wallpaper's folder.
        public var source: String

        // Shape.
        /// "rectangle" or "ellipse".
        public var shape: String
        public var fill: String
        public var cornerRadius: Double
        public var borderColor: String
        public var borderWidth: Double

        // Code: anything the web can do, placed in the layer's box.
        public var html: String
        public var css: String
        public var javaScript: String

        public init(kind: Kind, name: String, id: UUID = UUID()) {
            self.id = id
            self.kind = kind
            self.name = name
            isVisible = true
            showsOnLockScreen = true
            x = 50
            y = 50
            width = kind == .text ? 60 : 30
            height = 30
            rotation = 0
            opacity = 100
            blendMode = "normal"
            animation = "none"
            animationDuration = 4
            shadowColor = "#00000099"
            shadowBlur = kind == .text ? 12 : 0
            shadowX = 0
            shadowY = 0
            text = "{HH}:{mm}"
            fontFamily = "-apple-system"
            fontSize = 12
            fontWeight = 700
            isItalic = false
            color = "#FFFFFF"
            alignment = "center"
            letterSpacing = 0
            lineHeight = 1.1
            source = ""
            shape = "rectangle"
            fill = "#FFFFFF33"
            cornerRadius = 24
            borderColor = "#FFFFFF"
            borderWidth = 0
            html = ""
            css = ""
            javaScript = ""
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try values.decode(Kind.self, forKey: .kind)
            let defaults = Layer(kind: kind, name: kind.rawValue.capitalized)
            id = values.value(.id, or: defaults.id)
            self.kind = kind
            name = values.value(.name, or: defaults.name)
            isVisible = values.value(.isVisible, or: defaults.isVisible)
            showsOnLockScreen = values.value(.showsOnLockScreen, or: defaults.showsOnLockScreen)
            x = values.value(.x, or: defaults.x)
            y = values.value(.y, or: defaults.y)
            width = values.value(.width, or: defaults.width)
            height = values.value(.height, or: defaults.height)
            rotation = values.value(.rotation, or: defaults.rotation)
            opacity = values.value(.opacity, or: defaults.opacity)
            blendMode = values.value(.blendMode, or: defaults.blendMode)
            animation = values.value(.animation, or: defaults.animation)
            animationDuration = values.value(.animationDuration, or: defaults.animationDuration)
            shadowColor = values.value(.shadowColor, or: defaults.shadowColor)
            shadowBlur = values.value(.shadowBlur, or: defaults.shadowBlur)
            shadowX = values.value(.shadowX, or: defaults.shadowX)
            shadowY = values.value(.shadowY, or: defaults.shadowY)
            text = values.value(.text, or: defaults.text)
            fontFamily = values.value(.fontFamily, or: defaults.fontFamily)
            fontSize = values.value(.fontSize, or: defaults.fontSize)
            fontWeight = values.value(.fontWeight, or: defaults.fontWeight)
            isItalic = values.value(.isItalic, or: defaults.isItalic)
            color = values.value(.color, or: defaults.color)
            alignment = values.value(.alignment, or: defaults.alignment)
            letterSpacing = values.value(.letterSpacing, or: defaults.letterSpacing)
            lineHeight = values.value(.lineHeight, or: defaults.lineHeight)
            source = values.value(.source, or: defaults.source)
            shape = values.value(.shape, or: defaults.shape)
            fill = values.value(.fill, or: defaults.fill)
            cornerRadius = values.value(.cornerRadius, or: defaults.cornerRadius)
            borderColor = values.value(.borderColor, or: defaults.borderColor)
            borderWidth = values.value(.borderWidth, or: defaults.borderWidth)
            html = values.value(.html, or: defaults.html)
            css = values.value(.css, or: defaults.css)
            javaScript = values.value(.javaScript, or: defaults.javaScript)
        }
    }
}

extension WallpaperScene {
    /// A value the scene's author has put up for changing without the editor. It shows in the
    /// wallpaper's settings under its title, and the scene reads it by its key: `var(--key)` in
    /// CSS, `wallaero.variables.key` in JavaScript, `{key}` in the text of a text layer.
    public struct Variable: Codable, Equatable, Identifiable, Sendable {
        public enum Kind: String, Codable, CaseIterable, Sendable {
            case color, number, toggle, text, choice
        }

        public var id: UUID
        public var kind: Kind
        /// What the setting is called in the wallpaper's settings.
        public var title: String
        /// The name the scene's code knows it by: letters, digits and underscores.
        public var key: String

        // The value is in the field of the variable's kind; the others are ignored.
        public var color: String
        public var number: Double
        public var minimum: Double
        public var maximum: Double
        public var step: Double
        public var isOn: Bool
        /// The text, or the chosen one of `options` for a choice.
        public var text: String
        public var options: [String]

        // A scene whose background is a page made for Wallpaper Engine has the page's own
        // settings among its variables. The page is told their values, each under the name it
        // knows the setting by, in the form Wallpaper Engine would hand it over.
        /// That name; nil for a variable of the scene's own.
        public var property: String?
        /// For such a choice, what the page is given for each of `options`.
        public var values: [OptionValue]?

        /// A value of one of the kinds Wallpaper Engine lets an option of a choice have.
        public enum OptionValue: Codable, Equatable, Sendable {
            case text(String)
            case number(Double)
            case flag(Bool)

            public init(from decoder: Decoder) throws {
                let value = try decoder.singleValueContainer()
                if let flag = try? value.decode(Bool.self) {
                    self = .flag(flag)
                } else if let number = try? value.decode(Double.self) {
                    self = .number(number)
                } else {
                    self = .text(try value.decode(String.self))
                }
            }

            public func encode(to encoder: Encoder) throws {
                var value = encoder.singleValueContainer()
                switch self {
                case .text(let text): try value.encode(text)
                case .number(let number): try value.encode(number)
                case .flag(let flag): try value.encode(flag)
                }
            }
        }

        public init(kind: Kind, title: String, key: String, id: UUID = UUID()) {
            self.id = id
            self.kind = kind
            self.title = title
            self.key = key
            color = "#FFFFFF"
            number = 50
            minimum = 0
            maximum = 100
            step = 1
            isOn = true
            text = ""
            options = []
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try values.decode(Kind.self, forKey: .kind)
            let defaults = Variable(kind: kind, title: "", key: "variable")
            id = values.value(.id, or: defaults.id)
            self.kind = kind
            key = Self.key(from: values.value(.key, or: defaults.key))
            title = values.value(.title, or: key)
            color = values.value(.color, or: defaults.color)
            number = values.value(.number, or: defaults.number)
            minimum = values.value(.minimum, or: defaults.minimum)
            maximum = values.value(.maximum, or: defaults.maximum)
            step = values.value(.step, or: defaults.step)
            isOn = values.value(.isOn, or: defaults.isOn)
            text = values.value(.text, or: defaults.text)
            options = values.value(.options, or: defaults.options)
            property = try? values.decodeIfPresent(String.self, forKey: .property)
            self.values = try? values.decodeIfPresent([OptionValue].self, forKey: .values)
        }

        /// Any text made into a key that CSS, JavaScript and a text layer all accept: Latin
        /// letters, digits and underscores, not starting with a digit. "цвет полос" becomes
        /// "cvet_polos".
        public static func key(from text: String) -> String {
            let latin = text.applyingTransform(.toLatin, reverse: false)?
                .applyingTransform(.stripDiacritics, reverse: false) ?? text
            var key = ""
            for scalar in latin.unicodeScalars {
                let isLetter = ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
                let isDigit = ("0"..."9").contains(scalar)
                if isLetter || isDigit || scalar == "_" {
                    key.unicodeScalars.append(scalar)
                } else if !key.isEmpty, !key.hasSuffix("_") {
                    key.append("_")
                }
            }
            while key.hasSuffix("_") {
                key.removeLast()
            }
            if key.isEmpty {
                return "variable"
            }
            return key.first!.isNumber ? "_" + key : key
        }
    }
}

private extension KeyedDecodingContainer {
    /// A scene file written by hand, or by another version of the app, may lack keys or hold a
    /// value of the wrong type; either way the default stands in rather than the scene failing.
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

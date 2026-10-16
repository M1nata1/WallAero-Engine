import CoreGraphics
import Foundation

/// New objects of a scene, made the way Wallpaper Engine's editor makes them.
extension WallpaperEngineDocument {
    /// Where a new object goes: the middle of the scene.
    private var middle: JSONValue {
        .vector([Double(size.width) / 2, Double(size.height) / 2, 0])
    }

    /// What every object that is drawn starts with.
    private func base(id: Int, name: String) -> [String: JSONValue] {
        [
            "id": .number(Double(id)),
            "name": .string(name),
            "origin": middle,
            "scale": .vector([1, 1, 1]),
            "angles": .vector([0, 0, 0]),
            "visible": .bool(true),
            "parallaxDepth": .vector([1, 1]),
        ]
    }

    private mutating func append(_ object: [String: JSONValue], under parent: Int?) -> Int {
        var object = object
        if let parent {
            object["parent"] = .number(Double(parent))
            // What hangs on another is placed from it: in its middle.
            object["origin"] = .vector([0, 0, 0])
        }
        objects.append(.object(object))
        return Int(object["id"]?.numberValue ?? 0)
    }

    /// A picture: a model drawn with a material that shows the texture.
    /// - Parameter texture: the texture's name as materials give it.
    @discardableResult
    public mutating func addImage(texture: String, width: Int, height: Int, name: String, under parent: Int? = nil) -> Int {
        let model = "models/\(texture).json"
        let material = "materials/\(texture).json"
        setFile(material, .object(["passes": .array([.object([
            "blending": .string("translucent"),
            "cullmode": .string("nocull"),
            "depthtest": .string("disabled"),
            "depthwrite": .string("disabled"),
            "shader": .string("genericimage2"),
            "textures": .array([.string(texture)]),
        ])])]))
        setFile(model, .object(["autosize": .bool(true), "material": .string(material)]))
        let id = newID()
        var object = base(id: id, name: name)
        object["image"] = .string(model)
        object["size"] = .vector([Double(width), Double(height)])
        object["alpha"] = .number(1)
        object["color"] = .vector([1, 1, 1])
        object["colorBlendMode"] = .number(0)
        object["copybackground"] = .bool(true)
        object["alignment"] = .string("center")
        object["effects"] = .array([])
        object["solid"] = .bool(true)
        // A picture larger than the scene is made to fill it.
        let fits = min(Double(size.width) / Double(max(width, 1)), Double(size.height) / Double(max(height, 1)))
        if fits < 1, parent == nil {
            let cover = max(Double(size.width) / Double(max(width, 1)), Double(size.height) / Double(max(height, 1)))
            object["scale"] = .vector([cover, cover, 1])
        }
        return append(object, under: parent)
    }

    /// A rectangle of one color, as large as given.
    @discardableResult
    public mutating func addSolid(color: [Double], width: Double, height: Double, name: String, under parent: Int? = nil) -> Int {
        let id = newID()
        var object = base(id: id, name: name)
        object["image"] = .string("models/util/solidlayer.json")
        object["size"] = .vector([width, height])
        object["color"] = .vector(Array(color.prefix(3)))
        object["alpha"] = .number(1)
        object["colorBlendMode"] = .number(0)
        object["alignment"] = .string("center")
        object["effects"] = .array([])
        object["solid"] = .bool(true)
        return append(object, under: parent)
    }

    /// A layer that holds others, which are drawn into it, so that its effects work on them
    /// together.
    @discardableResult
    public mutating func addComposition(name: String, under parent: Int? = nil) -> Int {
        let id = newID()
        var object = base(id: id, name: name)
        object["image"] = .string("models/util/composelayer.json")
        object["size"] = .vector([Double(size.width), Double(size.height)])
        object["alpha"] = .number(1)
        object["color"] = .vector([1, 1, 1])
        object["config"] = .object(["passthrough": .bool(false)])
        object["effects"] = .array([])
        return append(object, under: parent)
    }

    /// A text, in a font of the system or one of the project's fonts.
    @discardableResult
    public mutating func addText(_ text: String, font: String = "systemfont_arial", pointSize: Double = 64, name: String,
                                 under parent: Int? = nil) -> Int {
        let id = newID()
        var object = base(id: id, name: name)
        object["text"] = .object(["value": .string(text)])
        object["font"] = .string(font)
        object["pointsize"] = .number(pointSize)
        object["horizontalalign"] = .string("center")
        object["verticalalign"] = .string("center")
        object["anchor"] = .string("none")
        object["color"] = .vector([1, 1, 1])
        object["alpha"] = .number(1)
        object["brightness"] = .number(1)
        object["padding"] = .number(32)
        object["backgroundcolor"] = .vector([0, 0, 0])
        object["backgroundbrightness"] = .number(1)
        object["opaquebackground"] = .bool(false)
        object["limitrows"] = .bool(false)
        object["limitwidth"] = .bool(false)
        object["maxrows"] = .number(1)
        object["maxwidth"] = .number(500)
        object["effects"] = .array([])
        return append(object, under: parent)
    }

    /// A sound that plays over and over.
    @discardableResult
    public mutating func addSound(_ file: String, name: String) -> Int {
        let id = newID()
        var object = base(id: id, name: name)
        object["sound"] = .array([.string(file)])
        object["playbackmode"] = .string("loop")
        object["volume"] = .number(1)
        object["mintime"] = .number(0)
        object["maxtime"] = .number(10)
        object["startsilent"] = .bool(false)
        return append(object, under: nil)
    }

    /// An object that only holds others together, to move them as one.
    @discardableResult
    public mutating func addGroup(name: String, under parent: Int? = nil) -> Int {
        let id = newID()
        return append(base(id: id, name: name), under: parent)
    }

    /// A system of particles, described by `file` in the project.
    @discardableResult
    public mutating func addParticles(file: String, name: String, under parent: Int? = nil) -> Int {
        let id = newID()
        var object = base(id: id, name: name)
        object["particle"] = .string(file)
        object["instanceoverride"] = .object([:])
        return append(object, under: parent)
    }

    /// Scales an object of the given size so that it covers the whole scene, in its middle.
    public mutating func cover(_ id: Int, width: Int, height: Int) {
        let scale = max(Double(size.width) / Double(max(width, 1)), Double(size.height) / Double(max(height, 1)))
        let middle = self.middle
        update(id) { object in
            object["scale"] = .vector([scale, scale, 1])
            object["origin"] = middle
        }
    }

    /// A copy of an object, a little to the side, with new numbers for it and its effects.
    @discardableResult
    public mutating func duplicate(_ id: Int) -> Int? {
        guard var copy = object(id) else { return nil }
        var next = newID()
        func renumber(_ value: JSONValue) -> JSONValue {
            switch value {
            case .object(var dictionary):
                if dictionary["id"] != nil {
                    dictionary["id"] = .number(Double(next))
                    next += 1
                }
                for (key, inner) in dictionary where key != "id" {
                    dictionary[key] = renumber(inner)
                }
                return .object(dictionary)
            case .array(let array):
                return .array(array.map(renumber))
            default:
                return value
            }
        }
        copy = renumber(copy)
        if let origin = copy["origin"]?.vector, origin.count >= 2 {
            copy["origin"] = copy["origin"]!.replacingPlain(with: .vector([origin[0] + 40, origin[1] - 40] + origin.dropFirst(2)))
        }
        if let name = copy["name"]?.stringValue {
            copy["name"] = .string(name + " " + NSLocalizedString("copy", comment: "Suffix of a duplicated object's name"))
        }
        var all = objects
        let index = all.firstIndex { $0["id"]?.numberValue == Double(id) } ?? all.count - 1
        all.insert(copy, at: index + 1)
        objects = all
        return copy["id"]?.numberValue.map { Int($0) }
    }
}

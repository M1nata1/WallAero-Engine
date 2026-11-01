import CoreGraphics
import Foundation
import ImageIO

/// A scene of Wallpaper Engine's as the editor has it: the project, the scene and the other
/// JSON files of its folder — models, materials, particles, effects — as values that can be
/// changed and taken back. The pictures, sounds, fonts, shaders and puppets stay files in the
/// folder; the JSON names them.
///
/// The folder is a Wallpaper Engine project as Wallpaper Engine's own editor leaves one, so it
/// can be opened there as it is.
public struct WallpaperEngineDocument: Equatable, Sendable {
    /// `project.json`: the title, the preview, the settings of the wallpaper.
    public var project: JSONValue
    /// `scene.json`: the camera, the scene's general values and its objects.
    public var scene: JSONValue
    /// The other JSON files, by their names in the folder.
    public var files: [String: JSONValue]
    /// The rigs of the scene's puppets being edited, by the names of their files. They are only
    /// here once `loadRigs` took them in.
    public var rigs: [String: WallpaperEnginePuppetRig] = [:]

    public static let sceneFileName = "scene.json"

    public init(project: JSONValue, scene: JSONValue, files: [String: JSONValue] = [:]) {
        self.project = project
        self.scene = scene
        self.files = files
    }

    // MARK: - A new scene

    /// An empty scene of the given size, in pixels.
    public static func empty(title: String, width: Int, height: Int) -> WallpaperEngineDocument {
        let project: JSONValue = .object([
            "file": .string(sceneFileName),
            "type": .string("scene"),
            "title": .string(title),
            "preview": .string("preview.jpg"),
            "version": .number(0),
            "general": .object(["properties": .object([
                "schemecolor": .object(["order": .number(0), "text": .string("ui_browse_properties_scheme_color"),
                                        "type": .string("color"), "value": .string("0 0 0")]),
            ])]),
        ])
        let scene: JSONValue = .object([
            "camera": .object([
                "center": .vector([0, 0, -1]),
                "eye": .vector([0, 0, 0]),
                "up": .vector([0, 1, 0]),
            ]),
            "general": .object([
                "ambientcolor": .vector([0.3, 0.3, 0.3]),
                "bloom": .bool(false),
                "bloomstrength": .number(2),
                "bloomthreshold": .number(0.65),
                "camerafade": .bool(true),
                "cameraparallax": .bool(false),
                "cameraparallaxamount": .number(0.5),
                "cameraparallaxdelay": .number(0.1),
                "cameraparallaxmouseinfluence": .number(0),
                "camerapreview": .bool(true),
                "camerashake": .bool(false),
                "camerashakeamplitude": .number(0.5),
                "camerashakeroughness": .number(1),
                "camerashakespeed": .number(3),
                "clearcolor": .vector([0, 0, 0]),
                "clearenabled": .bool(true),
                "farz": .number(10000),
                "fov": .number(50),
                "hdr": .bool(false),
                "nearz": .number(0.01),
                "orthogonalprojection": .object(["width": .number(Double(width)), "height": .number(Double(height))]),
                "skylightcolor": .vector([0.3, 0.3, 0.3]),
                "zoom": .number(1),
            ]),
            "objects": .array([]),
            "version": .number(4),
        ])
        return WallpaperEngineDocument(project: project, scene: scene)
    }

    // MARK: - The scene

    /// The size the scene is made at, in pixels.
    public var size: CGSize {
        get {
            let projection = scene["general"]?["orthogonalprojection"]
            return CGSize(width: projection?["width"]?.numberValue ?? 1920, height: projection?["height"]?.numberValue ?? 1080)
        }
        set {
            scene["general"]?["orthogonalprojection"] = .object(["width": .number(newValue.width.rounded()),
                                                                 "height": .number(newValue.height.rounded())])
        }
    }

    public var title: String {
        get { project["title"]?.stringValue ?? "" }
        set { project["title"] = .string(newValue) }
    }

    /// One of the scene's general values.
    public subscript(general key: String) -> JSONValue? {
        get { scene["general"]?[key] }
        set { scene["general"]?[key] = newValue }
    }

    public var objects: [JSONValue] {
        get { scene["objects"]?.arrayValue ?? [] }
        set { scene["objects"] = .array(newValue) }
    }

    /// The objects' numbers, in the order they are drawn: the one behind first.
    public var objectIDs: [Int] {
        objects.compactMap { $0["id"]?.numberValue.map { Int($0) } }
    }

    public func object(_ id: Int) -> JSONValue? {
        objects.first { $0["id"]?.numberValue == Double(id) }
    }

    /// Changes one object; nothing happens if the scene has none by that number.
    public mutating func update(_ id: Int, _ change: (inout JSONValue) -> Void) {
        var all = objects
        guard let index = all.firstIndex(where: { $0["id"]?.numberValue == Double(id) }) else { return }
        change(&all[index])
        objects = all
    }

    /// A number no object, effect or pass of the scene has yet.
    public func newID() -> Int {
        var highest = 0
        func look(_ value: JSONValue) {
            switch value {
            case .object(let dictionary):
                if let id = dictionary["id"]?.numberValue {
                    highest = max(highest, Int(id))
                }
                dictionary.values.forEach(look)
            case .array(let array):
                array.forEach(look)
            default:
                break
            }
        }
        look(scene)
        return highest + 1
    }

    /// The object an object hangs on, if it hangs on one.
    public func parent(of id: Int) -> Int? {
        object(id)?["parent"]?.numberValue.map { Int($0) }
    }

    /// The objects that hang on one, in the order they are drawn.
    public func children(of id: Int) -> [Int] {
        objects.compactMap { object in
            guard object["parent"]?.numberValue == Double(id) else { return nil }
            return object["id"]?.numberValue.map { Int($0) }
        }
    }

    /// Takes an object out of the scene, and the objects that hang on it with it.
    public mutating func remove(_ id: Int) {
        var gone: Set<Int> = [id]
        var grew = true
        while grew {
            grew = false
            for object in objects {
                guard let own = object["id"]?.numberValue.map({ Int($0) }), !gone.contains(own),
                      let parent = object["parent"]?.numberValue.map({ Int($0) }), gone.contains(parent)
                else {
                    continue
                }
                gone.insert(own)
                grew = true
            }
        }
        objects = objects.filter { object in
            guard let own = object["id"]?.numberValue.map({ Int($0) }) else { return true }
            return !gone.contains(own)
        }
    }

    /// Puts objects in a new order of drawing: the one behind first.
    public mutating func reorder(_ ids: [Int]) {
        let byID = Dictionary(objects.compactMap { object in object["id"]?.numberValue.map { (Int($0), object) } },
                              uniquingKeysWith: { first, _ in first })
        var ordered = ids.compactMap { byID[$0] }
        // Whatever the new order leaves out stays, at the end.
        let named = Set(ids)
        ordered += objects.filter { object in object["id"]?.numberValue.map { !named.contains(Int($0)) } ?? true }
        objects = ordered
    }

    // MARK: - Files

    /// A JSON file of the folder, by its name; Wallpaper Engine's names differ neither by case
    /// nor by the slash.
    public func file(_ name: String) -> JSONValue? {
        if let file = files[name] { return file }
        let wanted = Self.key(name)
        return files.first { Self.key($0.key) == wanted }?.value
    }

    public mutating func setFile(_ name: String, _ value: JSONValue?) {
        let wanted = Self.key(name)
        let existing = files.keys.first { Self.key($0) == wanted }
        files[existing ?? name] = value
    }

    static func key(_ name: String) -> String {
        name.replacingOccurrences(of: "\\", with: "/").lowercased().precomposedStringWithCanonicalMapping
    }

    /// The model a picture of the scene is drawn as, and the material of the model.
    public func material(ofObject id: Int) -> (name: String, value: JSONValue)? {
        guard let model = object(id)?["image"]?.plain.stringValue,
              let material = file(model)?["material"]?.stringValue,
              let value = file(material)
        else {
            return nil
        }
        return (material, value)
    }
}

// MARK: - Kinds of objects

extension WallpaperEngineDocument {
    /// What an object of a scene is.
    public enum ObjectKind: String, Sendable {
        case image, text, particles, sound, model, light, camera, solid, composition, fullscreen, group
    }

    public static func kind(of object: JSONValue) -> ObjectKind {
        if let image = object["image"]?.plain.stringValue {
            let name = key(image)
            if name.contains("solidlayer") { return .solid }
            if name.contains("composelayer") { return .composition }
            if name.contains("fullscreenlayer") || name.contains("projectlayer") { return .fullscreen }
            return .image
        }
        if let text = object["text"], !text.isNull { return .text }
        if let particle = object["particle"], !particle.isNull { return .particles }
        if let sound = object["sound"], !sound.isNull { return .sound }
        if let model = object["model"], !model.isNull { return .model }
        if let light = object["light"], !light.isNull { return .light }
        if let camera = object["camera"], !camera.isNull { return .camera }
        return .group
    }
}

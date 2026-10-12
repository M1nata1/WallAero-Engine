import CoreGraphics
import Foundation

/// Brings one of Wallpaper Engine's own scenes into a scene of this app.
///
/// Such a scene is a list of objects on a canvas — pictures with effects drawn by shaders,
/// particles, texts, sounds — described in files of Wallpaper Engine's own, with scripts that
/// move them and settings the user may change. They are not turned into anything else: the
/// scene's files are laid out in the `engine` folder of the wallpaper, and the page draws them
/// with a player of its own (`WallpaperEngineRuntime`), as the scene's background. What is done
/// here is what a page cannot do: the package is unpacked and the textures, kept in a format of
/// Wallpaper Engine's, become pictures a page can load.
///
///     engine/files.js    – the scene's text files, the list of its pictures, sounds and fonts,
///                          and its puppets: pictures that bend, with their bones and animations
///     engine/tex/        – the pictures
///     engine/sounds/     – the sounds
///     engine/fonts/      – the fonts its texts are written in
public enum WallpaperEngineScene {
    public static let folderName = "engine"
    public static let filesName = "files.js"

    /// What a scene has that the player does not play, as the number of its objects that have
    /// it. The wallpaper is shown without it, and the user is told.
    public struct LeftOut: Equatable, Sendable {
        /// Pictures bent by bones whose bones could not be read; they are shown still.
        public var animations = 0
        /// Objects of kinds that are not drawn: three-dimensional models, lights.
        public var objects = 0

        public var isEmpty: Bool { animations + objects == 0 }

        public init(animations: Int = 0, objects: Int = 0) {
            self.animations = animations
            self.objects = objects
        }
    }

    /// Lays the scene out in `folder/engine`. Throws when the scene has nothing to draw.
    static func export(_ package: WallpaperEnginePackage, into folder: URL) throws -> LeftOut {
        guard let description = package.json(named: "scene.json") else { throw ImportError.unreadable }
        let objects = (description["objects"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        guard objects.contains(where: { $0["image"] != nil || $0["particle"] != nil || $0["text"] != nil }) else {
            throw ImportError.noPicturesInScene
        }

        let files = FileManager.default
        let engine = folder.appendingPathComponent(folderName, isDirectory: true)
        let pictures = engine.appendingPathComponent("tex", isDirectory: true)
        let sounds = engine.appendingPathComponent("sounds", isDirectory: true)
        let fonts = engine.appendingPathComponent("fonts", isDirectory: true)
        try files.createDirectory(at: pictures, withIntermediateDirectories: true)

        var texts: [String: String] = [:]
        var textures: [String: Any] = [:]
        var soundFiles: [String: String] = [:]
        var fontFiles: [String: String] = [:]
        var puppets: [String: Any] = [:]
        var number = 0
        for name in package.names {
            let key = Self.key(name)
            let fileExtension = (key as NSString).pathExtension
            switch fileExtension {
            case "json", "vert", "frag", "h", "glsl":
                // A text file is small; one that is not is not what its name says.
                guard let data = package.data(named: name), data.count <= 4 * 1024 * 1024,
                      let text = String(data: data, encoding: .utf8)
                else {
                    continue
                }
                texts[key] = text
            case "tex":
                guard let data = package.data(named: name), let texture = WallpaperEngineTexture.texture(from: data) else { continue }
                var written: [[String: Any]] = []
                for picture in texture.pictures {
                    number += 1
                    // A PNG or JPEG the texture held is kept as it is; anything else is saved as PNG.
                    let fileName = "\(number).\(picture.file?.fileExtension ?? "png")"
                    if let file = picture.file {
                        try file.data.write(to: pictures.appendingPathComponent(fileName))
                    } else {
                        try Thumbnailer.writePNG(picture.image, to: pictures.appendingPathComponent(fileName))
                    }
                    written.append(["file": "\(folderName)/tex/\(fileName)", "width": picture.image.width, "height": picture.image.height])
                }
                var entry: [String: Any] = [
                    "pictures": written,
                    "channels": texture.channels.rawValue,
                    "clamp": texture.isClamped,
                    "smooth": texture.isSmooth,
                ]
                if !texture.frames.isEmpty {
                    entry["frames"] = texture.frames.map {
                        [$0.picture, $0.duration, $0.x, $0.y, $0.width, $0.widthY, $0.heightX, $0.height] as [Any]
                    }
                }
                // A material names a texture without its ending.
                textures[(key as NSString).deletingPathExtension] = entry
            case "mdl":
                // A picture that bends. One that cannot be read is shown as the plain picture.
                guard let data = package.data(named: name), let puppet = WallpaperEnginePuppet(data: data) else { continue }
                puppets[key] = puppet.table
            case "mp3", "wav", "ogg", "m4a", "aac", "flac":
                guard let data = package.data(named: name) else { continue }
                try files.createDirectory(at: sounds, withIntermediateDirectories: true)
                number += 1
                let fileName = "\(number).\(fileExtension)"
                try data.write(to: sounds.appendingPathComponent(fileName))
                soundFiles[key] = "\(folderName)/sounds/\(fileName)"
            case "ttf", "otf", "ttc", "woff", "woff2":
                guard let data = package.data(named: name) else { continue }
                try files.createDirectory(at: fonts, withIntermediateDirectories: true)
                number += 1
                let fileName = "\(number).\(fileExtension)"
                try data.write(to: fonts.appendingPathComponent(fileName))
                fontFiles[key] = "\(folderName)/fonts/\(fileName)"
            default:
                continue
            }
        }

        // The files go to the page as a script: a page opened from a file may load a script of
        // its folder, while reading a file takes a setting pages do not always have. What the
        // scene's files say is only ever data there — texts in a table.
        let table: [String: Any] = ["files": texts, "textures": textures, "sounds": soundFiles, "fonts": fontFiles, "puppets": puppets]
        let json = try JSONSerialization.data(withJSONObject: table, options: [.sortedKeys])
        var script = Data("window.wallaeroEngineScene = ".utf8)
        script.append(json)
        script.append(Data(";\n".utf8))
        try script.write(to: engine.appendingPathComponent(filesName), options: .atomic)

        return leftOut(of: objects, in: package, puppets: Set(puppets.keys))
    }

    /// The name a file of the scene is known by: Wallpaper Engine is a Windows program, where
    /// names differ neither by case nor by the slash.
    static func key(_ name: String) -> String {
        name.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    // MARK: - Settings

    /// The names of the wallpaper's settings the scene makes use of. A value of a scene that a
    /// setting stands behind says so next to it: `{"user": "name", "value": …}`, or with the
    /// choice the setting has to be at, `{"user": {"name": "name", "condition": "2"}, …}`.
    /// A script may ask for any setting by its name; then the name is in the script's text.
    static func settingNames(in package: WallpaperEnginePackage, among names: [String]) -> Set<String> {
        guard let description = package.json(named: "scene.json") else { return [] }
        var used: Set<String> = []
        var scripts: [String] = []
        func look(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                if let name = dictionary["user"] as? String {
                    used.insert(name)
                } else if let name = (dictionary["user"] as? [String: Any])?["name"] as? String {
                    used.insert(name)
                }
                if let script = dictionary["script"] as? String {
                    scripts.append(script)
                }
                dictionary.values.forEach(look)
            } else if let array = value as? [Any] {
                array.forEach(look)
            }
        }
        look(description)
        for name in names where !used.contains(name) && scripts.contains(where: { $0.contains(name) }) {
            used.insert(name)
        }
        return used
    }

    // MARK: - What is not played

    private static func leftOut(of objects: [[String: Any]], in package: WallpaperEnginePackage, puppets: Set<String>) -> LeftOut {
        var leftOut = LeftOut()
        for object in objects {
            // What the scene itself keeps out of sight is not missed.
            if (object["visible"] as? Bool) == false || ((object["visible"] as? [String: Any])?["value"] as? Bool) == false {
                continue
            }
            if object["model"] != nil || object["light"] != nil {
                leftOut.objects += 1
                continue
            }
            // A picture bent by bones names them in its model; the bones are played when they
            // could be read.
            let puppet = ((object["image"] as? String).flatMap(package.json(named:))?["puppet"] as? String).map(key)
            if puppet.map({ !puppets.contains($0) }) == true {
                leftOut.animations += 1
            }
        }
        return leftOut
    }
}

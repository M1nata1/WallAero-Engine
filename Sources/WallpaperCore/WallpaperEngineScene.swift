import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

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
///     engine/tex/        – the pictures, and the videos that stand in place of pictures
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
        /// Objects that are not drawn: three-dimensional models whose shape could not be read.
        public var objects = 0

        public var isEmpty: Bool { animations + objects == 0 }

        public init(animations: Int = 0, objects: Int = 0) {
            self.animations = animations
            self.objects = objects
        }
    }

    /// Lays the scene out in `folder/engine`. Throws when the scene has nothing to draw.
    /// - Parameter chosen: the pictures chosen for the settings of the scene that take a
    ///   picture, by the settings' names.
    /// - Parameter allowEmpty: whether a scene with nothing to draw yet is laid out too: one
    ///   being made in the editor.
    static func export(_ package: WallpaperEnginePackage, into folder: URL, chosen: [String: URL] = [:], allowEmpty: Bool = false,
                       progress: (Double) -> Void = { _ in }) throws -> LeftOut {
        guard let description = package.json(named: "scene.json") else { throw ImportError.unreadable }
        let objects = (description["objects"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        guard allowEmpty || objects.contains(where: { has($0["image"]) || has($0["particle"]) || has($0["text"]) }) else {
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
        // Files are named after what is in them, so that laying a scene out again — the editor
        // does after every change — writes only what is new. What a texture was read as is kept
        // next to them, so that a picture is not read again either.
        let cacheURL = engine.appendingPathComponent(cacheName)
        let cache = ((try? Data(contentsOf: cacheURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        var newCache: [String: Any] = [:]
        func written(_ url: URL) -> Bool { files.fileExists(atPath: url.path) }
        for (index, name) in package.names.enumerated() {
            progress(Double(index) / Double(max(package.names.count, 1)))
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
                guard let data = package.data(named: name) else { continue }
                let digest = Self.digest(data)
                if let entry = cache[digest] as? [String: Any], Self.filesNamed(in: entry).allSatisfy({ written(folder.appendingPathComponent($0)) }) {
                    textures[(key as NSString).deletingPathExtension] = entry
                    newCache[digest] = entry
                    continue
                }
                guard let texture = WallpaperEngineTexture.texture(from: data) else { continue }
                if let video = texture.video {
                    let fileName = "\(digest).mp4"
                    if !written(pictures.appendingPathComponent(fileName)) {
                        try video.file.write(to: pictures.appendingPathComponent(fileName))
                    }
                    let entry: [String: Any] = [
                        "video": "\(folderName)/tex/\(fileName)", "width": video.width, "height": video.height,
                        "clamp": texture.isClamped, "smooth": texture.isSmooth,
                    ]
                    textures[(key as NSString).deletingPathExtension] = entry
                    newCache[digest] = entry
                    continue
                }
                var written: [[String: Any]] = []
                for (index, picture) in texture.pictures.enumerated() {
                    // A PNG or JPEG the texture held is kept as it is; anything else is saved as PNG.
                    let fileName = "\(digest)-\(index).\(picture.file?.fileExtension ?? "png")"
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
                if texture.maps != 0 { entry["maps"] = texture.maps }
                if !texture.frames.isEmpty {
                    entry["frames"] = texture.frames.map {
                        [$0.picture, $0.duration, $0.x, $0.y, $0.width, $0.widthY, $0.heightX, $0.height] as [Any]
                    }
                }
                // A material names a texture without its ending.
                textures[(key as NSString).deletingPathExtension] = entry
                newCache[digest] = entry
            case "mdl":
                // A picture that bends. One that cannot be read is shown as the plain picture.
                guard let data = package.data(named: name), let puppet = WallpaperEnginePuppet(data: data) else { continue }
                puppets[key] = puppet.table
            case "mp3", "wav", "ogg", "m4a", "aac", "flac":
                guard let data = package.data(named: name) else { continue }
                try files.createDirectory(at: sounds, withIntermediateDirectories: true)
                let fileName = "\(Self.digest(data)).\(fileExtension)"
                if !written(sounds.appendingPathComponent(fileName)) {
                    try data.write(to: sounds.appendingPathComponent(fileName))
                }
                soundFiles[key] = "\(folderName)/sounds/\(fileName)"
            case "ttf", "otf", "ttc", "woff", "woff2":
                guard let data = package.data(named: name) else { continue }
                try files.createDirectory(at: fonts, withIntermediateDirectories: true)
                let fileName = "\(Self.digest(data)).\(fileExtension)"
                if !written(fonts.appendingPathComponent(fileName)) {
                    try data.write(to: fonts.appendingPathComponent(fileName))
                }
                fontFiles[key] = "\(folderName)/fonts/\(fileName)"
            default:
                continue
            }
        }

        // A text may be written in a font Wallpaper Engine itself comes with rather than one of
        // the scene's; of those, the app brings the ones under an open license.
        for font in fontNames(in: description) where fontFiles[key(font)] == nil {
            guard let stock = stockFont(named: font), let data = try? Data(contentsOf: stock) else { continue }
            try files.createDirectory(at: fonts, withIntermediateDirectories: true)
            let fileName = "\(Self.digest(data)).\(stock.pathExtension.lowercased())"
            if !written(fonts.appendingPathComponent(fileName)) {
                try data.write(to: fonts.appendingPathComponent(fileName))
            }
            fontFiles[key(font)] = "\(folderName)/fonts/\(fileName)"
        }

        // A picture chosen for a setting is a texture like the scene's own, named after the setting.
        for (setting, file) in chosen.sorted(by: { $0.key < $1.key }) {
            number += 1
            if let texture = chosenTexture(from: file, numbered: number, in: pictures) {
                textures["user/\(setting.lowercased())"] = texture
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
        if let data = try? JSONSerialization.data(withJSONObject: newCache, options: [.sortedKeys]) {
            try? data.write(to: cacheURL, options: .atomic)
        }
        // What the scene no longer has goes, and the original of a video turned into WebM with it.
        let kept = Set(Self.filesNamed(in: table).map { (($0 as NSString).lastPathComponent) })
        for directory in [pictures, sounds, fonts] {
            for name in (try? files.contentsOfDirectory(atPath: directory.path)) ?? [] where !kept.contains(name) && !name.hasPrefix(".") {
                try? files.removeItem(at: directory.appendingPathComponent(name))
                let relative = "\(folderName)/\(directory.lastPathComponent)/\(name)"
                try? files.removeItem(at: folder.appendingPathComponent(WebMediaConverter.originalsFolderName).appendingPathComponent(relative))
            }
        }

        let solids = Set(puppets.filter { ($0.value as? [String: Any])?["solid"] != nil || ($0.value as? [String: Any])?["skinned"] != nil }.keys)
        return leftOut(of: objects, in: package, puppets: Set(puppets.keys), solids: solids)
    }

    /// Where what textures were read as is kept, in the `engine` folder.
    static let cacheName = "cache.json"

    /// A short name for what is in a file.
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(10).map { String(format: "%02x", $0) }.joined()
    }

    /// The files of the folder a table names: every text in it that starts with the `engine` folder.
    static func filesNamed(in value: Any) -> [String] {
        if let text = value as? String {
            return text.hasPrefix(folderName + "/") ? [text] : []
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.values.flatMap(filesNamed(in:))
        }
        if let array = value as? [Any] {
            return array.flatMap(filesNamed(in:))
        }
        return []
    }

    /// A picture chosen for a setting of the scene, as a texture: a picture is written out as
    /// one, a video is taken as it is, and a picture that moves becomes a video, as Wallpaper
    /// Engine itself makes of one. Nil when the file is neither.
    private static func chosenTexture(from file: URL, numbered number: Int, in pictures: URL) -> [String: Any]? {
        let kind = file.pathExtension.lowercased()
        func video(_ fileName: String, width: Int, height: Int) -> [String: Any] {
            ["video": "\(folderName)/tex/\(fileName)", "width": width, "height": height, "clamp": true, "smooth": true]
        }
        if ["mp4", "m4v", "mov", "webm"].contains(kind) {
            let fileName = "\(number).\(kind)"
            guard (try? FileManager.default.copyItem(at: file, to: pictures.appendingPathComponent(fileName))) != nil else { return nil }
            return video(fileName, width: 0, height: 0)
        }
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width <= WallpaperEngineTexture.longestSide, image.height <= WallpaperEngineTexture.longestSide
        else {
            return nil
        }
        if AnimatedImageConverter.isAnimated(source) {
            let fileName = "\(number).mov"
            if (try? AnimatedImageConverter.convertSynchronously(source: file, to: pictures.appendingPathComponent(fileName),
                                                                enlarging: false, progress: { _ in })) != nil {
                return video(fileName, width: image.width, height: image.height)
            }
        }
        let fileName = "\(number).png"
        guard (try? Thumbnailer.writePNG(image, to: pictures.appendingPathComponent(fileName))) != nil else { return nil }
        return ["pictures": [["file": "\(folderName)/tex/\(fileName)", "width": image.width, "height": image.height]],
                "channels": WallpaperEngineTexture.Channels.color.rawValue, "clamp": true, "smooth": true]
    }

    // MARK: - Fonts

    /// The folder of the fonts the app brings: in the app, or, for a build run from the
    /// sources, in the sources' resources.
    public static var stockFontsFolder: URL? = {
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent("Fonts", isDirectory: true),
                          URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Fonts", isDirectory: true)]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }()

    /// One of the fonts the app brings, by the name a scene gives it; nil if it has none such.
    static func stockFont(named name: String) -> URL? {
        guard let folder = stockFontsFolder,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        else {
            return nil
        }
        let wanted = (key(name) as NSString).lastPathComponent
        return names.first { $0.lowercased() == wanted }.map { folder.appendingPathComponent($0) }
    }

    /// The fonts the texts of a scene are written in, as the scene names them.
    static func fontNames(in description: [String: Any]) -> Set<String> {
        var names: Set<String> = []
        func look(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                if let font = dictionary["font"] as? String, !font.isEmpty {
                    names.insert(font)
                }
                dictionary.values.forEach(look)
            } else if let array = value as? [Any] {
                array.forEach(look)
            }
        }
        look(description)
        return names
    }

    /// Whether an object of a scene has something under a name. Scenes saved by early versions
    /// of Wallpaper Engine write every name an object may have, with nothing under most of
    /// them: a particle system with `"model": null` is no model.
    static func has(_ value: Any?) -> Bool {
        value != nil && !(value is NSNull)
    }

    /// The name a file of the scene is known by: Wallpaper Engine is a Windows program, where
    /// names differ neither by case nor by the slash — nor, here, by whether a letter's marks
    /// are written with it or apart, as the Mac writes the names of files.
    static func key(_ name: String) -> String {
        name.replacingOccurrences(of: "\\", with: "/").lowercased().precomposedStringWithCanonicalMapping
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

    private static func leftOut(of objects: [[String: Any]], in package: WallpaperEnginePackage, puppets: Set<String>, solids: Set<String>) -> LeftOut {
        var leftOut = LeftOut()
        for object in objects {
            // What the scene itself keeps out of sight is not missed.
            if (object["visible"] as? Bool) == false || ((object["visible"] as? [String: Any])?["value"] as? Bool) == false {
                continue
            }
            // A light is played; a model is when its shape could be read.
            if has(object["light"]) {
                continue
            }
            if has(object["model"]) {
                if !((object["model"] as? String).map({ solids.contains(key($0)) }) ?? false) {
                    leftOut.objects += 1
                }
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

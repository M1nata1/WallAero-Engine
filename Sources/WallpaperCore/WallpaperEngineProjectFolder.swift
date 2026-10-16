import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The folder of a Wallpaper Engine project the editor works on: reading it into a document,
/// writing what changed back, and bringing pictures, sounds and fonts into it in the form
/// Wallpaper Engine takes them.
public enum WallpaperEngineProjectFolder {
    /// Where in a scene of the app its Wallpaper Engine project is kept.
    public static let folderName = "project"

    public enum Problem: LocalizedError {
        case noScene
        case unreadablePicture

        public var errorDescription: String? {
            switch self {
            case .noScene:
                return NSLocalizedString("The folder holds no Wallpaper Engine scene.", comment: "Editor error")
            case .unreadablePicture:
                return NSLocalizedString("The picture cannot be read.", comment: "Editor error")
            }
        }
    }

    // MARK: - Reading and writing

    public static func read(from folder: URL) throws -> WallpaperEngineDocument {
        guard let scene = JSONValue(data: try Data(contentsOf: folder.appendingPathComponent(WallpaperEngineDocument.sceneFileName))),
              scene.objectValue != nil
        else {
            throw Problem.noScene
        }
        let project = (try? Data(contentsOf: folder.appendingPathComponent(WallpaperEngineProject.projectFileName)))
            .flatMap(JSONValue.init(data:)) ?? .object([:])
        var files: [String: JSONValue] = [:]
        for name in jsonFileNames(in: folder) {
            if let value = (try? Data(contentsOf: folder.appendingPathComponent(name))).flatMap(JSONValue.init(data:)) {
                files[name] = value
            }
        }
        return WallpaperEngineDocument(project: project, scene: scene, files: files)
    }

    /// The JSON files of the folder besides the project and the scene, by their names in it.
    static func jsonFileNames(in folder: URL) -> [String] {
        let root = folder.standardizedFileURL.resolvingSymlinksInPath().path
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                                        options: [.skipsHiddenFiles])
        var names: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "json" else { continue }
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard path.hasPrefix(root + "/") else { continue }
            let name = String(path.dropFirst(root.count + 1))
            if name == WallpaperEngineDocument.sceneFileName || name == WallpaperEngineProject.projectFileName { continue }
            names.append(name)
        }
        return names.sorted()
    }

    /// Writes the files of the document that differ from `previous` — all of them without
    /// one — and takes away the JSON files the document no longer has.
    public static func write(_ document: WallpaperEngineDocument, previous: WallpaperEngineDocument?, to folder: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        func put(_ value: JSONValue, _ name: String) throws {
            guard Archive.staysInside(name) else { return }
            let url = folder.appendingPathComponent(name)
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try value.data().write(to: url, options: .atomic)
        }
        if previous?.scene != document.scene {
            try put(document.scene, WallpaperEngineDocument.sceneFileName)
        }
        if previous?.project != document.project {
            try put(document.project, WallpaperEngineProject.projectFileName)
        }
        for (name, value) in document.files where previous?.files[name] != value {
            try put(value, name)
        }
        for name in (previous?.files.keys).map(Array.init) ?? [] where document.files[name] == nil && Archive.staysInside(name) {
            try? files.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// Lays a Wallpaper Engine project out in `destination` as loose files, the way its own
    /// editor keeps one: the project's files as they are, and those of its `scene.pkg` taken
    /// out of it. Names that would lead out of the folder are passed over.
    public static func unpack(_ source: URL, to destination: URL) throws {
        let files = FileManager.default
        try files.createDirectory(at: destination, withIntermediateDirectories: true)
        let root = source.standardizedFileURL.resolvingSymlinksInPath().path
        let walker = files.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        while let url = walker?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard path.hasPrefix(root + "/") else { continue }
            let name = String(path.dropFirst(root.count + 1))
            if name == WallpaperEnginePackage.fileName { continue }
            let target = destination.appendingPathComponent(name)
            try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if files.fileExists(atPath: target.path) { try files.removeItem(at: target) }
            try files.copyItem(at: url, to: target)
        }
        let packed = source.appendingPathComponent(WallpaperEnginePackage.fileName)
        guard let data = try? Data(contentsOf: packed, options: .mappedIfSafe), let package = WallpaperEnginePackage(data: data) else { return }
        for name in package.names {
            let clean = name.replacingOccurrences(of: "\\", with: "/")
            guard Archive.staysInside(clean), let file = package.data(named: name) else { continue }
            let target = destination.appendingPathComponent(clean)
            try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.write(to: target, options: .atomic)
        }
    }

    // MARK: - Bringing things in

    /// A name for a new file of the folder: `base` made plain, numbered if a file of that name
    /// is there already, in `directory` with the ending `fileExtension`.
    static func freeName(_ base: String, in directory: String, fileExtension: String, folder: URL) -> String {
        var plain = base.folding(options: [.diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "[^A-Za-z0-9_\\-]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if plain.isEmpty { plain = "layer" }
        plain = String(plain.prefix(48))
        var name = plain
        var number = 2
        let existing = Set(((try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent(directory).path)) ?? [])
            .map { ($0 as NSString).deletingPathExtension.lowercased() })
        while existing.contains(name.lowercased()) {
            name = "\(plain)_\(number)"
            number += 1
        }
        return name + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
    }

    /// A picture brought in as a texture of the folder, `materials/<name>.tex`; returns the
    /// texture's name as materials give it — without the folder and the ending — and the
    /// picture's size. A PNG or JPEG is kept as the file it is; any other picture becomes a PNG.
    public static func addPicture(_ source: URL, to folder: URL, clamped: Bool = true) throws -> (texture: String, width: Int, height: Int) {
        guard let image = CGImageSourceCreateWithURL(source as CFURL, nil),
              let type = CGImageSourceGetType(image),
              let picture = CGImageSourceCreateImageAtIndex(image, 0, nil)
        else {
            throw Problem.unreadablePicture
        }
        let file: Data
        if UTType(type as String) == .png || UTType(type as String) == .jpeg {
            file = try Data(contentsOf: source)
        } else {
            guard let png = pngData(picture) else { throw Problem.unreadablePicture }
            file = png
        }
        return try addPicture(file, width: picture.width, height: picture.height,
                              named: source.deletingPathExtension().lastPathComponent, to: folder, clamped: clamped)
    }

    /// A picture file, PNG or JPEG, brought in as a texture.
    public static func addPicture(_ file: Data, width: Int, height: Int, named base: String, to folder: URL,
                                  directory: String = "materials", clamped: Bool = true) throws -> (texture: String, width: Int, height: Int) {
        let name = freeName(base, in: directory, fileExtension: "", folder: folder)
        let url = folder.appendingPathComponent(directory).appendingPathComponent(name + ".tex")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try WallpaperEngineWriter.texture(picture: file, width: width, height: height, clamped: clamped).write(to: url, options: .atomic)
        // A material names its texture from the folder of the materials on.
        let prefix = directory == "materials" ? "" : String(directory.dropFirst("materials/".count)) + "/"
        return (prefix + name, width, height)
    }

    /// A video, an H.264 MP4 file, brought in as a texture.
    public static func addVideo(_ file: Data, width: Int, height: Int, named base: String, to folder: URL) throws -> String {
        let name = freeName(base, in: "materials", fileExtension: "", folder: folder)
        let url = folder.appendingPathComponent("materials").appendingPathComponent(name + ".tex")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try WallpaperEngineWriter.texture(video: file, width: width, height: height).write(to: url, options: .atomic)
        return name
    }

    /// A file copied into a folder of the project as it is — a sound into `sounds`, a font
    /// into `fonts`; returns its name in the project.
    public static func addFile(_ source: URL, into directory: String, of folder: URL) throws -> String {
        let fileExtension = source.pathExtension.lowercased()
        let name = freeName(source.deletingPathExtension().lastPathComponent, in: directory, fileExtension: fileExtension, folder: folder)
        let url = folder.appendingPathComponent(directory).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: url)
        return "\(directory)/\(name)"
    }

    static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

// MARK: - Playing a project

extension WallpaperEngineProjectFolder {
    /// The project of a scene of the app, if it has one.
    public static func project(ofScene scene: URL) -> URL? {
        let project = scene.appendingPathComponent(folderName, isDirectory: true)
        return FileManager.default.fileExists(atPath: project.appendingPathComponent(WallpaperEngineDocument.sceneFileName).path) ? project : nil
    }

    /// Lays a scene's project out for the player and brings the scene's settings up to the
    /// project's. A setting the scene had already keeps the value the user gave it.
    @discardableResult
    public static func layOut(scene folder: URL, languages: [String] = Locale.preferredLanguages) throws -> WallpaperEngineScene.LeftOut {
        guard let projectFolder = project(ofScene: folder), let package = WallpaperEnginePackage(folder: projectFolder) else {
            throw Problem.noScene
        }
        let leftOut = try WallpaperEngineScene.export(package, into: folder, allowEmpty: true)
        let found = WallpaperEngineProject(folder: projectFolder, languages: languages)?.variables ?? []
        let used = WallpaperEngineScene.settingNames(in: package, among: found.compactMap(\.property))
        let offered = found.filter { $0.property.map(used.contains) == true }
        let source = "\(WallpaperEngineScene.folderName)/\(WallpaperEngineScene.filesName)"
        var scene = (try? SceneProject.read(from: folder)) ?? WallpaperScene(background: .init(kind: .engine, source: source))
        scene.background = .init(kind: .engine, source: source, engine: scene.background.engine)
        scene.variables = offered.map { variable in
            guard let before = scene.variables.first(where: { $0.property == variable.property && $0.kind == variable.kind }) else {
                return variable
            }
            var kept = variable
            kept.id = before.id
            kept.color = before.color
            kept.number = min(max(before.number, variable.minimum), variable.maximum)
            kept.isOn = before.isOn
            kept.text = variable.kind == .choice && !variable.options.contains(before.text) ? variable.text : before.text
            return kept
        }
        if SceneProject.isScene(folder) {
            try SceneProject.write(scene, to: folder)
        } else {
            try SceneProject.create(at: folder, scene: scene)
        }
        return leftOut
    }
}

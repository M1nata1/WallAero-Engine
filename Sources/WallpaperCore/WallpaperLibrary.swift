import Combine
import CoreGraphics
import Foundation

/// The user's collection of wallpapers, stored in Application Support:
///
///     WallAeroEngine/
///       library.json   – the list of entries
///       tags.json      – which category each tag is in
///       Media/         – imported videos and pictures (animated images converted to .mov)
///       Thumbnails/    – small JPEG previews for the library window
///       Stills/        – full-size first frames, used as the regular macOS wallpaper
///       Web/           – one folder per web wallpaper: scenes and imported pages
/// The tags of one category, for a list that groups them.
public struct TagGroup: Identifiable, Hashable, Sendable {
    /// nil for the tags that were given no category.
    public let category: String?
    public let tags: [String]

    public var id: String { category ?? "" }

    public init(category: String?, tags: [String]) {
        self.category = category
        self.tags = tags
    }
}

@MainActor
public final class WallpaperLibrary: ObservableObject {
    @Published public private(set) var items: [Wallpaper] = []
    /// The category of each tag that was given one, by the tag in lower case.
    @Published public private(set) var tagCategories: [String: String] = [:]
    /// What the scenes brought in from Wallpaper Engine since the app started had that could
    /// not be brought with them, by the wallpaper each became.
    public private(set) var leftOutOnImport: [UUID: WallpaperEngineScene.LeftOut] = [:]

    public let rootURL: URL
    public let mediaURL: URL
    public let thumbnailsURL: URL
    public let stillsURL: URL
    public let webURL: URL
    private let indexURL: URL
    private let tagsURL: URL

    public nonisolated static var defaultRootURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return applicationSupport.appendingPathComponent("WallAeroEngine", isDirectory: true)
    }

    public init(rootURL: URL = WallpaperLibrary.defaultRootURL) {
        self.rootURL = rootURL
        mediaURL = rootURL.appendingPathComponent("Media", isDirectory: true)
        thumbnailsURL = rootURL.appendingPathComponent("Thumbnails", isDirectory: true)
        stillsURL = rootURL.appendingPathComponent("Stills", isDirectory: true)
        webURL = rootURL.appendingPathComponent("Web", isDirectory: true)
        indexURL = rootURL.appendingPathComponent("library.json")
        tagsURL = rootURL.appendingPathComponent("tags.json")
        for directory in [mediaURL, thumbnailsURL, stillsURL, webURL] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        load()
    }

    // MARK: - Lookup

    public func item(withID id: UUID) -> Wallpaper? {
        items.first { $0.id == id }
    }

    /// The video or picture; for a web wallpaper, its page.
    public func fileURL(for item: Wallpaper) -> URL {
        (item.kind == .web ? webURL : mediaURL).appendingPathComponent(item.fileName)
    }

    /// The folder of a web wallpaper, with its page and everything the page uses.
    public func projectURL(for item: Wallpaper) -> URL {
        webURL.appendingPathComponent(item.id.uuidString, isDirectory: true)
    }

    public func stillURL(for item: Wallpaper) -> URL {
        stillsURL.appendingPathComponent("\(item.id.uuidString).jpg")
    }

    public func thumbnailURL(for item: Wallpaper) -> URL? {
        item.thumbnailFileName.map { thumbnailsURL.appendingPathComponent($0) }
    }

    /// A full-size still of the wallpaper, suitable for `NSWorkspace.setDesktopImageURL`.
    /// For videos the first frame is extracted once and cached. A web wallpaper has a still only
    /// after the app has rendered one, see `setStill`.
    public func stillImageURL(for item: Wallpaper) async throws -> URL {
        if item.kind == .image {
            return fileURL(for: item)
        }
        if item.kind == .web {
            guard let rendered = renderedStillURL(for: item) else { throw ImportError.unreadable }
            return rendered
        }
        let stillURL = stillURL(for: item)
        if FileManager.default.fileExists(atPath: stillURL.path) {
            return stillURL
        }
        let frame = try await Thumbnailer.frame(ofVideoAt: fileURL(for: item), at: 0, maxPixelSize: nil)
        try Thumbnailer.writeJPEG(frame, to: stillURL, quality: 0.92)
        return stillURL
    }

    // MARK: - Changes

    /// Copies (or converts) the file into the library and adds it to the top of the list.
    @discardableResult
    public func importFile(
        at url: URL,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> Wallpaper {
        let destination = MediaImporter.Destination(mediaDirectory: mediaURL, thumbnailDirectory: thumbnailsURL)
        let item = try await MediaImporter.importMedia(from: url, id: UUID(), into: destination, progress: progress)
        items.insert(item, at: 0)
        save()
        return item
    }

    // MARK: - Web wallpapers

    /// Copies a folder with a web page into the library. Wallpapers made for Wallpaper Engine
    /// bring their title and preview picture along.
    @discardableResult
    public func importWebProject(at folder: URL) throws -> Wallpaper {
        guard let source = WebProject(folder: folder) else {
            throw ImportError.noWebPage
        }
        let id = UUID()
        let destination = webURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.copyItem(at: folder, to: destination)
        if source.isScene {
            try SceneProject.refreshGeneratedFiles(in: destination)
        }

        var thumbnailFileName: String?
        if let preview = source.previewFile,
           let image = Thumbnailer.image(at: destination.appendingPathComponent(preview)) {
            thumbnailFileName = "\(id.uuidString).jpg"
            try? Thumbnailer.writeJPEG(image, to: thumbnailsURL.appendingPathComponent(thumbnailFileName!))
        }
        let item = Wallpaper(
            id: id,
            name: source.title ?? folder.lastPathComponent,
            kind: .web,
            fileName: "\(id.uuidString)/\(source.entryFile)",
            thumbnailFileName: thumbnailFileName,
            sourceFormat: source.isScene ? "SCENE" : "WEB",
            wasConverted: false,
            pixelWidth: 0,
            pixelHeight: 0,
            duration: nil,
            // Unknown until the page runs; assume it may make sound, so the sound settings apply.
            hasAudio: true,
            fileSize: Self.size(ofFolder: destination)
        )
        items.insert(item, at: 0)
        save()
        return item
    }

    // MARK: - Wallpaper Engine and archives

    /// Brings in a wallpaper made for Wallpaper Engine. A web page becomes a scene with the page
    /// as its background and the page's own settings as its variables: it is set up in the
    /// wallpaper's settings and takes layers in the editor like any scene. One of Wallpaper
    /// Engine's own scenes becomes a scene too, with the whole of it — pictures, effects,
    /// particles, texts, sounds, scripts — as the background, played by the page, and with the
    /// settings it makes use of as its variables; what of it is not played is noted in
    /// `leftOutOnImport`. A video is taken as any video is. Whatever its kind, the wallpaper
    /// gets the tags its project comes with.
    @discardableResult
    public func importWallpaperEngineProject(_ project: WallpaperEngineProject, fallbackName: String? = nil,
                                             progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Wallpaper {
        let inUse = Set(allTags.map { $0.lowercased() })
        let added = try await addWallpaperEngineProject(project, fallbackName: fallbackName, progress: progress)
        guard !project.tags.isEmpty else { return added }
        setTags(added.tagList + project.tags.map(\.name), for: added.id)
        // Only a tag that is new here is put into its category: one the library has already
        // stays where the user keeps it, be it in another category or in none.
        for tag in project.tags where !inUse.contains(tag.name.lowercased()) && category(of: tag.name) == nil {
            setCategory(tag.category, ofTag: tag.name)
        }
        return item(withID: added.id) ?? added
    }

    private func addWallpaperEngineProject(_ project: WallpaperEngineProject, fallbackName: String?,
                                           progress: @escaping @Sendable (Double) -> Void) async throws -> Wallpaper {
        let name = project.title ?? fallbackName ?? project.folder.lastPathComponent
        switch project.kind {
        case .other(let kind):
            throw ImportError.unsupportedWallpaperEngineKind(kind)
        case .preset:
            throw ImportError.settingsWithoutWallpaper
        case .video:
            guard let file = project.file else { throw ImportError.unreadable }
            let item = try await importFile(at: project.folder.appendingPathComponent(file), progress: progress)
            rename(item.id, to: name)
            return self.item(withID: item.id) ?? item
        case .web:
            guard let file = project.file else { throw ImportError.noWebPage }
            let id = UUID()
            let folder = webURL.appendingPathComponent(id.uuidString, isDirectory: true)
            let page = folder.appendingPathComponent(SceneProject.pageFolderName, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: project.folder, to: page)
                let background = WallpaperScene.Background(kind: .page, source: "\(SceneProject.pageFolderName)/\(file)")
                try SceneProject.create(at: folder, scene: WallpaperScene(background: background, variables: project.variables))
            } catch {
                try? FileManager.default.removeItem(at: folder)
                throw error
            }
            return addScene(id, named: name, preview: project.previewFile.map(page.appendingPathComponent))
        case .scene:
            let id = UUID()
            let folder = webURL.appendingPathComponent(id.uuidString, isDirectory: true)
            let source = project.folder
            let variables = project.variables
            let chosen = project.chosenPictures
            let leftOut: WallpaperEngineScene.LeftOut
            do {
                // Unpacking the pictures takes a while; the app stays responsive meanwhile.
                leftOut = try await Task.detached(priority: .userInitiated) {
                    guard WallpaperEnginePackage(folder: source) != nil else { throw ImportError.unreadable }
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    // The project is kept as Wallpaper Engine's editor keeps one, for the app's
                    // editor to change and to give back to Wallpaper Engine; the player plays
                    // what is laid out of it.
                    let project = folder.appendingPathComponent(WallpaperEngineProjectFolder.folderName, isDirectory: true)
                    // Taking the project out of its package is a third of the work; laying it
                    // out for the player — reading every picture — the rest.
                    try WallpaperEngineProjectFolder.unpack(source, to: project) { progress($0 / 3) }
                    guard let package = WallpaperEnginePackage(folder: project) else { throw ImportError.unreadable }
                    let leftOut = try WallpaperEngineScene.export(package, into: folder, chosen: chosen) { progress(1 / 3 + $0 * 2 / 3) }
                    // Kept with the scene, so that laying it out again shows them still.
                    for (setting, picture) in chosen {
                        try? WallpaperEngineProjectFolder.keep(picture, for: setting, scene: folder)
                    }
                    let source = "\(WallpaperEngineScene.folderName)/\(WallpaperEngineScene.filesName)"
                    // Every wallpaper comes with a scheme color and may come with settings left
                    // from an older version of itself; only what the scene uses is offered.
                    let used = WallpaperEngineScene.settingNames(in: package, among: variables.compactMap(\.property))
                    let offered = variables.filter { $0.property.map(used.contains) == true }
                    try SceneProject.create(at: folder, scene: WallpaperScene(background: .init(kind: .engine, source: source),
                                                                              variables: offered))
                    return leftOut
                }.value
            } catch {
                try? FileManager.default.removeItem(at: folder)
                throw error
            }
            // The app draws the thumbnail itself: the preview that comes with a scene is small.
            let item = addScene(id, named: name, preview: nil)
            if !leftOut.isEmpty {
                leftOutOnImport[id] = leftOut
            }
            return item
        }
    }

    /// Adds the scene in the folder named after `id` to the top of the list.
    private func addScene(_ id: UUID, named name: String, preview: URL?) -> Wallpaper {
        var thumbnailFileName: String?
        if let preview, let image = Thumbnailer.image(at: preview) {
            thumbnailFileName = "\(id.uuidString).jpg"
            try? Thumbnailer.writeJPEG(image, to: thumbnailsURL.appendingPathComponent(thumbnailFileName!))
        }
        let item = Wallpaper(
            id: id,
            name: name,
            kind: .web,
            fileName: "\(id.uuidString)/\(SceneProject.entryFileName)",
            thumbnailFileName: thumbnailFileName,
            sourceFormat: "SCENE",
            wasConverted: false,
            pixelWidth: 0,
            pixelHeight: 0,
            duration: nil,
            // Unknown until the page runs; assume it may make sound, so the sound settings apply.
            hasAudio: true,
            fileSize: Self.size(ofFolder: webURL.appendingPathComponent(id.uuidString, isDirectory: true))
        )
        items.insert(item, at: 0)
        save()
        return item
    }

    /// Brings in every wallpaper of an archive or a folder that holds several. Those that
    /// cannot be brought in are passed over as long as one can; if none can, the first one's
    /// reason is thrown.
    private func importWallpaperEngineProjects(_ found: [WallpaperEngineProject], fallbackName: String,
                                               progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> [Wallpaper] {
        let projects = WallpaperEngineProject.settled(found)
        var added: [Wallpaper] = []
        var firstError: Error?
        for (index, project) in projects.enumerated() {
            do {
                // One wallpaper alone is named after the archive when it has no title of its own;
                // each of several after its own folder.
                let done = Double(index), count = Double(projects.count)
                added.append(try await importWallpaperEngineProject(project, fallbackName: projects.count == 1 ? fallbackName : nil,
                                                                    progress: { progress((done + $0) / count) }))
            } catch {
                firstError = firstError ?? error
            }
        }
        if added.isEmpty, let firstError {
            throw firstError
        }
        return added
    }

    /// Brings in whatever is at `url`: an archive, the folder of a wallpaper made for Wallpaper
    /// Engine, a folder with a web page, or a video or picture. Returns what was added.
    /// - Parameter languages: the languages to name a Wallpaper Engine wallpaper's settings in.
    @discardableResult
    public func importItem(at url: URL, languages: [String] = Locale.preferredLanguages,
                           progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> [Wallpaper] {
        if Archive.isArchive(url) {
            return try await importArchive(at: url, languages: languages, progress: progress)
        }
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            // The wallpaper's own folder, or the one an archive of it was unpacked into.
            let projects = WallpaperEngineProject.all(in: url, languages: languages)
            if !projects.isEmpty {
                return try await importWallpaperEngineProjects(projects, fallbackName: url.lastPathComponent, progress: progress)
            }
            return [try importWebProject(at: url)]
        }
        return [try await importFile(at: url, progress: progress)]
    }

    /// Brings in what an archive holds: a wallpaper made for Wallpaper Engine, a folder with
    /// a web page, or videos and pictures. Returns what was added, never nothing.
    @discardableResult
    public func importArchive(at archive: URL, languages: [String] = Locale.preferredLanguages,
                              progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> [Wallpaper] {
        let files = FileManager.default
        let unpacked = files.temporaryDirectory.appendingPathComponent("WallAeroEngine-\(UUID().uuidString)", isDirectory: true)
        defer { try? files.removeItem(at: unpacked) }
        // Unpacking is the first fifth of the work.
        try await Task.detached(priority: .userInitiated) {
            try Archive.unpack(archive, into: unpacked) { progress($0 / 5) }
        }.value
        let rest: @Sendable (Double) -> Void = { progress(0.2 + $0 * 0.8) }
        // The archive's own name is the wallpaper's when nothing inside names it.
        let name = archive.deletingPathExtension().lastPathComponent

        let projects = WallpaperEngineProject.all(in: unpacked, languages: languages)
        if !projects.isEmpty {
            return try await importWallpaperEngineProjects(projects, fallbackName: name, progress: rest)
        }
        let inside = (try? files.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        if let page = ([unpacked] + inside).first(where: { WebProject(folder: $0) != nil }) {
            let item = try importWebProject(at: page)
            if page == unpacked, WebProject(folder: page)?.title == nil {
                rename(item.id, to: name)
            }
            return [self.item(withID: item.id) ?? item]
        }
        let media = (files.enumerator(at: unpacked, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])?
            .compactMap { $0 as? URL } ?? [])
            .filter(MediaImporter.canImport)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !media.isEmpty else { throw ImportError.emptyArchive }
        var added: [Wallpaper] = []
        for (index, file) in media.enumerated() {
            let done = Double(index), count = Double(media.count)
            added.append(try await importFile(at: file) { rest((done + $0) / count) })
        }
        return added
    }

    /// Makes a scene out of a video or picture of the library: a new wallpaper with that media as
    /// its background, ready for layers. The original stays as it is.
    @discardableResult
    public func makeScene(from original: Wallpaper, named name: String) throws -> Wallpaper {
        guard original.kind != .web else { throw ImportError.unreadable }
        let id = UUID()
        let folder = webURL.appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let source = try SceneProject.addMedia(fileURL(for: original), to: folder, named: "background")
            let background = WallpaperScene.Background(kind: original.kind == .video ? .video : .image, source: source)
            try SceneProject.create(at: folder, scene: WallpaperScene(background: background))
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }

        var thumbnailFileName: String?
        if let thumbnail = thumbnailURL(for: original) {
            thumbnailFileName = "\(id.uuidString).jpg"
            try? FileManager.default.copyItem(at: thumbnail, to: thumbnailsURL.appendingPathComponent(thumbnailFileName!))
        }
        let item = Wallpaper(
            id: id,
            name: name,
            kind: .web,
            fileName: "\(id.uuidString)/\(SceneProject.entryFileName)",
            thumbnailFileName: thumbnailFileName,
            sourceFormat: "SCENE",
            wasConverted: false,
            pixelWidth: original.pixelWidth,
            pixelHeight: original.pixelHeight,
            duration: original.duration,
            hasAudio: original.hasAudio,
            fileSize: Self.size(ofFolder: folder)
        )
        items.insert(item, at: 0)
        save()
        return item
    }

    /// Makes a new scene of Wallpaper Engine's, which the editor makes and which can be given to
    /// Wallpaper Engine as it is: `build` puts what it starts with into its project.
    /// - Parameters:
    ///   - size: the size the scene is made at, in pixels: the display's.
    @discardableResult
    public func makeEngineScene(named name: String, size: CGSize,
                                build: (_ project: URL, _ document: inout WallpaperEngineDocument) async throws -> Void = { _, _ in }) async throws -> Wallpaper {
        let id = UUID()
        let folder = webURL.appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            let project = folder.appendingPathComponent(WallpaperEngineProjectFolder.folderName, isDirectory: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            var document = WallpaperEngineDocument.empty(title: name, width: Int(size.width.rounded()), height: Int(size.height.rounded()))
            try await build(project, &document)
            try WallpaperEngineProjectFolder.write(document, previous: nil, to: project)
            try await Task.detached(priority: .userInitiated) {
                try WallpaperEngineProjectFolder.layOut(scene: folder)
            }.value
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return addScene(id, named: name, preview: nil)
    }

    /// Makes a scene of Wallpaper Engine's out of a video or picture of the library, with that
    /// media as a layer that fills it. The original stays as it is.
    @discardableResult
    public func makeEngineScene(from original: Wallpaper, named name: String, size: CGSize) async throws -> Wallpaper {
        guard original.kind != .web else { throw ImportError.unreadable }
        let source = fileURL(for: original)
        let isVideo = original.kind == .video
        return try await makeEngineScene(named: name, size: size) { project, document in
            let layer = NSLocalizedString("Background", comment: "Name of the layer a scene made from a wallpaper starts with")
            if isVideo {
                let video = try await WallpaperEngineVideo.prepare(source)
                let texture = try WallpaperEngineProjectFolder.addVideo(video.file, width: video.width, height: video.height,
                                                                         named: "background", to: project)
                let id = document.addImage(texture: texture, width: video.width, height: video.height, name: layer)
                document.cover(id, width: video.width, height: video.height)
            } else {
                let picture = try WallpaperEngineProjectFolder.addPicture(source, to: project)
                let id = document.addImage(texture: picture.texture, width: picture.width, height: picture.height, name: layer)
                document.cover(id, width: picture.width, height: picture.height)
            }
        }
    }

    /// Whether the wallpaper is a scene the editor can open.
    public func isScene(_ item: Wallpaper) -> Bool {
        item.kind == .web && SceneProject.isScene(projectURL(for: item))
    }

    /// Stores a picture of the page as the library thumbnail. The app renders it, as only the app
    /// has a web view.
    public func setThumbnail(_ image: CGImage, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let fileName = "\(id.uuidString).jpg"
        guard (try? Thumbnailer.writeJPEG(image, to: thumbnailsURL.appendingPathComponent(fileName))) != nil else { return }
        // A new value even when the name is the same, so that views showing the picture refresh.
        items[index].thumbnailFileName = fileName
        items[index].fileSize = Self.size(ofFolder: projectURL(for: items[index]))
        save()
    }

    /// Keeps the picture a display showed when the screen was locked, for the lock screen. Each
    /// is written under a new name, so macOS takes it for a new picture; the display's one before
    /// is deleted.
    public func setLockFrame(_ image: CGImage, forDisplay display: String) throws -> URL {
        let allowed = CharacterSet.alphanumerics
        let name = String(display.unicodeScalars.map { allowed.contains($0) && $0.isASCII ? Character($0) : "-" })
        let prefix = "lock-\(name)-"
        let files = FileManager.default
        for old in (try? files.contentsOfDirectory(atPath: stillsURL.path)) ?? [] where old.hasPrefix(prefix) {
            try? files.removeItem(at: stillsURL.appendingPathComponent(old))
        }
        let url = stillsURL.appendingPathComponent("\(prefix)\(UUID().uuidString).jpg")
        try Thumbnailer.writeJPEG(image, to: url, quality: 0.92)
        return url
    }

    /// The still the app last rendered for a web wallpaper, if any.
    public func renderedStillURL(for item: Wallpaper) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: stillsURL.path)) ?? []
        return names.first { $0.hasPrefix(item.id.uuidString) }.map(stillsURL.appendingPathComponent)
    }

    /// Stores a full-size picture of the page, for use as the regular macOS wallpaper. Every still
    /// gets a file name of its own: macOS does not look again at a desktop picture whose name it
    /// already knows, so an edited scene would keep its old picture on the lock screen.
    @discardableResult
    public func setStill(_ image: CGImage, for item: Wallpaper) throws -> URL {
        removeStill(for: item)
        let stamp = String(UInt64(Date().timeIntervalSince1970 * 1000), radix: 36)
        let url = stillsURL.appendingPathComponent("\(item.id.uuidString)-\(stamp).jpg")
        try Thumbnailer.writeJPEG(image, to: url, quality: 0.92)
        return url
    }

    public func removeStill(for item: Wallpaper) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: stillsURL.path)) ?? []
        for name in names where name.hasPrefix(item.id.uuidString) {
            try? FileManager.default.removeItem(at: stillsURL.appendingPathComponent(name))
        }
    }

    private static func size(ofFolder folder: URL) -> Int64 {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let file = enumerator?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    /// Stores how a wallpaper is shown. Nothing is written if that is how it is shown already.
    public func setSettings(_ settings: Wallpaper.Settings, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].settings != settings else { return }
        items[index].settings = settings
        save()
    }

    /// Gives the wallpapers that have no settings of their own yet the ones returned for them;
    /// nil leaves a wallpaper as it is.
    public func adoptSettings(_ settings: (Wallpaper) -> Wallpaper.Settings?) {
        var changed = false
        for index in items.indices where items[index].settings == nil {
            if let adopted = settings(items[index]) {
                items[index].settings = adopted
                changed = true
            }
        }
        if changed {
            save()
        }
    }

    /// Every tag the wallpapers have, in alphabetical order.
    public var allTags: [String] {
        var seen: Set<String> = []
        return items.flatMap(\.tagList)
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Gives a wallpaper its tags, in the order they come. Each is trimmed, and empty ones and
    /// repeats are left out. A tag that differs from one in use only in case takes that one's
    /// spelling, so "Anime" and "anime" do not become two filters.
    public func setTags(_ tags: [String], for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let inUse = items.filter { $0.id != id }.flatMap(\.tagList)
        var seen: Set<String> = []
        let cleaned = tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .map { tag in inUse.first { $0.caseInsensitiveCompare(tag) == .orderedSame } ?? tag }
        guard cleaned != items[index].tagList else { return }
        items[index].tags = cleaned.isEmpty ? nil : cleaned
        save()
    }

    /// Gives every wallpaper that has no music of its own the music that used to be set once
    /// for all of them.
    public func adoptMusic(_ music: Wallpaper.Settings.Music) {
        var changed = false
        for index in items.indices where items[index].shownSettings.music == nil {
            var settings = items[index].shownSettings
            settings.music = music
            items[index].settings = settings
            changed = true
        }
        if changed {
            save()
        }
    }

    public func category(of tag: String) -> String? {
        tagCategories[tag.lowercased()]
    }

    /// The categories the library's tags are in, in alphabetical order.
    public var allCategories: [String] {
        Set(allTags.compactMap(category(of:))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The library's tags by category, the ones without a category last.
    public var tagGroups: [TagGroup] {
        let tags = allTags
        var groups = allCategories.map { category in
            TagGroup(category: category, tags: tags.filter { self.category(of: $0) == category })
        }
        let loose = tags.filter { category(of: $0) == nil }
        if !loose.isEmpty {
            groups.append(TagGroup(category: nil, tags: loose))
        }
        return groups
    }

    /// Puts a tag into a category, on every wallpaper that has the tag, or takes it out of its
    /// category with nil. A category that differs from one in use only in case takes that one's
    /// spelling.
    public func setCategory(_ category: String?, ofTag tag: String) {
        let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let named = trimmed.isEmpty ? nil : allCategories.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed
        guard tagCategories[tag.lowercased()] != named else { return }
        tagCategories[tag.lowercased()] = named
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(tagCategories) else { return }
        try? data.write(to: tagsURL, options: .atomic)
    }

    public func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].name = trimmed
        save()
    }

    /// Removes the entries and deletes their files.
    public func remove(_ ids: Set<UUID>) {
        let removed = items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        save()
        for item in removed {
            removeStill(for: item)
            var files = [item.kind == .web ? projectURL(for: item) : fileURL(for: item)]
            if let thumbnail = thumbnailURL(for: item) {
                files.append(thumbnail)
            }
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stored = try? decoder.decode([Wallpaper].self, from: data) else { return }
        // Entries whose media file disappeared (deleted by hand) are dropped.
        items = stored.filter { FileManager.default.fileExists(atPath: fileURL(for: $0).path) }
        if let data = try? Data(contentsOf: tagsURL), let categories = try? JSONDecoder().decode([String: String].self, from: data) {
            tagCategories = categories
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}

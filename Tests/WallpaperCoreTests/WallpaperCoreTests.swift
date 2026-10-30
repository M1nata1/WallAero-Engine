import AVFoundation
import Compression
import ImageIO
import JavaScriptCore
import UniformTypeIdentifiers
import XCTest
@testable import WallpaperCore

final class AnimatedImageConverterTests: XCTestCase {
    func testSmallAnimationsAreUpscaledByAnIntegerFactor() {
        let size = AnimatedImageConverter.outputSize(forWidth: 498, height: 280)
        XCTAssertEqual(size.width, 1494)
        XCTAssertEqual(size.height, 840)
        XCTAssertTrue(size.nearestNeighbor)
    }

    func testMediumAnimationsKeepTheirSizeButBecomeEven() {
        let size = AnimatedImageConverter.outputSize(forWidth: 1001, height: 563)
        XCTAssertEqual(size.width, 1000)
        XCTAssertEqual(size.height, 562)
        XCTAssertFalse(size.nearestNeighbor)
    }

    func testHugeAnimationsAreScaledDown() {
        let size = AnimatedImageConverter.outputSize(forWidth: 5000, height: 5000)
        XCTAssertLessThanOrEqual(size.width * size.height, AnimatedImageConverter.maximumArea)
        XCTAssertEqual(size.width, size.height)
        XCTAssertEqual(size.width % 2, 0)
    }

    func testFramesWithoutDelayUseTheBrowserFallback() throws {
        let url = try TestMedia.directory().appendingPathComponent("delays.gif")
        try TestMedia.writeGIF(to: url, size: CGSize(width: 40, height: 30), delays: [0, 0.05, 0.2])
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let delays = AnimatedImageConverter.frameDelays(of: source)
        XCTAssertEqual(delays.count, 3)
        XCTAssertEqual(delays[0], 0.1, accuracy: 0.001)
        XCTAssertEqual(delays[1], 0.05, accuracy: 0.001)
        XCTAssertEqual(delays[2], 0.2, accuracy: 0.001)
        XCTAssertTrue(AnimatedImageConverter.isAnimated(source))
    }
}

@MainActor
final class WallpaperLibraryTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = try TestMedia.directory()
    }

    func testImportingAGIFProducesAVideoOfTheSameLength() async throws {
        let gif = root.appendingPathComponent("Pixel Sunset.gif")
        try TestMedia.writeGIF(to: gif, size: CGSize(width: 320, height: 180), delays: Array(repeating: 0.1, count: 12))
        let library = WallpaperLibrary(rootURL: root.appendingPathComponent("Library"))

        let item = try await library.importFile(at: gif)

        XCTAssertEqual(item.name, "Pixel Sunset")
        XCTAssertEqual(item.kind, .video)
        XCTAssertEqual(item.sourceFormat, "GIF")
        XCTAssertTrue(item.wasConverted)
        XCTAssertEqual(item.pixelWidth, 320)
        XCTAssertEqual(item.pixelHeight, 180)
        XCTAssertEqual(try XCTUnwrap(item.duration), 1.2, accuracy: 0.01)
        XCTAssertNotNil(library.thumbnailURL(for: item))

        let asset = AVURLAsset(url: library.fileURL(for: item))
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 1.2, accuracy: 0.05)
        let track = try await XCTUnwrapAsync(try await asset.loadTracks(withMediaType: .video).first)
        let naturalSize = try await track.load(.naturalSize)
        // 320 px wide → enlarged 6× for crisp scaling.
        XCTAssertEqual(naturalSize, CGSize(width: 1920, height: 1080))
    }

    func testImportingAVideoCopiesItAndReadsItsMetadata() async throws {
        let movie = root.appendingPathComponent("Waves.mov")
        let gif = root.appendingPathComponent("source.gif")
        try TestMedia.writeGIF(to: gif, size: CGSize(width: 1280, height: 720), delays: Array(repeating: 0.04, count: 25))
        _ = try await AnimatedImageConverter.convert(source: gif, to: movie)
        let library = WallpaperLibrary(rootURL: root.appendingPathComponent("Library"))

        let item = try await library.importFile(at: movie)

        XCTAssertEqual(item.kind, .video)
        XCTAssertEqual(item.sourceFormat, "MOV")
        XCTAssertFalse(item.wasConverted)
        XCTAssertEqual(item.pixelWidth, 1280)
        XCTAssertEqual(item.pixelHeight, 720)
        XCTAssertEqual(try XCTUnwrap(item.duration), 1.0, accuracy: 0.05)
        XCTAssertFalse(item.hasAudio)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.fileURL(for: item).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: movie.path), "The original must stay where it was")
    }

    func testImportingAStillImageKeepsItAsAnImage() async throws {
        let png = root.appendingPathComponent("Mountains.png")
        try TestMedia.writePNG(to: png, size: CGSize(width: 800, height: 600))
        let library = WallpaperLibrary(rootURL: root.appendingPathComponent("Library"))

        let item = try await library.importFile(at: png)

        XCTAssertEqual(item.kind, .image)
        XCTAssertNil(item.duration)
        XCTAssertEqual(item.pixelWidth, 800)
        XCTAssertEqual(item.pixelHeight, 600)
        let still = try await library.stillImageURL(for: item)
        XCTAssertEqual(still, library.fileURL(for: item))
    }

    func testStillOfAVideoIsExtractedAtFullSize() async throws {
        let gif = root.appendingPathComponent("loop.gif")
        try TestMedia.writeGIF(to: gif, size: CGSize(width: 1200, height: 800), delays: [0.1, 0.1])
        let library = WallpaperLibrary(rootURL: root.appendingPathComponent("Library"))
        let item = try await library.importFile(at: gif)

        let still = try await library.stillImageURL(for: item)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(still as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 1200)
    }

    func testUnsupportedFilesAreRejected() async throws {
        let text = root.appendingPathComponent("notes.txt")
        try "hello".write(to: text, atomically: true, encoding: .utf8)
        let library = WallpaperLibrary(rootURL: root.appendingPathComponent("Library"))

        do {
            try await library.importFile(at: text)
            XCTFail("Expected an error")
        } catch let error as ImportError {
            XCTAssertEqual(error, .unsupportedFormat("txt"))
        }
        XCTAssertTrue(library.items.isEmpty)
    }

    func testBrokenVideosAreRejected() async throws {
        let fake = root.appendingPathComponent("broken.mp4")
        try Data(repeating: 7, count: 4096).write(to: fake)
        let library = WallpaperLibrary(rootURL: root.appendingPathComponent("Library"))

        do {
            try await library.importFile(at: fake)
            XCTFail("Expected an error")
        } catch let error as ImportError {
            XCTAssertEqual(error, .undecodableVideo)
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: library.mediaURL.path)
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testAWebFolderIsImportedWholeAndRemovedWhole() async throws {
        let source = try TestMedia.directory()
        addTeardownBlock { try? FileManager.default.removeItem(at: source) }
        let folder = source.appendingPathComponent("Neon")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("js"), withIntermediateDirectories: true)
        try "<html></html>".write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try "x".write(to: folder.appendingPathComponent("js/app.js"), atomically: true, encoding: .utf8)

        let library = WallpaperLibrary(rootURL: root)
        let item = try library.importWebProject(at: folder)

        XCTAssertEqual(item.kind, .web)
        XCTAssertEqual(item.name, "Neon")
        XCTAssertEqual(item.sourceFormat, "WEB")
        XCTAssertEqual(library.fileURL(for: item).lastPathComponent, "index.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.projectURL(for: item).appendingPathComponent("js/app.js").path))
        XCTAssertFalse(library.isScene(item))
        XCTAssertEqual(WallpaperLibrary(rootURL: root).items.map(\.id), [item.id], "survives a restart")
        XCTAssertThrowsError(try library.importWebProject(at: source), "a folder without a page") { error in
            XCTAssertEqual(error as? ImportError, .noWebPage)
        }

        library.remove([item.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.projectURL(for: item).path))
    }

    func testAVideoBecomesASceneWithItselfAsTheBackground() async throws {
        let videoURL = root.appendingPathComponent("source.gif")
        try TestMedia.writeGIF(to: videoURL, size: CGSize(width: 64, height: 36), delays: [0.1, 0.1, 0.1])
        let library = WallpaperLibrary(rootURL: root.appendingPathComponent("library"))
        let video = try await library.importFile(at: videoURL)

        let scene = try library.makeScene(from: video, named: "Editable")

        XCTAssertEqual(scene.kind, .web)
        XCTAssertEqual(scene.name, "Editable")
        XCTAssertEqual(scene.sourceFormat, "SCENE")
        XCTAssertTrue(library.isScene(scene))
        XCTAssertEqual(library.items.map(\.id), [scene.id, video.id], "the original stays")
        let stored = try SceneProject.read(from: library.projectURL(for: scene))
        XCTAssertEqual(stored.background.kind, .video)
        XCTAssertEqual(stored.background.source, "media/background.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.projectURL(for: scene).appendingPathComponent("media/background.mov").path))
        XCTAssertNotNil(library.thumbnailURL(for: scene), "starts with the original's thumbnail")
        XCTAssertThrowsError(try library.makeScene(from: scene, named: "Again"), "a scene is edited, not wrapped again")
    }

    func testWebStillsGetANewFileNameEachTime() async throws {
        let library = WallpaperLibrary(rootURL: root)
        let folder = root.appendingPathComponent("page")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "<html></html>".write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let item = try library.importWebProject(at: folder)
        let picture = try XCTUnwrap(Thumbnailer.image(at: try TestMedia.pngFile(in: root)))

        XCTAssertNil(library.renderedStillURL(for: item))
        let first = try library.setStill(picture, for: item)
        try await Task.sleep(nanoseconds: 5_000_000)
        let second = try library.setStill(picture, for: item)

        XCTAssertNotEqual(first.lastPathComponent, second.lastPathComponent, "macOS ignores a changed picture under a known name")
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path), "the old still does not pile up")
        let stillURL = try await library.stillImageURL(for: item)
        XCTAssertEqual(stillURL, second)
        library.remove([item.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.path))
    }

    func testEveryWallpaperHasSettingsOfItsOwn() async throws {
        let folder = root.appendingPathComponent("Library")
        let library = WallpaperLibrary(rootURL: folder)
        let first = try await library.importFile(at: TestMedia.pngFile(in: root))
        let second = try await library.importFile(at: TestMedia.pngFile(in: root))
        XCTAssertNil(first.settings)
        XCTAssertEqual(first.shownSettings, Wallpaper.Settings(scaling: .fill, position: 50, speed: 1))

        library.setSettings(Wallpaper.Settings(scaling: .fit, position: 20, speed: 0.5), for: first.id)
        // What used to be one setting for all goes to those that have none of their own.
        library.adoptSettings { _ in Wallpaper.Settings(scaling: .stretch) }

        let reopened = WallpaperLibrary(rootURL: folder)
        XCTAssertEqual(reopened.item(withID: first.id)?.shownSettings, Wallpaper.Settings(scaling: .fit, position: 20, speed: 0.5))
        XCTAssertEqual(reopened.item(withID: second.id)?.shownSettings.scaling, .stretch)
    }

    func testEveryWallpaperHasMusicOfItsOwn() async throws {
        let folder = root.appendingPathComponent("Library")
        let library = WallpaperLibrary(rootURL: folder)
        let first = try await library.importFile(at: TestMedia.pngFile(in: root))
        let second = try await library.importFile(at: TestMedia.pngFile(in: root))
        XCTAssertNil(first.shownSettings.music)

        let own = Wallpaper.Settings.Music(folderPath: "/Music/Night", playlist: "Calm", isShuffled: true)
        library.setSettings(Wallpaper.Settings(scaling: .fit, music: own), for: first.id)
        // What used to be one folder for all goes to those that have no music of their own.
        library.adoptMusic(Wallpaper.Settings.Music(folderPath: "/Music/All"))

        let reopened = WallpaperLibrary(rootURL: folder)
        XCTAssertEqual(reopened.item(withID: first.id)?.shownSettings.music, own)
        XCTAssertEqual(reopened.item(withID: first.id)?.shownSettings.scaling, .fit)
        XCTAssertEqual(reopened.item(withID: second.id)?.shownSettings.music?.folderPath, "/Music/All")
        XCTAssertEqual(reopened.item(withID: second.id)?.shownSettings.music?.isShuffled, false)
    }

    func testSettingsWrittenBeforeMusicWasPerWallpaperStillOpen() throws {
        let old = #"{"position":20,"scaling":"fit","speed":0.5}"#
        let settings = try JSONDecoder().decode(Wallpaper.Settings.self, from: Data(old.utf8))
        XCTAssertEqual(settings, Wallpaper.Settings(scaling: .fit, position: 20, speed: 0.5))
        XCTAssertNil(settings.music)
    }

    func testOnlyOneWallpaperIsHeard() {
        func wallpaper(audio: Bool, music: String?) -> Wallpaper {
            Wallpaper(id: UUID(), name: "W", kind: .video, fileName: "a.mp4", thumbnailFileName: nil, sourceFormat: "MP4",
                      wasConverted: false, pixelWidth: 1920, pixelHeight: 1080, duration: 5, hasAudio: audio, fileSize: 1,
                      settings: music.map { Wallpaper.Settings(music: .init(folderPath: $0)) })
        }
        let silent = wallpaper(audio: false, music: nil)
        let loud = wallpaper(audio: true, music: nil)
        let musical = wallpaper(audio: false, music: "/Music")

        XCTAssertNil(Wallpaper.heard(among: []))
        XCTAssertNil(Wallpaper.heard(among: [silent, nil]))
        XCTAssertEqual(Wallpaper.heard(among: [silent, loud, musical])?.index, 1)
        XCTAssertEqual(Wallpaper.heard(among: [nil, musical, loud])?.wallpaper.id, musical.id)
    }

    func testALibraryWrittenBeforeSettingsExistedStillOpens() throws {
        let old = #"[{"dateAdded":"2026-10-01T09:00:00Z","duration":6.8,"fileName":"a.mp4","fileSize":10,"hasAudio":true,"id":"09970F42-E5A6-40F3-8100-68207CA21CDF","kind":"video","name":"Old","pixelHeight":1080,"pixelWidth":1920,"sourceFormat":"MP4","thumbnailFileName":null,"wasConverted":false}]"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let item = try XCTUnwrap(decoder.decode([Wallpaper].self, from: Data(old.utf8)).first)
        XCTAssertEqual(item.name, "Old")
        XCTAssertNil(item.settings)
        XCTAssertEqual(item.shownSettings.speed, 1)
        XCTAssertEqual(item.tagList, [])
    }

    func testTagsAreTidiedKeptAndListed() async throws {
        let folder = root.appendingPathComponent("Library")
        let library = WallpaperLibrary(rootURL: folder)
        let first = try await library.importFile(at: TestMedia.pngFile(in: root))
        let second = try await library.importFile(at: TestMedia.pngFile(in: root))
        XCTAssertNil(first.tags)
        XCTAssertTrue(library.allTags.isEmpty)

        library.setTags(["  Night ", "", "anime", "night"], for: first.id)
        XCTAssertEqual(library.item(withID: first.id)?.tagList, ["Night", "anime"])
        // The spelling in use wins, so one tag is not two filters.
        library.setTags(["ANIME", "City"], for: second.id)
        XCTAssertEqual(library.item(withID: second.id)?.tagList, ["anime", "City"])
        XCTAssertEqual(library.allTags, ["anime", "City", "Night"])

        let reopened = WallpaperLibrary(rootURL: folder)
        XCTAssertEqual(reopened.item(withID: first.id)?.tagList, ["Night", "anime"])
        reopened.setTags([], for: first.id)
        XCTAssertNil(reopened.item(withID: first.id)?.tags)
        XCTAssertEqual(reopened.allTags, ["anime", "City"])
    }

    func testTagsAreGroupedByTheirCategories() async throws {
        let folder = root.appendingPathComponent("Library")
        let library = WallpaperLibrary(rootURL: folder)
        let first = try await library.importFile(at: TestMedia.pngFile(in: root))
        let second = try await library.importFile(at: TestMedia.pngFile(in: root))
        library.setTags(["Anime", "Calm", "4K"], for: first.id)
        library.setTags(["Nature"], for: second.id)
        XCTAssertEqual(library.tagGroups, [TagGroup(category: nil, tags: ["4K", "Anime", "Calm", "Nature"])])

        library.setCategory(" Genre ", ofTag: "Anime")
        library.setCategory("genre", ofTag: "nature")
        library.setCategory("Mood", ofTag: "Calm")
        XCTAssertEqual(library.category(of: "ANIME"), "Genre")
        XCTAssertEqual(library.allCategories, ["Genre", "Mood"])
        XCTAssertEqual(library.tagGroups, [
            TagGroup(category: "Genre", tags: ["Anime", "Nature"]),
            TagGroup(category: "Mood", tags: ["Calm"]),
            TagGroup(category: nil, tags: ["4K"]),
        ])

        // The categories are kept apart from the wallpapers, in a file of their own.
        let reopened = WallpaperLibrary(rootURL: folder)
        XCTAssertEqual(reopened.category(of: "Nature"), "Genre")
        reopened.setCategory(nil, ofTag: "Calm")
        XCTAssertEqual(WallpaperLibrary(rootURL: folder).allCategories, ["Genre"])
        // A category lives as long as a wallpaper has one of its tags.
        reopened.setTags([], for: first.id)
        reopened.setTags([], for: second.id)
        XCTAssertTrue(reopened.tagGroups.isEmpty)
    }

    func testSearchLooksInNamesAndTagsAndTheFilterTakesAnyTagOfEachGroup() {
        func wallpaper(_ name: String, _ tags: [String]?) -> Wallpaper {
            Wallpaper(id: UUID(), name: name, kind: .video, fileName: "a.mp4", thumbnailFileName: nil, sourceFormat: "MP4",
                      wasConverted: false, pixelWidth: 1920, pixelHeight: 1080, duration: 5, hasAudio: false, fileSize: 1, tags: tags)
        }
        let lake = wallpaper("Japan Lake", ["Nature", "Night"])
        let frogs = wallpaper("Лягушки", ["Nature"])
        let plain = wallpaper("Steins Gate", nil)

        XCTAssertTrue(plain.matches(search: ""))
        XCTAssertTrue(plain.matches(search: "  "))
        XCTAssertTrue(lake.matches(search: "lake"))
        XCTAssertTrue(frogs.matches(search: "лягуш"))
        XCTAssertFalse(frogs.matches(search: "lake"))
        // A tag is found by the search as well as a name.
        XCTAssertTrue(frogs.matches(search: "natu"))
        XCTAssertFalse(plain.matches(search: "natu"))

        // Ticked tags of one category: any of them will do.
        XCTAssertTrue(frogs.matches(search: "", tagGroups: [["nature", "Anime"]]))
        XCTAssertFalse(plain.matches(search: "", tagGroups: [["Nature", "Anime"]]))
        // Tags of two categories: one of each is needed.
        XCTAssertTrue(lake.matches(search: "", tagGroups: [["Nature"], ["Night", "Day"]]))
        XCTAssertFalse(frogs.matches(search: "", tagGroups: [["Nature"], ["Night", "Day"]]))
        XCTAssertTrue(plain.matches(search: "", tagGroups: [[]]))
        XCTAssertFalse(lake.matches(search: "frog", tagGroups: [["Nature"]]))
    }

    func testLibraryIsPersistedRenamedAndCleanedUp() async throws {
        let png = root.appendingPathComponent("Calm.png")
        try TestMedia.writePNG(to: png, size: CGSize(width: 64, height: 64))
        let libraryRoot = root.appendingPathComponent("Library")
        let library = WallpaperLibrary(rootURL: libraryRoot)
        let item = try await library.importFile(at: png)
        library.rename(item.id, to: "  Quiet lake ")

        let reopened = WallpaperLibrary(rootURL: libraryRoot)
        XCTAssertEqual(reopened.items.map(\.name), ["Quiet lake"])

        let mediaFile = reopened.fileURL(for: item)
        let thumbnail = try XCTUnwrap(reopened.thumbnailURL(for: item))
        reopened.remove([item.id])
        XCTAssertTrue(reopened.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mediaFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: thumbnail.path))
        XCTAssertTrue(WallpaperLibrary(rootURL: libraryRoot).items.isEmpty)
    }
}

final class MusicFolderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = try TestMedia.directory()
        addTeardownBlock { [root] in try? FileManager.default.removeItem(at: root!) }
    }

    private func touch(_ path: String, _ text: String = "") throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func names(_ tracks: [URL]) -> [String] {
        tracks.map(\.lastPathComponent)
    }

    func testSubfoldersBecomePlaylistsAndLooseFilesBelongToNone() throws {
        try touch("intro.mp3")
        try touch("cover.jpg")
        try touch(".hidden.mp3")
        try touch("Rock/2 second.flac")
        try touch("Rock/10 tenth.mp3")
        try touch("Rock/1 first.m4a")
        try touch("Rock/Live/encore.wav")
        try touch("Rock/notes.txt")
        try touch("Calm/rain.aiff")
        try touch("Empty/readme.txt")

        let folder = MusicFolder.scan(root)

        XCTAssertEqual(folder.playlists.map(\.name), ["Calm", "Rock"], "a folder without music is not a playlist")
        // Numbers sort the way Finder shows them, and nested folders are part of the playlist.
        XCTAssertEqual(names(folder.tracks(inPlaylist: "Rock")), ["1 first.m4a", "2 second.flac", "10 tenth.mp3", "encore.wav"])
        XCTAssertEqual(names(folder.allTracks), ["intro.mp3", "rain.aiff", "1 first.m4a", "2 second.flac", "10 tenth.mp3", "encore.wav"])
        XCTAssertEqual(folder.tracks(inPlaylist: nil), folder.allTracks)
        XCTAssertEqual(folder.tracks(inPlaylist: "Deleted"), folder.allTracks, "a playlist that is gone falls back to everything")
    }

    func testM3UFilesArePlaylistsInTheirOwnOrder() throws {
        try touch("Songs/b.mp3")
        try touch("Songs/a.mp3")
        try touch("Songs/c.mp3")
        try touch("Favourites.m3u", "#EXTM3U\n#EXTINF:123,Artist - C\nSongs/c.mp3\r\nSongs\\a.mp3\nSongs/missing.mp3\nhttp://example.com/stream.mp3\n\n")

        let folder = MusicFolder.scan(root)

        XCTAssertEqual(folder.playlists.map(\.name), ["Favourites", "Songs"])
        XCTAssertEqual(names(folder.tracks(inPlaylist: "Favourites")), ["c.mp3", "a.mp3"], "playlist order, missing files and streams left out")
        XCTAssertEqual(names(folder.allTracks).sorted(), ["a.mp3", "b.mp3", "c.mp3"], "a file in two playlists is listed once")
    }

    func testAFolderWithoutMusicHasNoTracks() throws {
        try touch("picture.png")
        XCTAssertTrue(MusicFolder.scan(root).allTracks.isEmpty)
        XCTAssertTrue(MusicFolder.scan(root.appendingPathComponent("no such folder")).allTracks.isEmpty)
    }
}

final class TrackQueueTests: XCTestCase {
    private let tracks = (1...5).map { URL(fileURLWithPath: "/music/\($0).mp3") }

    func testPlaysInOrderAndStartsOver() {
        var queue = TrackQueue(tracks: tracks, shuffles: false)
        var played = [queue.current]
        for _ in 0..<6 { played.append(queue.advance()) }
        XCTAssertEqual(played, tracks + [tracks[0], tracks[1]])
    }

    func testCanStartWithTheTrackThatIsPlaying() {
        var queue = TrackQueue(tracks: tracks, shuffles: false, startingWith: tracks[3])
        XCTAssertEqual(queue.current, tracks[3])
        XCTAssertEqual(queue.advance(), tracks[4])
        XCTAssertEqual(queue.advance(), tracks[0])
        XCTAssertEqual(TrackQueue(tracks: tracks, shuffles: true, startingWith: tracks[3]).current, tracks[3])
    }

    func testShufflePlaysEveryTrackOnceBeforeRepeating() {
        for _ in 0..<50 {
            var queue = TrackQueue(tracks: tracks, shuffles: true)
            var played = [queue.current!]
            for _ in 0..<14 { played.append(queue.advance()!) }
            for pass in stride(from: 0, to: 15, by: 5) {
                XCTAssertEqual(Set(played[pass..<pass + 5]), Set(tracks))
            }
            for index in 1..<played.count {
                XCTAssertNotEqual(played[index], played[index - 1], "never the same track twice in a row")
            }
        }
    }

    func testAnEmptyQueueHasNothingToPlay() {
        var queue = TrackQueue()
        XCTAssertNil(queue.current)
        XCTAssertNil(queue.advance())
    }
}

@MainActor
final class PlaylistPlayerTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = try TestMedia.directory()
        addTeardownBlock { [root] in try? FileManager.default.removeItem(at: root!) }
    }

    /// Waits until the player reports each of the tracks in turn.
    private func expect(_ player: PlaylistPlayer, toPlay tracks: [URL], file: StaticString = #filePath, line: UInt = #line) async {
        for track in tracks {
            let deadline = Date().addingTimeInterval(5)
            while player.currentTrack != track, Date() < deadline {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertEqual(player.currentTrack?.lastPathComponent, track.lastPathComponent, file: file, line: line)
        }
    }

    func testPlaysTheListAroundAndSkipsFilesItCannotOpen() async throws {
        let first = root.appendingPathComponent("1.wav")
        let broken = root.appendingPathComponent("2.mp3")
        let last = root.appendingPathComponent("3.wav")
        try TestMedia.writeSilentWAV(to: first, seconds: 0.3)
        try Data("not audio".utf8).write(to: broken)
        try TestMedia.writeSilentWAV(to: last, seconds: 0.3)

        let player = PlaylistPlayer()
        player.volume = 0
        XCTAssertFalse(player.hasTracks)
        player.setTracks([first, broken, last], shuffled: false)
        XCTAssertTrue(player.hasTracks)
        XCTAssertEqual(player.currentTrack, first, "known before playback starts")

        player.setPlaying(true)
        await expect(player, toPlay: [last, first, last])
        player.setPlaying(false)
    }

    func testSkippingAndChangingTheList() async throws {
        let urls = try (1...3).map { index -> URL in
            let url = root.appendingPathComponent("\(index).wav")
            try TestMedia.writeSilentWAV(to: url, seconds: 5)
            return url
        }
        let player = PlaylistPlayer()
        player.volume = 0
        player.setTracks(urls, shuffled: false)
        player.skipToNext()
        XCTAssertEqual(player.currentTrack, urls[1])

        // The track that is playing stays when it is on the new list too…
        player.setTracks([urls[1], urls[2]], shuffled: false)
        XCTAssertEqual(player.currentTrack, urls[1])
        // …and gives way to the new list when it is not.
        player.setTracks([urls[0]], shuffled: false)
        XCTAssertEqual(player.currentTrack, urls[0])
        player.setTracks([], shuffled: false)
        XCTAssertNil(player.currentTrack)
        XCTAssertFalse(player.hasTracks)
    }
}

final class WallpaperSceneTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = try TestMedia.directory()
        addTeardownBlock { [root] in try? FileManager.default.removeItem(at: root!) }
    }

    func testASceneSurvivesBeingWrittenAndReadBack() throws {
        var clock = WallpaperScene.Layer(kind: .text, name: "Clock")
        clock.text = "{HH}:{mm}"
        clock.x = 25
        clock.fontSize = 14
        var logo = WallpaperScene.Layer(kind: .image, name: "Logo")
        logo.source = "media/logo.png"
        let scene = WallpaperScene(
            background: .init(kind: .video, source: "media/background.mp4", fit: .contain, blur: 8, brightness: 70),
            layers: [clock, logo]
        )
        try SceneProject.create(at: root, scene: scene)

        XCTAssertEqual(try SceneProject.read(from: root), scene)
        XCTAssertTrue(SceneProject.isScene(root))
        for file in ["index.html", "runtime.js", "custom.css", "custom.js", "scene.json", "media"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(file).path), file)
        }
    }

    func testMissingAndWrongValuesFallBackToDefaults() throws {
        // As a person might write it by hand: few keys, one of them of the wrong type.
        let json = #"{"background": {"kind": "image", "source": "a.png", "blur": "lots"}, "layers": [{"kind": "text", "text": "Hi", "x": 10}]}"#
        let scene = try JSONDecoder().decode(WallpaperScene.self, from: Data(json.utf8))

        XCTAssertEqual(scene.version, WallpaperScene.currentVersion)
        XCTAssertEqual(scene.background.kind, .image)
        XCTAssertEqual(scene.background.blur, 0)
        XCTAssertEqual(scene.background.brightness, 100)
        XCTAssertEqual(scene.layers.count, 1)
        XCTAssertEqual(scene.layers[0].text, "Hi")
        XCTAssertEqual(scene.layers[0].x, 10)
        XCTAssertEqual(scene.layers[0].y, 50)
        XCTAssertEqual(scene.layers[0].opacity, 100)
        XCTAssertTrue(scene.layers[0].isVisible)
        XCTAssertTrue(scene.layers[0].showsOnLockScreen, "scenes saved before the setting existed keep showing everything")
    }

    func testALayerCanBeLeftOutOfTheLockScreenPicture() throws {
        var clock = WallpaperScene.Layer(kind: .text, name: "Clock")
        XCTAssertTrue(clock.showsOnLockScreen)
        clock.showsOnLockScreen = false
        try SceneProject.create(at: root, scene: WallpaperScene(layers: [clock]))

        XCTAssertFalse(try SceneProject.read(from: root).layers[0].showsOnLockScreen)
        let text = try String(contentsOf: root.appendingPathComponent("scene.json"), encoding: .utf8)
        XCTAssertTrue(text.contains("\"showsOnLockScreen\" : false"))
        // The page has to act on it, or the setting would do nothing.
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("runtime.js"), encoding: .utf8).contains("showsOnLockScreen"))
    }

    func testChangesToAWallpaperEngineSceneAreKeptApartFromItsFiles() throws {
        var changes = WallpaperScene.EngineChanges(bloom: true)
        changes[object: 117].x = 900
        changes[object: 117].color = "#00FF00"
        changes[object: 117].showsOnLockScreen = false
        changes[object: 34].isVisible = false
        changes[object: 22][effect: 1].values["speed"] = [2.5]
        changes[object: 22][effect: 0].isVisible = false
        let scene = WallpaperScene(background: .init(kind: .engine, source: "engine/files.js", engine: changes))
        try SceneProject.create(at: root, scene: scene)
        XCTAssertEqual(try SceneProject.read(from: root), scene)
        XCTAssertEqual(changes.objects.map(\.id), [117, 34, 22])
        XCTAssertEqual(changes[object: 22].effects.map(\.id), [0, 1], "effects keep their order")
        // The page hands the changes to the player, which puts them over the scene's own.
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("runtime.js"), encoding: .utf8).contains("setChanges"))
        XCTAssertTrue(WallpaperEngineRuntime.script.contains("setChanges: function"))
        // What is kept out of the lock screen picture is hidden when the app draws that picture.
        XCTAssertTrue(WallpaperEngineRuntime.script.contains("window.wallaeroStill && change.showsOnLockScreen === false"))

        // Set back to what the scene has, an object is no longer listed, and a scene with no
        // changes says nothing of them.
        changes[object: 117] = WallpaperScene.ObjectChange(id: 117)
        changes[object: 34].isVisible = nil
        XCTAssertEqual(changes.objects.map(\.id), [22])
        changes[object: 22][effect: 1].values = [:]
        changes[object: 22][effect: 0].isVisible = nil
        changes.bloom = nil
        XCTAssertTrue(changes.isEmpty)
        XCTAssertEqual(changes.objects, [])
        try SceneProject.write(WallpaperScene(background: .init(kind: .engine, source: "engine/files.js", engine: changes)), to: root)
        XCTAssertFalse(try String(contentsOf: root.appendingPathComponent("scene.json"), encoding: .utf8).contains("\"engine\" : {"))

        // Written by hand, or by another version: what cannot be read is left out, not the rest.
        let json = #"{"background": {"kind": "engine", "source": "engine/files.js", "engine": {"bloom": "yes", "objects": [{"id": 5, "x": "far", "y": 10}]}}}"#
        let read = try JSONDecoder().decode(WallpaperScene.self, from: Data(json.utf8)).background.engine
        XCTAssertNil(read.bloom)
        XCTAssertNil(read[object: 5].x)
        XCTAssertEqual(read[object: 5].y, 10)
    }

    func testVariablesSurviveBeingWrittenAndFillInWhatIsMissing() throws {
        var color = WallpaperScene.Variable(kind: .color, title: "Цвет полос", key: "bars")
        color.color = "#FFAA00"
        var count = WallpaperScene.Variable(kind: .number, title: "Bars", key: "count")
        count.number = 22
        count.maximum = 64
        let scene = WallpaperScene(variables: [color, count])
        try SceneProject.write(scene, to: root)
        XCTAssertEqual(try SceneProject.read(from: root).variables, [color, count])

        // Written by hand: only what matters is there, and the key is not fit for code.
        let json = #"{"variables": [{"kind": "toggle", "key": "show clock"}, {"kind": "nonsense"}, {"title": "no kind"}]}"#
        try json.write(to: root.appendingPathComponent("scene.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try SceneProject.read(from: root).variables, [], "one bad variable loses them all, but not the scene")

        let good = #"{"variables": [{"kind": "toggle", "key": "show clock"}]}"#
        try good.write(to: root.appendingPathComponent("scene.json"), atomically: true, encoding: .utf8)
        let read = try XCTUnwrap(SceneProject.read(from: root).variables.first)
        XCTAssertEqual(read.key, "show_clock")
        XCTAssertEqual(read.title, "show_clock")
        XCTAssertTrue(read.isOn)
    }

    func testVariableKeysAreFitForCodeAndUnique() {
        XCTAssertEqual(WallpaperScene.Variable.key(from: "цвет полос"), "cvet_polos")
        XCTAssertEqual(WallpaperScene.Variable.key(from: "Цвет"), "Cvet", "capitals are kept")
        XCTAssertEqual(WallpaperScene.Variable.key(from: "bar-count!"), "bar_count")
        XCTAssertEqual(WallpaperScene.Variable.key(from: "2 colors"), "_2_colors")
        XCTAssertEqual(WallpaperScene.Variable.key(from: "  "), "variable")
        XCTAssertEqual(WallpaperScene.Variable.key(from: "barCount"), "barCount")

        let first = WallpaperScene.Variable(kind: .color, title: "Color", key: "color")
        let scene = WallpaperScene(variables: [first])
        XCTAssertEqual(scene.uniqueKey("Color"), "Color", "keys tell capitals apart, as code does")
        XCTAssertEqual(scene.uniqueKey("color"), "color2")
        XCTAssertEqual(scene.uniqueKey("color", for: first.id), "color", "a variable does not clash with itself")
    }

    func testStoringValuesLeavesTheRestOfTheSceneAlone() throws {
        var speed = WallpaperScene.Variable(kind: .number, title: "Speed", key: "speed")
        speed.number = 1
        let label = WallpaperScene.Variable(kind: .text, title: "Label", key: "label")
        try SceneProject.write(WallpaperScene(layers: [.init(kind: .text, name: "Clock")], variables: [speed, label]), to: root)

        // Meanwhile the scene is edited: a layer is added, a variable renamed, another removed.
        var edited = try SceneProject.read(from: root)
        edited.layers.append(.init(kind: .shape, name: "Box"))
        edited.variables[0].title = "Tempo"
        edited.variables.remove(at: 1)
        try SceneProject.write(edited, to: root)

        // The settings still hold the scene as it was, with new values.
        var fromSettings = speed
        fromSettings.number = 3
        var gone = label
        gone.text = "hello"
        let stored = try SceneProject.storeValues(of: [fromSettings, gone], in: root)

        XCTAssertEqual(stored.layers.map(\.name), ["Clock", "Box"])
        XCTAssertEqual(stored.variables.map(\.title), ["Tempo"])
        XCTAssertEqual(stored.variables[0].number, 3)
        XCTAssertEqual(try SceneProject.read(from: root), stored)

        // How the background fills the screen is stored only when it is given.
        XCTAssertEqual(stored.background.fit, .cover)
        let framed = try SceneProject.storeValues(of: [], framing: (fit: .contain, position: 80), in: root)
        XCTAssertEqual(framed.background.fit, .contain)
        XCTAssertEqual(framed.background.position, 80)
        XCTAssertEqual(framed.variables[0].number, 3, "the variables stay as they were")
        XCTAssertEqual(try SceneProject.storeValues(of: [], in: root).background.position, 80)
    }

    func testGeneratedFilesAreRefreshedButCustomOnesAreKept() throws {
        try SceneProject.create(at: root, scene: WallpaperScene())
        XCTAssertFalse(try SceneProject.refreshGeneratedFiles(in: root), "nothing to do right after creating")

        // An older version of the app left an old runtime; the user has written their own script.
        try "old".write(to: root.appendingPathComponent("runtime.js"), atomically: true, encoding: .utf8)
        try "mine".write(to: root.appendingPathComponent("custom.js"), atomically: true, encoding: .utf8)

        XCTAssertTrue(try SceneProject.refreshGeneratedFiles(in: root))
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("runtime.js"), encoding: .utf8).contains("wallaero"))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("custom.js"), encoding: .utf8), "mine")
    }

    func testMediaIsCopiedUnderAPlainUniqueName() throws {
        let picture = root.appendingPathComponent("Моя картинка #1.PNG")
        try TestMedia.writePNG(to: picture, size: CGSize(width: 8, height: 8))
        let project = root.appendingPathComponent("project")

        let first = try SceneProject.addMedia(picture, to: project)
        let second = try SceneProject.addMedia(picture, to: project)
        let named = try SceneProject.addMedia(picture, to: project, named: "background")

        XCTAssertEqual(first, "media/1.png", "only plain characters survive, as the name goes into a URL")
        XCTAssertEqual(second, "media/1-2.png")
        XCTAssertEqual(named, "media/background.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.appendingPathComponent(second).path))
    }
}

/// Which wallpapers of the library are selected, as clicks change it.
final class WallpaperSelectionTests: XCTestCase {
    private let ids = (0..<6).map { _ in UUID() }

    func testAClickSelectsOneAndCommandAddsAndTakesAway() {
        var selection = WallpaperSelection()
        selection.click(ids[0], .alone, in: ids)
        XCTAssertEqual(selection.ids, [ids[0]])
        XCTAssertEqual(selection.last, ids[0])
        selection.click(ids[2], .toggling, in: ids)
        XCTAssertEqual(selection.ids, [ids[0], ids[2]])
        XCTAssertEqual(selection.last, ids[2])
        // Taken away again, the one that is left is the one selected last.
        selection.click(ids[2], .toggling, in: ids)
        XCTAssertEqual(selection.ids, [ids[0]])
        XCTAssertEqual(selection.last, ids[0])
        selection.click(ids[0], .toggling, in: ids)
        XCTAssertTrue(selection.ids.isEmpty)
        XCTAssertNil(selection.last)
        // A plain click lets go of all the others.
        selection.click(ids[4], .toggling, in: ids)
        selection.click(ids[5], .toggling, in: ids)
        selection.click(ids[1], .alone, in: ids)
        XCTAssertEqual(selection.ids, [ids[1]])
    }

    func testShiftSelectsTheRunFromTheOneClickedBefore() {
        var selection = WallpaperSelection()
        // With none clicked before, it is a plain click.
        selection.click(ids[3], .extending, in: ids)
        XCTAssertEqual(selection.ids, [ids[3]])
        selection.click(ids[1], .extending, in: ids)
        XCTAssertEqual(selection.ids, Set(ids[1...3]))
        XCTAssertEqual(selection.last, ids[1])
        // The run still starts where it did.
        selection.click(ids[5], .extending, in: ids)
        XCTAssertEqual(selection.ids, Set(ids[3...5]))
        // One added with Command is where the next run starts.
        selection.click(ids[0], .toggling, in: ids)
        selection.click(ids[1], .extending, in: ids)
        XCTAssertEqual(selection.ids, Set(ids[0...1]))
        // The one clicked before is not among those shown any more: a plain click.
        selection.click(ids[4], .alone, in: ids)
        selection.click(ids[2], .extending, in: Array(ids[0...2]))
        XCTAssertEqual(selection.ids, [ids[2]])
    }

    func testAllAreSelectedAndWhatIsOutOfSightIsLetGo() {
        var selection = WallpaperSelection()
        selection.click(ids[2], .alone, in: ids)
        selection.selectAll(ids)
        XCTAssertEqual(selection.ids, Set(ids))
        XCTAssertEqual(selection.last, ids[2])
        // The search leaves three: only they stay selected, and so can be deleted.
        selection.keep(Array(ids[3...5]))
        XCTAssertEqual(selection.ids, Set(ids[3...5]))
        XCTAssertEqual(selection.last, ids[5])
        selection.keep([])
        XCTAssertTrue(selection.ids.isEmpty)
        XCTAssertNil(selection.last)
        selection.selectAll([])
        XCTAssertTrue(selection.ids.isEmpty)
        selection.select(ids[1])
        XCTAssertEqual(selection.last, ids[1])
        selection.select(nil)
        XCTAssertEqual(selection, WallpaperSelection())
    }
}

final class WebProjectTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = try TestMedia.directory()
        addTeardownBlock { [root] in try? FileManager.default.removeItem(at: root!) }
    }

    private func write(_ text: String, to name: String) throws {
        try text.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func testAFolderWithAnIndexPageIsAWebWallpaper() throws {
        try write("<html></html>", to: "index.html")
        try write("<html></html>", to: "about.html")
        let project = try XCTUnwrap(WebProject(folder: root))
        XCTAssertEqual(project.entryFile, "index.html")
        XCTAssertNil(project.title)
        XCTAssertNil(project.userPropertiesJSON)
        XCTAssertFalse(project.isScene)
    }

    func testReadsAWallpaperEngineProject() throws {
        try write("<html></html>", to: "main.html")
        try TestMedia.writePNG(to: root.appendingPathComponent("preview.png"), size: CGSize(width: 8, height: 8))
        try write(#"{"file": "main.html", "type": "web", "title": "Neon Rain", "preview": "preview.png", "general": {"properties": {"speed": {"type": "slider", "value": 3}}}}"#, to: "project.json")

        let project = try XCTUnwrap(WebProject(folder: root))
        XCTAssertEqual(project.entryFile, "main.html")
        XCTAssertEqual(project.title, "Neon Rain")
        XCTAssertEqual(project.previewFile, "preview.png")
        XCTAssertEqual(project.userPropertiesJSON, #"{"speed":{"type":"slider","value":3}}"#)
    }

    func testOtherKindsOfWallpaperEngineProjectsAndEmptyFoldersAreNotWebWallpapers() throws {
        XCTAssertNil(WebProject(folder: root), "no page at all")
        try write("<html></html>", to: "a.html")
        try write("<html></html>", to: "b.html")
        XCTAssertNil(WebProject(folder: root), "two pages and neither is index.html: which one?")
        try write("<html></html>", to: "index.html")
        try write(#"{"file": "scene.pkg", "type": "scene"}"#, to: "project.json")
        XCTAssertNil(WebProject(folder: root), "a Wallpaper Engine scene is not a page")
    }

    func testASceneIsRecognisedBeforeItsPageIsGenerated() throws {
        try write("{}", to: "scene.json")
        let project = try XCTUnwrap(WebProject(folder: root))
        XCTAssertTrue(project.isScene)
        XCTAssertEqual(project.entryFile, "index.html")
    }
}

@MainActor
final class WallpaperEngineTests: XCTestCase {
    private var root: URL!
    /// The folder of a wallpaper as Wallpaper Engine keeps it.
    private var wallpaper: URL { root.appendingPathComponent("3808790239") }

    override func setUpWithError() throws {
        root = try TestMedia.directory()
        addTeardownBlock { [root] in try? FileManager.default.removeItem(at: root!) }
        try FileManager.default.createDirectory(at: wallpaper, withIntermediateDirectories: true)
    }

    private func write(_ text: String, to name: String) throws {
        try text.write(to: wallpaper.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    /// A page with settings of every kind, named in two languages.
    private func writePage() throws {
        try write("<html></html>", to: "index.html")
        try TestMedia.writePNG(to: wallpaper.appendingPathComponent("preview.png"), size: CGSize(width: 8, height: 8))
        try write(#"""
        {"file": "index.html", "type": "web", "title": "Koi Pond", "preview": "preview.png", "general": {
          "localization": {
            "en-us": {"ui_count": "Number of Koi", "ui_weather": "Weather", "ui_clear": "Clear", "ui_rain": "Rain", "ui_accent": "Accent"},
            "ru-ru": {"ui_count": "Количество карпов"}
          },
          "properties": {
            "note":     {"order": 0, "type": "text", "text": "Just a heading"},
            "weather":  {"order": 4, "type": "combo", "text": "ui_weather", "value": 1,
                         "options": [{"label": "ui_clear", "value": 0}, {"label": "ui_rain", "value": 1}]},
            "accent":   {"order": 1, "type": "color", "text": "ui_accent", "value": "0.18 0.55 0.96"},
            "fishCount": {"order": 2, "type": "slider", "text": "ui_count", "value": 66, "min": 10, "max": 200},
            "fish-size": {"order": 3, "type": "slider", "text": "<h3>Fish&nbsp;size</h3>", "value": 1.45, "min": 0.5, "max": 3,
                          "fraction": true, "precision": 2},
            "density":  {"order": 5, "type": "combo", "text": "Density", "value": "2",
                         "options": [{"label": "Small", "value": "1"}, {"label": "Large", "value": "2"}]},
            "shy":      {"order": 6, "type": "bool", "text": "Shy", "value": false},
            "motto":    {"order": 7, "type": "textinput", "text": "Motto", "value": "hello"}
          }}}
        """#, to: "project.json")
    }

    func testThePagesSettingsBecomeVariables() throws {
        try writePage()
        let project = try XCTUnwrap(WallpaperEngineProject(folder: wallpaper, languages: ["ru-KZ", "en-KZ"]))
        XCTAssertEqual(project.kind, .web)
        XCTAssertEqual(project.title, "Koi Pond")
        XCTAssertEqual(project.file, "index.html")
        XCTAssertEqual(project.previewFile, "preview.png")

        // In the order the project gives; the heading has no value and is left out.
        let variables = project.variables
        XCTAssertEqual(variables.map(\.property), ["accent", "fishCount", "fish-size", "weather", "density", "shy", "motto"])
        // The name the page knows a setting by is kept as it is; the scene's own key is made plain.
        XCTAssertEqual(variables.map(\.key), ["accent", "fishCount", "fish_size", "weather", "density", "shy", "motto"])
        XCTAssertEqual(variables.map(\.kind), [.color, .number, .number, .choice, .choice, .toggle, .text])
        // Russian where the wallpaper has it, English where it has not, the text itself without its HTML otherwise.
        XCTAssertEqual(variables.map(\.title), ["Accent", "Количество карпов", "Fish size", "Weather", "Density", "Shy", "Motto"])

        XCTAssertEqual(variables[0].color, "#2E8CF5")
        XCTAssertEqual([variables[1].number, variables[1].minimum, variables[1].maximum, variables[1].step], [66, 10, 200, 1])
        XCTAssertEqual([variables[2].number, variables[2].minimum, variables[2].maximum, variables[2].step], [1.45, 0.5, 3, 0.01])
        XCTAssertEqual(variables[3].options, ["Clear", "Rain"])
        XCTAssertEqual(variables[3].values, [.number(0), .number(1)])
        XCTAssertEqual(variables[3].text, "Rain")
        XCTAssertEqual(variables[4].values, [.text("1"), .text("2")])
        XCTAssertEqual(variables[4].text, "Large")
        XCTAssertFalse(variables[5].isOn)
        XCTAssertEqual(variables[6].text, "hello")
    }

    func testAnOptionsValueKeepsItsKindInTheSceneFile() throws {
        var variable = WallpaperScene.Variable(kind: .choice, title: "Weather", key: "weather")
        variable.property = "weather"
        variable.options = ["Clear", "Rain", "Auto"]
        variable.values = [.number(0), .text("1"), .flag(true)]
        let scene = WallpaperScene(variables: [variable])
        let data = try SceneProject.encoded(scene, readable: false)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""values":[0,"1",true]"#))
        XCTAssertEqual(try JSONDecoder().decode(WallpaperScene.self, from: data), scene)

        // A scene written before variables could stand for a page's settings.
        let old = #"{"variables": [{"kind": "number", "key": "gain", "title": "Gain", "number": 3}]}"#
        let read = try JSONDecoder().decode(WallpaperScene.self, from: Data(old.utf8))
        XCTAssertNil(read.variables[0].property)
        XCTAssertNil(read.variables[0].values)
    }

    func testAPageIsImportedAsASceneWithThePageBehindIt() async throws {
        try writePage()
        try write("body {}", to: "style.css")
        let library = WallpaperLibrary(rootURL: root.appendingPathComponent("Library"))
        let added = try await library.importItem(at: wallpaper, languages: ["en"])
        let item = try XCTUnwrap(added.first)
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(item.name, "Koi Pond")
        XCTAssertEqual(item.sourceFormat, "SCENE")
        XCTAssertNotNil(item.thumbnailFileName, "the preview that came with it")
        XCTAssertTrue(library.isScene(item))

        let folder = library.projectURL(for: item)
        let scene = try SceneProject.read(from: folder)
        XCTAssertEqual(scene.background.kind, .page)
        XCTAssertEqual(scene.background.source, "page/index.html")
        XCTAssertFalse(scene.background.isMedia)
        XCTAssertEqual(scene.variables.count, 7)
        // The whole wallpaper came along, next to the scene's own files.
        for name in ["page/index.html", "page/style.css", "page/project.json", "index.html", "runtime.js", "scene.json"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path), name)
        }

        // What the wallpaper's settings change is kept, the page's side of a variable with it.
        var changed = scene.variables
        changed[1].number = 12
        let stored = try SceneProject.storeValues(of: changed, in: folder)
        XCTAssertEqual(stored.variables[1].number, 12)
        XCTAssertEqual(stored.variables[1].property, "fishCount")
        XCTAssertEqual(stored.variables[3].values, [.number(0), .number(1)])
    }

    func testAnArchiveOfAWallpaperIsUnpackedAndImported() async throws {
        try writePage()
        // As the sites pack them: the wallpaper in a folder, their own files next to it.
        try "from a site".write(to: root.appendingPathComponent("source.url"), atomically: true, encoding: .utf8)
        let archive = root.appendingPathComponent("3808790239_SITE.zip")
        try zip([wallpaper, root.appendingPathComponent("source.url")], into: archive)

        let library = WallpaperLibrary(rootURL: root.appendingPathComponent("Library"))
        let added = try await library.importItem(at: archive, languages: ["en"])
        XCTAssertEqual(added.map(\.name), ["Koi Pond"])
        XCTAssertEqual(try SceneProject.read(from: library.projectURL(for: added[0])).background.kind, .page)

        // The folder such an archive was unpacked into is taken the same way.
        let unpacked = root.appendingPathComponent("Unpacked")
        try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: wallpaper, to: unpacked.appendingPathComponent("3808790239"))
        try "from a site".write(to: unpacked.appendingPathComponent("EN.txt"), atomically: true, encoding: .utf8)
        let again = try await library.importItem(at: unpacked, languages: ["en"])
        XCTAssertEqual(again.map(\.name), ["Koi Pond"])

        let nothing = root.appendingPathComponent("notes.zip")
        try zip([root.appendingPathComponent("source.url")], into: nothing)
        do {
            _ = try await library.importItem(at: nothing)
            XCTFail("an archive without a wallpaper was taken")
        } catch {
            XCTAssertEqual(error as? ImportError, .emptyArchive)
        }
        XCTAssertEqual(library.items.count, 2)
    }

    func testAnArchiveWithSeveralWallpapersGivesThemAll() async throws {
        // As some sites pack them: two wallpapers, each in a folder of its own.
        let files = FileManager.default
        var folders: [URL] = []
        for (folder, title) in [("2599696783", "Black Smoke"), ("3502549178", "Behind the Veil")] {
            let url = root.appendingPathComponent(folder)
            try files.createDirectory(at: url, withIntermediateDirectories: true)
            try "<html></html>".write(to: url.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
            try #"{"file": "index.html", "type": "web", "title": "\#(title)"}"#
                .write(to: url.appendingPathComponent("project.json"), atomically: true, encoding: .utf8)
            folders.append(url)
        }
        // One that cannot be brought in is passed over as long as another can.
        let broken = root.appendingPathComponent("111")
        try files.createDirectory(at: broken, withIntermediateDirectories: true)
        try #"{"file": "tool.exe", "type": "application"}"#.write(to: broken.appendingPathComponent("project.json"), atomically: true, encoding: .utf8)
        let archive = root.appendingPathComponent("3502549178_SITE.zip")
        try zip(folders + [broken], into: archive)

        let library = WallpaperLibrary(rootURL: root.appendingPathComponent("Library"))
        let added = try await library.importItem(at: archive, languages: ["en"])
        XCTAssertEqual(added.map(\.name), ["Black Smoke", "Behind the Veil"])
        XCTAssertEqual(library.items.count, 2)
    }

    func testKindsThatNeedWallpaperEngineItselfAreRefusedByName() async throws {
        try write("MZ", to: "clock.exe")
        try write(#"{"file": "clock.exe", "type": "Application", "title": "Clock"}"#, to: "project.json")
        XCTAssertEqual(WallpaperEngineProject(folder: wallpaper)?.kind, .other("application"))
        let library = WallpaperLibrary(rootURL: root.appendingPathComponent("Library"))
        do {
            _ = try await library.importItem(at: wallpaper)
            XCTFail("an application was taken")
        } catch {
            XCTAssertEqual(error as? ImportError, .unsupportedWallpaperEngineKind("application"))
        }
        XCTAssertTrue(library.items.isEmpty)
    }

    func testNamesThatLeadOutOfTheFolderAreNotFollowed() throws {
        XCTAssertTrue(Archive.staysInside("3808790239/src/app.js"))
        XCTAssertTrue(Archive.staysInside("a..b/file"))
        XCTAssertFalse(Archive.staysInside("../outside.txt"))
        XCTAssertFalse(Archive.staysInside("folder/../../outside.txt"))
        XCTAssertFalse(Archive.staysInside("/etc/hosts"))

        try "<html></html>".write(to: root.appendingPathComponent("outside.html"), atomically: true, encoding: .utf8)
        try write(#"{"file": "../outside.html", "type": "web"}"#, to: "project.json")
        XCTAssertNil(try XCTUnwrap(WallpaperEngineProject(folder: wallpaper)).file)

        // A project.json of some other tool is not a wallpaper.
        try write(#"{"name": "my-app", "version": "1.0"}"#, to: "project.json")
        XCTAssertNil(WallpaperEngineProject(folder: wallpaper))
    }

    func testAProjectSaysItsGenresItsKindAndWhomItIsFor() throws {
        try write("<html></html>", to: "index.html")
        // Genres of the Workshop, one the author made up, a repeat, the one that says nothing,
        // and what is no name at all.
        try write(#"{"file": "index.html", "type": "web", "contentrating": "Mature", "tags": ["Anime", "Sci-Fi", "Neverness to Everness", "anime", "Unspecified", 7, " "]}"#,
                  to: "project.json")
        let project = try XCTUnwrap(WallpaperEngineProject(folder: wallpaper))
        XCTAssertEqual(project.tags.map(\.name), ["Anime", "Science fiction", "Neverness to Everness", "Web page", "For adults"])
        XCTAssertEqual(project.tags.map(\.category), ["Genre", "Genre", "Genre", "Kind", "Age rating"])

        // A project that says nothing of itself still has its kind.
        try write(#"{"file": "index.html", "type": "web"}"#, to: "project.json")
        XCTAssertEqual(WallpaperEngineProject(folder: wallpaper)?.tags, [WallpaperEngineProject.Tag(name: "Web page", category: "Kind")])
        // One genre written as a text, a rating the app does not know.
        try write(#"{"file": "index.html", "type": "web", "tags": "Relaxing", "contentrating": "Unknown"}"#, to: "project.json")
        XCTAssertEqual(WallpaperEngineProject(folder: wallpaper)?.tags.map(\.name), ["Relaxing", "Web page"])
    }

    func testAWallpaperComesWithItsTagsAndOnlyNewOnesGetACategory() async throws {
        let library = WallpaperLibrary(rootURL: root.appendingPathComponent("Library"))
        // The user has a tag of their own already, and keeps it in no category.
        let own = try await library.importFile(at: TestMedia.pngFile(in: root))
        library.setTags(["anime"], for: own.id)

        try write("<html></html>", to: "index.html")
        try write(#"{"file": "index.html", "type": "web", "title": "Koi", "contentrating": "Everyone", "tags": ["Anime", "Relaxing"]}"#, to: "project.json")
        let added = try await library.importItem(at: wallpaper, languages: ["en"])
        XCTAssertEqual(added.first?.tagList, ["anime", "Relaxing", "Web page", "For everyone"], "the spelling in use is kept")
        XCTAssertNil(library.category(of: "anime"), "a tag the user has stays where they keep it")
        XCTAssertEqual(library.category(of: "Relaxing"), "Genre")
        XCTAssertEqual(library.category(of: "Web page"), "Kind")
        XCTAssertEqual(library.category(of: "For everyone"), "Age rating")

        // Moved by the user, a tag is not put back by the next wallpaper that has it.
        library.setCategory("Mood", ofTag: "Relaxing")
        library.setCategory(nil, ofTag: "Web page")
        let again = try await library.importItem(at: wallpaper, languages: ["en"])
        XCTAssertEqual(again.first?.tagList, ["anime", "Relaxing", "Web page", "For everyone"])
        XCTAssertEqual(library.category(of: "Relaxing"), "Mood")
        XCTAssertNil(library.category(of: "Web page"))
    }

    func testAnArchiveOfAnotherKindIsUnpackedToo() async throws {
        XCTAssertTrue(Archive.isArchive(URL(fileURLWithPath: "/tmp/1491259571_SITE.RAR")))
        XCTAssertTrue(Archive.isArchive(URL(fileURLWithPath: "/tmp/wallpaper.7z")))
        XCTAssertFalse(Archive.isArchive(URL(fileURLWithPath: "/tmp/wallpaper.mp4")))

        try writePage()
        // Names that are not plain Latin letters are common in wallpapers.
        try "заметка".write(to: wallpaper.appendingPathComponent("说明 — заметка.txt"), atomically: true, encoding: .utf8)
        let archive = root.appendingPathComponent("3808790239_SITE.7z")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        process.arguments = ["--format", "7zip", "-cf", archive.path, "-C", root.path, wallpaper.lastPathComponent]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let library = WallpaperLibrary(rootURL: root.appendingPathComponent("Library"))
        let added = try await library.importItem(at: archive, languages: ["en"])
        XCTAssertEqual(added.map(\.name), ["Koi Pond"])
        let page = library.projectURL(for: added[0]).appendingPathComponent("page")
        XCTAssertEqual(try String(contentsOf: page.appendingPathComponent("说明 — заметка.txt"), encoding: .utf8), "заметка")

        // What only calls itself an archive is refused as one.
        let broken = root.appendingPathComponent("broken.rar")
        try Data("not an archive".utf8).write(to: broken)
        do {
            _ = try await library.importItem(at: broken)
            XCTFail("a file that is no archive was unpacked")
        } catch {
            XCTAssertEqual(error as? ImportError, .unreadableArchive)
        }
    }

    func testWallpaperEngineWritesAColorAsThreeNumbers() {
        XCTAssertEqual(WallpaperEngineProject.hexColor("1 0 0"), "#FF0000")
        XCTAssertEqual(WallpaperEngineProject.hexColor("0.18 0.55 0.96"), "#2E8CF5")
        XCTAssertEqual(WallpaperEngineProject.hexColor("2 -1 0.5"), "#FF0080")
        XCTAssertNil(WallpaperEngineProject.hexColor("blue"))
    }

    private func zip(_ sources: [URL], into archive: URL) throws {
        let staging = root.appendingPathComponent("zip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        for source in sources {
            try FileManager.default.copyItem(at: source, to: staging.appendingPathComponent(source.lastPathComponent))
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", staging.path, archive.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        try FileManager.default.removeItem(at: staging)
    }
}

/// Wallpaper Engine's own scenes: the package they come in, their pictures, and what becomes of
/// them. The files are put together here the way Wallpaper Engine writes them.
@MainActor
final class WallpaperEngineSceneTests: XCTestCase {
    private var root: URL!
    private var wallpaper: URL { root.appendingPathComponent("1257978685") }

    override func setUpWithError() throws {
        root = try TestMedia.directory()
        addTeardownBlock { [root] in try? FileManager.default.removeItem(at: root!) }
        try FileManager.default.createDirectory(at: wallpaper, withIntermediateDirectories: true)
    }

    private func number(_ value: Int) -> Data {
        withUnsafeBytes(of: UInt32(truncatingIfNeeded: value).littleEndian) { Data($0) }
    }

    private func text(_ value: String) -> Data {
        number(value.utf8.count) + Data(value.utf8)
    }

    /// A `scene.pkg`: the names with the place of each file, then the files.
    private func package(_ files: [(name: String, data: Data)]) -> Data {
        var list = text("PKGV0001") + number(files.count)
        var offset = 0
        for file in files {
            list += text(file.name) + number(offset) + number(file.data.count)
            offset += file.data.count
        }
        return files.reduce(list) { $0 + $1.data }
    }

    /// A `.tex`: a picture of `width` by `height` in the corner of a canvas, every pixel of it
    /// `color` and the rest of the canvas see-through black.
    private func texture(width: Int, height: Int, canvas: Int, color: [UInt8], version: Int = 2, packed: Bool = true) -> Data {
        var pixels = Data(count: canvas * canvas * 4)
        for y in 0..<height {
            for x in 0..<width {
                pixels.replaceSubrange(((y * canvas + x) * 4)..<((y * canvas + x) * 4 + 4), with: color)
            }
        }
        return texture(pixels: pixels, format: 0, width: width, height: height, canvas: canvas, version: version, packed: packed)
    }

    private func texture(pixels: Data, format: Int, width: Int, height: Int, canvas: Int, version: Int = 2,
                         packed: Bool = false, pictureFile: Bool = false, video: Bool = false, flags: Int = 2) -> Data {
        var file = Data("TEXV0005\0TEXI0001\0".utf8)
        for value in [format, flags, canvas, canvas, width, height, 0] {
            file += number(value)
        }
        file += Data("TEXB000\(version)\0".utf8) + number(1)
        if version >= 3 {
            file += number(pictureFile ? 13 : -1)
        }
        if version >= 4 {
            file += number(video ? 1 : 0)
        }
        file += number(1) + number(canvas) + number(canvas)
        var stored = pixels
        if version >= 2 {
            if packed {
                stored = lz4(pixels)
            }
            file += number(packed ? 1 : 0) + number(pixels.count)
        }
        return file + number(stored.count) + stored
    }

    private func lz4(_ data: Data) -> Data {
        var packed = Data(count: data.count + 1024)
        let capacity = packed.count
        let written = packed.withUnsafeMutableBytes { target in
            data.withUnsafeBytes { source in
                compression_encode_buffer(target.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_LZ4_RAW)
            }
        }
        XCTAssertGreaterThan(written, 0)
        return packed.prefix(written)
    }

    /// The color of a pixel, counted from the top left.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return bytes
    }

    /// The files of a picture: the object's model, its material and the texture.
    private func picture(_ name: String, texture: Data, blending: String = "translucent") -> [(name: String, data: Data)] {
        [("models/\(name).json", Data(#"{"autosize": true, "material": "materials/\#(name).json"}"#.utf8)),
         ("materials/\(name).json", Data(#"{"passes": [{"blending": "\#(blending)", "shader": "genericimage2", "textures": ["\#(name)"]}]}"#.utf8)),
         ("materials/\(name).tex", texture)]
    }

    // MARK: - The package

    func testAPackageGivesItsFilesByName() throws {
        let data = package([("scene.json", Data(#"{"objects": []}"#.utf8)), ("materials/Sky.tex", Data([1, 2, 3]))])
        let read = try XCTUnwrap(WallpaperEnginePackage(data: data))
        XCTAssertEqual(read.names, ["scene.json", "materials/Sky.tex"])
        XCTAssertEqual(read.data(named: "materials/Sky.tex"), Data([1, 2, 3]))
        // Wallpaper Engine is a Windows program: neither the case nor the slash matters.
        XCTAssertEqual(read.data(named: #"Materials\sky.tex"#), Data([1, 2, 3]))
        XCTAssertNotNil(read.json(named: "scene.json")?["objects"])
        XCTAssertNil(read.data(named: "missing.json"))
    }

    func testAFileIsFoundWhetherTheMarksOfItsLettersAreWrittenApartOrNot() throws {
        // The Mac gives names of files with a letter's marks written apart (ブ as フ and ゛); a
        // scene writes them as one (3660962877's song).
        let apart = "sounds/ナブナ.mp3".decomposedStringWithCanonicalMapping
        let read = try XCTUnwrap(WallpaperEnginePackage(data: package([("scene.json", Data("{}".utf8)), (apart, Data([7]))])))
        XCTAssertEqual(read.data(named: "sounds/ナブナ.mp3".precomposedStringWithCanonicalMapping), Data([7]))
        XCTAssertEqual(WallpaperEngineScene.key(apart), WallpaperEngineScene.key("sounds/ナブナ.mp3"))
    }

    func testAPackageThatNamesPlacesPastItsEndIsNotRead() {
        XCTAssertNil(WallpaperEnginePackage(data: Data("not a package".utf8)))
        XCTAssertNil(WallpaperEnginePackage(data: text("PKGV0001") + number(1) + text("a.json") + number(0) + number(500)))
        XCTAssertNil(WallpaperEnginePackage(data: text("PKGV0001") + number(3) + text("a.json") + number(0) + number(0)))
        XCTAssertNil(WallpaperEnginePackage(data: text("PKGV0001") + number(1) + number(1_000_000)))
        XCTAssertNil(WallpaperEnginePackage(data: text("ZIPV0001") + number(0)))
    }

    func testASceneNotYetPackedIsReadFromItsFolder() throws {
        try #"{"objects": []}"#.write(to: wallpaper.appendingPathComponent("scene.json"), atomically: true, encoding: .utf8)
        try "outside".write(to: root.appendingPathComponent("outside.txt"), atomically: true, encoding: .utf8)
        let read = try XCTUnwrap(WallpaperEnginePackage(folder: wallpaper))
        XCTAssertNotNil(read.json(named: "scene.json"))
        XCTAssertNil(read.data(named: "../outside.txt"))
        XCTAssertNil(WallpaperEnginePackage(folder: root), "no scene here")
    }

    func testASceneMadeFromATemplateIsReadUnderTheNameItsProjectGives() throws {
        // Wallpaper Engine's GIF template keeps `gifscene.json` in `gifscene.pkg` (843532366).
        try #"{"file": "gifscene.json", "type": "scene"}"#.write(to: wallpaper.appendingPathComponent("project.json"), atomically: true, encoding: .utf8)
        try package([("gifscene.json", Data(#"{"objects": [1]}"#.utf8)), ("models/a.json", Data("{}".utf8))])
            .write(to: wallpaper.appendingPathComponent("gifscene.pkg"))
        let read = try XCTUnwrap(WallpaperEnginePackage(folder: wallpaper))
        XCTAssertEqual(read.names, ["scene.json", "models/a.json"])
        XCTAssertEqual(read.json(named: "scene.json")?["objects"] as? [Int], [1])
        // Laid out as loose files, the scene keeps its own name and is still found.
        let project = root.appendingPathComponent("project", isDirectory: true)
        try WallpaperEngineProjectFolder.unpack(wallpaper, to: project)
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.appendingPathComponent("gifscene.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.appendingPathComponent("gifscene.pkg").path))
        XCTAssertEqual(try XCTUnwrap(WallpaperEnginePackage(folder: project)).json(named: "scene.json")?["objects"] as? [Int], [1])
    }

    // MARK: - Pictures

    func testAPictureIsUnpackedAndCutOutOfItsCanvas() throws {
        for (version, packed) in [(1, false), (2, false), (2, true), (3, true)] {
            let file = texture(width: 6, height: 3, canvas: 8, color: [255, 0, 0, 255], version: version, packed: packed)
            let image = try XCTUnwrap(WallpaperEngineTexture.image(from: file), "version \(version), packed: \(packed)")
            XCTAssertEqual([image.width, image.height], [6, 3])
            XCTAssertEqual(try pixel(image, 5, 2), [255, 0, 0, 255])
        }
    }

    func testAPictureKeepsItsSeeThroughPixelsAndIsNotTurnedOver() throws {
        var pixels = Data(count: 4 * 4 * 4)
        pixels.replaceSubrange(0..<4, with: [0, 255, 0, 255]) // the top left pixel
        let image = try XCTUnwrap(WallpaperEngineTexture.image(from: texture(pixels: pixels, format: 0, width: 4, height: 4, canvas: 4)))
        XCTAssertEqual(try pixel(image, 0, 0), [0, 255, 0, 255])
        XCTAssertEqual(try pixel(image, 0, 3), [0, 0, 0, 0])
    }

    func testAPictureKeptAsAFileOfAUsualKindIsRead() throws {
        let png = root.appendingPathComponent("inside.png")
        try TestMedia.writePNG(to: png, size: CGSize(width: 8, height: 8))
        let file = texture(pixels: try Data(contentsOf: png), format: 0, width: 8, height: 8, canvas: 8, version: 3, pictureFile: true)
        let image = try XCTUnwrap(WallpaperEngineTexture.image(from: file))
        XCTAssertEqual([image.width, image.height], [8, 8])
    }

    func testTheNewestKindOfTextureIsRead() throws {
        // The fourth version of the container is the third with a number more.
        let pixels = Data([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 9, 9, 9, 255])
        let plain = texture(pixels: pixels, format: 0, width: 2, height: 2, canvas: 2, version: 4, packed: true)
        let image = try XCTUnwrap(WallpaperEngineTexture.image(from: plain))
        XCTAssertEqual([image.width, image.height], [2, 2])
        XCTAssertEqual(try pixel(image, 1, 0), [0, 255, 0, 255])
        XCTAssertEqual(try pixel(image, 0, 1), [0, 0, 255, 255])
        // A picture file inside it, too.
        let png = root.appendingPathComponent("inside.png")
        try TestMedia.writePNG(to: png, size: CGSize(width: 8, height: 8))
        let file = texture(pixels: try Data(contentsOf: png), format: 0, width: 8, height: 8, canvas: 8, version: 4, pictureFile: true)
        XCTAssertEqual(WallpaperEngineTexture.image(from: file)?.width, 8)
        // A video, said by the flag, is not a picture.
        XCTAssertNil(WallpaperEngineTexture.image(from: texture(pixels: pixels, format: 0, width: 2, height: 2, canvas: 2, version: 4, flags: 2 | 32)))
        // The number more counts conditions on the wallpaper's settings, written before the
        // picture (3737268876's Link).
        var marked = Data()
        let head = texture(pixels: pixels, format: 0, width: 2, height: 2, canvas: 2, version: 4, packed: true)
        let place = try XCTUnwrap(head.range(of: Data("TEXB0004\0".utf8))).upperBound + 8
        marked += head[..<place] + number(1) + number(1) + number(1) + number(0)
        marked += Data("{\"condition\":{\"condition\":\"3\",\"name\":\"tuniccolor\"}}\0".utf8) + head[(place + 4)...]
        let conditional = try XCTUnwrap(WallpaperEngineTexture.image(from: marked))
        XCTAssertEqual(try pixel(conditional, 1, 0), [0, 255, 0, 255])
    }

    /// An MP4 file: a row of parts, each with its length and a name of four letters.
    private func movie() -> Data {
        func part(_ name: String, _ body: Data) -> Data {
            withUnsafeBytes(of: UInt32(8 + body.count).bigEndian) { Data($0) } + Data(name.utf8) + body
        }
        return part("ftyp", Data("isomiso2avc1mp41".utf8)) + part("moov", Data(count: 24)) + part("mdat", Data([1, 2, 3, 4, 5]))
    }

    func testATextureThatHoldsAVideoGivesTheVideo() throws {
        let movie = movie()
        // The third version says so among the texture's flags, and has the video where the pixels would be.
        let flagged = texture(pixels: movie, format: 0, width: 638, height: 746, canvas: 1024, version: 3, flags: 2 | 32)
        let read = try XCTUnwrap(WallpaperEngineTexture.texture(from: flagged))
        XCTAssertTrue(read.pictures.isEmpty)
        XCTAssertEqual(read.video?.file, movie)
        XCTAssertEqual([read.video?.width, read.video?.height], [638, 746])
        XCTAssertTrue(read.isClamped)
        XCTAssertNil(WallpaperEngineTexture.image(from: flagged), "a video is not a picture")

        // The fourth version says so by a number of its own; more may stand before the video
        // than before pixels, and what follows the video is not the video.
        var later = Data("TEXV0005\0TEXI0001\0".utf8)
        for value in [0, 2, 1024, 1024, 638, 746, 0] {
            later += number(value)
        }
        let head: [Data] = [Data("TEXB0004\0".utf8), number(1), number(-1), number(1), number(1), number(2), text("{}"), number(1),
                            number(638), number(746), number(0), number(0), number(movie.count)]
        head.forEach { later += $0 }
        later += movie
        later += Data(repeating: 0xFF, count: 9)
        XCTAssertEqual(WallpaperEngineTexture.texture(from: later)?.video?.file, movie)

        // Flagged as a video, with none inside.
        XCTAssertNil(WallpaperEngineTexture.texture(from: texture(pixels: Data(count: 64), format: 0, width: 4, height: 4, canvas: 4,
                                                                 version: 3, flags: 32)))
    }

    func testNamesAnEarlySceneLeavesEmptyAreNotTakenForWhatTheyName() throws {
        // Early versions of Wallpaper Engine wrote every name an object may have, with nothing
        // under most: a particle system with an empty model is no model, and not left out.
        let json = #"{"objects": [{"name": "Sky", "image": "models/Sky.json", "model": null, "light": null},"#
            + #" {"name": "Fireflies", "particle": "particles/snow.json", "image": null, "model": null},"#
            + #" {"name": "Lamp", "image": null, "light": "point", "model": null}]}"#
        let files = [("scene.json", Data(json.utf8)), ("particles/snow.json", Data(#"{"maxcount": 10}"#.utf8))]
            + picture("Sky", texture: texture(width: 2, height: 2, canvas: 2, color: [0, 0, 255, 255]))
        let leftOut = try WallpaperEngineScene.export(try XCTUnwrap(WallpaperEnginePackage(data: package(files))), into: root.appendingPathComponent("Scene"))
        XCTAssertEqual(leftOut, .init(animations: 0, objects: 0), "the light is played")

        // A scene of nothing but empty names has nothing to draw.
        let empty = [("scene.json", Data(#"{"objects": [{"name": "Nothing", "image": null, "particle": null, "text": null}]}"#.utf8))]
        XCTAssertThrowsError(try WallpaperEngineScene.export(try XCTUnwrap(WallpaperEnginePackage(data: package(empty))), into: root.appendingPathComponent("Empty"))) {
            XCTAssertEqual($0 as? ImportError, .noPicturesInScene)
        }
    }

    func testAVideoOfASceneIsLaidOutAsAVideo() throws {
        let json = #"{"objects": [{"name": "Film", "image": "models/Film.json"}]}"#
        let files = [("scene.json", Data(json.utf8))]
            + picture("Film", texture: texture(pixels: movie(), format: 0, width: 638, height: 746, canvas: 1024, version: 3, flags: 2 | 32))
        let folder = root.appendingPathComponent("Scene")
        _ = try WallpaperEngineScene.export(try XCTUnwrap(WallpaperEnginePackage(data: package(files))), into: folder)
        let textures = try XCTUnwrap(try table(in: folder)["textures"] as? [String: Any])
        let film = try XCTUnwrap(textures["materials/film"] as? [String: Any])
        let name = try XCTUnwrap(film["video"] as? String)
        XCTAssertTrue(name.hasPrefix("engine/tex/") && name.hasSuffix(".mp4"))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(name)), movie())
        XCTAssertEqual([film["width"] as? Int, film["height"] as? Int], [638, 746])
        XCTAssertNil(film["pictures"])
    }

    func testPixelsPackedForAGraphicsCardAreUnpacked() throws {
        // One square of four by four: red and blue, each pixel's two bits picking red, blue
        // or one of the two colors between them, a row at a time.
        let colors: [UInt8] = [0x00, 0xF8, 0x1F, 0x00, 0b00_00_00_00, 0b01_01_01_01, 0b10_10_10_10, 0b11_11_11_11]
        let plain = try XCTUnwrap(WallpaperEngineTexture.rgba(from: Data(colors), format: 7, width: 4, height: 4))
        XCTAssertEqual(Array(plain[0..<4]), [255, 0, 0, 255])
        XCTAssertEqual(Array(plain[16..<20]), [0, 0, 255, 255])
        XCTAssertEqual(Array(plain[32..<36]), [170, 0, 85, 255])
        XCTAssertEqual(Array(plain[48..<52]), [85, 0, 170, 255])

        // The same with the opacity before it: four bits a pixel, or two levels and a pick.
        let fourBits = Data([0xF0, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF] + colors)
        let sharp = try XCTUnwrap(WallpaperEngineTexture.rgba(from: fourBits, format: 6, width: 4, height: 4))
        XCTAssertEqual(Array(sharp[0..<8]), [255, 0, 0, 0, 255, 0, 0, 255])
        let levels = Data([255, 0, 0b0000_1000, 0, 0, 0, 0, 0] + colors)
        let smooth = try XCTUnwrap(WallpaperEngineTexture.rgba(from: levels, format: 4, width: 4, height: 4))
        XCTAssertEqual(Array(smooth[0..<8]), [255, 0, 0, 255, 255, 0, 0, 0])

        XCTAssertNil(WallpaperEngineTexture.rgba(from: Data(colors.prefix(5)), format: 7, width: 4, height: 4))
    }

    func testAPictureThatLiesAboutItsSizeIsNotRead() {
        XCTAssertNil(WallpaperEngineTexture.image(from: Data("TEXV0005\0TEXI0001\0".utf8)))
        XCTAssertNil(WallpaperEngineTexture.image(from: Data("PNG".utf8)))
        // Says its pixels take a hundred times the room they have.
        var short = texture(width: 4, height: 4, canvas: 4, color: [1, 2, 3, 255], packed: false)
        short.removeLast(40)
        XCTAssertNil(WallpaperEngineTexture.image(from: short))
        let huge = texture(pixels: Data(count: 16), format: 0, width: 4, height: 4, canvas: 60_000)
        XCTAssertNil(WallpaperEngineTexture.image(from: huge))
        XCTAssertNil(WallpaperEngineTexture.unpackedLZ4(Data([0xFF, 0xFF, 0xFF]), size: 64))
    }

    func testTwoValuesAPixelKeepTheirOwnChannels() throws {
        // A map of directions: the shaders of a scene read its red and its green.
        let file = texture(pixels: Data([10, 200, 30, 40, 0, 0, 0, 0]), format: 8, width: 2, height: 1, canvas: 2)
        let read = try XCTUnwrap(WallpaperEngineTexture.texture(from: file))
        XCTAssertEqual(read.channels, .double)
        XCTAssertTrue(read.isClamped)
        XCTAssertEqual(try pixel(read.pictures[0].image, 0, 0), [10, 200, 0, 255])
        XCTAssertEqual(try pixel(read.pictures[0].image, 1, 0), [30, 40, 0, 255])
        let mask = try XCTUnwrap(WallpaperEngineTexture.texture(from: texture(pixels: Data([7, 9, 0, 0]), format: 9, width: 2, height: 1, canvas: 2)))
        XCTAssertEqual(mask.channels, .single)
        XCTAssertEqual(try pixel(mask.pictures[0].image, 1, 0), [9, 9, 9, 255])
    }

    func testTheFramesOfAnAnimatedTextureAreRead() throws {
        var file = texture(width: 4, height: 2, canvas: 4, color: [255, 255, 255, 255], packed: false)
        file += Data("TEXS0002\0".utf8) + number(2)
        for (x, duration) in [(Float(0), Float(0.25)), (2, 0.5)] {
            file += number(0)
            for value in [duration, x, 0, 2, 0, 0, 2] {
                file += withUnsafeBytes(of: value.bitPattern.littleEndian) { Data($0) }
            }
        }
        let read = try XCTUnwrap(WallpaperEngineTexture.texture(from: file))
        XCTAssertEqual(read.frames.count, 2)
        XCTAssertEqual(read.frames[1], .init(picture: 0, duration: 0.5, x: 2, y: 0, width: 2, widthY: 0, heightX: 0, height: 2))
        // Frames that name a picture the texture has not got are not believed.
        var wrong = file
        wrong.replaceSubrange((file.count - 64)..<(file.count - 60), with: number(5))
        XCTAssertEqual(WallpaperEngineTexture.texture(from: wrong)?.frames.count, 0)
    }

    // MARK: - The scene

    private let sceneJSON = #"""
    {"general": {"clearcolor": "0.1 0.2 0.3", "orthogonalprojection": {"width": 200, "height": 100}},
     "objects": [
       {"id": 1, "name": "Sky", "image": "models/Sky.json", "origin": "100.0 50.0 0.0", "size": "200 100",
        "visible": {"user": {"name": "look", "condition": "2"}, "value": true},
        "effects": [{"file": "effects/glow/effect.json"}]},
       {"id": 2, "name": "Doll", "image": "models/Doll.json",
        "alpha": {"script": "export function update(value) { return engine.userProperties.speed; }", "value": 0.5},
        "animationlayers": [{"animation": 1}]},
       {"id": 3, "name": "Snow", "particle": "particles/snow.json"},
       {"id": 4, "name": "Wind", "sound": ["sounds/Wind.mp3"]},
       {"id": 5, "name": "Title", "text": {"user": "greeting", "value": "Hello"}, "font": "fonts/Hand.ttf"},
       {"id": 6, "name": "Clock", "visible": false, "text": {"value": "12:00"}},
       {"id": 7, "name": "Veil", "image": "models/Veil.json", "animationlayers": [{"animation": 51, "rate": 1}]},
       {"id": 8, "name": "Lamp", "light": "point"},
       {"id": 9, "name": "Hidden lamp", "light": "point", "visible": false},
       {"id": 10, "name": "Teapot", "model": "models/teapot.mdl"}
     ]}
    """#

    /// A puppet: a triangle on two bones, with an animation of two frames in which the
    /// second bone moves ten to the right. `newer` lays the file out as later versions of
    /// Wallpaper Engine do: more before the corners, a corner that also keeps which way it
    /// faces and lies, more after the triangles, the bones and each animation, and a second
    /// animation.
    private func puppet(triangle: [UInt16] = [0, 1, 2], bones: [UInt32] = [0, 1, 1], newer: Bool = false,
                        attachedTo attachmentBone: UInt16? = nil, clipped: Bool = false, sway: String = "",
                        deep: Bool = false) -> Data {
        func float(_ value: Float) -> Data { withUnsafeBytes(of: value.bitPattern.littleEndian) { Data($0) } }
        var file = Data("MDLV00\(newer ? 23 : 13)\0".utf8)
        let head: [Data] = [number(0x0180_0009), number(1), number(1), Data("materials/Sky.json\0".utf8), number(0)]
        head.forEach { file += $0 }
        if newer {
            file += Data(count: 24)
            file += number(0x0180_000F)
        }
        var corners = Data()
        for (index, place) in [(Float(-10), Float(5)), (10, 5), (0, -5)].enumerated() {
            let u: Float = place.0 / 20 + 0.5
            let v: Float = 0.5 - place.1 / 10
            var corner: [Data] = [float(place.0), float(place.1), float(0)]
            if deep {
                // Some files keep one more number after the place: 84 bytes a corner.
                corner.append(float(0))
            }
            if newer {
                corner += [float(0), float(0), float(1), float(1), float(0), float(0), float(1)]
            }
            corner += [number(Int(bones[index])), number(0), number(0), number(0),
                       float(1), float(0), float(0), float(0), float(u), float(v)]
            corner.forEach { corners += $0 }
        }
        file += number(corners.count)
        file += corners
        file += number(triangle.count * 2)
        for corner in triangle {
            file += withUnsafeBytes(of: corner.littleEndian) { Data($0) }
        }
        if newer {
            // Which of the triangles belong together: before that, if clipped, a block of the
            // corners' places once more; after it, the part shown only within itself.
            var parts: [Data] = clipped ? [Data([1]), number(1), number(12), Data(count: 12)] : [Data([0])]
            parts += [Data([1]), number(16), number(0), number(0), number(0), number(triangle.count)]
            if clipped {
                parts += [number(1), number(5661), number(0), Data("masks/clipping_mask_1\0".utf8), number(0), number(1),
                          number(0), number(1), number(0)]
            }
            parts.forEach { file += $0 }
        }
        var skeleton = Data()
        for (name, parent, x) in [("root", -1, Float(0)), ("hair", 0, Float(3))] {
            let bone: [Data] = [Data("\(name)\0".utf8), number(1), number(parent), number(64)]
            bone.forEach { skeleton += $0 }
            for value in [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, 0, 0, 1] as [Float] {
                skeleton += float(value)
            }
            skeleton += Data("\(name == "hair" ? sway : "")\0".utf8)
        }
        if newer {
            // What makes the bones sway, for each of them.
            let sway: [Data] = [Data(count: 11), Data([1]), float(10), float(6.5), float(6.5)]
            sway.forEach { skeleton += $0 }
        }
        var rest: [Data] = [Data("MDLS000\(newer ? 4 : 1)\0".utf8), number(0), Data([2, 0, 0, 0]), skeleton]
        if let attachmentBone {
            // A point to hang things on: a head, five across and seven up from its bone.
            rest += [Data("MDAT0001\0".utf8), number(0), Data([1, 0]), withUnsafeBytes(of: attachmentBone.littleEndian) { Data($0) },
                     Data("头\0".utf8)]
            for value in [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 5, 7, 0, 1] as [Float] {
                rest.append(float(value))
            }
        }
        rest += [Data("MDLA000\(newer ? 6 : 1)\0".utf8), number(0), number(newer ? 2 : 1)]
        rest.forEach { file += $0 }
        let animations: [(id: Int, name: String, mode: String, rate: Float)] = newer
            ? [(51, "Sway", "Loop", 30), (52, "动画 2", "single", 24)]
            : [(51, "Sway", "Loop", 30)]
        for animation in animations {
            let start: [Data] = [number(animation.id), number(0), Data("\(animation.name)\0".utf8), Data("\(animation.mode)\0".utf8),
                                 float(animation.rate), number(1), number(0), number(2)]
            start.forEach { file += $0 }
            for x in [Float(0), Float(3)] {
                file += number(0)
                file += number(2 * 36)
                let places: [Float] = [x, x > 0 ? x + 10 : x]
                for moved in places {
                    for value in [moved, 0, 0, 0, 0, 0, 1, 1, 1] as [Float] {
                        file += float(value)
                    }
                }
            }
            // What follows an animation: a number, and in later versions more.
            file += newer ? Data(count: 35) : number(0)
        }
        return file
    }

    func testAPuppetIsReadWithItsBonesAndAnimations() throws {
        let read = try XCTUnwrap(WallpaperEnginePuppet(data: puppet()))
        XCTAssertEqual(read.triangles, [0, 1, 2])
        // A corner: where it is, where in the picture, its bones and their weights.
        XCTAssertEqual(Array(read.corners[12..<24]), [10, 5, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0])
        XCTAssertEqual(read.bones.map(\.parent), [-1, 0])
        // Scripts ask for a bone by its name.
        XCTAssertEqual(read.bones.map(\.name), ["root", "hair"])
        XCTAssertEqual(read.bones[1].matrix[12], 3)
        XCTAssertEqual(read.animations.count, 1)
        let animation = read.animations[0]
        XCTAssertEqual([animation.id, animation.length, animation.frameCount], [51, 1, 2])
        XCTAssertEqual(animation.mode, "loop")
        XCTAssertEqual(animation.framesPerSecond, 30)
        // The second bone, second frame: ten further than at rest.
        XCTAssertEqual(animation.frames[(1 * 2 + 1) * 9], 13)
        // For the page the long lists are packed as text.
        let table = read.table
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(table["corners"] as? String))?.count, 3 * 12 * 4)
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(table["triangles"] as? String)), Data([0, 0, 1, 0, 2, 0]))

        // A corner that is not there, a bone that is not there, a file cut short.
        XCTAssertNil(WallpaperEnginePuppet(data: puppet(triangle: [0, 1, 7])))
        XCTAssertNil(WallpaperEnginePuppet(data: puppet(bones: [0, 1, 5])))
        XCTAssertNil(WallpaperEnginePuppet(data: puppet().prefix(120)))
        XCTAssertNil(WallpaperEnginePuppet(data: Data("MDLV0013".utf8)))
        // Cut short in its animations, it still has its shape and bones.
        XCTAssertEqual(WallpaperEnginePuppet(data: puppet().dropLast(40))?.animations.count, 0)
    }

    func testABoneSaysHowItSwaysByItself() throws {
        let sway = #"{"re":true,"ge":true,"gd":"0 -1 0","rf":5,"tp":"40 0 0"}"#
        let read = try XCTUnwrap(WallpaperEnginePuppet(data: puppet(newer: true, sway: sway)))
        XCTAssertEqual(read.bones.map(\.physics), [nil, sway])
        let bones = try XCTUnwrap(read.table["bones"] as? [[String: Any]])
        XCTAssertNil(bones[0]["physics"])
        XCTAssertEqual(bones[1]["physics"] as? String, sway)
        XCTAssertEqual(read.animations.map(\.id), [51, 52], "what follows is read as before")
        XCTAssertNil(read.solid, "corners on bones are no shape in three dimensions")
    }

    func testAPuppetWithLongerCornersIsRead() throws {
        let read = try XCTUnwrap(WallpaperEnginePuppet(data: puppet(newer: true, deep: true)))
        let older = try XCTUnwrap(WallpaperEnginePuppet(data: puppet()))
        XCTAssertEqual(read.corners, older.corners)
        XCTAssertEqual(read.triangles, [0, 1, 2])
        XCTAssertEqual(read.animations.map(\.id), [51, 52])
    }

    func testAPuppetOfALaterVersionIsRead() throws {
        // Later versions put more before the corners, keep more in each, and put more after the
        // triangles, the bones and every animation. The puppet read is the same.
        let older = try XCTUnwrap(WallpaperEnginePuppet(data: puppet()))
        let read = try XCTUnwrap(WallpaperEnginePuppet(data: puppet(newer: true)))
        XCTAssertEqual(read.corners, older.corners)
        XCTAssertEqual(read.triangles, [0, 1, 2])
        XCTAssertEqual(read.bones, older.bones)
        // Both of its animations, the second found past what follows the first.
        XCTAssertEqual(read.animations.map(\.id), [51, 52])
        XCTAssertEqual(read.animations.map(\.name), ["Sway", "动画 2"])
        XCTAssertEqual(read.animations.map(\.mode), ["loop", "single"])
        XCTAssertEqual(read.animations.map(\.framesPerSecond), [30, 24])
        XCTAssertEqual(read.animations[1].frames, older.animations[0].frames)

        // What must hold of it still must: a corner of the triangle that is not there, a bone
        // that is not there.
        XCTAssertNil(WallpaperEnginePuppet(data: puppet(triangle: [0, 1, 7], newer: true)))
        XCTAssertNil(WallpaperEnginePuppet(data: puppet(bones: [0, 1, 5], newer: true)))
    }

    func testAPuppetSaysWhichTrianglesAreDrawnTogetherAndWhichOnlyWithinOthers() throws {
        let newer = try XCTUnwrap(WallpaperEnginePuppet(data: puppet(newer: true)))
        XCTAssertEqual(newer.parts, [WallpaperEnginePuppet.Part(start: 0, count: 3)])
        XCTAssertEqual(newer.clips, [])
        XCTAssertEqual(try XCTUnwrap(WallpaperEnginePuppet(data: puppet())).parts, [], "older files do not say")

        let clipped = try XCTUnwrap(WallpaperEnginePuppet(data: puppet(newer: true, clipped: true)))
        XCTAssertEqual(clipped.parts, newer.parts, "the block before the parts is passed over")
        XCTAssertEqual(clipped.clips, [WallpaperEnginePuppet.Clip(part: 0, masks: [0], texture: "masks/clipping_mask_1")])
        XCTAssertEqual(clipped.animations.map(\.id), [51, 52])
        let table = clipped.table
        XCTAssertEqual(table["parts"] as? [[Int]], [[0, 3]])
        XCTAssertEqual((table["clips"] as? [[String: Any]])?.first?["texture"] as? String, "masks/clipping_mask_1")
    }

    func testAPuppetHasPointsOtherObjectsHangOn() throws {
        let read = try XCTUnwrap(WallpaperEnginePuppet(data: puppet(newer: true, attachedTo: 1)))
        XCTAssertEqual(read.attachments.map(\.name), ["头"])
        XCTAssertEqual(read.attachments.first?.bone, 1)
        XCTAssertEqual(read.attachments.first.map { Array($0.matrix[12...13]) }, [5, 7])
        XCTAssertEqual(read.animations.map(\.id), [51, 52], "the animations after them are read as before")
        XCTAssertEqual((read.table["attachments"] as? [[String: Any]])?.first?["name"] as? String, "头")
        // One on a bone the puppet does not have is left out, and the puppet with it.
        let wrong = try XCTUnwrap(WallpaperEnginePuppet(data: puppet(newer: true, attachedTo: 9)))
        XCTAssertEqual(wrong.attachments, [])
        XCTAssertEqual(wrong.bones, read.bones)
        XCTAssertEqual(try XCTUnwrap(WallpaperEnginePuppet(data: puppet())).attachments, [])
    }

    func testAPuppetWithoutBonesIsAPictureCutToItsShape() throws {
        // Some files end after the triangles: corners that say nothing of bones, and no bones.
        func float(_ value: Float) -> Data { withUnsafeBytes(of: value.bitPattern.littleEndian) { Data($0) } }
        var file = Data("MDLV0023\0".utf8)
        let head: [Data] = [number(9), number(1), number(1), Data("materials/Sky.json\0".utf8), number(0), Data(count: 24), number(0xF)]
        head.forEach { file += $0 }
        var corners = Data()
        for place in [(Float(-10), Float(5)), (10, 5), (0, -5)] {
            let corner: [Float] = [place.0, place.1, 0, 0, 0, 1, 1, 0, 0, 1, place.0 / 20 + 0.5, 0.5 - place.1 / 10]
            corner.forEach { corners += float($0) }
        }
        file += number(corners.count)
        file += corners
        file += number(6)
        for corner in [0, 1, 2] as [UInt16] {
            file += withUnsafeBytes(of: corner.littleEndian) { Data($0) }
        }
        file += Data(count: 7)

        let read = try XCTUnwrap(WallpaperEnginePuppet(data: file))
        XCTAssertEqual(read.triangles, [0, 1, 2])
        // Every corner hangs whole on one bone that stays where it is.
        XCTAssertEqual(Array(read.corners[0..<12]), [-10, 5, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0])
        XCTAssertEqual(Array(read.corners[24..<28]), [0, -5, 0.5, 1])
        XCTAssertEqual(read.bones.count, 1)
        XCTAssertEqual(read.bones.first?.parent, -1)
        XCTAssertTrue(read.animations.isEmpty)
        // Read as a shape in three dimensions too: each corner's place, the way it faces, and
        // where in the picture it is; and the material it is drawn with.
        XCTAssertEqual(read.solid.map { Array($0[0..<8]) }, [-10, 5, 0, 0, 0, 1, 0, 0])
        XCTAssertEqual(read.solid?.count, 3 * 8)
        XCTAssertEqual(read.material, "materials/Sky.json")
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(read.table["solid"] as? String))?.count, 3 * 8 * 4)
        XCTAssertEqual(read.table["material"] as? String, "materials/Sky.json")
        // A corner the triangles name that is not there.
        var broken = file
        broken[broken.count - 9] = 9
        XCTAssertNil(WallpaperEnginePuppet(data: broken))
    }

    private func scenePackage() throws -> Data {
        let png = root.appendingPathComponent("inside.png")
        try TestMedia.writePNG(to: png, size: CGSize(width: 8, height: 8))
        return package([
            ("scene.json", Data(sceneJSON.utf8)),
            ("effects/glow/effect.json", Data(#"{"passes": [{"material": "materials/effects/glow.json"}]}"#.utf8)),
            ("shaders/effects/Glow.frag", Data("void main() {\r\n\tgl_FragColor = vec4(1);\r\n}\r\n".utf8)),
            ("particles/snow.json", Data(#"{"maxcount": 10}"#.utf8)),
            ("sounds/Wind.mp3", Data([1, 2, 3, 4])),
            ("fonts/Hand.ttf", Data([7, 7, 7])),
            ("models/Doll.json", Data(#"{"material": "materials/Sky.json", "puppet": "models/doll.mdl"}"#.utf8)),
            ("models/doll.mdl", Data([9, 9, 9])),
            ("models/Veil.json", Data(#"{"material": "materials/Sky.json", "puppet": "models/Veil_Puppet.mdl"}"#.utf8)),
            ("models/Veil_Puppet.mdl", puppet()),
            ("materials/masks/Glow_Mask.tex", texture(pixels: Data([0, 255, 255, 0]), format: 9, width: 2, height: 2, canvas: 2)),
            ("materials/Photo.tex", texture(pixels: try Data(contentsOf: png), format: 0, width: 8, height: 8, canvas: 8, version: 3, pictureFile: true)),
        ] + picture("Sky", texture: texture(width: 200, height: 100, canvas: 256, color: [0, 0, 255, 255])))
    }

    /// What the page is handed: the table in `engine/files.js`.
    private func table(in folder: URL) throws -> [String: Any] {
        let script = try String(contentsOf: folder.appendingPathComponent("engine/files.js"), encoding: .utf8)
        let prefix = "window.wallaeroEngineScene = "
        XCTAssertTrue(script.hasPrefix(prefix))
        let json = script.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines).dropLast()
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    func testTheScenesFilesAreLaidOutForThePlayer() throws {
        let folder = root.appendingPathComponent("Scene")
        let leftOut = try WallpaperEngineScene.export(try XCTUnwrap(WallpaperEnginePackage(data: scenePackage())), into: folder)
        let table = try table(in: folder)

        // The texts, under names without capitals: Wallpaper Engine does not tell them apart.
        let files = try XCTUnwrap(table["files"] as? [String: String])
        XCTAssertEqual(Set(files.keys), ["scene.json", "effects/glow/effect.json", "shaders/effects/glow.frag", "particles/snow.json",
                                         "models/doll.json", "models/veil.json", "models/sky.json", "materials/sky.json"])
        XCTAssertEqual(files["shaders/effects/glow.frag"], "void main() {\r\n\tgl_FragColor = vec4(1);\r\n}\r\n")

        // The textures as pictures a page can load, each with what a shader has to know of it.
        let textures = try XCTUnwrap(table["textures"] as? [String: [String: Any]])
        XCTAssertEqual(Set(textures.keys), ["materials/sky", "materials/masks/glow_mask", "materials/photo"])
        let sky = try XCTUnwrap(textures["materials/sky"])
        XCTAssertEqual(sky["channels"] as? String, "rgba")
        XCTAssertEqual(sky["clamp"] as? Bool, true)
        let skyPicture = try XCTUnwrap((sky["pictures"] as? [[String: Any]])?.first)
        XCTAssertEqual([skyPicture["width"] as? Int, skyPicture["height"] as? Int], [200, 100])
        let skyFile = folder.appendingPathComponent(try XCTUnwrap(skyPicture["file"] as? String))
        let image = try XCTUnwrap(Thumbnailer.image(at: skyFile, maxPixelSize: 400))
        XCTAssertEqual([image.width, image.height], [200, 100])
        XCTAssertEqual(try pixel(image, 199, 99), [0, 0, 255, 255])
        XCTAssertEqual(textures["materials/masks/glow_mask"]?["channels"] as? String, "r8")

        // A PNG a texture held is written out as it was.
        let photo = try XCTUnwrap((textures["materials/photo"]?["pictures"] as? [[String: Any]])?.first?["file"] as? String)
        XCTAssertTrue(photo.hasSuffix(".png"))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(photo)), try Data(contentsOf: root.appendingPathComponent("inside.png")))

        // The sound, and nothing of what the player has no use for.
        let sounds = try XCTUnwrap(table["sounds"] as? [String: String])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(try XCTUnwrap(sounds["sounds/wind.mp3"]))), Data([1, 2, 3, 4]))

        // The font a text is written in.
        let fonts = try XCTUnwrap(table["fonts"] as? [String: String])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(try XCTUnwrap(fonts["fonts/hand.ttf"]))), Data([7, 7, 7]))

        // A picture that bends comes with its bones, when they can be read.
        let puppets = try XCTUnwrap(table["puppets"] as? [String: [String: Any]])
        XCTAssertEqual(Array(puppets.keys), ["models/veil_puppet.mdl"])
        XCTAssertEqual((puppets["models/veil_puppet.mdl"]?["bones"] as? [[String: Any]])?.count, 2)

        // What will not play: the doll's bones, which could not be read, and the teapot, whose
        // shape is not in the scene. The veil, the text, the script and the lamp play, and what
        // is hidden is not missed.
        XCTAssertEqual(leftOut, .init(animations: 1, objects: 1))
    }

    func testTheSettingsASceneUsesAreFound() throws {
        let package = try XCTUnwrap(WallpaperEnginePackage(data: scenePackage()))
        // By the note next to a value, with or without the choice the setting has to be at,
        // and by its name in a script; not what the scene never asks for.
        XCTAssertEqual(WallpaperEngineScene.settingNames(in: package, among: ["greeting", "look", "speed", "schemecolor", "old"]),
                       ["greeting", "look", "speed"])
        XCTAssertEqual(WallpaperEngineScene.settingNames(in: package, among: []), ["greeting", "look"])
    }

    func testASceneIsAddedFromItsArchiveAndFolder() async throws {
        try scenePackage().write(to: wallpaper.appendingPathComponent("scene.pkg"))
        try TestMedia.writePNG(to: wallpaper.appendingPathComponent("preview.png"), size: CGSize(width: 8, height: 8))
        try #"""
        {"file": "scene.json", "type": "scene", "title": "Night Sky", "preview": "preview.png", "general": {"properties": {
          "schemecolor": {"order": 0, "text": "ui_browse_properties_scheme_color", "type": "color", "value": "0 0 0"},
          "greeting": {"order": 1, "text": "Greeting", "type": "textinput", "value": "Hello"},
          "old": {"order": 2, "text": "Left from an older version", "type": "bool", "value": true},
          "look": {"order": 3, "text": "Look", "type": "combo", "value": "2",
                   "options": [{"label": "Day", "value": "1"}, {"label": "Night", "value": "2"}]},
          "speed": {"order": 4, "text": "Speed", "type": "slider", "min": 0, "max": 2, "value": 1}
        }}}
        """#.write(to: wallpaper.appendingPathComponent("project.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(WallpaperEngineProject(folder: wallpaper)?.kind, .scene)
        XCTAssertEqual(WallpaperEngineProject(folder: wallpaper)?.variables.count, 5)
        XCTAssertNil(WebProject(folder: wallpaper), "not a page")

        let library = WallpaperLibrary(rootURL: root.appendingPathComponent("Library"))
        let added = try await library.importItem(at: wallpaper)
        XCTAssertEqual(added.map(\.name), ["Night Sky"])
        XCTAssertEqual(added[0].sourceFormat, "SCENE")
        XCTAssertNil(added[0].thumbnailFileName, "the app draws it: the preview that comes with a scene is small")
        XCTAssertTrue(library.isScene(added[0]))
        let folder = library.projectURL(for: added[0])
        let scene = try SceneProject.read(from: folder)
        // The scene of Wallpaper Engine's is the background, whole; layers go on top of it.
        XCTAssertEqual(scene.background.kind, .engine)
        XCTAssertEqual(scene.background.source, "engine/files.js")
        XCTAssertTrue(scene.background.isFitted)
        XCTAssertFalse(scene.background.isMedia)
        XCTAssertTrue(scene.layers.isEmpty)
        // The settings the scene makes use of are the wallpaper's; the others are not offered.
        XCTAssertEqual(scene.variables.map(\.property), ["greeting", "look", "speed"])
        XCTAssertEqual(scene.variables.map(\.kind), [.text, .choice, .number])
        XCTAssertEqual(scene.variables[1].text, "Night")
        // The page, the runtime and the player that draws the scene.
        for name in ["index.html", "runtime.js", "engine.js", "engine/files.js"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path), name)
        }
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("engine.js"), encoding: .utf8), WallpaperEngineRuntime.script)
        XCTAssertEqual(library.leftOutOnImport[added[0].id], .init(animations: 1, objects: 1))
    }

    func testSettingsMadeForAnotherWallpaperBringItInAsTheyHaveIt() async throws {
        // As sites pack them: the wallpaper under its number, the settings made for it under theirs.
        let both = root.appendingPathComponent("Both")
        let base = both.appendingPathComponent("3122339805")
        let settings = both.appendingPathComponent("3154017672")
        let files = FileManager.default
        try files.createDirectory(at: base, withIntermediateDirectories: true)
        try files.createDirectory(at: settings.appendingPathComponent("files"), withIntermediateDirectories: true)
        try scenePackage().write(to: base.appendingPathComponent("scene.pkg"))
        try #"""
        {"file": "scene.json", "type": "scene", "title": "Pixels", "tags": ["Pixel art"], "contentrating": "Everyone",
         "general": {"properties": {
          "greeting": {"order": 1, "text": "Greeting", "type": "textinput", "value": "Hello"},
          "look": {"order": 3, "text": "Look", "type": "combo", "value": "2",
                   "options": [{"label": "Day", "value": "1"}, {"label": "Night", "value": "2"}]},
          "speed": {"order": 4, "text": "Speed", "type": "slider", "min": 0, "max": 2, "value": 1},
          "picture": {"order": 5, "text": "Picture", "type": "scenetexture", "value": ""},
          "other": {"order": 6, "text": "Other picture", "type": "scenetexture", "value": ""}
        }}}
        """#.write(to: base.appendingPathComponent("project.json"), atomically: true, encoding: .utf8)
        try TestMedia.writePNG(to: settings.appendingPathComponent("files/own.png"), size: CGSize(width: 8, height: 4))
        try "kept to itself".write(to: both.appendingPathComponent("outside.png"), atomically: true, encoding: .utf8)
        try #"""
        {"dependency": "3122339805", "title": "y2k", "tags": ["Abstract"], "contentrating": "Mature",
         "preset": {"greeting": "Hi", "look": "1", "speed": 7, "picture": "files/own.png", "other": "../outside.png", "gone": 1}}
        """#.write(to: settings.appendingPathComponent("project.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(WallpaperEngineProject(folder: settings)?.kind, .preset)
        XCTAssertEqual(WallpaperEngineProject(folder: settings)?.dependency, "3122339805")

        let library = WallpaperLibrary(rootURL: root.appendingPathComponent("Library"))
        let added = try await library.importItem(at: both, languages: ["en"])
        // One wallpaper, not two: the one the settings are for, as they have it.
        XCTAssertEqual(added.map(\.name), ["y2k"])
        XCTAssertEqual(library.items.count, 1)
        XCTAssertEqual(added[0].tagList, ["Abstract", "Scene", "For adults"])
        let folder = library.projectURL(for: added[0])
        let scene = try SceneProject.read(from: folder)
        XCTAssertEqual(scene.variables.map(\.property), ["greeting", "look", "speed"])
        XCTAssertEqual(scene.variables[0].text, "Hi")
        XCTAssertEqual(scene.variables[1].text, "Day")
        XCTAssertEqual(scene.variables[2].number, 2, "no further than the setting goes")
        // The picture the settings choose is a texture of the scene, named after the setting;
        // a name that leads out of their folder is not followed.
        let textures = try XCTUnwrap(try table(in: folder)["textures"] as? [String: Any])
        let chosen = try XCTUnwrap(((textures["user/picture"] as? [String: Any])?["pictures"] as? [[String: Any]])?.first)
        XCTAssertEqual([chosen["width"] as? Int, chosen["height"] as? Int], [8, 4])
        XCTAssertTrue(files.fileExists(atPath: folder.appendingPathComponent(try XCTUnwrap(chosen["file"] as? String)).path))
        XCTAssertNil(textures["user/other"])

        // Chosen alone where Steam keeps them, each item in a folder named by its number, the
        // settings take their wallpaper from the folder next to them.
        let alone = try await library.importItem(at: settings, languages: ["en"])
        XCTAssertEqual(alone.map(\.name), ["y2k"])
        XCTAssertEqual(library.items.count, 2)

        // Settings with no wallpaper of theirs anywhere near are no wallpaper, and say so.
        let apart = root.appendingPathComponent("Apart/3154017672")
        try files.createDirectory(at: apart.deletingLastPathComponent(), withIntermediateDirectories: true)
        try files.copyItem(at: settings, to: apart)
        do {
            _ = try await library.importItem(at: apart)
            XCTFail("settings without their wallpaper were taken")
        } catch {
            XCTAssertEqual(error as? ImportError, .settingsWithoutWallpaper)
        }
        XCTAssertEqual(library.items.count, 2)
    }

    func testOnlyScenesThatHoldOneGetThePlayer() throws {
        let plain = root.appendingPathComponent("Plain")
        try SceneProject.create(at: plain, scene: WallpaperScene())
        XCTAssertFalse(FileManager.default.fileExists(atPath: plain.appendingPathComponent("engine.js").path))
    }

    func testASceneWithNothingToDrawIsRefusedAndLeavesNothingBehind() async throws {
        let json = #"{"objects": [{"name": "Wind", "sound": ["sounds/wind.mp3"]}, {"name": "Lamp", "light": "point"}]}"#
        try package([("scene.json", Data(json.utf8))]).write(to: wallpaper.appendingPathComponent("scene.pkg"))
        try #"{"type": "scene", "title": "Wind"}"#.write(to: wallpaper.appendingPathComponent("project.json"), atomically: true, encoding: .utf8)
        let library = WallpaperLibrary(rootURL: root.appendingPathComponent("Library"))
        do {
            _ = try await library.importItem(at: wallpaper)
            XCTFail("a scene with nothing to show was taken")
        } catch {
            XCTAssertEqual(error as? ImportError, .noPicturesInScene)
        }
        XCTAssertTrue(library.items.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.webURL.path), [])

        try Data("broken".utf8).write(to: wallpaper.appendingPathComponent("scene.pkg"))
        do {
            _ = try await library.importItem(at: wallpaper)
            XCTFail("a broken package was taken")
        } catch {
            XCTAssertEqual(error as? ImportError, .unreadable)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.webURL.path), [])
    }
}

/// The translation of Wallpaper Engine's shaders into the GLSL a browser compiles. The
/// translator is part of the player's script; it is run here without a browser.
final class WallpaperEngineShaderTests: XCTestCase {
    private var context: JSContext!

    override func setUpWithError() throws {
        context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { _, exception in XCTFail("the player's script failed: \(exception?.toString() ?? "?")") }
        context.evaluateScript("var window = {};")
        context.evaluateScript(WallpaperEngineRuntime.source)
    }

    /// A shader translated, all of it.
    private func whole(_ source: String, stage: String = "fragment", switches: [String: Int] = [:],
                       files: [String: String] = [:]) throws -> String {
        let function = try XCTUnwrap(context.objectForKeyedSubscript("window")?.objectForKeyedSubscript("WallaeroEngine")?.objectForKeyedSubscript("translate"))
        let whole = try XCTUnwrap(function.call(withArguments: [source, stage, switches, files])?.toString())
        XCTAssertTrue(whole.hasPrefix("#version 300 es\n"))
        return whole
    }

    /// The body of a translated shader: without the lines every one of them begins with.
    private func translate(_ source: String, stage: String = "fragment", switches: [String: Int] = [:],
                           files: [String: String] = [:]) throws -> String {
        let lines = try whole(source, stage: stage, switches: switches, files: files).components(separatedBy: "\n")
        let first = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("out vec4 wallaero_FragColor") || $0.hasPrefix("uniform float wallaero_Flip") })
        return lines[(first + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func player(_ name: String) throws -> JSValue {
        try XCTUnwrap(context.objectForKeyedSubscript("window")?.objectForKeyedSubscript("WallaeroEngine")?.objectForKeyedSubscript(name))
    }

    func testAValueChangesOverTimeAsItsAnimationSays() throws {
        context.evaluateScript("""
        var keys = [{ frame: 0, value: 0 }, { frame: 30, value: 10 }];
        function at(mode, seconds) {
          return window.WallaeroEngine.curve({ c0: keys, options: { fps: 30, length: 30, mode: mode } })(seconds, [7, 7]).join(' ');
        }
        """)
        func at(_ mode: String, _ seconds: Double) -> String? {
            context.objectForKeyedSubscript("at")?.call(withArguments: [mode, seconds])?.toString()
        }
        // Between two moments the value goes straight from one to the other; a number the
        // animation does not have stays as the scene has it.
        XCTAssertEqual(at("loop", 0.5), "5 7")
        // Past its end it starts anew, goes back the way it came, or stays at its last.
        XCTAssertEqual(at("loop", 1.25), "2.5 7")
        XCTAssertEqual(at("mirror", 1.25), "7.5 7")
        XCTAssertEqual(at("single", 5), "10 7")
        // With handles the value leaves slowly and arrives slowly.
        let eased = context.evaluateScript("""
        (function () {
          var curve = window.WallaeroEngine.curve({ c0: [{ frame: 0, value: 0, front: { enabled: true, x: 10, y: 0 } },
                                                         { frame: 30, value: 10, back: { enabled: true, x: -10, y: 0 } }],
                                                    options: { fps: 30, length: 30, mode: 'loop' } });
          return [0.25, 0.5, 0.75].map(function (seconds) { return Math.round(curve(seconds, [0])[0] * 100) / 100; }).join(' ');
        })()
        """)?.toString()
        XCTAssertEqual(eased, "1.56 5 8.44")
        // What is no animation gives none.
        XCTAssertTrue(try player("curve").call(withArguments: [["options": ["fps": 30]]]).isNull)
    }

    func testAnAnimationSaysHowItIsPlayed() throws {
        // One that a script plays by its name, and one tied to it that plays along.
        context.evaluateScript("""
        var keys = [{ frame: 0, value: 0 }, { frame: 90, value: 9 }];
        var named = window.WallaeroEngine.curve({ c0: keys, options: { fps: 30, length: 90, mode: 'single', name: 'edcv', startpaused: true } });
        var tied = window.WallaeroEngine.curve({ c0: keys, options: { fps: 30, length: 90, mode: 'single', parent: { key: 'origin' } } });
        var plain = window.WallaeroEngine.curve({ c0: keys, options: { fps: 30, length: 90, mode: 'loop' } });
        """)
        func says(_ which: String, _ what: String) -> String? {
            context.evaluateScript("String(\(which).\(what))")?.toString()
        }
        XCTAssertEqual([says("named", "called"), says("named", "startsPaused"), says("named", "mode"), says("named", "frames"), says("named", "rate")],
                       ["edcv", "true", "single", "90", "30"])
        XCTAssertEqual([says("tied", "follows"), says("tied", "startsPaused")], ["origin", "false"])
        XCTAssertEqual([says("plain", "called"), says("plain", "follows"), says("plain", "startsPaused")], ["", "", "false"])
        // It is still asked for its value by how far it has played.
        XCTAssertEqual(context.evaluateScript("named(1.5, [0]).join()")?.toString(), "4.5")
    }

    func testNumbersAreReadHoweverTheyAreSetApart() throws {
        func numbers(_ text: String, _ count: Int) -> String? {
            try? player("numbers").call(withArguments: [text, count, 7])?.toArray().map { "\($0)" }.joined(separator: " ")
        }
        XCTAssertEqual(numbers("990.000 540.000 0.000", 3), "990 540 0")
        // An effect's shader may give its vectors with commas.
        XCTAssertEqual(numbers("0.0, 1.0", 2), "0 1")
        XCTAssertEqual(numbers(" 1,2 ,3", 4), "1 2 3 7")
    }

    func testAShadersNotesOnItsSettingsMayBeLooselyWritten() throws {
        let source = """
        uniform float u_userSpeed; // {"material":"Speed","default":1,"range":[0,01]}
        uniform vec2 u_Bounds; // {"default":"0.0, 1.0","material":"bounds",}
        // [COMBO] {"material":"Shape","combo":"SHAPE","type":"options","default":02,}
        """
        let said = try XCTUnwrap(try player("annotations").call(withArguments: [source]))
        let uniforms = try XCTUnwrap(said.objectForKeyedSubscript("uniforms"))
        XCTAssertEqual(uniforms.objectForKeyedSubscript("u_userSpeed")?.objectForKeyedSubscript("material")?.toString(), "Speed")
        XCTAssertEqual(uniforms.objectForKeyedSubscript("u_Bounds")?.objectForKeyedSubscript("default")?.toString(), "0.0, 1.0")
        XCTAssertEqual(said.objectForKeyedSubscript("combos")?.objectForKeyedSubscript("SHAPE")?.toInt32(), 2)
    }

    func testAShaderDirect3DWouldTakeIsMended() throws {
        // Written as scenes write them: vectors of different sizes in one function and joined
        // by a sign, a vector given to a smaller one and to a single number.
        let source = """
        varying vec2 v_Uv;
        uniform sampler2D g_Texture0;
        uniform vec3 u_Tone;
        void main() {
          vec4 albedo = texSample2D(g_Texture0, v_Uv);
          albedo.rgb = lerp(albedo, u_Tone, 0.5);
          vec3 base = albedo; float level = albedo;
          albedo.rgb = albedo * u_Tone - 1.0;
          albedo.rgb = u_Tone * (level > 0.5);
          if (level == 1.0) albedo.rgb = albedo;
          gl_FragColor = albedo;
        }
        """
        var shader = try whole(source)
        func line(of text: String) throws -> Int {
            try XCTUnwrap(shader.components(separatedBy: "\n").firstIndex { $0.contains(text) }) + 1
        }
        func mend(_ messages: [String], at line: Int) throws -> String? {
            let mended = try XCTUnwrap(try player("mend").call(withArguments: [shader, messages, line]))
            return mended.isNull ? nil : mended.toString()
        }
        let vector4 = "'highp 4-component vector of float'", vector3 = "'highp 3-component vector of float'"

        // A function is given under a name of its own, for every mixture of sizes.
        var at = try line(of: "mix(albedo, u_Tone, 0.5)")
        shader = try XCTUnwrap(try mend(["ERROR: 0:\(at): 'mix' : no matching overloaded function found", "ERROR: 0:\(at): '=' : dimension mismatch"], at: at))
        XCTAssertTrue(shader.contains("albedo.rgb = wallaero_mix(albedo, u_Tone, 0.5);"))
        XCTAssertTrue(shader.contains("vec3 wallaero_mix(vec4 v0, vec3 v1, float v2) { return mix(vec3(v0), v1, vec3(v2)); }"))
        // Once is enough: the same complaint again is not one this mends.
        at = try line(of: "wallaero_mix(albedo")
        XCTAssertNil(try mend(["ERROR: 0:\(at): 'mix' : no matching overloaded function found"], at: at))

        // Of the statements of a line, the one that gives a value to something of that size.
        at = try line(of: "vec3 base = albedo;")
        shader = try XCTUnwrap(try mend(["ERROR: 0:\(at): '=' : dimension mismatch",
                                         "ERROR: 0:\(at): '=' : cannot convert from \(vector4) to 'highp float'"], at: at))
        XCTAssertTrue(shader.contains("vec3 base = albedo; float level = float(albedo);"))
        shader = try XCTUnwrap(try mend(["ERROR: 0:\(at): '=' : cannot convert from \(vector4) to \(vector3)"], at: at))
        XCTAssertTrue(shader.contains("vec3 base = vec3(albedo); float level = float(albedo);"))

        // Of two values joined by a sign, the larger is cut to the smaller.
        at = try line(of: "albedo * u_Tone - 1.0")
        shader = try XCTUnwrap(try mend(["ERROR: 0:\(at): '*' : wrong operand types - no operation '*' exists that takes a left-hand operand of type \(vector4) and a right operand of type 'uniform highp 3-component vector of float' (or there is no acceptable conversion)"], at: at))
        XCTAssertTrue(shader.contains("albedo.rgb = vec3(albedo) * u_Tone - 1.0;"))
        // A yes or no joined to a number counts as a number.
        at = try line(of: "u_Tone * (level > 0.5)")
        shader = try XCTUnwrap(try mend(["ERROR: 0:\(at): '*' : wrong operand types - no operation '*' exists that takes a left-hand operand of type 'uniform highp 3-component vector of float' and a right operand of type 'bool' (or there is no acceptable conversion)"], at: at))
        XCTAssertTrue(shader.contains("albedo.rgb = u_Tone * float((level > 0.5));"))
        // A comparison is not taken for the giving of a value.
        at = try line(of: "if (level == 1.0)")
        shader = try XCTUnwrap(try mend(["ERROR: 0:\(at): 'assign' : cannot convert from \(vector4) to \(vector3)"], at: at))
        XCTAssertTrue(shader.contains("if (level == 1.0) albedo.rgb = vec3(albedo);"))

        // What cannot be mended is left to be reported: a vector cannot grow, and other complaints.
        XCTAssertNil(try mend(["ERROR: 0:\(at): 'assign' : cannot convert from \(vector3) to \(vector4)"], at: at))
        XCTAssertNil(try mend(["ERROR: 0:3: 'foo' : undeclared identifier"], at: 3))
    }

    func testTwoShadersThatDeclareAValueDifferentlyAreMadeToAgree() throws {
        // Direct3D makes each shader by itself and hands on what fits; here the two are one
        // program and must say the same of what they share.
        let vertex = "#version 300 es\nin vec2 a_TexCoord;\nout vec2 v_TexCoord;\nvoid main() {\n  v_TexCoord.xy = a_TexCoord;\n  gl_Position = vec4(0.0);\n}"
        let fragment = "#version 300 es\nin vec4 v_TexCoord;\nout vec4 o;\nvoid main() {\n  o = vec4(v_TexCoord.xy, v_TexCoord.zw);\n}"
        let said = ["Types of varying 'v_TexCoord' differ between VERTEX and FRAGMENT shaders."]
        var pair = try XCTUnwrap(try player("mendPair").call(withArguments: [vertex, fragment, said]))
        var mended = try XCTUnwrap(pair.forProperty("vertex")?.toString())
        XCTAssertTrue(mended.contains("out vec4 v_TexCoord;"))
        XCTAssertTrue(mended.contains("v_TexCoord.xy = a_TexCoord;"), "what was written to is still written to")
        XCTAssertTrue(mended.contains("{ v_TexCoord = vec4(0.0);"), "what the vertex shader never set is nought")
        XCTAssertEqual(pair.forProperty("fragment")?.toString(), fragment)

        // The other way about, the fragment shader uses the parts it knew of.
        let wide = "#version 300 es\nout vec4 v_TexCoord;\nvoid main() {\n  v_TexCoord = vec4(1.0);\n}"
        let narrow = "#version 300 es\nuniform sampler2D t;\nin vec2 v_TexCoord;\nout vec4 o;\nvoid main() {\n  o = texture(t, v_TexCoord) + v_TexCoord.x;\n}"
        pair = try XCTUnwrap(try player("mendPair").call(withArguments: [wide, narrow, said]))
        mended = try XCTUnwrap(pair.forProperty("fragment")?.toString())
        XCTAssertTrue(mended.contains("in vec4 v_TexCoord;"))
        XCTAssertTrue(mended.contains("texture(t, v_TexCoord.xy) + v_TexCoord.x;"))
        XCTAssertEqual(pair.forProperty("vertex")?.toString(), wide)

        // A setting both take, of two sizes: no nought is written to it.
        let first = "#version 300 es\nuniform vec2 u_ref;\nvoid main() {\n  gl_Position = vec4(u_ref, 0.0, 1.0);\n}"
        let second = "#version 300 es\nuniform float u_ref;\nout vec4 o;\nvoid main() {\n  o = vec4(u_ref);\n}"
        pair = try XCTUnwrap(try player("mendPair").call(withArguments: [first, second, ["Types of uniform 'u_ref' differ between VERTEX and FRAGMENT shaders."]]))
        mended = try XCTUnwrap(pair.forProperty("fragment")?.toString())
        XCTAssertTrue(mended.contains("uniform vec2 u_ref;"))
        XCTAssertTrue(mended.contains("o = vec4(u_ref.x);"))
        XCTAssertFalse(mended.contains("u_ref = "))

        // What it cannot do anything about is left alone.
        XCTAssertTrue(try XCTUnwrap(try player("mendPair").call(withArguments: [vertex, fragment, ["something else"]])).isNull)
    }

    func testANumberAskedAsAYesOrNoAndAValueHandedOnThatIsChangedAreMended() throws {
        func mended(_ source: String, _ message: String, at line: Int) throws -> String? {
            let result = try XCTUnwrap(try player("mend").call(withArguments: [source, [message], line]))
            return result.isNull ? nil : result.toString()
        }
        // Direct3D takes anything but nought for a yes.
        let asked = "void main() {\n  float outside = 1.0;\n  vec4 final = outside ? inSmooth : outSmooth;\n  if (outside) final.a = 0.0;\n  float c = a < b ? 1.0 : 0.0;\n}"
        let refused = "ERROR: 0:3: '' : boolean expression expected"
        XCTAssertEqual(try mended(asked, refused, at: 3)?.components(separatedBy: "\n")[2], "  vec4 final = ((outside) != 0.0) ? inSmooth : outSmooth;")
        XCTAssertEqual(try mended(asked, refused, at: 4)?.components(separatedBy: "\n")[3], "  if ((outside) != 0.0) final.a = 0.0;")
        XCTAssertNil(try mended(asked, refused, at: 5), "what is asked there is a yes or no already")

        // A fragment shader may not change what it is handed; it changes a copy of its own.
        let handed = "in vec2 v_TexCoord;\nvec2 twice() { return v_TexCoord * 2.0; }\nvoid main() {\n  v_TexCoord = twice();\n}"
        let own = try XCTUnwrap(try mended(handed, "ERROR: 0:4: 'assign' : l-value required (can't modify an input \"v_TexCoord\")", at: 4))
        // On a line of its own: the line that takes the value in may be written anew (3701796900).
        XCTAssertTrue(own.hasPrefix("in vec2 v_TexCoord;\nvec2 wallaero_own_v_TexCoord;"))
        XCTAssertTrue(own.contains("return wallaero_own_v_TexCoord * 2.0;"))
        XCTAssertTrue(own.contains("void main() { wallaero_own_v_TexCoord = v_TexCoord;"))
        XCTAssertTrue(own.contains("  wallaero_own_v_TexCoord = twice();"))
        XCTAssertNil(try mended(own, "ERROR: 0:4: 'assign' : l-value required (can't modify an input \"v_TexCoord\")", at: 4), "once is enough")
    }

    func testVectorsTooLargeForWhatTakesThemAreCutAsDirect3DCutsThem() throws {
        func mended(_ source: String, _ message: String, at line: Int) throws -> String? {
            let result = try XCTUnwrap(try player("mend").call(withArguments: [source, [message], line]))
            return result.isNull ? nil : result.toString()
        }
        // A function the shader writes itself, given a larger vector than it takes (3680252478's shimmer).
        let called = "vec2 rotateVec2(vec2 v, float r) {\n  return v;\n}\nin vec4 v_TexCoord;\nvoid main() {\n  vec2 at = rotateVec2(v_TexCoord, -u_direction + 1.5) * u_scale;\n}"
        let refused = "ERROR: 0:6: 'rotateVec2' : no matching overloaded function found"
        let cut = try XCTUnwrap(try mended(called, refused, at: 6))
        XCTAssertEqual(cut.components(separatedBy: "\n")[5], "  vec2 at = rotateVec2(vec2(v_TexCoord), float(-u_direction + 1.5)) * u_scale;")
        XCTAssertNil(try mended(cut, refused, at: 6), "once is enough")

        // A sum whose larger side is more than one value (2902406982's clipping mask): each name
        // of that size on the line is cut where it is taken whole.
        let summed = "in vec4 v_TexCoord;\nuniform vec2 u_center;\n#define center (u_center * 2.0 - 1.0)\nvoid main() {\n  vec2 uv = (v_TexCoord * 2.0 - 1.0 - center) / 2.0 + v_TexCoord.zw;\n}"
        let joined = "ERROR: 0:5: '-' : wrong operand types - no operation '-' exists that takes a left-hand operand of type ' temp highp 4-component vector of float' and a right operand of type ' temp highp 2-component vector of float' (or there is no acceptable conversion)"
        XCTAssertEqual(try mended(summed, joined, at: 5)?.components(separatedBy: "\n")[4], "  vec2 uv = (v_TexCoord.xy * 2.0 - 1.0 - center) / 2.0 + v_TexCoord.zw;")
    }

    func testAShaderKeepsItsOwnLog10AndHasTheRadialBlurs() throws {
        // A shader that writes `log10` itself is not given the one every shader has.
        let own = try whole("#define logOf10 2.302585092994\nfloat log10(float x) { return log(x) / logOf10; }\nvoid main() {\n  gl_FragColor = vec4(log10(2.0));\n}")
        XCTAssertTrue(own.contains("#undef log10"))
        XCTAssertFalse(try whole("void main() {\n  gl_FragColor = vec4(log10(2.0));\n}").contains("#undef log10"))
        // Blurs around a point, from Wallpaper Engine's header of blurs.
        let blurred = try translate("#include \"common_blur.h\"\nuniform sampler2D g_Texture0;\nvoid main() {\n  gl_FragColor = blurRadial13a(vec2(0.5), vec2(0.4), 2.0);\n}")
        XCTAssertTrue(blurred.contains("#define blurRadial13a(u, c, a)"))
        XCTAssertTrue(blurred.contains("#define blurRadial7a(u, c, a)"))
        XCTAssertTrue(blurred.contains("#define blurRadial3a(u, c, a)"))
        XCTAssertTrue(blurred.contains("vec2 wallaeroTurn(vec2 v, float r)"))
    }

    func testWhatWallpaperEngineKeepsToItselfForEffectsIsThere() throws {
        // A declaration with parts named after its value is that value whole.
        let declared = try translate("varying vec4 v_Size.xy; // xy = size\nvoid main() {\n  gl_FragColor = v_Size;\n}")
        XCTAssertTrue(declared.contains("in vec4 v_Size;"))
        // The header for putting an effect's result together with the picture, by its switch.
        let composed = "#include \"common_composite.h\"\nvoid main() {\n  gl_FragColor = ApplyComposite(vec4(0.0), vec4(1.0));\n}"
        let blended = try translate(composed, switches: ["COMPOSITE": 1, "BLENDMODE": 31])
        XCTAssertTrue(blended.contains("uniform float g_CompositeAlpha;"))
        XCTAssertTrue(blended.contains("ApplyBlending(BLENDMODE"))
        XCTAssertTrue(blended.contains("return A + B;"), "the mode that adds")
        XCTAssertTrue(try translate(composed).contains("return made;"), "with the switch off the result stands in place of the picture")
        // The blend modes by name, one handed to another.
        let named = try translate("#include \"common_blending.h\"\nvoid main() {\n  vec3 a = BlendOpacity(vec3(0.5), vec3(0.2), BlendLinearDodge, 0.1);\n  gl_FragColor = vec4(BlendSoftLight(a, a), 1.0);\n}")
        XCTAssertTrue(named.contains("#define BlendLinearDodge BlendAdd"))
        XCTAssertTrue(named.contains("#define BlendOpacity(base, blend, F, O)"))
    }

    func testEveryNameDeclaredAtOnceIsMendedByItself() throws {
        // Direct3D takes one number for a vector, also where several names are declared at once.
        let source = """
        varying vec2 v_TexCoord;
        void main() {
          vec2 uv = v_TexCoord.xy;
          vec2 radial = 0.0, tangential = 0.0, center = (uv - 0.5);
          gl_FragColor = vec4(radial + tangential + center, 0.0, 1.0);
        }
        """
        var shader = try whole(source)
        let at = try XCTUnwrap(shader.components(separatedBy: "\n").firstIndex { $0.contains("vec2 radial") }) + 1
        let refused = "ERROR: 0:\(at): '=' : cannot convert from 'const float' to 'highp 2-component vector of float'"
        func mended() throws -> String? {
            let result = try XCTUnwrap(try player("mend").call(withArguments: [shader, [refused], at]))
            return result.isNull ? nil : result.toString()
        }
        shader = try XCTUnwrap(try mended())
        XCTAssertTrue(shader.contains("vec2 radial = vec2(0.0), tangential = 0.0, center = (uv - 0.5);"))
        shader = try XCTUnwrap(try mended())
        XCTAssertTrue(shader.contains("vec2 radial = vec2(0.0), tangential = vec2(0.0), center = (uv - 0.5);"))
    }

    func testTheRemainderSignAndAYesOrNoAreMended() throws {
        // A translated shader counts in fractions, which have no sign for what a division
        // leaves; and Direct3D takes a yes or no for a number.
        let source = """
        void main() {
          uint low = frequency % RESOLUTION; uint next = (low + 1) % RESOLUTION;
          float bar = 1.0;
          bar *= isLeft;
          gl_FragColor = vec4(bar);
        }
        """
        var shader = try whole(source, switches: ["RESOLUTION": 32])
        let at = try XCTUnwrap(shader.components(separatedBy: "\n").firstIndex { $0.contains("frequency % RESOLUTION") }) + 1
        let remainder = "ERROR: 0:\(at): '%' : wrong operand types - no operation '%' exists that takes a left-hand operand of type 'highp float' and a right operand of type 'const float' (or there is no acceptable conversion)"
        func mended(_ messages: [String], at line: Int) throws -> String? {
            let result = try XCTUnwrap(try player("mend").call(withArguments: [shader, messages, line]))
            return result.isNull ? nil : result.toString()
        }
        // One sign at a time, the first that is left.
        shader = try XCTUnwrap(try mended([remainder], at: at))
        XCTAssertTrue(shader.contains("float low = fmod(frequency, RESOLUTION); float next = (low + 1.0) % RESOLUTION;"))
        shader = try XCTUnwrap(try mended([remainder], at: at))
        XCTAssertTrue(shader.contains("float low = fmod(frequency, RESOLUTION); float next = fmod((low + 1.0), RESOLUTION);"))
        XCTAssertNil(try mended([remainder], at: at))

        let yesOrNo = try XCTUnwrap(shader.components(separatedBy: "\n").firstIndex { $0.contains("bar *= isLeft;") }) + 1
        shader = try XCTUnwrap(try mended(["ERROR: 0:\(yesOrNo): 'assign' : cannot convert from 'bool' to 'highp float'"], at: yesOrNo))
        XCTAssertTrue(shader.contains("bar *= float(isLeft);"))
    }

    func testTheBlursWallpaperEngineKeepsToItselfAreThere() throws {
        // A shader includes them before it names its pictures, so they are replacements of
        // text, made out where they are used.
        let source = """
        #include "common_blur.h"
        varying vec4 v_TexCoord;
        uniform sampler2D g_Texture0;
        void main() {
          vec4 soft = blur13a(v_TexCoord.xy, v_TexCoord.zw);
          gl_FragColor = vec4(blur7(v_TexCoord.xy, v_TexCoord.zw) + blur3a(v_TexCoord.xy, v_TexCoord.zw).rgb, soft.a);
        }
        """
        let shader = try translate(source)
        XCTAssertFalse(shader.contains("#error"))
        for name in ["blur13a", "blur13", "blur7a", "blur7", "blur3a", "blur3"] {
            XCTAssertTrue(shader.contains("#define \(name)(u, d) ("), name)
        }
        // Looked at in the middle and to both sides of it, along the direction given.
        XCTAssertTrue(shader.contains("#define blur3a(u, d) (texture(g_Texture0, (u)) * 0.29411764705882354 + (texture(g_Texture0, (u) + (d) * 1.3333333333333333) + texture(g_Texture0, (u) - (d) * 1.3333333333333333)) * 0.35294117647058826)"))
    }

    func testAScriptsOwnSettingsFollowWhatTheSceneGives() throws {
        context.evaluateScript("""
        var given = { speed: { user: 'missing', value: 5 }, tone: '1 0.5 0', plain: 7 };
        var made = window.WallaeroEngine.settings(given)()
          .addSlider({ name: 'speed', value: 1 }).addColor({ name: 'tone', value: { x: 0, y: 0, z: 0 } })
          .addSlider({ name: 'plain', value: 2 }).addCheckbox({ name: 'own', value: true }).finish();
        """)
        func says(_ what: String) -> String? { context.evaluateScript("String(\(what))")?.toString() }
        // What the scene gives stands in for what the script declares; a color comes as a vector.
        XCTAssertEqual([says("made.speed"), says("made.plain"), says("made.own"), says("made.tone.y")], ["5", "7", "true", "0.5"])
        // The scene's value is asked anew every time, so that a setting of the wallpaper
        // behind it may change while the scene plays.
        context.evaluateScript("given.speed.value = 9;")
        XCTAssertEqual(says("made.speed"), "9")
        // What the script sets itself stays.
        context.evaluateScript("made.speed = 3; given.speed.value = 11;")
        XCTAssertEqual(says("made.speed"), "3")
    }

    func testTheTintBlendModeKeepsHowLightThePictureWas() throws {
        // The tint effect's own mode: as light as the picture was, in the color given.
        let source = "#include \"common_blending.h\"\nvoid main() { gl_FragColor = vec4(ApplyBlending(BLENDMODE, vec3(0.5), vec3(1, 0, 0), 1), 1); }"
        let tinted = try translate(source, switches: ["BLENDMODE": 30])
        XCTAssertTrue(tinted.contains("return max(A.r, max(A.g, A.b)) * B;"))
        XCTAssertFalse(tinted.contains("return A * B;"))
        // The modes that take hue, saturation or lightness from one picture and the rest from the other.
        XCTAssertTrue(try translate(source, switches: ["BLENDMODE": 28]).contains("return wallaeroSetLum(B, wallaeroLum(A));"))
    }

    func testAnAnimationMayBeCountedFromTheScenesValueAndComeRoundSmoothly() throws {
        // As a real scene has it: something that bobs up and down. Two moments, the handles
        // left to the player, the numbers counted from the place the scene gives, and the
        // curve going on from its last moment back to its first.
        context.evaluateScript("""
        function handle(x) { return { enabled: true, magic: true, x: x, y: 0 }; }
        function moment(frame, value) { return { frame: frame, value: value, back: handle(-1), front: handle(1), lockangle: true, locklength: true }; }
        var bob = window.WallaeroEngine.curve({
          c0: [moment(0, 0), moment(60, 0)], c1: [moment(0, 16), moment(60, -12)], c2: [moment(0, 0), moment(60, 0)],
          options: { fps: 30, length: 120, mode: 'loop', wraploop: true }, relative: true
        });
        function bobAt(seconds) { return bob(seconds, [1280, 744, 300]).map(function (part) { return Math.round(part * 100) / 100; }).join(' '); }
        """)
        func at(_ seconds: Double) -> String? {
            context.objectForKeyedSubscript("bobAt")?.call(withArguments: [seconds])?.toString()
        }
        // At its moments it is the scene's place moved by what the animation says.
        XCTAssertEqual(at(0), "1280 760 300")
        XCTAssertEqual(at(2), "1280 732 300")
        // Half way down and half way back up it is in the middle: after the last moment the
        // curve returns to the first, with no jump where the loop starts anew.
        XCTAssertEqual(at(1), "1280 746 300")
        XCTAssertEqual(at(3), "1280 746 300")
        XCTAssertEqual(at(3.999), at(0))
        // It leaves a turning point slowly: a quarter of the way in time is less than a
        // quarter of the way down.
        let early = try XCTUnwrap(context.evaluateScript("bob(0.5, [1280, 744, 300])[1]")?.toDouble())
        XCTAssertGreaterThan(early, 760 - 28 * 0.25)
        XCTAssertLessThan(early, 760)
    }

    func testAScriptOfASceneIsMadeReady() throws {
        let source = """
        'use strict';
        import * as WEMath from 'WEMath';
        import { mix as blend } from 'WEMath';
        let parent = 3, top = 4;
        export var seen = typeof window + ' ' + typeof document + ' ' + typeof fetch;
        export function update(value) { return WEMath.mix(value, 10, 0.5) + blend(0, engine.runtime, 1) + parent + top; }
        export function init(value) { return seen; }
        function helper() {}
        export { helper };
        """
        let made = try XCTUnwrap(try player("script").call(withArguments: [source, ["engine"], [["runtime": 2]]]))
        // What it exports is what the scene calls; its helpers come by the names it imports
        // them under, and what it declares is its own whatever the page calls the same.
        XCTAssertEqual(made.objectForKeyedSubscript("update")?.call(withArguments: [4])?.toDouble(), 16)
        // The page itself is kept from it, as in Wallpaper Engine.
        XCTAssertEqual(made.objectForKeyedSubscript("init")?.call(withArguments: [0])?.toString(), "undefined undefined undefined")
        XCTAssertTrue(try XCTUnwrap(made.objectForKeyedSubscript("cursorClick")).isNull)
    }

    func testAScriptSqueezedOntoOneLineIsMadeReady() throws {
        // As 3811154012 brings it: no room between the statements, nor in `import*as … from'…'`.
        let source = "'use strict';import*as WEMath from'WEMath';var k=2;export function update(value){return WEMath.mix(0,value,0.5)*k;}"
        let made = try XCTUnwrap(try player("script").call(withArguments: [source, ["engine"], [["runtime": 2]]]))
        XCTAssertEqual(made.objectForKeyedSubscript("update")?.call(withArguments: [10])?.toDouble(), 10)
    }

    func testAShaderFunctionNamedAsOneOfGLSLsAndAConstantReturnAreMended() throws {
        func mended(_ source: String, _ message: String, at line: Int) throws -> String? {
            let result = try XCTUnwrap(try player("mend").call(withArguments: [source, [message], line]))
            return result.isNull ? nil : result.toString()
        }
        // 3819066109's light pillar: Direct3D has `frac`, so `fract` is the shader's own.
        let own = "const float fract(float x) {\n  return x - floor(x);\n}\nvoid main() {\n  float a = fract(0.5);\n}"
        let constant = try XCTUnwrap(try mended(own, "ERROR: 0:1: 'const' : no qualifiers allowed for function return", at: 1))
        XCTAssertTrue(constant.hasPrefix("float fract(float x) {"))
        let renamed = try XCTUnwrap(try mended(constant, "ERROR: 0:1: 'redefinition of built-in function' : not supported with this profile: es", at: 1))
        XCTAssertTrue(renamed.hasPrefix("float wallaero_fract(float x) {"))
        XCTAssertTrue(renamed.contains("float a = wallaero_fract(0.5);"))
        // Where a pixel shader reads the place it is drawn at, it is the fragment's.
        let place = try XCTUnwrap(try mended("void main() {\n  float r = gl_Position.x;\n}", "ERROR: 0:2: 'gl_Position' : undeclared identifier", at: 2))
        XCTAssertTrue(place.contains("float r = gl_FragCoord.x;"))
    }

    func testWholeNumbersBecomeFractionsExceptWhereThingsAreCounted() throws {
        XCTAssertEqual(try translate("float x = 1; float y = 2.5f * 4 + .5 + 3. + 1e3 + 0x10;"),
                       "float x = 1.0; float y = 2.5 * 4.0 + 0.5 + 3.0 + 1e3 + 16.0;")
        // Between square brackets a whole number stays one, and anything else is made one.
        XCTAssertEqual(try translate("float v[13]; for (int i = 0; i < 4; ++i) { v[i] = v[i + 1] + float(int(x)); }"),
                       "float v[13]; for (float i = 0.0; i < 4.0; ++i) { v[int(i)] = v[int(i + 1.0)] + float(trunc(x)); }")
        // Digits that belong to a name are left alone.
        XCTAssertEqual(try translate("vec2 a = g_Texture0Resolution.xy * vec2(1, 2);"), "vec2 a = g_Texture0Resolution.xy * vec2(1.0, 2.0);")
    }

    func testTheOldNamesBecomeTheNewOnes() throws {
        let source = "varying vec2 v_Uv;\nattribute vec3 a_Position;\nvoid main() { gl_FragColor = texSample2D(g_Texture0, frac(v_Uv)); }"
        XCTAssertEqual(try translate(source), "in vec2 v_Uv;\nin vec3 a_Position;\nvoid main() { wallaero_FragColor = texture(g_Texture0, fract(v_Uv)); }")
        // A vertex shader gives where a fragment shader takes, and is turned over at its end.
        let vertex = try translate(source, stage: "vertex")
        XCTAssertTrue(vertex.hasPrefix("out vec2 v_Uv;\nin vec3 a_Position;\nvoid wallaero_main() {"))
        XCTAssertTrue(vertex.hasSuffix("void main() {\n  wallaero_main();\n  gl_Position.y *= wallaero_Flip;\n}"))
        // A name this GLSL keeps for itself is given another.
        XCTAssertEqual(try translate("vec4 sample = texSample2D(g_Texture0, uv); float input = sample.r;"),
                       "vec4 sample_ = texture(g_Texture0, uv); float input_ = sample_.r;")
    }

    func testConditionsAreSettledByTheSwitchesOfTheEffect() throws {
        let source = "#if MASK == 1\r\nfloat mask = 0.5;\r\n#else\r\nfloat mask = 1;\r\n#endif\r\n#ifdef EXTRA\r\nfloat extra;\r\n#endif\r\n#if KERNEL == 0 || defined(WIDE)\r\nfloat wide;\r\n#endif"
        // A name that stands for nothing counts as zero, as in C.
        XCTAssertEqual(try translate(source), "float mask = 1.0;\nfloat wide;")
        XCTAssertEqual(try translate(source, switches: ["MASK": 1, "EXTRA": 0, "KERNEL": 0]).components(separatedBy: "\n").suffix(3),
                       ["float mask = 0.5;", "float extra;", "float wide;"])
        // A switch is also a name the shader may use as a number.
        XCTAssertTrue(try whole("float mode = BLENDMODE;", switches: ["BLENDMODE": 9]).contains("\n#define BLENDMODE 9.0\n"))
        // The shader's own definitions are kept, as fractions, and conditions know of them.
        XCTAssertEqual(try translate("#define COUNT 3\n#if COUNT > 2\nfloat many = COUNT;\n#endif"), "#define COUNT 3.0\nfloat many = COUNT;")
    }

    func testHeadersAreTakenFromThePlayerOrTheSceneAndOnlyOnce() throws {
        let twice = try translate("#include \"common.h\"\n#include \"common.h\"\nfloat grey = greyscale(vec3(1));")
        XCTAssertEqual(twice.components(separatedBy: "float greyscale(vec3 color)").count, 2)
        XCTAssertTrue(twice.hasSuffix("float grey = greyscale(vec3(1.0));"))
        XCTAssertEqual(try translate("#include \"Own.h\"\nfloat b = a;", files: ["shaders/own.h": "float a = 2;"]), "float a = 2.0;\nfloat b = a;")
        // One nobody has stops the shader from compiling, and says why.
        XCTAssertTrue(try translate("#include \"common_missing.h\"").contains("#error the header common_missing.h is not known"))
        // The blend modes go by the number of the switch.
        let blended = try translate("#include \"common_blending.h\"", switches: ["BLENDMODE": 9])
        XCTAssertTrue(blended.contains("return A + B;"))
        XCTAssertFalse(blended.contains("return A * B;"))
    }

    func testAShaderSaysOfItsSwitchesAndUniformsInComments() throws {
        let function = try XCTUnwrap(context.objectForKeyedSubscript("window")?.objectForKeyedSubscript("WallaeroEngine")?.objectForKeyedSubscript("annotations"))
        let source = """
        // [COMBO] {"material":"ui_editor_properties_blend_mode","combo":"BLENDMODE","type":"imageblending","default":9}\r
        // [COMBO_OFF] {"combo":"SPECULAR","default":0}\r
        uniform sampler2D g_Texture1; // {"label":"mask","mode":"opacitymask","combo":"MASK","default":"util/white"}\r
        uniform float g_Speed; // {"material":"speed","default":5,"range":[0.01,50]}\r
        uniform float g_Time;\r
        """
        let said = try XCTUnwrap(function.call(withArguments: [source])?.toDictionary() as? [String: [String: Any]])
        XCTAssertEqual(said["combos"]?["BLENDMODE"] as? Int, 9)
        XCTAssertEqual(said["combos"]?["SPECULAR"] as? Int, 0)
        XCTAssertEqual((said["uniforms"]?["g_Texture1"] as? [String: Any])?["combo"] as? String, "MASK")
        XCTAssertEqual((said["uniforms"]?["g_Speed"] as? [String: Any])?["material"] as? String, "speed")
        XCTAssertNil(said["uniforms"]?["g_Time"])
    }
}

final class SpectrumAnalyzerTests: XCTestCase {
    private let analyzer = SpectrumAnalyzer(sampleRate: 48_000)
    private let frame = 1.0 / 30

    private func tone(_ frequency: Double, volume: Float = 0.5) -> [Float] {
        (0..<analyzer.windowSize).map { volume * Float(sin(2 * Double.pi * frequency * Double($0) / analyzer.sampleRate)) }
    }

    private var quiet: [Float] { [Float](repeating: 0, count: analyzer.windowSize) }

    /// The band whose centre is nearest to a frequency.
    private func band(for frequency: Double) -> Int {
        (0..<SpectrumAnalyzer.bandCount).min { abs(log(analyzer.frequency(ofBand: $0) / frequency)) < abs(log(analyzer.frequency(ofBand: $1) / frequency)) }!
    }

    func testBandsRunFromLowNotesToHighOnes() {
        let frequencies = (0..<SpectrumAnalyzer.bandCount).map(analyzer.frequency(ofBand:))
        XCTAssertEqual(frequencies, frequencies.sorted())
        XCTAssertLessThan(frequencies[0], 50)
        XCTAssertGreaterThan(frequencies[63], 12_000)
    }

    func testAToneLightsItsOwnBandAndLeavesTheRestDark() {
        let levels = analyzer.levels(left: tone(1000), right: tone(1000), interval: frame)
        XCTAssertEqual(levels.count, 2 * SpectrumAnalyzer.bandCount)
        let lit = band(for: 1000)
        XCTAssertEqual(levels[lit], 1, accuracy: 0.05)
        XCTAssertEqual(levels[lit + 64], 1, accuracy: 0.05, "the right channel follows the left's bands")
        for index in 0..<SpectrumAnalyzer.bandCount where abs(index - lit) > 6 {
            XCTAssertEqual(levels[index], 0, "band \(index) is far from the tone")
        }
    }

    func testLowAndHighTonesLandAtOppositeEnds() {
        let low = analyzer.levels(left: tone(60), right: tone(60), interval: frame)
        XCTAssertLessThan(low.firstIndex(of: low.max()!)!, 8)
        let other = SpectrumAnalyzer(sampleRate: 48_000)
        let high = other.levels(left: tone(10_000), right: tone(10_000), interval: frame)
        XCTAssertGreaterThan(high[..<64].firstIndex(of: high[..<64].max()!)!, 54)
    }

    func testChannelsAreKeptApart() {
        let levels = analyzer.levels(left: tone(1000), right: quiet, interval: frame)
        XCTAssertGreaterThan(levels[..<64].max()!, 0.9)
        XCTAssertEqual(levels[64...].max()!, 0)
    }

    func testAQuietSourceFillsTheBarsLikeALoudOne() {
        let loud = analyzer.levels(left: tone(1000, volume: 0.5), right: quiet, interval: frame)
        let other = SpectrumAnalyzer(sampleRate: 48_000)
        let soft = other.levels(left: tone(1000, volume: 0.02), right: quiet, interval: frame)
        XCTAssertEqual(soft.max()!, loud.max()!, accuracy: 0.01)
    }

    func testHissIsNotBlownUpIntoMusic() {
        let levels = analyzer.levels(left: tone(1000, volume: 0.000_05), right: quiet, interval: frame)
        XCTAssertLessThan(levels.max()!, 0.3)
    }

    func testLevelsFallAwayGraduallyInSilence() {
        _ = analyzer.levels(left: tone(1000), right: tone(1000), interval: frame)
        let lit = band(for: 1000)
        let afterOneFrame = analyzer.silence(interval: frame)[lit]
        XCTAssertGreaterThan(afterOneFrame, 0.8, "a bar does not drop to the floor at once")
        XCTAssertLessThan(afterOneFrame, 1)
        var levels: [Float] = []
        for _ in 0..<30 {
            levels = analyzer.silence(interval: frame)
        }
        XCTAssertEqual(levels.max()!, 0, "a second of silence leaves every bar down")
    }

    func testOtherSampleRatesKeepTheSameBands() {
        let other = SpectrumAnalyzer(sampleRate: 44_100)
        XCTAssertEqual(other.frequency(ofBand: 20), analyzer.frequency(ofBand: 20), accuracy: 0.01)
        let samples = (0..<other.windowSize).map { 0.5 * Float(sin(2 * Double.pi * 1000 * Double($0) / 44_100)) }
        let levels = other.levels(left: samples, right: samples, interval: frame)
        XCTAssertEqual(levels.firstIndex(of: levels.max()!)!, band(for: 1000), accuracy: 1)
    }
}

// MARK: - Helpers

private func XCTUnwrapAsync<T>(_ value: @autoclosure () async throws -> T?) async throws -> T {
    let unwrapped = try await value()
    return try XCTUnwrap(unwrapped)
}

enum TestMedia {
    static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WallAeroEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A short mono WAV of silence: enough for a player to open, play through and finish.
    static func writeSilentWAV(to url: URL, seconds: Double) throws {
        let sampleRate: UInt32 = 8000
        let dataSize = UInt32(Double(sampleRate) * seconds) * 2
        var wav = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) } }
        append(36 + dataSize)
        wav.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))  // PCM, mono
        append(sampleRate); append(sampleRate * 2)                 // byte rate
        append(UInt16(2)); append(UInt16(16))                      // block align, bits per sample
        wav.append(Data("data".utf8))
        append(dataSize)
        wav.append(Data(count: Int(dataSize)))
        try wav.write(to: url)
    }

    static func writeGIF(to url: URL, size: CGSize, delays: [Double]) throws {
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, delays.count, nil)
        )
        let loop = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        CGImageDestinationSetProperties(destination, loop)
        for (index, delay) in delays.enumerated() {
            let frame = try image(size: size, hue: Double(index) / Double(delays.count))
            let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
            CGImageDestinationAddImage(destination, frame, properties)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    /// A small PNG written into the folder; returns where it is.
    static func pngFile(in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent("picture-\(UUID().uuidString).png")
        try writePNG(to: url, size: CGSize(width: 16, height: 9))
        return url
    }

    static func writePNG(to url: URL, size: CGSize) throws {
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, try image(size: size, hue: 0.6), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private static func image(size: CGSize, hue: Double) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: hue, green: 1 - hue, blue: 0.5, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: size.width * hue, y: 0, width: size.width / 10, height: size.height))
        return try XCTUnwrap(context.makeImage())
    }
}

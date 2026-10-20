import Foundation
import WallpaperCore

/// Turns the videos and sounds of web wallpapers into WebM, one wallpaper at a time, away from
/// the main thread (see `WebMediaConverter`). A wallpaper shown while its files are converted
/// loads again when they change, as it does for any change of its files.
@MainActor
final class MediaConversion {
    static let shared = MediaConversion()

    /// What is being done; each conversion waits for the one before it, since each uses every core.
    private var last: Task<Void, Never>?

    /// Converts what the folder needs and returns when that is done.
    func convert(_ folder: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async {
        let before = last
        let task = Task.detached(priority: .userInitiated) {
            await before?.value
            let converted = await WebMediaConverter.convertFolder(folder, progress: progress)
            if !converted.isEmpty {
                Log.playback.info("Converted for Chromium in \(folder.lastPathComponent, privacy: .public): \(converted.joined(separator: ", "), privacy: .public)")
            }
        }
        last = task
        await task.value
    }

    /// Converts what the folder needs, without waiting.
    func convertSoon(_ folder: URL) {
        Task { await convert(folder) }
    }

    /// Goes through every web wallpaper and scene of the library: those added by an earlier
    /// version of the app have their videos as they came, mostly in H.264. What is done already
    /// is only looked at.
    /// Lays out anew the scenes an earlier version of the app laid out, so that what it now
    /// reads of them — a puppet of a newer kind, say — plays; then has the wallpapers shown anew.
    func layOutLibrary(_ library: WallpaperLibrary, then done: @escaping @MainActor ([Wallpaper]) -> Void) {
        let stale = library.items.filter { $0.kind == .web }
            .filter { WallpaperEngineProjectFolder.isLaidOutByEarlierVersion(scene: library.projectURL(for: $0)) }
        guard !stale.isEmpty else { return }
        let folders = stale.map { ($0, library.projectURL(for: $0)) }
        Task {
            var redone: [Wallpaper] = []
            for (item, folder) in folders {
                let laidOut = await Task.detached(priority: .utility) {
                    (try? WallpaperEngineProjectFolder.layOut(scene: folder)) != nil
                }.value
                if laidOut { redone.append(item) }
            }
            done(redone)
        }
    }

    /// Makes over in HEVC the video wallpapers the Mac's media engine cannot decode (see
    /// `HardwareVideo`), one at a time and in the background; `done` is told of each, to be
    /// shown again from its new file.
    func makeVideosDecodableInHardware(_ items: [Wallpaper], in library: WallpaperLibrary,
                                       done: @escaping @MainActor (Wallpaper) -> Void) {
        let videos = items.filter { $0.kind == .video }.map { ($0, library.fileURL(for: $0)) }
        guard !videos.isEmpty else { return }
        let before = last
        let task = Task.detached(priority: .utility) {
            await before?.value
            for (item, url) in videos {
                do {
                    if try await HardwareVideo.makeDecodableInHardware(url) {
                        Log.playback.info("Made “\(item.name, privacy: .public)” over in HEVC for the media engine")
                        await done(item)
                    }
                } catch {
                    Log.playback.error("Cannot make “\(item.name, privacy: .public)” over in HEVC: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        last = task
    }

    func convertLibrary(_ library: WallpaperLibrary) {
        guard WebMediaConverter.encodersAvailable else {
            Log.playback.error("The video encoders are missing; videos of web wallpapers stay as they are")
            return
        }
        let folders = library.items.filter { $0.kind == .web }.map { library.projectURL(for: $0) }
        Task {
            for folder in folders {
                await convert(folder)
            }
        }
    }
}

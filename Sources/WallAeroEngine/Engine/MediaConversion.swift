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
    func convert(_ folder: URL) async {
        let before = last
        let task = Task.detached(priority: .userInitiated) {
            await before?.value
            let converted = await WebMediaConverter.convertFolder(folder)
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

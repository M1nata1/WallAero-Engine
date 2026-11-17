import Foundation
import WallpaperCore

/// How the app starts. The app itself (`WallAeroEngine`) leaves all of this as it is; the test
/// host (`WallAeroTestHost`), which runs the developer's helpers and tests next to the copy in
/// use, sets it before calling `AppDelegate.launch()`.
enum Launch {
    /// Runs next to the copy in use: Chromium gets a storage folder of its own, gone when it quits,
    /// and the music players are left alone (macOS would ask the user's leave for a program they
    /// did not start themselves).
    static var isHelper = false
    /// Whether the music players may be asked what plays.
    static var asksPlayers = true
    /// The library to show instead of the user's own.
    static var libraryFolder: URL?
    /// The library's window neither reads nor leaves anything of how the user keeps theirs.
    static var remembers = true
    /// Run instead of the app, once Chromium and the codecs are ready; true when it did and the
    /// app's own start is not wanted.
    static var alone: (() -> Bool)?
    /// Run once launched, in place of the app's own start.
    static var instead: ((AppParts) -> Void)?
    /// Run after the app's own start.
    static var afterStart: ((AppParts) -> Void)?
}

/// What the app is made of, for the test host's helpers.
struct AppParts {
    let library: WallpaperLibrary
    let preferences: Preferences
    let manager: WallpaperManager
    let importer: ImportCoordinator
    let workshop: WorkshopStore
    let cursorSettings: CursorSettings
    let windows: WindowManager
    /// The app's main menu and its delete key, as in the app.
    let showMenus: () -> Void
}

/// The app's start, for its own `main`.
public enum WallAeroEngineApp {
    @MainActor
    public static func launch() {
        AppDelegate.launch()
    }
}

import Combine
import Foundation
import WallpaperCore

/// How a wallpaper fills the screen; each wallpaper has its own setting, kept in the library.
typealias ScalingMode = Wallpaper.Settings.Scaling

extension Wallpaper.Settings.Scaling: Identifiable {
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .fill: return NSLocalizedString("Fill Screen", comment: "Scaling mode")
        case .fit: return NSLocalizedString("Fit to Screen", comment: "Scaling mode")
        case .stretch: return NSLocalizedString("Stretch", comment: "Scaling mode")
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    static let playbackRates: [Double] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2]
    /// The frame rates a web wallpaper may be held to. Sixty is what the screen shows; thirty,
    /// the usual choice for a wallpaper, halves the work.
    static let frameRates = [15, 20, 30, 60]

    static func title(forRate rate: Double) -> String {
        if rate == 1 {
            return NSLocalizedString("Normal", comment: "Playback speed 1×")
        }
        return String(format: "%g×", rate)
    }

    private enum Key {
        static let scaling = "scaling"
        static let playbackRate = "playbackRate"
        static let playsSound = "playsSound"
        static let volume = "volume"
        // Music was one folder for all wallpapers once; see `sharedMusic`.
        static let musicFolderPath = "musicFolderPath"
        static let musicPlaylist = "musicPlaylist"
        static let shufflesMusic = "shufflesMusic"
        static let pauseWhenCovered = "pauseWhenCovered"
        static let pauseOnBattery = "pauseOnBattery"
        static let pauseInLowPowerMode = "pauseInLowPowerMode"
        static let frameRate = "frameRate"
        static let drawsAtFullDensity = "drawsAtFullDensity"
        static let setsSystemWallpaper = "setsSystemWallpaper"
    }

    private let defaults: UserDefaults

    // Scaling and speed used to be one setting for all wallpapers. Each wallpaper has its own
    // now; these are only read once, to hand the old values over to the wallpapers there were.
    @Published var scaling: ScalingMode {
        didSet { defaults.set(scaling.rawValue, forKey: Key.scaling) }
    }
    @Published var playbackRate: Double {
        didSet { defaults.set(playbackRate, forKey: Key.playbackRate) }
    }
    @Published var playsSound: Bool {
        didSet { defaults.set(playsSound, forKey: Key.playsSound) }
    }
    @Published var volume: Double {
        didSet { defaults.set(volume, forKey: Key.volume) }
    }
    /// Music used to be one folder for all wallpapers, chosen here. Each wallpaper has its own
    /// now; this is only read once, to hand the old choice over to the wallpapers there were.
    var sharedMusic: Wallpaper.Settings.Music? {
        defaults.string(forKey: Key.musicFolderPath).map {
            Wallpaper.Settings.Music(folderPath: $0, playlist: defaults.string(forKey: Key.musicPlaylist),
                                     isShuffled: defaults.bool(forKey: Key.shufflesMusic))
        }
    }
    /// Stop decoding while windows or a full-screen app hide the desktop.
    @Published var pauseWhenCovered: Bool {
        didSet { defaults.set(pauseWhenCovered, forKey: Key.pauseWhenCovered) }
    }
    @Published var pauseOnBattery: Bool {
        didSet { defaults.set(pauseOnBattery, forKey: Key.pauseOnBattery) }
    }
    @Published var pauseInLowPowerMode: Bool {
        didSet { defaults.set(pauseInLowPowerMode, forKey: Key.pauseInLowPowerMode) }
    }
    /// How many frames a second a web wallpaper's scripts may draw; one of `frameRates`. A
    /// page that draws itself frame by frame costs as much as it draws frames.
    @Published var frameRate: Int {
        didSet { defaults.set(frameRate, forKey: Key.frameRate) }
    }
    /// Whether a web wallpaper's scripts draw at a Retina display's full density: four times
    /// the pixels of a plain display, and that much more work for the graphics chip.
    @Published var drawsAtFullDensity: Bool {
        didSet { defaults.set(drawsAtFullDensity, forKey: Key.drawsAtFullDensity) }
    }
    /// Also set a still frame as the regular macOS wallpaper, which shows on the lock screen,
    /// in Mission Control and whenever the app is not running.
    @Published var setsSystemWallpaper: Bool {
        didSet { defaults.set(setsSystemWallpaper, forKey: Key.setsSystemWallpaper) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.scaling: ScalingMode.fill.rawValue,
            Key.playbackRate: 1.0,
            Key.playsSound: false,
            Key.volume: 0.5,
            Key.pauseWhenCovered: true,
            Key.pauseOnBattery: false,
            Key.pauseInLowPowerMode: true,
            Key.frameRate: 30,
            Key.drawsAtFullDensity: true,
            Key.setsSystemWallpaper: false,
        ])
        scaling = ScalingMode(rawValue: defaults.string(forKey: Key.scaling) ?? "") ?? .fill
        playbackRate = defaults.double(forKey: Key.playbackRate)
        playsSound = defaults.bool(forKey: Key.playsSound)
        volume = defaults.double(forKey: Key.volume)
        pauseWhenCovered = defaults.bool(forKey: Key.pauseWhenCovered)
        pauseOnBattery = defaults.bool(forKey: Key.pauseOnBattery)
        pauseInLowPowerMode = defaults.bool(forKey: Key.pauseInLowPowerMode)
        let storedFrameRate = defaults.integer(forKey: Key.frameRate)
        frameRate = Self.frameRates.contains(storedFrameRate) ? storedFrameRate : 30
        drawsAtFullDensity = defaults.bool(forKey: Key.drawsAtFullDensity)
        setsSystemWallpaper = defaults.bool(forKey: Key.setsSystemWallpaper)
    }
}

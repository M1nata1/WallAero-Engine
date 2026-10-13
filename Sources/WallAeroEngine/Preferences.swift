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
    /// the usual choice for a wallpaper, halves the work; twenty-four is the rate of film.
    static let frameRates = [15, 24, 30, 60]

    /// The scales a web wallpaper's scripts may draw at, as parts of the display's own
    /// resolution each way: at 0.5 a canvas has half the width and height, a quarter of the pixels.
    static let renderScales: [Double] = [0.25, 0.5, 0.75, 1]

    /// The scale to use for one that was stored: the nearest offered one, and the display's
    /// own resolution if none was ever chosen.
    static func renderScale(forStored stored: Double?) -> Double {
        guard let stored, stored > 0 else { return 1 }
        return renderScales.min { abs($0 - stored) < abs($1 - stored) } ?? 1
    }

    /// The rate to use for one that was stored: itself if it is offered, the nearest offered
    /// one if it no longer is, and thirty if none was ever chosen.
    static func frameRate(forStored stored: Int) -> Int {
        guard stored > 0 else { return 30 }
        return frameRates.min { abs($0 - stored) < abs($1 - stored) } ?? 30
    }

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
        static let renderScale = "renderScale"
        /// What the render scale was before it had steps: a switch, off for half the scale.
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
    /// The part of the display's resolution a web wallpaper's scripts draw at; one of
    /// `renderScales`. The graphics chip's work goes with the pixels: at 0.5, a quarter.
    @Published var renderScale: Double {
        didSet { defaults.set(renderScale, forKey: Key.renderScale) }
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
            Key.setsSystemWallpaper: false,
        ])
        scaling = ScalingMode(rawValue: defaults.string(forKey: Key.scaling) ?? "") ?? .fill
        playbackRate = defaults.double(forKey: Key.playbackRate)
        playsSound = defaults.bool(forKey: Key.playsSound)
        volume = defaults.double(forKey: Key.volume)
        pauseWhenCovered = defaults.bool(forKey: Key.pauseWhenCovered)
        pauseOnBattery = defaults.bool(forKey: Key.pauseOnBattery)
        pauseInLowPowerMode = defaults.bool(forKey: Key.pauseInLowPowerMode)
        frameRate = Self.frameRate(forStored: defaults.integer(forKey: Key.frameRate))
        // Whoever had switched drawing at Retina resolution off had half the scale.
        let hadPlainDensity = (defaults.object(forKey: Key.drawsAtFullDensity) as? Bool) == false
        renderScale = Self.renderScale(forStored: (defaults.object(forKey: Key.renderScale) as? Double) ?? (hadPlainDensity ? 0.5 : nil))
        setsSystemWallpaper = defaults.bool(forKey: Key.setsSystemWallpaper)
    }
}

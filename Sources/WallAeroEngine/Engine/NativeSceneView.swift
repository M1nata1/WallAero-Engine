import AppKit
import MetalScene
import WallpaperCore

/// Shows a scene of Wallpaper Engine's drawn by the app itself (`MetalScenePlayer`): no web
/// engine, no second process. Only for a scene that is nothing but that — see
/// `SceneProject.isNativelyPlayable`; anything more is shown by `WebWallpaperView`.
@MainActor
final class NativeSceneView: NSView {
    /// Called, on the main thread, when the wallpaper's files change on disk.
    var onContentChange: (() -> Void)?
    /// Called once the scene has something to show: its first frame, or a few seconds after
    /// `show` at the latest, so that whoever waits never waits for good.
    var onReady: (() -> Void)?
    /// Set before `show` to let the scene have the spectrum of the sound the Mac is playing.
    var hearsSound = true

    /// Frames a second; 0 leaves it to the screen.
    var frameRate = 0 {
        didSet { player?.frameRate = frameRate }
    }
    /// The part of the display's density the scene is drawn at; 1 is all of it.
    var renderScale = 1.0 {
        didSet { if renderScale != oldValue { applySize() } }
    }

    private var player: MetalScenePlayer?
    private let sceneView = NSView()
    /// A picture of the scene, the library's own, seen until the scene has drawn itself.
    private let backdropView = NSView()
    private var folder: URL?
    private var watcher: FolderWatcher?
    /// What the scene was started with; a change to it starts the scene anew.
    private var started: (changes: NSDictionary, fit: String, position: Double)?
    private var generation = 0
    private var isReady = false

    private var isPlaying = false
    private var rate: Float = 1
    private var isMuted = true
    private var volume: Float = 1
    private var isHearingSound = false
    private var isToldMedia = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        autoresizingMask = [.width, .height]
        sceneView.wantsLayer = true
        sceneView.frame = bounds
        sceneView.autoresizingMask = [.width, .height]
        addSubview(sceneView)
        backdropView.wantsLayer = true
        backdropView.layer?.contentsGravity = .resizeAspectFill
        backdropView.layer?.masksToBounds = true
        backdropView.autoresizingMask = [.width, .height]
        backdropView.frame = bounds
        backdropView.isHidden = true
        addSubview(backdropView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Content

    /// Plays the scene in the folder. False if this Mac cannot: then nothing is shown.
    @discardableResult
    func show(folder: URL, backdrop: NSImage? = nil) -> Bool {
        unload()
        self.folder = folder
        backdropView.layer?.contents = backdrop
        backdropView.isHidden = backdrop == nil
        // Scenes made by an older version of the app get the current player.
        _ = try? SceneProject.refreshGeneratedFiles(in: folder)
        guard start() else { return false }
        watcher = FolderWatcher(folder: folder) { [weak self] paths in
            self?.filesDidChange(paths)
        }
        generation += 1
        let generation = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.generation == generation else { return }
            self.becomeReady()
        }
        return true
    }

    private func start(sceneData: Data? = nil) -> Bool {
        guard let folder,
              let player = MetalScenePlayer(folder: folder, engineScript: WallpaperEngineRuntime.script) else { return false }
        self.player?.stop()
        self.player = player
        sceneView.layer = player.layer
        let settings = sceneData.map(SceneSettings.init(sceneData:))
            ?? SceneSettings(sceneFile: folder.appendingPathComponent(SceneProject.sceneFileName))
        if let scene = try? SceneProject.read(from: folder) {
            player.layer.backgroundColor = Self.color(scene.background.color)
        }
        player.frameRate = frameRate
        player.videoFiles = WallpaperEngineProjectFolder.nativeVideos(scene: folder)
        player.setPlaying(isPlaying, rate: Double(rate))
        player.setAudio(muted: isMuted, volume: volume)
        player.onListensToSound = { [weak self] _ in self?.updateListening() }
        player.onListensToMedia = { [weak self] _ in self?.updateListening() }
        player.onFirstFrame = { [weak self] in self?.firstFrame() }
        applySize()
        player.start(settings: settings.settings, changes: settings.changes, fit: settings.fit, position: settings.position)
        started = (settings.changes as NSDictionary, settings.fit, settings.position)
        for note in player.notes {
            Log.playback.info("Scene \(folder.lastPathComponent, privacy: .public): \(note, privacy: .public)")
        }
        updateListening()
        return true
    }

    func unload() {
        generation += 1
        watcher = nil
        player?.stop()
        player = nil
        sceneView.layer = CALayer()
        folder = nil
        started = nil
        isReady = false
        backdropView.isHidden = true
        backdropView.layer?.contents = nil
        updateListening()
    }

    private func firstFrame() {
        becomeReady()
        // The frame takes a moment more to reach the screen; the picture behind waits for it.
        guard !backdropView.isHidden else { return }
        let generation = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.generation == generation else { return }
            self.backdropView.isHidden = true
            self.backdropView.layer?.contents = nil
        }
    }

    private func becomeReady() {
        guard !isReady else { return }
        isReady = true
        onReady?()
    }

    /// A picture of the scene as it looks now, as large as the view in pixels.
    func snapshot() -> CGImage? {
        player?.snapshot()
    }

    /// Shows the scene as it is being changed in the wallpaper's settings, without waiting for
    /// it to be saved. A change to its settings is taken in place; to the scene itself — what
    /// the editor changed, how it fills the screen — it is started anew.
    func showUnsaved(_ sceneData: Data) {
        let settings = SceneSettings(sceneData: sceneData)
        if let started, started.changes.isEqual(to: settings.changes), started.fit == settings.fit, started.position == settings.position {
            player?.setSettings(settings.settings)
        } else {
            _ = start(sceneData: sceneData)
        }
    }

    // MARK: - Layout

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applySize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        applySize()
    }

    private func applySize() {
        guard let player else { return }
        let scale = (window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2) * max(0.05, min(1, renderScale))
        player.screenRate = window?.screen?.maximumFramesPerSecond ?? NSScreen.main?.maximumFramesPerSecond ?? 60
        player.setViewSize(bounds.size, scale: scale)
    }

    // MARK: - Playback settings

    func setPlaying(_ playing: Bool, rate: Float) {
        isPlaying = playing
        self.rate = rate
        player?.setPlaying(playing, rate: Double(rate))
        updateListening()
    }

    func setAudio(muted: Bool, volume: Float) {
        isMuted = muted
        self.volume = volume
        player?.setAudio(muted: muted, volume: volume)
    }

    /// Tells the scene what the mouse did; see `PointerForwarder`. The point is in the view,
    /// from its top left corner. A paused wallpaper is told nothing.
    func pointer(_ kind: PointerForwarder.Kind, at point: CGPoint) {
        guard isPlaying, let player else { return }
        player.pointer(kind.rawValue, x: point.x, y: point.y)
    }

    // MARK: - Sound and music

    /// The scene hears the Mac's sound, and what music plays, only while it asks and plays.
    private func updateListening() {
        let hears = hearsSound && isPlaying && player?.listensToSound == true
        if hears != isHearingSound {
            isHearingSound = hears
            if hears {
                SoundSpectrum.shared.addListener(self) { [weak self] script in self?.player?.perform(script) }
            } else {
                SoundSpectrum.shared.removeListener(self)
            }
        }
        let told = isPlaying && player?.listensToMedia == true
        if told != isToldMedia {
            isToldMedia = told
            if told {
                NowPlaying.shared.addListener(self) { [weak self] script in self?.player?.perform(script) }
            } else {
                NowPlaying.shared.removeListener(self)
            }
        }
    }

    // MARK: - Live reload

    private func filesDidChange(_ paths: [String]) {
        guard let folder else { return }
        // Saving a file safely writes a hidden temporary one first and renames it; those are not
        // changes to the wallpaper, and neither is Finder's own bookkeeping.
        let names = Set(paths.map { ($0 as NSString).lastPathComponent }).filter { !$0.hasPrefix(".") && !$0.contains(".sb-") }
        guard !names.isEmpty else { return }
        if names == [SceneProject.sceneFileName], let data = try? Data(contentsOf: folder.appendingPathComponent(SceneProject.sceneFileName)) {
            showUnsaved(data)
        } else {
            _ = start()
        }
        onContentChange?()
    }

    private static func color(_ hex: String) -> CGColor {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count >= 6, let value = UInt32(digits.prefix(6), radix: 16) else { return CGColor(gray: 0, alpha: 1) }
        return CGColor(srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

import AppKit
import Combine
import WallpaperCore

enum DisplayTarget: Hashable {
    case all
    case display(String)
}

/// Which wallpaper shows where. Persisted in user defaults.
struct WallpaperAssignments: Codable, Equatable {
    /// Shown on every display that has no choice of its own.
    var allDisplays: UUID?
    /// Per-display choices, keyed by `NSScreen.stableID`. A nil value turns the animated
    /// wallpaper off on that display; a missing key means "same as all displays".
    var displays: [String: UUID?] = [:]

    func wallpaperID(forDisplay id: String) -> UUID? {
        if let choice = displays[id] {
            return choice
        }
        return allDisplays
    }

    var isEmpty: Bool { allDisplays == nil && displays.values.allSatisfy { $0 == nil } }
}

enum PauseReason {
    case user
    case displaysAsleep
    case locked
    case battery
    case lowPowerMode

    var title: String {
        switch self {
        case .user: return NSLocalizedString("Paused", comment: "Playback status")
        case .displaysAsleep: return NSLocalizedString("Paused while displays sleep", comment: "Playback status")
        case .locked: return NSLocalizedString("Paused while the screen is locked", comment: "Playback status")
        case .battery: return NSLocalizedString("Paused on battery power", comment: "Playback status")
        case .lowPowerMode: return NSLocalizedString("Paused in Low Power Mode", comment: "Playback status")
        }
    }
}

/// Owns one desktop window per display and keeps them in sync with the user's choices,
/// the preferences and the state of the Mac (battery, sleep, lock, covered desktop).
@MainActor
final class WallpaperManager: NSObject, ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var assignments: WallpaperAssignments
    @Published var isPausedByUser = false {
        didSet { updatePlayback() }
    }
    @Published private(set) var pauseReason: PauseReason?
    /// What was found in the music folders the wallpapers name, by path. A folder is read once,
    /// when it is first asked for.
    @Published private(set) var musicFolders: [String: MusicFolder] = [:]

    /// The music of the wallpaper that is heard. When it has any, the music plays in place of
    /// the wallpaper's own sound.
    let music = PlaylistPlayer()
    /// Passes the mouse on to web wallpapers, which lie under the desktop and get none.
    private let pointer = PointerForwarder()

    private static let assignmentsKey = "assignments"

    private let library: WallpaperLibrary
    private let preferences: Preferences
    private var screens: [String: ScreenWallpaper] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var displaysAsleep = false
    private var screenLocked = false
    private var sessionActive = true
    /// The music folders being read in the background, so the same scan is not started twice.
    private var scanningMusicPaths: Set<String> = []
    /// What the log last said of the music, so it says it once.
    private var loggedMusicSource = ""
    /// Web wallpapers whose pictures are due to be rendered again, once the edits settle.
    private var pendingWebRefresh: [UUID: Task<Void, Never>] = [:]
    /// Stills of web wallpapers being rendered, so two displays do not render the same one twice.
    private var webStillTasks: [UUID: Task<URL, Error>] = [:]
    /// Still images already handed to macOS, per display, to avoid redundant updates.
    private var syncedSystemWallpapers: [String: UUID] = [:]
    /// The pictures the displays showed as the screen was locked, by display; macOS shows them
    /// on the lock screen until it is unlocked.
    private var lockFrames: [String: URL] = [:]

    init(library: WallpaperLibrary, preferences: Preferences) {
        self.library = library
        self.preferences = preferences
        if
            let data = UserDefaults.standard.data(forKey: Self.assignmentsKey),
            let stored = try? JSONDecoder().decode(WallpaperAssignments.self, from: data)
        {
            assignments = stored
        } else {
            assignments = WallpaperAssignments()
        }
        super.init()
        // Wallpapers that show what music plays are told of the app's own too.
        NowPlaying.shared.watch(music)
    }

    /// Scaling and speed used to be set once for all wallpapers. The first time this version
    /// runs, the wallpapers of the library take those values as their own.
    private func handOverSharedSettings() {
        let key = "wallpapersHaveOwnSettings"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let shared = Wallpaper.Settings(scaling: preferences.scaling, speed: preferences.playbackRate)
        guard shared != Wallpaper.Settings() else { return }
        library.adoptSettings { _ in shared }
    }

    /// Music used to be one folder for all wallpapers too. The first time this version runs,
    /// the wallpapers of the library take that folder as their own, so each goes on sounding
    /// as it did; from then on it is changed wallpaper by wallpaper.
    private func handOverSharedMusic() {
        let key = "wallpapersHaveOwnMusic"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        if let shared = preferences.sharedMusic {
            library.adoptMusic(shared)
        }
    }

    func start() {
        handOverSharedSettings()
        handOverSharedMusic()
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        center.addObserver(self, selector: #selector(powerStateDidChange), name: PowerSource.didChangeNotification, object: nil)
        // Low Power Mode changes are posted on a background thread.
        center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updatePlayback() }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(displaysDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(displaysDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionDidResignActive), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionDidBecomeActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(activeSpaceDidChange), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenDidLock), name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenDidUnlock), name: .init("com.apple.screenIsUnlocked"), object: nil)

        PowerSource.startMonitoring()

        preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.preferencesDidChange() }
            .store(in: &cancellables)
        library.$items
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.libraryDidChange() }
            .store(in: &cancellables)

        rebuildScreens()
        // Scenes edited by hand while the app was not looking get their thumbnails redone.
        for item in library.items where item.kind == .web {
            refreshPicturesIfOutdated(of: item)
        }
    }

    // MARK: - Choosing wallpapers

    var hasWallpaper: Bool { !assignments.isEmpty }

    func wallpaperID(for target: DisplayTarget) -> UUID? {
        switch target {
        case .all: return assignments.allDisplays
        case .display(let id): return assignments.wallpaperID(forDisplay: id)
        }
    }

    /// Choosing for all displays replaces every per-display choice, like System Settings does.
    /// Passing nil turns the animated wallpaper off for the target.
    func setWallpaper(_ id: UUID?, for target: DisplayTarget) {
        switch target {
        case .all:
            assignments = WallpaperAssignments(allDisplays: id)
        case .display(let displayID):
            assignments.displays.updateValue(id, forKey: displayID)
        }
        saveAssignments()
        applyAssignments()
    }

    /// Whether the display has its own choice instead of following all displays.
    func hasOwnWallpaper(_ displayID: String) -> Bool {
        assignments.displays.keys.contains(displayID)
    }

    func followAllDisplays(_ displayID: String) {
        assignments.displays.removeValue(forKey: displayID)
        saveAssignments()
        applyAssignments()
    }

    /// Switches every display to the library entry after the current one.
    func showNextWallpaper() {
        let items = library.items
        guard !items.isEmpty else { return }
        let currentIndex = assignments.allDisplays.flatMap { id in items.firstIndex { $0.id == id } } ?? -1
        setWallpaper(items[(currentIndex + 1) % items.count].id, for: .all)
    }

    var statusText: String {
        guard hasWallpaper else {
            return NSLocalizedString("No animated wallpaper", comment: "Playback status")
        }
        return pauseReason?.title ?? NSLocalizedString("Playing", comment: "Playback status")
    }

    // MARK: - Screens

    private func rebuildScreens() {
        var remaining = screens
        var updated: [String: ScreenWallpaper] = [:]
        var infos: [DisplayInfo] = []
        for screen in NSScreen.screens {
            var id = screen.stableID
            if updated[id] != nil {
                // Two identical monitors without serial numbers.
                id += "-\(screen.displayNumber ?? 0)"
            }
            if let existing = remaining.removeValue(forKey: id) {
                existing.move(to: screen)
                updated[id] = existing
            } else {
                updated[id] = ScreenWallpaper(screen: screen, displayID: id, manager: self)
            }
            infos.append(DisplayInfo(id: id, name: screen.localizedName))
        }
        for screen in remaining.values {
            screen.close()
        }
        screens = updated
        displays = infos
        applyAssignments()
    }

    private func applyAssignments() {
        let leaders = leadersOfSharedWallpapers()
        // Leaders first, so that the screens that follow find what they show.
        for screen in screens.values.sorted(by: { leaders[$0.displayID] == nil && leaders[$1.displayID] != nil }) {
            let item = assignments.wallpaperID(forDisplay: screen.displayID).flatMap(library.item(withID:))
            // Before the wallpaper is shown, so that a page is loaded once, the way it is to draw.
            screen.view.setDrawing(frameRate: preferences.frameRate, renderScale: preferences.renderScale)
            screen.show(item, from: library, following: leaders[screen.displayID].flatMap { screens[$0] })
        }
        reloadMusic()
        syncSystemWallpapers()
    }

    /// The displays that show a wallpaper another one shows too, each with the display that
    /// plays it for both: the one with the most pixels, so that none is drawn smaller than it
    /// is shown. Only videos and the scenes the app draws itself are shared; a picture costs
    /// nothing to show twice, and a page draws itself where it is.
    private func leadersOfSharedWallpapers() -> [String: String] {
        var groups: [UUID: [ScreenWallpaper]] = [:]
        for screen in screens.values {
            guard let item = assignments.wallpaperID(forDisplay: screen.displayID).flatMap(library.item(withID:)),
                  isShared(item) else { continue }
            groups[item.id, default: []].append(screen)
        }
        var leaders: [String: String] = [:]
        for group in groups.values where group.count > 1 {
            guard let leader = group.max(by: { $0.pixelCount < $1.pixelCount || ($0.pixelCount == $1.pixelCount && $0.displayID > $1.displayID) })
            else { continue }
            for screen in group where screen !== leader { leaders[screen.displayID] = leader.displayID }
        }
        return leaders
    }

    private func isShared(_ item: Wallpaper) -> Bool {
        switch item.kind {
        case .video: return true
        case .image: return false
        case .web: return ScreenWallpaper.drawsScenesNatively && SceneProject.isNativelyPlayable(library.projectURL(for: item))
        }
    }

    /// The wallpaper that is heard, and the display it is on: the first one, in menu bar order,
    /// with music of its own or with sound in its video.
    private var heard: (displayID: String, wallpaper: Wallpaper)? {
        Wallpaper.heard(among: displays.map { screens[$0.id]?.item }).map { (displays[$0.index].id, $0.wallpaper) }
    }

    private func applyPlaybackSettings() {
        // Only one display plays sound, the one whose wallpaper is heard. With music of its own
        // none does: the music takes the place of the video's sound. It does so from the moment
        // its folder starts being read, or the video would be heard for that moment.
        let heard = heard
        let musicTakesOver = music.hasTracks || (heard?.wallpaper.shownSettings.music).map { scanningMusicPaths.contains($0.folderPath) } == true
        let audibleDisplay = musicTakesOver ? nil : heard.flatMap { $0.wallpaper.hasAudio ? $0.displayID : nil }
        // With the volume all the way down nothing is heard, so nothing is played: a video or
        // a song at volume zero would still keep the audio hardware running and the Mac awake.
        for screen in screens.values {
            if let item = screen.item {
                screen.view.setFraming(item.shownSettings.scaling, position: item.shownSettings.position,
                                       mediaSize: CGSize(width: item.pixelWidth, height: item.pixelHeight))
            }
            // A display that shows another's video hears it there.
            let audible = isAudible && (screen.displayID == audibleDisplay
                || screens.values.contains { $0.leader === screen && $0.displayID == audibleDisplay })
            screen.view.setAudio(muted: !audible, volume: Float(preferences.volume))
            screen.view.setDrawing(frameRate: preferences.frameRate, renderScale: preferences.renderScale)
        }
        music.volume = Float(preferences.volume)
    }

    /// Plays the mouse at a place on the screens — a move, a press and a release — the way
    /// the real mouse is passed on, and says whether the place is the desktop. For
    /// `--picture-desktop`, which has no mouse to move.
    func playPointer(at place: NSPoint) -> String {
        let isDesktop = pointer.isDesktop(at: place)
        pointer.handle(.move, at: place)
        pointer.handle(.down, at: place)
        pointer.handle(.up, at: place)
        return "\(isDesktop ? "the desktop" : "a window is in the way"); the mouse is \(pointer.isActive ? "being passed on" : "not passed on")"
    }

    /// What is on each display, for `--picture-desktop`.
    var desktops: [ScreenWallpaper] { displays.compactMap { screens[$0.id] } }

    /// Starts or stops every player according to the current state of the Mac.
    func updatePlayback() {
        let reason = currentPauseReason()
        if reason != pauseReason {
            pauseReason = reason
        }
        for screen in screens.values {
            screen.watchesCover = preferences.pauseWhenCovered
        }
        // A wallpaper shared by several displays plays while any of them shows it.
        func visible(_ screen: ScreenWallpaper) -> Bool { !preferences.pauseWhenCovered || screen.isVisibleOnScreen }
        for screen in screens.values {
            let root = screen.leader ?? screen
            let seen = screens.values.contains { ($0.leader ?? $0) === root && visible($0) }
            screen.setPlaying(pauseReason == nil && seen, rate: Float(screen.item?.shownSettings.speed ?? 1))
        }
        // Unlike the picture, the music goes on while windows cover the desktop: songs that
        // stopped whenever a window was maximized would be of little use.
        music.setPlaying(playsMusic && isAudible && hasWallpaper && pauseReason == nil)
        // The mouse is watched only while a page is on the desktop to be told of it.
        pointer.targets = { [weak self] in self?.screens.values.compactMap(\.pointerTarget) ?? [] }
        pointer.isActive = screens.values.contains { $0.pointerTarget != nil }
    }

    private func currentPauseReason() -> PauseReason? {
        if isPausedByUser { return .user }
        if displaysAsleep { return .displaysAsleep }
        if screenLocked || !sessionActive { return .locked }
        if preferences.pauseOnBattery && PowerSource.isOnBattery { return .battery }
        if preferences.pauseInLowPowerMode && ProcessInfo.processInfo.isLowPowerModeEnabled { return .lowPowerMode }
        return nil
    }

    // MARK: - Reacting to changes

    private func preferencesDidChange() {
        applyPlaybackSettings()
        updatePlayback()
        syncSystemWallpapers()
    }

    /// A wallpaper that is on a display now: the one for all displays, or else any display's own.
    var shownWallpaperID: UUID? {
        assignments.allDisplays ?? displays.lazy.compactMap { self.assignments.wallpaperID(forDisplay: $0.id) }.first
    }

    /// Shows a scene on the desktop as it is being changed in the wallpaper's settings, without
    /// waiting for it to be saved.
    func showUnsaved(_ scene: WallpaperScene, of id: UUID) {
        guard let data = try? SceneProject.encoded(scene, readable: false) else { return }
        let script = "window.wallaero && window.wallaero.setScene(\(String(decoding: data, as: UTF8.self)))"
        for screen in screens.values where screen.item?.id == id {
            screen.view.webView?.evaluate(script)
            screen.view.nativeView?.showUnsaved(data)
        }
    }

    // MARK: - Web wallpapers

    /// The files of a web wallpaper changed. Once the edits settle, its thumbnail is rendered
    /// again, and its still too if it serves as the macOS wallpaper.
    /// A video wallpaper's file was made anew: the displays that show it play it again from it.
    func videoFileDidChange(_ item: Wallpaper) {
        for screen in screens.values where screen.item?.id == item.id {
            screen.view.showVideo(at: library.fileURL(for: item))
        }
    }

    func webWallpaperDidChange(_ item: Wallpaper) {
        pendingWebRefresh[item.id]?.cancel()
        pendingWebRefresh[item.id] = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            pendingWebRefresh[item.id] = nil
            await refreshPictures(of: item)
        }
    }

    /// A web wallpaper is watched only while it is on screen. If its files were changed in the
    /// meantime, its thumbnail and still show the old look; this notices and has them redone.
    func refreshPicturesIfOutdated(of item: Wallpaper) {
        let folder = library.projectURL(for: item)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        let changed = files.compactMap { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }.max()
        let thumbnail = library.thumbnailURL(for: item)
            .flatMap { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate }
        guard let changed, thumbnail.map({ $0 < changed }) ?? true else { return }
        webWallpaperDidChange(item)
    }

    /// Renders the library thumbnail of a web wallpaper and drops its still, which is rendered
    /// again when next needed.
    func refreshPictures(of item: Wallpaper) async {
        guard let current = library.item(withID: item.id), current.kind == .web,
              let project = WebProject(folder: library.projectURL(for: current))
        else {
            return
        }
        if let picture = await WebSnapshotter.render(project, size: NSSize(width: 960, height: 540)) {
            if let old = library.thumbnailURL(for: current) {
                ThumbnailCache.forget(old)
            }
            library.setThumbnail(WebSnapshotter.thumbnail(from: picture), for: current.id)
        }
        library.removeStill(for: current)
        resyncSystemWallpapers()
    }

    /// The still of a web wallpaper, rendered at the display's size if there is none yet.
    private func webStill(for item: Wallpaper, size: NSSize) async throws -> URL {
        if let rendered = library.renderedStillURL(for: item) {
            return rendered
        }
        if let running = webStillTasks[item.id] {
            return try await running.value
        }
        let task = Task { () throws -> URL in
            defer { webStillTasks[item.id] = nil }
            guard let project = WebProject(folder: library.projectURL(for: item)),
                  let picture = await WebSnapshotter.render(project, size: size, forStill: true)
            else {
                throw ImportError.unreadable
            }
            return try library.setStill(picture, for: item)
        }
        webStillTasks[item.id] = task
        return try await task.value
    }

    // MARK: - Music

    /// Whether music of the user's own plays in place of the wallpaper's sound.
    var playsMusic: Bool { preferences.playsSound && music.hasTracks }

    /// Whether anything can be heard at all: sound is on and the volume is above zero.
    private var isAudible: Bool { preferences.playsSound && preferences.volume > 0 }

    /// Brings the player in line with the music of the wallpaper that is heard: its folder,
    /// playlist and order. A song that is in the new list too goes on playing.
    private func reloadMusic() {
        // What the log is told, once the folder has been read: nil until then.
        var source: String? = "none"
        if let heard, let chosen = heard.wallpaper.shownSettings.music {
            let folder = musicFolders[chosen.folderPath]
            let tracks = folder?.tracks(inPlaylist: chosen.playlist) ?? []
            music.setTracks(tracks, shuffled: chosen.isShuffled)
            source = folder.map { _ in "\(heard.wallpaper.name): \(tracks.count) from \(chosen.folderPath)" }
            if folder == nil {
                readMusicFolder(at: chosen.folderPath)
            }
        } else {
            music.setTracks([], shuffled: false)
        }
        if let source, source != loggedMusicSource {
            loggedMusicSource = source
            Log.playback.info("Music: \(source, privacy: .public)")
        }
        applyPlaybackSettings()
        updatePlayback()
    }

    /// Reads a music folder, unless it has been read or is being read. It is done off the main
    /// thread, as a large collection takes a moment; `musicFolders` has it when it is done. The
    /// settings ask for the folder of the wallpaper they show, to list its playlists.
    func readMusicFolder(at path: String) {
        guard musicFolders[path] == nil, scanningMusicPaths.insert(path).inserted else { return }
        Task {
            let folder = await Task.detached(priority: .userInitiated) {
                MusicFolder.scan(URL(fileURLWithPath: path))
            }.value
            scanningMusicPaths.remove(path)
            // Kept under the path as it was asked for, which is how the wallpapers name it.
            musicFolders[path] = folder
            reloadMusic()
        }
    }

    /// Takes a folder that was just read, in place of what was known of it.
    func remember(_ folder: MusicFolder) {
        musicFolders[folder.url.path] = folder
        reloadMusic()
    }

    private func libraryDidChange() {
        // Forget wallpapers that were deleted from the library.
        let existing = Set(library.items.map(\.id))
        var cleaned = assignments
        if let id = cleaned.allDisplays, !existing.contains(id) {
            cleaned.allDisplays = nil
        }
        cleaned.displays = cleaned.displays.filter { _, id in id.map(existing.contains) ?? true }
        if cleaned != assignments {
            assignments = cleaned
            saveAssignments()
        }
        applyAssignments()
    }

    private func saveAssignments() {
        if let data = try? JSONEncoder().encode(assignments) {
            UserDefaults.standard.set(data, forKey: Self.assignmentsKey)
        }
    }

    /// Mirrors the wallpaper as a still picture into macOS, when the user asked for it.
    ///
    /// macOS keeps a desktop picture for every Space, and `setDesktopImageURL` changes only the
    /// Space in front. `resyncSystemWallpapers` therefore runs again whenever another Space comes
    /// to the front, so each one is corrected as soon as it is shown; otherwise the lock screen
    /// would show whatever picture that Space had before.
    private func syncSystemWallpapers() {
        guard preferences.setsSystemWallpaper else {
            syncedSystemWallpapers = [:]
            return
        }
        for screen in NSScreen.screens {
            guard
                let displayID = screens.first(where: { $0.value.isShown(on: screen) })?.key,
                let item = assignments.wallpaperID(forDisplay: displayID).flatMap(library.item(withID:)),
                syncedSystemWallpapers[displayID] != item.id
            else {
                continue
            }
            syncedSystemWallpapers[displayID] = item.id
            Task {
                do {
                    let url: URL
                    if screenLocked || displaysAsleep || !sessionActive, let frame = lockFrames[displayID] {
                        url = frame
                    } else if item.kind == .web {
                        url = try await webStill(for: item, size: screen.frame.size)
                    } else {
                        url = try await library.stillImageURL(for: item)
                    }
                    // What macOS reports is for the Space in front; skip it if it is right already.
                    let current = NSWorkspace.shared.desktopImageURL(for: screen)
                    guard current?.standardizedFileURL != url.standardizedFileURL else {
                        return
                    }
                    try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                        .allowClipping: true,
                    ])
                    Log.playback.notice("System wallpaper on \(screen.localizedName, privacy: .public): “\(item.name, privacy: .public)” replaces \(current?.lastPathComponent ?? "nothing", privacy: .public)")
                } catch {
                    syncedSystemWallpapers[displayID] = nil
                    NSLog("WallAero Engine: cannot set the system wallpaper: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Checks the picture again against what macOS has now, not against what was set last.
    private func resyncSystemWallpapers() {
        syncedSystemWallpapers = [:]
        syncSystemWallpapers()
    }

    @objc private func activeSpaceDidChange() {
        resyncSystemWallpapers()
        // Once more when the switch animation is over, in case macOS still reported the old Space.
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            resyncSystemWallpapers()
        }
    }

    @objc private func screensDidChange() {
        rebuildScreens()
    }

    @objc private func powerStateDidChange() {
        updatePlayback()
    }

    @objc private func displaysDidSleep() {
        displaysAsleep = true
        updatePlayback()
        takeLockFrames()
    }

    @objc private func displaysDidWake() {
        displaysAsleep = false
        forgetLockFramesIfUnlocked()
        updatePlayback()
        resyncSystemWallpapers()
    }

    @objc private func sessionDidResignActive() {
        sessionActive = false
        updatePlayback()
        takeLockFrames()
    }

    @objc private func sessionDidBecomeActive() {
        sessionActive = true
        forgetLockFramesIfUnlocked()
        updatePlayback()
        resyncSystemWallpapers()
    }

    @objc private func screenDidLock() {
        screenLocked = true
        updatePlayback()
        takeLockFrames()
    }

    @objc private func screenDidUnlock() {
        screenLocked = false
        lockFrames = [:]
        updatePlayback()
        resyncSystemWallpapers()
    }

    /// Displays that wake without the screen having been locked, or a session back without it,
    /// leave nothing for a lock screen: the next one gets the frame of its own moment.
    private func forgetLockFramesIfUnlocked() {
        if !screenLocked, !displaysAsleep, sessionActive {
            lockFrames = [:]
        }
    }

    /// Gives the lock screen what each display showed last: the frame the wallpaper stood at as
    /// the screen locked, its displays went to sleep or another user came in — whichever comes
    /// first. A paused wallpaper still has the picture it stopped on. A scene that keeps some of
    /// itself off the lock screen gets its picture rendered without that, as before.
    private func takeLockFrames() {
        guard preferences.setsSystemWallpaper, lockFrames.isEmpty else { return }
        for screen in NSScreen.screens {
            guard let (displayID, wallpaper) = screens.first(where: { $0.value.isShown(on: screen) }),
                  let item = wallpaper.item, item.kind != .image
            else { continue }
            if item.kind == .web, (try? SceneProject.read(from: library.projectURL(for: item)))?.hidesSomethingFromLockScreen == true {
                continue
            }
            // Taken now, before anything moves on; the file is written meanwhile.
            Task {
                guard let frame = await wallpaper.view.currentFrame(),
                      let url = try? library.setLockFrame(frame, forDisplay: displayID)
                else { return }
                lockFrames[displayID] = url
                do {
                    try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                        .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                        .allowClipping: true,
                    ])
                    syncedSystemWallpapers[displayID] = item.id
                    Log.playback.notice("Lock screen on \(screen.localizedName, privacy: .public): the frame “\(item.name, privacy: .public)” stood at")
                } catch {
                    NSLog("WallAero Engine: cannot set the lock screen picture: \(error.localizedDescription)")
                }
            }
        }
    }
}

/// The desktop window of a single display.
@MainActor
final class ScreenWallpaper: NSObject {
    let displayID: String
    let view: WallpaperView
    /// The window on the desktop. Not private: `--picture-desktop` takes a picture of it.
    let window: WallpaperWindow
    private(set) var item: Wallpaper?
    private var isPlaying = false
    private weak var manager: WallpaperManager?
    /// Says how much of the desktop shows around the windows over it; see `isVisibleOnScreen`.
    private let visibility: DesktopVisibility
    /// Whether the desktop is watched for being covered. It is not while the user would have
    /// the wallpaper play covered or not, or while nothing here moves.
    var watchesCover = true {
        didSet {
            if watchesCover != oldValue { updateVisibilityWatch() }
        }
    }
    /// Whether macOS has the window as one that can be seen, taken with a short delay when it
    /// says it cannot: as a window opens over the desktop macOS changes its mind several times
    /// within a moment, and the wallpaper would be paused and started again as often.
    private var windowIsSeen = true
    private var windowGoesUnseen: DispatchWorkItem?
    private static let unseenMustLast: TimeInterval = 0.4
    /// Tells a wallpaper that became ready late that another one has been asked for since.
    private var showGeneration = 0
    /// Whether scenes of Wallpaper Engine's are drawn by the app rather than by Chromium; the
    /// `NativeScenes` default, on unless set off, is there to compare the two.
    static var drawsScenesNatively: Bool {
        UserDefaults.standard.object(forKey: "NativeScenes") as? Bool ?? true
    }

    /// A wallpaper that cannot be shown is not waited for longer than this.
    private static let longestWaitForPicture: TimeInterval = 3

    init(screen: NSScreen, displayID: String, manager: WallpaperManager) {
        self.displayID = displayID
        self.manager = manager
        window = WallpaperWindow(screen: screen)
        view = WallpaperView(frame: NSRect(origin: .zero, size: screen.frame.size))
        visibility = DesktopVisibility(screen: screen)
        super.init()
        window.contentView = view
        visibility.onChange = { [weak self] in self?.manager?.updatePlayback() }
        NotificationCenter.default.addObserver(
            self, selector: #selector(occlusionStateDidChange),
            name: NSWindow.didChangeOcclusionStateNotification, object: window
        )
    }

    /// The page of a web wallpaper that is playing here, as what the mouse is passed on to.
    var pointerTarget: PointerForwarder.Target? {
        guard isPlaying else { return nil }
        // Another display's scene, shown here: the pointer here moves it there.
        if leader != nil, let scene = view.leader?.nativeView {
            let size = view.bounds.size
            return PointerForwarder.Target(id: ObjectIdentifier(view), frame: window.frame) { [weak scene] kind, point in
                scene?.pointer(kind, at: point, inViewOf: size)
            }
        }
        if let scene = view.nativeView {
            return PointerForwarder.Target(id: ObjectIdentifier(scene), frame: window.frame) { [weak scene] kind, point in
                scene?.pointer(kind, at: point)
            }
        }
        guard let page = view.webView else { return nil }
        return PointerForwarder.Target(id: ObjectIdentifier(page), frame: window.frame) { [weak page] kind, point in
            page?.pointer(kind, at: point)
        }
    }

    /// False while other windows, a full-screen app or the lock screen cover the desktop. The
    /// window alone does not tell: it counts as visible while any of it is, and the strip under
    /// the see-through menu bar is, whatever lies over the rest of the desktop.
    var isVisibleOnScreen: Bool {
        window.isVisible && windowIsSeen && !visibility.isCovered
    }

    /// The desktop is watched while a wallpaper that moves is on it.
    private func updateVisibilityWatch() {
        if watchesCover, let item, item.kind != .image, window.isVisible {
            visibility.show()
        } else {
            visibility.hide()
        }
    }

    func isShown(on screen: NSScreen) -> Bool {
        window.screen == screen || window.frame == screen.frame
    }

    func move(to screen: NSScreen) {
        window.setFrame(screen.frame, display: true)
        visibility.move(to: screen)
    }

    func setPlaying(_ playing: Bool, rate: Float) {
        if playing != isPlaying, let item, item.kind != .image {
            Log.playback.info("\(playing ? "Playing" : "Paused", privacy: .public) “\(item.name, privacy: .public)” on \(self.window.screen?.localizedName ?? self.displayID, privacy: .public)")
        }
        isPlaying = playing
        view.setPlaying(playing, rate: rate)
    }

    /// The display whose wallpaper this one shows, played and drawn there; see `WallpaperView.follow`.
    private(set) weak var leader: ScreenWallpaper?

    /// The display's pixels, to choose the one that draws a wallpaper shared by several.
    var pixelCount: CGFloat {
        let size = window.screen?.frame.size ?? window.frame.size
        let scale = window.screen?.backingScaleFactor ?? 2
        return size.width * size.height * scale * scale
    }

    func show(_ newItem: Wallpaper?, from library: WallpaperLibrary, following newLeader: ScreenWallpaper? = nil) {
        if let newLeader, let newItem {
            guard newItem.id != item?.id || leader !== newLeader else {
                item = newItem
                return
            }
            item = newItem
            leader = newLeader
            isPlaying = false
            showGeneration += 1
            let generation = showGeneration
            window.alphaValue = 0
            view.onReady = { [weak self] in self?.reveal(generation) }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.longestWaitForPicture) { [weak self] in
                self?.reveal(generation)
            }
            view.follow(newLeader.view)
            window.orderFrontRegardless()
            updateVisibilityWatch()
            return
        }
        // A display that showed another's wallpaper shows its own now, even the same one.
        let wasFollowing = leader != nil
        leader = nil
        guard newItem?.id != item?.id || wasFollowing else {
            // The same wallpaper, possibly with other settings; the manager applies those.
            item = newItem
            return
        }
        item = newItem
        isPlaying = false
        guard let newItem else {
            view.clear()
            window.orderOut(nil)
            updateVisibilityWatch()
            return
        }
        // The window stays out of sight until the wallpaper has a picture to show. Until then
        // the macOS wallpaper is what is seen, rather than a black screen.
        showGeneration += 1
        let generation = showGeneration
        window.alphaValue = 0
        view.onReady = { [weak self] in self?.reveal(generation) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.longestWaitForPicture) { [weak self] in
            self?.reveal(generation)
        }
        switch newItem.kind {
        case .video:
            view.showVideo(at: library.fileURL(for: newItem))
        case .image:
            view.showImage(at: library.fileURL(for: newItem))
        case .web:
            guard let project = WebProject(folder: library.projectURL(for: newItem)) else {
                Log.playback.error("The web wallpaper “\(newItem.name, privacy: .public)” has no page to show")
                view.clear()
                break
            }
            // The library's picture of it stands in until the page has drawn; the full-size
            // still if there is one, the thumbnail otherwise.
            let picture = (library.renderedStillURL(for: newItem) ?? library.thumbnailURL(for: newItem)).flatMap(NSImage.init(contentsOf:))
            // A scene of Wallpaper Engine's on its own is drawn by the app; anything else, and
            // any scene on a Mac where the app cannot, by Chromium.
            if Self.drawsScenesNatively, project.isScene, SceneProject.isNativelyPlayable(project.folder),
               view.showNativeScene(project.folder, backdrop: picture) {
                Log.playback.info("“\(newItem.name, privacy: .public)” is drawn by the app")
                view.nativeView?.onContentChange = { [weak self] in
                    guard let self else { return }
                    self.manager?.webWallpaperDidChange(newItem)
                }
            } else {
                view.showWeb(project, backdrop: picture)
                view.webView?.onContentChange = { [weak self] in
                    guard let self else { return }
                    self.manager?.webWallpaperDidChange(newItem)
                }
            }
            manager?.refreshPicturesIfOutdated(of: newItem)
        }
        window.orderFrontRegardless()
        updateVisibilityWatch()
    }

    private func reveal(_ generation: Int) {
        guard generation == showGeneration, window.alphaValue < 1 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            window.animator().alphaValue = 1
        }
    }

    func close() {
        NotificationCenter.default.removeObserver(self)
        visibility.hide()
        view.clear()
        window.orderOut(nil)
        window.close()
    }

    @objc private func occlusionStateDidChange() {
        windowGoesUnseen?.cancel()
        windowGoesUnseen = nil
        if window.occlusionState.contains(.visible) {
            // Back in view: at once.
            guard !windowIsSeen else { return }
            windowIsSeen = true
            manager?.updatePlayback()
        } else if windowIsSeen {
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.window.occlusionState.contains(.visible) else { return }
                self.windowIsSeen = false
                self.manager?.updatePlayback()
            }
            windowGoesUnseen = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.unseenMustLast, execute: work)
        }
    }
}

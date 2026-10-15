import AppKit
import AVFoundation
import Combine
import ImageIO
import WallpaperCore

/// What music plays now — its title, who plays it, its cover — for wallpapers that show it, as
/// many made for Wallpaper Engine do: the app's own music, Apple Music's or Spotify's, whichever
/// began last.
///
/// Since macOS 15.4 an app cannot ask the system what plays. Apple Music and Spotify tell anyone
/// who listens when what they play changes; their covers they give only when asked, and asking
/// them takes the user's leave, which macOS asks for once. So they are listened to, and asked,
/// only while a wallpaper on screen wants to know, and never started by being asked.
@MainActor
final class NowPlaying {
    static let shared = NowPlaying()

    /// Whether Apple Music and Spotify are asked anything; what they announce by themselves is
    /// heard all the same.
    static var asksPlayers = true

    enum State: Int {
        case stopped = 0, playing = 1, paused = 2
    }

    /// What one player says it plays.
    struct Track: Equatable {
        var title = ""
        var artist = ""
        var album = ""
        var albumArtist = ""
        var genre = ""
        var state = State.stopped
        /// Seconds into the track at `asOf`.
        var position = 0.0
        var asOf = Date()
        var duration = 0.0
        /// The file, or the player's own name for the track: the cover goes with it.
        var identity = ""
    }

    private enum Source: Hashable {
        case own, music, spotify

        var bundleIdentifier: String? {
            switch self {
            case .own: return nil
            case .music: return "com.apple.Music"
            case .spotify: return "com.spotify.client"
            }
        }
    }

    /// A cover made small enough to hand to a page, with the colors a wallpaper may dress itself in.
    private struct Cover {
        var identity: String
        var dataURL: String
        var colors: [String: [Double]]
    }

    private struct Listener {
        weak var owner: AnyObject?
        let handler: (String) -> Void
    }

    private var listeners: [ObjectIdentifier: Listener] = [:]
    private var tracks: [Source: Track] = [:]
    /// When each player began to play last.
    private var began: [Source: Date] = [:]
    private var cover: Cover?
    private var coverWanted: String?
    /// Players that would not tell their covers: the user said no.
    private var refused: Set<Source> = []
    private var observers: [NSObjectProtocol] = []
    private var ticker: Timer?
    private var lastSent = ""
    private weak var ownPlayer: PlaylistPlayer?
    private var ownWatch: AnyCancellable?
    /// The app's own files whose tags have been read.
    private var tagsRead: Set<String> = []

    private init() {}

    // MARK: - Listeners

    /// Starts handing `handler` the scripts that tell a page what plays: at once, and whenever
    /// it changes. The owner is not kept alive; when it goes away, so does its handler.
    func addListener(_ owner: AnyObject, handler: @escaping (String) -> Void) {
        let isFirst = listeners.isEmpty
        listeners[ObjectIdentifier(owner)] = Listener(owner: owner, handler: handler)
        if isFirst {
            start()
        }
        handler(script(full: true))
    }

    func removeListener(_ owner: AnyObject) {
        guard listeners.removeValue(forKey: ObjectIdentifier(owner)) != nil else { return }
        if listeners.isEmpty {
            stop()
        }
    }

    /// The app's own music, which the wallpapers' manager plays.
    func watch(_ player: PlaylistPlayer) {
        ownPlayer = player
        ownWatch = player.$currentTrack.combineLatest(player.$isPlaying)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.ownMusicChanged() }
    }

    private func start() {
        let center = DistributedNotificationCenter.default()
        observers = [
            center.addObserver(forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                MainActor.assumeIsolated { self?.musicSaid(info) }
            },
            center.addObserver(forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                MainActor.assumeIsolated { self?.spotifySaid(info) }
            },
        ]
        ownMusicChanged()
        // What plays already: a player that runs is asked once.
        askMusic()
        askSpotify()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stop() {
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
        observers = []
        ticker?.invalidate()
        ticker = nil
        tracks[.music] = nil
        tracks[.spotify] = nil
    }

    // MARK: - What the players say

    private func ownMusicChanged() {
        guard !listeners.isEmpty, let player = ownPlayer else { return }
        guard let file = player.currentTrack else {
            set(.own, nil)
            return
        }
        var track = tracks[.own]?.identity == file.path ? tracks[.own]! : Track(identity: file.path)
        if track.title.isEmpty {
            track.title = file.deletingPathExtension().lastPathComponent
        }
        track.state = player.isPlaying ? .playing : .paused
        track.position = player.position
        track.duration = player.duration
        track.asOf = Date()
        set(.own, track)
        if tagsRead.insert(file.path).inserted {
            readTags(of: file)
        }
    }

    /// The title, the artist, the album and the cover kept in the file itself.
    private func readTags(of file: URL) {
        Task { [weak self] in
            let asset = AVURLAsset(url: file)
            guard let items = try? await asset.load(.commonMetadata) else { return }
            var found: [AVMetadataKey: String] = [:]
            var artwork: Data?
            for item in items {
                guard let key = item.commonKey else { continue }
                if key == .commonKeyArtwork {
                    artwork = try? await item.load(.dataValue)
                } else if let text = try? await item.load(.stringValue) {
                    found[key] = text
                }
            }
            await MainActor.run {
                guard let self, var track = self.tracks[.own], track.identity == file.path else {
                    self?.tagsRead.remove(file.path)
                    return
                }
                track.title = found[.commonKeyTitle] ?? track.title
                track.artist = found[.commonKeyArtist] ?? found[.commonKeyCreator] ?? ""
                track.album = found[.commonKeyAlbumName] ?? ""
                track.genre = found[.commonKeyType] ?? ""
                self.set(.own, track)
                if let artwork {
                    self.coverArrived(artwork, for: file.path)
                }
            }
        }
    }

    private static func state(_ text: Any?) -> State {
        switch (text as? String)?.lowercased() {
        case "playing": return .playing
        case "paused": return .paused
        default: return .stopped
        }
    }

    private func musicSaid(_ info: [AnyHashable: Any]) {
        var track = Track()
        track.title = info["Name"] as? String ?? ""
        track.artist = info["Artist"] as? String ?? ""
        track.album = info["Album"] as? String ?? ""
        track.albumArtist = info["Album Artist"] as? String ?? ""
        track.genre = info["Genre"] as? String ?? ""
        track.state = Self.state(info["Player State"])
        track.duration = ((info["Total Time"] as? NSNumber)?.doubleValue ?? 0) / 1000
        track.position = tracks[.music].map { $0.title == track.title ? livePosition($0) : 0 } ?? 0
        track.identity = "music:" + ((info["PersistentID"] as? NSNumber)?.stringValue ?? "\(track.title)|\(track.artist)|\(track.album)")
        set(.music, track.state == .stopped ? nil : track)
        // Where it is in the track and the cover, from the player itself.
        askMusic()
    }

    private func spotifySaid(_ info: [AnyHashable: Any]) {
        var track = Track()
        track.title = info["Name"] as? String ?? ""
        track.artist = info["Artist"] as? String ?? ""
        track.album = info["Album"] as? String ?? ""
        track.albumArtist = info["Album Artist"] as? String ?? ""
        track.state = Self.state(info["Player State"])
        track.duration = ((info["Duration"] as? NSNumber)?.doubleValue ?? 0) / 1000
        track.position = (info["Playback Position"] as? NSNumber)?.doubleValue ?? 0
        track.identity = "spotify:" + (info["Track ID"] as? String ?? "\(track.title)|\(track.artist)")
        set(.spotify, track.state == .stopped ? nil : track)
        askSpotifyCover()
    }

    // MARK: - Asking the players

    private func isRunning(_ source: Source) -> Bool {
        guard let identifier = source.bundleIdentifier else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty
    }

    /// Runs a script that talks to a player that is running. Nil if it failed; a player the
    /// user would not let the app talk to is not asked again.
    private func run(_ source: String, of player: Source) -> NSAppleEventDescriptor? {
        guard Self.asksPlayers, isRunning(player), !refused.contains(player), let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            // -1743: the user said no. -1744: they would be asked, and are not to be here.
            if let number = error[NSAppleScript.errorNumber] as? Int, number == -1743 || number == -1744 {
                refused.insert(player)
            }
            return nil
        }
        return result
    }

    private func askMusic() {
        guard !listeners.isEmpty, isRunning(.music) else { return }
        let source = """
        tell application id "com.apple.Music"
          set out to {player state as text, "", "", "", 0, 0, ""}
          if player state is not stopped then
            set t to current track
            set out to {player state as text, name of t, artist of t, album of t, player position, duration of t, persistent ID of t}
          end if
          return out
        end tell
        """
        guard let result = run(source, of: .music), result.numberOfItems >= 7 else { return }
        func item(_ index: Int) -> NSAppleEventDescriptor? { result.atIndex(index) }
        var track = tracks[.music] ?? Track()
        track.state = Self.state(item(1)?.stringValue)
        if let name = item(2)?.stringValue, !name.isEmpty { track.title = name }
        if let artist = item(3)?.stringValue, !artist.isEmpty { track.artist = artist }
        if let album = item(4)?.stringValue, !album.isEmpty { track.album = album }
        track.position = item(5)?.doubleValue ?? 0
        track.duration = item(6)?.doubleValue ?? track.duration
        if let identity = item(7)?.stringValue, !identity.isEmpty { track.identity = "music:" + identity }
        track.asOf = Date()
        set(.music, track.state == .stopped ? nil : track)
        guard let playing = tracks[.music], cover?.identity != playing.identity, coverWanted != playing.identity else { return }
        coverWanted = playing.identity
        let coverSource = """
        tell application id "com.apple.Music"
          if player state is not stopped then
            try
              return raw data of artwork 1 of current track
            end try
          end if
        end tell
        """
        if let data = run(coverSource, of: .music)?.data, !data.isEmpty {
            coverArrived(data, for: playing.identity)
        }
    }

    private func askSpotify() {
        guard !listeners.isEmpty, isRunning(.spotify) else { return }
        let source = """
        tell application id "com.spotify.client"
          set out to {player state as text, "", "", "", 0, 0, ""}
          if player state is not stopped then
            set t to current track
            set out to {player state as text, name of t, artist of t, album of t, player position, duration of t, id of t}
          end if
          return out
        end tell
        """
        guard let result = run(source, of: .spotify), result.numberOfItems >= 7 else { return }
        func item(_ index: Int) -> NSAppleEventDescriptor? { result.atIndex(index) }
        var track = tracks[.spotify] ?? Track()
        track.state = Self.state(item(1)?.stringValue)
        if let name = item(2)?.stringValue, !name.isEmpty { track.title = name }
        if let artist = item(3)?.stringValue, !artist.isEmpty { track.artist = artist }
        if let album = item(4)?.stringValue, !album.isEmpty { track.album = album }
        track.position = item(5)?.doubleValue ?? 0
        // Spotify counts the length in milliseconds.
        track.duration = (item(6)?.doubleValue ?? 0) / 1000
        if let identity = item(7)?.stringValue, !identity.isEmpty { track.identity = "spotify:" + identity }
        track.asOf = Date()
        set(.spotify, track.state == .stopped ? nil : track)
        askSpotifyCover()
    }

    /// Spotify gives the address of its cover; the picture is fetched from there.
    private func askSpotifyCover() {
        guard let playing = tracks[.spotify], cover?.identity != playing.identity, coverWanted != playing.identity else { return }
        coverWanted = playing.identity
        let source = """
        tell application id "com.spotify.client"
          if player state is not stopped then return artwork url of current track
        end tell
        """
        guard let address = run(source, of: .spotify)?.stringValue, let url = URL(string: address),
              url.scheme == "https" else { return }
        let identity = playing.identity
        Task { [weak self] in
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            await MainActor.run { self?.coverArrived(data, for: identity) }
        }
    }

    // MARK: - What is told

    private func set(_ source: Source, _ track: Track?) {
        let before = tracks[source]
        if track?.state == .playing, before?.state != .playing || before?.identity != track?.identity {
            began[source] = Date()
        }
        tracks[source] = track
        send()
    }

    /// The track the wallpapers are told of: of those that play, the one that began last; if
    /// none plays, the one paused last.
    private var current: Track? {
        let playing = tracks.filter { $0.value.state == .playing }
        if let latest = playing.max(by: { (began[$0.key] ?? .distantPast) < (began[$1.key] ?? .distantPast) }) {
            return latest.value
        }
        return tracks.values.filter { $0.state == .paused }.max { $0.asOf < $1.asOf }
    }

    private func livePosition(_ track: Track) -> Double {
        guard track.state == .playing else { return track.position }
        let position = track.position + Date().timeIntervalSince(track.asOf)
        return track.duration > 0 ? min(position, track.duration) : position
    }

    private func tick() {
        // The app's own player is asked where it is; the others are counted on from what they said.
        if let player = ownPlayer, var own = tracks[.own], own.state == .playing {
            own.position = player.position
            own.asOf = Date()
            tracks[.own] = own
        }
        guard current?.state == .playing else { return }
        deliver(script(full: false))
    }

    private func send() {
        let script = script(full: true)
        guard script != lastSent else { return }
        lastSent = script
        deliver(script)
    }

    private func deliver(_ script: String) {
        for (key, listener) in listeners {
            if listener.owner == nil {
                listeners[key] = nil
            } else {
                listener.handler(script)
            }
        }
        if listeners.isEmpty {
            stop()
        }
    }

    /// The script that tells a page: all of it, or where the track has got to.
    private func script(full: Bool) -> String {
        var message: [String: Any]
        if let track = current {
            let position = livePosition(track)
            if full {
                let shown = cover?.identity == track.identity ? cover : nil
                message = [
                    "enabled": true, "title": track.title, "artist": track.artist, "subTitle": "",
                    "albumTitle": track.album, "albumArtist": track.albumArtist, "genres": track.genre, "contentType": "music",
                    "state": track.state.rawValue, "position": position, "duration": track.duration,
                    "thumbnail": shown?.dataURL ?? "", "colors": shown?.colors ?? [:],
                ]
            } else {
                message = ["timeline": ["position": position, "duration": track.duration]]
            }
        } else {
            message = full ? ["enabled": false, "state": State.stopped.rawValue] : ["timeline": ["position": 0, "duration": 0]]
        }
        let data = (try? JSONSerialization.data(withJSONObject: message)) ?? Data("{}".utf8)
        return "window.__wallaeroHost && window.__wallaeroHost.media && window.__wallaeroHost.media(\(String(decoding: data, as: UTF8.self)))"
    }

    // MARK: - Covers

    private func coverArrived(_ data: Data, for identity: String) {
        guard let made = Self.cover(from: data, identity: identity) else { return }
        cover = made
        if coverWanted == identity {
            coverWanted = nil
        }
        lastSent = ""
        send()
    }

    /// The cover no larger than a page needs, and its colors: the whole of it on average, its
    /// darker and its lighter half, and a color for text on it.
    private static func cover(from data: Data, identity: String) -> Cover? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 512,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary)
        else {
            return nil
        }
        let picture = NSBitmapImageRep(cgImage: image)
        guard let jpeg = picture.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return nil }

        // The colors, from the cover made tiny.
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        var colors: [String: [Double]] = [:]
        if drawn {
            let all = stride(from: 0, to: pixels.count, by: 4).map { [Double(pixels[$0]) / 255, Double(pixels[$0 + 1]) / 255, Double(pixels[$0 + 2]) / 255] }
            func light(_ color: [Double]) -> Double { 0.2126 * color[0] + 0.7152 * color[1] + 0.0722 * color[2] }
            func average(_ list: [[Double]]) -> [Double] {
                guard !list.isEmpty else { return [0, 0, 0] }
                return (0..<3).map { part in list.reduce(0) { $0 + $1[part] } / Double(list.count) }
            }
            let sorted = all.sorted { light($0) < light($1) }
            let primary = average(all)
            let darker = average(Array(sorted.prefix(sorted.count / 2)))
            let lighter = average(Array(sorted.suffix(sorted.count / 2)))
            let text: [Double] = light(primary) > 0.55 ? [0, 0, 0] : [1, 1, 1]
            let contrast = abs(light(lighter) - light(primary)) > abs(light(darker) - light(primary)) ? lighter : darker
            colors = ["primary": primary, "secondary": darker, "tertiary": lighter, "text": text,
                      "highContrast": abs(light(contrast) - light(primary)) > 0.35 ? contrast : text]
        }
        return Cover(identity: identity, dataURL: "data:image/jpeg;base64," + jpeg.base64EncodedString(), colors: colors)
    }
}

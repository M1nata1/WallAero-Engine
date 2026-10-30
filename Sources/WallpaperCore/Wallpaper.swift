import Foundation

/// A single entry of the wallpaper library.
public struct Wallpaper: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Played with AVFoundation. Animated images are converted to video on import.
        case video
        /// A still picture.
        case image
        /// A web page in a folder of its own: a scene made in the editor, or any page with an
        /// `index.html`. `fileName` is the page, relative to the library's web folder.
        case web
    }

    public let id: UUID
    public var name: String
    public var kind: Kind
    /// File name inside the library's media folder.
    public var fileName: String
    /// File name inside the library's thumbnail folder.
    public var thumbnailFileName: String?
    /// Short uppercase label of the original format, e.g. "GIF" or "MP4".
    public var sourceFormat: String
    /// Whether the original file was converted to video during import.
    public var wasConverted: Bool
    /// Size of the original media, in pixels.
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Loop length in seconds; nil for still images.
    public var duration: Double?
    public var hasAudio: Bool
    /// Size of the stored media file, in bytes.
    public var fileSize: Int64
    public var dateAdded: Date
    /// How this wallpaper is shown, once that has been set; `shownSettings` is what to go by.
    public var settings: Settings?
    /// The tags the user gave it, once there are any; `tagList` is what to go by.
    public var tags: [String]?
    /// The number of the Steam Workshop item it was downloaded from, if it was.
    public var workshopID: String?

    /// What every wallpaper lets be set: how it fills the screen, how fast it plays and what
    /// music goes with it.
    public struct Settings: Codable, Hashable, Sendable {
        /// Music of the user's own that plays while the wallpaper is on, in place of its sound.
        public struct Music: Codable, Hashable, Sendable {
            /// The folder with the songs.
            public var folderPath: String
            /// The playlist to play from that folder; nil plays all the music in it.
            public var playlist: String?
            public var isShuffled: Bool

            public init(folderPath: String, playlist: String? = nil, isShuffled: Bool = false) {
                self.folderPath = folderPath
                self.playlist = playlist
                self.isShuffled = isShuffled
            }
        }

        public enum Scaling: String, Codable, CaseIterable, Sendable {
            /// Covers the whole screen, cropping the edges if the proportions differ.
            case fill
            /// Shows the whole picture, with black bars.
            case fit
            case stretch
        }

        public var scaling: Scaling
        /// Which part stays in view when filling the screen crops the picture, in percent:
        /// 0 keeps the left or the top, 100 the right or the bottom, 50 the middle.
        public var position: Double
        /// 1 is the wallpaper's own speed.
        public var speed: Double
        /// Nil: no music of its own, and a video is heard with its own sound.
        public var music: Music?

        public init(scaling: Scaling = .fill, position: Double = 50, speed: Double = 1, music: Music? = nil) {
            self.scaling = scaling
            self.position = position
            self.speed = speed
            self.music = music
        }
    }

    /// The settings to show the wallpaper with: its own, or the usual ones until it has any.
    public var shownSettings: Settings { settings ?? Settings() }

    public var tagList: [String] { tags ?? [] }

    /// Of the wallpapers on the displays, in the displays' order, the one that is heard: the
    /// first with music of its own or with sound in its video. Only one is, so that two do not
    /// sound at once. `index` is its place in the list.
    public static func heard(among shown: [Wallpaper?]) -> (index: Int, wallpaper: Wallpaper)? {
        for (index, wallpaper) in shown.enumerated() {
            if let wallpaper, wallpaper.shownSettings.music != nil || wallpaper.hasAudio {
                return (index, wallpaper)
            }
        }
        return nil
    }

    /// Whether a search for `text` among the wallpapers the ticked tags leave finds this one.
    /// The tags come in groups, one per category: a wallpaper stays if it has a tag from every
    /// group, any one of that group's. The text is looked for in the name and in the tags,
    /// whatever the case; no text finds them all.
    public func matches(search text: String, tagGroups: [Set<String>] = []) -> Bool {
        let own = Set(tagList.map { $0.lowercased() })
        for group in tagGroups where !group.isEmpty {
            guard group.contains(where: { own.contains($0.lowercased()) }) else { return false }
        }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || name.localizedStandardContains(text) || tagList.contains { $0.localizedStandardContains(text) }
    }

    public init(
        id: UUID,
        name: String,
        kind: Kind,
        fileName: String,
        thumbnailFileName: String?,
        sourceFormat: String,
        wasConverted: Bool,
        pixelWidth: Int,
        pixelHeight: Int,
        duration: Double?,
        hasAudio: Bool,
        fileSize: Int64,
        dateAdded: Date = Date(),
        settings: Settings? = nil,
        tags: [String]? = nil,
        workshopID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.fileName = fileName
        self.thumbnailFileName = thumbnailFileName
        self.sourceFormat = sourceFormat
        self.wasConverted = wasConverted
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.hasAudio = hasAudio
        self.fileSize = fileSize
        self.dateAdded = dateAdded
        self.settings = settings
        self.tags = tags
        self.workshopID = workshopID
    }
}

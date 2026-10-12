import Foundation

public enum ImportError: LocalizedError, Equatable {
    /// The file is neither a video nor an image. Carries the file extension.
    case unsupportedFormat(String)
    case unreadable
    case noVideoTrack
    /// AVFoundation recognises the container but cannot decode it (WebM, AV1 on older Macs, …).
    case undecodableVideo
    case conversionFailed(String)
    /// The folder has no page to show.
    case noWebPage
    /// A wallpaper made for Wallpaper Engine of a kind that cannot be shown: an application.
    /// Carries the kind as the wallpaper names it.
    case unsupportedWallpaperEngineKind(String)
    /// One of Wallpaper Engine's own scenes with no picture in it that could be read.
    case noPicturesInScene
    case unreadableArchive
    /// The archive unpacks, but has no wallpaper, page, video or picture in it.
    case emptyArchive

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let fileExtension) where fileExtension.isEmpty:
            return NSLocalizedString("This file type is not supported.", comment: "Import error")
        case .unsupportedFormat(let fileExtension):
            return String(
                format: NSLocalizedString(
                    "The “%@” format is not supported. Use GIF, MP4, MOV, PNG, JPEG, HEIC or WebP.",
                    comment: "Import error; the argument is a file extension"
                ),
                fileExtension.uppercased()
            )
        case .unreadable:
            return NSLocalizedString("The file could not be read.", comment: "Import error")
        case .noVideoTrack:
            return NSLocalizedString("The file contains no video.", comment: "Import error")
        case .undecodableVideo:
            return NSLocalizedString(
                "macOS cannot play this video. Convert it to MP4 or MOV (H.264 or HEVC).",
                comment: "Import error"
            )
        case .noWebPage:
            return NSLocalizedString("The folder has no web page to show. It needs an index.html.", comment: "Import error")
        case .unsupportedWallpaperEngineKind(let kind):
            return String(
                format: NSLocalizedString(
                    "This Wallpaper Engine wallpaper is of the “%@” kind. Only web pages, scenes and videos can be opened.",
                    comment: "Import error; the argument is Wallpaper Engine's name of the kind, such as application"
                ),
                kind
            )
        case .noPicturesInScene:
            return NSLocalizedString("This Wallpaper Engine scene has no pictures that could be read.", comment: "Import error")
        case .unreadableArchive:
            return NSLocalizedString("The archive could not be unpacked.", comment: "Import error")
        case .emptyArchive:
            return NSLocalizedString("The archive has no wallpaper in it: no web page, video or picture.", comment: "Import error")
        case .conversionFailed(let reason):
            return String(
                format: NSLocalizedString("Conversion failed: %@", comment: "Import error; the argument is the reason"),
                reason
            )
        }
    }
}

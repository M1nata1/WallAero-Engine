import CryptoKit
import Foundation
import ImageIO

/// The pictures of Workshop items, kept on disk for a day so that going through the list again
/// costs no traffic. What is kept is the first frame at the size of a tile: many previews are
/// GIFs of a megabyte, which Steam does not scale. An item opened by the user has its preview
/// kept whole as well, for as long.
public struct SteamWorkshopPreviews: Sendable {
    /// Twice the width of a tile, for a Retina display.
    private static let pixels = 432

    public let folder: URL
    /// How long a picture is kept, in seconds.
    public let lifetime: TimeInterval

    public init(folder: URL, lifetime: TimeInterval = 24 * 60 * 60) {
        self.folder = folder
        self.lifetime = lifetime
    }

    /// The app's place for what can be got again.
    public static var defaultFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.fadevec.WallAeroEngine/WorkshopPreviews", isDirectory: true)
    }

    private func file(for url: URL, extension kind: String = "jpg") -> URL {
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(name).appendingPathExtension(kind)
    }

    private func isExpired(_ file: URL, at date: Date) -> Bool {
        let written = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return written.map { date.timeIntervalSince($0) >= lifetime } ?? true
    }

    /// The picture kept for `url`, if it is no older than a day.
    public func kept(for url: URL, at date: Date = Date()) -> CGImage? {
        let file = file(for: url)
        guard !isExpired(file, at: date), let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Makes the picture out of what was downloaded from `url`, and keeps it.
    public func keep(_ data: Data, for url: URL) -> CGImage? {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: Self.pixels]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let frame = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return nil
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Thumbnailer.writeJPEG(frame, to: file(for: url))
        return frame
    }

    /// The preview at `url` as it was downloaded, if it is no older than a day.
    public func keptOriginal(for url: URL, at date: Date = Date()) -> Data? {
        let file = file(for: url, extension: "original")
        return isExpired(file, at: date) ? nil : try? Data(contentsOf: file)
    }

    public func keepOriginal(_ data: Data, for url: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file(for: url, extension: "original"), options: .atomic)
    }

    /// Lets go of the pictures that are more than a day old.
    public func removeExpired(at date: Date = Date()) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where isExpired(file, at: date) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

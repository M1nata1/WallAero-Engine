import AVFoundation
import Foundation

/// A video as a texture of a Wallpaper Engine scene holds one: an MP4 file with H.264 pictures,
/// which Windows plays by itself. A video in another codec or container is made into one.
public enum WallpaperEngineVideo {
    public enum Problem: LocalizedError {
        case unreadable
        case cannotConvert

        public var errorDescription: String? {
            switch self {
            case .unreadable: return NSLocalizedString("The video cannot be read.", comment: "Editor error")
            case .cannotConvert: return NSLocalizedString("The video cannot be converted for Wallpaper Engine.", comment: "Editor error")
            }
        }
    }

    /// The video as an H.264 MP4 file, and the size its pictures are shown at.
    public static func prepare(_ source: URL) async throws -> (file: Data, width: Int, height: Int) {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Problem.unreadable }
        let (natural, transform, descriptions) = try await track.load(.naturalSize, .preferredTransform, .formatDescriptions)
        let shown = natural.applying(transform)
        let width = Int(abs(shown.width).rounded()), height = Int(abs(shown.height).rounded())
        let isH264 = descriptions.contains { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 }
        if isH264, source.pathExtension.lowercased() == "mp4" {
            return (try Data(contentsOf: source), width, height)
        }
        // H.264 in another box is put into an MP4 one as it is; anything else is encoded anew,
        // no larger than 4K, which Wallpaper Engine plays.
        let preset = isH264 ? AVAssetExportPresetPassthrough
            : (max(width, height) > 1920 ? AVAssetExportPreset3840x2160 : AVAssetExportPreset1920x1080)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw Problem.cannotConvert }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("WallAero-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        session.outputURL = output
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        await session.export()
        guard session.status == .completed else { throw Problem.cannotConvert }
        return (try Data(contentsOf: output), width, height)
    }
}

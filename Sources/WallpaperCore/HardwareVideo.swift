import AVFoundation
import Foundation
import VideoToolbox

/// The Mac's media engine decodes most videos for next to nothing; a video it cannot decode —
/// H.264 wider than 4096 pixels, say — is decoded by the processor instead, at twenty times the
/// energy (measured: 5.5 W in place of 0.3 W for a 4320 × 2160 video at 60 frames a second on an
/// M4). Such a video is made over in HEVC, which the media engine decodes at that size, as
/// large and as fast as it was.
public enum HardwareVideo {
    /// Whether the media engine decodes the video's pictures. True when that cannot be told:
    /// nothing is done to a video for a doubt.
    public static func isDecodedInHardware(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let format = try? await track.load(.formatDescriptions).first
        else {
            return true
        }
        let required = [kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: true] as CFDictionary
        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(allocator: nil, formatDescription: format, decoderSpecification: required,
                                                  imageBufferAttributes: nil, outputCallback: nil, decompressionSessionOut: &session)
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        return status == noErr
    }

    /// Makes the video over in HEVC in its place if the media engine does not decode it, and
    /// says whether it did. The new file takes the place of the old only once it is whole, is
    /// decoded by the media engine and lasts as long.
    @discardableResult
    public static func makeDecodableInHardware(_ url: URL) async throws -> Bool {
        guard await !isDecodedInHardware(url) else { return false }
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality) else { return false }
        let made = url.deletingLastPathComponent().appendingPathComponent(".hevc-\(UUID().uuidString).\(url.pathExtension.isEmpty ? "mp4" : url.pathExtension)")
        defer { try? FileManager.default.removeItem(at: made) }
        try await export.export(to: made, as: url.pathExtension.lowercased() == "mov" ? .mov : .mp4)
        let before = try await asset.load(.duration).seconds
        let after = try await AVURLAsset(url: made).load(.duration).seconds
        guard await isDecodedInHardware(made), abs(before - after) < 0.5 else { return false }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: made)
        return true
    }
}

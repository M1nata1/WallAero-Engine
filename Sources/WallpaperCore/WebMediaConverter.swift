import Accelerate
import AVFoundation
import CCodecs
import CoreMedia
import Foundation

/// Chromium, which draws the web wallpapers, plays only open formats: no H.264, HEVC or AAC, the
/// codecs nearly every video comes in. The videos and sounds of a web wallpaper or a scene are
/// therefore turned into WebM (VP9 pictures, Opus sound) once, when the wallpaper comes into the
/// library, and written back under their own names: Chromium goes by what is in a file, not by
/// its name, so pages and scenes that point at "clip.mp4" play the WebM in it unchanged.
///
/// The original files are kept in the folder's `originalsFolderName`, out of the page's way.
public enum WebMediaConverter {
    /// Where the encoders are (libWallAeroCodecs.dylib); set by the app when it starts.
    public static var libraryURL: URL?

    /// The hidden folder of a wallpaper that keeps the files as they were before.
    public static let originalsFolderName = ".originals"

    public enum ConversionError: Error, Equatable {
        case encodersMissing
        case unreadable
        case encoderFailed
    }

    /// The names a video or a sound in a page may have that AVFoundation can read.
    static let candidateExtensions: Set<String> = ["mp4", "m4v", "mov", "qt", "m4a", "aac", "3gp", "3g2", "caf"]
    /// Pictures and sounds Chromium plays as they are.
    static let openVideoCodecs: Set<FourCharCode> = [fourCC("vp08"), fourCC("vp09"), fourCC("av01")]
    static let openAudioCodecs: Set<FourCharCode> = [fourCC("opus"), fourCC(".mp3"), fourCC("fLaC"), kAudioFormatLinearPCM]

    public static var encodersAvailable: Bool {
        guard let libraryURL else { return false }
        return wa_codecs_load(libraryURL.path) == 1
    }

    // MARK: - Folders

    /// Converts every video and sound of the folder Chromium cannot play, in place, keeping the
    /// originals. Returns the files converted, relative to the folder. A file that cannot be
    /// converted is left as it was.
    @discardableResult
    public static func convertFolder(_ folder: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async -> [String] {
        var converted: [String] = []
        // Paths compared as they really are: a folder may be reached through a link.
        let root = folder.resolvingSymlinksInPath().path
        let needing = await filesNeedingConversion(in: folder)
        // How far it has come, by the size of the files: a large video takes the longest.
        let sizes = needing.map { Double((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 1) }
        let total = max(sizes.reduce(0, +), 1)
        var done = 0.0
        for (index, file) in needing.enumerated() {
            let before = done, share = sizes[index]
            defer {
                done += share
                progress(done / total)
            }
            let path = file.resolvingSymlinksInPath().path
            guard path.hasPrefix(root + "/") else { continue }
            let relative = String(path.dropFirst(root.count + 1))
            let original = folder.appendingPathComponent(originalsFolderName).appendingPathComponent(relative)
            let temporary = file.deletingLastPathComponent().appendingPathComponent(".\(file.lastPathComponent).webm-\(UUID().uuidString)")
            do {
                try await convert(file, to: temporary) { part in progress((before + part * share) / total) }
                let files = FileManager.default
                // What is laid out of a scene's project for the player is in the project as it
                // was; a second copy of it is not kept.
                let isLaidOut = relative.hasPrefix(WallpaperEngineScene.folderName + "/")
                    && files.fileExists(atPath: folder.appendingPathComponent(WallpaperEngineProjectFolder.folderName).path)
                // Save one: a video made of a picture the user chose for a setting, laid out by its
                // number, is not in the project; the Mac's own player is given it from beside the
                // scene (see `nativeVideos`).
                let isChosen = isLaidOut && (file.deletingPathExtension().lastPathComponent).allSatisfy(\.isNumber)
                if isLaidOut && !isChosen {
                    try files.removeItem(at: file)
                } else if isChosen {
                    let native = folder.appendingPathComponent(".native-videos").appendingPathComponent(file.lastPathComponent)
                    try files.createDirectory(at: native.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if files.fileExists(atPath: native.path) {
                        try files.removeItem(at: native)
                    }
                    try files.moveItem(at: file, to: native)
                } else {
                    try files.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if files.fileExists(atPath: original.path) {
                        try files.removeItem(at: original)
                    }
                    try files.moveItem(at: file, to: original)
                }
                try files.moveItem(at: temporary, to: file)
                converted.append(relative)
            } catch {
                try? FileManager.default.removeItem(at: temporary)
            }
        }
        return converted
    }

    /// The videos and sounds of the folder, at any depth, that Chromium cannot play.
    public static func filesNeedingConversion(in folder: URL) async -> [URL] {
        let files = FileManager.default
        guard let walker = files.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
                                            options: [.skipsHiddenFiles]) else { return [] }
        var found: [URL] = []
        while let file = walker.nextObject() as? URL {
            // A scene's Wallpaper Engine project stays as Wallpaper Engine takes it; the player
            // plays copies of its files made elsewhere in the folder.
            if file.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL,
               file.lastPathComponent == WallpaperEngineProjectFolder.folderName {
                walker.skipDescendants()
                continue
            }
            guard candidateExtensions.contains(file.pathExtension.lowercased()),
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { continue }
            if await needsConversion(file) {
                found.append(file)
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    /// Whether the file is a video or a sound in a codec Chromium does not play. A file
    /// AVFoundation cannot read (WebM, say) is taken to be fine as it is.
    public static func needsConversion(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.load(.tracks) else { return false }
        for track in tracks {
            guard let descriptions = try? await track.load(.formatDescriptions) else { continue }
            for description in descriptions {
                let codec = CMFormatDescriptionGetMediaSubType(description)
                switch track.mediaType {
                case .video where !openVideoCodecs.contains(codec): return true
                case .audio where !openAudioCodecs.contains(codec): return true
                default: continue
                }
            }
        }
        return false
    }

    // MARK: - One file

    /// Writes `source` to `destination` as WebM.
    /// - Parameter progress: how far it has come, from 0 to 1, by the time of the video.
    public static func convert(_ source: URL, to destination: URL, progress: (Double) -> Void = { _ in }) async throws {
        guard encodersAvailable else { throw ConversionError.encodersMissing }
        let asset = AVURLAsset(url: source)
        guard let duration = try? await asset.load(.duration) else { throw ConversionError.unreadable }
        let videoTrack = try? await asset.loadTracks(withMediaType: .video).first
        let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first
        guard videoTrack != nil || audioTrack != nil else { throw ConversionError.unreadable }

        var videoInfo: (width: Int, height: Int, fps: Double, bt709: Bool, fullRange: Bool)?
        if let videoTrack {
            let (size, rate, descriptions) = try await videoTrack.load(.naturalSize, .nominalFrameRate, .formatDescriptions)
            let width = Int(abs(size.width).rounded()), height = Int(abs(size.height).rounded())
            var bt709 = height >= 720
            if let description = descriptions.first,
               let matrix = CMFormatDescriptionGetExtension(description, extensionKey: kCMFormatDescriptionExtension_YCbCrMatrix) as? String {
                bt709 = matrix == (kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String)
            }
            if width >= 2, height >= 2 {
                videoInfo = (width, height, Double(rate > 0 ? rate : 30), bt709, false)
            }
        }
        let channels = audioTrack == nil ? 0 : min(2, max(1, await channelCount(of: audioTrack!)))

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw ConversionError.unreadable
        }
        var videoOutput: AVAssetReaderTrackOutput?
        if let videoTrack, videoInfo != nil {
            let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            ])
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) { reader.add(output); videoOutput = output }
        }
        var audioOutput: AVAssetReaderTrackOutput?
        if let audioTrack, channels > 0 {
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
            ])
            output.alwaysCopiesSampleData = false
            if reader.canAdd(output) { reader.add(output); audioOutput = output }
        }
        guard videoOutput != nil || audioOutput != nil, reader.startReading() else { throw ConversionError.unreadable }
        defer { reader.cancelReading() }

        // The encoders.
        var video: OpaquePointer?
        if let info = videoInfo, videoOutput != nil {
            video = wa_vp9_create(Int32(info.width), Int32(info.height), info.fps, 30,
                                  Int32(max(2, ProcessInfo.processInfo.activeProcessorCount)), info.bt709 ? 1 : 0, info.fullRange ? 1 : 0)
            guard video != nil else { throw ConversionError.encoderFailed }
        }
        defer { if let video { wa_vp9_destroy(video) } }
        var preSkip: Int32 = 0
        var audio: OpaquePointer?
        if audioOutput != nil {
            audio = wa_opus_create(Int32(channels), channels == 1 ? 64000 : 128_000, &preSkip)
            guard audio != nil else { throw ConversionError.encoderFailed }
        }
        defer { if let audio { wa_opus_destroy(audio) } }

        let writer = try WebMWriter(
            url: destination,
            video: video == nil ? nil : WebMWriter.Video(width: videoInfo!.width, height: videoInfo!.height),
            audio: audio == nil ? nil : WebMWriter.Audio(channels: channels, preSkip: Int(preSkip))
        )

        var pictures = PictureEncoder(encoder: video, writer: writer)
        var sound = SoundEncoder(encoder: audio, writer: writer, channels: channels)
        var videoDone = videoOutput == nil
        var audioDone = audioOutput == nil
        let length = max((duration.seconds.isFinite ? duration.seconds : 0) * 1000, 1)
        var told = -1.0
        // Read the two tracks side by side, as AVAssetReader wants: sound up to the picture's time.
        while !videoDone || !audioDone {
            try Task.checkCancellation()
            try autoreleasepool {
                if !videoDone {
                    if let sample = videoOutput!.copyNextSampleBuffer() {
                        try pictures.add(sample)
                    } else {
                        videoDone = true
                    }
                }
                while !audioDone && (videoDone || sound.time <= pictures.time) {
                    if let sample = audioOutput!.copyNextSampleBuffer() {
                        try sound.add(sample)
                    } else {
                        audioDone = true
                    }
                }
            }
            let share = min(1, Double(max(pictures.time, sound.time)) / length)
            if share - told >= 0.01 {
                told = share
                progress(share)
            }
        }
        if reader.status == .failed {
            throw ConversionError.unreadable
        }
        try pictures.finish()
        try sound.finish()
        try writer.finish(duration: Int64((duration.seconds.isFinite ? duration.seconds : 0) * 1000))
    }

    private static func channelCount(of track: AVAssetTrack) async -> Int {
        guard let descriptions = try? await track.load(.formatDescriptions), let description = descriptions.first,
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description)
        else { return 2 }
        return Int(basic.pointee.mChannelsPerFrame)
    }

    static func fourCC(_ text: String) -> FourCharCode {
        text.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }
}

// MARK: - Encoding

/// Hands the pictures of the video to the VP9 encoder and its packets to the file.
private struct PictureEncoder {
    let encoder: OpaquePointer?
    let writer: WebMWriter
    /// The time of the last picture read, in ms.
    private(set) var time: Int64 = 0
    private var start: CMTime?
    private var pending: (buffer: CVPixelBuffer, time: Int64)?
    private var u: [UInt8] = []
    private var v: [UInt8] = []
    private var count = 0

    init(encoder: OpaquePointer?, writer: WebMWriter) {
        self.encoder = encoder
        self.writer = writer
    }

    mutating func add(_ sample: CMSampleBuffer) throws {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
        let presented = CMSampleBufferGetPresentationTimeStamp(sample)
        if start == nil { start = presented }
        let at = Int64(((presented - start!).seconds * 1000).rounded())
        time = at
        // Each picture lasts until the next one; the last, as long as the one before it.
        if let pending {
            try encode(pending.buffer, time: pending.time, duration: max(1, at - pending.time))
        }
        pending = (buffer, at)
    }

    mutating func finish() throws {
        guard let encoder else { return }
        if let pending {
            try encode(pending.buffer, time: pending.time, duration: 33)
            self.pending = nil
        }
        guard wa_vp9_finish(encoder) == 0 else { throw WebMediaConverter.ConversionError.encoderFailed }
        try drain()
    }

    private mutating func encode(_ buffer: CVPixelBuffer, time: Int64, duration: Int64) throws {
        guard let encoder else { return }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPlaneCount(buffer) == 2,
              let yPlane = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
              let uvPlane = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)
        else { throw WebMediaConverter.ConversionError.unreadable }
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        let chromaWidth = CVPixelBufferGetWidthOfPlane(buffer, 1)
        let chromaHeight = CVPixelBufferGetHeightOfPlane(buffer, 1)
        // The decoder gives U and V interleaved; VP9 wants them apart.
        let size = chromaWidth * chromaHeight
        if u.count != size {
            u = [UInt8](repeating: 0, count: size)
            v = [UInt8](repeating: 0, count: size)
        }
        let interleaved = uvPlane.assumingMemoryBound(to: UInt8.self)
        u.withUnsafeMutableBufferPointer { uOut in
            v.withUnsafeMutableBufferPointer { vOut in
                var uBuffer = vImage_Buffer(data: uOut.baseAddress, height: vImagePixelCount(chromaHeight),
                                            width: vImagePixelCount(chromaWidth), rowBytes: chromaWidth)
                var vBuffer = vImage_Buffer(data: vOut.baseAddress, height: vImagePixelCount(chromaHeight),
                                            width: vImagePixelCount(chromaWidth), rowBytes: chromaWidth)
                withUnsafeMutablePointer(to: &uBuffer) { uPointer in
                    withUnsafeMutablePointer(to: &vBuffer) { vPointer in
                        var destinations: [UnsafePointer<vImage_Buffer>?] = [UnsafePointer(uPointer), UnsafePointer(vPointer)]
                        var sources: [UnsafeRawPointer?] = [UnsafeRawPointer(interleaved), UnsafeRawPointer(interleaved + 1)]
                        _ = vImageConvert_ChunkyToPlanar8(&sources, &destinations, 2, 2, vImagePixelCount(chromaWidth),
                                                          vImagePixelCount(chromaHeight), uvStride, vImage_Flags(kvImageNoFlags))
                    }
                }
            }
        }
        let result = u.withUnsafeBufferPointer { uIn in
            v.withUnsafeBufferPointer { vIn in
                wa_vp9_encode(encoder, yPlane.assumingMemoryBound(to: UInt8.self), Int32(yStride),
                              uIn.baseAddress, Int32(chromaWidth), vIn.baseAddress, Int32(chromaWidth),
                              time, duration, count == 0 ? 1 : 0)
            }
        }
        count += 1
        guard result == 0 else { throw WebMediaConverter.ConversionError.encoderFailed }
        try drain()
    }

    private func drain() throws {
        guard let encoder else { return }
        var data: UnsafePointer<UInt8>?
        var size = 0
        var time: Int64 = 0
        var keyframe: Int32 = 0
        while wa_vp9_packet(encoder, &data, &size, &time, &keyframe) == 1, let data {
            try writer.addVideo(Data(bytes: data, count: size), time: time, keyframe: keyframe != 0)
        }
    }
}

/// Gathers the sound into 20 ms frames for the Opus encoder and hands its packets to the file.
private struct SoundEncoder {
    let encoder: OpaquePointer?
    let writer: WebMWriter
    let channels: Int
    private var samples: [Float] = []
    private var written: Int64 = 0  // frames of 960 samples written
    /// The time of the sound read so far, in ms.
    var time: Int64 { (written * 960 + Int64(samples.count / max(1, channels))) * 1000 / 48000 }
    private var output = [UInt8](repeating: 0, count: 4000)

    init(encoder: OpaquePointer?, writer: WebMWriter, channels: Int) {
        self.encoder = encoder
        self.writer = writer
        self.channels = channels
    }

    mutating func add(_ sample: CMSampleBuffer) throws {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return }
        let length = CMBlockBufferGetDataLength(block)
        var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
        chunk.withUnsafeMutableBytes { bytes in
            _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
        }
        samples += chunk
        try encodeWhole()
    }

    mutating func finish() throws {
        guard encoder != nil, !samples.isEmpty else { return }
        // The last frame is filled up with silence.
        let frame = 960 * channels
        samples += [Float](repeating: 0, count: (frame - samples.count % frame) % frame)
        try encodeWhole()
    }

    private mutating func encodeWhole() throws {
        guard let encoder else { return }
        let frame = 960 * channels
        var offset = 0
        while samples.count - offset >= frame {
            let bytes = samples.withUnsafeBufferPointer { input in
                output.withUnsafeMutableBufferPointer { out in
                    wa_opus_encode(encoder, input.baseAddress! + offset, out.baseAddress, Int32(out.count))
                }
            }
            guard bytes > 0 else { throw WebMediaConverter.ConversionError.encoderFailed }
            try writer.addAudio(Data(output[0..<Int(bytes)]), time: written * 960 * 1000 / 48000)
            written += 1
            offset += frame
        }
        if offset > 0 {
            samples.removeFirst(offset)
        }
    }
}

import Accelerate
import AVFoundation
import CoreVideo
import Foundation
import ImageIO
import Metal

/// The pictures, videos and sounds a page makes: `<img>`, `<video>`, `<audio>`, played by the
/// app. Each tells the page what happens to it through `event`.
final class MediaElement {
    enum Kind: String { case image, video, audio }
    let kind: Kind
    let handle: Int
    var event: (String) -> Void = { _ in }
    /// Where its relative addresses lead.
    let folder: URL
    /// Videos by the address the page gives them, as files AVFoundation plays.
    var videoFiles: [String: URL] = [:]

    // A picture
    private(set) var pixels: Data?
    private(set) var pictureSize = (0, 0)

    // A video or a sound
    private var player: AVPlayer?
    private var output: AVPlayerItemVideoOutput?
    private var observers: [NSObjectProtocol] = []
    private var statusObservation: NSKeyValueObservation?
    private var loop = false, muted = false, volume: Float = 1, rate: Float = 1, wantsPlay = false
    private var ready = false
    private var suspended = false
    private(set) var ended = false
    private var lastFrame: MTLTexture?
    /// The frame's buffer as Metal sees it, kept for as long as its texture is used.
    private var lastFrameBuffer: CVMetalTexture?

    init(kind: Kind, handle: Int, folder: URL) {
        self.kind = kind
        self.handle = handle
        self.folder = folder
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        player?.pause()
    }

    private func url(of source: String) -> URL {
        if let url = URL(string: source), url.scheme != nil { return url }
        let path = source.removingPercentEncoding ?? source
        if let file = videoFiles[path] { return file }
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : folder.appendingPathComponent(path)
    }

    // MARK: Values

    func set(_ name: String, _ value: Any?) {
        switch name {
        case "src": load(value as? String ?? "")
        case "loop": loop = (value as? NSNumber)?.boolValue ?? false
        case "muted": muted = (value as? NSNumber)?.boolValue ?? false; player?.isMuted = muted || kind == .video
        case "volume": volume = Float((value as? NSNumber)?.doubleValue ?? 1); player?.volume = volume
        case "playbackRate":
            rate = Float((value as? NSNumber)?.doubleValue ?? 1)
            if player?.rate ?? 0 > 0 { player?.rate = rate }
        case "currentTime":
            let seconds = (value as? NSNumber)?.doubleValue ?? 0
            player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            ended = false
        default: break
        }
    }

    func get(_ name: String) -> Any {
        switch name {
        case "naturalWidth", "width", "videoWidth":
            if kind == .image { return pictureSize.0 }
            return Int(player?.currentItem?.presentationSize.width ?? 0)
        case "naturalHeight", "height", "videoHeight":
            if kind == .image { return pictureSize.1 }
            return Int(player?.currentItem?.presentationSize.height ?? 0)
        case "complete": return pixels != nil
        case "currentTime": return player.map { CMTimeGetSeconds($0.currentTime()) } ?? 0
        case "duration":
            let duration = player?.currentItem.map { CMTimeGetSeconds($0.duration) } ?? 0
            return duration.isFinite ? duration : 0
        case "paused": return (player?.rate ?? 0) == 0
        case "ended": return ended
        case "readyState": return ready ? 4 : 0
        default: return NSNull()
        }
    }

    func call(_ name: String) {
        switch name {
        case "play":
            wantsPlay = true
            ended = false
            if !suspended { player?.rate = rate }
        case "pause":
            wantsPlay = false
            player?.pause()
        // The wallpaper pauses and plays again: what the scene plays stands still meanwhile.
        case "suspend":
            suspended = true
            player?.pause()
        case "resume":
            suspended = false
            if wantsPlay, ready, !ended { player?.rate = rate }
        case "remove":
            wantsPlay = false
            player?.pause()
            player = nil
        default: break
        }
    }

    // MARK: Loading

    private func load(_ source: String) {
        guard !source.isEmpty else { return }
        let address = url(of: source)
        switch kind {
        case .image:
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let decoded = Self.decode(address)
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let decoded {
                        self.pixels = decoded.pixels
                        self.pictureSize = (decoded.width, decoded.height)
                        self.event("load")
                    } else {
                        self.event("error")
                    }
                }
            }
        case .video, .audio:
            let item = AVPlayerItem(url: address)
            if kind == .video {
                let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                                 kCVPixelBufferMetalCompatibilityKey as String: true]
                let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
                item.add(output)
                self.output = output
            }
            let player = AVPlayer(playerItem: item)
            player.isMuted = muted || kind == .video
            player.volume = volume
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.allowsExternalPlayback = false
            self.player = player
            statusObservation = item.observe(\.status) { [weak self] item, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if item.status == .readyToPlay, !self.ready {
                        self.ready = true
                        self.event("loadedmetadata")
                        self.event("loadeddata")
                        self.event("canplay")
                        if self.wantsPlay, !self.suspended { player.rate = self.rate }
                    } else if item.status == .failed {
                        self.event("error")
                    }
                }
            }
            observers.append(NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                guard let self else { return }
                if self.loop {
                    player.seek(to: .zero)
                    if !self.suspended { player.rate = self.rate }
                } else {
                    self.ended = true
                    self.event("ended")
                }
            })
            if wantsPlay, !suspended { player.rate = rate }
        }
    }

    /// RGBA, top row first, colors not multiplied by alpha: as WebGL takes a page's picture.
    static func decode(_ url: URL) -> (pixels: Data, width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let width = image.width, height = image.height
        var data = Data(count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var buffer = vImage_Buffer(data: raw.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 4)
            vImageUnpremultiplyData_RGBA8888(&buffer, &buffer, vImage_Flags(kvImageNoFlags))
            return true
        }
        return drawn ? (data, width, height) : nil
    }

    /// The video's frame for now, on the graphics chip: the newest one, or the one before.
    func frame(cache: CVMetalTextureCache) -> MTLTexture? {
        guard let output, let player else { return lastFrame }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        let at = CMTimeCompare(time, .zero) > 0 ? time : player.currentTime()
        guard output.hasNewPixelBuffer(forItemTime: at), let buffer = output.copyPixelBuffer(forItemTime: at, itemTimeForDisplay: nil) else {
            return lastFrame
        }
        var texture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .bgra8Unorm, CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &texture)
        lastFrameBuffer = texture
        lastFrame = texture.flatMap(CVMetalTextureGetTexture)
        return lastFrame
    }
}

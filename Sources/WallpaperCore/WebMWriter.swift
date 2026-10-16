import Foundation

/// Writes a WebM file: VP9 pictures and Opus sound, as the encoders hand them over, in the
/// Matroska layout Chromium reads — a header, the tracks, clusters of blocks, and an index of
/// where each cluster starts so that a video can be sought and looped.
///
/// Times are in milliseconds. Blocks may come in any order across the two tracks; they are put
/// in order of time when written.
public final class WebMWriter {
    public struct Video {
        public var width: Int
        public var height: Int
        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    public struct Audio {
        public var channels: Int
        /// Samples a player leaves out at the start (the encoder's delay), at 48 kHz.
        public var preSkip: Int
        public init(channels: Int, preSkip: Int) {
            self.channels = channels
            self.preSkip = preSkip
        }
    }

    private struct Block {
        var track: Int
        var time: Int64
        var keyframe: Bool
        var data: Data
    }

    private let handle: FileHandle
    private let video: Video?
    private let audio: Audio?
    private var blocks: [Block] = []
    private var cues: [(time: Int64, position: UInt64)] = []
    private var lastTime: Int64 = 0
    private var segmentStart: UInt64 = 0
    private var seekHeadPosition: UInt64 = 0
    private var durationPosition: UInt64 = 0
    private var infoPosition: UInt64 = 0
    private var tracksPosition: UInt64 = 0
    private static let seekHeadRoom = 96

    private var videoTrack: Int { 1 }
    private var audioTrack: Int { video == nil ? 1 : 2 }

    public init(url: URL, video: Video?, audio: Audio?) throws {
        precondition(video != nil || audio != nil)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        self.video = video
        self.audio = audio
        try writeStart()
    }

    deinit {
        try? handle.close()
    }

    public func addVideo(_ data: Data, time: Int64, keyframe: Bool) throws {
        blocks.append(Block(track: videoTrack, time: time, keyframe: keyframe, data: data))
        try writeSettled()
    }

    public func addAudio(_ data: Data, time: Int64) throws {
        blocks.append(Block(track: audioTrack, time: time, keyframe: true, data: data))
        try writeSettled()
    }

    /// Writes what is left and the index, and closes the file. `duration` is the length in ms.
    public func finish(duration: Int64) throws {
        try writeClusters(upTo: .max)
        let cuesPosition = try handle.offset()
        var cuePoints = Data()
        for cue in cues {
            let positions = EBML.element(0xB7, EBML.uint(0xF7, UInt64(videoTrack)) + EBML.uint(0xF1, cue.position - segmentStart))
            cuePoints += EBML.element(0xBB, EBML.uint(0xB3, UInt64(max(0, cue.time))) + positions)
        }
        if !cues.isEmpty {
            try handle.write(contentsOf: EBML.element(0x1C53_BB6B, cuePoints))
        }
        let end = try handle.offset()

        // The segment's size, the length, and where the parts of the file are.
        try handle.seek(toOffset: segmentStart - 8)
        try handle.write(contentsOf: EBML.size(end - segmentStart, width: 8))
        try handle.seek(toOffset: durationPosition)
        try handle.write(contentsOf: EBML.float(0x4489, Double(max(duration, lastTime))))
        var seeks = Data()
        func seek(_ id: UInt32, _ position: UInt64) {
            seeks += EBML.element(0x4DBB, EBML.element(0x53AB, EBML.id(id)) + EBML.uint(0x53AC, position - segmentStart))
        }
        seek(0x1549_A966, infoPosition)
        seek(0x1654_AE6B, tracksPosition)
        if !cues.isEmpty { seek(0x1C53_BB6B, cuesPosition) }
        var seekHead = EBML.element(0x114D_9B74, seeks)
        let room = Self.seekHeadRoom
        precondition(seekHead.count <= room - 2)
        // The rest of the room stays a void element.
        seekHead += EBML.void(room - seekHead.count)
        try handle.seek(toOffset: seekHeadPosition)
        try handle.write(contentsOf: seekHead)
        try handle.close()
    }

    // MARK: - Writing

    private func writeStart() throws {
        let header = EBML.uint(0x4286, 1) + EBML.uint(0x42F7, 1) + EBML.uint(0x42F2, 4) + EBML.uint(0x42F3, 8)
            + EBML.string(0x4282, "webm") + EBML.uint(0x4287, 4) + EBML.uint(0x4285, 2)
        try handle.write(contentsOf: EBML.element(0x1A45_DFA3, header))
        // The segment, its size written at the end.
        try handle.write(contentsOf: EBML.id(0x1853_8067) + EBML.size(0, width: 8))
        segmentStart = try handle.offset()
        seekHeadPosition = segmentStart
        try handle.write(contentsOf: EBML.void(Self.seekHeadRoom))

        infoPosition = try handle.offset()
        let fixed = EBML.uint(0x2AD7B1, 1_000_000) + EBML.string(0x4D80, "WallAero Engine") + EBML.string(0x5741, "WallAero Engine")
        let durationPlaceholder = EBML.float(0x4489, 0)
        let info = EBML.element(0x1549_A966, fixed + durationPlaceholder)
        try handle.write(contentsOf: info)
        durationPosition = infoPosition + UInt64(info.count - durationPlaceholder.count)

        tracksPosition = try handle.offset()
        var tracks = Data()
        if let video {
            let picture = EBML.uint(0xB0, UInt64(video.width)) + EBML.uint(0xBA, UInt64(video.height))
            tracks += EBML.element(0xAE, EBML.uint(0xD7, UInt64(videoTrack)) + EBML.uint(0x73C5, UInt64(videoTrack))
                + EBML.uint(0x83, 1) + EBML.string(0x86, "V_VP9") + EBML.uint(0x9C, 0) + EBML.element(0xE0, picture))
        }
        if let audio {
            var head = Data("OpusHead".utf8)
            head.append(1)
            head.append(UInt8(audio.channels))
            head.append(contentsOf: withUnsafeBytes(of: UInt16(audio.preSkip).littleEndian, Array.init))
            head.append(contentsOf: withUnsafeBytes(of: UInt32(48000).littleEndian, Array.init))
            head.append(contentsOf: [0, 0, 0])
            let sound = EBML.float(0xB5, 48000) + EBML.uint(0x9F, UInt64(audio.channels))
            tracks += EBML.element(0xAE, EBML.uint(0xD7, UInt64(audioTrack)) + EBML.uint(0x73C5, UInt64(audioTrack))
                + EBML.uint(0x83, 2) + EBML.string(0x86, "A_OPUS") + EBML.binary(0x63A2, head)
                + EBML.uint(0x56AA, UInt64(audio.preSkip) * 1_000_000_000 / 48000) + EBML.uint(0x56BB, 80_000_000)
                + EBML.element(0xE1, sound))
        }
        try handle.write(contentsOf: EBML.element(0x1654_AE6B, tracks))
    }

    /// Blocks are held back a little, since the other track's may still come with earlier times.
    private func writeSettled() throws {
        guard blocks.count > 64 else { return }
        let sorted = blocks.map(\.time).sorted()
        try writeClusters(upTo: sorted[sorted.count - 32])
    }

    private var clusterTime: Int64?
    private var cluster = Data()

    private func writeClusters(upTo limit: Int64) throws {
        blocks.sort { $0.time == $1.time ? $0.track < $1.track : $0.time < $1.time }
        var written = 0
        for block in blocks where block.time < limit || limit == .max {
            // A new cluster at each picture that needs no other, and at least every five seconds;
            // a block's time is kept as a short distance from its cluster's.
            let startsCluster = clusterTime == nil
                || (block.track == videoTrack && video != nil && block.keyframe)
                || block.time - clusterTime! > 5000
                || block.time - clusterTime! > Int64(Int16.max)
            if startsCluster {
                try flushCluster()
                clusterTime = block.time
                if video == nil || (block.track == videoTrack && block.keyframe) {
                    cues.append((block.time, try handle.offset()))
                }
            }
            var simple = EBML.vint(UInt64(block.track))
            simple.append(contentsOf: withUnsafeBytes(of: Int16(block.time - clusterTime!).bigEndian, Array.init))
            simple.append(block.keyframe ? 0x80 : 0x00)
            simple += block.data
            cluster += EBML.binary(0xA3, simple)
            lastTime = max(lastTime, block.time)
            written += 1
        }
        blocks.removeFirst(written)
        if limit == .max {
            try flushCluster()
        }
    }

    private func flushCluster() throws {
        guard let clusterTime, !cluster.isEmpty else { return }
        try handle.write(contentsOf: EBML.element(0x1F43_B675, EBML.uint(0xE7, UInt64(max(0, clusterTime))) + cluster))
        cluster = Data()
    }
}

/// The few parts of EBML, Matroska's way of writing elements, that a WebM file needs.
enum EBML {
    static func id(_ id: UInt32) -> Data {
        var bytes = withUnsafeBytes(of: id.bigEndian, Array.init)
        while bytes.first == 0 { bytes.removeFirst() }
        return Data(bytes)
    }

    /// A size in the shortest form, or in `width` bytes.
    static func size(_ value: UInt64, width: Int? = nil) -> Data {
        var length = width ?? 1
        if width == nil {
            while length < 8, value >= (UInt64(1) << (7 * UInt64(length))) - 1 { length += 1 }
        }
        var bytes = [UInt8](repeating: 0, count: length)
        var rest = value
        for index in stride(from: length - 1, through: 0, by: -1) {
            bytes[index] = UInt8(rest & 0xFF)
            rest >>= 8
        }
        bytes[0] |= UInt8(0x80 >> (length - 1))
        return Data(bytes)
    }

    static func vint(_ value: UInt64) -> Data { size(value) }

    static func element(_ identifier: UInt32, _ payload: Data) -> Data {
        id(identifier) + size(UInt64(payload.count)) + payload
    }

    static func uint(_ identifier: UInt32, _ value: UInt64) -> Data {
        var bytes = withUnsafeBytes(of: value.bigEndian, Array.init)
        while bytes.count > 1, bytes.first == 0 { bytes.removeFirst() }
        return element(identifier, Data(bytes))
    }

    static func float(_ identifier: UInt32, _ value: Double) -> Data {
        element(identifier, Data(withUnsafeBytes(of: value.bitPattern.bigEndian, Array.init)))
    }

    static func string(_ identifier: UInt32, _ value: String) -> Data {
        element(identifier, Data(value.utf8))
    }

    static func binary(_ identifier: UInt32, _ value: Data) -> Data {
        element(identifier, value)
    }

    /// A void element of exactly `count` bytes (at least 2).
    static func void(_ count: Int) -> Data {
        // One byte of id, the size in 1 or 8 bytes, the rest zeros.
        if count - 2 < 127 {
            return Data([0xEC]) + size(UInt64(count - 2), width: 1) + Data(count: count - 2)
        }
        return Data([0xEC]) + size(UInt64(count - 9), width: 8) + Data(count: count - 9)
    }
}

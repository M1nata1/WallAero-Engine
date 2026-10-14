import Foundation

/// A picture of a Wallpaper Engine scene that bends: a "puppet", kept in a `.mdl` file next to
/// the picture's model. It is the picture cut into triangles, bones that the corners of the
/// triangles hang on, and animations — where every bone is, frame by frame.
///
/// The file is read here and handed to the page as numbers; the page moves the bones and draws
/// the triangles. Like everything in a scene's package it comes from the web: every length the
/// file states is checked against the file before it is believed.
///
///     MDLVnnnn  three numbers, the material's name, then — after a few numbers that differ
///               from one version of the format to the next —
///               the corners: place (3), in later versions the way the corner faces (3) and
///               lies (4), bones (4), their weights (4), place in the picture (2),
///               the triangles: three corners each
///               then, in later versions, the parts: which triangles belong together, in
///               the order they are drawn, and which parts show only where others are —
///               an iris only within the white of its eye — with a picture saying where
///               those others count
///     MDLSnnnn  the bones: parent and where the bone is from it, as a matrix
///     MDATnnnn  in some files, points other objects of the scene may hang on — a head, a
///               hand: the bone, a name, and where the point is from the bone, as a matrix
///     MDLAnnnn  the animations: name, how it repeats, frames a second, and for every bone
///               its place, turn and scale in every frame
///
/// The versions differ in what lies between these parts, so the parts are found by their
/// marks and by what must hold of them rather than by counting bytes from the start. A file
/// may also end after its triangles: a picture cut to its shape that nothing bends. Its
/// corners then say nothing of bones.
struct WallpaperEnginePuppet {
    struct Bone: Equatable {
        /// The bone this one hangs on; −1 for one that hangs on nothing.
        var parent: Int
        /// Where it is from its parent, at rest: a matrix of four by four, column by column.
        var matrix: [Float]
    }

    /// A point of the picture another object of the scene may hang on, to go where the point
    /// goes as the bones move: a hat on a head, say.
    struct Attachment: Equatable {
        var name: String
        var bone: Int
        /// Where it is from the bone: a matrix of four by four, column by column.
        var matrix: [Float]
    }

    /// Triangles drawn together: where their corners stand in `triangles`, three to a triangle.
    struct Part: Equatable {
        var start: Int
        var count: Int
    }

    /// A part that shows only where other parts are, as they are bent at the moment: an iris
    /// only within the white of its eye, which a closing lid flattens. Where the others count
    /// is said by a picture of the same layout as the puppet's own.
    struct Clip: Equatable {
        /// The part clipped and those it is clipped by, by their places in `parts`.
        var part: Int
        var masks: [Int]
        var texture: String
    }

    struct Animation {
        var id: Int
        var name: String
        /// "loop", "mirror" or "single".
        var mode: String
        var framesPerSecond: Double
        /// Frames from its start to its end; there is one more frame than that.
        var length: Int
        var frameCount: Int
        /// For every bone, for every frame: place (3), turn (3), scale (3).
        var frames: [Float]
    }

    /// For every corner: x, y, its place in the picture (2), four bones, their four weights.
    var corners: [Float]
    var triangles: [UInt16]
    var bones: [Bone]
    /// In the order they are drawn; empty when the file does not say, and the triangles are
    /// drawn as they come.
    var parts: [Part]
    var clips: [Clip]
    var attachments: [Attachment]
    var animations: [Animation]

    static let floatsPerCorner = 12
    /// How long a corner may be: with its place alone, or also with the way it faces, the way
    /// it lies, or both. Its bones, their weights and its place in the picture are always
    /// its last forty bytes; in a file without bones only the place in the picture ends it.
    private static let cornerSizes = [52, 64, 68, 80]
    private static let bonesAndWeights = 32
    private static let frameSize = 36

    init?(data: Data) {
        var reader = BinaryReader(data)
        guard reader.textToZero()?.hasPrefix("MDLV") == true,
              reader.uint32() != nil, reader.uint32() != nil, reader.uint32() != nil,
              reader.textToZero(atMost: 1024) != nil
        else {
            return nil
        }
        guard let bonesAt = Self.place(of: "MDLS", in: data, from: reader.offset) else {
            // No bones: the picture hangs whole on one that stays where it is.
            guard let mesh = Self.mesh(in: data, from: reader.offset, before: data.count, onBones: false) else { return nil }
            corners = mesh.corners
            triangles = mesh.triangles
            bones = [Bone(parent: -1, matrix: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])]
            (parts, clips) = Self.layout(in: data, from: mesh.end, before: data.count, indexCount: mesh.triangles.count)
            attachments = []
            animations = []
            return
        }
        guard let mesh = Self.mesh(in: data, from: reader.offset, before: bonesAt, onBones: true) else { return nil }
        let cornerCount = mesh.corners.count / Self.floatsPerCorner

        // The bones.
        guard reader.seek(to: bonesAt), reader.textToZero()?.hasPrefix("MDLS") == true, reader.uint32() != nil,
              let boneCount = reader.uint16(), boneCount > 0, boneCount <= 1024, reader.uint16() != nil
        else {
            return nil
        }
        var bones: [Bone] = []
        for _ in 0..<boneCount {
            guard reader.textToZero(atMost: 1024) != nil, reader.int32() != nil,
                  let parent = reader.int32(), parent >= -1, parent < Int(boneCount),
                  let matrixSize = reader.uint32(), matrixSize == 64
            else {
                return nil
            }
            var matrix: [Float] = []
            for _ in 0..<16 {
                guard let value = reader.float32(), value.isFinite else { return nil }
                matrix.append(value)
            }
            // What makes the bone sway by itself, as a text; not played.
            guard reader.textToZero(atMost: 65536) != nil else { return nil }
            bones.append(Bone(parent: parent, matrix: matrix))
        }
        // A corner hangs on bones the puppet has.
        for corner in 0..<cornerCount {
            for slot in 4..<8 where mesh.corners[corner * Self.floatsPerCorner + slot] >= Float(boneCount) {
                return nil
            }
        }

        corners = mesh.corners
        triangles = mesh.triangles
        self.bones = bones
        (parts, clips) = Self.layout(in: data, from: mesh.end, before: bonesAt, indexCount: mesh.triangles.count)
        attachments = Self.attachments(in: data, from: reader.offset, boneCount: Int(boneCount))
        animations = Self.animations(in: data, from: reader.offset, boneCount: Int(boneCount))
    }

    /// The parts after the triangles, in later versions: a flag and, if it is set, blocks this
    /// does not use (the corners' places once more, so many blocks of so many bytes each); a
    /// flag and, if it is set, the parts —
    /// sixteen bytes each: a number, nought, where its corners start and how many there are —
    /// and then the clipped parts: two numbers, the picture, two numbers, the part, how many
    /// parts clip it and which. What does not read whole is left out: the puppet is drawn
    /// as its triangles come, unclipped.
    private static func layout(in data: Data, from start: Int, before end: Int, indexCount: Int) -> (parts: [Part], clips: [Clip]) {
        var reader = BinaryReader(data)
        guard start < end, reader.seek(to: start), let skipped = reader.bytes(1) else { return ([], []) }
        if skipped.first == 1 {
            guard let blocks = reader.uint32(), blocks <= 1024 else { return ([], []) }
            for _ in 0..<blocks {
                guard let length = reader.uint32(), reader.offset + Int(length) <= end, reader.skip(Int(length)) else { return ([], []) }
            }
        } else if skipped.first != 0 {
            return ([], [])
        }
        guard reader.offset < end, let flag = reader.bytes(1), flag.first == 1, let length = reader.uint32(),
              length % 16 == 0, reader.offset + Int(length) <= end
        else {
            return ([], [])
        }
        var parts: [Part] = []
        for _ in 0..<(Int(length) / 16) {
            guard reader.uint32() != nil, reader.uint32() != nil, let from = reader.uint32(), let count = reader.uint32(),
                  from % 3 == 0, count % 3 == 0, Int(from) + Int(count) <= indexCount
            else {
                return ([], [])
            }
            parts.append(Part(start: Int(from), count: Int(count)))
        }
        var clips: [Clip] = []
        if reader.offset + 4 <= end, let count = reader.uint32(), count <= 1024 {
            for _ in 0..<count {
                guard reader.offset < end, reader.uint32() != nil, reader.uint32() != nil,
                      let texture = reader.textToZero(atMost: 1024), reader.uint32() != nil, reader.uint32() != nil,
                      let part = reader.uint32(), Int(part) < parts.count, let maskCount = reader.uint32(), maskCount <= 1024
                else {
                    return (parts, [])
                }
                var masks: [Int] = []
                for _ in 0..<maskCount {
                    guard let mask = reader.uint32(), Int(mask) < parts.count else { return (parts, []) }
                    masks.append(Int(mask))
                }
                guard reader.offset <= end else { return (parts, []) }
                clips.append(Clip(part: Int(part), masks: masks, texture: texture))
            }
        }
        return (parts, clips)
    }

    /// The points to hang other objects on, if the file has them, before its animations. A
    /// part that does not read whole is left out: the puppet is the same without it.
    private static func attachments(in data: Data, from start: Int, boneCount: Int) -> [Attachment] {
        guard let mark = place(of: "MDAT", in: data, from: start) else { return [] }
        if let animationsAt = place(of: "MDLA", in: data, from: start), animationsAt < mark { return [] }
        var reader = BinaryReader(data)
        guard reader.seek(to: mark), reader.textToZero()?.hasPrefix("MDAT") == true, reader.uint32() != nil,
              let count = reader.uint16(), count <= 1024
        else {
            return []
        }
        var attachments: [Attachment] = []
        for _ in 0..<count {
            guard let bone = reader.uint16(), Int(bone) < boneCount, let name = reader.textToZero(atMost: 1024) else { return [] }
            var matrix: [Float] = []
            for _ in 0..<16 {
                guard let value = reader.float32(), value.isFinite else { return [] }
                matrix.append(value)
            }
            attachments.append(Attachment(name: name, bone: Int(bone), matrix: matrix))
        }
        return attachments
    }

    /// Where a mark of the file stands, looking from a place on.
    private static func place(of mark: String, in data: Data, from start: Int) -> Int? {
        guard start >= 0, start < data.count,
              let found = data.range(of: Data(mark.utf8), in: (data.startIndex + start)..<data.endIndex)
        else {
            return nil
        }
        return found.lowerBound - data.startIndex
    }

    private static func number(in data: Data, at place: Int) -> Int? {
        guard place >= 0, place + 4 <= data.count else { return nil }
        let from = data.startIndex + place
        return (0..<4).reduce(0) { $0 | Int(data[from + $1]) << (8 * $1) }
    }

    /// The corners and the triangles. What lies between the material's name and them differs
    /// from version to version, and so does how long a corner is. They are where a length
    /// stands that is so many whole corners, followed by a length that is so many whole
    /// triangles of those very corners, all of it before the bones — and where every corner
    /// then reads as one: on a few bones, by weights that are shares. Of the lengths a corner
    /// may have, the one by which the triangles use every corner is tried first.
    private static func mesh(in data: Data, from start: Int, before end: Int, onBones: Bool) -> (corners: [Float], triangles: [UInt16], end: Int)? {
        guard start >= 0, end <= data.count, start < end else { return nil }
        for place in start..<min(start + 512, end - 8) {
            guard let cornerBytes = number(in: data, at: place), cornerBytes > 0, cornerBytes <= 16 * 1024 * 1024,
                  place + 4 + cornerBytes + 4 <= end,
                  let triangleBytes = number(in: data, at: place + 4 + cornerBytes), triangleBytes > 0, triangleBytes % 6 == 0,
                  place + 4 + cornerBytes + 4 + triangleBytes <= end
            else {
                continue
            }
            let trianglesAt = data.startIndex + place + 4 + cornerBytes + 4
            let triangles = data.subdata(in: trianglesAt..<(trianglesAt + triangleBytes)).withUnsafeBytes { raw in
                (0..<(triangleBytes / 2)).map { UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 2, as: UInt16.self)) }
            }
            let packed = data.subdata(in: (data.startIndex + place + 4)..<(data.startIndex + place + 4 + cornerBytes))
            let last = Int(triangles.max() ?? 0)
            let sizes = cornerSizes.map { onBones ? $0 : $0 - bonesAndWeights }.filter { cornerBytes % $0 == 0 }
            for size in sizes.filter({ cornerBytes / $0 == last + 1 }) + sizes.filter({ cornerBytes / $0 != last + 1 }) {
                guard last < cornerBytes / size, let corners = corners(in: packed, each: size, onBones: onBones) else { continue }
                return (corners, triangles, place + 4 + cornerBytes + 4 + triangleBytes)
            }
        }
        return nil
    }

    /// The corners out of their bytes, if the bytes are corners of that length: nil if one of
    /// them hangs on what cannot be a bone or by what cannot be a weight. Corners that say
    /// nothing of bones all hang on the first one.
    private static func corners(in packed: Data, each size: Int, onBones: Bool) -> [Float]? {
        let count = packed.count / size
        var corners: [Float] = []
        corners.reserveCapacity(count * floatsPerCorner)
        let whole = packed.withUnsafeBytes { raw -> Bool in
            func float(_ at: Int) -> Float {
                Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt32.self)))
            }
            for corner in 0..<count {
                let base = corner * size
                // Its bones, their weights and its place in the picture end the corner.
                let x = float(base), y = float(base + 4)
                var hangsOn: [Float] = [0, 0, 0, 0]
                var weights: [Float] = [1, 0, 0, 0]
                if onBones {
                    let rest = base + size - 40
                    for slot in 0..<4 {
                        let bone = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: rest + slot * 4, as: UInt32.self))
                        let weight = float(rest + 16 + slot * 4)
                        guard bone < 1024, weight.isFinite, weight >= -0.001, weight <= 1.001 else { return false }
                        hangsOn[slot] = Float(bone)
                        weights[slot] = weight
                    }
                }
                let u = float(base + size - 8), v = float(base + size - 4)
                guard x.isFinite, y.isFinite, u.isFinite, v.isFinite, abs(x) < 1_000_000, abs(y) < 1_000_000,
                      abs(u) < 1024, abs(v) < 1024
                else {
                    return false
                }
                corners += [x, y, u, v] + hangsOn + weights
            }
            return true
        }
        return whole ? corners : nil
    }

    /// The animations that follow the bones: as many of them as can be read. Between the
    /// bones and the animations, and after each animation, lies what differs from version to
    /// version; an animation is known by how it begins, and looked for from where the one
    /// before it ended.
    private static func animations(in data: Data, from start: Int, boneCount: Int) -> [Animation] {
        guard let mark = place(of: "MDLA", in: data, from: start) else { return [] }
        var reader = BinaryReader(data)
        guard reader.seek(to: mark), reader.textToZero()?.hasPrefix("MDLA") == true, reader.uint32() != nil,
              let count = reader.uint32(), count <= 4096
        else {
            return []
        }
        var animations: [Animation] = []
        var place = reader.offset
        for _ in 0..<Int(count) {
            var found: (animation: Animation, end: Int)?
            for skipped in 0...512 {
                found = animation(in: data, at: place + skipped, boneCount: boneCount)
                if found != nil { break }
            }
            guard let found else { break }
            animations.append(found.animation)
            place = found.end
        }
        return animations
    }

    /// The animation that begins at a place of the file, and where it ends; nil if what is
    /// there is no animation.
    private static func animation(in data: Data, at place: Int, boneCount: Int) -> (animation: Animation, end: Int)? {
        var reader = BinaryReader(data)
        guard reader.seek(to: place),
              let id = reader.int32(), id >= 0, id < 100_000_000, reader.int32() != nil,
              let name = reader.textToZero(atMost: 1024), let mode = reader.textToZero(atMost: 16),
              ["loop", "single", "mirror"].contains(mode.lowercased()),
              let framesPerSecond = reader.float32(), framesPerSecond > 0, framesPerSecond <= 1000,
              let length = reader.int32(), length > 0, length <= 1_000_000, reader.int32() != nil,
              let animated = reader.uint32(), Int(animated) == boneCount
        else {
            return nil
        }
        var frames: [Float] = []
        var frameCount = 0
        for _ in 0..<boneCount {
            guard reader.int32() != nil, let size = reader.uint32().map(Int.init), size > 0, size % frameSize == 0,
                  frameCount == 0 || size / frameSize == frameCount, let packed = reader.bytes(size)
            else {
                return nil
            }
            frameCount = size / frameSize
            packed.withUnsafeBytes { raw in
                for at in 0..<(size / 4) {
                    frames.append(Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at * 4, as: UInt32.self))))
                }
            }
        }
        guard frames.allSatisfy(\.isFinite) else { return nil }
        return (Animation(id: id, name: name, mode: mode.lowercased(), framesPerSecond: Double(framesPerSecond),
                          length: length, frameCount: frameCount, frames: frames), reader.offset)
    }

    /// The puppet as the page takes it: the long lists of numbers as text (base64 of the
    /// numbers' bytes, four to a number, the low byte first), which a page reads back at once.
    var table: [String: Any] {
        func packed(_ numbers: [Float]) -> String {
            var data = Data(capacity: numbers.count * 4)
            for number in numbers {
                withUnsafeBytes(of: number.bitPattern.littleEndian) { data.append(contentsOf: $0) }
            }
            return data.base64EncodedString()
        }
        var triangleData = Data(capacity: triangles.count * 2)
        for corner in triangles {
            withUnsafeBytes(of: corner.littleEndian) { triangleData.append(contentsOf: $0) }
        }
        return [
            "corners": packed(corners),
            "triangles": triangleData.base64EncodedString(),
            "bones": bones.map { ["parent": $0.parent, "matrix": $0.matrix.map(Double.init)] as [String: Any] },
            "attachments": attachments.map { ["name": $0.name, "bone": $0.bone, "matrix": $0.matrix.map(Double.init)] as [String: Any] },
            "parts": parts.map { [$0.start, $0.count] },
            "clips": clips.map { ["part": $0.part, "masks": $0.masks, "texture": $0.texture] as [String: Any] },
            "animations": animations.map {
                ["id": $0.id, "name": $0.name, "mode": $0.mode, "fps": $0.framesPerSecond, "length": $0.length,
                 "frameCount": $0.frameCount, "frames": packed($0.frames)] as [String: Any]
            },
        ]
    }
}

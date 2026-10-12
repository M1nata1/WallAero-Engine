import Foundation

/// A picture of a Wallpaper Engine scene that bends: a "puppet", kept in a `.mdl` file next to
/// the picture's model. It is the picture cut into triangles, bones that the corners of the
/// triangles hang on, and animations — where every bone is, frame by frame.
///
/// The file is read here and handed to the page as numbers; the page moves the bones and draws
/// the triangles. Like everything in a scene's package it comes from the web: every length the
/// file states is checked against the file before it is believed.
///
///     MDLVnnnn  three numbers, the material's name, a number,
///               the corners: place (3), bones (4), their weights (4), place in the picture (2),
///               the triangles: three corners each
///     MDLSnnnn  the bones: parent and where the bone is from it, as a matrix
///     MDLAnnnn  the animations: name, how it repeats, frames a second, and for every bone
///               its place, turn and scale in every frame
struct WallpaperEnginePuppet {
    struct Bone: Equatable {
        /// The bone this one hangs on; −1 for one that hangs on nothing.
        var parent: Int
        /// Where it is from its parent, at rest: a matrix of four by four, column by column.
        var matrix: [Float]
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
    var animations: [Animation]

    static let floatsPerCorner = 12
    private static let cornerSize = 52
    private static let frameSize = 36

    init?(data: Data) {
        var reader = BinaryReader(data)
        guard reader.textToZero()?.hasPrefix("MDLV") == true,
              reader.uint32() != nil, reader.uint32() != nil, reader.uint32() != nil,
              reader.textToZero(atMost: 1024) != nil, reader.uint32() != nil,
              let cornerBytes = reader.uint32().map(Int.init), cornerBytes > 0, cornerBytes % Self.cornerSize == 0,
              cornerBytes <= 16 * 1024 * 1024, let packed = reader.bytes(cornerBytes)
        else {
            return nil
        }
        let cornerCount = cornerBytes / Self.cornerSize
        var corners: [Float] = []
        corners.reserveCapacity(cornerCount * Self.floatsPerCorner)
        var cornerReader = BinaryReader(packed)
        for _ in 0..<cornerCount {
            guard let x = cornerReader.float32(), let y = cornerReader.float32(), cornerReader.float32() != nil else { return nil }
            var hangsOn: [Float] = []
            for _ in 0..<4 {
                guard let bone = cornerReader.uint32() else { return nil }
                hangsOn.append(Float(bone))
            }
            var weights: [Float] = []
            for _ in 0..<4 {
                guard let weight = cornerReader.float32() else { return nil }
                weights.append(weight)
            }
            guard let u = cornerReader.float32(), let v = cornerReader.float32() else { return nil }
            corners += [x, y, u, v] + hangsOn + weights
        }
        guard corners.allSatisfy(\.isFinite),
              let triangleBytes = reader.uint32().map(Int.init), triangleBytes > 0, triangleBytes % 6 == 0,
              let packedTriangles = reader.bytes(triangleBytes)
        else {
            return nil
        }
        let triangles = packedTriangles.withUnsafeBytes { raw in
            (0..<(triangleBytes / 2)).map { UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 2, as: UInt16.self)) }
        }
        guard triangles.allSatisfy({ Int($0) < cornerCount }) else { return nil }

        // The bones.
        guard reader.textToZero()?.hasPrefix("MDLS") == true, reader.uint32() != nil,
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
            for slot in 4..<8 where corners[corner * Self.floatsPerCorner + slot] >= Float(boneCount) {
                return nil
            }
        }

        self.corners = corners
        self.triangles = triangles
        self.bones = bones
        animations = Self.animations(&reader, boneCount: Int(boneCount))
    }

    /// The animations that follow the bones: as many of them as can be read.
    private static func animations(_ reader: inout BinaryReader, boneCount: Int) -> [Animation] {
        guard reader.textToZero()?.hasPrefix("MDLA") == true, reader.uint32() != nil,
              let count = reader.uint32(), count <= 4096
        else {
            return []
        }
        var animations: [Animation] = []
        for index in 0..<Int(count) {
            // A number follows every animation but the last thing in the file is one too.
            if index > 0, reader.uint32() == nil { break }
            guard let id = reader.int32(), reader.int32() != nil,
                  let name = reader.textToZero(atMost: 1024), let mode = reader.textToZero(),
                  let framesPerSecond = reader.float32(), framesPerSecond > 0, framesPerSecond <= 1000,
                  let length = reader.int32(), length > 0, length <= 1_000_000, reader.int32() != nil,
                  let animated = reader.uint32(), Int(animated) == boneCount
            else {
                break
            }
            var frames: [Float] = []
            var frameCount = 0
            var whole = true
            for _ in 0..<boneCount {
                guard reader.int32() != nil, let size = reader.uint32().map(Int.init), size > 0, size % frameSize == 0,
                      frameCount == 0 || size / frameSize == frameCount, let packed = reader.bytes(size)
                else {
                    whole = false
                    break
                }
                frameCount = size / frameSize
                packed.withUnsafeBytes { raw in
                    for at in 0..<(size / 4) {
                        frames.append(Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at * 4, as: UInt32.self))))
                    }
                }
            }
            guard whole, frames.allSatisfy(\.isFinite) else { break }
            animations.append(Animation(id: id, name: name, mode: mode.lowercased(), framesPerSecond: Double(framesPerSecond),
                                        length: length, frameCount: frameCount, frames: frames))
        }
        return animations
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
            "animations": animations.map {
                ["id": $0.id, "name": $0.name, "mode": $0.mode, "fps": $0.framesPerSecond, "length": $0.length,
                 "frameCount": $0.frameCount, "frames": packed($0.frames)] as [String: Any]
            },
        ]
    }
}

import CoreGraphics
import Foundation

/// A picture bent by bones, as the editor makes one — Wallpaper Engine's "puppet warp": a mesh
/// laid over the opaque part of the picture, bones that hold it, how much each bone holds each
/// corner, and animations made of keys the bones are turned and moved to. It is written as the
/// `.mdl` file Wallpaper Engine reads (the layout of its version 13 files), and kept besides in
/// a file of the app's own, for its keys.
///
/// Places are in the picture's pixels from its middle, y up, as in Wallpaper Engine's files.
public struct WallpaperEnginePuppetRig: Codable, Equatable, Sendable {
    public struct Point: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    public struct Bone: Codable, Equatable, Sendable, Identifiable {
        public var id: Int { index }
        public var index: Int
        public var name: String
        public var parent: Int?
        /// Where the bone turns about, at rest.
        public var joint: Point
        /// How it sways by itself, if it does.
        public var sway: Sway?
        /// Where the bone ends, at rest; without one it reaches its first child.
        public var tail: Point?
        /// How it is turned from its parent at rest, in radians, where it is at all.
        public var restTurn: Double?
        /// What Wallpaper Engine wrote of how it sways, kept for all the app does not know of it.
        public var physics: String?

        public var restAngle: Double { restTurn ?? 0 }

        public init(index: Int, name: String, parent: Int?, joint: Point) {
            self.index = index
            self.name = name
            self.parent = parent
            self.joint = joint
        }
    }

    /// A bone that sways by itself: on a spring that brings it back, or hanging under gravity.
    public struct Sway: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, CaseIterable, Sendable { case spring, hanging }
        public var kind: Kind
        public var stiffness: Double = 200
        public var friction: Double = 20
        public var weight: Double = 30
        public init(kind: Kind) { self.kind = kind }
    }

    /// Where a bone is at a frame of an animation: turned and moved from where it is at rest.
    public struct Key: Codable, Equatable, Sendable {
        public var frame: Int
        /// In radians, counterclockwise.
        public var angle: Double
        public var dx: Double
        public var dy: Double
        /// Turned about the picture's horizontal axis and its vertical one, in radians: seen
        /// straight on, the bone's part is squeezed up and down, or from side to side — a lid
        /// closing over an eye — and past a quarter turn it is seen from behind.
        public var tiltX: Double = 0
        public var tiltY: Double = 0

        public init(frame: Int, angle: Double = 0, dx: Double = 0, dy: Double = 0, tiltX: Double = 0, tiltY: Double = 0) {
            self.frame = frame
            self.angle = angle
            self.dx = dx
            self.dy = dy
            self.tiltX = tiltX
            self.tiltY = tiltY
        }

        // Keys saved before there were tilts have none.
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            frame = try values.decode(Int.self, forKey: .frame)
            angle = try values.decode(Double.self, forKey: .angle)
            dx = try values.decode(Double.self, forKey: .dx)
            dy = try values.decode(Double.self, forKey: .dy)
            tiltX = try values.decodeIfPresent(Double.self, forKey: .tiltX) ?? 0
            tiltY = try values.decodeIfPresent(Double.self, forKey: .tiltY) ?? 0
        }

        /// How the bone's part is turned and squeezed as it is seen, before it is moved: the
        /// turn about x, then y, then in the picture's plane.
        var turn: CGAffineTransform {
            let cz = cos(angle), sz = sin(angle), cx = cos(tiltX), sx = sin(tiltX), cy = cos(tiltY), sy = sin(tiltY)
            return CGAffineTransform(a: cz * cy, b: sz * cy, c: cz * sy * sx - sz * cx, d: sz * sy * sx + cz * cx, tx: 0, ty: 0)
        }
    }

    /// How much a corner of the mesh is held by the bones that hold it.
    public struct Hold: Codable, Equatable, Sendable {
        public var bones: [Int]
        public var weights: [Double]
    }

    public struct Animation: Codable, Equatable, Sendable, Identifiable {
        public var id: Int
        public var name: String
        public var framesPerSecond: Double = 30
        /// The last frame; the animation has one more.
        public var length: Int = 60
        /// "loop", "mirror" or "single".
        public var mode: String = "loop"
        /// The keys of each bone, by the bone's index, in the order of their frames.
        public var keys: [Int: [Key]] = [:]

        public init(id: Int, name: String) {
            self.id = id
            self.name = name
        }
    }

    public var width: Double
    public var height: Double
    public var points: [Point] = []
    public var triangles: [Int] = []
    public var bones: [Bone] = []
    public var animations: [Animation] = []
    /// How much the bones hold each corner, as painted or as a file has it; nil is worked out
    /// from how near the bones are.
    public var holds: [Hold]?

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    // MARK: - The mesh

    /// Lays a mesh of squares `spacing` pixels wide over the part of the picture that is not
    /// see-through, each square two triangles.
    public mutating func makeMesh(from image: CGImage, spacing: Double) {
        let step = max(4, spacing)
        let columns = max(1, Int((width / step).rounded(.up)))
        let rows = max(1, Int((height / step).rounded(.up)))
        let opaque = Self.opaqueCells(of: image, columns: columns, rows: rows)
        var index: [Int: Int] = [:]
        var points: [Point] = []
        func corner(_ column: Int, _ row: Int) -> Int {
            let key = row * (columns + 1) + column
            if let existing = index[key] { return existing }
            let x = min(Double(column) * step, width) - width / 2
            let y = height / 2 - min(Double(row) * step, height)
            points.append(Point(x: x, y: y))
            index[key] = points.count - 1
            return points.count - 1
        }
        var triangles: [Int] = []
        for row in 0..<rows {
            for column in 0..<columns where opaque[row * columns + column] {
                let a = corner(column, row), b = corner(column + 1, row)
                let c = corner(column, row + 1), d = corner(column + 1, row + 1)
                triangles += [a, c, b, b, c, d]
            }
        }
        self.points = points
        self.triangles = triangles
        holds = nil
    }

    /// Takes corners out of the mesh with the triangles they stand in.
    public mutating func removePoints(_ gone: Set<Int>) {
        var renumbered: [Int: Int] = [:]
        var kept: [Point] = []
        var keptHolds: [Hold] = []
        for (index, point) in points.enumerated() where !gone.contains(index) {
            renumbered[index] = kept.count
            kept.append(point)
            if let holds, holds.indices.contains(index) { keptHolds.append(holds[index]) }
        }
        var left: [Int] = []
        for index in Swift.stride(from: 0, to: triangles.count - 2, by: 3) {
            if let a = renumbered[triangles[index]], let b = renumbered[triangles[index + 1]], let c = renumbered[triangles[index + 2]] {
                left += [a, b, c]
            }
        }
        points = kept
        triangles = left
        if holds != nil { holds = keptHolds.count == kept.count ? keptHolds : nil }
    }

    /// Which squares of a grid over the picture have something to show in them.
    static func opaqueCells(of image: CGImage, columns: Int, rows: Int) -> [Bool] {
        // The picture made small enough to look at every pixel: four a square each way.
        let sampleWidth = columns * 4, sampleHeight = rows * 4
        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        if let context = CGContext(data: &pixels, width: sampleWidth, height: sampleHeight, bitsPerComponent: 8, bytesPerRow: sampleWidth * 4,
                                   space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
        }
        var cells = [Bool](repeating: false, count: columns * rows)
        for y in 0..<sampleHeight {
            // The context's rows go up from the bottom; the grid's go down from the top.
            let row = (sampleHeight - 1 - y) / 4
            for x in 0..<sampleWidth where pixels[(y * sampleWidth + x) * 4 + 3] > 12 {
                cells[row * columns + x / 4] = true
            }
        }
        return cells
    }

    // MARK: - Bones

    @discardableResult
    public mutating func addBone(at joint: Point, parent: Int?) -> Int {
        let index = bones.count
        bones.append(Bone(index: index, name: String(format: NSLocalizedString("Bone %d", comment: "Name of a new bone"), index + 1),
                          parent: parent, joint: joint))
        return index
    }

    /// Takes a bone away; those that hung on it hang on its parent, and the keys go with it.
    public mutating func removeBone(_ index: Int) {
        guard bones.indices.contains(index) else { return }
        let parent = bones[index].parent
        var kept: [Bone] = []
        var renumbered: [Int: Int] = [:]
        for bone in bones where bone.index != index {
            renumbered[bone.index] = kept.count
            kept.append(bone)
        }
        for i in kept.indices {
            kept[i].index = i
            var newParent = kept[i].parent
            if newParent == index { newParent = parent }
            kept[i].parent = newParent.flatMap { renumbered[$0] }
        }
        bones = kept
        holds = holds?.map { hold in
            var bones: [Int] = [], weights: [Double] = []
            for (bone, weight) in zip(hold.bones, hold.weights) where bone != index && weight > 0 {
                bones.append(renumbered[bone] ?? 0)
                weights.append(weight)
            }
            let total = weights.reduce(0, +)
            guard total > 0 else { return Hold(bones: [0, 0, 0, 0], weights: [1, 0, 0, 0]) }
            weights = weights.map { $0 / total }
            while bones.count < 4 {
                bones.append(0)
                weights.append(0)
            }
            return Hold(bones: bones, weights: weights)
        }
        for a in animations.indices {
            var keys: [Int: [Key]] = [:]
            for (bone, list) in animations[a].keys {
                if let new = renumbered[bone] { keys[new] = list }
            }
            animations[a].keys = keys
        }
    }

    /// How far a bone reaches from its joint: to where it is said to end, else to its first child.
    func tip(of index: Int) -> Point? {
        let bone = bones[index]
        let end = bone.tail ?? bones.first { $0.parent == index }?.joint
        return end.map { Point(x: $0.x - bone.joint.x, y: $0.y - bone.joint.y) }
    }

    /// Where a bone ends at rest, to be drawn: one that says nothing goes on the way its parent does.
    public func restTail(of index: Int) -> Point {
        let bone = bones[index]
        if let tip = tip(of: index), hypot(tip.x, tip.y) > 0.001 {
            return Point(x: bone.joint.x + tip.x, y: bone.joint.y + tip.y)
        }
        let reach = max(16, min(width, height) / 12)
        var way = Point(x: 0, y: 1)
        if let parent = bone.parent, parent != index {
            let from = bones[parent].joint
            let length = hypot(bone.joint.x - from.x, bone.joint.y - from.y)
            if length > 0.001 { way = Point(x: (bone.joint.x - from.x) / length, y: (bone.joint.y - from.y) / length) }
        }
        return Point(x: bone.joint.x + way.x * reach, y: bone.joint.y + way.y * reach)
    }

    /// How a bone is turned at rest, from the picture.
    func restWorldAngle(of index: Int) -> Double {
        var total = 0.0
        var at: Int? = index
        var steps = 0
        while let current = at, bones.indices.contains(current), steps < 64 {
            total += bones[current].restAngle
            at = bones[current].parent
            steps += 1
        }
        return total
    }

    /// Where a bone is from its parent at rest, counted along its parent.
    func restPlace(of index: Int) -> Point {
        let bone = bones[index]
        guard let parent = bone.parent, bones.indices.contains(parent), parent != index else { return bone.joint }
        let x = bone.joint.x - bones[parent].joint.x, y = bone.joint.y - bones[parent].joint.y
        let turn = -restWorldAngle(of: parent)
        return Point(x: x * cos(turn) - y * sin(turn), y: x * sin(turn) + y * cos(turn))
    }

    /// Where a point of a bone's own is, from its joint, for one seen from the picture.
    public func alongBone(_ index: Int, _ point: Point) -> Point {
        let x = point.x - bones[index].joint.x, y = point.y - bones[index].joint.y
        let turn = -restWorldAngle(of: index)
        return Point(x: x * cos(turn) - y * sin(turn), y: x * sin(turn) + y * cos(turn))
    }

    /// How much each bone holds each corner: the four nearest bones, more the nearer, a bone
    /// counted as the line from its joint to its tip.
    public func weights() -> [(bones: [Int], weights: [Double])] {
        if let holds, holds.count == points.count, !bones.isEmpty { return holds.map { ($0.bones, $0.weights) } }
        return nearestWeights()
    }

    /// Paints how much a bone holds the corners within a radius of a point: towards `target`,
    /// by `strength` at the middle and less towards the edge. The others share what is left.
    public mutating func paintWeight(bone: Int, at center: Point, radius: Double, strength: Double, target: Double) {
        guard bones.indices.contains(bone), radius > 0 else { return }
        var painted = weights().map { Hold(bones: $0.bones, weights: $0.weights) }
        for index in points.indices {
            let distance = hypot(points[index].x - center.x, points[index].y - center.y)
            guard distance < radius else { continue }
            let share = 1 - distance / radius
            var hold = painted[index]
            var slot = hold.bones.indices.first { hold.bones[$0] == bone && hold.weights[$0] > 0 }
            if slot == nil {
                guard target > 0 else { continue }
                slot = hold.weights.indices.min { hold.weights[$0] < hold.weights[$1] }
                hold.bones[slot!] = bone
                hold.weights[slot!] = 0
            }
            guard let slot else { continue }
            let now = hold.weights[slot]
            let next = now + (target - now) * min(1, strength * share * share * (3 - 2 * share))
            let others = hold.weights.indices.filter { $0 != slot }.reduce(0) { $0 + hold.weights[$1] }
            // A corner is always held in whole: one nothing else holds stays with this bone.
            guard others > 1e-6 || next > 1e-6 else { continue }
            let room = 1 - next
            for other in hold.weights.indices where other != slot {
                hold.weights[other] = others > 1e-6 ? hold.weights[other] / others * room : 0
            }
            hold.weights[slot] = others > 1e-6 ? next : 1
            painted[index] = hold
        }
        holds = painted
    }

    /// How much a bone holds each corner.
    public func weights(of bone: Int) -> [Double] {
        weights().map { hold in
            zip(hold.bones, hold.weights).reduce(0) { $1.0 == bone ? $0 + $1.1 : $0 }
        }
    }

    private func nearestWeights() -> [(bones: [Int], weights: [Double])] {
        guard !bones.isEmpty else { return points.map { _ in ([0, 0, 0, 0], [1, 0, 0, 0]) } }
        let segments: [(Point, Point)] = bones.map { bone in
            let tip = tip(of: bone.index) ?? Point(x: 0, y: 0)
            return (bone.joint, Point(x: bone.joint.x + tip.x, y: bone.joint.y + tip.y))
        }
        return points.map { point in
            var near: [(Int, Double)] = segments.enumerated().map { index, segment in
                (index, max(Self.distance(point, segment.0, segment.1), 1))
            }
            near.sort { $0.1 < $1.1 }
            let chosen = Array(near.prefix(4))
            var weights = chosen.map { 1 / pow($0.1, 3) }
            let total = weights.reduce(0, +)
            weights = weights.map { $0 / total }
            var indices = chosen.map(\.0)
            while indices.count < 4 {
                indices.append(0)
                weights.append(0)
            }
            return (indices, weights)
        }
    }

    static func distance(_ p: Point, _ a: Point, _ b: Point) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = dx * dx + dy * dy
        let t = length > 0 ? min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / length, 0), 1) : 0
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    // MARK: - Animation

    /// Where a bone is at a frame: between the keys about it, or at its only key.
    public func pose(of bone: Int, in animation: Animation, at frame: Double) -> Key {
        guard let keys = animation.keys[bone], !keys.isEmpty else { return Key(frame: Int(frame)) }
        if frame <= Double(keys[0].frame) { return keys[0] }
        if frame >= Double(keys[keys.count - 1].frame) { return keys[keys.count - 1] }
        for index in 1..<keys.count where Double(keys[index].frame) >= frame {
            let a = keys[index - 1], b = keys[index]
            let share = Double(b.frame - a.frame) > 0 ? (frame - Double(a.frame)) / Double(b.frame - a.frame) : 0
            // Eased, as hand-made animation is.
            let eased = share * share * (3 - 2 * share)
            return Key(frame: Int(frame), angle: a.angle + (b.angle - a.angle) * eased,
                       dx: a.dx + (b.dx - a.dx) * eased, dy: a.dy + (b.dy - a.dy) * eased,
                       tiltX: a.tiltX + (b.tiltX - a.tiltX) * eased, tiltY: a.tiltY + (b.tiltY - a.tiltY) * eased)
        }
        return keys[keys.count - 1]
    }

    public mutating func setKey(_ key: Key, bone: Int, animation: Int) {
        guard animations.indices.contains(animation) else { return }
        var keys = animations[animation].keys[bone] ?? []
        keys.removeAll { $0.frame == key.frame }
        keys.append(key)
        keys.sort { $0.frame < $1.frame }
        animations[animation].keys[bone] = keys
    }

    /// Where every corner is at a frame of an animation, or at rest without one.
    public func posedPoints(animation: Int?, frame: Double) -> [Point] {
        let world = worldTransforms(animation: animation, frame: frame)
        let weights = self.weights()
        return points.enumerated().map { index, point in
            guard !bones.isEmpty else { return point }
            var x = 0.0, y = 0.0
            for slot in 0..<4 where weights[index].weights[slot] > 0 {
                let bone = weights[index].bones[slot]
                let move = world[bone]
                // From where the bone is at rest to where it is now.
                let along = alongBone(bone, point)
                let rx = along.x, ry = along.y
                let px = move.a * rx + move.c * ry + move.tx
                let py = move.b * rx + move.d * ry + move.ty
                x += px * weights[index].weights[slot]
                y += py * weights[index].weights[slot]
            }
            return Point(x: x, y: y)
        }
    }

    /// Each bone's place and turn in the picture at a frame; the place of a bone's joint is
    /// where the transform takes nought.
    public func posedTransforms(animation: Int?, frame: Double) -> [CGAffineTransform] {
        worldTransforms(animation: animation, frame: frame)
    }

    /// Each bone's place and turn in the picture at a frame, as an affine transform of where it
    /// holds things from its joint.
    func worldTransforms(animation: Int?, frame: Double) -> [CGAffineTransform] {
        var result = [CGAffineTransform?](repeating: nil, count: bones.count)
        func world(_ index: Int, _ depth: Int) -> CGAffineTransform {
            if let done = result[index] { return done }
            let bone = bones[index]
            var key = animation.flatMap { animations.indices.contains($0) ? pose(of: index, in: animations[$0], at: frame) : nil } ?? Key(frame: 0)
            key.angle += bone.restAngle
            let place = restPlace(of: index)
            let local = key.turn.concatenating(CGAffineTransform(translationX: place.x + key.dx, y: place.y + key.dy))
            let made = bone.parent.flatMap { $0 != index && depth < 64 ? world($0, depth + 1) : nil }.map { local.concatenating($0) } ?? local
            result[index] = made
            return made
        }
        return bones.indices.map { world($0, 0) }
    }

    /// Each bone from its parent at a frame, for the player: place (2), turn, scale (2), and
    /// the turns about the picture's x and y axes. `draft` stands in for what the animation says.
    public func localPoses(animation: Int?, frame: Double, draft: [Int: Key] = [:]) -> [[Double]] {
        bones.map { bone in
            let key = draft[bone.index]
                ?? animation.flatMap { animations.indices.contains($0) ? pose(of: bone.index, in: animations[$0], at: frame) : nil }
                ?? Key(frame: 0)
            let place = restPlace(of: bone.index)
            return [place.x + key.dx, place.y + key.dy, bone.restAngle + key.angle, 1, 1, key.tiltX, key.tiltY]
        }
    }

    /// The same as `posedTransforms`, with bones in `draft` where they stand for now.
    public func posedTransforms(animation: Int?, frame: Double, draft: [Int: Key]) -> [CGAffineTransform] {
        guard !draft.isEmpty, let animation, animations.indices.contains(animation) else {
            return worldTransforms(animation: animation, frame: frame)
        }
        var copy = self
        for (bone, key) in draft {
            var held = key
            held.frame = Int(frame.rounded())
            copy.animations[animation].keys[bone] = [held]
        }
        return copy.worldTransforms(animation: animation, frame: frame)
    }

    /// The rig as the player is handed a puppet, drawn with `material`.
    public func playerTable(material: String) -> [String: Any]? {
        WallpaperEnginePuppet(data: mdl(material: material))?.table
    }

    // MARK: - Writing

    /// The rig as Wallpaper Engine's `.mdl` file, drawn with `material`.
    public func mdl(material: String) -> Data {
        var data = Data()
        func uint(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func int(_ value: Int32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func float(_ value: Double) { withUnsafeBytes(of: Float(value).bitPattern.littleEndian) { data.append(contentsOf: $0) } }
        func text(_ value: String) { data.append(contentsOf: Array(value.utf8)); data.append(0) }
        func patch(_ at: Int, _ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { data.replaceSubrange(at..<(at + 4), with: $0) }
        }

        text("MDLV0013")
        uint(0x0180_0009)
        uint(1)
        uint(1)
        text(material)
        uint(0)
        let weights = self.weights()
        uint(UInt32(points.count * 52))
        for (index, point) in points.enumerated() {
            float(point.x)
            float(point.y)
            float(0)
            for slot in 0..<4 { uint(UInt32(weights[index].bones[slot])) }
            for slot in 0..<4 { float(weights[index].weights[slot]) }
            float((point.x + width / 2) / max(width, 1))
            float((height / 2 - point.y) / max(height, 1))
        }
        uint(UInt32(triangles.count * 2))
        for corner in triangles {
            withUnsafeBytes(of: UInt16(corner).littleEndian) { data.append(contentsOf: $0) }
        }

        // The bones: each from its parent, at rest.
        text("MDLS0001")
        let skeletonEnd = data.count
        uint(0)
        let rigBones = bones.isEmpty ? [Bone(index: 0, name: "", parent: nil, joint: Point(x: 0, y: 0))] : bones
        withUnsafeBytes(of: UInt16(rigBones.count).littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(0).littleEndian) { data.append(contentsOf: $0) }
        for bone in rigBones {
            text(bone.name)
            int(1)
            int(Int32(bone.parent ?? -1))
            uint(64)
            let place = bones.isEmpty ? bone.joint : restPlace(of: bone.index)
            let c = cos(bone.restAngle), s = sin(bone.restAngle)
            for value in [c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, place.x, place.y, 0, 1] {
                float(value)
            }
            text(physics(of: bone))
        }
        // Where the skeleton ends: where the animations begin.
        patch(skeletonEnd, UInt32(data.count))

        // The animations: where each bone is at every frame.
        text("MDLA0001")
        let animationsEnd = data.count
        uint(0)
        uint(UInt32(animations.count))
        for (index, animation) in animations.enumerated() {
            int(Int32(animation.id))
            uint(0)
            text(animation.name)
            text(animation.mode)
            float(animation.framesPerSecond)
            uint(UInt32(max(animation.length, 1)))
            uint(0)
            uint(UInt32(rigBones.count))
            for bone in rigBones.indices {
                uint(0)
                uint(UInt32((max(animation.length, 1) + 1) * 36))
                let place = bones.isEmpty ? rigBones[bone].joint : restPlace(of: bone)
                for frame in 0...max(animation.length, 1) {
                    let key = bones.isEmpty ? Key(frame: frame) : pose(of: bone, in: animations[index], at: Double(frame))
                    float(place.x + key.dx)
                    float(place.y + key.dy)
                    float(0)
                    float(key.tiltX)
                    float(key.tiltY)
                    float(rigBones[bone].restAngle + key.angle)
                    float(1)
                    float(1)
                    float(1)
                }
            }
            uint(0)
        }
        patch(animationsEnd, UInt32(data.count))
        return data
    }

    /// How a bone sways, in the words Wallpaper Engine's editor writes it.
    func physics(of bone: Bone) -> String {
        var tip = Point(x: 50, y: 0)
        if bones.indices.contains(bone.index), let reach = self.tip(of: bone.index) {
            tip = alongBone(bone.index, Point(x: bone.joint.x + reach.x, y: bone.joint.y + reach.y))
        }
        var values = bone.physics.flatMap { JSONValue(data: Data($0.utf8))?.objectValue } ?? ["tm": .number(100)]
        values["tp"] = .string(String(format: "%.5f %.5f 0.00000", tip.x, tip.y))
        if let sway = bone.sway {
            values["se"] = .bool(sway.kind == .spring)
            values["re"] = .bool(sway.kind == .hanging)
            values["r"] = .bool(true)
            values["rs"] = .number(sway.stiffness)
            values["rf"] = .number(sway.friction)
            values["ri"] = .number(sway.weight)
            values["ge"] = .bool(sway.kind == .hanging)
            values["gd"] = .string("0 -1 0")
        }
        return JSONValue.object(values).text
    }
}

// MARK: - In a scene

extension WallpaperEngineDocument {
    /// The file of the app's own that keeps the keys of a puppet, next to the puppet.
    public static func rigFileName(ofPuppet puppet: String) -> String {
        (puppet as NSString).deletingPathExtension + ".wallaero.json"
    }

    /// The name of the puppet an image object is, or would be.
    func puppetName(ofObject id: Int) -> String? {
        guard let model = object(id)?["image"]?.plain.stringValue, let value = file(model) else { return nil }
        return value["puppet"]?.stringValue ?? (model as NSString).deletingPathExtension + "_puppet.mdl"
    }

    /// The rig an image object is bent by, if it has one.
    public func rig(ofObject id: Int) -> WallpaperEnginePuppetRig? {
        guard let model = object(id)?["image"]?.plain.stringValue, let puppet = file(model)?["puppet"]?.stringValue else { return nil }
        return rigs[puppet]
    }

    /// Makes an image object a puppet bent by `rig`, or changes the one it is: the files of the
    /// puppet follow when the document is written. The animations it played go on being played.
    public mutating func setRig(_ rig: WallpaperEnginePuppetRig, ofObject id: Int) {
        guard let model = object(id)?["image"]?.plain.stringValue, var modelValue = file(model),
              let puppet = puppetName(ofObject: id) else { return }
        let old = rigs[puppet]
        rigs[puppet] = rig
        if modelValue["puppet"] == nil {
            modelValue["puppet"] = .string(puppet)
            setFile(model, modelValue)
            // Pictures bent by bones are drawn the way Wallpaper Engine's editor draws them.
            if let material = modelValue["material"]?.stringValue, var materialValue = file(material),
               var passes = materialValue["passes"]?.arrayValue, !passes.isEmpty {
                var combos = passes[0]["combos"] ?? .object([:])
                combos["VERSION"] = .number(2)
                passes[0]["combos"] = combos
                materialValue["passes"] = .array(passes)
                setFile(material, materialValue)
            }
        }
        guard old?.animations.map(\.id) != rig.animations.map(\.id) || old?.animations.map(\.name) != rig.animations.map(\.name) else { return }
        let ids = Set(rig.animations.map(\.id))
        let kept = (object(id)?["animationlayers"]?.arrayValue ?? []).filter { layer in
            layer["animation"]?.plain.numberValue.map { ids.contains(Int($0)) } ?? false
        }
        // One animation plays: the first; the others are there for scripts.
        let layers = kept.isEmpty ? rig.animations.prefix(1).map { animation -> JSONValue in
            .object([
                "additive": .bool(false), "animation": .number(Double(animation.id)), "blend": .number(1),
                "blendin": .bool(false), "blendout": .bool(false), "blendtime": .number(0.5), "id": .number(Double(newID())),
                "name": .string(animation.name), "rate": .number(1), "visible": .bool(true),
            ])
        } : kept
        update(id) { $0["animationlayers"] = .array(Array(layers)) }
    }

    /// Makes an image object a plain picture again.
    public mutating func removeRig(ofObject id: Int) {
        guard let model = object(id)?["image"]?.plain.stringValue, var value = file(model), let puppet = value["puppet"]?.stringValue else { return }
        value["puppet"] = nil
        setFile(model, value)
        rigs[puppet] = nil
        update(id) { $0["animationlayers"] = nil }
    }

    /// Makes an image object a puppet bent by `rig`, with its files written at once.
    public mutating func setPuppet(_ rig: WallpaperEnginePuppetRig, ofObject id: Int, projectFolder: URL) throws {
        setRig(rig, ofObject: id)
        guard let puppet = puppetName(ofObject: id) else { return }
        try writeRig(puppet, to: projectFolder)
    }

    /// Writes a rig as the puppet's `.mdl`, with the app's own file of its keys beside it.
    func writeRig(_ puppet: String, to projectFolder: URL) throws {
        guard let rig = rigs[puppet], Archive.staysInside(puppet) else { return }
        let material = files.values.first { $0["puppet"]?.stringValue == puppet }?["material"]?.stringValue ?? ""
        let url = projectFolder.appendingPathComponent(puppet)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try rig.mdl(material: material).write(to: url, options: .atomic)
        try JSONEncoder().encode(rig).write(to: projectFolder.appendingPathComponent(Self.rigFileName(ofPuppet: puppet)), options: .atomic)
    }

    /// Takes the rigs of the scene's puppets in from their files, to be edited. A file is only
    /// written again when its rig is changed.
    public mutating func loadRigs(projectFolder: URL) {
        for id in objectIDs where rig(ofObject: id) == nil {
            guard let found = object(id), Self.kind(of: found) == .image, let puppet = puppetName(ofObject: id), rigs[puppet] == nil else { continue }
            let size = object(id)?["size"]?.vector ?? []
            let picture = size.count < 2 ? self.picture(ofObject: id, projectFolder: projectFolder) : nil
            let width = size.first ?? Double(picture?.width ?? 100), height = size.count > 1 ? size[1] : Double(picture?.height ?? 100)
            if let rig = puppetRig(ofObject: id, projectFolder: projectFolder, width: width, height: height) {
                rigs[puppet] = rig
            }
        }
    }
}

// MARK: - On the timeline

extension WallpaperEnginePuppetRig {
    /// A key as the numbers the timeline has of a bone: the turns in degrees, then the moves.
    static func numbers(of key: Key) -> [Double] {
        [key.angle * 180 / .pi, key.tiltX * 180 / .pi, key.tiltY * 180 / .pi, key.dx, key.dy]
    }

    /// The keys of a bone as an animation of the timeline's. Between keys a bone eases from
    /// standing to standing; the handles say so, and the curves come out as it moves.
    public func timelineAnimation(_ animation: Int, bone: Int) -> WallpaperEngineAnimation? {
        guard animations.indices.contains(animation) else { return nil }
        let action = animations[animation]
        var made = WallpaperEngineAnimation(bone: (action.keys[bone] ?? []).map { (Double($0.frame), Self.numbers(of: $0)) }, channels: 5)
        made.options = WallpaperEngineAnimation.Options(fps: action.framesPerSecond, length: Double(action.length),
                                                        mode: WallpaperEngineAnimation.Mode(rawValue: action.mode) ?? .loop, name: action.name)
        return made
    }

    /// Takes keys back from the timeline's way of having them, with how the animation plays.
    public mutating func setTimelineAnimation(_ edited: WallpaperEngineAnimation, animation: Int, bone: Int) {
        guard animations.indices.contains(animation) else { return }
        let options = edited.options
        animations[animation].framesPerSecond = options.fps
        animations[animation].length = max(1, Int(options.length.rounded()))
        animations[animation].mode = options.mode.rawValue
        if !options.name.isEmpty { animations[animation].name = options.name }
        let frames = edited.keyFrames
        guard !frames.isEmpty else {
            animations[animation].keys[bone] = nil
            return
        }
        let zero = [Double](repeating: 0, count: 5)
        animations[animation].keys[bone] = frames.map { frame in
            let n = edited.numbers(atFrame: frame, base: zero)
            return Key(frame: Int(frame.rounded()), angle: n[0] * .pi / 180, dx: n[3], dy: n[4], tiltX: n[1] * .pi / 180, tiltY: n[2] * .pi / 180)
        }
    }
}

extension WallpaperEnginePuppetRig {
    /// A rig made of a puppet Wallpaper Engine wrote, to be changed: its mesh and bones, and
    /// keys taken from its animations every few frames. How much each bone holds each corner
    /// is worked out anew when it is written.
    public init?(mdl data: Data, width: Double, height: Double) {
        guard let puppet = WallpaperEnginePuppet(data: data) else { return nil }
        self.init(width: width, height: height)
        let stride = WallpaperEnginePuppet.floatsPerCorner
        points = (0..<(puppet.corners.count / stride)).map { index in
            Point(x: Double(puppet.corners[index * stride]), y: Double(puppet.corners[index * stride + 1]))
        }
        triangles = puppet.triangles.map(Int.init)
        holds = (0..<(puppet.corners.count / stride)).map { index in
            let at = index * stride
            return Hold(bones: (4..<8).map { Int(puppet.corners[at + $0]) }, weights: (8..<12).map { Double(puppet.corners[at + $0]) })
        }
        // Joints at rest, from each bone's place under its parent, which may be turned.
        var joints = [(point: Point, angle: Double)?](repeating: nil, count: puppet.bones.count)
        func joint(_ index: Int, _ depth: Int) -> (point: Point, angle: Double) {
            if let done = joints[index] { return done }
            let bone = puppet.bones[index]
            let own = Point(x: Double(bone.matrix[12]), y: Double(bone.matrix[13]))
            let turn = atan2(Double(bone.matrix[1]), Double(bone.matrix[0]))
            let base = bone.parent >= 0 && bone.parent != index && depth < 64 ? joint(bone.parent, depth + 1) : (point: Point(x: 0, y: 0), angle: 0)
            let c = cos(base.angle), s = sin(base.angle)
            let made = (Point(x: base.point.x + own.x * c - own.y * s, y: base.point.y + own.x * s + own.y * c), base.angle + turn)
            joints[index] = made
            return made
        }
        bones = puppet.bones.enumerated().map { index, bone in
            let place = joint(index, 0)
            var made = Bone(index: index, name: bone.name, parent: bone.parent >= 0 ? bone.parent : nil, joint: place.point)
            let turn = atan2(Double(bone.matrix[1]), Double(bone.matrix[0]))
            if abs(turn) > 1e-5 { made.restTurn = turn }
            made.physics = bone.physics
            if let said = bone.physics.flatMap({ JSONValue(data: Data($0.utf8)) }) {
                // The end of the bone is said from its joint, along the bone.
                let numbers = (said["tp"]?.stringValue ?? "").split(separator: " ").compactMap { Double($0) }
                if numbers.count >= 2, hypot(numbers[0], numbers[1]) > 0.001 {
                    let c = cos(place.angle), s = sin(place.angle)
                    made.tail = Point(x: place.point.x + numbers[0] * c - numbers[1] * s, y: place.point.y + numbers[0] * s + numbers[1] * c)
                }
                if said["se"]?.boolValue == true || said["re"]?.boolValue == true {
                    var sway = Sway(kind: said["se"]?.boolValue == true ? .spring : .hanging)
                    sway.stiffness = said["rs"]?.numberValue ?? sway.stiffness
                    sway.friction = said["rf"]?.numberValue ?? sway.friction
                    sway.weight = said["ri"]?.numberValue ?? sway.weight
                    made.sway = sway
                }
            }
            return made
        }
        animations = puppet.animations.map { source in
            var animation = Animation(id: source.id, name: source.name)
            animation.framesPerSecond = Double(source.framesPerSecond)
            animation.length = max(1, source.frameCount - 1)
            animation.mode = source.mode
            for bone in puppet.bones.indices {
                let rest = puppet.bones[bone].matrix
                var keys: [Key] = []
                for frame in Swift.stride(from: 0, to: source.frameCount, by: 5) + [source.frameCount - 1] where keys.last?.frame != frame {
                    let at = (bone * source.frameCount + frame) * 9
                    guard at + 5 < source.frames.count else { continue }
                    let turn = atan2(Double(rest[1]), Double(rest[0]))
                    keys.append(Key(frame: frame, angle: Double(source.frames[at + 5]) - turn,
                                    dx: Double(source.frames[at] - rest[12]), dy: Double(source.frames[at + 1] - rest[13]),
                                    tiltX: Double(source.frames[at + 3]), tiltY: Double(source.frames[at + 4])))
                }
                if keys.contains(where: { abs($0.angle) > 1e-5 || abs($0.dx) > 1e-3 || abs($0.dy) > 1e-3 ||
                                          abs($0.tiltX) > 1e-5 || abs($0.tiltY) > 1e-5 }) {
                    animation.keys[bone] = keys
                }
            }
            return animation
        }
    }
}

extension WallpaperEngineDocument {
    /// The picture an image object shows, as its texture has it.
    public func picture(ofObject id: Int, projectFolder: URL) -> CGImage? {
        guard let texture = material(ofObject: id)?.value["passes"]?[0]?["textures"]?[0]?.stringValue,
              let data = try? Data(contentsOf: projectFolder.appendingPathComponent("materials/\(texture).tex"))
        else {
            return nil
        }
        return WallpaperEngineTexture.image(from: data)
    }

    /// The rig of an image object that is a puppet, if it is one: as the app kept it, or made
    /// of the puppet's file.
    public func puppetRig(ofObject id: Int, projectFolder: URL, width: Double, height: Double) -> WallpaperEnginePuppetRig? {
        guard let model = object(id)?["image"]?.plain.stringValue, let puppet = file(model)?["puppet"]?.stringValue else { return nil }
        if let data = try? Data(contentsOf: projectFolder.appendingPathComponent(Self.rigFileName(ofPuppet: puppet))),
           let rig = try? JSONDecoder().decode(WallpaperEnginePuppetRig.self, from: data) {
            return rig
        }
        guard let data = try? Data(contentsOf: projectFolder.appendingPathComponent(puppet)) else { return nil }
        return WallpaperEnginePuppetRig(mdl: data, width: width, height: height)
    }
}

import CoreGraphics
import CryptoKit
import Foundation

/// A map painted for an effect: over the whole of the object, a value a pixel for a mask or a
/// depth, two for directions, three for colors. Wallpaper Engine keeps it as a texture of its own
/// in `materials/masks`, named after the effect, and the effect's pass names that texture in the
/// slot its shader asks for one in; nothing else says what it is.
public struct WallpaperEngineMask: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// How many values a pixel has.
    public let channels: Int
    /// By rows from the top, the values of a pixel side by side.
    public private(set) var pixels: [UInt8]

    /// The value of a direction map that stands for no direction.
    public static let noDirection: UInt8 = 127

    /// How the picture is to move under a brush painting directions.
    public enum Flow: Sendable {
        /// Along the way the brush goes.
        case along
        /// One way, across and down, from -1 to 1.
        case fixed(x: Double, y: Double)
        /// Round the middle of the brush.
        case spin
        /// Away from its middle.
        case spread
        /// Toward its middle.
        case pinch
    }

    /// What a brush does.
    public enum Paint: Sendable {
        /// Lays values down.
        case values([UInt8])
        /// Evens the map out.
        case smooth
        /// Lays directions down, as strong as this, from 0 to 1.
        case flow(Flow, strength: Double)
    }

    /// How a brush lays its paint down, sized in pixels of the map: an object drawn wider than
    /// its map makes the brush an oval here.
    public struct Brush: Sendable {
        public var radiusX: Double
        public var radiusY: Double
        /// From 0, soft from the middle out, to 1, sharp at its edge.
        public var hardness: Double
        /// How far the stroke goes toward what it lays down at most, from 0 to 1.
        public var opacity: Double
        public var paint: Paint

        public init(radiusX: Double, radiusY: Double, hardness: Double, opacity: Double, paint: Paint) {
            self.radiusX = radiusX
            self.radiusY = radiusY
            self.hardness = hardness
            self.opacity = opacity
            self.paint = paint
        }
    }

    /// One stroke, from pressing to letting go. However often the brush passes over a pixel, the
    /// stroke goes as far as the brush's opacity and no further.
    public struct Stroke: Sendable {
        fileprivate var before: [UInt8]
        fileprivate var reach: [Float]
        fileprivate var last: (x: Double, y: Double)?
    }

    /// A map all of one kind: with the values of a pixel.
    public init(width: Int, height: Int, values: [UInt8]) {
        self.width = max(1, width)
        self.height = max(1, height)
        channels = max(1, values.count)
        pixels = (0..<self.width * self.height).flatMap { _ in values }
    }

    /// A map read from its texture, whatever way that holds it, by the channels shaders read.
    public init?(textureFile: Data, channels: Int) {
        guard let image = WallpaperEngineTexture.image(from: textureFile), (1...3).contains(channels) else { return nil }
        let width = image.width, height = image.height
        var colors = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = colors.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.width = width
        self.height = height
        self.channels = channels
        var values = [UInt8]()
        values.reserveCapacity(width * height * channels)
        for index in stride(from: 0, to: colors.count, by: 4) {
            values.append(contentsOf: colors[index..<index + channels])
        }
        pixels = values
    }

    /// The size of a new map for an object: half of it, as Wallpaper Engine makes them, unless
    /// that leaves too little to paint on.
    public static func size(forObject width: Int, _ height: Int) -> (width: Int, height: Int) {
        guard max(width, height) > 512 else { return (max(1, width), max(1, height)) }
        return (max(1, width / 2), max(1, height / 2))
    }

    /// The values under a point, in pixels of the map.
    public func values(atX x: Double, y: Double) -> [UInt8] {
        let index = (min(height - 1, max(0, Int(y))) * width + min(width - 1, max(0, Int(x)))) * channels
        return Array(pixels[index..<index + channels])
    }

    /// The way the picture moves at a point of a direction map, across and down, each from -1 to 1.
    /// Shaders read the picture at a place that goes along the map's direction, so that what is
    /// shown goes the other way.
    public func flow(atX x: Double, y: Double) -> (x: Double, y: Double) {
        let values = values(atX: x, y: y)
        guard values.count >= 2 else { return (0, 0) }
        return (-(Double(values[0]) - 127) / 127, -(Double(values[1]) - 127) / 127)
    }

    public mutating func fill(_ values: [UInt8]) {
        pixels = (0..<width * height).flatMap { _ in values }
    }

    public func startStroke() -> Stroke {
        Stroke(before: pixels, reach: [Float](repeating: 0, count: pixels.count / channels), last: nil)
    }

    /// Takes the brush to a point of the map, in dabs close enough for the line to be even.
    public mutating func paint(_ stroke: inout Stroke, with brush: Brush, toX x: Double, y: Double) {
        let from = stroke.last ?? (x, y)
        let distance = hypot(x - from.x, y - from.y)
        // A direction taken from the way the brush goes has to wait for it to go somewhere.
        if case .flow(.along, _) = brush.paint, distance < 1 {
            if stroke.last == nil { stroke.last = (x, y) }
            return
        }
        let step = max(1, min(brush.radiusX, brush.radiusY) / 4)
        let dabs = max(1, Int((distance / step).rounded(.up)))
        for dab in (stroke.last == nil ? dabs : 1)...dabs {
            let share = Double(dab) / Double(dabs)
            let at = (x: from.x + (x - from.x) * share, y: from.y + (y - from.y) * share)
            switch brush.paint {
            case .smooth:
                smooth(at: at, with: brush)
            case .values(let values):
                lay(&stroke, at: at, with: brush) { _, _ in values.map(Float.init) }
            case .flow(let flow, let strength):
                let way = distance > 0 ? (x: (x - from.x) / distance, y: (y - from.y) / distance) : (x: 0, y: 0)
                lay(&stroke, at: at, with: brush) { dx, dy in
                    let length = (dx * dx + dy * dy).squareRoot()
                    // The middle of the brush has no direction of its own and fades into the rest.
                    let out = length > 0 ? (x: dx / length, y: dy / length) : (x: 0, y: 0), middle = min(1, length / 0.2)
                    let moves: (x: Double, y: Double)
                    switch flow {
                    case .along: moves = way
                    case .fixed(let x, let y): moves = (x, y)
                    case .spin: moves = (-out.y * middle, out.x * middle)
                    case .spread: moves = (out.x * middle, out.y * middle)
                    case .pinch: moves = (-out.x * middle, -out.y * middle)
                    }
                    return [127 - Float(moves.x * strength * 127), 127 - Float(moves.y * strength * 127)]
                }
            }
        }
        stroke.last = (x, y)
    }

    /// The share of the brush at a distance from its middle, in parts of its radius.
    private static func share(at distance: Double, hardness: Double) -> Float {
        guard distance < 1 else { return 0 }
        guard distance > hardness, hardness < 1 else { return 1 }
        let t = 1 - (distance - hardness) / (1 - hardness)
        return Float(t * t * (3 - 2 * t))
    }

    private func area(of at: (x: Double, y: Double), _ brush: Brush) -> (rows: Range<Int>, columns: Range<Int>)? {
        let left = max(0, Int((at.x - brush.radiusX).rounded(.down))), right = min(width, Int((at.x + brush.radiusX).rounded(.up)) + 1)
        let top = max(0, Int((at.y - brush.radiusY).rounded(.down))), bottom = min(height, Int((at.y + brush.radiusY).rounded(.up)) + 1)
        return left < right && top < bottom ? (top..<bottom, left..<right) : nil
    }

    /// One dab: the values for a pixel come from where it is in the brush, in parts of its radius.
    private mutating func lay(_ stroke: inout Stroke, at: (x: Double, y: Double), with brush: Brush,
                              values: (Double, Double) -> [Float]) {
        guard let area = area(of: at, brush) else { return }
        let opacity = Float(brush.opacity)
        for row in area.rows {
            let dy = (Double(row) + 0.5 - at.y) / brush.radiusY
            for column in area.columns {
                let dx = (Double(column) + 0.5 - at.x) / brush.radiusX
                let share = Self.share(at: (dx * dx + dy * dy).squareRoot(), hardness: brush.hardness)
                let index = row * width + column
                guard share > stroke.reach[index] else { continue }
                stroke.reach[index] = share
                let wanted = values(dx, dy)
                for channel in 0..<channels {
                    let before = Float(stroke.before[index * channels + channel])
                    pixels[index * channels + channel] = UInt8(min(255, max(0, before + (wanted[channel] - before) * share * opacity)).rounded())
                }
            }
        }
    }

    private mutating func smooth(at: (x: Double, y: Double), with brush: Brush) {
        guard let area = area(of: at, brush) else { return }
        let reach = max(1, Int(min(brush.radiusX, brush.radiusY) / 8))
        var result = pixels
        for row in area.rows {
            let dy = (Double(row) + 0.5 - at.y) / brush.radiusY
            for column in area.columns {
                let dx = (Double(column) + 0.5 - at.x) / brush.radiusX
                let share = Self.share(at: (dx * dx + dy * dy).squareRoot(), hardness: brush.hardness) * Float(brush.opacity)
                guard share > 0 else { continue }
                for channel in 0..<channels {
                    var sum = 0, count = 0
                    for near in max(0, row - reach)...min(height - 1, row + reach) {
                        for beside in max(0, column - reach)...min(width - 1, column + reach) {
                            sum += Int(pixels[(near * width + beside) * channels + channel])
                            count += 1
                        }
                    }
                    let index = (row * width + column) * channels + channel
                    let before = Float(pixels[index])
                    result[index] = UInt8((before + (Float(sum) / Float(count) - before) * share).rounded())
                }
            }
        }
        pixels = result
    }

    /// The map as four bytes a pixel, as a graphics card takes it: one value is a grey, and of two
    /// the second is green, which is how shaders read them.
    public func writeColors(to memory: UnsafeMutablePointer<UInt8>) {
        let count = pixels.count / channels
        for index in 0..<count {
            let at = memory + index * 4
            switch channels {
            case 1:
                at[0] = pixels[index]
                at[1] = pixels[index]
                at[2] = pixels[index]
            case 2:
                at[0] = pixels[index * 2]
                at[1] = pixels[index * 2 + 1]
                at[2] = 0
            default:
                at[0] = pixels[index * 3]
                at[1] = pixels[index * 3 + 1]
                at[2] = pixels[index * 3 + 2]
            }
            at[3] = 255
        }
    }

    /// The map as a picture of three colors: the kind of PNG Wallpaper Engine keeps in a mask.
    private var picture: CGImage? {
        var colors = [UInt8](repeating: 255, count: pixels.count / channels * 4)
        colors.withUnsafeMutableBufferPointer { writeColors(to: $0.baseAddress!) }
        return colors.withUnsafeMutableBytes { bytes in
            CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        }
    }

    /// Writes the map into a project as `materials/masks/<effect>_mask_<digest>.tex`, and
    /// returns the name a pass gives it. A map painted the same comes to the same file.
    public func save(forEffect effect: String, to projectFolder: URL) throws -> String {
        guard let picture, let png = WallpaperEngineProjectFolder.pngData(picture) else {
            throw WallpaperEngineProjectFolder.Problem.unreadablePicture
        }
        let digest = SHA256.hash(data: Data(pixels)).prefix(4).map { String(format: "%02x", $0) }.joined()
        let name = "\(effect)_mask_\(digest)"
        let url = projectFolder.appendingPathComponent("materials/masks/\(name).tex")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Direction maps say their color at rest in the header, as Wallpaper Engine writes them.
        try WallpaperEngineWriter.texture(picture: png, width: width, height: height, color: channels == 2 ? 0xFF00_7F7F : 0xFF00_0000)
            .write(to: url, options: .atomic)
        return "masks/\(name)"
    }
}

extension WallpaperEngineDocument {
    /// The texture in a slot of a pass of an effect, as the scene names it.
    public func effectTexture(object id: Int, effect: Int, pass: Int, slot: Int) -> String? {
        guard let passes = object(id)?["effects"]?.arrayValue.flatMap({ $0.indices.contains(effect) ? $0[effect]["passes"]?.arrayValue : nil }),
              passes.indices.contains(pass), let textures = passes[pass]["textures"]?.arrayValue, textures.indices.contains(slot)
        else { return nil }
        return textures[slot].stringValue
    }

    /// Sets a switch of the shader of passes of an effect.
    public mutating func setEffectCombo(_ name: String, to value: Double, object id: Int, effect: Int, passes wanted: [Int]) {
        update(id) { object in
            guard var effects = object["effects"]?.arrayValue, effects.indices.contains(effect) else { return }
            var passes = effects[effect]["passes"]?.arrayValue ?? []
            for index in wanted {
                while passes.count <= index { passes.append(.object([:])) }
                var combos = passes[index]["combos"] ?? .object([:])
                combos[name] = .number(value)
                passes[index]["combos"] = combos
            }
            effects[effect]["passes"] = .array(passes)
            object["effects"] = .array(effects)
        }
    }

    /// Puts a texture in a slot of passes of an effect, or takes it out. Passes before it are
    /// kept in their places, as the player and Wallpaper Engine count them.
    public mutating func setEffectTexture(_ texture: String?, object id: Int, effect: Int, passes wanted: [Int], slot: Int) {
        update(id) { object in
            guard var effects = object["effects"]?.arrayValue, effects.indices.contains(effect) else { return }
            var passes = effects[effect]["passes"]?.arrayValue ?? []
            for index in wanted {
                while passes.count <= index { passes.append(.object([:])) }
                var textures = passes[index]["textures"]?.arrayValue ?? []
                while textures.count <= slot { textures.append(.null) }
                textures[slot] = texture.map { .string($0) } ?? .null
                while let last = textures.last, last.isNull { textures.removeLast() }
                passes[index]["textures"] = textures.isEmpty ? nil : .array(textures)
            }
            effects[effect]["passes"] = .array(passes)
            object["effects"] = .array(effects)
        }
    }
}

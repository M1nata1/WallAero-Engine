import CoreGraphics
import Foundation

/// Systems of particles the editor starts from: the app's own, described in Wallpaper Engine's
/// format, with sprites the app draws. A system brought into a scene is laid into its project
/// as `particles/<name>.json`, with its material and sprite under `materials/particle/wallaero`.
public struct WallpaperEngineParticlePreset: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let symbol: String
    let sprite: Sprite
    let blending: String
    let system: JSONValue

    enum Sprite: String, Sendable {
        case soft, streak, ring
    }

    public static let all: [WallpaperEngineParticlePreset] = [snow, rain, fireflies, dust, embers, bubbles]

    public static func named(_ id: String) -> WallpaperEngineParticlePreset? {
        all.first { $0.id == id }
    }

    /// The material the system is drawn with.
    var materialName: String { "materials/particle/wallaero/\(sprite.rawValue)_\(blending).json" }
    var textureName: String { "particle/wallaero/\(sprite.rawValue)" }

    /// The system as a file of the project, drawn with its material.
    public var file: JSONValue {
        var system = self.system
        system["material"] = .string(materialName)
        return system
    }

    // MARK: - The presets

    private static func component(_ name: String, _ id: Int, _ values: [String: JSONValue] = [:]) -> JSONValue {
        var object = values
        object["name"] = .string(name)
        object["id"] = .number(Double(id))
        return .object(object)
    }

    private static func system(maxCount: Int, emitter: [JSONValue], initializer: [JSONValue], operator operators: [JSONValue],
                               renderer: String = "sprite", startTime: Double = 0) -> JSONValue {
        .object([
            "emitter": .array(emitter),
            "initializer": .array(initializer),
            "operator": .array(operators),
            "renderer": .array([component(renderer, 1)]),
            "maxcount": .number(Double(maxCount)),
            "starttime": .number(startTime),
            "flags": .number(0),
        ])
    }

    /// Particles made anywhere across a band above the scene's top, falling.
    static let snow = WallpaperEngineParticlePreset(
        id: "snow", title: NSLocalizedString("Snow", comment: "Particle preset"), symbol: "snowflake", sprite: .soft, blending: "translucent",
        system: system(maxCount: 600, emitter: [component("boxrandom", 2, [
            "distancemax": .string("1100 40 0"), "origin": .string("0 600 0"), "rate": .number(60),
        ])], initializer: [
            component("lifetimerandom", 3, ["min": .number(12), "max": .number(18)]),
            component("sizerandom", 4, ["min": .number(6), "max": .number(22)]),
            component("alpharandom", 5, ["min": .number(0.5), "max": .number(1)]),
            component("velocityrandom", 6, ["min": .string("-20 -90 0"), "max": .string("20 -50 0")]),
            component("colorrandom", 7, ["min": .string("230 240 255"), "max": .string("255 255 255")]),
        ], operator: [
            component("movement", 8, ["gravity": .string("0 -4 0"), "drag": .number(0)]),
            component("alphafade", 9, ["fadeintime": .number(0.1), "fadeouttime": .number(0.9)]),
            component("turbulence", 10, ["scale": .number(0.004), "speedmin": .number(10), "speedmax": .number(30), "mask": .string("1 0.2 0")]),
        ], startTime: 15))

    static let rain = WallpaperEngineParticlePreset(
        id: "rain", title: NSLocalizedString("Rain", comment: "Particle preset"), symbol: "cloud.rain", sprite: .streak, blending: "translucent",
        system: system(maxCount: 900, emitter: [component("boxrandom", 2, [
            "distancemax": .string("1100 40 0"), "origin": .string("0 600 0"), "rate": .number(400),
        ])], initializer: [
            component("lifetimerandom", 3, ["min": .number(1.2), "max": .number(1.6)]),
            component("sizerandom", 4, ["min": .number(14), "max": .number(30)]),
            component("alpharandom", 5, ["min": .number(0.25), "max": .number(0.6)]),
            component("velocityrandom", 6, ["min": .string("-60 -1100 0"), "max": .string("-40 -900 0")]),
            component("colorrandom", 7, ["min": .string("190 210 230"), "max": .string("230 240 255")]),
        ], operator: [
            component("movement", 8, ["gravity": .string("0 -300 0")]),
            component("alphafade", 9, ["fadeintime": .number(0.05), "fadeouttime": .number(0.2)]),
        ], renderer: "spritetrail", startTime: 2))

    static let fireflies = WallpaperEngineParticlePreset(
        id: "fireflies", title: NSLocalizedString("Fireflies", comment: "Particle preset"), symbol: "sparkles", sprite: .soft, blending: "additive",
        system: system(maxCount: 60, emitter: [component("boxrandom", 2, [
            "distancemax": .string("900 400 0"), "rate": .number(6),
        ])], initializer: [
            component("lifetimerandom", 3, ["min": .number(5), "max": .number(9)]),
            component("sizerandom", 4, ["min": .number(10), "max": .number(28)]),
            component("velocityrandom", 6, ["min": .string("-15 -15 0"), "max": .string("15 15 0")]),
            component("colorrandom", 7, ["min": .string("200 255 90"), "max": .string("255 255 160")]),
        ], operator: [
            component("movement", 8, ["gravity": .string("0 0 0")]),
            component("alphafade", 9, ["fadeintime": .number(0.3), "fadeouttime": .number(0.4)]),
            component("turbulence", 10, ["scale": .number(0.006), "speedmin": .number(20), "speedmax": .number(45)]),
            component("oscillatealpha", 11, ["frequencymin": .number(0.5), "frequencymax": .number(2), "scalemin": .number(0.2)]),
        ], startTime: 8))

    static let dust = WallpaperEngineParticlePreset(
        id: "dust", title: NSLocalizedString("Dust in Light", comment: "Particle preset"), symbol: "aqi.low", sprite: .soft, blending: "additive",
        system: system(maxCount: 150, emitter: [component("boxrandom", 2, [
            "distancemax": .string("1000 600 0"), "rate": .number(12),
        ])], initializer: [
            component("lifetimerandom", 3, ["min": .number(8), "max": .number(14)]),
            component("sizerandom", 4, ["min": .number(2), "max": .number(7)]),
            component("alpharandom", 5, ["min": .number(0.2), "max": .number(0.7)]),
            component("velocityrandom", 6, ["min": .string("-6 -6 0"), "max": .string("6 6 0")]),
            component("colorrandom", 7, ["min": .string("255 240 210"), "max": .string("255 255 240")]),
        ], operator: [
            component("movement", 8, ["gravity": .string("0 -1 0")]),
            component("alphafade", 9, ["fadeintime": .number(0.3), "fadeouttime": .number(0.4)]),
            component("turbulence", 10, ["scale": .number(0.003), "speedmin": .number(4), "speedmax": .number(12)]),
        ], startTime: 12))

    static let embers = WallpaperEngineParticlePreset(
        id: "embers", title: NSLocalizedString("Embers", comment: "Particle preset"), symbol: "flame", sprite: .soft, blending: "additive",
        system: system(maxCount: 80, emitter: [component("boxrandom", 2, [
            "distancemax": .string("700 30 0"), "origin": .string("0 -560 0"), "rate": .number(14),
        ])], initializer: [
            component("lifetimerandom", 3, ["min": .number(3), "max": .number(6)]),
            component("sizerandom", 4, ["min": .number(4), "max": .number(14)]),
            component("velocityrandom", 6, ["min": .string("-30 80 0"), "max": .string("30 180 0")]),
            component("colorrandom", 7, ["min": .string("255 120 40"), "max": .string("255 210 110")]),
        ], operator: [
            component("movement", 8, ["gravity": .string("0 10 0")]),
            component("alphafade", 9, ["fadeintime": .number(0.05), "fadeouttime": .number(0.6)]),
            component("turbulence", 10, ["scale": .number(0.004), "speedmin": .number(30), "speedmax": .number(70), "mask": .string("1 0.3 0")]),
            component("sizechange", 11, ["starttime": .number(0.5), "startvalue": .number(1), "endvalue": .number(0.2)]),
        ], startTime: 5))

    static let bubbles = WallpaperEngineParticlePreset(
        id: "bubbles", title: NSLocalizedString("Bubbles", comment: "Particle preset"), symbol: "bubbles.and.sparkles", sprite: .ring, blending: "translucent",
        system: system(maxCount: 60, emitter: [component("boxrandom", 2, [
            "distancemax": .string("900 20 0"), "origin": .string("0 -560 0"), "rate": .number(4),
        ])], initializer: [
            component("lifetimerandom", 3, ["min": .number(6), "max": .number(10)]),
            component("sizerandom", 4, ["min": .number(16), "max": .number(48)]),
            component("alpharandom", 5, ["min": .number(0.5), "max": .number(0.9)]),
            component("velocityrandom", 6, ["min": .string("-10 60 0"), "max": .string("10 140 0")]),
        ], operator: [
            component("movement", 8, ["gravity": .string("0 5 0")]),
            component("alphafade", 9, ["fadeintime": .number(0.1), "fadeouttime": .number(0.2)]),
            component("turbulence", 10, ["scale": .number(0.005), "speedmin": .number(15), "speedmax": .number(35), "mask": .string("1 0 0")]),
        ], startTime: 6))
}

extension WallpaperEngineDocument {
    /// Brings a system of particles into the scene: its file, material and sprite into the
    /// project if they are not there, and an object that plays it.
    @discardableResult
    public mutating func addParticles(_ preset: WallpaperEngineParticlePreset, projectFolder: URL) throws -> Int {
        let sprite = projectFolder.appendingPathComponent("materials/\(preset.textureName).tex")
        if !FileManager.default.fileExists(atPath: sprite.path), let png = WallpaperEngineParticlePreset.spritePNG(preset.sprite) {
            try FileManager.default.createDirectory(at: sprite.deletingLastPathComponent(), withIntermediateDirectories: true)
            try WallpaperEngineWriter.texture(picture: png, width: 128, height: 128).write(to: sprite, options: .atomic)
        }
        if file(preset.materialName) == nil {
            setFile(preset.materialName, .object(["passes": .array([.object([
                "blending": .string(preset.blending),
                "cullmode": .string("nocull"),
                "depthtest": .string("disabled"),
                "depthwrite": .string("disabled"),
                "shader": .string("genericparticle"),
                "textures": .array([.string(preset.textureName)]),
            ])])]))
        }
        // Each system has a file of its own, to be changed without changing another's.
        var name = "particles/\(preset.id).json"
        var number = 2
        while file(name) != nil || FileManager.default.fileExists(atPath: projectFolder.appendingPathComponent(name).path) {
            name = "particles/\(preset.id)_\(number).json"
            number += 1
        }
        setFile(name, preset.file)
        return addParticles(file: name, name: preset.title)
    }
}

extension WallpaperEngineParticlePreset {
    /// A sprite of 128 by 128 pixels, as a PNG file: white, its shape in its opacity.
    static func spritePNG(_ sprite: Sprite) -> Data? {
        let side = 128
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            return nil
        }
        let middle = CGPoint(x: side / 2, y: side / 2)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func white(_ alpha: CGFloat) -> CGColor { CGColor(colorSpace: space, components: [1, 1, 1, alpha])! }
        switch sprite {
        case .soft:
            let gradient = CGGradient(colorsSpace: space, colors: [white(1), white(0.55), white(0)] as CFArray, locations: [0, 0.35, 1])!
            context.drawRadialGradient(gradient, startCenter: middle, startRadius: 0, endCenter: middle, endRadius: CGFloat(side) / 2, options: [])
        case .streak:
            let gradient = CGGradient(colorsSpace: space, colors: [white(0), white(1), white(0)] as CFArray, locations: [0, 0.5, 1])!
            context.saveGState()
            context.clip(to: CGRect(x: CGFloat(side) * 0.44, y: 0, width: CGFloat(side) * 0.12, height: CGFloat(side)))
            context.drawLinearGradient(gradient, start: CGPoint(x: middle.x, y: 0), end: CGPoint(x: middle.x, y: CGFloat(side)), options: [])
            context.restoreGState()
        case .ring:
            let gradient = CGGradient(colorsSpace: space, colors: [white(0.08), white(0.15), white(0.9), white(0)] as CFArray,
                                      locations: [0, 0.75, 0.9, 1])!
            context.drawRadialGradient(gradient, startCenter: middle, startRadius: 0, endCenter: middle, endRadius: CGFloat(side) / 2, options: [])
            context.setFillColor(white(0.7))
            context.fillEllipse(in: CGRect(x: CGFloat(side) * 0.3, y: CGFloat(side) * 0.6, width: CGFloat(side) * 0.14, height: CGFloat(side) * 0.1))
        }
        guard let image = context.makeImage() else { return nil }
        return WallpaperEngineProjectFolder.pngData(image)
    }
}

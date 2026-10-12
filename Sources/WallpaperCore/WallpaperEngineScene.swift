import CoreGraphics
import Foundation

/// Turns one of Wallpaper Engine's own scenes into a scene of this app.
///
/// Such a scene is a list of objects on a canvas of a set size. The pictures among them are
/// brought over: the one that fills the canvas at the very bottom becomes the background, the
/// others become picture layers, each where it was and as large, to be moved and changed in
/// the editor like any layer. What Wallpaper Engine draws with programs of its own — the
/// effects on a picture, particles — and its sounds have nothing here to draw them and are
/// left out; `LeftOut` says how much of that there was.
public enum WallpaperEngineScene {
    /// What a scene had that was not brought over.
    public struct LeftOut: Equatable, Sendable {
        /// Effects on pictures: glows, rays, waves.
        public var effects = 0
        public var particles = 0
        public var sounds = 0
        /// Objects of other kinds, and pictures that could not be read.
        public var others = 0

        public var isEmpty: Bool { effects + particles + sounds + others == 0 }

        public init(effects: Int = 0, particles: Int = 0, sounds: Int = 0, others: Int = 0) {
            self.effects = effects
            self.particles = particles
            self.sounds = sounds
            self.others = others
        }
    }

    struct Converted {
        var scene: WallpaperScene
        var leftOut: LeftOut
    }

    /// Reads the scene and writes its pictures as PNG files into the `media` folder of
    /// `folder`. Throws when the scene has no picture that could be read.
    static func convert(_ package: WallpaperEnginePackage, into folder: URL) throws -> Converted {
        guard let description = package.json(named: "scene.json") else { throw ImportError.unreadable }
        var leftOut = LeftOut()
        var pictures: [Picture] = []
        for case let object as [String: Any] in description["objects"] as? [Any] ?? [] {
            let effects = (object["effects"] as? [Any] ?? [])
                .filter { (plain(($0 as? [String: Any])?["visible"]) as? Bool) != false }
                .count
            if object["particle"] != nil {
                leftOut.particles += 1
            } else if object["sound"] != nil {
                leftOut.sounds += 1
            } else if object["image"] != nil, let picture = picture(of: object, in: package) {
                leftOut.effects += effects
                pictures.append(picture)
            } else if object["image"] != nil, effects > 0 {
                // A layer with no picture of its own, there to put effects over what is under it.
                leftOut.effects += effects
            } else {
                leftOut.others += 1
            }
        }
        guard !pictures.isEmpty else { throw ImportError.noPicturesInScene }

        let general = description["general"] as? [String: Any] ?? [:]
        let projection = general["orthogonalprojection"] as? [String: Any] ?? [:]
        // A scene may leave its size to Wallpaper Engine, which then takes the first picture's.
        var canvas = CGSize(width: number(projection["width"]) ?? 0, height: number(projection["height"]) ?? 0)
        if canvas.width < 1 || canvas.height < 1 {
            canvas = pictures[0].size
        }

        var scene = WallpaperScene()
        scene.background.color = WallpaperEngineProject.hexColor(plain(general["clearcolor"]) as? String) ?? "#000000"
        let media = folder.appendingPathComponent(SceneProject.mediaFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        for (index, picture) in pictures.enumerated() {
            if index == 0, picture.fills(canvas) {
                let name = "background.png"
                try Thumbnailer.writePNG(picture.image, to: media.appendingPathComponent(name))
                scene.background.kind = .image
                scene.background.source = "\(SceneProject.mediaFolderName)/\(name)"
                continue
            }
            let name = "picture-\(index + 1).png"
            try Thumbnailer.writePNG(picture.image, to: media.appendingPathComponent(name))
            var layer = WallpaperScene.Layer(kind: .image, name: picture.name)
            layer.source = "\(SceneProject.mediaFolderName)/\(name)"
            layer.isVisible = picture.isVisible
            layer.x = rounded(picture.center.x / canvas.width * 100)
            // Wallpaper Engine counts up from the bottom of the canvas.
            layer.y = rounded((1 - picture.center.y / canvas.height) * 100)
            layer.width = rounded(picture.size.width / canvas.width * 100)
            layer.height = rounded(picture.size.height / canvas.height * 100)
            layer.rotation = rounded(picture.rotation)
            layer.opacity = rounded(picture.opacity * 100)
            layer.blendMode = picture.blendMode
            scene.layers.append(layer)
        }
        return Converted(scene: scene, leftOut: leftOut)
    }

    // MARK: - Pictures

    private struct Picture {
        var name: String
        var image: CGImage
        /// On the canvas, counted from its bottom left corner.
        var center: CGPoint
        var size: CGSize
        /// Degrees, clockwise.
        var rotation: Double
        /// From 0 to 1.
        var opacity: Double
        var isVisible: Bool
        var blendMode: String

        /// Whether the picture is the canvas's own backdrop: all of it, straight and opaque.
        func fills(_ canvas: CGSize) -> Bool {
            isVisible && opacity > 0.99 && abs(rotation) < 0.1 && blendMode == "normal"
                && abs(center.x - canvas.width / 2) <= canvas.width * 0.02
                && abs(center.y - canvas.height / 2) <= canvas.height * 0.02
                && abs(size.width - canvas.width) <= canvas.width * 0.02
                && abs(size.height - canvas.height) <= canvas.height * 0.02
        }
    }

    /// The picture an object shows. An object names a model, the model a material, and the
    /// material the texture with the pixels.
    private static func picture(of object: [String: Any], in package: WallpaperEnginePackage) -> Picture? {
        guard let modelName = plain(object["image"]) as? String, let model = package.json(named: modelName),
              let materialName = model["material"] as? String, let material = package.json(named: materialName),
              let pass = (material["passes"] as? [Any])?.first as? [String: Any],
              let texture = (pass["textures"] as? [Any])?.first as? String,
              let data = package.data(named: "materials/\(texture).tex"),
              let image = WallpaperEngineTexture.image(from: data)
        else {
            return nil
        }
        let origin = numbers(object["origin"])
        let scale = numbers(object["scale"])
        let angles = numbers(object["angles"])
        var size = numbers(object["size"])
        if size.count < 2 || size[0] < 1 || size[1] < 1 {
            size = [number(model["width"]) ?? Double(image.width), number(model["height"]) ?? Double(image.height)]
        }
        let name = (plain(object["name"]) as? String).flatMap { $0.isEmpty ? nil : $0 } ?? texture
        return Picture(
            name: name,
            image: image,
            center: CGPoint(x: origin.count > 0 ? origin[0] : size[0] / 2, y: origin.count > 1 ? origin[1] : size[1] / 2),
            // A scale below zero mirrors the picture; the size is the same.
            size: CGSize(width: size[0] * abs(scale.count > 0 ? scale[0] : 1), height: size[1] * abs(scale.count > 1 ? scale[1] : 1)),
            // Wallpaper Engine turns counterclockwise and counts in radians.
            rotation: -(angles.count > 2 ? angles[2] : 0) * 180 / .pi,
            opacity: min(1, max(0, number(plain(object["alpha"])) ?? 1)),
            isVisible: (plain(object["visible"]) as? Bool) ?? true,
            blendMode: (pass["blending"] as? String)?.lowercased() == "additive" ? "plus-lighter" : "normal"
        )
    }

    // MARK: - Values

    /// A value as the scene gives it. One that a setting of the wallpaper or a script stands
    /// behind is written as a dictionary with the value inside.
    private static func plain(_ value: Any?) -> Any? {
        (value as? [String: Any]).map { $0["value"] as Any? } ?? value
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return (value as? String).flatMap(Double.init)
    }

    /// Several numbers written as one text: "990.000 540.000 0.000".
    private static func numbers(_ value: Any?) -> [Double] {
        (plain(value) as? String ?? "").split(whereSeparator: \.isWhitespace).compactMap { Double($0) }.filter(\.isFinite)
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }
}

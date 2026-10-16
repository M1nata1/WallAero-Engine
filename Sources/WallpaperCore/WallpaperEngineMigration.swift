import CoreGraphics
import Foundation

extension WallpaperEngineDocument {
    /// What the earlier editor changed of a scene, kept beside it, put into the scene itself.
    public mutating func apply(_ changes: WallpaperScene.EngineChanges) {
        func set(_ key: String, _ value: JSONValue, in object: inout JSONValue) {
            object[key] = (object[key] ?? .null).replacingPlain(with: value)
        }
        if let parallax = changes.parallax { self[general: "cameraparallax"] = (self[general: "cameraparallax"] ?? .null).replacingPlain(with: .bool(parallax)) }
        if let amount = changes.parallaxAmount { self[general: "cameraparallaxamount"] = .number(amount) }
        if let bloom = changes.bloom { self[general: "bloom"] = (self[general: "bloom"] ?? .null).replacingPlain(with: .bool(bloom)) }
        if let strength = changes.bloomStrength { self[general: "bloomstrength"] = .number(strength) }
        for change in changes.objects {
            update(change.id) { object in
                if let visible = change.isVisible { set("visible", .bool(visible), in: &object) }
                if change.x != nil || change.y != nil {
                    var origin = object["origin"]?.vector ?? [0, 0, 0]
                    while origin.count < 3 { origin.append(0) }
                    if let x = change.x { origin[0] = x }
                    if let y = change.y { origin[1] = y }
                    set("origin", .vector(origin), in: &object)
                }
                if change.scaleX != nil || change.scaleY != nil {
                    var scale = object["scale"]?.vector ?? [1, 1, 1]
                    while scale.count < 3 { scale.append(1) }
                    if let x = change.scaleX { scale[0] = x }
                    if let y = change.scaleY { scale[1] = y }
                    set("scale", .vector(scale), in: &object)
                }
                if let rotation = change.rotation {
                    var angles = object["angles"]?.vector ?? [0, 0, 0]
                    while angles.count < 3 { angles.append(0) }
                    angles[2] = -rotation * .pi / 180
                    set("angles", .vector(angles), in: &object)
                }
                if let opacity = change.opacity { set("alpha", .number(opacity / 100), in: &object) }
                if let color = change.color, let numbers = Self.numbers(hex: color) { set("color", .vector(numbers), in: &object) }
                if let text = change.text {
                    var value = object["text"] ?? .object([:])
                    if value.objectValue != nil { value["value"] = .string(text) } else { value = .object(["value": .string(text)]) }
                    object["text"] = value
                }
                if let size = change.fontSize { set("pointsize", .number(size), in: &object) }
                if let volume = change.volume { set("volume", .number(volume / 100), in: &object) }
                var over = object["instanceoverride"] ?? .object([:])
                for (key, value) in [("count", change.particleCount), ("rate", change.particleRate), ("speed", change.particleSpeed),
                                     ("size", change.particleSize), ("lifetime", change.particleLifetime), ("alpha", change.particleOpacity)] {
                    if let value { over[key] = .number(value / 100) }
                }
                if let color = change.particleColor, let numbers = Self.numbers(hex: color) {
                    over["colorn"] = .vector(numbers)
                    over["color"] = nil
                }
                if over != .object([:]) || object["instanceoverride"] != nil { object["instanceoverride"] = over }
            }
            for effect in change.effects {
                if let visible = effect.isVisible { setEffectVisible(visible, effect: effect.id, of: change.id) }
                for (name, numbers) in effect.values {
                    let value: JSONValue = numbers.count == 1 ? .number(numbers[0])
                        : .string(numbers.map { String(format: "%g", $0) }.joined(separator: " "))
                    setEffectValue(value, named: name, effect: effect.id, of: change.id)
                }
            }
        }
    }

    private static func numbers(hex: String) -> [Double]? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count >= 6, let value = UInt32(text.prefix(6), radix: 16) else { return nil }
        return [Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255]
    }
}

extension WallpaperLibrary {
    /// Gives a Wallpaper Engine scene added before the editor could change it its project back,
    /// from the archive or folder it came in, so that it opens in the editor. It stays the same
    /// wallpaper: its settings keep their values, and what the earlier editor changed of it is
    /// put into the project.
    public func attachEngineProject(from source: URL, to item: Wallpaper, languages: [String] = Locale.preferredLanguages) async throws {
        let files = FileManager.default
        var folder = source
        var unpacked: URL?
        if Archive.isArchive(source) {
            let temporary = files.temporaryDirectory.appendingPathComponent("WallAeroEngine-\(UUID().uuidString)", isDirectory: true)
            try await Task.detached(priority: .userInitiated) { try Archive.unpack(source, into: temporary) }.value
            folder = temporary
            unpacked = temporary
        }
        defer { if let unpacked { try? files.removeItem(at: unpacked) } }
        let scenes = WallpaperEngineProject.settled(WallpaperEngineProject.all(in: folder, languages: languages)).filter { $0.kind == .scene }
        guard let project = scenes.first(where: { $0.title == item.name }) ?? (scenes.count == 1 ? scenes.first : nil) else {
            throw ImportError.unreadable
        }
        let scene = projectURL(for: item)
        let target = scene.appendingPathComponent(WallpaperEngineProjectFolder.folderName, isDirectory: true)
        let source = project.folder
        try await Task.detached(priority: .userInitiated) {
            try? FileManager.default.removeItem(at: target)
            try WallpaperEngineProjectFolder.unpack(source, to: target)
            var stored = try SceneProject.read(from: scene)
            var document = try WallpaperEngineProjectFolder.read(from: target)
            let original = document
            document.apply(stored.background.engine)
            try WallpaperEngineProjectFolder.write(document, previous: original, to: target)
            // Only what the project cannot say stays beside it: what to leave off the lock screen.
            var kept = WallpaperScene.EngineChanges()
            kept.objects = stored.background.engine.objects.compactMap { change in
                guard let shows = change.showsOnLockScreen else { return nil }
                var only = WallpaperScene.ObjectChange(id: change.id)
                only.showsOnLockScreen = shows
                return only
            }
            stored.background.engine = kept
            try SceneProject.write(stored, to: scene)
            try WallpaperEngineProjectFolder.layOut(scene: scene)
        }.value
    }
}

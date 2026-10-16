import CoreGraphics
import Foundation
import ImageIO

/// A scene of the app's own format made into one of Wallpaper Engine's, for its editor: the
/// background and the layers become objects, a layer's animation an effect, the variables the
/// wallpaper's settings. A layer of code has no counterpart there, nor has a web page as the
/// background; a scene with either stays as it is.
public enum WallpaperSceneConversion {
    /// Whether the scene can be made into one of Wallpaper Engine's.
    public static func canConvert(_ scene: WallpaperScene) -> Bool {
        guard scene.background.kind != .page, scene.background.kind != .engine else { return false }
        return !scene.layers.contains { $0.kind == .code }
    }

    /// Makes the scene of `folder` into a Wallpaper Engine project in it, of the given size,
    /// and lays that out for the player. The scene's old file is kept next to it.
    public static func convert(sceneIn folder: URL, size: CGSize, title: String) async throws {
        let scene = try SceneProject.read(from: folder)
        guard canConvert(scene) else { throw WallpaperEngineProjectFolder.Problem.noScene }
        let project = folder.appendingPathComponent(WallpaperEngineProjectFolder.folderName, isDirectory: true)
        try? FileManager.default.removeItem(at: project)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let width = Double(size.width), height = Double(size.height)
        var document = WallpaperEngineDocument.empty(title: title, width: Int(width.rounded()), height: Int(height.rounded()))

        // The settings first, so that what follows them can be linked to them.
        var properties: [String: JSONValue] = [:]
        for (index, variable) in scene.variables.enumerated() {
            var property: [String: JSONValue] = ["text": .string(variable.title), "order": .number(Double(100 + index))]
            switch variable.kind {
            case .color:
                property["type"] = .string("color")
                property["value"] = .string((numbers(hex: variable.color) ?? [1, 1, 1]).map { short($0) }.joined(separator: " "))
            case .number:
                property["type"] = .string("slider")
                property["value"] = .number(variable.number)
                property["min"] = .number(variable.minimum)
                property["max"] = .number(variable.maximum)
                property["step"] = .number(variable.step)
                property["fraction"] = .bool(variable.step < 1)
            case .toggle:
                property["type"] = .string("bool")
                property["value"] = .bool(variable.isOn)
            case .text:
                property["type"] = .string("textinput")
                property["value"] = .string(variable.text)
            case .choice:
                property["type"] = .string("combo")
                property["value"] = .string(variable.text)
                property["options"] = .array(variable.options.map { .object(["label": .string($0), "value": .string($0)]) })
            }
            properties[variable.key] = .object(property)
        }
        if !properties.isEmpty {
            var general = document.project["general"] ?? .object([:])
            var all = general["properties"] ?? .object([:])
            for (name, value) in properties { all[name] = value }
            general["properties"] = all
            document.project["general"] = general
        }

        // The background.
        let background = scene.background
        let backgroundName = NSLocalizedString("Background", comment: "Name of the layer a scene made from a wallpaper starts with")
        var backgroundID: Int?
        switch background.kind {
        case .color:
            document[general: "clearcolor"] = .vector(numbers(hex: background.color) ?? [0, 0, 0])
        case .image:
            if let source = background.source, Archive.staysInside(source) {
                let picture = try WallpaperEngineProjectFolder.addPicture(folder.appendingPathComponent(source), to: project)
                let id = document.addImage(texture: picture.texture, width: picture.width, height: picture.height, name: backgroundName)
                document.cover(id, width: picture.width, height: picture.height)
                backgroundID = id
            }
            document[general: "clearcolor"] = .vector(numbers(hex: background.color) ?? [0, 0, 0])
        case .video:
            if let source = background.source, Archive.staysInside(source) {
                let url = original(of: source, in: folder)
                let video = try await WallpaperEngineVideo.prepare(url)
                let texture = try WallpaperEngineProjectFolder.addVideo(video.file, width: video.width, height: video.height, named: "background", to: project)
                let id = document.addImage(texture: texture, width: video.width, height: video.height, name: backgroundName)
                document.cover(id, width: video.width, height: video.height)
                backgroundID = id
            }
            document[general: "clearcolor"] = .vector(numbers(hex: background.color) ?? [0, 0, 0])
        case .page, .engine:
            break
        }
        if let backgroundID {
            if background.blur > 0, let blur = WallpaperEngineEffect.named("blur") {
                try document.addEffect(blur, to: backgroundID, projectFolder: project)
                document.setEffectValue(.number(min(32, background.blur)), named: "scale", effect: 0, of: backgroundID)
            }
            if background.brightness != 100 || background.contrast != 100 || background.saturation != 100 || background.hue != 0,
               let adjust = WallpaperEngineEffect.named("coloradjust") {
                try document.addEffect(adjust, to: backgroundID, projectFolder: project)
                let index = (document.object(backgroundID)?["effects"]?.arrayValue?.count ?? 1) - 1
                document.setEffectValue(.number(background.brightness / 100), named: "brightness", effect: index, of: backgroundID)
                document.setEffectValue(.number(background.contrast / 100), named: "contrast", effect: index, of: backgroundID)
                document.setEffectValue(.number(background.saturation / 100), named: "saturation", effect: index, of: backgroundID)
                document.setEffectValue(.number(background.hue / 360), named: "hue", effect: index, of: backgroundID)
            }
        }

        // The layers, the one behind first.
        for layer in scene.layers {
            let origin: [Double] = [layer.x / 100 * width, height - layer.y / 100 * height, 0]
            var id: Int?
            switch layer.kind {
            case .text:
                let made = document.addText(layer.text, font: font(layer.fontFamily), pointSize: max(4, layer.fontSize / 100 * height * 72 / 300),
                                            name: layer.name)
                document.update(made) { object in
                    object["color"] = .vector(numbers(hex: layer.color) ?? [1, 1, 1])
                    object["horizontalalign"] = .string(["left", "right"].contains(layer.alignment) ? layer.alignment : "center")
                    object["limitwidth"] = .bool(true)
                    object["maxwidth"] = .number(layer.width / 100 * width)
                    if layer.text.contains("{") {
                        object["text"] = .object(["value": .string(layer.text), "script": .string(clockScript(layer.text))])
                    }
                }
                id = made
            case .image:
                guard Archive.staysInside(layer.source) else { continue }
                let picture = try WallpaperEngineProjectFolder.addPicture(folder.appendingPathComponent(layer.source), to: project)
                let made = document.addImage(texture: picture.texture, width: picture.width, height: picture.height, name: layer.name)
                let scale = layer.width / 100 * width / Double(max(picture.width, 1))
                document.update(made) { $0["scale"] = .vector([scale, scale, 1]) }
                id = made
            case .shape:
                id = document.addSolid(color: numbers(hex: layer.fill) ?? [1, 1, 1], width: layer.width / 100 * width,
                                       height: layer.height / 100 * height, name: layer.name)
            case .code:
                continue
            }
            guard let id else { continue }
            document.update(id) { object in
                object["origin"] = .vector(origin)
                object["angles"] = .vector([0, 0, -layer.rotation * .pi / 180])
                object["alpha"] = .number(layer.opacity / 100)
                object["visible"] = .bool(layer.isVisible)
            }
            if let effect = animationEffect(layer.animation) {
                try document.addEffect(effect.effect, to: id, projectFolder: project)
                let index = (document.object(id)?["effects"]?.arrayValue?.count ?? 1) - 1
                for (name, value) in effect.values(max(layer.animationDuration, 0.1)) {
                    document.setEffectValue(value, named: name, effect: index, of: id)
                }
            }
        }

        try WallpaperEngineProjectFolder.write(document, previous: nil, to: project)
        // The scene as it was, for whoever wants it back.
        let old = folder.appendingPathComponent(SceneProject.sceneFileName)
        let kept = folder.appendingPathComponent("scene.before-wallpaper-engine.json")
        if !FileManager.default.fileExists(atPath: kept.path) {
            try? FileManager.default.copyItem(at: old, to: kept)
        }
        var cleared = scene
        cleared.layers = []
        try SceneProject.write(cleared, to: folder)
        try WallpaperEngineProjectFolder.layOut(scene: folder)
    }

    /// A video as it was before it was made WebM for Chromium.
    private static func original(of source: String, in folder: URL) -> URL {
        let original = folder.appendingPathComponent(WebMediaConverter.originalsFolderName).appendingPathComponent(source)
        return FileManager.default.fileExists(atPath: original.path) ? original : folder.appendingPathComponent(source)
    }

    /// The font of Wallpaper Engine's closest to a family the scene named.
    private static func font(_ family: String) -> String {
        let name = family.lowercased()
        if name.contains("mono") || name.contains("courier") || name.contains("menlo") { return "systemfont_consolas" }
        if name.contains("serif") && !name.contains("sans") || name.contains("times") || name.contains("georgia") { return "systemfont_georgia" }
        return "systemfont_segoeui"
    }

    /// The effect a layer's animation becomes, and its values for a round of so many seconds.
    private static func animationEffect(_ animation: String) -> (effect: WallpaperEngineEffect, values: (Double) -> [(String, JSONValue)])? {
        switch animation {
        case "pulse":
            return WallpaperEngineEffect.named("pulse").map { ($0, { [("speed", .number(1 / $0)), ("low", .number(0.7)), ("high", .number(1.2))] }) }
        case "blink":
            return WallpaperEngineEffect.named("pulse").map { ($0, { [("speed", .number(1 / $0)), ("low", .number(0)), ("high", .number(1))] }) }
        case "float":
            return WallpaperEngineEffect.named("shake").map { ($0, { [("speed", .number(1 / $0)), ("strength", .number(0.02)), ("direction", .number(Double.pi / 2))] }) }
        case "spin":
            return WallpaperEngineEffect.named("spin").map { ($0, { [("speed", .number(1 / $0))] }) }
        default:
            return nil
        }
    }

    /// A script of Wallpaper Engine's that writes a text with the time, the date and the
    /// wallpaper's settings put in, as the app's text layers do.
    static func clockScript(_ template: String) -> String {
        let literal = String(decoding: (try? JSONSerialization.data(withJSONObject: [template])) ?? Data("[\"\"]".utf8), as: UTF8.self)
        return """
        'use strict';

        const TEMPLATE = \(literal)[0];
        const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
        const DAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

        function pad(value) {
        \treturn value < 10 ? '0' + value : '' + value;
        }

        function local(date, options, fallback) {
        \ttry {
        \t\treturn date.toLocaleDateString(undefined, options);
        \t} catch (error) {
        \t\treturn fallback;
        \t}
        }

        export function update(value) {
        \tconst d = new Date();
        \treturn TEMPLATE.replace(/\\{(\\w+)\\}/g, function (whole, name) {
        \t\tswitch (name) {
        \t\tcase 'HH': return pad(d.getHours());
        \t\tcase 'H': return '' + d.getHours();
        \t\tcase 'hh': return pad(d.getHours() % 12 || 12);
        \t\tcase 'h': return '' + (d.getHours() % 12 || 12);
        \t\tcase 'mm': return pad(d.getMinutes());
        \t\tcase 'ss': return pad(d.getSeconds());
        \t\tcase 'ampm': return d.getHours() < 12 ? 'AM' : 'PM';
        \t\tcase 'weekday': return local(d, { weekday: 'long' }, DAYS[d.getDay()]);
        \t\tcase 'date': return local(d, { day: 'numeric', month: 'long' }, MONTHS[d.getMonth()] + ' ' + d.getDate());
        \t\tcase 'day': return '' + d.getDate();
        \t\tcase 'dd': return pad(d.getDate());
        \t\tcase 'month': return local(d, { month: 'long' }, MONTHS[d.getMonth()]);
        \t\tcase 'MM': return pad(d.getMonth() + 1);
        \t\tcase 'year': return '' + d.getFullYear();
        \t\tcase 'yy': return pad(d.getFullYear() % 100);
        \t\t}
        \t\tconst settings = engine.userProperties || {};
        \t\treturn name in settings ? String(settings[name]) : whole;
        \t});
        }

        """
    }

    private static func numbers(hex: String) -> [Double]? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count >= 6, let value = UInt32(text.prefix(6), radix: 16) else { return nil }
        return [Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255]
            .map { ($0 * 100_000).rounded() / 100_000 }
    }

    private static func short(_ number: Double) -> String {
        number == number.rounded() ? String(Int(number)) : String(format: "%.5f", number)
    }
}

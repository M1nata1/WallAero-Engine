import Foundation

extension SceneProject {
    /// Whether the app can play the scene in the folder by itself, without a web engine: a
    /// scene of Wallpaper Engine's on its own — no layers on top of it, no look laid over it,
    /// nothing of the user's own in its custom files. Anything more is for the scene's page.
    public static func isNativelyPlayable(_ folder: URL) -> Bool {
        guard let scene = try? read(from: folder) else { return false }
        return isNativelyPlayable(scene, in: folder)
    }

    public static func isNativelyPlayable(_ scene: WallpaperScene, in folder: URL) -> Bool {
        let background = scene.background
        guard background.kind == .engine, scene.layers.isEmpty,
              background.blur == 0, background.brightness == 100, background.contrast == 100,
              background.saturation == 100, background.hue == 0,
              FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(WallpaperEngineScene.folderName)/files.js").path)
        else { return false }
        for (name, template) in [("custom.css", customCSS), ("custom.js", customJS)] {
            guard let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) else { continue }
            if text.trimmingCharacters(in: .whitespacesAndNewlines) != template.trimmingCharacters(in: .whitespacesAndNewlines) { return false }
        }
        return true
    }
}

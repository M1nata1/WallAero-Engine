import Foundation

/// The player of Wallpaper Engine's own scenes: the script a scene's page loads to draw one as
/// its background. It is written into the folder of every scene that holds such a scene, next
/// to the runtime, and rewritten when the app has a newer one. See `WallpaperEngineScene` for
/// how a scene's files get there.
public enum WallpaperEngineRuntime {
    public static let fileName = "engine.js"

    /// The script. While the player is being worked on it can be taken from a file instead,
    /// named by `WALLAERO_ENGINE_JS`, so that a change shows without building the app.
    public static var script: String {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["WALLAERO_ENGINE_JS"],
           let text = try? String(contentsOfFile: path, encoding: .utf8) {
            return text
        }
        #endif
        return source
    }

    /// The player's files joined in the order `Player/order.txt` gives: from the app's resources
    /// (`Contents/Resources/Player`, put there by scripts/build.sh), or, for a binary run bare from
    /// the build folder and for tests, from the source folder beside this file.
    static let source: String = {
        for folder in playerFolders {
            guard let order = try? String(contentsOf: folder.appendingPathComponent("order.txt"), encoding: .utf8) else { continue }
            var script = ""
            for name in order.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) where !name.isEmpty && !name.hasPrefix("#") {
                guard let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) else {
                    fatalError("the scene player's \(name) is missing from \(folder.path)")
                }
                script += text
            }
            return script
        }
        fatalError("the scene player is missing: no Player/order.txt in the app's resources or beside the sources")
    }()

    /// One file of the player, as it is: for code that runs a part of it alone
    /// (`WallpaperEngineCurves`).
    static func file(named name: String) -> String? {
        for folder in playerFolders {
            if let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8) { return text }
        }
        return nil
    }

    static var playerFolders: [URL] {
        var folders: [URL] = []
        if let resources = Bundle.main.resourceURL { folders.append(resources.appendingPathComponent("Player", isDirectory: true)) }
        folders.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Player", isDirectory: true))
        return folders
    }
}

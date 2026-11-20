import Foundation

/// The scene's JSON files read by the app for the player: the scene, its models, materials,
/// effects and particles, by the rules of Wallpaper Engine's format that are the app's to keep
/// (docs/we-format.md: whatever does not change while a scene plays). The player is handed them
/// in place of the files as written, and does not keep those rules itself.
///
/// The scene's table (`WallpaperEngineSceneData`) stays as it was laid out; what is read is
/// worked out from it whenever a scene starts, and from what the editor changes as it changes it.
public enum WallpaperEngineSceneReading {
    /// The JSON files among `files` (names as the table has them), read; a file that does not
    /// read is left out, and the player finds it as written.
    public static func read(_ files: [String: String]) -> [String: String] {
        var read: [String: String] = [:]
        for (name, text) in files where name.hasSuffix(".json") {
            if let json = WallpaperEngineJSON(text: text) { read[name] = json.text }
        }
        return read
    }

    /// What is read of a laid-out scene's table, as a JSON object of names and texts, for the
    /// player to put over the files as written. Nil when the table has no files to read.
    public static func readTable(_ table: Data) -> String? {
        guard case .object(let members)? = WallpaperEngineJSON.member("files", ofObjectIn: table) else { return nil }
        var out: [(key: String, value: WallpaperEngineJSON)] = []
        for member in members where WallpaperEngineJSON.unescaped(member.key).hasSuffix(".json") {
            guard let text = member.value.stringValue, let json = WallpaperEngineJSON(text: text) else { continue }
            out.append((member.key, .string(WallpaperEngineJSON.escaped(json.text))))
        }
        return WallpaperEngineJSON.object(out).text
    }

    /// The script that puts what is read over the files of the table the page was handed.
    public static func script(putting read: String) -> String {
        "Object.assign(\(PlayerEnvironment.scene).files, \(read));\n"
    }
}

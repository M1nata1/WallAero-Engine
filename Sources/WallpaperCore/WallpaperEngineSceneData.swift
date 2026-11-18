import Foundation

/// The data the player plays a laid-out scene from: `engine/files.json`, a table of the scene's
/// texts and of the files it names (see `WallpaperEngineScene`). It is data only; neither the
/// player nor any other code lies in a scene's folder. The player comes from the app.
///
/// The page of a scene in Chromium still asks for `engine/files.js` and `engine.js` (its runtime
/// loads them as scripts, the way a page opened from a file can): Chromium is handed the table
/// with the player's name for it before it, and the app's own player, by `CEFHost`.
///
/// Scenes laid out before v4.0 had the table as a script, `engine/files.js`, and a copy of the
/// player, `engine.js`, in their folders. `migrate` writes `files.json` beside them; the old
/// files go at the following launch, once `files.json` has been read.
public enum WallpaperEngineSceneData {
    /// The table's file, in the scene's `engine` folder.
    public static let fileName = "files.json"
    /// What the table is written as: `"format"` in it. A table of an earlier format is made
    /// anew from the scene's project; one of a later format is refused, not played wrong.
    public static let format = 1

    /// Before v4.0: the table as a script, and the copy of the player.
    static let oldScriptName = "files.js"
    static let oldPlayerName = "engine.js"
    /// What the script put before the table, and after it.
    static let scriptPrefix = Data("window.wallaeroEngineScene = ".utf8)

    public static func url(scene folder: URL) -> URL {
        folder.appendingPathComponent(WallpaperEngineScene.folderName).appendingPathComponent(fileName)
    }

    static func oldScriptURL(scene folder: URL) -> URL {
        folder.appendingPathComponent(WallpaperEngineScene.folderName).appendingPathComponent(oldScriptName)
    }

    /// Whether the scene has a table, of any format, to play from.
    public static func exists(scene folder: URL) -> Bool {
        let files = FileManager.default
        return files.fileExists(atPath: url(scene: folder).path) || files.fileExists(atPath: oldScriptURL(scene: folder).path)
    }

    public enum Problem: Error, Equatable {
        /// The scene has no table.
        case missing
        /// The table is of a later format than this app reads.
        case newer(Int)
        case unreadable
    }

    /// The table as JSON text: from `files.json`, or from the script of before v4.0.
    public static func read(scene folder: URL) -> Result<Data, Problem> {
        if let data = try? Data(contentsOf: url(scene: folder), options: .alwaysMapped) {
            let written = formatOf(data)
            if written > format { return .failure(.newer(written)) }
            return .success(data)
        }
        guard let script = try? Data(contentsOf: oldScriptURL(scene: folder), options: .alwaysMapped) else { return .failure(.missing) }
        guard let json = tableOfScript(script) else { return .failure(.unreadable) }
        return .success(json)
    }

    /// The table as an object, for whoever looks into it in Swift.
    public static func table(scene folder: URL) -> [String: Any]? {
        guard case .success(let data) = read(scene: folder) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// The table written as `files.json`, with its format.
    static func write(_ table: [String: Any], scene folder: URL) throws {
        let json = try JSONSerialization.data(withJSONObject: table, options: [.sortedKeys])
        try stamped(json).write(to: url(scene: folder), options: .atomic)
    }

    /// A table with its format put first, where `formatOf` reads it; the rest as it was.
    static func stamped(_ json: Data) -> Data {
        var data = Data("{\"format\":\(format)".utf8)
        let body = json.dropFirst()
        if body.first(where: { ![UInt8(ascii: " "), UInt8(ascii: "\n")].contains($0) }) != UInt8(ascii: "}") {
            data.append(UInt8(ascii: ","))
        }
        data.append(body)
        return data
    }

    /// The format a table says it is written in, read from its start, where `stamped` puts it;
    /// tables of before v4.0 have none.
    static func formatOf(_ data: Data) -> Int {
        let head = String(decoding: data.prefix(64), as: UTF8.self)
        guard let range = head.range(of: #"^\{\s*"format"\s*:\s*(\d+)"#, options: .regularExpression) else { return 0 }
        return Int(head[range].filter(\.isNumber)) ?? 0
    }

    /// The table of a script of before v4.0: what lies between the prefix and the closing `;`.
    static func tableOfScript(_ script: Data) -> Data? {
        guard script.starts(with: scriptPrefix) else { return nil }
        var end = script.endIndex
        while end > script.startIndex, [UInt8(ascii: "\n"), UInt8(ascii: " "), UInt8(ascii: ";")].contains(script[end - 1]) { end -= 1 }
        let json = script[(script.startIndex + scriptPrefix.count)..<end]
        guard json.first == UInt8(ascii: "{"), json.last == UInt8(ascii: "}") else { return nil }
        return Data(json)
    }

    // MARK: - From before v4.0

    /// The scenes of a library laid out before v4.0, by their folders: what is old is taken out
    /// of those whose `files.json` an earlier launch wrote and that reads, and `files.json` is
    /// written for those that have none yet. The old files of a scene are removed only at the
    /// launch after the one that wrote its `files.json`: the removal is the first step, the
    /// writing the second. Returns how many were written and how many cleared.
    @discardableResult
    public static func migrate(scenes folders: [URL]) -> (written: Int, cleared: Int) {
        var written = 0, cleared = 0
        for folder in folders where FileManager.default.fileExists(atPath: folder.appendingPathComponent(WallpaperEngineScene.folderName).path) {
            if clearOldFiles(scene: folder) { cleared += 1 }
        }
        for folder in folders where FileManager.default.fileExists(atPath: folder.appendingPathComponent(WallpaperEngineScene.folderName).path) {
            if (try? writeFromScript(scene: folder)) == true { written += 1 }
        }
        return (written, cleared)
    }

    /// Writes `files.json` from the script of before v4.0, beside it; true if it did.
    static func writeFromScript(scene folder: URL) throws -> Bool {
        let files = FileManager.default
        guard !files.fileExists(atPath: url(scene: folder).path),
              let script = try? Data(contentsOf: oldScriptURL(scene: folder), options: .alwaysMapped),
              let json = tableOfScript(script)
        else { return false }
        try stamped(json).write(to: url(scene: folder), options: .atomic)
        return true
    }

    /// Removes `files.js` and `engine.js` from a scene whose `files.json` reads; true if it did.
    static func clearOldFiles(scene folder: URL) -> Bool {
        let files = FileManager.default
        let old = [oldScriptURL(scene: folder), folder.appendingPathComponent(oldPlayerName)].filter { files.fileExists(atPath: $0.path) }
        guard !old.isEmpty, let data = try? Data(contentsOf: url(scene: folder)), formatOf(data) >= 1,
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
        else { return false }
        for url in old { try? files.removeItem(at: url) }
        return true
    }
}

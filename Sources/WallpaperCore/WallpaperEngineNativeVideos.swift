import Foundation

extension WallpaperEngineProjectFolder {
    /// The videos a laid-out scene plays, as files AVFoundation plays, by the address the scene's
    /// table gives them (`engine/tex/….mp4`). For Chromium those were made WebM, which
    /// AVFoundation does not open; the MP4 each came as is taken out of the scene's own texture
    /// in `project/` once, into the hidden `.native-videos/` (which the WebM conversion leaves
    /// alone), and decoded by the Mac's media engine.
    public static func nativeVideos(scene folder: URL) -> [String: URL] {
        let table = folder.appendingPathComponent("\(WallpaperEngineScene.folderName)/\(WallpaperEngineScene.filesName)")
        guard let script = try? String(contentsOf: table, encoding: .utf8), let start = script.firstIndex(of: "{"),
              let json = try? JSONSerialization.jsonObject(with: Data(script[start...].trimmingCharacters(in: CharacterSet(charactersIn: ";\n ")).utf8)) as? [String: Any],
              let textures = json["textures"] as? [String: Any]
        else {
            return [:]
        }
        let files = FileManager.default
        let project = folder.appendingPathComponent(folderName)
        let originals = folder.appendingPathComponent(".native-videos")
        // The project's textures by their names, as the table has them: without case.
        var projectTextures: [String: URL] = [:]
        if let walker = files.enumerator(at: project, includingPropertiesForKeys: nil) {
            for case let url as URL in walker where url.pathExtension.lowercased() == "tex" {
                let relative = String(url.path.dropFirst(project.path.count + 1))
                projectTextures[(relative as NSString).deletingPathExtension.lowercased()] = url
            }
        }
        var result: [String: URL] = [:]
        for (key, value) in textures {
            guard let entry = value as? [String: Any], let address = entry["video"] as? String else { continue }
            let laidOut = folder.appendingPathComponent(address)
            if let head = try? FileHandle(forReadingFrom: laidOut).read(upToCount: 12), head.count == 12, head[4..<8] == Data("ftyp".utf8) {
                result[address] = laidOut
                continue
            }
            let original = originals.appendingPathComponent(laidOut.lastPathComponent)
            if files.fileExists(atPath: original.path) {
                result[address] = original
                continue
            }
            guard let source = projectTextures[key.lowercased()], let data = try? Data(contentsOf: source),
                  let video = WallpaperEngineTexture.texture(from: data)?.video else { continue }
            try? files.createDirectory(at: originals, withIntermediateDirectories: true)
            if (try? video.file.write(to: original)) != nil { result[address] = original }
        }
        return result
    }
}

import CryptoKit
import Foundation

/// What glslang and SPIRV-Cross made of a scene's shaders, kept on disk by the shaders' text:
/// a scene asks the same of them every time it starts, and working it out is most of starting.
enum ShaderCache {
    /// Changed whenever what is kept would come out differently.
    private static let version = "2"

    private static let folder: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let folder = caches.appendingPathComponent("WallAeroEngine/Shaders", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    private static func file(_ parts: [String]) -> URL? {
        var hash = SHA256()
        for part in [version] + parts {
            hash.update(data: Data(part.utf8))
            hash.update(data: Data([0]))
        }
        let name = hash.finalize().map { String(format: "%02x", $0) }.joined()
        return folder?.appendingPathComponent(name)
    }

    /// The answer kept for these texts, or `make`'s, kept for next time.
    static func answer(_ parts: [String], make: () -> String?) -> String? {
        let file = file(parts)
        if let file, let kept = try? String(contentsOf: file, encoding: .utf8) { return kept }
        guard let made = make() else { return nil }
        if let file { try? made.write(to: file, atomically: true, encoding: .utf8) }
        return made
    }
}

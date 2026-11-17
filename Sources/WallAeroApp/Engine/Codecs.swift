import Foundation
import WallpaperCore

/// The encoders that turn web wallpapers' videos into WebM (see `WebMediaConverter`).
enum Codecs {
    static let libraryName = "libWallAeroCodecs.dylib"

    /// Tells the converter where the encoders are: in the app's Frameworks folder, or, for a
    /// binary run from the package in development, in `build/codecs` (see scripts/codecs.sh).
    static func configure() {
        let files = FileManager.default
        // For a developer's measurements with a release build outside the app.
        if let given = ProcessInfo.processInfo.environment["WALLAERO_CODECS"], files.fileExists(atPath: given) {
            WebMediaConverter.libraryURL = URL(fileURLWithPath: given)
            return
        }
        if let bundled = Bundle.main.privateFrameworksURL?.appendingPathComponent(libraryName),
           files.fileExists(atPath: bundled.path) {
            WebMediaConverter.libraryURL = bundled
            return
        }
        #if DEBUG
        // Sources/WallAeroEngine/Engine/Codecs.swift → the package → build/codecs.
        let built = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/codecs/\(libraryName)")
        if files.fileExists(atPath: built.path) {
            WebMediaConverter.libraryURL = built
        }
        #endif
    }
}

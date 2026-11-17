// swift-tools-version:5.9
import Foundation
import PackageDescription

// The test host reaches into the app (`@testable import WallAeroApp`), which takes the app's
// code compiled for testing. The app that is shipped is built without: scripts/build.sh --dist
// sets WALLAERO_DIST and builds only the app.
let forTests: [SwiftSetting] = ProcessInfo.processInfo.environment["WALLAERO_DIST"] == nil
    ? [.unsafeFlags(["-enable-testing"])] : []

let package = Package(
    name: "WallAeroEngine",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WallAeroEngine", targets: ["WallAeroEngine"])
    ],
    targets: [
        // The VP9 and Opus encoders (libvpx, libopus), loaded from the app when needed.
        .target(
            name: "CCodecs",
            path: "Sources/CCodecs",
            exclude: ["vpx/LICENSE", "opus/COPYING"]
        ),
        // Shaders of WebGL made over for Metal: glslang and SPIRV-Cross, as they come (see
        // VERSIONS.txt), with a small bridge.
        .target(
            name: "ShaderTranslation",
            path: "Sources/ShaderTranslation",
            exclude: ["glslang/LICENSE.txt", "glslang/LICENSES", "SPIRV-Cross/LICENSE", "VERSIONS.txt"],
            cxxSettings: [
                .headerSearchPath("glslang"),
                .headerSearchPath("SPIRV-Cross"),
                .define("ENABLE_OPT", to: "0"),
                .define("GLSLANG_OSINCLUDE_UNIX"),
                // Their own warnings, not the app's.
                .unsafeFlags(["-w"]),
            ]
        ),
        // Wallpaper Engine's scenes drawn with Metal: the scene player run in JavaScriptCore,
        // its WebGL calls carried out natively.
        .target(
            name: "MetalScene",
            dependencies: ["ShaderTranslation", "WallpaperCore"],
            path: "Sources/MetalScene",
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("JavaScriptCore"),
                .linkedLibrary("c++"),
            ]
        ),
        // Media import, conversion and the wallpaper library. No UI code.
        // The scene player's own files (Player/) are not SwiftPM resources: scripts/build.sh puts
        // them in the app's Resources, where WallpaperEngineRuntime reads them.
        .target(
            name: "WallpaperCore",
            dependencies: ["CCodecs"],
            path: "Sources/WallpaperCore",
            exclude: ["Player"]
        ),
        // Thin C wrapper over the private CoreGraphics cursor API (CGS).
        .target(
            name: "CGSCursor",
            path: "Sources/CGSCursor",
            linkerSettings: [.linkedFramework("ApplicationServices")]
        ),
        // Windows .ani/.cur decoding and the system-wide cursor theme engine.
        .target(
            name: "CursorCore",
            dependencies: ["CGSCursor"],
            path: "Sources/CursorCore"
        ),
        // The C++ side of Chromium Embedded Framework (CEF), as it comes with CEF: its headers
        // and the wrapper that turns its C interface into C++ classes. The framework itself is
        // not linked: it is loaded when the app starts (see scripts/cef.sh).
        .target(
            name: "CEFWrapper",
            path: "Sources/CEFWrapper",
            exclude: ["LICENSE.txt"],
            cxxSettings: [
                .headerSearchPath("."),
                .define("WRAPPING_CEF_SHARED"),
            ]
        ),
        // Web pages drawn by Chromium: the browser side for the app, the page side for the helper.
        .target(
            name: "CEFHost",
            dependencies: ["CEFWrapper"],
            path: "Sources/CEFHost",
            cxxSettings: [
                .headerSearchPath("../CEFWrapper"),
                .unsafeFlags(["-fobjc-arc"]),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
            ]
        ),
        // The program Chromium runs its other processes with (pages, graphics, sound…).
        .executableTarget(
            name: "WallAeroHelper",
            dependencies: ["CEFHost"],
            path: "Sources/WallAeroHelper",
            cxxSettings: [.headerSearchPath("../CEFWrapper"), .headerSearchPath("../CEFHost")]
        ),
        // The menu bar app: desktop windows, playback engine and SwiftUI screens.
        // All of the app, but for its start.
        .target(
            name: "WallAeroApp",
            dependencies: ["WallpaperCore", "CursorCore", "CEFHost", "MetalScene"],
            path: "Sources/WallAeroApp",
            swiftSettings: forTests
        ),
        // The app that is shipped: only its start.
        .executableTarget(
            name: "WallAeroEngine",
            dependencies: ["WallAeroApp"],
            path: "Sources/WallAeroEngine"
        ),
        // The app with the developer's helpers and tests (scripts/build.sh puts it next to the
        // app's binary; --dist leaves it out).
        .executableTarget(
            name: "WallAeroTestHost",
            dependencies: ["WallAeroApp", "WallpaperCore", "MetalScene", "CEFHost"],
            path: "Sources/WallAeroTestHost"
        ),
        // Command-line helper to apply or reset a cursor theme, reusing the app's engine.
        .executableTarget(
            name: "cursorctl",
            dependencies: ["CursorCore"],
            path: "Sources/cursorctl"
        ),
        .testTarget(
            name: "WallpaperCoreTests",
            dependencies: ["WallpaperCore"],
            path: "Tests/WallpaperCoreTests"
        ),
        // The scene player's own tests (Tests/PlayerTests, for node) and its shaders through glslang.
        .testTarget(
            name: "PlayerScriptTests",
            dependencies: ["WallpaperCore", "ShaderTranslation"],
            path: "Tests/PlayerScriptTests",
            linkerSettings: [.linkedFramework("JavaScriptCore"), .linkedLibrary("c++")]
        ),
        .testTarget(
            name: "CursorCoreTests",
            dependencies: ["CursorCore"],
            path: "Tests/CursorCoreTests"
        ),
    ],
    cxxLanguageStandard: .cxx20
)

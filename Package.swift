// swift-tools-version:5.9
import PackageDescription

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
        // Media import, conversion and the wallpaper library. No UI code.
        .target(
            name: "WallpaperCore",
            dependencies: ["CCodecs"],
            path: "Sources/WallpaperCore"
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
        .executableTarget(
            name: "WallAeroEngine",
            dependencies: ["WallpaperCore", "CursorCore", "CEFHost"],
            path: "Sources/WallAeroEngine"
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
        .testTarget(
            name: "CursorCoreTests",
            dependencies: ["CursorCore"],
            path: "Tests/CursorCoreTests"
        ),
    ],
    cxxLanguageStandard: .cxx20
)

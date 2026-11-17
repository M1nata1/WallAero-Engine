import AppKit
@testable import WallAeroApp
import WallpaperCore

// The test host: the app with the developer's helpers and tests, which the app that is shipped
// has none of. It lies next to the app's own binary (Contents/MacOS/WallAeroTestHost), so that
// it runs with the same resources; started with no options it is the app. The options are
// those the app took before they moved here, so that the scripts run as they did.

let arguments = CommandLine.arguments

/// A helper that needs neither the library nor the rest of the app; true when one was asked for.
@MainActor
func runAlone() -> Bool {
    if let index = arguments.firstIndex(of: "--convert-media"), index + 2 < arguments.count {
        // Turns one video or sound into WebM as the library would.
        let source = URL(fileURLWithPath: arguments[index + 1])
        let destination = URL(fileURLWithPath: arguments[index + 2])
        Task {
            let started = Date()
            do {
                print("needs conversion: \(await WebMediaConverter.needsConversion(source))")
                try await WebMediaConverter.convert(source, to: destination)
                print(String(format: "converted in %.1f s", Date().timeIntervalSince(started)))
            } catch {
                print("failed: \(error)")
            }
            exit(0)
        }
        return true
    }
    if let request = ScreenshotMode.renderRequest {
        ScreenshotMode.renderWeb(request)
        return true
    }
    if let request = ScreenshotMode.editRequest {
        ScreenshotMode.editScene(request)
        return true
    }
    if let target = ScreenshotMode.energyTestTarget {
        ScreenshotMode.energyTest(target)
        return true
    }
    // Lays a scene's Wallpaper Engine project out anew, as the app does after an update, for a
    // copy of a scene to be tested.
    if let index = arguments.firstIndex(of: "--lay-out"), index + 1 < arguments.count {
        let folder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        do {
            try WallpaperEngineProjectFolder.layOut(scene: folder)
            print("laid out \(folder.path)")
            exit(0)
        } catch {
            print("cannot lay out: \(error)")
            exit(1)
        }
    }
    if let request = NativeSceneTest.request {
        NativeSceneTest.run(request)
        return true
    }
    if let request = ScreenshotMode.engineTest {
        ScreenshotMode.runEngineTest(request)
        return true
    }
    if let seconds = ScreenshotMode.coverTestSeconds {
        ScreenshotMode.coverTest(seconds)
        return true
    }
    if let folder = ScreenshotMode.settingsTestFolder {
        ScreenshotMode.settingsTest(folder)
        return true
    }
    if let target = ScreenshotMode.readyTestTarget {
        ScreenshotMode.readyTest(target)
        return true
    }
    if let seconds = ScreenshotMode.pointerTestSeconds {
        ScreenshotMode.pointerTest(seconds: seconds)
        return true
    }
    if let request = ScreenshotMode.attachTest {
        ScreenshotMode.runAttachTest(request)
        return true
    }
    if let folder = ScreenshotMode.steamTestFolder {
        ScreenshotMode.steamTest(folder)
        return true
    }
    if let request = ScreenshotMode.importTest {
        ScreenshotMode.runImportTest(request)
        return true
    }
    if let seconds = ScreenshotMode.soundTestSeconds {
        ScreenshotMode.soundTest(seconds: seconds)
        return true
    }
    return false
}

MainActor.assumeIsolated {
    Launch.isHelper = arguments.dropFirst().contains { $0.hasPrefix("--") }
    Launch.asksPlayers = !Launch.isHelper || arguments.contains("--ask-players")
    Launch.libraryFolder = ScreenshotMode.libraryFolder
    Launch.alone = runAlone
    if let directory = ScreenshotMode.outputDirectory {
        Launch.remembers = false
        Launch.instead = { parts in
            if arguments.contains("--select-test") {
                // The library's own window and menu, to check selecting several wallpapers and
                // deleting them.
                parts.showMenus()
                ScreenshotMode.selectTest(windows: parts.windows, library: parts.library, in: directory)
            } else {
                ScreenshotMode.run(to: directory, library: parts.library, preferences: parts.preferences,
                                   manager: parts.manager, importer: parts.importer, workshop: parts.workshop,
                                   cursorSettings: parts.cursorSettings)
            }
        }
    }
    if let url = ScreenshotMode.desktopPictureURL {
        Launch.afterStart = { parts in ScreenshotMode.pictureDesktop(of: parts.manager, to: url) }
    }
    AppDelegate.launch()
}

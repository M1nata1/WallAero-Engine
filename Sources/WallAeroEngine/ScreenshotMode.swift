import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers
import WallpaperCore

/// Renders the main window to PNG files for the README (`scripts/screenshots.sh`): as it opens,
/// with the settings of a wallpaper at its side, and with the app's own settings there:
///
///     "build/WallAero Engine.app/Contents/MacOS/WallAeroEngine" --screenshots docs/screenshots
///
/// It runs as a separate process next to the copy in use: it starts no wallpaper and no menu bar
/// icon, and only reads the library and settings. ScreenCaptureKit lets an app capture its own
/// windows without the Screen Recording permission (macOS 14.4+); older systems fall back to
/// drawing the window's views.
@MainActor
enum ScreenshotMode {
    static var outputDirectory: URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--screenshots"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    /// `--library <folder>`, with `--screenshots`: the library to picture instead of the user's.
    static var libraryFolder: URL? {
        guard outputDirectory != nil else { return nil }
        return values(of: "--library").last.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func run(
        to directory: URL,
        library: WallpaperLibrary,
        preferences: Preferences,
        manager: WallpaperManager,
        importer: ImportCoordinator,
        workshop: WorkshopStore,
        cursorSettings: CursorSettings
    ) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        applyRequestedAppearance()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // The first picture shows the settings of a wallpaper: the first of the library, or the
        // one `--select-wallpaper <number>` names. The second shows the app's own settings, or
        // the wallpaper's again with `--settings-tab wallpaper`.
        let state = MainWindowState(defaults: nil)
        let number = values(of: "--select-wallpaper").last.flatMap(Int.init) ?? 1
        if library.items.indices.contains(number - 1) {
            state.selection = library.items[number - 1].id
        }
        let secondTab = values(of: "--settings-tab").last.flatMap(MainWindowState.SettingsTab.init(rawValue:)) ?? .general
        // `--search <text>` and `--tag <name>`, which may be given several times, show the
        // library as it is with that typed into the search field and those tags ticked.
        state.searchText = values(of: "--search").last ?? ""
        state.selectedTags = Set(values(of: "--tag"))
        // `--kind <scene|video|web|image>` and `--order <newest|oldest|name>` likewise.
        state.kindFilter = values(of: "--kind").last.flatMap(MainWindowState.KindFilter.init(rawValue:)) ?? .all
        state.libraryOrder = values(of: "--order").last.flatMap(WallpaperOrder.init(rawValue:)) ?? .newest
        // `--show-tags` drops the list of tags down for the first picture.
        let showsTags = CommandLine.arguments.contains("--show-tags")
        let mainView = MainView(actions: LibraryActions(addFiles: {}))
            .environmentObject(library)
            .environmentObject(manager)
            .environmentObject(importer)
            .environmentObject(workshop)
            .environmentObject(preferences)
            .environmentObject(cursorSettings)
            .environmentObject(state)

        // The second picture has the settings open, scrolled to their end, where the cursors are
        // (`--settings-top` leaves them at the top, to check the first sections, and
        // `--settings-end` scrolls a wallpaper's settings to their end as well).
        let showsEnd = CommandLine.arguments.contains("--settings-end")
            || (!CommandLine.arguments.contains("--settings-top") && secondTab == .general)
        Task {
            // `--switch-sections` goes between the parts of the window and back.
            if CommandLine.arguments.contains("--switch-sections") {
                await switchSections(AnyView(mainView), state: state, workshop: workshop, in: directory)
                NSApp.terminate(nil)
                return
            }
            // `--import-cancel <file>` imports it into the library given as a Workshop item is,
            // and stops that `--import-cancel-after <seconds>` later, saying what is left.
            if let source = values(of: "--import-cancel").last {
                setlinebuf(stdout)
                let id = UUID()
                let started = Date()
                var isStopped = false
                if let seconds = values(of: "--import-cancel-after").last.flatMap(Double.init) {
                    Task {
                        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                        guard let job = importer.jobs.first(where: { $0.id == id }) else { return }
                        isStopped = true
                        print("stopping at \(Int(job.progress * 100))%, converting: \(job.isConverting)")
                        importer.cancel(id)
                    }
                }
                let added = await importer.importDownload(URL(fileURLWithPath: source), title: "Test", id: id) { part in
                    print(String(format: "%.1f s: %d%%", Date().timeIntervalSince(started), Int(part * 100)))
                }
                let folders = (try? FileManager.default.contentsOfDirectory(atPath: library.rootURL.appendingPathComponent("Web").path)) ?? []
                print("stopped: \(isStopped) after \(Int(Date().timeIntervalSince(started))) s; added \(added.count); "
                    + "the library has \(library.items.count), Web holds \(folders.count); failures \(importer.failures.count)")
                NSApp.terminate(nil)
                return
            }
            // `--workshop` pictures the Steam Workshop's part of the window, as Steam lists it
            // now, `--workshop-sign-in` what it asks for signing in, `--workshop-select <n>` the
            // panel of the n-th item of the list, `--workshop-general` the app's settings there,
            // `--workshop-progress` tiles on their way and a click on one, with
            // `--workshop-cross` as they look under the pointer; `--workshop-tag <tag>` ticks a
            // tag, `--workshop-tags` opens the list of them and `--workshop-tags-click` clicks there.
            if CommandLine.arguments.contains("--workshop") {
                state.section = .workshop
                state.settingsTab = CommandLine.arguments.contains("--workshop-general") ? .general : .wallpaper
                workshop.showsSignIn = CommandLine.arguments.contains("--workshop-sign-in")
                // Steam takes a few seconds to list them, and more for their pictures.
                workshop.query.search = values(of: "--search").last ?? ""
                workshop.query.setTags(Set(values(of: "--workshop-tag")))
                workshop.showsTagFilter = CommandLine.arguments.contains("--workshop-tags")
                workshop.reload()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if CommandLine.arguments.contains("--workshop-progress") {
                    WorkshopRingLook.showsCross = CommandLine.arguments.contains("--workshop-cross")
                    for (item, phase) in zip(workshop.items, [WorkshopStore.Download.Phase.downloading(0.42), .adding(0.73), .waiting, .stopping, .downloading(0)]) {
                        workshop.show(phase, of: item)
                    }
                    let queued = workshop.downloads.count
                    await shoot(AnyView(mainView), title: "WallAero Engine", size: NSSize(width: 1420, height: 700),
                                to: directory.appendingPathComponent("workshop.png"), waiting: 4) { window in
                        // The third tile is in the queue, so its ring takes it off.
                        click(NSPoint(x: 614, y: 187), in: window)
                        print("the ring " + (workshop.downloads.count < queued ? "cancelled" : "did NOT cancel"))
                    }
                    NSApp.terminate(nil)
                    return
                }
                if CommandLine.arguments.contains("--workshop-click") {
                    // The app's own window, which makes room for the panel at its side.
                    let windows = WindowManager(state: state, remembersFrames: false, main: { AnyView(mainView) })
                    windows.showWorkshop()
                    if let window = windows.libraryWindow {
                        var frame = window.frame
                        frame.size.width = 1420
                        window.setFrame(frame, display: true)
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        await clickWorkshopButtons(in: window, store: workshop, state: state, in: directory)
                    }
                    NSApp.terminate(nil)
                    return
                }
                if let index = values(of: "--workshop-select").last.flatMap(Int.init), workshop.items.indices.contains(index) {
                    workshop.selected = workshop.items[index]
                }
                let clicksTags = CommandLine.arguments.contains("--workshop-tags-click")
                await shoot(AnyView(mainView), title: "WallAero Engine",
                            size: NSSize(width: values(of: "--workshop-width").last.flatMap(Double.init) ?? 1180, height: 700),
                            to: directory.appendingPathComponent("workshop.png"), waiting: 12) { window in
                    if workshop.selected != nil {
                        Task {
                            try? await Task.sleep(nanoseconds: 8_000_000_000)
                            printPreviewFrames(in: window)
                        }
                    }
                    if clicksTags {
                        Task { await clickTagList(in: window, store: workshop) }
                    }
                }
                NSApp.terminate(nil)
                return
            }
            if let seconds = values(of: "--watch-theme").last.flatMap(Int.init) {
                state.showsSettings = true
                await watchTheme(AnyView(mainView), seconds: seconds, in: directory)
                NSApp.terminate(nil)
                return
            }
            if CommandLine.arguments.contains("--toggle-settings") {
                await toggleSettings(AnyView(mainView), state: state, in: directory)
                NSApp.terminate(nil)
                return
            }
            state.showsSettings = true
            state.settingsTab = .wallpaper
            await shoot(AnyView(mainView), title: "WallAero Engine", size: NSSize(width: 1180, height: 700),
                        to: directory.appendingPathComponent("library.png")) { window in
                scrollSettings(in: window, toEnd: false)
                state.showsTagFilter = showsTags
            }
            state.showsTagFilter = false
            state.settingsTab = secondTab
            await shoot(AnyView(mainView), title: "WallAero Engine", size: NSSize(width: 1180, height: 760),
                        to: directory.appendingPathComponent("settings.png")) { window in
                if showsEnd {
                    scrollSettings(in: window, toEnd: true)
                }
            }
            NSApp.terminate(nil)
        }
    }

    /// `--select-test`, with `--screenshots <folder>` and `--library <folder>`: opens the library
    /// with the app's own menu and does to it what a user would with the mouse and the keys —
    /// a click, a click with Command, one with Shift, Command-A, the Delete key, the button
    /// that confirms — saying after each how many wallpapers are selected and how many there
    /// are, and taking pictures (`select-1.png`, …). **It deletes wallpapers**, so it only
    /// works on a library named for it, never on the one in use.
    static func selectTest(windows: WindowManager, library: WallpaperLibrary, in directory: URL) {
        guard libraryFolder != nil else {
            print("--select-test deletes wallpapers: name a library for it with --library <folder>")
            exit(2)
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        applyRequestedAppearance()
        Task {
            // Without the settings at its side the window has five wallpapers in a row.
            windows.state.showsSettings = false
            windows.showLibrary()
            guard let window = windows.libraryWindow else { exit(1) }
            let state = windows.state
            var step = 0
            @MainActor func pause(_ seconds: Double = 0.5) async {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            @MainActor func report(_ what: String) async {
                await pause()
                step += 1
                let names = library.items.filter { state.picked.ids.contains($0.id) }.map(\.name).joined(separator: ", ")
                print("\(step). \(what): \(state.picked.ids.count) selected of \(library.items.count) [\(names)]; "
                    + "asked to confirm: \(window.attachedSheet != nil); keys go to \(window.firstResponder.map { String(describing: type(of: $0)) } ?? "nothing")"
                    + "\(window.isKeyWindow ? "" : ", the window is not the one in use")")
                var image: CGImage?
                if #available(macOS 14.4, *) {
                    image = try? await captureWithScreenCaptureKit(window)
                }
                if let image = image ?? drawViews(of: window) {
                    write(image, to: directory.appendingPathComponent("select-\(step).png"))
                }
            }
            /// The middle of a wallpaper's picture, counted along the first row.
            @MainActor func tile(_ number: Int) -> NSPoint {
                let top = window.contentLayoutRect.maxY - CGFloat(values(of: "--grid-top").last.flatMap(Double.init) ?? 60)
                return NSPoint(x: 16 + LibraryView.tileWidth / 2 + CGFloat(number - 1) * (LibraryView.tileWidth + 16), y: top - 16 - 60)
            }
            /// The helper's window has to be the one in use for what is done to it to count,
            /// and someone at the Mac may have clicked elsewhere meanwhile.
            @MainActor func comeForward() async {
                guard !window.isKeyWindow, window.attachedSheet == nil else { return }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                await pause(0.4)
            }
            @MainActor func click(at point: NSPoint, _ keys: NSEvent.ModifierFlags = []) async {
                await comeForward()
                for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let event = NSEvent.mouseEvent(with: kind, location: point, modifierFlags: keys,
                                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                      context: nil, eventNumber: 0, clickCount: 1, pressure: kind == .leftMouseDown ? 1 : 0) {
                        NSApp.postEvent(event, atStart: false)
                    }
                    await pause(0.08)
                }
            }
            @MainActor func press(_ characters: String, code: UInt16, _ keys: NSEvent.ModifierFlags = []) async {
                await comeForward()
                for kind in [NSEvent.EventType.keyDown, .keyUp] {
                    if let event = NSEvent.keyEvent(with: kind, location: .zero, modifierFlags: keys,
                                                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                    context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                                    isARepeat: false, keyCode: code) {
                        NSApp.postEvent(event, atStart: false)
                    }
                    await pause(0.08)
                }
            }
            await pause(1)
            await report("as it opens")
            await click(at: tile(1))
            await report("a click on the first")
            await click(at: tile(3), .command)
            await report("Command and a click on the third")
            await click(at: tile(4), .shift)
            await report("Shift and a click on the fourth")
            await click(at: tile(1), .command)
            await report("Command and a click on the first")
            await click(at: NSPoint(x: tile(1).x + LibraryView.tileWidth / 2 + 8, y: tile(1).y))
            await report("a click between the first and the second")
            await click(at: tile(2))
            await click(at: tile(3), .command)
            await report("the second and the third selected")
            await click(at: NSPoint(x: tile(5).x, y: 120))
            await report("a click below the wallpapers")
            await press("a", code: 0, .command)
            await report("Command-A")
            await click(at: tile(2), .command)
            await report("Command and a click on the second")
            // A key equivalent names the Delete key by the backspace character; an event made
            // here has to carry the same one to be matched.
            await press("\u{8}", code: 51)
            await report("the Delete key")
            if window.attachedSheet == nil {
                await press("\u{8}", code: 51, .command)
                await report("Command and the Delete key")
            }
            // The button that confirms is the one that is not Cancel.
            @MainActor func buttons(in view: NSView) -> [NSButton] {
                ((view as? NSButton).map { [$0] } ?? []) + view.subviews.flatMap(buttons(in:))
            }
            if let sheet = window.attachedSheet, let content = sheet.contentView {
                let all = buttons(in: content)
                print("   the sheet's buttons: \(all.map(\.title))")
                all.first { $0.keyEquivalent != "\u{1b}" && !$0.title.isEmpty && $0.hasDestructiveAction }?.performClick(nil)
                    ?? all.first { $0.keyEquivalent != "\u{1b}" && !$0.title.isEmpty }?.performClick(nil)
            }
            await report("confirmed")
            // In a text the Delete key deletes letters, whatever is selected in the library.
            await click(at: tile(1))
            windows.showSearch()
            await pause(0.3)
            await press("w", code: 13)
            let typed = state.searchText
            await press("\u{7F}", code: 51)
            await report("the Delete key in the search field, which read “\(typed)” and now reads “\(state.searchText)”")
            // With the Workshop on show, the library's commands leave the library alone.
            await click(at: tile(1))
            await report("the wallpaper left selected")
            state.section = .workshop
            await pause(1)
            await press("a", code: 0, .command)
            await press("\u{8}", code: 51)
            await report("Command-A and the Delete key in the Workshop")
            state.section = .library
            await report("back in the library")
            exit(0)
        }
    }

    /// `--watch-theme <seconds>`, with `--screenshots`: keeps the main window open with the
    /// settings at its side and takes a picture of it every second (`theme-1.png`, …), to see
    /// whether it follows the Mac's accent color and appearance when they change meanwhile.
    private static func watchTheme(_ content: AnyView, seconds: Int, in directory: URL) async {
        let size = NSSize(width: 1100, height: 520)
        let window = AppWindow.make(title: "WallAero Engine", content: content, size: size)
        centerOnSharpestScreen(window)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(nanoseconds: 700_000_000)
        if !CommandLine.arguments.contains("--settings-top") {
            scrollSettings(in: window, toEnd: true)
        }
        for second in 1...max(1, seconds) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            var image: CGImage?
            if #available(macOS 14.4, *) {
                image = try? await captureWithScreenCaptureKit(window)
            }
            if let image {
                write(image, to: directory.appendingPathComponent("theme-\(second).png"))
            }
        }
        window.close()
    }

    /// `--picture-desktop <picture.png> [--after <seconds>] [--times <n>] [--switch-to <id>] [--click <x> <y>]` starts the app as
    /// usual and has it take pictures of its own windows on the desktop, the way they are being
    /// shown: `picture-1.png` after the given seconds (5), and so on. For each it says how much
    /// of it is black and what the wallpaper is doing. A capture of the whole screen needs a
    /// permission; an app's picture of its own window does not, which is the point.
    static var desktopPictureURL: URL? {
        values(of: "--picture-desktop").last.map { URL(fileURLWithPath: $0) }
    }

    static func pictureDesktop(of manager: WallpaperManager, to url: URL) {
        let pause = values(of: "--after").last.flatMap(Double.init) ?? 5
        let times = values(of: "--times").last.flatMap(Int.init) ?? 1
        Task {
            for time in 1...max(1, times) {
                try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
                for (index, desktop) in manager.desktops.enumerated() {
                    var image: CGImage?
                    if #available(macOS 14.4, *) {
                        image = try? await captureWithScreenCaptureKit(desktop.window)
                    }
                    let name = url.deletingPathExtension().lastPathComponent + "-\(time)" + (index > 0 ? "-\(index + 1)" : "") + ".png"
                    if let image {
                        write(image, to: url.deletingLastPathComponent().appendingPathComponent(name))
                    }
                    let black = image.map { "\(Int((blackShare(of: $0) * 100).rounded())) %" } ?? "could not look"
                    let web = desktop.view.webView
                    print("\(name): \(desktop.item?.name ?? "nothing") — black \(black); window alpha \(desktop.window.alphaValue), "
                        + "on screen \(desktop.isVisibleOnScreen); still in front \(web?.isShowingStill ?? false); reason for a pause: \(manager.pauseReason.map { "\($0)" } ?? "none")")
                    fflush(stdout)
                }
                // `--switch-to <wallpaper id>`: after the first picture that wallpaper is chosen,
                // the way a click in the library would choose it.
                if time == 1, let id = values(of: "--switch-to").last.flatMap(UUID.init(uuidString:)) {
                    manager.setWallpaper(id, for: .all)
                }
                // `--click <x> <y>`, in parts of the main display from its bottom left: after
                // the first picture the mouse is played there — a move, a press, a release —
                // through the same door the real mouse comes in by.
                let arguments = CommandLine.arguments
                if time == 1, let index = arguments.firstIndex(of: "--click"), index + 2 < arguments.count,
                   let x = Double(arguments[index + 1]), let y = Double(arguments[index + 2]), let screen = NSScreen.main {
                    let place = NSPoint(x: screen.frame.minX + screen.frame.width * x, y: screen.frame.minY + screen.frame.height * y)
                    print("the mouse is played at \(Int(place.x)),\(Int(place.y)): \(manager.playPointer(at: place))")
                    fflush(stdout)
                }
            }
        }
    }

    /// `--pointer-test <seconds>` checks how the mouse is passed on to web wallpapers, with a
    /// made-up wallpaper as large as the main display that only writes down what it is told.
    /// It says which places of the display count as the desktop, plays a press, a drag onto a
    /// window and a release there to see what the wallpaper would be sent, and then watches the
    /// real mouse for the given seconds: move it and click the desktop meanwhile.
    static var pointerTestSeconds: Double? {
        values(of: "--pointer-test").last.flatMap(Double.init)
    }

    static func pointerTest(seconds: Double) {
        NSApp.setActivationPolicy(.accessory)
        guard let screen = NSScreen.main else { exit(1) }
        let forwarder = PointerForwarder()
        var told: [String] = []
        let wallpaper = NSObject()
        forwarder.targets = {
            [PointerForwarder.Target(id: ObjectIdentifier(wallpaper), frame: screen.frame) { kind, point in
                told.append("\(kind.rawValue) \(Int(point.x)),\(Int(point.y))")
            }]
        }

        // Which places are the desktop: a grid over the display, and the first of each sort.
        var desktop: NSPoint?
        var covered: NSPoint?
        var count = 0
        let steps = 24
        for row in 0..<steps {
            for column in 0..<steps {
                let place = NSPoint(x: screen.frame.minX + (CGFloat(column) + 0.5) * screen.frame.width / CGFloat(steps),
                                    y: screen.frame.minY + (CGFloat(row) + 0.5) * screen.frame.height / CGFloat(steps))
                if forwarder.isDesktop(at: place) {
                    count += 1
                    desktop = desktop ?? place
                } else {
                    covered = covered ?? place
                }
            }
        }
        print("the desktop shows at \(count) of \(steps * steps) places of the main display; under the pointer now: \(forwarder.isDesktop(at: NSEvent.mouseLocation) ? "the desktop" : "a window")")

        Task {
            if let desktop, let covered {
                // Each step a little after the last: moves told too close together are held back.
                let steps: [(PointerForwarder.Kind, NSPoint, String)] = [
                    (.move, covered, "the pointer over a window"), (.move, desktop, "onto the desktop"),
                    (.down, desktop, "the button goes down"), (.move, covered, "dragged onto a window"),
                    (.up, covered, "released there"), (.move, covered, "moved on over the window"),
                    (.down, covered, "a click in the window"), (.up, covered, "and its release"),
                ]
                for (kind, place, what) in steps {
                    told = []
                    forwarder.handle(kind, at: place)
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    print("  \(what): \(told.isEmpty ? "nothing" : told.joined(separator: "; "))")
                }
            } else {
                print("  the display is all desktop or all windows; nothing to play out")
            }
            told = []
            // What reaches the app at all, whether or not it is over the desktop.
            var seen = 0
            let watcher = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]) { _ in
                seen += 1
            }
            forwarder.isActive = true
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            forwarder.isActive = false
            watcher.map(NSEvent.removeMonitor)
            let moves = told.filter { $0.hasPrefix("move") }.count
            print("the real mouse in \(Int(seconds)) s: \(seen) events reached the app; passed on: \(moves) moves, \(told.filter { $0.hasPrefix("down") }.count) presses, "
                + "\(told.filter { $0.hasPrefix("up") }.count) releases, \(told.filter { $0.hasPrefix("leave") }.count) times left the desktop")
            exit(0)
        }
    }

    /// Says which frame the preview in the Workshop's panel is on, three times: they differ if it plays.
    private static func printPreviewFrames(in window: NSWindow) {
        func picture(in view: NSView) -> NSImageView? {
            (view as? NSImageView).flatMap { $0.animates ? $0 : nil } ?? view.subviews.lazy.compactMap(picture(in:)).first
        }
        guard let view = window.contentView.flatMap(picture(in:)),
              let bitmap = view.image?.representations.first as? NSBitmapImageRep
        else {
            print("no moving preview")
            return
        }
        let total = bitmap.value(forProperty: .frameCount) as? Int ?? 1
        for _ in 0..<3 {
            print("frame \(bitmap.value(forProperty: .currentFrame) as? Int ?? 0) of \(total)")
            RunLoop.current.run(until: Date().addingTimeInterval(0.37))
        }
    }

    /// `--workshop-tags-click`, with `--workshop`: opens the tags with a real click, and clicks the
    /// two things at the top of it, saying what each click did.
    private static func clickTagList(in window: NSWindow, store: WorkshopStore) async {
        setlinebuf(stdout)
        click(NSPoint(x: 270, y: 56), in: window, isButton: true)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        print("the tags are " + (store.showsTagFilter ? "open" : "NOT open"))
        guard let list = NSApp.windows.first(where: { $0 !== window && $0.isVisible && $0.contentView.map { $0.bounds.height > 200 } == true }) else {
            print("no list")
            return
        }
        // The rows below the heading of the list, counted from its top.
        for (name, y) in [("18+", 35.0), ("anime", 58), ("18+", 35), ("anime", 58)] {
            let before = store.query
            click(NSPoint(x: 40, y: y), in: list, isButton: true)
            try? await Task.sleep(nanoseconds: 400_000_000)
            print("\(name): shows anime \(before.includesAnime) -> \(store.query.includesAnime), shows 18+ \(before.includesMature) -> \(store.query.includesMature)")
        }
    }

    /// `--workshop-click`, with `--workshop`: clicks each tile with a real mouse event, saying
    /// which of them show up in the panel, and then Download in the panel of the last one. With no
    /// account in this helper that click opens the sign-in and starts nothing.
    private static func clickWorkshopButtons(in window: NSWindow, store: WorkshopStore, state: MainWindowState, in directory: URL) async {
        setlinebuf(stdout)
        // SwiftUI draws the tiles itself, so they are found by where the grid has them with the
        // panel open in a window of 1420×700: the middle of each picture, counted from the top left.
        let panelStayed = window.frame.width
        for y in [187.0, 381, 575] {
            for x in [150.0, 382, 614, 846] {
                store.selected = nil
                // From the app's settings or from a closed panel, a click still shows the item.
                state.settingsTab = .general
                state.showsSettings = y != 575
                try? await Task.sleep(nanoseconds: 700_000_000)
                click(NSPoint(x: x, y: y), in: window)
                try? await Task.sleep(nanoseconds: 700_000_000)
                let isShown = store.selected != nil && state.settingsTab == .wallpaper && state.showsSettings
                print("(\(Int(x)), \(Int(y))): " + (isShown ? "shown" : "NOT shown") + ", window \(Int(window.frame.width)) wide")
            }
        }
        print("the window stayed \(Int(panelStayed)) wide: \(window.frame.width == panelStayed)")
        if let image = drawViews(of: window) {
            write(image, to: directory.appendingPathComponent("workshop-panel.png"))
        }
        guard let content = window.contentView else { return }
        // The button stands at the end of the panel's last row.
        let before = store.downloads.count
        click(NSPoint(x: content.bounds.width - 50, y: content.bounds.height - 24), in: window, isButton: true)
        print("Download in the panel: " + (store.downloads.count > before ? "clicked" : "NOT clicked"))
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        print("the sign-in " + (window.attachedSheet != nil ? "opened" : "did NOT open"))
        store.cancelSignIn()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        print("the sign-in " + (window.attachedSheet == nil ? "closed" : "did NOT close"))
    }

    private static func click(_ point: NSPoint, in window: NSWindow, isButton: Bool = false) {
        let height = window.contentView?.bounds.height ?? 700
        let mouse = { (type: NSEvent.EventType) in
            NSEvent.mouseEvent(with: type, location: NSPoint(x: point.x, y: height - point.y), modifierFlags: [],
                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        if isButton {
            // A button waits for the release once pressed, so that goes in the queue first.
            mouse(.leftMouseUp).map { NSApp.postEvent($0, atStart: false) }
            mouse(.leftMouseDown).map(window.sendEvent)
        } else {
            mouse(.leftMouseDown).map(window.sendEvent)
            mouse(.leftMouseUp).map(window.sendEvent)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }

    /// `--steam-test <folder>` gets SteamCMD into the folder, signs in to no account and asks for
    /// a Workshop item as `--steam-test-item <number>` says, printing what it answers: Steam
    /// refuses, the way it refuses an account that does not own Wallpaper Engine; a free game's
    /// item, by `--steam-test-app`, it gives out. The first time, the program updates itself first.
    static var steamTestFolder: URL? {
        values(of: "--steam-test").last.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func steamTest(_ folder: URL) {
        setlinebuf(stdout)
        let steam = SteamCMD(folder: folder)
        let item = values(of: "--steam-test-item").last ?? "2482408967"
        Task {
            do {
                if !steam.isInstalled {
                    try await steam.install()
                }
                print("installed: \(steam.isInstalled)")
                let run = try steam.download([item], account: "anonymous", app: values(of: "--steam-test-app").last ?? SteamWorkshop.appID)
                // `--steam-test-size <bytes>`: says how far it has come, as a tile would show it.
                let size = values(of: "--steam-test-size").last.flatMap(Double.init)
                let watching = Task {
                    while let size, !Task.isCancelled {
                        print("\(Int(min(0.99, Double(run.bytesDownloaded) / size) * 100))%")
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
                defer { watching.cancel() }
                for await event in run.events {
                    print(event)
                    // `--steam-test-cancel` stops it at the first thing it says.
                    if CommandLine.arguments.contains("--steam-test-cancel") {
                        run.cancel()
                    }
                }
                exit(0)
            } catch {
                print("failed: \(error)")
                exit(1)
            }
        }
    }

    /// `--import-test <library folder> <file or folder>…` brings files into a library of its
    /// own, the way adding them in the app does — an archive, a wallpaper made for Wallpaper
    /// Engine, a page, a video — and says what each became. The library in use is not touched.
    static var importTest: (library: URL, sources: [URL])? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--import-test"), index + 2 < arguments.count else { return nil }
        let sources = arguments[(index + 2)...].prefix { !$0.hasPrefix("-") }.map { URL(fileURLWithPath: $0) }
        return (URL(fileURLWithPath: arguments[index + 1], isDirectory: true), sources)
    }

    /// `--attach-test <library folder> <archive>`: gives the first scene of the library its
    /// Wallpaper Engine project from the archive, as the editor offers for a scene added before
    /// it could change one, and lists what the project then has.
    static var attachTest: (library: URL, source: URL)? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--attach-test"), index + 2 < arguments.count else { return nil }
        return (URL(fileURLWithPath: arguments[index + 1], isDirectory: true), URL(fileURLWithPath: arguments[index + 2]))
    }

    static func runAttachTest(_ request: (library: URL, source: URL)) {
        NSApp.setActivationPolicy(.accessory)
        let library = WallpaperLibrary(rootURL: request.library)
        Task {
            guard let item = library.items.first(where: library.isScene) else {
                print("no scene in the library")
                exit(1)
            }
            do {
                try await library.attachEngineProject(from: request.source, to: item)
                let folder = library.projectURL(for: item)
                let document = try WallpaperEngineProjectFolder.read(from: folder.appendingPathComponent(WallpaperEngineProjectFolder.folderName))
                print("“\(item.name)”: \(document.objects.count) objects, \(document.files.count) files")
                let scene = try SceneProject.read(from: folder)
                print("  kept beside it: \(scene.background.engine.objects.count) changes; settings: \(scene.variables.count)")
            } catch {
                print("failed: \(error)")
            }
            exit(0)
        }
    }

    /// Prints how far an import has come, a line at each tenth, for `--import-test`.
    final class ProgressShown: @unchecked Sendable {
        private var last: [String: Int] = [:]
        private let lock = NSLock()

        func show(_ part: Double, since start: Date, label: String) {
            lock.lock()
            defer { lock.unlock() }
            let tenth = Int(part * 10)
            guard tenth > (last[label] ?? -1) else { return }
            last[label] = tenth
            print(String(format: "  %@ %3d%% at %.1f s", label, tenth * 10, Date().timeIntervalSince(start)))
        }
    }

    static func runImportTest(_ request: (library: URL, sources: [URL])) {
        NSApp.setActivationPolicy(.accessory)
        let library = WallpaperLibrary(rootURL: request.library)
        Task {
            for source in request.sources {
                do {
                    let shown = ProgressShown()
                    let started = Date()
                    let added = try await library.importItem(at: source, languages: Bundle.main.preferredLocalizations) { part in
                        shown.show(part, since: started, label: "adding")
                    }
                    for item in added where item.kind == .web {
                        // As the app's own import does: videos turned into WebM for Chromium.
                        let converted = await WebMediaConverter.convertFolder(library.projectURL(for: item)) { part in
                            shown.show(part, since: started, label: "converting")
                        }
                        if !converted.isEmpty { print("  converted for Chromium: \(converted.joined(separator: ", "))") }
                    }
                    for item in added {
                        print("\(source.lastPathComponent) → “\(item.name)” [\(item.sourceFormat)] \(item.fileName), thumbnail: \(item.thumbnailFileName != nil)")
                        if !item.tagList.isEmpty {
                            print("  tags: " + item.tagList.map { "\($0) (\(library.category(of: $0) ?? "—"))" }.joined(separator: ", "))
                        }
                        guard library.isScene(item), let scene = try? SceneProject.read(from: library.projectURL(for: item)) else { continue }
                        print("  background: \(scene.background.kind.rawValue) \(scene.background.source ?? "")")
                        for layer in scene.layers {
                            print("  layer “\(layer.name)”: \(layer.kind.rawValue) \(layer.source) at \(layer.x), \(layer.y), \(layer.width) wide, turned \(layer.rotation), opacity \(layer.opacity), \(layer.blendMode)\(layer.isVisible ? "" : ", hidden")")
                        }
                        if let leftOut = library.leftOutOnImport[item.id] {
                            print("  not played: \(leftOut.animations) pictures that bend, \(leftOut.objects) objects of other kinds")
                        }
                        for variable in scene.variables {
                            let value: String
                            switch variable.kind {
                            case .color: value = variable.color
                            case .number: value = "\(variable.number) in \(variable.minimum)…\(variable.maximum) by \(variable.step)"
                            case .toggle: value = variable.isOn ? "on" : "off"
                            case .text: value = "“\(variable.text)”"
                            case .choice: value = "“\(variable.text)” of \(variable.options) for \(variable.values.map { "\($0)" } ?? "—")"
                            }
                            print("  \(variable.property ?? "—") as \(variable.key): “\(variable.title)” \(variable.kind.rawValue) \(value)")
                        }
                    }
                } catch {
                    print("\(source.lastPathComponent) → \(error.localizedDescription)")
                }
            }
            exit(0)
        }
    }

    /// `--toggle-settings`, with `--screenshots`: opens the main window the way the app does,
    /// narrow and without the settings, then shows them at its side and hides them again as the
    /// button in the toolbar would. It takes a picture each time (`toggle-1.png`, …) and prints
    /// how wide the window is and how narrow it may get, and whether Find reaches the search field.
    private static func toggleSettings(_ content: AnyView, state: MainWindowState, in directory: URL) async {
        state.showsSettings = false
        let windows = WindowManager(state: state, remembersFrames: false, main: { content })
        windows.showLibrary()
        guard let window = windows.libraryWindow else { return }
        try? await Task.sleep(nanoseconds: 800_000_000)
        var frame = window.frame
        // `--toggle-width <points>`: a wide window, which the settings do not widen.
        frame.size.width = values(of: "--toggle-width").last.flatMap(Double.init).map { CGFloat($0) } ?? 700
        window.setFrame(frame, display: true)
        for (step, shown) in [false, true, false, true].enumerated() {
            state.showsSettings = shown
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            var image: CGImage?
            if #available(macOS 14.4, *) {
                image = try? await captureWithScreenCaptureKit(window)
            }
            if let image = image ?? drawViews(of: window) {
                write(image, to: directory.appendingPathComponent("toggle-\(step + 1).png"))
            }
            print("settings \(shown ? "shown" : "hidden"): the window is \(Int(window.frame.width)) wide, at least \(Int(window.contentMinSize.width))")
        }
        // What the Find command does: the cursor goes to the search field.
        windows.showSearch()
        let editor = window.firstResponder as? NSTextView
        print("Find puts the cursor in the search field: \(editor?.delegate is NSSearchField)")
        window.close()
    }

    /// `--switch-sections`, with `--screenshots`: goes from the library to the Steam Workshop and
    /// back as the control in the toolbar would, with the settings open, taking a picture each
    /// time (`section-1.png`, …). It scrolls the library first and says where it finds it again,
    /// and asks Find which search field it reaches.
    private static func switchSections(_ content: AnyView, state: MainWindowState, workshop: WorkshopStore, in directory: URL) async {
        state.showsSettings = true
        let windows = WindowManager(state: state, remembersFrames: false, main: { content })
        windows.showLibrary()
        guard let window = windows.libraryWindow else { return }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        func allScrollViews(in view: NSView) -> [NSScrollView] {
            ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap(allScrollViews(in:))
        }
        // The grid is the scroll view at the left of the window, the settings the one at its right.
        func gridOffset() -> CGFloat {
            allScrollViews(in: window.contentView ?? NSView()).first { $0.convert($0.bounds, to: nil).minX < 100 }?.contentView.bounds.minY ?? -1
        }
        allScrollViews(in: window.contentView ?? NSView()).first { $0.convert($0.bounds, to: nil).minX < 100 }.map { grid in
            grid.contentView.scroll(to: NSPoint(x: 0, y: 200))
            grid.reflectScrolledClipView(grid.contentView)
        }
        func report(_ step: Int, _ what: String) async {
            var image: CGImage?
            if #available(macOS 14.4, *) {
                image = try? await captureWithScreenCaptureKit(window)
            }
            if let image = image ?? drawViews(of: window) {
                write(image, to: directory.appendingPathComponent("section-\(step).png"))
            }
            windows.showSearch()
            let field = (window.firstResponder as? NSTextView)?.delegate as? NSSearchField
            print("\(what): the window is \(Int(window.frame.width)) wide; Find reaches “\(field?.placeholderString ?? "the library's field")”")
            window.makeFirstResponder(nil)
        }
        await report(1, "the library, scrolled to \(Int(gridOffset()))")
        state.section = .workshop
        try? await Task.sleep(nanoseconds: 9_000_000_000)
        print("the Workshop lists \(workshop.items.count)")
        await report(2, "the Workshop")
        state.section = .library
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        await report(3, "the library again, scrolled to \(Int(gridOffset()))")
        window.close()
    }

    /// Scrolls whatever scrolls in the right half of the window, the settings, to its end or
    /// back to its start. The settings sometimes open a little way down; a picture of how the
    /// window opens is taken from their start.
    private static func scrollSettings(in window: NSWindow, toEnd: Bool) {
        guard let content = window.contentView else { return }
        func scrollViews(in view: NSView) -> [NSScrollView] {
            view.subviews.flatMap { subview in
                (subview as? NSScrollView).map { [$0] } ?? scrollViews(in: subview)
            }
        }
        for scrollView in scrollViews(in: content) where scrollView.convert(scrollView.bounds, to: nil).minX > content.bounds.midX {
            guard let document = scrollView.documentView else { continue }
            let end = max(0, document.frame.height - scrollView.contentView.bounds.height)
            let atEnd = document.isFlipped ? end : 0
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: toEnd ? atEnd : end - atEnd))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private static func pictureInspectorPages(of window: NSWindow, to output: URL) async {
        guard let content = window.contentView else { return }
        func scrollViews(in view: NSView) -> [NSScrollView] {
            view.subviews.flatMap { subview in
                (subview as? NSScrollView).map { [$0] } ?? scrollViews(in: subview)
            }
        }
        let inspector = scrollViews(in: content).filter { $0.convert($0.bounds, to: nil).minX > content.bounds.midX }
            .max { $0.documentView?.frame.height ?? 0 < $1.documentView?.frame.height ?? 0 }
        guard let inspector, let document = inspector.documentView else { return }
        let page = inspector.contentView.bounds.height - 40
        let start = document.isFlipped ? inspector.contentView.bounds.minY : document.frame.height - inspector.contentView.bounds.height
        for number in 2...12 {
            let moved = page * CGFloat(number - 1)
            guard moved < document.frame.height - inspector.contentView.bounds.height + page else { break }
            inspector.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? start + moved : max(0, start - moved)))
            inspector.reflectScrolledClipView(inspector.contentView)
            try? await Task.sleep(nanoseconds: 500_000_000)
            var image: CGImage?
            if #available(macOS 14.4, *) {
                image = try? await captureWithScreenCaptureKit(window)
            }
            if let image = image ?? drawViews(of: window) {
                let name = output.deletingPathExtension().lastPathComponent + "-\(number)"
                write(image, to: output.deletingLastPathComponent().appendingPathComponent(name).appendingPathExtension("png"))
            }
        }
    }

    private static func shoot(_ content: AnyView, title: String, size: NSSize, to url: URL,
                              waiting seconds: Double = 0, prepare: ((NSWindow) -> Void)? = nil) async {
        let window = AppWindow.make(title: title, content: content, size: size)
        centerOnSharpestScreen(window)
        window.makeKeyAndOrderFront(nil)
        // Let SwiftUI lay out, thumbnails load and the window server draw a few frames.
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        prepare?(window)
        try? await Task.sleep(nanoseconds: 500_000_000 + UInt64(seconds * 1_000_000_000))
        // Whoever is at the Mac may have clicked elsewhere meanwhile: a window that is not
        // the active one is drawn dimmed. Ask for it back a few times, then say so.
        for _ in 0..<8 where !(NSApp.isActive && window.isKeyWindow) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        if !(NSApp.isActive && window.isKeyWindow) {
            print("the window was not the active one; \(url.lastPathComponent) shows it dimmed")
        }

        var image: CGImage?
        if #available(macOS 14.4, *) {
            image = try? await captureWithScreenCaptureKit(window)
        }
        image = image ?? drawViews(of: window)
        if let image {
            write(image, to: url)
            print("wrote \(url.path) (\(image.width)×\(image.height))")
        } else {
            print("could not capture \(title)")
        }
        window.close()
    }

    @available(macOS 14.4, *)
    private static func captureWithScreenCaptureKit(_ window: NSWindow) async throws -> CGImage? {
        let content = try await SCShareableContent.currentProcess
        guard let shareable = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
            return nil
        }
        let filter = SCContentFilter(desktopIndependentWindow: shareable)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = Int(filter.contentRect.width * scale)
        configuration.height = Int(filter.contentRect.height * scale)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        // A shadow would be captured on an opaque black background; the rounded corners stay clear.
        configuration.ignoreShadowsSingleWindow = true
        configuration.shouldBeOpaque = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// `--appearance light` or `--appearance dark` shows the helper's windows that way, whatever
    /// the Mac is set to; without it they follow the system, as the app's own windows do.
    private static func applyRequestedAppearance() {
        switch values(of: "--appearance").last {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    private static func drawViews(of window: NSWindow) -> CGImage? {
        guard let view = window.contentView?.superview ?? window.contentView,
              let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else {
            return nil
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        return representation.cgImage
    }

    // MARK: - Rendering a web wallpaper

    /// `--render-web <wallpaper folder> <picture.png> [width height]` draws a web wallpaper off
    /// screen, with the code the app uses for thumbnails and stills, and quits. It touches
    /// neither the library nor the copy in use; handy for checking a scene from a script.
    /// With `--still` the picture is the one for the lock screen.
    static var renderRequest: (folder: URL, output: URL, size: NSSize)? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--render-web"), index + 2 < arguments.count else { return nil }
        var size = NSSize(width: 960, height: 540)
        if index + 4 < arguments.count, let width = Double(arguments[index + 3]), let height = Double(arguments[index + 4]) {
            size = NSSize(width: width, height: height)
        }
        return (URL(fileURLWithPath: arguments[index + 1], isDirectory: true), URL(fileURLWithPath: arguments[index + 2]), size)
    }

    static func renderWeb(_ request: (folder: URL, output: URL, size: NSSize)) {
        NSApp.setActivationPolicy(.accessory)
        Task {
            guard let project = WebProject(folder: request.folder) else {
                print("no web page in \(request.folder.path)")
                exit(1)
            }
            if CommandLine.arguments.contains("--pause-test") {
                await pauseTest(project, size: request.size)
            }
            let forStill = CommandLine.arguments.contains("--still")
            guard let image = await WebSnapshotter.render(project, size: request.size, forStill: forStill) else {
                print("could not render \(request.folder.path)")
                exit(1)
            }
            write(image, to: request.output)
            print("wrote \(request.output.path) (\(image.width)×\(image.height))")
            exit(0)
        }
    }

    /// `--pause-test`, with `--render-web`: pauses and resumes the wallpaper the way the desktop
    /// window does, and reports whether the page really stood still in between. With
    /// `--needs-user-action` the web engine starts no video by itself, as in Low Power Mode, and
    /// the report shows whether the app got it playing all the same.
    private static func pauseTest(_ project: WebProject, size: NSSize) async {
        let view = WebWallpaperView(frame: NSRect(origin: .zero, size: size))
        view.mediaNeedsUserAction = CommandLine.arguments.contains("--needs-user-action")
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 120, y: 120), size: size), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // Above other windows: a covered page pauses by itself, which would hide what is tested.
        window.level = .floating
        window.contentView = view
        window.orderFrontRegardless()
        view.setPlaying(true, rate: 1)
        view.show(project, watchingForChanges: false)
        await view.waitUntilLoaded()
        // Counts animation frames, to see whether the page is running.
        _ = await view.value(of: "window.__frames = 0; (function tick() { window.__frames++; requestAnimationFrame(tick); })(); 1")
        func report(_ label: String) async {
            let state = await view.value(of: "var v = document.querySelector('video'); JSON.stringify({frames: window.__frames, video: v ? (v.paused ? 'paused' : 'playing') + ' at ' + v.currentTime.toFixed(1) : 'none', page: document.visibilityState})")
            print(label.padding(toLength: 22, withPad: " ", startingAt: 0), state as? String ?? "?", "| still shown:", view.isShowingStill)
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await report("playing:")
        view.setPlaying(false, rate: 1)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await report("paused, 1 s:")
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await report("paused, 2.5 s:")
        view.setPlaying(true, rate: 1)
        try? await Task.sleep(nanoseconds: 300_000_000)
        await report("again, 0.3 s:")
        try? await Task.sleep(nanoseconds: 900_000_000)
        await report("playing again:")
        view.setPlaying(true, rate: 2)
        view.setAudio(muted: false, volume: 0)
        try? await Task.sleep(nanoseconds: 600_000_000)
        let media = await view.value(of: "var v = document.querySelector('video'); v ? JSON.stringify({rate: v.playbackRate, muted: v.muted, volume: v.volume}) : 'no video'")
        print("speed 2×, sound on:   ", media as? String ?? "?")
        view.unload()
        window.close()
        fflush(stdout)
    }

    // MARK: - The scene editor

    /// `--edit-scene <scene folder> <picture.png>` opens the scene editor on a folder, takes a
    /// picture of its window and quits; the README's editor screenshot is made this way. Options,
    /// for checking the editor from a script: `--select <layer number, front first>` selects a
    /// layer, `--eval <JavaScript>` runs in the preview first — to act as the mouse would —
    /// and `--add <kind>`, `--background-blur <number>` and `--undo <times>` change the scene the
    /// way the editor's own controls do. `--add-variable <kind>` adds a variable and
    /// `--select-variable <number>` selects one; `--select-object <number>` selects the object
    /// of a Wallpaper Engine scene the scene numbers so, and the scene's objects are listed;
    /// `--engine-changes <JSON>` changes that scene as the inspector does, one after another.
    static var editRequest: (folder: URL, output: URL)? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--edit-scene"), index + 2 < arguments.count else { return nil }
        return (URL(fileURLWithPath: arguments[index + 1], isDirectory: true), URL(fileURLWithPath: arguments[index + 2]))
    }

    private static func values(of option: String) -> [String] {
        let arguments = CommandLine.arguments
        return arguments.indices.filter { arguments[$0] == option && $0 + 1 < arguments.count }.map { arguments[$0 + 1] }
    }

    static func editScene(_ request: (folder: URL, output: URL)) {
        applyRequestedAppearance()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if WallpaperEngineProjectFolder.project(ofScene: request.folder) != nil {
            editEngineScene(request)
            return
        }
        guard let model = try? SceneEditorModel(folder: request.folder, title: request.folder.lastPathComponent) else {
            print("no scene in \(request.folder.path)")
            exit(1)
        }
        let preview = SceneEditorPreviewController(model: model)
        let size = NSSize(width: 1240, height: 760)
        let window = AppWindow.make(title: model.title, content: AnyView(SceneEditorView(model: model, preview: preview)), size: size)
        centerOnSharpestScreen(window)
        window.makeKeyAndOrderFront(nil)

        Task {
            await preview.view.waitUntilLoaded()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            for script in values(of: "--eval") {
                preview.view.evaluate(script)
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            for kind in values(of: "--add").compactMap(WallpaperScene.Layer.Kind.init(rawValue:)) {
                model.addLayer(kind)
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            if let blur = values(of: "--background-blur").last.flatMap(Double.init) {
                model.scene.background.blur = blur
            }
            for _ in 0..<(values(of: "--undo").last.flatMap(Int.init) ?? 0) {
                model.undo()
            }
            for kind in values(of: "--add-variable").compactMap(WallpaperScene.Variable.Kind.init(rawValue:)) {
                model.addVariable(kind)
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            if let number = values(of: "--select").last.flatMap(Int.init), model.layersFrontFirst.indices.contains(number - 1) {
                model.selection = .layer(model.layersFrontFirst[number - 1].id)
            }
            if let number = values(of: "--select-variable").last.flatMap(Int.init), model.scene.variables.indices.contains(number - 1) {
                model.selection = .variable(model.scene.variables[number - 1].id)
            }
            if let number = values(of: "--select-object").last.flatMap(Int.init) {
                model.selection = .object(number)
            }
            for text in values(of: "--engine-changes") {
                if let changes = try? JSONDecoder().decode(WallpaperScene.EngineChanges.self, from: Data(text.utf8)) {
                    model.scene.background.engine = changes
                } else {
                    print("cannot read the changes \(text)")
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            // What the editor holds now, for a script to check.
            print("selection: \(model.selectedLayer?.name ?? model.selection.map { "\($0)" } ?? "background"); undo: \(model.canUndo)")
            if let engineScene = model.engineScene {
                print("scene objects:")
                for row in engineScene.rows {
                    let object = row.object
                    print(String(repeating: "  ", count: row.depth + 1) + "#\(object.id) \(object.title) [\(object.kind.rawValue)]"
                          + (object.effects.isEmpty ? "" : " effects: " + object.effects.map { "\($0.title) (\($0.values.count))" }.joined(separator: ", ")))
                }
            }
            if !model.scene.background.engine.isEmpty,
               let data = try? JSONEncoder().encode(model.scene.background.engine) {
                print("changes: \(String(decoding: data, as: UTF8.self))")
            }
            for layer in model.layersFrontFirst {
                print(String(format: "  %@ [%@] x %.2f y %.2f width %.2f height %.2f rotation %.2f size %.2f",
                             layer.name, layer.kind.rawValue, layer.x, layer.y, layer.width, layer.height, layer.rotation, layer.fontSize))
            }
            var image: CGImage?
            if #available(macOS 14.4, *) {
                image = try? await captureWithScreenCaptureKit(window)
            }
            if let image = image ?? drawViews(of: window) {
                write(image, to: request.output)
                print("wrote \(request.output.path) (\(image.width)×\(image.height))")
            }
            // `--inspector-pages`: the properties a screen at a time, as <output>-2.png and on.
            if CommandLine.arguments.contains("--inspector-pages") {
                await pictureInspectorPages(of: window, to: request.output)
            }
            model.saveNow()
            exit(0)
        }
    }

    /// The editor of a scene made as Wallpaper Engine makes one, for `--edit-scene`. Options:
    /// `--select-object <number>`, `--add-effect <name>` (on the selected object),
    /// `--add-particles <name>`, `--add-text`, `--sheet effects|particles|puppet` (for the
    /// selected object), `--set <key> <number>` on the selected object, `--undo <times>`,
    /// `--size <width> <height>` of the window, to see more of the inspector.
    private static func editEngineScene(_ request: (folder: URL, output: URL)) {
        guard let model = try? EngineEditorModel(folder: request.folder, title: request.folder.lastPathComponent) else {
            print("no project in \(request.folder.path)")
            exit(1)
        }
        let preview = EngineEditorPreviewController(model: model)
        var size = NSSize(width: 1360, height: 820)
        if let index = CommandLine.arguments.firstIndex(of: "--size"), index + 2 < CommandLine.arguments.count,
           let width = Double(CommandLine.arguments[index + 1]), let height = Double(CommandLine.arguments[index + 2]) {
            size = NSSize(width: width, height: height)
        }
        let window = AppWindow.make(title: model.title, content: AnyView(EngineEditorView(model: model, preview: preview)), size: size)
        centerOnSharpestScreen(window)
        window.makeKeyAndOrderFront(nil)
        Task {
            await preview.waitUntilLoaded()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            print("preview drawn by the app: \(preview.drawsNatively)")
            if let number = values(of: "--select-object").last.flatMap(Int.init) {
                model.selection = number
            }
            // `--tool <move|rotate|scale>`, `--tab <kind|effects>`, `--scene-tab <view|environment|settings>`,
            // `--zoom <factor>` and `--find <text>`: the editor with that chosen; `--open-rows`
            // with everything in the properties unfolded.
            FoldingRowsLook.opensAll = CommandLine.arguments.contains("--open-rows")
            switch values(of: "--tool").last {
            case "move": model.tool = .move
            case "rotate": model.tool = .rotate
            case "scale": model.tool = .scale
            default: break
            }
            switch values(of: "--tab").last {
            case "kind": model.objectTab = .kind
            case "effects": model.objectTab = .effects
            default: break
            }
            switch values(of: "--scene-tab").last {
            case "view": model.sceneTab = .view
            case "environment": model.sceneTab = .environment
            case "settings": model.sceneTab = .settings
            default: break
            }
            if let zoom = values(of: "--zoom").last.flatMap(Double.init) {
                model.zoomView(by: zoom, around: .zero)
            }
            model.layerFilter = values(of: "--find").last ?? ""
            // `--move-row <from> <to>`: a row of the list of layers dragged to another place.
            if let index = CommandLine.arguments.firstIndex(of: "--move-row"), index + 2 < CommandLine.arguments.count,
               let from = Int(CommandLine.arguments[index + 1]), let to = Int(CommandLine.arguments[index + 2]) {
                let names = { model.rows.prefix(5).map { model.name(of: $0.id) } }
                print("rows before: \(names())")
                model.moveRows(fromOffsets: IndexSet(integer: from), toOffset: to)
                print("rows after: \(names()); objects \(model.document.objectIDs.count); undo \(model.canUndo)")
            }
            // `--timeline`, `--curves`: the timeline open, on its keys or on its curves.
            model.showsTimeline = CommandLine.arguments.contains("--timeline")
            model.timelineCurves = CommandLine.arguments.contains("--curves")
            // `--effect-switch <effect> <name> <value>`: a switch of an effect of the selection set.
            if let index = CommandLine.arguments.firstIndex(of: "--effect-switch"), index + 3 < CommandLine.arguments.count,
               let effect = Int(CommandLine.arguments[index + 1]), let value = Double(CommandLine.arguments[index + 3]), let id = model.selection {
                for _ in 0..<40 where model.description?.object(id)?.effects.first(where: { $0.id == effect }) == nil {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                @MainActor func show(_ when: String) {
                    let described = model.description?.object(id)?.effects.first { $0.id == effect }
                    print("\(when): switches \(described?.switches?.map { "\($0.name)=\($0.value)" } ?? []), values \(described?.values.count ?? 0), maps \(described?.masks?.map(\.slot) ?? [])")
                }
                show("before")
                if let item = model.description?.object(id)?.effects.first(where: { $0.id == effect })?.switches?.first(where: { $0.name == CommandLine.arguments[index + 2] }) {
                    model.setEffectSwitch(item, to: value, object: id, effect: effect)
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                show("after")
            }
            // `--paint <effect> [slot]`: the selected object's effect's mask opened to paint, `--paint-setup
            // <size> <value> <hardness> <opacity>` for the brush, `--paint-show` with it shown.
            if let effect = values(of: "--paint").last.flatMap(Int.init), let id = model.selection {
                for _ in 0..<40 where model.description?.object(id)?.effects.first(where: { $0.id == effect }) == nil {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                let masks = model.description?.object(id)?.effects.first { $0.id == effect }?.masks ?? []
                print("masks of effect \(effect): \(masks.map { "\($0.label) slot \($0.slot) passes \($0.passes) fill \($0.fill)" })")
                if let mask = masks.first {
                    model.startPainting(.init(object: id, effect: effect, mask: mask))
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    if let index = CommandLine.arguments.firstIndex(of: "--paint-setup"), index + 4 < CommandLine.arguments.count, let paint = model.painting {
                        let numbers = CommandLine.arguments[(index + 1)...(index + 4)].compactMap(Double.init)
                        paint.size = numbers[0]
                        paint.value = numbers[1]
                        paint.hardness = numbers[2]
                        paint.opacity = numbers[3]
                    }
                    if let kind = values(of: "--paint-brush").last.flatMap(EngineMaskPaint.Brush.init(rawValue:)) {
                        model.painting?.brush = kind
                    }
                    model.painting?.isolates = CommandLine.arguments.contains("--paint-isolate")
                    model.painting?.isPicking = CommandLine.arguments.contains("--paint-pick")
                    model.painting?.showsMask = CommandLine.arguments.contains("--paint-show")
                    print("painting \(model.painting?.texture ?? "nothing"), new \(model.painting?.isNew ?? false), mask \(model.painting?.mask.width ?? 0)×\(model.painting?.mask.height ?? 0)")
                }
            }
            // `--window-drag <x0> <y0> <x1> <y1>`: the mouse pressed, dragged and let go, in points
            // of the window from its bottom left, as the window gets it.
            // Given several times, one after another.
            for index in CommandLine.arguments.indices where CommandLine.arguments[index] == "--window-drag" && index + 4 < CommandLine.arguments.count {
                let numbers = CommandLine.arguments[(index + 1)...(index + 4)].compactMap(Double.init)
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(nanoseconds: 600_000_000)
                for step in 0...8 {
                    let share = Double(step) / 8
                    let at = NSPoint(x: numbers[0] + (numbers[2] - numbers[0]) * share, y: numbers[1] + (numbers[3] - numbers[1]) * share)
                    var held = NSEvent.ModifierFlags()
                    if values(of: "--drag-keys").last?.contains("c") == true { held.insert(.control) }
                    if values(of: "--drag-keys").last?.contains("s") == true { held.insert(.shift) }
                    if let event = NSEvent.mouseEvent(with: step == 0 ? .leftMouseDown : .leftMouseDragged, location: at, modifierFlags: held,
                                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                      context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                        NSApp.postEvent(event, atStart: false)
                    }
                    try? await Task.sleep(nanoseconds: 40_000_000)
                }
                if let event = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: numbers[2], y: numbers[3]), modifierFlags: [],
                                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                  context: nil, eventNumber: 0, clickCount: 1, pressure: 0) {
                    NSApp.postEvent(event, atStart: false)
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
                if let paint = model.painting {
                    print("brush after the drag: size \(paint.size), opacity \(paint.opacity), hardness \(paint.hardness), value \(paint.value), undo \(paint.canUndo)")
                }
                print("after the drag: frame \(model.timelineFrame), keys \(model.activeAnimation?.keyFrames ?? []), selected \(model.selectedKeys.map(\.frame).sorted()), undo \(model.canUndo), handles at 30 \(model.activeAnimation?.keys(0).first { $0.frame == 30 }.map { "\($0.back.map { [$0.x, $0.y] } ?? []) \($0.front.map { [$0.x, $0.y] } ?? [])" } ?? "")")
            }
            // `--script <key>`: the panel of scripts, on the script of a value of the selection, made
            // if there is none (`general:<key>` for one of the scene); `--script-text <file>`,
            // that text typed in; `--script-apply`, applied.
            if let key = values(of: "--script").last {
                model.showsScripts = true
                let target: WallpaperEngineScriptTarget = key.hasPrefix("general:") ? .general(String(key.dropFirst(8))) : .value(object: model.selection ?? 0, key: key)
                try? await Task.sleep(nanoseconds: 800_000_000)
                if model.document.script(of: target) == nil { model.addScript(target) } else { model.openScript(target) }
                try? await Task.sleep(nanoseconds: 300_000_000)
                if let file = values(of: "--script-text").last, let text = try? String(contentsOfFile: file, encoding: .utf8) {
                    model.scriptView?.replaceAll(with: text)
                }
                if let id = values(of: "--script-example").last, let example = WallpaperEngineScriptText.examples.first(where: { $0.id == id }) {
                    model.useExample(example)
                }
                if CommandLine.arguments.contains("--script-apply") {
                    print("applied: \(model.applyScript()), problem \(model.scriptProblem.map { "line \($0.line): \($0.message)" } ?? "none")")
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    model.readScriptReport()
                }
                // `--script-typing`: what typing does: a new line keeps the indent, Undo takes back
                // text and not the scene, and names are offered.
                if CommandLine.arguments.contains("--script-typing"), let text = model.scriptView {
                    window.makeFirstResponder(text)
                    let start = (text.string as NSString).range(of: "return").location
                    text.setSelectedRange(NSRange(location: start, length: 0))
                    let before = text.string
                    text.insertNewline(nil)
                    let line = (text.string as NSString).substring(with: NSRange(location: start, length: 3))
                    print("after a new line: \(line.debugDescription)")
                    text.insertText("engine.", replacementRange: text.selectedRange())
                    var index = 0
                    let at = text.selectedRange().location
                    print("names after engine.: \(text.completions(forPartialWordRange: NSRange(location: at, length: 0), indexOfSelectedItem: &index)?.prefix(4).map { $0 } ?? [])")
                    let steps = model.canUndo
                    for _ in 0..<4 { model.undo() }
                    print("undone: \(text.string == before), draft follows \(model.scriptDraft == text.string), scene steps \(steps) → \(model.canUndo)")
                }
                let colored = Date()
                model.scriptView?.showColors(problemLine: model.scriptProblem?.line)
                print("colors in \(Int(Date().timeIntervalSince(colored) * 1000)) ms")
                print("script \(model.scriptTarget.map(model.title(of:)) ?? "none"): \(model.scriptDraft.count) characters, changed \(model.scriptIsChanged), settings \(model.scriptSettings.map(\.name)), problem \(model.scriptProblem.map { "line \($0.line): \($0.message) \($0.during ?? "")" } ?? "none"), log \(model.scriptLog.suffix(3))")
            }
            // `--scene-menu <x> <y>`: the right button at a point of the preview, in points from its
            // top left; `--scene-menu-pick <title>…`, a way through the menus to an item to choose.
            if let index = CommandLine.arguments.firstIndex(of: "--scene-menu"), index + 2 < CommandLine.arguments.count {
                let numbers = CommandLine.arguments[(index + 1)...(index + 2)].compactMap(Double.init)
                var menu = preview.sceneMenu(at: CGPoint(x: numbers[0], y: numbers[1]))
                print("scene menu: \(menu?.items.map(\.title) ?? [])")
                for title in values(of: "--scene-menu-pick") {
                    guard let found = menu?.items.first(where: { $0.title == title }) else { print("no \(title)"); break }
                    if let inner = found.submenu {
                        menu = inner
                        print("in \(title): \(inner.items.map(\.title))")
                    } else {
                        NSApp.sendAction(found.action!, to: found.target, from: found)
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                print("selected \(model.selection.map(String.init) ?? "nothing"): \(model.selection.flatMap { model.document.object($0)?["origin"]?.plain.stringValue } ?? "")")
            }
            // `--paint-speed`: how long the scene takes to be given the whole mask.
            if CommandLine.arguments.contains("--paint-speed"), let paint = model.painting {
                let start = Date()
                for _ in 0..<30 { paint.push() }
                print("mask \(paint.mask.width)×\(paint.mask.height): \(Int(Date().timeIntervalSince(start) * 1000 / 30)) ms a time")
            }
            // `--paint-end done|cancel`, after the drags, and `--paint-back`, a step back after that.
            if let end = values(of: "--paint-end").last {
                model.finishPainting(keeping: end == "done")
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                print("ended \(end): texture \(model.document.effectTexture(object: model.selection ?? 0, effect: values(of: "--paint").last.flatMap(Int.init) ?? 0, pass: 0, slot: 1) ?? "none"), undo \(model.canUndo)")
                if CommandLine.arguments.contains("--paint-back") {
                    model.undo()
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    print("back: texture \(model.document.effectTexture(object: model.selection ?? 0, effect: values(of: "--paint").last.flatMap(Int.init) ?? 0, pass: 0, slot: 1) ?? "none"), redo \(model.canRedo)")
                }
                model.close()
                print("masks left: \((try? FileManager.default.contentsOfDirectory(atPath: model.projectFolder.appendingPathComponent("materials/masks").path)) ?? [])")
            }
            // `--wheel <x> <y> <lines>`: the wheel turned over a point of the window, from its top left;
            // `--wheel-heights` as with Shift. A wheel event made here belongs to no window, so
            // this starts past the point where the mouse's own are told from others.
            if let index = CommandLine.arguments.firstIndex(of: "--wheel"), index + 3 < CommandLine.arguments.count {
                let numbers = CommandLine.arguments[(index + 1)...(index + 3)].compactMap(Double.init)
                // The timeline has to have come out first.
                try? await Task.sleep(nanoseconds: 700_000_000)
                let heights = CommandLine.arguments.contains("--wheel-heights")
                let taken = preview.turnWheel(at: CGPoint(x: numbers[0], y: numbers[1]), across: 0, along: numbers[2], precise: false, heights: heights)
                try? await Task.sleep(nanoseconds: 300_000_000)
                print("the wheel taken: \(taken); curves \(model.curveRange.map { "\($0)" } ?? "fitted")")
                print("after the wheel: start \(model.timelineStart), shown \(model.timelineShown) of \(model.timelineTotal), area \(model.timelineArea)")
            }
            // `--timeline-test`: an animation made and shown, checked against what the player says.
            if CommandLine.arguments.contains("--timeline-test"), let id = model.selection {
                await timelineTest(model, preview, object: id)
            }
            // `--curve-check`: every animation of the scene, worked out here and by the player.
            if CommandLine.arguments.contains("--curve-check") {
                curveCheck(model, preview)
            }
            // `--press <letters>`: the keys pressed in turn, as they come from the keyboard, saying
            // what each did; `,` stands for the search field taking the keys, `.` for its leaving them.
            if let letters = values(of: "--press").last {
                let codes: [Character: UInt16] = ["w": 13, "g": 5, "r": 15, "s": 1, "h": 4, " ": 49, "k": 40, "a": 0, "t": 17, "<": 123, ">": 124,
                                                  "C": 8, "V": 9, "x": 51, "m": 46, "i": 34]
                for letter in letters {
                    if letter == "," || letter == "." {
                        func field(in view: NSView) -> NSSearchField? {
                            (view as? NSSearchField) ?? view.subviews.lazy.compactMap(field(in:)).first
                        }
                        window.makeFirstResponder(letter == "," ? window.contentView.flatMap(field(in:)) : nil)
                    } else if letter == "B" {
                        model.setSelectedInterpolation(.both)
                    } else if let code = codes[letter], let event = NSEvent.keyEvent(
                        with: .keyDown, location: .zero, modifierFlags: letter.isUppercase ? [.command] : [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, characters: String(letter),
                        charactersIgnoringModifiers: String(letter), isARepeat: false, keyCode: code) {
                        NSApp.activate(ignoringOtherApps: true)
                        window.makeKeyAndOrderFront(nil)
                        NSApp.postEvent(event, atStart: false)
                    }
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    if let paint = model.painting {
                        print("brush: shows mask \(paint.showsMask), picking \(paint.isPicking)")
                    }
                    print("“\(letter)”: frame \(model.timelineFrame), keys \(model.activeAnimation?.keyFrames ?? []), auto \(model.autoKey), timeline \(model.showsTimeline), tool \(model.tool), playing \(model.isPlaying), "
                        + "visible \(model.selection.map(model.isVisible) ?? true), filter “\(model.layerFilter)”")
                }
                window.makeFirstResponder(nil)
            }
            // `--zoom-steps`: the scene enlarged and made small again step by step, as a pinch does,
            // saying how late the app got behind the steps at worst.
            if CommandLine.arguments.contains("--zoom-steps") {
                var worst = 0.0
                for step in 0..<60 {
                    let before = ProcessInfo.processInfo.systemUptime
                    model.zoomView(by: step < 30 ? 1.05 : 1 / 1.05, around: .zero)
                    try? await Task.sleep(nanoseconds: 16_000_000)
                    worst = max(worst, ProcessInfo.processInfo.systemUptime - before - 0.016)
                }
                print("zoom steps: at the end \(model.viewZoom), latest by \(Int(worst * 1000)) ms")
            }
            // `--drag <x0> <y0> <x1> <y1>`: the mouse dragged over the preview, in shares of its size.
            let arguments0 = CommandLine.arguments
            if let index = arguments0.firstIndex(of: "--drag"), index + 4 < arguments0.count,
               let x0 = Double(arguments0[index + 1]), let y0 = Double(arguments0[index + 2]),
               let x1 = Double(arguments0[index + 3]), let y1 = Double(arguments0[index + 4]) {
                try? await Task.sleep(nanoseconds: 500_000_000)
                preview.drag(from: CGPoint(x: x0, y: y0), to: CGPoint(x: x1, y: y1))
                try? await Task.sleep(nanoseconds: 500_000_000)
                print("after the drag: selection \(model.selection.map(String.init) ?? "scene"), undo: \(model.canUndo)")
            }
            for name in values(of: "--add-particles") {
                if let preset = WallpaperEngineParticlePreset.named(name) { model.addParticles(preset) }
            }
            if CommandLine.arguments.contains("--add-text") { model.addText() }
            for name in values(of: "--add-effect") {
                if let effect = WallpaperEngineEffect.named(name), let selection = model.selection { model.addEffect(effect, to: selection) }
            }
            let arguments = CommandLine.arguments
            for index in arguments.indices where arguments[index] == "--set" && index + 2 < arguments.count {
                if let selection = model.selection, let number = Double(arguments[index + 2]) {
                    model.change { $0.update(selection) { $0[arguments[index + 1]] = .number(number) } }
                }
            }
            for _ in 0..<(values(of: "--undo").last.flatMap(Int.init) ?? 0) { model.undo() }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            model.saveNow()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if let sheet = values(of: "--sheet").last, let selection = model.selection {
                switch sheet {
                case "effects": model.sheet = .effects(object: selection)
                case "puppet": model.puppetObject = selection
                case "options":
                    if let target = model.timelineTarget {
                        model.sheet = .animation(object: selection, target: target, isNew: false, fallback: [])
                    }
                case "events":
                    if let target = model.timelineTarget { model.sheet = .events(target: target) }
                default: break
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            print("selection: \(model.selection.map(String.init) ?? "scene"); undo: \(model.canUndo)")
            for row in model.rows {
                print(String(repeating: "  ", count: row.depth + 1) + "#\(row.id) \(model.name(of: row.id)) [\(model.kind(of: row.id).rawValue)]")
            }
            if let description = model.description {
                for object in description.objects where !object.effects.isEmpty {
                    print("  effects of #\(object.id): " + object.effects.map { "\($0.title) (\($0.values.count))" }.joined(separator: ", "))
                }
            }
            var image: CGImage?
            if #available(macOS 14.4, *) {
                image = try? await captureWithScreenCaptureKit(window)
            }
            if let image = image ?? drawViews(of: window) {
                write(image, to: request.output)
                print("wrote \(request.output.path) (\(image.width)×\(image.height))")
            }
            // `--inspector-pages`: the properties a screen at a time, as <output>-2.png and on.
            if CommandLine.arguments.contains("--inspector-pages") {
                await pictureInspectorPages(of: window, to: request.output)
            }
            model.saveNow()
            exit(0)
        }
    }

    private static func timelineTest(_ model: EngineEditorModel, _ preview: EngineEditorPreviewController, object id: Int) async {
        @MainActor func middle() -> [Double] { preview.outlineMiddle(of: id) }
        func pause(_ seconds: Double = 0.3) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        let target = WallpaperEngineAnimationTarget.value("origin")
        if model.document.animation(of: id, target) != nil { model.unbindAnimation(target) }
        model.showsTimeline = true
        await pause()
        let before = middle()
        model.bindAnimation(target, options: .init(fps: 30, length: 60, mode: .loop), fallback: [0, 0, 0])
        model.timelineSeconds = 1
        let start = model.value(id, "origin")?.vector ?? [0, 0, 0]
        // The way the frame on the scene writes a move, at the moment the timeline stands at.
        model.applyFromPreview(object: id, patch: ["x": start[0] + 300, "y": start[1]])
        await pause()
        let moved = middle()
        print("frame 30: origin \(model.value(id, "origin")?.stringValue ?? "?"), keys \(model.activeAnimation?.keyFrames ?? []), on the page \(before) → \(moved)")
        model.timelineSeconds = 0
        await pause()
        print("frame 0: on the page \(middle()), origin \(model.value(id, "origin")?.stringValue ?? "?")")
        model.timelineSeconds = 0.5
        await pause()
        print("frame 15: on the page \(middle()), origin \(model.value(id, "origin")?.stringValue ?? "?")")
        model.isPlaying = false
        await pause()
        model.timelineSeconds = 1
        await pause()
        print("frame 30, scene paused: on the page \(middle())")
        model.isPlaying = true
    }

    private static func curveCheck(_ model: EngineEditorModel, _ preview: EngineEditorPreviewController) {
        var checked = 0, wrong = 0, worst = 0.0
        for id in model.document.objectIDs {
            for target in model.document.animatedTargets(of: id) {
                guard let animation = model.document.animation(of: id, target) else { continue }
                let base = model.document.rawValue(of: id, target)?.vector ?? Array(repeating: 0, count: animation.channelCount)
                for step in 0...40 {
                    let seconds = Double(step) * max(animation.duration, 0.1) / 17
                    let own = animation.numbers(atSeconds: seconds, base: base)
                    guard let theirs = preview.curveValue(animation.raw, seconds: seconds, base: base) else { continue }
                    checked += 1
                    let off = zip(own, theirs).map { abs($0 - $1) }.max() ?? 0
                    worst = max(worst, off)
                    if off > 1e-3 * max(1, own.map(abs).max() ?? 1) { wrong += 1 }
                }
            }
        }
        print("curves: \(checked) moments compared, \(wrong) differ, by \(worst) at most")
    }

    /// A made-up sound: silence and a tone by turns, starting with silence and ending in it.
    private final class SyntheticSound: SoundSource {
        let sampleRate = 48_000.0
        private let turns: [Double]
        private var timer: DispatchSourceTimer?
        private var frame = 0
        private var sounded = false

        /// - Parameter turns: how many seconds each turn lasts.
        init(turns: [Double]) {
            self.turns = turns
        }

        func start(on queue: DispatchQueue, handler: @escaping (UnsafePointer<AudioBufferList>) -> Void) throws {
            let frames = 512 // what the Mac hands over at a time
            var samples = [Float](repeating: 0, count: frames * 2)
            // Strict, as sound itself is: it arrives on time whatever else the Mac is doing.
            let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
            timer.schedule(deadline: .now(), repeating: Double(frames) / sampleRate, leeway: .milliseconds(1))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let sounds = self.sounds(at: Double(self.frame) / self.sampleRate)
                if sounds != self.sounded {
                    self.sounded = sounds
                    print(sounds ? "— the tone starts —" : "— the tone stops —")
                }
                for index in 0..<frames {
                    let phase = 2 * Double.pi * 1000 * Double(self.frame + index) / self.sampleRate
                    let value: Float = sounds ? 0.3 * Float(sin(phase)) : 0
                    samples[index * 2] = value
                    samples[index * 2 + 1] = value
                }
                self.frame += frames
                samples.withUnsafeMutableBytes { bytes in
                    var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                        mNumberChannels: 2, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
                    handler(&list)
                }
            }
            timer.resume()
            self.timer = timer
        }

        func stop() {
            timer?.cancel()
            timer = nil
        }

        private func sounds(at time: Double) -> Bool {
            var start = 0.0
            for (index, length) in turns.enumerated() {
                if time < start + length { return index % 2 == 1 }
                start += length
            }
            return false
        }
    }

    // MARK: - A scene of Wallpaper Engine's

    /// `--engine-test <scene folder> <picture.png> [--after <seconds>] [--size <w> <h>] [--eval-at
    /// <seconds> <JavaScript>]… [--eval-end <JavaScript>]` shows a scene in a window nothing
    /// covers, lets it play for a while and takes a picture of it; then it prints what the
    /// player of Wallpaper Engine's scenes has to report — what it drew, what it left out and
    /// why — and what the script comes to. A script given with `--eval-at` runs that many
    /// seconds in: to change a setting, or to move the pointer.
    static var engineTest: (folder: URL, output: URL)? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--engine-test"), index + 2 < arguments.count else { return nil }
        return (URL(fileURLWithPath: arguments[index + 1], isDirectory: true), URL(fileURLWithPath: arguments[index + 2]))
    }

    static func runEngineTest(_ request: (folder: URL, output: URL)) {
        NSApp.setActivationPolicy(.accessory)
        let arguments = CommandLine.arguments
        var size = NSSize(width: 960, height: 540)
        if let index = arguments.firstIndex(of: "--size"), index + 2 < arguments.count,
           let width = Double(arguments[index + 1]), let height = Double(arguments[index + 2]) {
            size = NSSize(width: width, height: height)
        }
        let seconds = values(of: "--after").last.flatMap(Double.init) ?? 3
        guard let project = WebProject(folder: request.folder) else {
            print("no page in \(request.folder.path)")
            exit(1)
        }
        let view = WebWallpaperView(frame: NSRect(origin: .zero, size: size))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = view
        window.orderFrontRegardless()
        view.frameRate = values(of: "--fps").last.flatMap(Int.init) ?? 0
        view.setPlaying(true, rate: 1)
        view.show(project, watchingForChanges: false)
        Task {
            await view.waitUntilLoaded()
            for (index, argument) in arguments.enumerated() where argument == "--eval-at" && index + 2 < arguments.count {
                guard let moment = Double(arguments[index + 1]) else { continue }
                let script = arguments[index + 2]
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(max(0, moment) * 1_000_000_000))
                    let value = await view.value(of: script)
                    print("eval at \(moment) s: \(value.map { "\($0)" } ?? "nothing")")
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if let image = await view.snapshot() {
                let bitmap = NSBitmapImageRep(cgImage: image)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: request.output)
                print("wrote \(request.output.path) (\(image.width)×\(image.height))")
            } else {
                print("no picture could be taken")
            }
            let report = await view.value(of: "window.WallaeroEngine && window.WallaeroEngine.report ? window.WallaeroEngine.report() : 'no player on the page'")
            print(report as? String ?? "nothing reported")
            for script in values(of: "--eval-end") {
                let value = await view.value(of: script)
                print("eval: \(value.map { "\($0)" } ?? "nothing")")
            }
            exit(0)
        }
    }

    // MARK: - Cover

    /// `--cover-test <seconds>` watches the main display the way a wallpaper's window does and
    /// prints, whenever it changes and once a second, how much of the desktop shows around the
    /// windows over it and whether that counts as covered. No wallpaper is shown.
    static var coverTestSeconds: Double? {
        values(of: "--cover-test").last.flatMap(Double.init)
    }

    static func coverTest(_ seconds: Double) {
        NSApp.setActivationPolicy(.accessory)
        guard let screen = NSScreen.main else { exit(1) }
        let visibility = DesktopVisibility(screen: screen)
        let started = CFAbsoluteTimeGetCurrent()
        func say(_ what: String) {
            print(String(format: "%5.1f s  %@: %.0f %% of the desktop shows, %@", CFAbsoluteTimeGetCurrent() - started, what,
                         visibility.seenShare * 100, visibility.isCovered ? "covered" : "in view"))
            fflush(stdout)
        }
        visibility.onChange = { say("changed") }
        visibility.show()
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { say("      ") }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            timer.invalidate()
            visibility.hide()
            exit(0)
        }
    }

    // MARK: - Energy

    /// `--energy-test <video, picture or web wallpaper folder> [--seconds <n>] [--window <w> <h>]`
    /// plays a wallpaper the way the desktop does, in a window nothing covers, so that what it
    /// costs can be measured from outside (`top -stats pid,command,cpu,power`); the helper only
    /// prints its process identifier and waits. A web wallpaper is told about sound as the app
    /// would tell it, without listening to the Mac: `--sound music` hands it a moving spectrum
    /// thirty times a second, `--sound silence` zeros four times a second, and without the
    /// option it is told nothing, as when the reaction to sound is switched off. `--eval
    /// <JavaScript>` runs in the page once it has loaded and `--eval-end <JavaScript>` when it
    /// has played, each printing what it comes to; `--pause-after <seconds>` pauses the
    /// wallpaper then, the way the app does when windows cover the desktop.
    ///
    /// `--twice [--shared]` shows it in a second window too, played there or shown from the first.
    /// `--native` draws a scene of Wallpaper Engine's with the app's own renderer, as the desktop does.
    /// `--full-screen` makes the window as large as the main display, which is what a wallpaper
    /// costs for real, and `--zoomed` as large as a window gets short of that, to serve as one
    /// lying over the desktop. `--fps <n>` and `--render-scale <part>` are the app's two settings
    /// for what a web wallpaper costs: its frame rate, and the part of the display's resolution
    /// it draws at.
    static var energyTestTarget: URL? {
        values(of: "--energy-test").last.map { URL(fileURLWithPath: $0) }
    }

    static func energyTest(_ target: URL) {
        NSApp.setActivationPolicy(.accessory)
        var size = NSSize(width: 1280, height: 800)
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--window"), index + 2 < arguments.count,
           let width = Double(arguments[index + 1]), let height = Double(arguments[index + 2]) {
            size = NSSize(width: width, height: height)
        }
        let seconds = values(of: "--seconds").last.flatMap(Double.init) ?? 20
        var origin = NSPoint(x: 60, y: 60)
        // `--full-screen`: as large as the main display, which is what a wallpaper costs for real.
        // `--zoomed`: as large as a window made as large as it gets, which leaves the menu bar
        // and the Dock out; the helper then serves as such a window over the desktop.
        if arguments.contains("--full-screen"), let screen = NSScreen.main {
            size = screen.frame.size
            origin = screen.frame.origin
        } else if arguments.contains("--zoomed"), let screen = NSScreen.main {
            size = screen.visibleFrame.size
            origin = screen.visibleFrame.origin
        }
        let window = NSWindow(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        // On every Space and over full-screen apps: a page that goes out of sight stops, and
        // the measurement with it.
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = .black
        let view = WallpaperView(frame: NSRect(origin: .zero, size: size))
        window.contentView = view
        view.setPlaying(true, rate: 1)
        // `--fps <n>` and `--render-scale <part>`: the app's own two ways of making a page cost less.
        view.setDrawing(frameRate: values(of: "--fps").last.flatMap(Int.init) ?? 0,
                        renderScale: values(of: "--render-scale").last.flatMap(Double.init) ?? 1)
        var isFolder: ObjCBool = false
        FileManager.default.fileExists(atPath: target.path, isDirectory: &isFolder)
        if isFolder.boolValue, let project = WebProject(folder: target) {
            // `--native`: a scene of Wallpaper Engine's drawn by the app itself, as on the desktop.
            if arguments.contains("--native"), SceneProject.isNativelyPlayable(target), view.showNativeScene(target) {
                print("drawn by the app")
            } else {
                view.showWeb(project, hearsSound: false)
            }
        } else if UTType(filenameExtension: target.pathExtension)?.conforms(to: .image) == true {
            view.showImage(at: target)
        } else {
            view.showVideo(at: target)
        }
        window.orderFrontRegardless()
        // `--twice`: the same wallpaper in a second, smaller window, as on a second display —
        // played there on its own, or with `--shared` shown from the first as the app does.
        var second: WallpaperView?
        if arguments.contains("--twice") {
            let other = NSWindow(contentRect: NSRect(x: origin.x + 40, y: origin.y + 40, width: size.width * 0.6, height: size.height * 0.5),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
            other.isReleasedWhenClosed = false
            other.level = .floating
            other.collectionBehavior = window.collectionBehavior
            let view2 = WallpaperView(frame: NSRect(origin: .zero, size: other.frame.size))
            other.contentView = view2
            view2.setPlaying(true, rate: 1)
            view2.setDrawing(frameRate: values(of: "--fps").last.flatMap(Int.init) ?? 0,
                             renderScale: values(of: "--render-scale").last.flatMap(Double.init) ?? 1)
            if arguments.contains("--shared") {
                view2.follow(view)
            } else if isFolder.boolValue, let project = WebProject(folder: target) {
                if !(arguments.contains("--native") && SceneProject.isNativelyPlayable(target) && view2.showNativeScene(target)) {
                    view2.showWeb(project, hearsSound: false)
                }
            } else {
                view2.showVideo(at: target)
            }
            other.orderFrontRegardless()
            second = view2
        }
        print("pid \(ProcessInfo.processInfo.processIdentifier)")
        fflush(stdout)
        Task {
            await view.webView?.waitUntilLoaded()
            for script in values(of: "--eval") {
                let value = await view.webView?.value(of: script)
                print("eval: \(value.map { "\($0)" } ?? "nothing")")
                fflush(stdout)
            }
        }
        if let pause = values(of: "--pause-after").last.flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
                view.setPlaying(false, rate: 1)
            }
        }
        // `--frame-at <seconds> <picture.png>`: the picture the lock screen would get then.
        if let index = arguments.firstIndex(of: "--frame-at"), index + 2 < arguments.count,
           let moment = Double(arguments[index + 1]) {
            let output = URL(fileURLWithPath: arguments[index + 2])
            DispatchQueue.main.asyncAfter(deadline: .now() + moment) {
                Task {
                    if let frame = await view.currentFrame(),
                       let data = NSBitmapImageRep(cgImage: frame).representation(using: .png, properties: [:]) {
                        try? data.write(to: output)
                        print("frame at \(moment) s: \(frame.width)×\(frame.height) → \(output.path)")
                    } else {
                        print("frame at \(moment) s: none")
                    }
                    if let second, let frame = await second.currentFrame(),
                       let data = NSBitmapImageRep(cgImage: frame).representation(using: .png, properties: [:]) {
                        let path = output.deletingPathExtension().path + "-second.png"
                        try? data.write(to: URL(fileURLWithPath: path))
                        print("second window: \(frame.width)×\(frame.height) → \(path)")
                    }
                    if let scene = view.nativeView, arguments.contains("--shared") {
                        print("frames copied to the second window: \(scene.mirroredFrames)")
                    }
                    if let second {
                        print("second window plays a video of the first: \(second.sharesPlayer(with: view))")
                    }
                    fflush(stdout)
                }
            }
        }

        // How many of the seconds the window was out of sight, covered or on another Space.
        var hiddenSeconds = 0
        let watch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated {
                if !window.occlusionState.contains(.visible) { hiddenSeconds += 1 }
            }
        }
        let sound = values(of: "--sound").last
        let started = CFAbsoluteTimeGetCurrent()
        var timer: Timer?
        if sound == "music" || sound == "silence" {
            timer = Timer.scheduledTimer(withTimeInterval: sound == "music" ? 1.0 / 30 : 0.25, repeats: true) { _ in
                let time = CFAbsoluteTimeGetCurrent() - started
                // Something like music: a beat in the low bands, slower waves across the rest.
                var levels = [Float](repeating: 0, count: 128)
                if sound == "music" {
                    for index in levels.indices {
                        let band = Double(index % 64) / 64
                        let kick: Double = pow(max(0, sin(time * 4 * Double.pi)), 6)
                        let beat: Double = kick * max(0, 1 - band * 3)
                        let fast: Double = sin(time * (1.3 + band * 5) + band * 20)
                        let slow: Double = sin(time * 0.7 + band * 9)
                        let wave: Double = 0.35 + 0.3 * fast * slow
                        let level: Double = wave * (1 - band * 0.5) + beat * 0.6
                        levels[index] = Float(min(1, max(0, level)))
                    }
                }
                MainActor.assumeIsolated {
                    view.webView?.evaluate(SoundSpectrum.script(for: levels))
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            timer?.invalidate()
            watch.invalidate()
            Task {
                // Whether the wallpaper was really playing all that time: a measurement of a
                // page that stood hidden behind another window says nothing.
                print("hidden \(hiddenSeconds) s")
                // `--eval-end <JavaScript>`: what the page has to say once it has played.
                for script in values(of: "--eval-end") {
                    let value = await view.webView?.value(of: script)
                    print("eval: \(value.map { "\($0)" } ?? "nothing")")
                }
                if let page = view.webView {
                    let state = await page.value(of: "(function () { var v = document.querySelector('video'); return document.visibilityState + ', video ' + (v ? (v.paused ? 'paused' : 'playing') + ' at ' + v.currentTime.toFixed(1) + ' of ' + v.duration.toFixed(1) + ' s, ' + (v.getVideoPlaybackQuality ? v.getVideoPlaybackQuality().totalVideoFrames + ' frames' : '') : 'none'); })()")
                    print("page \(state as? String ?? "?")")
                }
                exit(0)
            }
        }
    }

    // MARK: - A wallpaper's settings

    /// `--settings-test <scene folder>` does to a scene what the wallpaper's settings do when a
    /// value is changed in them, and prints what ends up on disk; then it changes the scene file
    /// from outside, as the editor would, and prints whether the settings took that over.
    static var settingsTestFolder: URL? {
        values(of: "--settings-test").last.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func settingsTest(_ folder: URL) {
        NSApp.setActivationPolicy(.accessory)
        let item = Wallpaper(id: UUID(), name: folder.lastPathComponent, kind: .web, fileName: "index.html", thumbnailFileName: nil,
                             sourceFormat: "SCENE", wasConverted: false, pixelWidth: 0, pixelHeight: 0, duration: nil,
                             hasAudio: false, fileSize: 0)
        let model = WallpaperSettingsModel()
        model.show(item, folder: folder)
        func describe(_ scene: WallpaperScene?) -> String {
            (scene?.variables ?? []).map { variable in
                switch variable.kind {
                case .color: return "\(variable.key)=\(variable.color)"
                case .number: return "\(variable.key)=\(variable.number)"
                case .toggle: return "\(variable.key)=\(variable.isOn)"
                case .text, .choice: return "\(variable.key)=\(variable.text)"
                }
            }.joined(separator: ", ")
        }
        Task {
            print("read:           ", describe(model.scene))
            for variable in model.scene?.variables ?? [] {
                guard let binding = model.binding(for: variable.id) else { continue }
                switch variable.kind {
                case .color: binding.wrappedValue.color = "#123456"
                case .number: binding.wrappedValue.number = variable.number + 1
                case .toggle: binding.wrappedValue.isOn.toggle()
                case .text: binding.wrappedValue.text = variable.text + "!"
                case .choice: binding.wrappedValue.text = variable.options.last ?? variable.text
                }
            }
            print("set:            ", describe(model.scene))
            print("on disk at once:", describe(try? SceneProject.read(from: folder)))
            try? await Task.sleep(nanoseconds: 800_000_000)
            print("on disk later:  ", describe(try? SceneProject.read(from: folder)))

            // From outside: a variable goes, another's value changes.
            if var edited = try? SceneProject.read(from: folder), !edited.variables.isEmpty {
                edited.variables.removeLast()
                if !edited.variables.isEmpty, edited.variables[0].kind == .color {
                    edited.variables[0].color = "#ABCDEF"
                }
                try? SceneProject.write(edited, to: folder)
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            print("after an edit from outside:", describe(model.scene))
            exit(0)
        }
    }

    // MARK: - The first picture

    /// `--ready-test <video, picture or web wallpaper folder> [--picture <file.png>]` shows a
    /// wallpaper the way a desktop window does — out of sight until it has a picture — and
    /// prints how long that took and how much of the window was still black when it was revealed.
    /// With `--watch <seconds>` it keeps looking for that long and reports the blackest moment,
    /// when a picture first came, and whether a web wallpaper's page was loaded anew; `--touch <file name>` rewrites a file
    /// of the wallpaper meanwhile, as saving it in an editor would. `--scaling fill|fit|stretch`
    /// and `--position <percent>` show a video or picture the way those settings of it would,
    /// in a window of `--window <width> <height>`. `--backdrop <picture>` gives a web wallpaper
    /// the picture that is seen until its page has drawn.
    static var readyTestTarget: URL? {
        values(of: "--ready-test").last.map { URL(fileURLWithPath: $0) }
    }

    static func readyTest(_ target: URL) {
        NSApp.setActivationPolicy(.accessory)
        var size = NSSize(width: 960, height: 600)
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--window"), index + 2 < arguments.count,
           let width = Double(arguments[index + 1]), let height = Double(arguments[index + 2]) {
            size = NSSize(width: width, height: height)
        }
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 120, y: 120), size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.backgroundColor = .black
        window.alphaValue = 0
        let view = WallpaperView(frame: NSRect(origin: .zero, size: size))
        window.contentView = view
        let started = CFAbsoluteTimeGetCurrent()
        view.onReady = {
            let waited = CFAbsoluteTimeGetCurrent() - started
            window.alphaValue = 1
            Task {
                var image: CGImage?
                if #available(macOS 14.4, *) {
                    image = try? await captureWithScreenCaptureKit(window)
                }
                let black = image.map { "\(Int((blackShare(of: $0) * 100).rounded())) %" } ?? "could not look"
                print(String(format: "ready after %.2f s; black when revealed: %@", waited, black))
                if let path = values(of: "--picture").last, let image {
                    write(image, to: URL(fileURLWithPath: path))
                }
                if let seconds = values(of: "--watch").last.flatMap(Double.init) {
                    _ = await view.webView?.value(of: "window.__sameLoad = true; 1")
                    var blackest = 0.0
                    var looks = 0
                    var touched = false
                    // When the window first had a picture and how black it was at the last look:
                    // a window black for a moment and one that stays black are not the same fault.
                    var pictureAfter: Double?
                    var last = 0.0
                    let watchStarted = CFAbsoluteTimeGetCurrent()
                    while CFAbsoluteTimeGetCurrent() - watchStarted < seconds {
                        if !touched, CFAbsoluteTimeGetCurrent() - watchStarted > 0.6, let name = values(of: "--touch").last {
                            touched = true
                            let file = target.appendingPathComponent(name)
                            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                            try? (text + "\n").write(to: file, atomically: true, encoding: .utf8)
                        }
                        if #available(macOS 14.4, *), let look = try? await captureWithScreenCaptureKit(window) {
                            last = blackShare(of: look)
                            blackest = max(blackest, last)
                            looks += 1
                            if pictureAfter == nil, last < 0.5 {
                                pictureAfter = CFAbsoluteTimeGetCurrent() - watchStarted
                            }
                        }
                        try? await Task.sleep(nanoseconds: 20_000_000)
                    }
                    let sameLoad = await view.webView?.value(of: "window.__sameLoad === true") as? Bool
                    print("watched \(looks) times: blackest \(Int((blackest * 100).rounded())) %; page loaded anew: \(sameLoad.map { $0 ? "no" : "yes" } ?? "not a page")")
                    print("a picture \(pictureAfter.map { String(format: "%.2f s after the reveal", $0) } ?? "never came"); black at the end: \(Int((last * 100).rounded())) %")
                }
                exit(0)
            }
        }
        view.setPlaying(true, rate: 1)
        var isFolder: ObjCBool = false
        FileManager.default.fileExists(atPath: target.path, isDirectory: &isFolder)
        // The size of the picture or of the video's frames, as the library would know it.
        var mediaSize = CGSize.zero
        if let source = CGImageSourceCreateWithURL(target as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Double, let height = properties[kCGImagePropertyPixelHeight] as? Double {
            mediaSize = CGSize(width: width, height: height)
        }
        let scaling = values(of: "--scaling").last.flatMap(ScalingMode.init(rawValue:)) ?? .fill
        let position = values(of: "--position").last.flatMap(Double.init) ?? 50
        view.setFraming(scaling, position: position, mediaSize: mediaSize)
        if mediaSize == .zero, !isFolder.boolValue {
            Task {
                guard let track = try? await AVURLAsset(url: target).loadTracks(withMediaType: .video).first,
                      let size = try? await track.load(.naturalSize) else { return }
                view.setFraming(scaling, position: position, mediaSize: size)
            }
        }
        if isFolder.boolValue, let project = WebProject(folder: target) {
            // `--backdrop <picture>` stands in for the library's picture of the page.
            view.showWeb(project, backdrop: values(of: "--backdrop").last.flatMap(NSImage.init(contentsOfFile:)))
        } else if UTType(filenameExtension: target.pathExtension)?.conforms(to: .image) == true {
            view.showImage(at: target)
        } else {
            view.showVideo(at: target)
        }
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            guard !view.isReady else { return }
            print("never became ready")
            exit(1)
        }
    }

    /// How much of a picture is black or nearly so, from 0 to 1.
    private static func blackShare(of image: CGImage) -> Double {
        let width = 96, height = 60
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let data = { () -> UnsafeMutablePointer<UInt8>? in
                  context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                  return context.data?.assumingMemoryBound(to: UInt8.self)
              }()
        else {
            return 1
        }
        var black = 0
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * context.bytesPerRow + x * 4
                if Int(data[offset]) + Int(data[offset + 1]) + Int(data[offset + 2]) < 36 { black += 1 }
            }
        }
        return Double(black) / Double(width * height)
    }

    // MARK: - Sound

    /// `--sound-test <seconds>` listens to the Mac's sound the way the app does for a wallpaper
    /// and prints, second by second, the levels that would reach the page. With
    /// `--scene <scene folder>` the scene is shown in a window and the report says what its page
    /// was really given, also while paused; `--picture <file.png>` saves how it looked at the end,
    /// `--eval <JavaScript>` runs in the page before the listening and `--eval-after <JavaScript>`
    /// after it, its value printed; `--eval-end <JavaScript>` runs last of all, once the page
    /// has been paused and set playing again. `--synthetic` listens to a made-up
    /// sound instead of the Mac's — three seconds of silence, four of a tone, three of silence,
    /// three of the tone, then silence — which needs no permission and always goes the same way.
    ///
    /// macOS grants the listening to the app that was launched, so start it through `open`:
    ///
    ///     open -n -W --stdout report.txt "build/WallAero Engine.app" --args --sound-test 8
    static var soundTestSeconds: Double? {
        values(of: "--sound-test").last.flatMap(Double.init)
    }

    static func soundTest(seconds: Double) {
        NSApp.setActivationPolicy(.accessory)
        final class Probe {
            var frames = 0
            var loudest: Float = 0
            var latest: [Float] = []
        }
        let probe = Probe()
        if CommandLine.arguments.contains("--synthetic") {
            SoundSpectrum.shared.makeSource = { SyntheticSound(turns: [3, 4, 3, 3]) }
        }
        SoundSpectrum.shared.addListener(probe) { script in
            // The numbers between the brackets of the script a page would run.
            guard let open = script.lastIndex(of: "["), let close = script.lastIndex(of: "]") else { return }
            let levels = script[script.index(after: open)..<close].split(separator: ",").compactMap { Float($0) }
            probe.frames += 1
            probe.latest = levels
            probe.loudest = max(probe.loudest, levels.max() ?? 0)
        }
        func line(_ label: String, page: String? = nil) {
            // Sixteen columns, low notes on the left, in tenths of the full height.
            let levels = probe.latest
            let columns = levels.count == 128
                ? (0..<16).map { column in (column * 4..<column * 4 + 4).map { max(levels[$0], levels[$0 + 64]) }.max() ?? 0 }
                : []
            let picture = columns.map { $0 >= 0.95 ? "#" : String(Int($0 * 10)) }.joined()
            print(label.padding(toLength: 14, withPad: " ", startingAt: 0),
                  String(format: "frames %3d  loudest %.2f  [%@]", probe.frames, probe.loudest, picture), page ?? "")
            fflush(stdout)
            probe.frames = 0
            probe.loudest = 0
        }

        Task {
            var view: WebWallpaperView?
            var window: NSWindow?
            if let folder = values(of: "--scene").last, let project = WebProject(folder: URL(fileURLWithPath: folder, isDirectory: true)) {
                let size = NSSize(width: 960, height: 540)
                let page = WebWallpaperView(frame: NSRect(origin: .zero, size: size))
                page.hearsSound = true
                let host = NSWindow(contentRect: NSRect(origin: NSPoint(x: 120, y: 120), size: size), styleMask: [.titled],
                                    backing: .buffered, defer: false)
                host.isReleasedWhenClosed = false
                host.level = .floating // a covered page pauses by itself
                host.contentView = page
                host.orderFrontRegardless()
                page.setPlaying(true, rate: 1)
                page.show(project, watchingForChanges: false)
                await page.waitUntilLoaded()
                _ = await page.value(of: """
                window.__heard = { frames: 0, loudest: 0, length: 0 };
                window.wallpaperRegisterAudioListener(function (levels) {
                  __heard.frames++; __heard.length = levels.length;
                  __heard.loudest = Math.max(__heard.loudest, Math.max.apply(null, levels));
                }); 1
                """)
                for script in values(of: "--eval") {
                    _ = await page.value(of: script)
                }
                view = page
                window = host
            }
            func heard() async -> String? {
                guard let view else { return nil }
                let text = await view.value(of: "var h = JSON.stringify(window.__heard); __heard.frames = 0; __heard.loudest = 0; h")
                return "| page: " + (text as? String ?? "?")
            }
            for second in 1...max(1, Int(seconds)) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                line("second \(second):", page: await heard())
            }
            if let view {
                for script in values(of: "--eval-after") {
                    print("eval:", await view.value(of: script) ?? "nil")
                }
                if let path = values(of: "--picture").last, let image = await view.snapshot() {
                    write(image, to: URL(fileURLWithPath: path))
                    print("wrote \(path) (\(image.width)×\(image.height))")
                }
                view.setPlaying(false, rate: 1)
                try? await Task.sleep(nanoseconds: 400_000_000)
                _ = await heard()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                // The listening goes on for this report, but a paused page must be told nothing.
                line("paused:", page: await heard())
                view.setPlaying(true, rate: 1)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                line("playing again:", page: await heard())
                for script in values(of: "--eval-end") {
                    print("eval at the end:", await view.value(of: script) ?? "nil")
                }
                view.unload()
                window?.close()
            }
            fflush(stdout)
            exit(0)
        }
    }

    /// Pictures are taken at the display's resolution, so a Retina display is preferred to
    /// whichever one happens to have the keyboard focus.
    private static func centerOnSharpestScreen(_ window: NSWindow) {
        guard let screen = NSScreen.screens.max(by: { $0.backingScaleFactor < $1.backingScaleFactor }) else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        window.setFrameOrigin(NSPoint(x: visible.midX - window.frame.width / 2, y: visible.midY - window.frame.height / 2))
    }

    private static func write(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}

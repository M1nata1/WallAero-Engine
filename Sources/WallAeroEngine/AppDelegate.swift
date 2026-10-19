import AppKit
import CEFHost
import Combine
import SwiftUI
import WallpaperCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let library: WallpaperLibrary
    private let preferences: Preferences
    private let manager: WallpaperManager
    private let importer: ImportCoordinator
    private let cursorSettings = CursorSettings()
    private var windows: WindowManager!
    private var statusMenu: StatusMenuController?
    private var cancellables: Set<AnyCancellable> = []
    private var isLaunched = false
    private var urlsOpenedBeforeLaunch: [URL] = []

    static func main() {
        DevelopmentRun.prepare()
        // The helpers a developer runs (all started with options) leave the music players
        // alone: macOS would ask the user's leave for a program they did not start themselves.
        NowPlaying.asksPlayers = !CommandLine.arguments.contains { $0.hasPrefix("--") } || CommandLine.arguments.contains("--ask-players")
        // Chromium needs to know when the app hands on an event, so the app's object is its kind.
        let app = CEFApplication.shared
        Chromium.start()
        Codecs.configure()
        if let index = CommandLine.arguments.firstIndex(of: "--convert-media"), index + 2 < CommandLine.arguments.count {
            // A developer's helper: turns one video or sound into WebM as the library would.
            let source = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            let destination = URL(fileURLWithPath: CommandLine.arguments[index + 2])
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
            app.run()
            return
        }
        Codecs.configure()
        if let index = CommandLine.arguments.firstIndex(of: "--convert-media"), index + 2 < CommandLine.arguments.count {
            // A developer's helper: turns one video or sound into WebM as the library would.
            let source = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            let destination = URL(fileURLWithPath: CommandLine.arguments[index + 2])
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
            app.run()
            return
        }
        if let request = ScreenshotMode.renderRequest {
            // A developer's helper that needs neither the library nor the rest of the app.
            ScreenshotMode.renderWeb(request)
            app.run()
            return
        }
        if let request = ScreenshotMode.editRequest {
            ScreenshotMode.editScene(request)
            app.run()
            return
        }
        if let target = ScreenshotMode.energyTestTarget {
            ScreenshotMode.energyTest(target)
            app.run()
            return
        }
        if let request = ScreenshotMode.engineTest {
            ScreenshotMode.runEngineTest(request)
            app.run()
            return
        }
        if let seconds = ScreenshotMode.coverTestSeconds {
            ScreenshotMode.coverTest(seconds)
            app.run()
            return
        }
        if let folder = ScreenshotMode.settingsTestFolder {
            ScreenshotMode.settingsTest(folder)
            app.run()
            return
        }
        if let target = ScreenshotMode.readyTestTarget {
            ScreenshotMode.readyTest(target)
            app.run()
            return
        }
        if let seconds = ScreenshotMode.pointerTestSeconds {
            ScreenshotMode.pointerTest(seconds: seconds)
            app.run()
            return
        }
        if let request = ScreenshotMode.attachTest {
            ScreenshotMode.runAttachTest(request)
            app.run()
            return
        }
        if let request = ScreenshotMode.importTest {
            ScreenshotMode.runImportTest(request)
            app.run()
            return
        }
        if let seconds = ScreenshotMode.soundTestSeconds {
            ScreenshotMode.soundTest(seconds: seconds)
            app.run()
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    override init() {
        // The screenshot helper can be pointed at another library, to picture things the
        // user's own does not have.
        library = ScreenshotMode.libraryFolder.map { WallpaperLibrary(rootURL: $0) } ?? WallpaperLibrary()
        preferences = Preferences()
        manager = WallpaperManager(library: library, preferences: preferences)
        importer = ImportCoordinator(library: library, manager: manager)
        super.init()
        // The helper that takes pictures runs next to the copy in use: its window neither
        // reads nor leaves anything of how the user keeps theirs.
        let helps = ScreenshotMode.outputDirectory != nil
        windows = WindowManager(state: helps ? MainWindowState(defaults: nil) : nil, remembersFrames: !helps, main: { [unowned self] in
            AnyView(
                MainView(actions: LibraryActions(
                    addFiles: { [unowned self] in addWallpapers(nil) },
                    edit: { [unowned self] item in edit(item) },
                    newScene: { [unowned self] in newScene(nil) }
                ))
                .environmentObject(library)
                .environmentObject(manager)
                .environmentObject(importer)
                .environmentObject(preferences)
                .environmentObject(cursorSettings)
                .environmentObject(windows.state)
            )
        })
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let directory = ScreenshotMode.outputDirectory, CommandLine.arguments.contains("--select-test") {
            // The library's own window and menu, to check selecting several wallpapers and
            // deleting them.
            NSApp.mainMenu = makeMainMenu()
            watchDeleteKey()
            ScreenshotMode.selectTest(windows: windows, library: library, in: directory)
            return
        }
        if let directory = ScreenshotMode.outputDirectory {
            // Documentation helper; runs alongside the copy in use, so it skips the checks below.
            ScreenshotMode.run(to: directory, library: library, preferences: preferences,
                               manager: manager, importer: importer, cursorSettings: cursorSettings)
            return
        }
        if activateRunningCopy() {
            return
        }
        NSApp.mainMenu = makeMainMenu()
        watchDeleteKey()
        manager.start()
        MediaConversion.shared.layOutLibrary(library) { [weak self] redone in
            for item in redone { self?.manager.webWallpaperDidChange(item) }
        }
        MediaConversion.shared.convertLibrary(library)
        cursorSettings.reapplyIfNeeded()
        statusMenu = StatusMenuController(library: library, manager: manager, actions: .init(
            openLibrary: { [unowned self] in showLibrary(nil) },
            addFiles: { [unowned self] in addWallpapers(nil) },
            openSettings: { [unowned self] in showSettings(nil) },
            showAbout: { [unowned self] in showAbout(nil) }
        ))
        importer.$failures
            .filter { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.presentImportFailures() }
            .store(in: &cancellables)
        importer.$notices
            .filter { !$0.isEmpty }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.presentImportNotices() }
            .store(in: &cancellables)

        if let url = ScreenshotMode.desktopPictureURL {
            ScreenshotMode.pictureDesktop(of: manager, to: url)
        }

        isLaunched = true
        if !urlsOpenedBeforeLaunch.isEmpty {
            open(urlsOpenedBeforeLaunch)
            urlsOpenedBeforeLaunch = []
        } else if library.items.isEmpty {
            // First launch: show where to start instead of a lonely menu bar icon.
            windows.showLibrary()
        }
    }

    /// Files opened with the app (Finder's "Open With", dropping on the icon) become the wallpaper.
    func application(_ application: NSApplication, open urls: [URL]) {
        if isLaunched {
            open(urls)
        } else {
            urlsOpenedBeforeLaunch += urls
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows.showLibrary()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        Chromium.stop()
    }

    // MARK: - Actions

    @objc func showLibrary(_ sender: Any?) {
        windows.showLibrary()
    }

    @objc func showSettings(_ sender: Any?) {
        windows.showSettings()
    }

    @objc func showSearch(_ sender: Any?) {
        windows.showSearch()
    }

    /// Whether a command of the Edit menu is meant for the library: its window is the one in
    /// use, and the cursor is not in a text.
    private var libraryTakesCommands: Bool {
        guard let window = windows.libraryWindow, window.isKeyWindow else { return false }
        return !(window.firstResponder is NSText)
    }

    /// Select All: the text the cursor is in, or else every wallpaper the library shows.
    @objc func selectAllOfIt(_ sender: Any?) {
        guard libraryTakesCommands else {
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: sender)
            return
        }
        windows.state.command = .selectAll
    }

    /// Delete: asks about deleting the wallpapers selected in the library.
    @objc func deleteSelectedWallpapers(_ sender: Any?) {
        windows.state.command = .deleteSelected
    }

    /// The Delete key in the library, by itself or with Command, is the Delete of the menu.
    /// A key pressed without Command is not looked up in the menu unless everything in the
    /// window has passed it on, which the window's content need not do; so it is taken here.
    private func watchDeleteKey() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keys = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // 51 is Delete, 117 the Delete that deletes forward.
            guard let self, [51, 117].contains(event.keyCode), keys.isEmpty || keys == .command,
                  self.libraryTakesCommands, !self.windows.state.picked.ids.isEmpty
            else {
                return event
            }
            self.deleteSelectedWallpapers(nil)
            return nil
        }
    }

    /// Opens a wallpaper in the scene editor. A video or a picture first becomes a scene with
    /// itself as the background; the original stays in the library as it is.
    func edit(_ item: Wallpaper) {
        if item.kind == .web {
            editScene(item)
            return
        }
        let name = String(format: NSLocalizedString("%@ (scene)", comment: "Name of a scene made from a wallpaper"), item.name)
        Task {
            do {
                let scene = try await library.makeEngineScene(from: item, named: name, size: Self.sceneSize)
                // Chromium plays the video once it is WebM.
                MediaConversion.shared.convertSoon(library.projectURL(for: scene))
                windows.state.selection = scene.id
                editScene(scene)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    /// A new, empty scene, made as Wallpaper Engine makes one, opened in the editor.
    @objc func newScene(_ sender: Any?) {
        Task {
            do {
                let scene = try await library.makeEngineScene(named: NSLocalizedString("New Scene", comment: "Name of a new scene"),
                                                              size: Self.sceneSize)
                windows.state.selection = scene.id
                editScene(scene)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    /// The size a new scene is made at: the main display's, in its pixels.
    private static var sceneSize: CGSize {
        guard let screen = NSScreen.main else { return CGSize(width: 1920, height: 1080) }
        return CGSize(width: screen.frame.width * screen.backingScaleFactor, height: screen.frame.height * screen.backingScaleFactor)
    }

    /// Opens the editor for a scene of the library, or brings it forward if it is open.
    func editScene(_ item: Wallpaper) {
        guard !windows.showOpenEditor(for: item.id) else { return }
        let folder = library.projectURL(for: item)
        if WallpaperEngineProjectFolder.project(ofScene: folder) != nil {
            editEngineScene(item)
            return
        }
        // A scene of Wallpaper Engine's added before the editor could change one has no project
        // of its own yet; it gets it back from the archive it came in.
        if let scene = try? SceneProject.read(from: folder), scene.background.kind == .engine, !windows.showOpenEditor(for: item.id) {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("This scene was added before the new editor", comment: "Alert title")
            alert.informativeText = NSLocalizedString("To change it in the new editor, choose the archive or folder it was added from. It stays the same wallpaper, with its settings and your changes.", comment: "Alert text")
            alert.addButton(withTitle: NSLocalizedString("Choose Archive…", comment: "Alert button"))
            alert.addButton(withTitle: NSLocalizedString("Open in the Earlier Editor", comment: "Alert button"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Alert button"))
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                panel.allowedContentTypes = MediaImporter.acceptedContentTypes
                panel.message = String(format: NSLocalizedString("Choose the archive or folder “%@” was added from.", comment: "Open panel"), item.name)
                panel.prompt = NSLocalizedString("Choose", comment: "Open panel button")
                guard panel.runModal() == .OK, let url = panel.url else { return }
                Task {
                    do {
                        try await library.attachEngineProject(from: url, to: item)
                        MediaConversion.shared.convertSoon(folder)
                        manager.webWallpaperDidChange(item)
                        editEngineScene(item)
                    } catch {
                        let failed = NSAlert()
                        failed.messageText = NSLocalizedString("This is not the scene's archive", comment: "Alert title")
                        failed.informativeText = NSLocalizedString("No Wallpaper Engine scene of that name was found in it.", comment: "Alert text")
                        failed.runModal()
                    }
                }
                return
            case .alertSecondButtonReturn:
                break
            default:
                return
            }
        }
        // A scene of the app's own format becomes one of Wallpaper Engine's, which the editor
        // makes; one with a layer of code or a page behind it stays as it is.
        if let scene = try? SceneProject.read(from: folder), WallpaperSceneConversion.canConvert(scene) {
            Task {
                do {
                    try await WallpaperSceneConversion.convert(sceneIn: folder, size: Self.sceneSize, title: item.name)
                    MediaConversion.shared.convertSoon(folder)
                    manager.webWallpaperDidChange(item)
                    editEngineScene(item)
                } catch {
                    NSAlert(error: error).runModal()
                }
            }
            return
        }
        do {
            let model = try SceneEditorModel(folder: library.projectURL(for: item), title: item.name)
            // The library thumbnail and the lock-screen still follow the edits.
            model.onSave = { [weak self] in self?.manager.webWallpaperDidChange(item) }
            let preview = SceneEditorPreviewController(model: model)
            windows.showEditor(for: item.id, title: item.name,
                               content: AnyView(SceneEditorView(model: model, preview: preview)),
                               onClose: { model.saveNow() })
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Opens the editor of a scene made as Wallpaper Engine makes one.
    private func editEngineScene(_ item: Wallpaper) {
        do {
            let model = try EngineEditorModel(folder: library.projectURL(for: item), title: item.name)
            model.onSave = { [weak self] in self?.manager.webWallpaperDidChange(item) }
            let preview = EngineEditorPreviewController(model: model)
            windows.showEditor(for: item.id, title: item.name,
                               content: AnyView(EngineEditorView(model: model, preview: preview)),
                               onClose: { model.saveNow() })
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: NSLocalizedString("Animated wallpapers from videos, GIFs and pictures.", comment: "About panel"),
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc func addWallpapers(_ sender: Any?) {
        windows.showLibrary()
        guard let window = windows.libraryWindow else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = MediaImporter.acceptedContentTypes
        panel.message = NSLocalizedString("Choose videos, GIFs, pictures or an archive with a wallpaper. Folders are searched too.", comment: "Open panel")
        panel.prompt = NSLocalizedString("Add", comment: "Open panel button")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.importer.importFiles(panel.urls, applyWhenDone: false)
        }
    }

    // MARK: - Helpers

    private func open(_ urls: [URL]) {
        windows.showLibrary()
        importer.importFiles(urls, applyWhenDone: true)
    }

    /// Only one copy may own the desktop; a second launch brings the first one forward.
    private func activateRunningCopy() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let current = NSRunningApplication.current
        guard let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first(where: { $0 != current }) else {
            return false
        }
        other.activate(options: [])
        NSApp.terminate(nil)
        return true
    }

    private func presentImportFailures() {
        let failures = importer.failures
        importer.failures = []
        guard let first = failures.first else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        if failures.count == 1 {
            alert.messageText = String(format: NSLocalizedString("“%@” could not be added", comment: "Import error title"), first.fileName)
            alert.informativeText = first.message
        } else {
            alert.messageText = NSLocalizedString("Some files could not be added", comment: "Import error title")
            alert.informativeText = failures.prefix(8)
                .map { "\($0.fileName): \($0.message)" }
                .joined(separator: "\n\n")
        }
        if let window = windows.visibleWindow {
            alert.beginSheetModal(for: window)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    /// Says which of the wallpapers just added are scenes of Wallpaper Engine with something
    /// in them that is not played, so that what stands still or is missing is not taken for a fault.
    private func presentImportNotices() {
        let notices = importer.notices
        importer.notices = []
        guard let first = notices.first else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        let explanation = NSLocalizedString(
            "A 3D model of a Wallpaper Engine scene whose shape cannot be read is left out, and a picture whose bones cannot be read stands still.",
            comment: "Import notice"
        )
        if notices.count == 1 {
            alert.messageText = String(format: NSLocalizedString("“%@” was added in part", comment: "Import notice title"), first.name)
            alert.informativeText = explanation
        } else {
            alert.messageText = NSLocalizedString("Some wallpapers were added in part", comment: "Import notice title")
            alert.informativeText = notices.prefix(8).map(\.name).joined(separator: "\n") + "\n\n" + explanation
        }
        if let window = windows.visibleWindow {
            alert.beginSheetModal(for: window)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: NSLocalizedString("About WallAero Engine", comment: "Menu item"), action: #selector(showAbout(_:)), keyEquivalent: "")
            .setSymbol("info.circle")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: NSLocalizedString("Settings…", comment: "Menu item"), action: #selector(showSettings(_:)), keyEquivalent: ",")
            .setSymbol("gearshape")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: NSLocalizedString("Hide WallAero Engine", comment: "Menu item"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: NSLocalizedString("Hide Others", comment: "Menu item"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: NSLocalizedString("Show All", comment: "Menu item"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: NSLocalizedString("Quit WallAero Engine", comment: "Menu item"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenu = NSMenu(title: NSLocalizedString("File", comment: "Menu title"))
        fileMenu.addItem(withTitle: NSLocalizedString("New Scene", comment: "Menu item"), action: #selector(newScene(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: NSLocalizedString("Add Wallpapers…", comment: "Menu item"), action: #selector(addWallpapers(_:)), keyEquivalent: "o")
            .setSymbol("plus")
        fileMenu.addItem(withTitle: NSLocalizedString("Open Library…", comment: "Menu item"), action: #selector(showLibrary(_:)), keyEquivalent: "l")
            .setSymbol("square.grid.2x2")
        fileMenu.addItem(withTitle: NSLocalizedString("Find", comment: "Menu item"), action: #selector(showSearch(_:)), keyEquivalent: "f")
            .setSymbol("magnifyingglass")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: NSLocalizedString("Close Window", comment: "Menu item"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editMenu = NSMenu(title: NSLocalizedString("Edit", comment: "Menu title"))
        editMenu.addItem(withTitle: NSLocalizedString("Undo", comment: "Menu item"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: NSLocalizedString("Redo", comment: "Menu item"), action: Selector(("redo:")), keyEquivalent: "z")
            .keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: NSLocalizedString("Cut", comment: "Menu item"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: NSLocalizedString("Copy", comment: "Menu item"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: NSLocalizedString("Paste", comment: "Menu item"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: NSLocalizedString("Select All", comment: "Menu item"), action: #selector(selectAllOfIt(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        // The Delete key by itself, as in Photos and Mail, and with Command, as in the Finder.
        for keys in [[], [.command]] as [NSEvent.ModifierFlags] {
            let delete = editMenu.addItem(withTitle: NSLocalizedString("Delete", comment: "Menu item"),
                                          action: #selector(deleteSelectedWallpapers(_:)), keyEquivalent: "\u{8}")
            delete.keyEquivalentModifierMask = keys
            delete.isAlternate = !keys.isEmpty
        }

        let windowMenu = NSMenu(title: NSLocalizedString("Window", comment: "Menu title"))
        windowMenu.addItem(withTitle: NSLocalizedString("Minimize", comment: "Menu item"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: NSLocalizedString("Zoom", comment: "Menu item"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        let mainMenu = NSMenu()
        for submenu in [appMenu, fileMenu, editMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }
}

extension AppDelegate: NSMenuItemValidation {
    /// Delete is for the wallpapers selected in the library, and there is nothing to delete
    /// when none is, or when the keys go to a text.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(deleteSelectedWallpapers(_:)) {
            return libraryTakesCommands && !windows.state.picked.ids.isEmpty
        }
        return true
    }
}

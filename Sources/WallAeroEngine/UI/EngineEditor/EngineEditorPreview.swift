import AppKit
import SwiftUI
import WallpaperCore

/// The editor's live picture of a Wallpaper Engine scene: the scene's own page, with the editor
/// script on top so that objects can be picked, moved, scaled and turned with the mouse. What
/// changes in the editor is handed to the player as it changes, before it is written.
@MainActor
final class EngineEditorPreviewController {
    /// What the preview is shown in: the scene drawn by the app, or its page in Chromium.
    let view: NSView
    private var webView: WebWallpaperView?
    private var sceneView: NativeSceneView?
    private var overlay: EngineEditorOverlay?
    private weak var model: EngineEditorModel?
    private var colorsObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var wheelMonitor: Any?

    init(model: EngineEditorModel) {
        self.model = model
        let frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        // A scene the app draws on the desktop it draws here too, with the editor's frame over it.
        if ScreenWallpaper.drawsScenesNatively, SceneProject.isNativelyPlayable(model.folder) {
            let container = NSView(frame: frame)
            let scene = NativeSceneView(frame: frame)
            scene.hearsSound = true
            scene.setAudio(muted: true, volume: 0)
            scene.setPlaying(true, rate: 1)
            let overlay = EngineEditorOverlay(frame: frame)
            container.addSubview(scene)
            container.addSubview(overlay)
            view = container
            sceneView = scene
            self.overlay = overlay
            overlay.onSelect = { [weak model] id in model?.selection = id }
            overlay.onChange = { [weak model] id, patch in model?.applyFromPreview(object: id, patch: patch) }
            overlay.onCommit = { [weak model] in model?.endGesture() }
            overlay.onMenu = { [weak self] point in self?.sceneMenu(at: point) }
            overlay.animatedPlace = { [weak model] id, name in model?.animatedPlace(of: id, name) }
            overlay.onZoom = { [weak model] factor, point in model?.zoomView(by: factor, around: point) }
            overlay.onPan = { [weak model, weak overlay] distance in
                model?.panView(by: distance, within: overlay?.bounds.size ?? .zero)
            }
            scene.onRestart = { [weak self] in self?.sceneRestarted() }
            if scene.show(folder: model.folder, watchingForChanges: false) {
                model.preview = self
                listenForKeys()
                return
            }
            container.subviews.forEach { $0.removeFromSuperview() }
            sceneView = nil
            self.overlay = nil
            let web = WebWallpaperView(frame: frame)
            container.addSubview(web)
            web.autoresizingMask = [.width, .height]
            webView = web
        } else {
            let web = WebWallpaperView(frame: frame)
            view = web
            webView = web
        }
        if let webView {
            webView.editorScript = Self.editorScript
            webView.hearsSound = true
            webView.onEditorMessage = { [weak self] message in
                self?.handle(message)
            }
            webView.setAudio(muted: true, volume: 0)
            webView.setPlaying(true, rate: 1)
            if let project = WebProject(folder: model.folder) {
                webView.show(project)
            }
        }
        model.preview = self
        colorsObserver = NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showAccentColor() }
        }
        listenForKeys()
    }

    deinit {
        if let colorsObserver {
            NotificationCenter.default.removeObserver(colorsObserver)
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let wheelMonitor {
            NSEvent.removeMonitor(wheelMonitor)
        }
    }

    private func listenForKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Keys arrive on the main thread.
            nonisolated(unsafe) let pressed = event
            let handled = MainActor.assumeIsolated { self?.handleKey(pressed) == true }
            return handled ? nil : event
        }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            nonisolated(unsafe) let turned = event
            let handled = MainActor.assumeIsolated { self?.handleWheel(turned) == true }
            return handled ? nil : event
        }
    }

    /// The wheel over the timeline, as in Wallpaper Engine: it enlarges the time, and with Shift
    /// or Control the heights of the curves. Two fingers sideways go along the time.
    private func handleWheel(_ event: NSEvent) -> Bool {
        guard let model, model.showsTimeline, let window = view.window, event.window === window, let content = window.contentView else { return false }
        let at = CGPoint(x: event.locationInWindow.x, y: content.bounds.height - event.locationInWindow.y)
        return turnWheel(at: at, across: event.scrollingDeltaX, along: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                         heights: !event.modifierFlags.intersection([.shift, .control]).isEmpty)
    }

    /// The wheel turned over a point of the window, from its top left.
    func turnWheel(at: CGPoint, across: CGFloat, along: CGFloat, precise: Bool, heights: Bool) -> Bool {
        guard let model else { return false }
        let area = model.timelineArea
        guard area.contains(at) else { return false }
        if precise, abs(across) > abs(along) {
            model.panTimeline(bySeconds: -Double(across) / max(Double(area.width), 1) * model.timelineShown)
            return true
        }
        let factor = pow(precise ? 1.01 : 1.1, Double(along))
        if heights {
            model.zoomCurvesFromWheel(by: factor)
        } else {
            model.zoomTimeline(by: factor, atShare: Double((at.x - area.minX) / max(area.width, 1)))
        }
        return true
    }

    /// The next change of the scene is one the player cannot follow as it plays.
    var playsAnewOnNextChange = false

    /// What is wrong with the text of a script, without running it.
    func checkScript(_ text: String) -> EngineScriptProblem? {
        guard let said = sceneView?.scenePlayer?.ask("checkScript", [text]) as? [String: Any] else { return nil }
        return Self.problem(said)
    }

    private static func problem(_ said: [String: Any]) -> EngineScriptProblem {
        EngineScriptProblem(message: said["message"] as? String ?? "", line: (said["line"] as? NSNumber)?.intValue ?? 0, during: said["during"] as? String)
    }

    /// The settings a script declares.
    func scriptDeclares(_ text: String) -> [[String: Any]] {
        sceneView?.scenePlayer?.ask("scriptDeclares", [text]) as? [[String: Any]] ?? []
    }

    /// What went wrong with scripts, by their text, and what they wrote since the last time.
    func scriptReport() -> (errors: [String: EngineScriptProblem], log: [String])? {
        guard let said = sceneView?.scenePlayer?.ask("scriptReport") as? [String: Any] else { return nil }
        return ((said["errors"] as? [String: [String: Any]] ?? [:]).mapValues(Self.problem), said["log"] as? [String] ?? [])
    }

    /// What the right button offers at a point of the scene: the object under it, and what can
    /// be added there.
    func sceneMenu(at point: CGPoint) -> NSMenu? {
        guard let model, let player = sceneView?.scenePlayer else { return nil }
        let menu = NSMenu()
        if let hit = (player.ask("hit", [point.x, point.y]) as? NSNumber)?.intValue {
            model.selection = hit
            menu.addItem(NSMenuItem(title: model.name(of: hit), action: nil, keyEquivalent: ""))
            menu.items.last?.isEnabled = false
            menu.addItem(EngineMenuItem(NSLocalizedString("Duplicate", comment: "Menu of an object")) { model.duplicate(hit) })
            menu.addItem(EngineMenuItem(NSLocalizedString("Bring Forward", comment: "Menu of an object")) { model.move(hit, forward: true) })
            menu.addItem(EngineMenuItem(NSLocalizedString("Send Backward", comment: "Menu of an object")) { model.move(hit, forward: false) })
            menu.addItem(EngineMenuItem(NSLocalizedString(model.isVisible(hit) ? "Hide" : "Show", comment: "Menu of an object")) { model.toggleVisibility(of: hit) })
            menu.addItem(EngineMenuItem(NSLocalizedString("Delete", comment: "Menu of an object")) { model.delete(hit) })
            menu.addItem(.separator())
        }
        let here = { [weak self] (add: () -> Void) in self?.addHere(point, add) }
        let adds = NSMenu()
        adds.addItem(EngineMenuItem(NSLocalizedString("Image…", comment: "Add menu")) { here(model.addPicture) })
        adds.addItem(EngineMenuItem(NSLocalizedString("Video…", comment: "Add menu")) { model.addVideo() })
        adds.addItem(EngineMenuItem(NSLocalizedString("Text", comment: "Add menu")) { here(model.addText) })
        adds.addItem(EngineMenuItem(NSLocalizedString("Solid Color", comment: "Add menu")) { here(model.addSolid) })
        adds.addItem(.separator())
        let particles = NSMenu()
        for preset in WallpaperEngineParticlePreset.all {
            particles.addItem(EngineMenuItem(preset.title) { here { model.addParticles(preset) } })
        }
        adds.addItem(Self.submenu(NSLocalizedString("Particles", comment: "Add menu"), particles))
        adds.addItem(EngineMenuItem(NSLocalizedString("Sound…", comment: "Add menu")) { model.addSound() })
        let lights = NSMenu()
        for kind in WallpaperEngineDocument.LightKind.allCases {
            lights.addItem(EngineMenuItem(EngineEditorModel.lightTitle(kind)) { here { model.addLight(kind) } })
        }
        adds.addItem(Self.submenu(NSLocalizedString("Light Source", comment: "Add menu"), lights))
        adds.addItem(EngineMenuItem(NSLocalizedString("Group", comment: "Add menu")) { here(model.addGroup) })
        menu.addItem(Self.submenu(NSLocalizedString("Add", comment: "Menu of the scene"), adds))
        return menu
    }

    private static func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    /// Adds an object and puts it where the menu was opened.
    private func addHere(_ point: CGPoint, _ add: () -> Void) {
        guard let model else { return }
        let before = model.selection
        add()
        guard let made = model.selection, made != before,
              let place = sceneView?.scenePlayer?.ask("placeAt", [made, point.x, point.y]) as? [NSNumber], place.count >= 2 else { return }
        model.applyFromPreview(object: made, patch: ["x": place[0].doubleValue, "y": place[1].doubleValue])
        model.endGesture()
    }

    /// A mask being painted is shown by the frame over the scene, and the mouse is its.
    func setPainting(_ paint: EngineMaskPaint?) {
        overlay?.painting = paint
    }

    /// New values of a texture being painted.
    func showMask(_ texture: String, _ mask: WallpaperEngineMask) {
        sceneView?.scenePlayer?.paintTexture(texture, width: mask.width, byteCount: mask.width * mask.height * 4) { mask.writeColors(to: $0) }
    }

    func maskChanged() {
        overlay?.maskChanged()
    }

    /// An object's own size, in the scene's pixels.
    func objectSize(_ id: Int) -> CGSize? {
        guard let size = (sceneView?.scenePlayer?.ask("outline", [id]) as? [String: Any])?["size"] as? [Double], size.count >= 2 else { return nil }
        return CGSize(width: size[0], height: size[1])
    }

    /// The editor's keys, by their place on the keyboard, so that they work in any layout. They
    /// are not for a text being typed, a window on top, or the puppet warp, which has its own.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let model, model.puppetObject == nil, let window = view.window, event.window === window,
              window.attachedSheet == nil, !(window.firstResponder is NSText) else { return false }
        let keys = event.modifierFlags.intersection([.command, .control, .option])
        if let painting = model.painting {
            guard keys.isEmpty else { return false }
            switch event.keyCode {
            case 46: painting.showsMask.toggle()               // M
            case 34: painting.isPicking.toggle()               // I
            case 49: model.isPlaying.toggle()
            case 115: model.fitView()
            default: return false
            }
            return true
        }
        if keys == .command, event.keyCode == 2, let selection = model.selection {
            model.duplicate(selection)
            return true
        }
        if model.showsTimeline, handleTimelineKey(event, keys) { return true }
        guard keys.isEmpty else { return false }
        switch event.keyCode {
        case 13 where overlay != nil: model.tool = .multi
        case 5 where overlay != nil: model.tool = .move
        case 15 where overlay != nil: model.tool = .rotate
        case 1 where overlay != nil: model.tool = .scale
        case 53 where overlay != nil && model.tool != .multi: model.tool = .multi
        case 17 where overlay != nil: model.showsTimeline.toggle()
        case 4:
            guard let selection = model.selection else { return false }
            model.toggleVisibility(of: selection)
        case 49: model.isPlaying.toggle()
        case 115: model.fitView()
        default: return false
        }
        return true
    }

    /// A new player: the frame asks it, and the editor learns what the scene has once it plays.
    private func sceneRestarted() {
        guard let overlay, let player = sceneView?.scenePlayer else { return }
        overlay.player = player
        player.onEngineStarted = { [weak self] in self?.engineStarted() }
    }

    private func engineStarted() {
        guard let model, let overlay, let text = overlay.describe(),
              let description = try? JSONDecoder().decode(EngineSceneDescription.self, from: Data(text.utf8)) else { return }
        model.playerDidStart(description)
        overlay.selectObject(model.selection)
        model.showTimelineMoment()
    }

    /// Has the scene show a moment of its animations; with nil they go on as they were.
    func showAnimations(at seconds: Double?) {
        sceneView?.scenePlayer?.showAnimations(at: seconds)
        overlay?.needsDisplay = true
    }

    /// Returns once the preview has loaded; a scene the app draws starts at once.
    func waitUntilLoaded() async {
        await webView?.waitUntilLoaded()
    }

    /// Whether the scene is drawn by the app, for tests.
    var drawsNatively: Bool { sceneView != nil }

    /// The mouse pressed at one point of the preview, dragged to another and let go, each as
    /// a share of the preview's width and height from its top left, for tests.
    func drag(from startShare: CGPoint, to endShare: CGPoint) {
        guard let overlay, let window = overlay.window else { return }
        let size = overlay.bounds.size
        let start = CGPoint(x: startShare.x * size.width, y: startShare.y * size.height)
        let end = CGPoint(x: endShare.x * size.width, y: endShare.y * size.height)
        func event(_ type: NSEvent.EventType, _ at: CGPoint) -> NSEvent? {
            let inWindow = overlay.convert(at, to: nil)
            return NSEvent.mouseEvent(with: type, location: inWindow, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        if let down = event(.leftMouseDown, start) { overlay.mouseDown(with: down) }
        for step in 1...8 {
            let share = CGFloat(step) / 8
            let at = CGPoint(x: start.x + (end.x - start.x) * share, y: start.y + (end.y - start.y) * share)
            if let moved = event(.leftMouseDragged, at) { overlay.mouseDragged(with: moved) }
        }
        if let up = event(.leftMouseUp, end) { overlay.mouseUp(with: up) }
    }

    /// A picture of the preview as it is now.
    func snapshot() async -> CGImage? {
        if let sceneView { return sceneView.snapshot() }
        return await webView?.snapshot()
    }

    private static var editorScript: String {
        SceneEditorScript.source + "\nwindow.wallaeroEditor.setAccent('\(NSColor.controlAccentColor.cssHex)');"
    }

    private func showAccentColor() {
        overlay?.needsDisplay = true
        guard let view = webView else { return }
        view.editorScript = Self.editorScript
        view.evaluate("window.wallaeroEditor && window.wallaeroEditor.setAccent('\(NSColor.controlAccentColor.cssHex)')")
    }

    /// Hands the player what changed of the scene: the scene file alone is followed as it plays;
    /// with any other file the scene is played anew.
    func show(_ document: WallpaperEngineDocument, after old: WallpaperEngineDocument) {
        var changed: [String: String] = [:]
        for (name, value) in document.files where old.file(name) != value {
            changed[Self.key(name)] = value.text
        }
        let scene = document.scene.text
        if let player = sceneView?.scenePlayer {
            // What the frame showed while an object was dragged is in the scene now.
            overlay?.forgetChanges()
            player.editorUpdate(settings: nil, changes: [:])
            if changed.isEmpty, !playsAnewOnNextChange {
                player.setSceneFile(scene)
            } else {
                changed["scene.json"] = scene
                player.setFiles(changed)
            }
            if let text = overlay?.describe(),
               let description = try? JSONDecoder().decode(EngineSceneDescription.self, from: Data(text.utf8)) {
                model?.playerDidStart(description)
            }
            return
        }
        guard let view = webView else { return }
        let call: String
        if changed.isEmpty {
            call = "window.wallaero.setEngineScene(\(Self.literal(scene)))"
        } else {
            changed["scene.json"] = scene
            let table = (try? JSONSerialization.data(withJSONObject: changed, options: [])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            call = "window.wallaero.setEngineFiles(\(table))"
        }
        // What the editor script showed while an object was dragged is in the scene now.
        view.evaluate("""
        (function () {
          if (!window.wallaero) return;
          var scene = window.wallaero.scene;
          if (scene && scene.background) scene.background.engine = {};
          \(call);
          window.wallaero.updateEngine();
          if (window.wallaeroEditor && window.wallaeroEditor.refresh) setTimeout(window.wallaeroEditor.refresh, 0);
        })()
        """)
    }

    /// The scene's files were laid out anew: they are read again.
    func reload() {
        if let player = sceneView?.scenePlayer {
            player.reloadFiles()
            return
        }
        webView?.evaluate("window.wallaero && window.wallaero.reloadEngine && window.wallaero.reloadEngine()")
    }

    func select(_ id: Int?) {
        if let overlay {
            if overlay.object != id { overlay.selectObject(id) }
            return
        }
        webView?.evaluate("window.wallaeroEditor && window.wallaeroEditor.selectObject(\(id.map(String.init) ?? "null"))")
    }

    /// The timeline's keys, as Wallpaper Engine has them, while it is open.
    private func handleTimelineKey(_ event: NSEvent, _ keys: NSEvent.ModifierFlags) -> Bool {
        guard let model else { return false }
        switch (event.keyCode, keys) {
        case (40, []): model.toggleKey()                       // K
        case (0, []): model.autoKey.toggle()                   // A
        case (49, []): model.setTimelinePlaying(!model.timelinePlaying)
        case (123, []) where model.activeAnimation != nil: model.stepFrame(-1)
        case (124, []) where model.activeAnimation != nil: model.stepFrame(1)
        case (123, [.control]): model.jumpToKey(forward: false)
        case (124, [.control]): model.jumpToKey(forward: true)
        case (51, []) where !model.selectedKeys.isEmpty, (117, []) where !model.selectedKeys.isEmpty: model.deleteSelectedKeys()
        case (8, [.command]) where !model.selectedKeys.isEmpty: model.copySelectedKeys()
        case (9, [.command]) where !model.timelineClipboard.isEmpty: model.pasteKeys()
        default: return false
        }
        return true
    }

    func setTool(_ tool: EngineEditorModel.Tool) {
        overlay?.tool = tool
    }

    func setPlaying(_ playing: Bool) {
        webView?.setPlaying(playing, rate: 1)
        sceneView?.setPlaying(playing, rate: 1)
    }

    /// Where an object's middle is on the page, for tests.
    func outlineMiddle(of id: Int) -> [Double] {
        (sceneView?.scenePlayer?.ask("outline", [id]) as? [String: Any]).flatMap { $0["middle"] as? [Double] } ?? []
    }

    /// What the player works out of an animation, for tests.
    func curveValue(_ animation: JSONValue, seconds: Double, base: [Double]) -> [Double]? {
        sceneView?.scenePlayer?.ask("curveValue", [animation.any, seconds, base]) as? [Double]
    }

    private func handle(_ message: [String: Any]) {
        guard let model, let type = message["type"] as? String else { return }
        let number = (message["id"] as? NSNumber)?.intValue
        let patch = (message["patch"] as? [String: Any])?.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        switch type {
        case "ready":
            select(model.selection)
        case "engine":
            if let text = message["scene"] as? String,
               let description = try? JSONDecoder().decode(EngineSceneDescription.self, from: Data(text.utf8)) {
                model.playerDidStart(description)
            }
        case "select-object":
            model.selection = number
        case "object-change":
            if let number, let patch {
                model.applyFromPreview(object: number, patch: patch)
            }
        case "commit":
            model.endGesture()
        default:
            break
        }
    }

    /// A name as the player knows the scene's files by.
    static func key(_ name: String) -> String {
        name.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    /// A text as a JavaScript string.
    static func literal(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text], options: [])) ?? Data("[\"\"]".utf8)
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }
}

/// The preview at the proportions of the scene, centred in the space it is given.
struct EngineEditorPreview: View {
    @ObservedObject var model: EngineEditorModel
    let controller: EngineEditorPreviewController
    let aspectRatio: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let available = CGSize(width: max(geometry.size.width - 32, 100), height: max(geometry.size.height - 32, 100))
            let width = min(available.width, available.height * aspectRatio)
            EnginePreviewHost(view: controller.view)
                .frame(width: width * model.viewZoom, height: width / aspectRatio * model.viewZoom)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
                .offset(model.viewPan)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct EnginePreviewHost: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// An item of a menu made in code, which does what it is given.
private final class EngineMenuItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(chosen), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func chosen() { run() }
}

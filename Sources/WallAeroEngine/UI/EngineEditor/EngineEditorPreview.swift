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
            scene.onRestart = { [weak self] in self?.sceneRestarted() }
            if scene.show(folder: model.folder, watchingForChanges: false) {
                model.preview = self
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
    }

    deinit {
        if let colorsObserver {
            NotificationCenter.default.removeObserver(colorsObserver)
        }
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
            if changed.isEmpty {
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

    func setPlaying(_ playing: Bool) {
        webView?.setPlaying(playing, rate: 1)
        sceneView?.setPlaying(playing, rate: 1)
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
    let controller: EngineEditorPreviewController
    let aspectRatio: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let available = CGSize(width: max(geometry.size.width - 32, 100), height: max(geometry.size.height - 32, 100))
            let width = min(available.width, available.height * aspectRatio)
            EnginePreviewHost(view: controller.view)
                .frame(width: width, height: width / aspectRatio)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct EnginePreviewHost: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

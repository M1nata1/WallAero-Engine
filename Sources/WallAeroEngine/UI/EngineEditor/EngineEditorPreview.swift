import AppKit
import SwiftUI
import WallpaperCore

/// The editor's live picture of a Wallpaper Engine scene: the scene's own page, with the editor
/// script on top so that objects can be picked, moved, scaled and turned with the mouse. What
/// changes in the editor is handed to the player as it changes, before it is written.
@MainActor
final class EngineEditorPreviewController {
    let view: WebWallpaperView
    private weak var model: EngineEditorModel?
    private var colorsObserver: NSObjectProtocol?

    init(model: EngineEditorModel) {
        self.model = model
        view = WebWallpaperView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.editorScript = Self.editorScript
        view.hearsSound = true
        view.onEditorMessage = { [weak self] message in
            self?.handle(message)
        }
        view.setAudio(muted: true, volume: 0)
        view.setPlaying(true, rate: 1)
        if let project = WebProject(folder: model.folder) {
            view.show(project)
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

    private static var editorScript: String {
        SceneEditorScript.source + "\nwindow.wallaeroEditor.setAccent('\(NSColor.controlAccentColor.cssHex)');"
    }

    private func showAccentColor() {
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
        view.evaluate("window.wallaero && window.wallaero.reloadEngine && window.wallaero.reloadEngine()")
    }

    func select(_ id: Int?) {
        view.evaluate("window.wallaeroEditor && window.wallaeroEditor.selectObject(\(id.map(String.init) ?? "null"))")
    }

    func setPlaying(_ playing: Bool) {
        view.setPlaying(playing, rate: 1)
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
    let view: WebWallpaperView

    func makeNSView(context: Context) -> WebWallpaperView { view }
    func updateNSView(_ nsView: WebWallpaperView, context: Context) {}
}

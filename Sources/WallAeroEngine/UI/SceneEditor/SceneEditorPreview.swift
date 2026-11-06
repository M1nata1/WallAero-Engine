import AppKit
import SwiftUI
import WallpaperCore

/// The editor's live picture of the scene: the scene's own page, with the editor script on top
/// so that layers can be picked and moved with the mouse.
@MainActor
final class SceneEditorPreviewController {
    let view: WebWallpaperView
    private weak var model: SceneEditorModel?
    private var colorsObserver: NSObjectProtocol?

    init(model: SceneEditorModel) {
        self.model = model
        view = WebWallpaperView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.editorScript = Self.editorScript
        // The page's time is the timeline's: it stands until the timeline plays it.
        view.followsEditorClock = true
        view.hearsSound = true
        view.onSceneFileChange = { [weak model] in
            model?.sceneFileDidChange()
        }
        view.onEditorMessage = { [weak self] message in
            self?.handle(message)
        }
        view.setAudio(muted: true, volume: 0)
        view.setPlaying(true, rate: 1)
        if let project = WebProject(folder: model.folder) {
            view.show(project)
        }
        model.preview = self
        listenForKeys()
        // The selection in the preview is drawn by the page, so the page is told the Mac's
        // accent color, again whenever the user picks another one.
        colorsObserver = NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showAccentColor() }
        }
    }

    deinit {
        if let colorsObserver {
            NotificationCenter.default.removeObserver(colorsObserver)
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    /// The editor script, ending with the accent color as it is now. It keeps the real clock
    /// while the page's is the timeline's.
    private static var editorScript: String {
        "(function (requestAnimationFrame, setTimeout, setInterval) {\n" + SceneEditorScript.source
            + "\n})((window.__wallaeroReal || window).requestAnimationFrame, (window.__wallaeroReal || window).setTimeout, (window.__wallaeroReal || window).setInterval);"
            + "\nwindow.wallaeroEditor.setAccent('\(NSColor.controlAccentColor.cssHex)');"
    }

    // MARK: - Time

    private var keyMonitor: Any?
    /// The moment the page stands at, as far as is known, and one to go to once it has loaded.
    private var pageSeconds = 0.0
    private var pendingMoment: Double?
    private var rewind: DispatchWorkItem?

    /// Holds the page's time, or lets it play on.
    func setClockHeld(_ held: Bool) {
        view.evaluate("window.__wallaeroClock && window.__wallaeroClock.hold(\(held))")
    }

    /// Has the page stand at a moment, as it would have played up to it: on from where it is,
    /// or, for a moment gone by, loaded anew and played up to it. While the timeline is dragged
    /// back, the page is loaded anew only once it rests.
    func show(moment seconds: Double) {
        rewind?.cancel()
        rewind = nil
        if seconds >= pageSeconds - 0.0005 {
            pageSeconds = seconds
            view.evaluate("window.__wallaeroClock && window.__wallaeroClock.goTo(\(seconds))")
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.rewind = nil
            self.pendingMoment = seconds
            self.pageSeconds = 0
            self.view.reloadForEditor()
        }
        rewind = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (NSEvent.pressedMouseButtons != 0 ? 0.25 : 0), execute: work)
    }

    /// The page loaded anew from its files, as after its code was written.
    func reloadPage() {
        pendingMoment = model?.timelineSeconds ?? 0
        pageSeconds = 0
        view.reloadForEditor()
    }

    /// The page has loaded: it goes to the timeline's moment, and plays if the timeline does.
    private func pageReady() {
        // The page says so once its document is read, a moment before it counts as loaded and
        // can be told anything.
        Task { @MainActor [weak self] in
            await self?.view.waitUntilLoaded()
            guard let self, let model = self.model else { return }
            let moment = self.pendingMoment ?? model.timelineSeconds
            self.pendingMoment = nil
            self.pageSeconds = 0
            self.show(moment: moment)
            self.setClockHeld(!model.isPlaying)
        }
    }

    // MARK: - The view

    /// Shows the page as a card turned in depth, across and up by degrees, or flat again.
    func setCard(_ turn: CGSize?) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let turn {
            let middle = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)
            var turned = CATransform3DMakeScale(0.72, 0.72, 1)
            turned = CATransform3DConcat(turned, CATransform3DMakeRotation(turn.width * .pi / 180, 0, 1, 0))
            turned = CATransform3DConcat(turned, CATransform3DMakeRotation(turn.height * .pi / 180, 1, 0, 0))
            var lens = CATransform3DIdentity
            lens.m34 = -1 / max(layer.bounds.width * 1.6, 1)
            turned = CATransform3DConcat(turned, lens)
            layer.sublayerTransform = CATransform3DConcat(CATransform3DConcat(CATransform3DMakeTranslation(-middle.x, -middle.y, 0), turned),
                                                          CATransform3DMakeTranslation(middle.x, middle.y, 0))
            layer.backgroundColor = NSColor.underPageBackgroundColor.cgColor
        } else {
            layer.sublayerTransform = CATransform3DIdentity
            layer.backgroundColor = NSColor.black.cgColor
        }
        CATransaction.commit()
    }

    // MARK: - Keys

    /// Blender's keys, by their place on the keyboard: Space plays, Escape stops where it
    /// began, Shift-Left goes to the start, the arrows by frames, 0 through the screen or
    /// freely, Home fits, Control-Page Up and Down from one workspace to the next.
    private func listenForKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            nonisolated(unsafe) let pressed = event
            let handled = MainActor.assumeIsolated { self?.handleKey(pressed) == true }
            return handled ? nil : event
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let model, let window = view.window, event.window === window, window.attachedSheet == nil,
              !(window.firstResponder is NSText) else { return false }
        let keys = event.modifierFlags.intersection([.command, .control, .option, .shift])
        switch (event.keyCode, keys) {
        case (49, []): model.isPlaying.toggle()
        case (53, []) where model.isPlaying: model.cancelPlaying()
        case (123, [.shift]): model.timelineSeconds = 0
        case (123, []): model.stepFrame(-1)
        case (124, []): model.stepFrame(1)
        case (29, []), (82, []): model.setViewsFreely(!model.viewsFreely)
        case (115, []): model.fitView()
        case (116, [.control]), (121, [.control]):
            let all = SceneEditorModel.Workspace.allCases
            let at = all.firstIndex(of: model.workspace) ?? 0
            model.workspace = all[(at + (event.keyCode == 121 ? 1 : all.count - 1)) % all.count]
        default: return false
        }
        return true
    }

    private func showAccentColor() {
        // For the page as it is, and for when it loads anew.
        view.editorScript = Self.editorScript
        view.evaluate("window.wallaeroEditor && window.wallaeroEditor.setAccent('\(NSColor.controlAccentColor.cssHex)')")
    }

    func show(_ scene: WallpaperScene) {
        guard let data = try? SceneProject.encoded(scene, readable: false) else { return }
        view.evaluate("window.wallaero && window.wallaero.setScene(\(String(decoding: data, as: UTF8.self)))")
    }

    func select(_ item: SceneEditorItem?) {
        switch item {
        case .layer(let id):
            view.evaluate("window.wallaeroEditor && window.wallaeroEditor.select('\(id.uuidString)')")
        case .object(let number):
            view.evaluate("window.wallaeroEditor && window.wallaeroEditor.selectObject(\(number))")
        case .variable, nil:
            view.evaluate("window.wallaeroEditor && window.wallaeroEditor.select(null)")
        }
    }

    private func handle(_ message: [String: Any]) {
        guard let model, let type = message["type"] as? String else { return }
        let id = (message["id"] as? String).flatMap(UUID.init(uuidString:))
        // An object of a Wallpaper Engine scene goes by a number.
        let number = (message["id"] as? NSNumber)?.intValue
        let patch = (message["patch"] as? [String: Any])?.compactMapValues { ($0 as? NSNumber)?.doubleValue }
        switch type {
        case "ready":
            // The page loaded, or loaded again after its files changed: bring it up to date.
            show(model.scene)
            select(model.selection)
            pageReady()
        case "clock":
            let seconds = (message["time"] as? NSNumber)?.doubleValue ?? 0
            pageSeconds = max(pageSeconds, seconds)
            model.pageClock(seconds: seconds, held: message["held"] as? Bool ?? true)
        case "engine":
            // The scene of Wallpaper Engine's in the background has started: its objects.
            if let text = message["scene"] as? String,
               let description = try? JSONDecoder().decode(EngineSceneDescription.self, from: Data(text.utf8)) {
                model.engineDidStart(description)
            }
        case "select":
            model.selection = id.map(SceneEditorItem.layer)
        case "select-object":
            model.selection = number.map(SceneEditorItem.object)
        case "change":
            if let id, let patch {
                model.applyFromPreview(layer: id, patch: patch)
            }
        case "object-change":
            if let number, let patch {
                model.applyFromPreview(object: number, patch: patch)
            }
        case "counts":
            print("page clock: \(message["counts"] ?? "")")
        case "commit":
            model.endGesture()
        case "delete":
            if let id {
                model.deleteLayer(id)
            }
        default:
            break
        }
    }
}

/// The preview at the proportions of the display the editor is on, centred in the space it is
/// given. Moving the window to another display shows how the scene will look there.
struct SceneEditorPreview: View {
    let controller: SceneEditorPreviewController
    @ObservedObject var model: SceneEditorModel
    /// Width to height of the display.
    @State private var aspectRatio: CGFloat = 16.0 / 10.0
    @State private var lastDrag: CGSize?

    private func readAspectRatio() {
        guard let size = (controller.view.window?.screen ?? NSScreen.main)?.frame.size, size.height > 0 else { return }
        aspectRatio = size.width / size.height
    }

    var body: some View {
        GeometryReader { geometry in
            let available = CGSize(width: max(geometry.size.width - 32, 100), height: max(geometry.size.height - 32, 100))
            let width = min(available.width, available.height * aspectRatio)
            WebPreviewHost(view: controller.view)
                .frame(width: width * model.viewZoom, height: width / aspectRatio * model.viewZoom)
                .clipShape(RoundedRectangle(cornerRadius: SystemLook.tileCornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
                // Turned as a card, the page is only looked at: a drag turns it, with Shift moves it.
                .overlay {
                    if model.showsCard {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    let by = CGSize(width: drag.translation.width - (lastDrag?.width ?? 0),
                                                    height: drag.translation.height - (lastDrag?.height ?? 0))
                                    lastDrag = drag.translation
                                    model.navigate(by: by, moving: NSEvent.modifierFlags.contains(.shift), within: geometry.size)
                                }
                                .onEnded { _ in lastDrag = nil })
                    }
                }
                .offset(model.viewPan)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
        .background(Color(nsColor: .underPageBackgroundColor))
        .onAppear {
            readAspectRatio()
            // Once more when the view has its window.
            DispatchQueue.main.async(execute: readAspectRatio)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeScreenNotification)) { notification in
            if notification.object as? NSWindow === controller.view.window {
                readAspectRatio()
            }
        }
    }
}

private struct WebPreviewHost: NSViewRepresentable {
    let view: WebWallpaperView

    func makeNSView(context: Context) -> WebWallpaperView { view }
    func updateNSView(_ nsView: WebWallpaperView, context: Context) {}
}

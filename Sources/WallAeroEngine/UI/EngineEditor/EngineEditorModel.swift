import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import WallpaperCore

/// A scene of Wallpaper Engine's being made or changed in the editor: its project, what is
/// selected, and the history of changes to take back. Every change shows in the preview at once
/// and is written to the project a moment later; the project is then laid out for the player
/// anew, so a wallpaper on the desktop follows the editor.
@MainActor
final class EngineEditorModel: ObservableObject {
    /// The scene of the app.
    let folder: URL
    /// Its Wallpaper Engine project.
    let projectFolder: URL
    let title: String

    @Published var document: WallpaperEngineDocument {
        didSet { documentDidChange(from: oldValue) }
    }
    /// The object selected; nil is the scene as a whole.
    @Published var selection: Int? {
        didSet {
            if selection != oldValue {
                preview?.select(selection)
                timelineDidChangeObject()
            }
        }
    }
    /// What the player says of the scene once it plays: the values of the effects, among others.
    @Published private(set) var description: EngineSceneDescription?
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var isPlaying = true {
        didSet { preview?.setPlaying(isPlaying) }
    }
    /// A sheet the editor shows: the effects to add.
    @Published var sheet: Sheet?
    /// The picture whose puppet warp is being edited; the middle of the window is then its.
    @Published var puppetObject: Int?
    /// What a drag over the scene does.
    @Published var tool = Tool.multi {
        didSet { preview?.setTool(tool) }
    }
    /// How much the scene is enlarged in the preview, and how far it is moved from the middle.
    @Published private(set) var viewZoom: CGFloat = 1
    @Published private(set) var viewPan = CGSize.zero
    /// The part of an object's properties and of the scene's on show. Each stays as it is from
    /// one selection to the next, so that the same thing can be looked at on object after object.
    @Published var objectTab = ObjectTab.object
    @Published var sceneTab = SceneTab.scene
    /// Whether the timeline is open under the scene; the scene then stands at its moment.
    @Published var showsTimeline = false {
        didSet {
            guard showsTimeline != oldValue else { return }
            if !showsTimeline { setTimelinePlaying(false) }
            showTimelineMoment()
        }
    }
    /// The moment the timeline stands at, in seconds.
    @Published var timelineSeconds = 0.0 {
        didSet {
            if timelineSeconds != oldValue { showTimelineMoment() }
        }
    }
    /// What of the selected object the timeline's keys and curves are for.
    @Published var timelineTarget: WallpaperEngineAnimationTarget?
    /// The moments selected, on one value or on several.
    @Published var selectedKeys: Set<EngineTimelineKey> = []
    /// The first of them, for what is shown of one.
    var selectedKey: EngineTimelineKey? { selectedKeys.first }
    var timelineClipboard: [EngineCopiedKey] = []
    /// What of the time the timeline shows: from a second, as many seconds; nil is all of it.
    @Published var timelineStart = 0.0
    @Published var timelineSpan: Double?
    /// The heights the curves are shown in; nil follows the curves.
    @Published var curveRange: ClosedRange<Double>?
    /// Where the timeline's tracks are in the window, from its top left, for the wheel over them.
    var timelineArea = CGRect.zero
    /// Whether a change of an animated value makes a moment where there is none.
    @Published var autoKey = true
    @Published var timelineCurves = false
    @Published var timelinePlaying = false
    var timelineTimer: Timer?
    /// What the list of layers is narrowed down to.
    @Published var layerFilter = ""

    enum Sheet: Identifiable {
        case effects(object: Int)
        /// How an animation plays; `fallback` is the value of one not yet written in the scene.
        case animation(object: Int, target: WallpaperEngineAnimationTarget, isNew: Bool, fallback: [Double])
        case events(target: WallpaperEngineAnimationTarget)

        var id: String {
            switch self {
            case .effects(let object): return "effects-\(object)"
            case .animation(let object, let target, _, _): return "animation-\(object)-\(target)"
            case .events(let target): return "events-\(target)"
            }
        }
    }

    enum Tool: CaseIterable {
        /// Picks, moves, and scales and turns by the handles of the frame.
        case multi
        case move
        case rotate
        case scale

        var symbol: String {
            switch self {
            case .multi: return "cursorarrow"
            case .move: return "arrow.up.and.down.and.arrow.left.and.right"
            case .rotate: return "rotate.right"
            case .scale: return "arrow.up.left.and.arrow.down.right"
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .multi: return "Select and Transform (W)"
            case .move: return "Move (G)"
            case .rotate: return "Rotate (R)"
            case .scale: return "Scale (S)"
            }
        }

        var hint: LocalizedStringKey {
            switch self {
            case .multi: return "Drag to move. The corners resize, the round handle turns."
            case .move: return "Drag to move. Shift keeps to one axis."
            case .rotate: return "Drag anywhere to turn. Shift turns by 15°."
            case .scale: return "Drag anywhere to resize."
            }
        }
    }

    enum ObjectTab {
        case object
        /// What only this kind of object has: its text, its particles, its light.
        case kind
        case effects
    }

    enum SceneTab {
        case scene
        case view
        case environment
        case settings
    }

    /// Called after the scene was written and laid out.
    var onSave: (() -> Void)?
    weak var preview: EngineEditorPreviewController?

    private var undoStack: [WallpaperEngineDocument] = []
    private var redoStack: [WallpaperEngineDocument] = []
    private var lastChange = Date.distantPast
    private var isApplyingHistory = false
    private var saveTask: Task<Void, Never>?
    private var layoutTask: Task<Void, Never>?
    /// The project as it is on disk.
    private var savedDocument: WallpaperEngineDocument
    /// Files were brought into the project that the player does not have yet.
    private var hasNewFiles = false

    init(folder: URL, title: String) throws {
        guard let project = WallpaperEngineProjectFolder.project(ofScene: folder) else {
            throw WallpaperEngineProjectFolder.Problem.noScene
        }
        self.folder = folder
        projectFolder = project
        self.title = title
        let read = try WallpaperEngineProjectFolder.read(from: project)
        document = read
        savedDocument = read
    }

    // MARK: - Changes

    private func documentDidChange(from old: WallpaperEngineDocument) {
        guard document != old else { return }
        if !isApplyingHistory {
            // Changes that follow closely — a slider being dragged — are one step to undo.
            if Date().timeIntervalSince(lastChange) > 0.6 {
                undoStack.append(old)
                if undoStack.count > 200 { undoStack.removeFirst() }
                redoStack = []
            }
            lastChange = Date()
        }
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        if let selection, document.object(selection) == nil {
            self.selection = nil
        }
        preview?.show(document, after: old)
        scheduleSave()
    }

    /// The next change starts a new step to undo, however soon it comes.
    func endGesture() {
        lastChange = .distantPast
    }

    /// Makes a change as one step of its own.
    func change(_ body: (inout WallpaperEngineDocument) throws -> Void) rethrows {
        endGesture()
        var copy = document
        try body(&copy)
        document = copy
        endGesture()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        restore(next)
    }

    private func restore(_ other: WallpaperEngineDocument) {
        isApplyingHistory = true
        document = other
        isApplyingHistory = false
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        endGesture()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    /// Writes the project at once if it changed, and lays it out for the player.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard document != savedDocument || hasNewFiles else { return }
        do {
            try WallpaperEngineProjectFolder.write(document, previous: savedDocument, to: projectFolder)
            savedDocument = document
        } catch {
            Log.playback.error("Cannot save the project \(self.folder.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }
        let reload = hasNewFiles
        hasNewFiles = false
        let folder = self.folder
        layoutTask?.cancel()
        layoutTask = Task { [weak self] in
            let done = await Task.detached(priority: .userInitiated) { () -> Bool in
                (try? WallpaperEngineProjectFolder.layOut(scene: folder)) != nil
            }.value
            guard let self, done, !Task.isCancelled else { return }
            if reload {
                self.preview?.reload()
                // A video plays in the editor once it is WebM.
                MediaConversion.shared.convertSoon(folder)
            }
            self.onSave?()
        }
    }

    // MARK: - From the preview

    func playerDidStart(_ description: EngineSceneDescription) {
        if description != self.description {
            self.description = description
        }
    }

    /// An object moved, scaled or turned with the mouse; the page shows it already.
    func applyFromPreview(object id: Int, patch: [String: Double]) {
        if patch["x"] != nil || patch["y"] != nil {
            var origin = value(id, "origin")?.vector ?? [0, 0, 0]
            while origin.count < 3 { origin.append(0) }
            if let x = patch["x"] { origin[0] = x }
            if let y = patch["y"] { origin[1] = y }
            set(id, "origin", .vector(origin))
        }
        if patch["scaleX"] != nil || patch["scaleY"] != nil {
            var scale = value(id, "scale")?.vector ?? [1, 1, 1]
            while scale.count < 3 { scale.append(1) }
            if let x = patch["scaleX"] { scale[0] = x }
            if let y = patch["scaleY"] { scale[1] = y }
            set(id, "scale", .vector(scale))
        }
        if let rotation = patch["rotation"] {
            var angles = value(id, "angles")?.vector ?? [0, 0, 0]
            while angles.count < 3 { angles.append(0) }
            angles[2] = -rotation * .pi / 180
            set(id, "angles", .vector(angles))
        }
    }

    /// Where the animations of the scene stand on the timeline, for the frame over an object to
    /// start from; nil when the object is as the scene says.
    func animatedPlace(of id: Int, _ name: String) -> Double? {
        guard showsTimeline else { return nil }
        func part(_ key: String, _ index: Int) -> Double? {
            guard document.animation(of: id, .value(key)) != nil, let numbers = value(id, key)?.vector, index < numbers.count else { return nil }
            return numbers[index]
        }
        switch name {
        case "x": return part("origin", 0)
        case "y": return part("origin", 1)
        case "scaleX": return part("scale", 0)
        case "scaleY": return part("scale", 1)
        case "rotation": return part("angles", 2).map { -$0 * 180 / .pi }
        default: return nil
        }
    }

    /// Has the scene show the moment of the timeline, or go on as it plays.
    func showTimelineMoment() {
        preview?.showAnimations(at: showsTimeline ? timelineSeconds : nil)
    }

    // MARK: - The lock screen

    /// Whether an object is part of the still picture the lock screen shows. The app keeps this
    /// beside the project, in the scene's own file: Wallpaper Engine has nothing of the kind,
    /// and the project stays as it takes it.
    func showsOnLockScreen(_ id: Int) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                guard let self, let scene = try? SceneProject.read(from: self.folder) else { return true }
                return scene.background.engine[object: id].showsOnLockScreen ?? true
            },
            set: { [weak self] shows in
                guard let self, var scene = try? SceneProject.read(from: self.folder) else { return }
                scene.background.engine[object: id].showsOnLockScreen = shows ? nil : false
                try? SceneProject.write(scene, to: self.folder)
                self.objectWillChange.send()
                self.onSave?()
            }
        )
    }

    // MARK: - The view of the scene

    /// Enlarges the scene around a point, given from the middle of the preview, which stays
    /// under the pointer. It does not get smaller than the space it is shown in.
    func zoomView(by factor: CGFloat, around point: CGSize) {
        let zoom = min(max(viewZoom * factor, 1), 4)
        let share = zoom / viewZoom
        viewPan = zoom == 1 ? .zero : CGSize(width: viewPan.width + point.width * (1 - share),
                                             height: viewPan.height + point.height * (1 - share))
        viewZoom = zoom
    }

    /// Moves the scene, not further than its middle reaching the edge of what is shown of it.
    func panView(by distance: CGSize, within size: CGSize) {
        guard viewZoom > 1 else { return }
        viewPan = CGSize(width: min(max(viewPan.width + distance.width, -size.width / 2), size.width / 2),
                         height: min(max(viewPan.height + distance.height, -size.height / 2), size.height / 2))
    }

    func fitView() {
        viewZoom = 1
        viewPan = .zero
    }

    // MARK: - Objects

    /// The rows of the list of layers with what its search field leaves. The ones it finds are
    /// shown side by side, as what they hang on need not be among them.
    var shownRows: [(id: Int, depth: Int)] {
        let wanted = layerFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return rows }
        return rows.filter { name(of: $0.id).localizedStandardContains(wanted) }.map { ($0.id, 0) }
    }

    /// Puts the rows of the list of layers in another order by dragging them. What hangs on
    /// another keeps hanging on it; the list has the one in front first, the scene last.
    func moveRows(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ids = rows.map(\.id)
        let moved = source.map { ids[$0] }
        let before = ids[..<destination].filter { !moved.contains($0) }
        let after = ids[destination...].filter { !moved.contains($0) }
        ids = before + moved + after
        change { $0.reorder(ids.reversed()) }
    }

    /// The objects as the list shows them: the one in front first, each followed by those that
    /// hang on it, one step further in.
    var rows: [(id: Int, depth: Int)] {
        let ids = document.objectIDs
        let known = Set(ids)
        var children: [Int: [Int]] = [:]
        var roots: [Int] = []
        for id in ids {
            if let parent = document.parent(of: id), parent != id, known.contains(parent) {
                children[parent, default: []].append(id)
            } else {
                roots.append(id)
            }
        }
        var result: [(Int, Int)] = []
        var seen: Set<Int> = []
        func add(_ id: Int, depth: Int) {
            guard seen.insert(id).inserted else { return }
            result.append((id, depth))
            for child in (children[id] ?? []).reversed() { add(child, depth: depth + 1) }
        }
        roots.reversed().forEach { add($0, depth: 0) }
        ids.reversed().forEach { add($0, depth: 0) }
        return result
    }

    func name(of id: Int) -> String {
        guard let object = document.object(id) else { return "" }
        if let name = object["name"]?.plain.stringValue, !name.isEmpty { return name }
        return Self.kindTitle(WallpaperEngineDocument.kind(of: object))
    }

    func kind(of id: Int) -> WallpaperEngineDocument.ObjectKind {
        document.object(id).map(WallpaperEngineDocument.kind(of:)) ?? .group
    }

    func isVisible(_ id: Int) -> Bool {
        document.object(id)?["visible"]?.plain.boolValue ?? true
    }

    func toggleVisibility(of id: Int) {
        let shown = !isVisible(id)
        change { document in
            document.update(id) { $0["visible"] = ($0["visible"] ?? .null).replacingPlain(with: .bool(shown)) }
        }
    }

    func rename(_ id: Int, to name: String) {
        change { document in document.update(id) { $0["name"] = .string(name) } }
    }

    func delete(_ id: Int) {
        change {
            $0.remove(id)
            $0.countLights()
        }
    }

    func duplicate(_ id: Int) {
        var made: Int?
        change {
            made = $0.duplicate(id)
            $0.countLights()
        }
        selection = made
    }

    /// Moves an object one place nearer the front, or further back, among those it hangs with.
    func move(_ id: Int, forward: Bool) {
        let parent = document.parent(of: id)
        var order = document.objectIDs
        let siblings = order.filter { document.parent(of: $0) == parent }
        guard let at = siblings.firstIndex(of: id) else { return }
        let other = forward ? at + 1 : at - 1
        guard siblings.indices.contains(other) else { return }
        let a = order.firstIndex(of: id)!, b = order.firstIndex(of: siblings[other])!
        order.swapAt(a, b)
        change { $0.reorder(order) }
    }

    /// Hangs an object on another, or on nothing; it stays where it is in the scene.
    func setParent(of id: Int, to parent: Int?) {
        guard parent != id, !(parent.map { isInside($0, id) } ?? false) else { return }
        let before = worldOrigin(of: id)
        let base = parent.map(worldOrigin(of:)) ?? [0, 0]
        change { document in
            document.update(id) { object in
                if let parent { object["parent"] = .number(Double(parent)) } else { object["parent"] = nil }
                var origin = object["origin"]?.vector ?? [0, 0, 0]
                while origin.count < 3 { origin.append(0) }
                origin[0] = before[0] - base[0]
                origin[1] = before[1] - base[1]
                object["origin"] = (object["origin"] ?? .null).replacingPlain(with: .vector(origin))
            }
            // Drawn with what it now hangs on: just after it and its own.
            var order = document.objectIDs.filter { $0 != id }
            if let parent, let at = order.lastIndex(where: { $0 == parent || self.isInside($0, parent, in: document) }) {
                order.insert(id, at: at + 1)
            } else {
                order.append(id)
            }
            document.reorder(order)
        }
    }

    /// Whether an object hangs on another, at any depth.
    func isInside(_ id: Int, _ other: Int) -> Bool {
        isInside(id, other, in: document)
    }

    private func isInside(_ id: Int, _ other: Int, in document: WallpaperEngineDocument) -> Bool {
        var at = document.parent(of: id)
        var steps = 0
        while let current = at, steps < 64 {
            if current == other { return true }
            at = document.parent(of: current)
            steps += 1
        }
        return false
    }

    /// Where an object is in the scene, as the places of what it hangs on add up.
    private func worldOrigin(of id: Int) -> [Double] {
        var total = [0.0, 0.0]
        var at: Int? = id
        var steps = 0
        while let current = at, steps < 64 {
            let origin = document.object(current)?["origin"]?.vector ?? [0, 0]
            total[0] += origin.first ?? 0
            total[1] += origin.count > 1 ? origin[1] : 0
            at = document.parent(of: current)
            steps += 1
        }
        return total
    }

    // MARK: - Adding

    /// Where a new object goes: into the selected composition layer or group, else on its own.
    private var newParent: Int? {
        guard let selection else { return nil }
        let kind = self.kind(of: selection)
        return kind == .composition || kind == .group ? selection : nil
    }

    func addPicture() {
        guard let url = choose([.image]) else { return }
        do {
            let picture = try WallpaperEngineProjectFolder.addPicture(url, to: projectFolder)
            hasNewFiles = true
            var made = 0
            change { made = $0.addImage(texture: picture.texture, width: picture.width, height: picture.height,
                                        name: url.deletingPathExtension().lastPathComponent, under: newParent) }
            selection = made
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func addVideo() {
        guard let url = choose([.movie]) else { return }
        let projectFolder = self.projectFolder
        let parent = newParent
        Task {
            do {
                let video = try await WallpaperEngineVideo.prepare(url)
                let texture = try WallpaperEngineProjectFolder.addVideo(video.file, width: video.width, height: video.height,
                                                                         named: url.deletingPathExtension().lastPathComponent, to: projectFolder)
                hasNewFiles = true
                var made = 0
                change { made = $0.addImage(texture: texture, width: video.width, height: video.height,
                                            name: url.deletingPathExtension().lastPathComponent, under: parent) }
                selection = made
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    func addText() {
        var made = 0
        change { made = $0.addText(NSLocalizedString("Text", comment: "Text of a new text object"), name: Self.kindTitle(.text), under: newParent) }
        selection = made
    }

    func addSolid() {
        let size = document.size
        var made = 0
        change { made = $0.addSolid(color: [0.2, 0.5, 0.9], width: size.width / 3, height: size.height / 3, name: Self.kindTitle(.solid), under: newParent) }
        selection = made
    }

    func addComposition() {
        var made = 0
        change { made = $0.addComposition(name: Self.kindTitle(.composition), under: newParent) }
        selection = made
    }

    func addLight(_ kind: WallpaperEngineDocument.LightKind) {
        var made = 0
        change { made = $0.addLight(kind, name: Self.lightTitle(kind), under: newParent) }
        selection = made
    }

    static func lightTitle(_ kind: WallpaperEngineDocument.LightKind) -> String {
        switch kind {
        case .point: return NSLocalizedString("Point Light", comment: "Kind of a light of a Wallpaper Engine scene")
        case .spot: return NSLocalizedString("Spotlight", comment: "Kind of a light of a Wallpaper Engine scene")
        case .directional: return NSLocalizedString("Directional Light", comment: "Kind of a light of a Wallpaper Engine scene")
        case .tube: return NSLocalizedString("Tube Light", comment: "Kind of a light of a Wallpaper Engine scene")
        }
    }

    func addCamera() {
        var made = 0
        change { made = $0.addCamera(name: Self.kindTitle(.camera)) }
        selection = made
    }

    func addGroup() {
        var made = 0
        change { made = $0.addGroup(name: Self.kindTitle(.group), under: newParent) }
        selection = made
    }

    func addParticles(_ preset: WallpaperEngineParticlePreset) {
        do {
            var made = 0
            try change { made = try $0.addParticles(preset, projectFolder: projectFolder) }
            hasNewFiles = true
            selection = made
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func addSound() {
        guard let url = choose([.audio]) else { return }
        do {
            let file = try WallpaperEngineProjectFolder.addFile(url, into: "sounds", of: projectFolder)
            hasNewFiles = true
            var made = 0
            change { made = $0.addSound(file, name: url.deletingPathExtension().lastPathComponent) }
            selection = made
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Puts a picture in place of the one an image object shows.
    func replacePicture(of id: Int) {
        guard let url = choose([.image]), let material = document.material(ofObject: id) else { return }
        do {
            let picture = try WallpaperEngineProjectFolder.addPicture(url, to: projectFolder)
            hasNewFiles = true
            change { document in
                var value = material.value
                if var passes = value["passes"]?.arrayValue, !passes.isEmpty {
                    // Only the picture: its normal map and masks stay.
                    var textures = passes[0]["textures"]?.arrayValue ?? []
                    if textures.isEmpty { textures.append(.null) }
                    textures[0] = .string(picture.texture)
                    passes[0]["textures"] = .array(textures)
                    value["passes"] = .array(passes)
                }
                document.setFile(material.name, value)
                document.update(id) { $0["size"] = .vector([Double(picture.width), Double(picture.height)]) }
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// A picture brought into the project as the normal map of a picture: which way each of
    /// its points faces, for the lights to light it by.
    func chooseNormalMap(of id: Int) {
        guard let url = choose([.image]) else { return }
        do {
            let picture = try WallpaperEngineProjectFolder.addPicture(url, to: projectFolder)
            hasNewFiles = true
            setMaterialTexture(id, slot: 1, to: picture.texture)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// A font file brought into the project, for a text to be written in.
    func importFont(for id: Int) {
        let types = ["ttf", "otf"].compactMap { UTType(filenameExtension: $0) }
        guard let url = choose(types) else { return }
        do {
            let file = try WallpaperEngineProjectFolder.addFile(url, into: "fonts", of: projectFolder)
            hasNewFiles = true
            change { document in document.update(id) { $0["font"] = .string(file) } }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Files were written into the project — a puppet, say — that the player is to read.
    func markNewFiles() {
        hasNewFiles = true
        scheduleSave()
    }

    // MARK: - Effects

    func addEffect(_ effect: WallpaperEngineEffect, to id: Int) {
        do {
            try change { try $0.addEffect(effect, to: id, projectFolder: projectFolder) }
            hasNewFiles = true
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    // MARK: - Helpers

    private func choose(_ types: [UTType]) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = NSLocalizedString("Choose", comment: "Open panel button")
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func kindTitle(_ kind: WallpaperEngineDocument.ObjectKind) -> String {
        switch kind {
        case .image: return NSLocalizedString("Image", comment: "Kind of an object of a Wallpaper Engine scene")
        case .text: return NSLocalizedString("Text", comment: "Kind of an object of a Wallpaper Engine scene")
        case .particles: return NSLocalizedString("Particles", comment: "Kind of an object of a Wallpaper Engine scene")
        case .sound: return NSLocalizedString("Sound", comment: "Kind of an object of a Wallpaper Engine scene")
        case .model: return NSLocalizedString("3D Model", comment: "Kind of an object of a Wallpaper Engine scene")
        case .light: return NSLocalizedString("Light Source", comment: "Kind of an object of a Wallpaper Engine scene")
        case .camera: return NSLocalizedString("Camera", comment: "Kind of an object of a Wallpaper Engine scene")
        case .solid: return NSLocalizedString("Solid Color", comment: "Kind of an object of a Wallpaper Engine scene")
        case .composition: return NSLocalizedString("Composition Layer", comment: "Kind of an object of a Wallpaper Engine scene")
        case .fullscreen: return NSLocalizedString("Fullscreen Layer", comment: "Kind of an object of a Wallpaper Engine scene")
        case .group: return NSLocalizedString("Group", comment: "Kind of an object of a Wallpaper Engine scene")
        }
    }

    static func symbol(_ kind: WallpaperEngineDocument.ObjectKind) -> String {
        switch kind {
        case .image: return "photo"
        case .text: return "textformat"
        case .particles: return "sparkles"
        case .sound: return "speaker.wave.2"
        case .model: return "cube"
        case .light: return "lightbulb"
        case .camera: return "video"
        case .solid: return "square.fill"
        case .composition: return "square.stack.3d.up"
        case .fullscreen: return "rectangle.inset.filled"
        case .group: return "square.dashed"
        }
    }
}

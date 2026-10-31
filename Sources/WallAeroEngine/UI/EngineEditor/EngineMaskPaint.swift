import AppKit
import SwiftUI
import WallpaperCore

/// A mask being painted over the scene, with the brush's settings as Wallpaper Engine's editor
/// has them. The scene shows every dab; the project gets the mask once it is done.
@MainActor
final class EngineMaskPaint: ObservableObject {
    /// The mask of an effect of an object.
    struct Target {
        var object: Int
        var effect: Int
        var mask: EngineSceneDescription.Mask
    }

    enum Brush: String, CaseIterable {
        case draw, direction, fixed, spin, spread, pinch, smooth

        var title: LocalizedStringKey {
            switch self {
            case .draw: return "Draw"
            case .direction: return "Direction"
            case .fixed: return "Fixed Direction"
            case .spin: return "Spin Round"
            case .spread: return "Spread"
            case .pinch: return "Pinch"
            case .smooth: return "Smooth Out"
            }
        }

        var symbol: String {
            switch self {
            case .draw: return "paintbrush"
            case .direction: return "arrow.up.right"
            case .fixed: return "arrow.right"
            case .spin: return "arrow.clockwise"
            case .spread: return "arrow.up.left.and.arrow.down.right"
            case .pinch: return "arrow.down.right.and.arrow.up.left"
            case .smooth: return "drop"
            }
        }
    }

    let target: Target
    /// What the mask is called in the scene while it is painted.
    let texture: String
    /// Whether that texture was made for this painting, and goes if it is given up.
    let isNew: Bool
    /// The scene as it was before, which one step takes back to.
    let before: WallpaperEngineDocument
    private let original: WallpaperEngineMask

    /// In pixels of the scene across.
    @Published var size = 40.0
    /// Both in percent.
    @Published var opacity = 100.0
    @Published var hardness = 50.0
    /// What the brush lays down, from 0 to 255; on a direction map, how strong a direction.
    @Published var value = 255.0
    /// What it lays down on a map of colors.
    @Published var color = "#FFFFFF"
    /// The way a fixed direction goes, in degrees, clockwise from the right.
    @Published var angle = 0.0
    @Published var brush: Brush
    /// The other effects of the object are left out of the scene.
    @Published var isolates = false {
        didSet { onIsolate?(isolates) }
    }
    @Published var showsMask = false {
        didSet { onPainted?() }
    }
    @Published var maskOpacity = 50.0 {
        didSet { onPainted?() }
    }
    /// The next click takes the value from the mask.
    @Published var isPicking = false

    private(set) var mask: WallpaperEngineMask
    private var stroke: WallpaperEngineMask.Stroke?
    private var undoSteps: [WallpaperEngineMask] = []
    private var redoSteps: [WallpaperEngineMask] = []
    private var pushWaits = false

    weak var preview: EngineEditorPreviewController?
    /// The mask changed, or the way it is shown.
    var onPainted: (() -> Void)?
    /// What can be taken back changed.
    var onHistory: (() -> Void)?
    var onIsolate: ((Bool) -> Void)?

    /// The brushes this map can be painted with, as Wallpaper Engine's editor has them.
    var brushes: [Brush] {
        target.mask.isFlow ? [.direction, .fixed, .spin, .spread, .pinch, .smooth] : [.draw, .smooth]
    }

    var canUndo: Bool { !undoSteps.isEmpty }
    var canRedo: Bool { !redoSteps.isEmpty }

    init(target: Target, mask: WallpaperEngineMask, texture: String, isNew: Bool, before: WallpaperEngineDocument) {
        self.target = target
        self.mask = mask
        original = mask
        self.texture = texture
        self.isNew = isNew
        self.before = before
        brush = target.mask.isFlow ? .direction : .draw
    }

    var isChanged: Bool { mask != original }

    /// The mask as it was, for a scene being given it back.
    func revert() {
        mask = original
        push()
    }

    // MARK: - Strokes

    func startStroke() {
        remember()
        stroke = mask.startStroke()
    }

    /// Takes the brush to a point of the mask, sized in pixels of the mask.
    func paint(atX x: Double, y: Double, radiusX: Double, radiusY: Double) {
        guard stroke != nil else { return }
        let brush = WallpaperEngineMask.Brush(radiusX: max(0.5, radiusX), radiusY: max(0.5, radiusY), hardness: hardness / 100, opacity: opacity / 100,
                                              paint: paintKind)
        mask.paint(&stroke!, with: brush, toX: x, y: y)
        schedulePush()
    }

    private var paintKind: WallpaperEngineMask.Paint {
        let strength = value / 255
        switch brush {
        case .draw: return .values(laid)
        case .smooth: return .smooth
        case .direction: return .flow(.along, strength: strength)
        case .fixed: return .flow(.fixed(x: cos(angle * .pi / 180), y: sin(angle * .pi / 180)), strength: strength)
        case .spin: return .flow(.spin, strength: strength)
        case .spread: return .flow(.spread, strength: strength)
        case .pinch: return .flow(.pinch, strength: strength)
        }
    }

    /// The values the brush lays down, a color's or a shade's.
    private var laid: [UInt8] {
        guard target.mask.isColor else { return [UInt8(value)] }
        return (EngineEditorModel.numbers(hex: color) ?? [1, 1, 1]).prefix(3).map { UInt8(min(255, max(0, ($0 * 255).rounded()))) }
    }

    func endStroke() {
        stroke = nil
    }

    /// Fills the whole mask with what the brush lays down; a direction map goes back to none.
    func fill() {
        remember()
        mask.fill(target.mask.isFlow ? target.mask.start : laid)
        push()
    }

    func pickValue(atX x: Double, y: Double) {
        let found = mask.values(atX: x, y: y)
        if target.mask.isColor, found.count >= 3 {
            color = EngineEditorModel.hex(found.prefix(3).map { Double($0) / 255 })
        } else if !target.mask.isFlow, let first = found.first {
            value = Double(first)
        }
        isPicking = false
    }

    private func remember() {
        undoSteps.append(mask)
        if undoSteps.count > 30 { undoSteps.removeFirst() }
        redoSteps = []
        onHistory?()
    }

    func undo() {
        guard let step = undoSteps.popLast() else { return }
        redoSteps.append(mask)
        mask = step
        push()
        onHistory?()
    }

    func redo() {
        guard let step = redoSteps.popLast() else { return }
        undoSteps.append(mask)
        mask = step
        push()
        onHistory?()
    }

    // MARK: - To the scene

    /// A mouse gives more points than frames: the scene gets the mask once for each turn.
    private func schedulePush() {
        guard !pushWaits else { return }
        pushWaits = true
        DispatchQueue.main.async { [weak self] in
            self?.pushWaits = false
            self?.push()
        }
    }

    func push() {
        preview?.showMask(texture, mask)
        onPainted?()
    }
}

extension EngineEditorModel {
    /// The name of an effect's folder, which its masks are named after.
    private func effectName(of target: EngineMaskPaint.Target) -> String {
        let effects = document.object(target.object)?["effects"]?.arrayValue ?? []
        guard effects.indices.contains(target.effect), let file = effects[target.effect]["file"]?.stringValue else { return "effect" }
        return ((file as NSString).deletingLastPathComponent as NSString).lastPathComponent
    }

    /// The maps of an effect to offer: what fills a slot with what is drawn elsewhere in the
    /// scene is not for painting.
    func paintableMasks(of effect: EngineSceneDescription.Effect, object: Int) -> [EngineSceneDescription.Mask] {
        (effect.masks ?? []).filter { mask in
            maskTexture(of: .init(object: object, effect: effect.id, mask: mask))?.hasPrefix("_rt_") != true
        }
    }

    func maskTexture(of target: EngineMaskPaint.Target) -> String? {
        document.effectTexture(object: target.object, effect: target.effect, pass: target.mask.passes[0], slot: target.mask.slot)
    }

    /// Opens a mask to paint: the one the effect has, or a new one, which the scene needs before
    /// a dab of it can be shown.
    func startPainting(_ target: EngineMaskPaint.Target) {
        guard painting == nil, let preview, preview.drawsNatively else { return }
        selection = target.object
        let before = document
        let name = maskTexture(of: target)
        let found = name.flatMap { try? Data(contentsOf: projectFolder.appendingPathComponent("materials/\($0).tex")) }
            .flatMap { WallpaperEngineMask(textureFile: $0, channels: target.mask.start.count) }
        let session: EngineMaskPaint
        if let name, let found {
            session = EngineMaskPaint(target: target, mask: found, texture: name, isNew: false, before: before)
        } else {
            let size = preview.objectSize(target.object) ?? document.size
            let chosen = WallpaperEngineMask.size(forObject: Int(size.width), Int(size.height))
            let blank = WallpaperEngineMask(width: chosen.width, height: chosen.height, values: target.mask.start)
            guard let made = try? blank.save(forEffect: effectName(of: target), to: projectFolder) else { return }
            madeMasks.insert(made)
            var changed = document
            changed.setEffectTexture(made, object: target.object, effect: target.effect, passes: target.mask.passes, slot: target.mask.slot)
            replaceDocument(with: changed, undoingTo: nil)
            markNewFiles()
            saveNow()
            session = EngineMaskPaint(target: target, mask: blank, texture: made, isNew: true, before: before)
        }
        session.preview = preview
        session.onPainted = { [weak preview] in preview?.maskChanged() }
        session.onHistory = { [weak self, weak session] in
            guard let self, let session else { return }
            self.showHistory(canUndo: session.canUndo, canRedo: session.canRedo)
        }
        session.onHistory?()
        session.onIsolate = { [weak self, weak session] on in
            if let self, let session { self.isolate(on, session) }
        }
        painting = session
        preview.setPainting(session)
    }

    /// Ends the painting: the mask goes into the project as one step to take back, or is given up.
    func finishPainting(keeping keep: Bool) {
        guard let session = painting else { return }
        painting = nil
        preview?.setPainting(nil)
        let target = session.target
        if keep, session.isChanged || session.isNew,
           let name = try? session.mask.save(forEffect: effectName(of: target), to: projectFolder) {
            madeMasks.insert(name)
            var changed = session.before
            changed.setEffectTexture(name, object: target.object, effect: target.effect, passes: target.mask.passes, slot: target.mask.slot)
            replaceDocument(with: changed, undoingTo: session.before)
            markNewFiles()
        } else if session.isNew {
            replaceDocument(with: session.before, undoingTo: nil)
            markNewFiles()
        } else {
            session.revert()
            if document != session.before { replaceDocument(with: session.before, undoingTo: nil) }
        }
        saveNow()
    }

    /// Leaves the object's other effects out for now. What the scene was before painting comes
    /// back with the end of it, whatever this changed.
    private func isolate(_ on: Bool, _ session: EngineMaskPaint) {
        let target = session.target
        let count = document.object(target.object)?["effects"]?.arrayValue?.count ?? 0
        let original = session.before.object(target.object)?["effects"]?.arrayValue ?? []
        var changed = document
        changed.update(target.object) { object in
            guard var effects = object["effects"]?.arrayValue else { return }
            for index in 0..<count where index != target.effect {
                effects[index]["visible"] = on ? .bool(false) : (original.indices.contains(index) ? original[index]["visible"] : nil)
            }
            object["effects"] = .array(effects)
        }
        replaceDocument(with: changed, undoingTo: nil)
    }

    /// Takes a mask off its effect, which then works on the whole object.
    func removeMask(_ target: EngineMaskPaint.Target) {
        change {
            $0.setEffectTexture(nil, object: target.object, effect: target.effect, passes: target.mask.passes, slot: target.mask.slot)
        }
        markNewFiles()
    }

    /// What painting left behind and no step of this editor can reach any more.
    func dropUnusedMasks() {
        let scene = document.scene.text
        for name in madeMasks where !scene.contains(name) {
            try? FileManager.default.removeItem(at: projectFolder.appendingPathComponent("materials/\(name).tex"))
        }
        madeMasks = []
    }

    /// The window closes: what is being painted is kept, and all of it is written.
    func close() {
        finishPainting(keeping: true)
        openScript(nil)
        saveNow()
        dropUnusedMasks()
    }
}

/// A row of an effect for one of its masks.
struct EngineMaskRow: View {
    @ObservedObject var model: EngineEditorModel
    let target: EngineMaskPaint.Target

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Button(model.maskTexture(of: target) == nil ? "Paint" : "Repaint") { model.startPainting(target) }
                    .disabled(model.preview?.drawsNatively != true)
                if target.mask.isColor {
                    Button("Image…") { model.chooseMapPicture(target) }
                }
                if model.maskTexture(of: target) != nil {
                    Button {
                        model.removeMask(target)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove the mask")
                }
            }
        } label: {
            Text(verbatim: target.mask.title)
        }
    }
}

/// The brush, in place of the properties for as long as a mask is painted.
struct EngineBrushPanel: View {
    @ObservedObject var model: EngineEditorModel
    @ObservedObject var paint: EngineMaskPaint

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Brush", selection: $paint.brush) {
                        ForEach(paint.brushes, id: \.self) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    NumberRow("Size", value: $paint.size, in: 1...2000)
                    NumberRow("Opacity", value: $paint.opacity, in: 1...100, suffix: "%")
                    NumberRow("Hardness", value: $paint.hardness, in: 0...100, suffix: "%")
                } header: {
                    Text(verbatim: paint.target.mask.title)
                }
                if paint.target.mask.isFlow {
                    Section {
                        if paint.brush != .smooth {
                            NumberRow("Strength", value: $paint.value, in: 0...255)
                        }
                        if paint.brush == .fixed {
                            NumberRow("Angle", value: $paint.angle, in: 0...359, suffix: "°")
                        }
                        Button("Clear the Whole Map") { paint.fill() }
                    } footer: {
                        Text("The picture moves the way the brush goes.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else if paint.target.mask.isColor, paint.brush == .draw {
                    Section {
                        ColorRow(title: Text("Color"), hex: $paint.color)
                        picker
                        Button("Fill the Whole Map") { paint.fill() }
                    }
                } else if paint.brush == .draw {
                    Section {
                        NumberRow("Value", value: $paint.value, in: 0...255)
                        HStack {
                            Button("White") { paint.value = 255 }
                            Button("Black") { paint.value = 0 }
                            Spacer()
                            picker
                        }
                        Button("Fill the Whole Map") { paint.fill() }
                    } footer: {
                        if paint.target.mask.mode == "opacitymask" {
                            Text("Where the mask is white the effect works in full, where it is black not at all.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Toggle("Isolate Effect", isOn: $paint.isolates)
                        .help("Leave the object's other effects out while painting")
                    Toggle(paint.target.mask.isFlow ? "Show Directions" : "Show Mask", isOn: $paint.showsMask)
                        .help("Show the map over the scene (M)")
                    if paint.showsMask, !paint.target.mask.isFlow {
                        NumberRow("Mask Opacity", value: $paint.maskOpacity, in: 0...100, suffix: "%")
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { model.finishPainting(keeping: false) }
                    .keyboardShortcut(.cancelAction)
                Button("Done") { model.finishPainting(keeping: true) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
    }

    private var picker: some View {
        Toggle(isOn: $paint.isPicking) {
            Label("Take From the Map", systemImage: "eyedropper")
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .help("Take the value from the map (I)")
    }
}

import AppKit
import SwiftUI
import WallpaperCore

/// What is being worked on in the editor, as in Blender: the scene's objects, or one part of the
/// selected picture. The parts are those of Wallpaper Engine's puppet warp. Each mode has its own
/// tools on the scene and its own panel at the side; the timeline under the scene is the same in
/// all of them.
extension EngineEditorModel {
    enum Mode: String, CaseIterable {
        case object, mesh, rig, weights, pose, paint

        var title: LocalizedStringKey {
            switch self {
            case .object: return "Object Mode"
            case .mesh: return "Mesh Mode"
            case .rig: return "Rig Mode"
            case .weights: return "Weight Paint"
            case .pose: return "Pose Mode"
            case .paint: return "Mask Paint"
            }
        }

        var symbol: String {
            switch self {
            case .object: return "square.on.square"
            case .mesh: return "circle.grid.cross"
            case .rig: return "figure.stand"
            case .weights: return "flame"
            case .pose: return "figure.walk"
            case .paint: return "paintbrush"
            }
        }

        /// The tools on the scene in this mode, the one it starts with first.
        var tools: [Tool] {
            switch self {
            case .object: return [.multi, .move, .rotate, .scale]
            case .mesh: return [.multi]
            case .rig: return [.multi, .addBone]
            case .weights: return []
            case .pose: return [.rotate, .move]
            case .paint: return []
            }
        }

        /// A part of a picture's rig, not the scene as a whole.
        var isRig: Bool { self == .mesh || self == .rig || self == .weights || self == .pose }
    }

    var selectedRig: WallpaperEnginePuppetRig? {
        selection.flatMap(document.rig(ofObject:))
    }

    /// Whether the mode can be gone into with what is selected.
    func canEnter(_ wanted: Mode) -> Bool {
        guard preview?.drawsNatively == true else { return wanted == .object }
        switch wanted {
        case .object: return true
        case .mesh, .rig, .weights, .pose:
            guard let selection else { return false }
            return kind(of: selection) == .image && document.material(ofObject: selection) != nil
        case .paint:
            return firstPaintableMask != nil
        }
    }

    private var firstPaintableMask: EngineMaskPaint.Target? {
        guard let selection, let effects = description?.object(selection)?.effects else { return nil }
        for effect in effects {
            if let mask = paintableMasks(of: effect, object: selection).first {
                return .init(object: selection, effect: effect.id, mask: mask)
            }
        }
        return nil
    }

    func enter(_ wanted: Mode) {
        guard wanted != mode, canEnter(wanted) else { return }
        if mode == .paint { finishPainting(keeping: true) }
        if wanted == .paint {
            if mode.isRig { leaveRig() }
            if let target = firstPaintableMask { startPainting(target) }
            return
        }
        if wanted == .object {
            leaveRig()
            mode = .object
            tool = .multi
            showRig()
            return
        }
        guard let selection else { return }
        if document.rig(ofObject: selection) == nil { makeRig(selection) }
        mode = wanted
        lastEditMode = wanted
        tool = wanted.tools.first ?? .multi
        if wanted == .pose {
            if selectedRig?.animations.isEmpty == true { addRigAnimation() }
            showsTimeline = true
        }
        showRig()
    }

    /// Tab: into the mode last worked in and out again, as in Blender.
    func toggleEditMode() {
        enter(mode == .object ? lastEditMode : .object)
    }

    private func makeRig(_ id: Int) {
        guard let picture = document.picture(ofObject: id, projectFolder: projectFolder) else { return }
        let size = value(id, "size")?.vector ?? []
        let width = size.first ?? Double(picture.width), height = size.count > 1 ? size[1] : Double(picture.height)
        var rig = WallpaperEnginePuppetRig(width: width, height: height)
        meshDensity = max(16, (max(width, height) / 30).rounded())
        rig.makeMesh(from: picture, spacing: meshDensity)
        change { $0.setRig(rig, ofObject: id) }
    }

    /// A mesh with no bones on it holds nothing: the picture stays a plain one.
    private func leaveRig() {
        selectedPoints = []
        guard let selection, let rig = selectedRig, rig.bones.isEmpty else { return }
        change { $0.removeRig(ofObject: selection) }
        preview?.showPuppet(selection, table: nil, layers: nil)
        rigsShown.remove(selection)
    }

    func removePuppet() {
        guard let selection else { return }
        mode = .object
        tool = .multi
        change { $0.removeRig(ofObject: selection) }
        preview?.showPuppet(selection, table: nil, layers: nil)
        rigsShown.remove(selection)
        selectedBone = nil
        timelineTarget = timelineTargets.first
    }

    /// Changes the rig of the selected picture. Changes that follow closely are one step to take back.
    func editRig(_ edit: (inout WallpaperEnginePuppetRig) -> Void) {
        guard let selection, var rig = selectedRig else { return }
        edit(&rig)
        var copy = document
        copy.setRig(rig, ofObject: selection)
        document = copy
    }

    // MARK: - The scene follows

    /// Whether the scene stands as the editor has the bones, not as it plays.
    private var holdsBones: Bool { mode.isRig || showsTimeline }

    /// Has the scene show a picture's rig as it is now: its mesh and bones if they changed, and
    /// the bones where the mode and the timeline have them.
    func showRig(tableToo: Bool = false) {
        guard let selection, let rig = selectedRig else { return }
        if tableToo { sendRig(selection, rig) }
        preview?.holdBones(selection, holdsBones ? poses(of: rig) : nil)
    }

    private func sendRig(_ id: Int, _ rig: WallpaperEnginePuppetRig) {
        let material = document.object(id)?["image"]?.plain.stringValue.flatMap { document.file($0)?["material"]?.stringValue } ?? ""
        preview?.showPuppet(id, table: rig.playerTable(material: material), layers: document.object(id)?["animationlayers"]?.any)
        rigsShown.insert(id)
    }

    /// The rigs that changed in a step reach the scene; they are not read from the files again.
    func rigsDidChange(from old: WallpaperEngineDocument) {
        guard document.rigs != old.rigs else { return }
        // A step back to before the picture had a rig leaves nothing for the mode to work on.
        if mode.isRig, selectedRig == nil {
            mode = .object
            tool = .multi
        }
        for id in document.objectIDs {
            let now = document.rig(ofObject: id), before = old.rig(ofObject: id)
            guard now != before else { continue }
            guard let now else {
                preview?.showPuppet(id, table: nil, layers: nil)
                rigsShown.remove(id)
                continue
            }
            // Keys go with a table only when the scene plays them by itself.
            let sameShape = before.map { $0.points == now.points && $0.triangles == now.triangles && $0.bones == now.bones && $0.holds == now.holds } ?? false
            if !sameShape || id != selection || !holdsBones { sendRig(id, now) }
        }
        showRig()
    }

    /// The scene was played anew from files that may be behind what is edited.
    func rigsAfterRestart() {
        for id in rigsShown {
            if let rig = document.rig(ofObject: id) { sendRig(id, rig) }
        }
        showRig()
    }

    /// The bones of a rig at the moment of the timeline, each from its parent.
    private func poses(of rig: WallpaperEnginePuppetRig) -> [[Double]] {
        let shows = mode == .pose || (showsTimeline && !mode.isRig)
        return rig.localPoses(animation: shows ? rigAnimation : nil, frame: rigFrame, draft: mode == .pose ? poseDraft : [:])
    }

    /// The frame the timeline stands at, in the animation of the bones.
    var rigFrame: Double {
        guard let rig = selectedRig, rig.animations.indices.contains(rigAnimation) else { return 0 }
        return timelineSeconds * rig.animations[rigAnimation].framesPerSecond
    }

    /// How each bone stands now, from the picture, where the player does not say otherwise.
    func standingBones(of rig: WallpaperEnginePuppetRig) -> [CGAffineTransform] {
        if mode == .pose || (showsTimeline && !mode.isRig) {
            return rig.posedTransforms(animation: rigAnimation, frame: rigFrame, draft: mode == .pose ? poseDraft : [:])
        }
        return rig.posedTransforms(animation: nil, frame: 0)
    }

    // MARK: - Bones

    /// Picks a bone, whose keys the timeline is then on.
    func selectBone(_ bone: Int?) {
        selectedBone = bone
        selectedKeys = []
        timelineTarget = bone.map { .bone(animation: rigAnimation, bone: $0) } ?? timelineTargets.first
    }

    func deleteSelectedBone() {
        guard let bone = selectedBone else { return }
        editRig { $0.removeBone(bone) }
        endGesture()
        selectBone(nil)
    }

    /// What a bone is called: Wallpaper Engine leaves most of them without a name.
    func boneTitle(_ bone: WallpaperEnginePuppetRig.Bone) -> String {
        bone.name.isEmpty ? String(format: NSLocalizedString("Bone %d", comment: "Name of a new bone"), bone.index + 1) : bone.name
    }

    /// The tree of bones, each under its parent.
    var boneRows: [(bone: WallpaperEnginePuppetRig.Bone, depth: Int)] {
        guard let rig = selectedRig else { return [] }
        var rows: [(WallpaperEnginePuppetRig.Bone, Int)] = []
        func add(_ bone: WallpaperEnginePuppetRig.Bone, _ depth: Int) {
            rows.append((bone, depth))
            guard depth < 64 else { return }
            rig.bones.filter { $0.parent == bone.index && $0.index != bone.index }.forEach { add($0, depth + 1) }
        }
        rig.bones.filter { $0.parent == nil }.forEach { add($0, 0) }
        return rows
    }

    // MARK: - Animations of the bones

    func addRigAnimation() {
        var made = 0
        editRig { rig in
            let used = Set(rig.animations.map(\.id))
            var id = document.newID()
            while used.contains(id) { id += 1 }
            rig.animations.append(.init(id: id, name: String(format: NSLocalizedString("Animation %d", comment: "Name of a new animation"), rig.animations.count + 1)))
            made = rig.animations.count - 1
        }
        endGesture()
        setRigAnimation(made)
    }

    func setRigAnimation(_ index: Int) {
        rigAnimation = index
        poseDraft = [:]
        timelineSeconds = 0
        selectBone(selectedBone)
        showRig()
    }

    func removeRigAnimation() {
        let index = rigAnimation
        rigAnimation = 0
        editRig { $0.animations.remove(at: index) }
        endGesture()
        selectBone(selectedBone)
        showRig()
    }

    /// How a bone stands at the frame of the timeline.
    func pose(of bone: Int) -> WallpaperEnginePuppetRig.Key {
        if let draft = poseDraft[bone] { return draft }
        guard let rig = selectedRig, rig.animations.indices.contains(rigAnimation) else { return .init(frame: 0) }
        return rig.pose(of: bone, in: rig.animations[rigAnimation], at: rigFrame.rounded())
    }

    /// Stands a bone so at the frame of the timeline: as a key if keys are made by themselves or
    /// there is one, else for now, until the time moves or K makes it one.
    func setPose(_ key: WallpaperEnginePuppetRig.Key, of bone: Int) {
        guard let selection, let rig = selectedRig else { return }
        if rig.animations.isEmpty { addRigAnimation() }
        let target = WallpaperEngineAnimationTarget.bone(animation: rigAnimation, bone: bone)
        guard let animation = animation(target) else { return }
        let frame = rigFrame.rounded()
        if autoKey || animation.keyFrames.contains(frame) {
            poseDraft[bone] = nil
            var copy = document
            // A bone's first key also holds it at the start, so it does not jump there.
            if animation.keyFrames.isEmpty, frame != 0, var first = selectedRig {
                first.setKey(.init(frame: 0), bone: bone, animation: rigAnimation)
                copy.setRig(first, ofObject: selection)
                document = copy
            }
            _ = writeAnimated(selection, target, numbers: [key.angle * 180 / .pi, key.tiltX * 180 / .pi, key.tiltY * 180 / .pi, key.dx, key.dy])
        } else {
            poseDraft[bone] = key
            showRig()
        }
    }

    /// The numbers of K for a bone that stands for now.
    func draftNumbers(of target: WallpaperEngineAnimationTarget) -> [Double]? {
        guard case .bone(_, let bone) = target, let key = poseDraft[bone] else { return nil }
        return [key.angle * 180 / .pi, key.tiltX * 180 / .pi, key.tiltY * 180 / .pi, key.dx, key.dy]
    }
}

/// The mode the editor is in, at the head of the window.
struct EngineModeMenu: View {
    @ObservedObject var model: EngineEditorModel

    var body: some View {
        Menu {
            ForEach(EngineEditorModel.Mode.allCases, id: \.self) { mode in
                Button {
                    model.enter(mode)
                } label: {
                    Label(mode.title, systemImage: mode.symbol)
                }
                .disabled(!model.canEnter(mode))
            }
        } label: {
            Label(model.mode.title, systemImage: model.mode.symbol)
        }
        .labelStyle(.titleAndIcon)
        .fixedSize()
        .help("The mode of the editor. Tab goes in and out of it, Control-Tab into Pose Mode.")
    }
}

/// The bones of the picture, in place of the layers while they are what is worked on.
struct EngineBoneList: View {
    @ObservedObject var model: EngineEditorModel

    var body: some View {
        List(selection: Binding(get: { model.selectedBone }, set: { model.selectBone($0) })) {
            Section {
                ForEach(model.boneRows, id: \.bone.index) { row in
                    Label(model.boneTitle(row.bone), systemImage: row.bone.parent == nil ? "smallcircle.filled.circle" : "line.diagonal")
                        .lineLimit(1)
                        .padding(.leading, CGFloat(min(row.depth, 8)) * 12)
                        .tag(Optional(row.bone.index))
                }
                if model.boneRows.isEmpty {
                    Text("There are no bones yet. Add them in Rig Mode.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(verbatim: model.selection.map(model.name(of:)) ?? "")
            }
        }
        .listStyle(.sidebar)
    }
}

/// The side panel of the modes of a picture's rig.
struct EngineRigPanel: View {
    @ObservedObject var model: EngineEditorModel

    private var rig: WallpaperEnginePuppetRig? { model.selectedRig }

    var body: some View {
        Form {
            switch model.mode {
            case .mesh: meshSections
            case .rig: rigSections
            case .weights: weightSections
            default: poseSections
            }
            Section {
                Button("Remove Puppet Warp", role: .destructive) { model.removePuppet() }
                    .disabled(rig == nil)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var meshSections: some View {
        Section("Mesh") {
            NumberRow("Density", value: $model.meshDensity, in: 8...200)
            Button(rig?.triangles.isEmpty == false ? "Make Mesh Again" : "Make Mesh") {
                guard let selection = model.selection,
                      let picture = model.document.picture(ofObject: selection, projectFolder: model.projectFolder) else { return }
                model.selectedPoints = []
                model.editRig { $0.makeMesh(from: picture, spacing: model.meshDensity) }
                model.endGesture()
            }
            LabeledContent("Triangles") { Text("\((rig?.triangles.count ?? 0) / 3)") }
            LabeledContent("Corners") { Text("\(rig?.points.count ?? 0)") }
        }
        Section {
            Text("The mesh covers the parts of the picture that are not see-through. A finer one bends more smoothly. Drag corners to change it; X deletes those selected.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var rigSections: some View {
        if let bone = model.selectedBone, let rig, rig.bones.indices.contains(bone) {
            Section("Bone") {
                TextField("Name", text: Binding(get: { rig.bones[bone].name }, set: { name in model.editRig { $0.bones[bone].name = name } }))
                Picker("Hangs On", selection: Binding(get: { rig.bones[bone].parent }, set: { parent in
                    model.editRig { $0.bones[bone].parent = parent }
                    model.endGesture()
                })) {
                    Text("Nothing").tag(Int?.none)
                    ForEach(rig.bones.filter { !isBelow($0.index, bone, rig) }) { Text(verbatim: model.boneTitle($0)).tag(Optional($0.index)) }
                }
                Picker("Sways by Itself", selection: Binding(
                    get: { rig.bones[bone].sway?.kind },
                    set: { kind in
                        model.editRig { $0.bones[bone].sway = kind.map { WallpaperEnginePuppetRig.Sway(kind: $0) } }
                        model.endGesture()
                    }
                )) {
                    Text("No").tag(WallpaperEnginePuppetRig.Sway.Kind?.none)
                    Text("On a Spring").tag(Optional(WallpaperEnginePuppetRig.Sway.Kind.spring))
                    Text("Hanging").tag(Optional(WallpaperEnginePuppetRig.Sway.Kind.hanging))
                }
                if rig.bones[bone].sway != nil {
                    NumberRow("Stiffness", value: Binding(get: { rig.bones[bone].sway?.stiffness ?? 200 },
                                                          set: { value in model.editRig { $0.bones[bone].sway?.stiffness = value } }), in: 0...1000)
                    NumberRow("Friction", value: Binding(get: { rig.bones[bone].sway?.friction ?? 20 },
                                                         set: { value in model.editRig { $0.bones[bone].sway?.friction = value } }), in: 0...200)
                }
                Button("Delete Bone", role: .destructive) { model.deleteSelectedBone() }
            }
        }
        Section {
            Text("With the Add Bone tool, press where a bone starts and drag to where it ends; it hangs on the selected one. Each click after that goes on from the last.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// Whether a bone is the one given or hangs on it, at any depth.
    private func isBelow(_ index: Int, _ top: Int, _ rig: WallpaperEnginePuppetRig) -> Bool {
        var at: Int? = index
        var steps = 0
        while let current = at, steps < 64 {
            if current == top { return true }
            at = rig.bones[current].parent
            steps += 1
        }
        return false
    }

    @ViewBuilder
    private var weightSections: some View {
        Section("Brush") {
            Picker("Paint", selection: $model.weightAdds) {
                Text("Add").tag(true)
                Text("Subtract").tag(false)
            }
            .pickerStyle(.segmented)
            NumberRow("Size", value: $model.weightSize, in: 4...1000)
            NumberRow("Strength", value: $model.weightStrength, in: 1...100, suffix: "%")
            Button("Work Out Weights Again") {
                model.editRig { $0.holds = nil }
                model.endGesture()
            }
            .disabled(rig?.holds == nil)
        }
        Section {
            Text("Paint how much the selected bone holds the picture: red holds it fully, blue not at all. Shift paints the other way, Control and a click picks the bone under the pointer.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func poseRow(_ title: LocalizedStringKey, _ bone: Int, _ path: WritableKeyPath<WallpaperEnginePuppetRig.Key, Double>,
                         degrees: Bool, in range: ClosedRange<Double>) -> some View {
        NumberRow(title, value: Binding(
            get: { model.pose(of: bone)[keyPath: path] * (degrees ? 180 / .pi : 1) },
            set: { value in
                var key = model.pose(of: bone)
                key[keyPath: path] = value * (degrees ? .pi / 180 : 1)
                model.setPose(key, of: bone)
            }
        ), in: range, suffix: degrees ? "°" : "")
    }

    @ViewBuilder
    private var poseSections: some View {
        if let bone = model.selectedBone, let rig, rig.bones.indices.contains(bone) {
            Section {
                poseRow("Turn", bone, \.angle, degrees: true, in: -180...180)
                poseRow("Tilt X", bone, \.tiltX, degrees: true, in: -180...180)
                poseRow("Tilt Y", bone, \.tiltY, degrees: true, in: -180...180)
                poseRow("Move X", bone, \.dx, degrees: false, in: -rig.width / 2...rig.width / 2)
                poseRow("Move Y", bone, \.dy, degrees: false, in: -rig.height / 2...rig.height / 2)
            } header: {
                Text("Bone at This Frame")
            }
        }
        Section {
            Text("Drag a bone to turn it. With Auto Keyframe on, a key is made at the frame the timeline stands at; K makes one by hand.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

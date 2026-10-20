import AppKit
import SwiftUI
import WallpaperCore

/// Puppet warp, as Wallpaper Engine's editor has it: a mesh over the picture, bones that bend
/// it, and animations made of keys the bones are turned and moved to. The picture bends here as
/// it is changed; the scene shows it once the editor is done.
struct EnginePuppetEditor: View {
    @ObservedObject var model: EngineEditorModel
    let object: Int
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable {
        case mesh, bones, animate
        var title: LocalizedStringKey {
            switch self {
            case .mesh: return "Mesh"
            case .bones: return "Bones"
            case .animate: return "Animation"
            }
        }
    }

    @State private var rig = WallpaperEnginePuppetRig(width: 1, height: 1)
    @State private var picture: CGImage?
    @State private var mode: Mode = .mesh
    @State private var spacing: Double = 40
    @State private var selectedBone: Int?
    @State private var animation: Int = 0
    @State private var frame: Double = 0
    @State private var playing = false
    @State private var loaded = false
    @State private var dragging: Int?
    private let timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                canvas
                Divider()
                Form { sidePanel }
                    .formStyle(.grouped)
                    .frame(width: 300)
            }
            if mode == .animate {
                Divider()
                timeline
            }
            Divider()
            HStack {
                Button("Remove Puppet Warp", role: .destructive) { removePuppet() }
                    .disabled(model.document.object(object).flatMap { model.document.file($0["image"]?.plain.stringValue ?? "") }?["puppet"] == nil)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(rig.triangles.isEmpty)
            }
            .padding()
        }
        .frame(width: 1040, height: 720)
        .onAppear(perform: load)
        .onReceive(timer) { _ in
            guard playing, mode == .animate, rig.animations.indices.contains(animation) else { return }
            let length = Double(rig.animations[animation].length)
            frame = (frame + rig.animations[animation].framesPerSecond / 30).truncatingRemainder(dividingBy: length + 1)
        }
    }

    private var header: some View {
        HStack {
            Text("Puppet Warp").font(.headline)
            Spacer()
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)
            .disabled(rig.triangles.isEmpty)
            Spacer()
            Text(verbatim: model.name(of: object)).foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - The picture

    private var canvas: some View {
        GeometryReader { geometry in
            let scale = min((geometry.size.width - 40) / max(rig.width, 1), (geometry.size.height - 40) / max(rig.height, 1))
            let middle = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let toView = { (point: WallpaperEnginePuppetRig.Point) in CGPoint(x: middle.x + point.x * scale, y: middle.y - point.y * scale) }
            let toRig = { (point: CGPoint) in WallpaperEnginePuppetRig.Point(x: (point.x - middle.x) / scale, y: (middle.y - point.y) / scale) }
            let posed = rig.posedPoints(animation: mode == .animate ? animation : nil, frame: frame)
            Canvas { context, _ in
                context.withCGContext { cg in
                    drawPicture(cg, posed: posed, toView: toView)
                }
                if mode != .animate || selectedBone == nil {
                    var lines = Path()
                    for index in stride(from: 0, to: rig.triangles.count - 2, by: 3) {
                        let a = toView(posed[rig.triangles[index]]), b = toView(posed[rig.triangles[index + 1]]), c = toView(posed[rig.triangles[index + 2]])
                        lines.move(to: a)
                        lines.addLine(to: b)
                        lines.addLine(to: c)
                        lines.closeSubpath()
                    }
                    context.stroke(lines, with: .color(.white.opacity(mode == .mesh ? 0.45 : 0.15)), lineWidth: 0.5)
                }
                if mode != .mesh {
                    drawBones(context, toView: toView)
                }
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                drag(value, toRig: toRig, scale: scale)
            }.onEnded { _ in
                dragging = nil
            })
        }
    }

    /// The picture bent as the bones have it: each triangle of it where its corners are now.
    private func drawPicture(_ cg: CGContext, posed: [WallpaperEnginePuppetRig.Point], toView: (WallpaperEnginePuppetRig.Point) -> CGPoint) {
        guard let picture else { return }
        let width = Double(picture.width), height = Double(picture.height)
        // Where a corner is in the picture, in the view's way up.
        func source(_ point: WallpaperEnginePuppetRig.Point) -> CGPoint {
            CGPoint(x: (point.x + rig.width / 2) / rig.width * width, y: (rig.height / 2 - point.y) / rig.height * height)
        }
        cg.interpolationQuality = .medium
        for index in stride(from: 0, to: rig.triangles.count - 2, by: 3) {
            let corners = [rig.triangles[index], rig.triangles[index + 1], rig.triangles[index + 2]]
            let s = corners.map { source(rig.points[$0]) }
            let d = corners.map { toView(posed[$0]) }
            guard let transform = Self.affine(from: s, to: d) else { continue }
            cg.saveGState()
            let path = CGMutablePath()
            // A little larger, so that no seams show between triangles.
            let center = CGPoint(x: (d[0].x + d[1].x + d[2].x) / 3, y: (d[0].y + d[1].y + d[2].y) / 3)
            let grown = d.map { CGPoint(x: center.x + ($0.x - center.x) * 1.02, y: center.y + ($0.y - center.y) * 1.02) }
            path.addLines(between: grown)
            path.closeSubpath()
            cg.addPath(path)
            cg.clip()
            cg.concatenate(transform)
            // The picture is drawn with its top at the top.
            cg.translateBy(x: 0, y: height)
            cg.scaleBy(x: 1, y: -1)
            cg.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
            cg.restoreGState()
        }
    }

    /// The transform that takes three points to three others.
    static func affine(from s: [CGPoint], to d: [CGPoint]) -> CGAffineTransform? {
        let det = (s[1].x - s[0].x) * (s[2].y - s[0].y) - (s[2].x - s[0].x) * (s[1].y - s[0].y)
        guard abs(det) > 1e-9 else { return nil }
        let a = ((d[1].x - d[0].x) * (s[2].y - s[0].y) - (d[2].x - d[0].x) * (s[1].y - s[0].y)) / det
        let c = ((d[2].x - d[0].x) * (s[1].x - s[0].x) - (d[1].x - d[0].x) * (s[2].x - s[0].x)) / det
        let b = ((d[1].y - d[0].y) * (s[2].y - s[0].y) - (d[2].y - d[0].y) * (s[1].y - s[0].y)) / det
        let dd = ((d[2].y - d[0].y) * (s[1].x - s[0].x) - (d[1].y - d[0].y) * (s[2].x - s[0].x)) / det
        let tx = d[0].x - a * s[0].x - c * s[0].y
        let ty = d[0].y - b * s[0].x - dd * s[0].y
        return CGAffineTransform(a: a, b: b, c: c, d: dd, tx: tx, ty: ty)
    }

    private func drawBones(_ context: GraphicsContext, toView: (WallpaperEnginePuppetRig.Point) -> CGPoint) {
        let world = posedJoints()
        for bone in rig.bones {
            let at = toView(world[bone.index])
            if let parent = bone.parent {
                var line = Path()
                line.move(to: toView(world[parent]))
                line.addLine(to: at)
                context.stroke(line, with: .color(.accentColor), lineWidth: 3)
            }
            let size: CGFloat = bone.index == selectedBone ? 14 : 10
            let dot = Path(ellipseIn: CGRect(x: at.x - size / 2, y: at.y - size / 2, width: size, height: size))
            context.fill(dot, with: .color(bone.index == selectedBone ? .accentColor : .white))
            context.stroke(dot, with: .color(.black.opacity(0.6)), lineWidth: 1)
        }
    }

    /// Where each bone's joint is now.
    private func posedJoints() -> [WallpaperEnginePuppetRig.Point] {
        let transforms = rig.posedTransforms(animation: mode == .animate ? animation : nil, frame: frame)
        return transforms.map { WallpaperEnginePuppetRig.Point(x: $0.tx, y: $0.ty) }
    }

    private func drag(_ value: DragGesture.Value, toRig: (CGPoint) -> WallpaperEnginePuppetRig.Point, scale: Double) {
        let point = toRig(value.location)
        let joints = mode == .animate ? posedJoints() : rig.bones.map(\.joint)
        let nearest = joints.enumerated().min { hypot($0.element.x - point.x, $0.element.y - point.y) < hypot($1.element.x - point.x, $1.element.y - point.y) }
        let reach = 10 / max(scale, 0.0001)
        switch mode {
        case .mesh:
            break
        case .bones:
            if dragging == nil {
                if let nearest, hypot(nearest.element.x - point.x, nearest.element.y - point.y) < reach {
                    selectedBone = nearest.offset
                    dragging = nearest.offset
                } else if value.translation == .zero {
                    selectedBone = rig.addBone(at: point, parent: selectedBone)
                    dragging = selectedBone
                }
            } else if let dragging {
                rig.bones[dragging].joint = point
            }
        case .animate:
            if dragging == nil {
                if let nearest, hypot(nearest.element.x - point.x, nearest.element.y - point.y) < reach {
                    selectedBone = nearest.offset
                }
                dragging = selectedBone ?? -1
            } else if let bone = selectedBone, rig.bones.indices.contains(bone), let parent = rig.bones[bone].parent {
                // A bone is turned about its parent's joint, toward the pointer.
                let pivot = joints[parent]
                let start = toRig(value.startLocation)
                let from = atan2(start.y - pivot.y, start.x - pivot.x), to = atan2(point.y - pivot.y, point.x - pivot.x)
                var key = currentKey(of: parent)
                if dragStartAngle == nil { dragStartAngle = key.angle }
                key.angle = (dragStartAngle ?? 0) + (to - from)
                setKey(key, bone: parent)
            }
        }
        if value.translation == .zero { dragStartAngle = nil }
    }

    @State private var dragStartAngle: Double?

    // MARK: - The side

    @ViewBuilder
    private var sidePanel: some View {
        switch mode {
        case .mesh:
            Section {
                NumberRow("Density", value: $spacing, in: 8...200)
                Button(rig.triangles.isEmpty ? "Make Mesh" : "Make Mesh Again") { makeMesh() }
                LabeledContent("Triangles") { Text("\(rig.triangles.count / 3)") }
            } footer: {
                Text("The mesh covers the parts of the picture that are not see-through. A finer one bends more smoothly.")
            }
        case .bones:
            Section {
                Text("Click on the picture to add a bone; it hangs on the selected one. Drag a joint to move it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let bone = selectedBone, rig.bones.indices.contains(bone) {
                    TextField("Name", text: $rig.bones[bone].name)
                    Picker("Sways by Itself", selection: Binding(
                        get: { rig.bones[bone].sway?.kind },
                        set: { kind in rig.bones[bone].sway = kind.map { WallpaperEnginePuppetRig.Sway(kind: $0) } }
                    )) {
                        Text("No").tag(WallpaperEnginePuppetRig.Sway.Kind?.none)
                        Text("On a Spring").tag(Optional(WallpaperEnginePuppetRig.Sway.Kind.spring))
                        Text("Hanging").tag(Optional(WallpaperEnginePuppetRig.Sway.Kind.hanging))
                    }
                    if rig.bones[bone].sway != nil {
                        NumberRow("Stiffness", value: Binding(get: { rig.bones[bone].sway?.stiffness ?? 200 },
                                                              set: { rig.bones[bone].sway?.stiffness = $0 }), in: 0...1000)
                        NumberRow("Friction", value: Binding(get: { rig.bones[bone].sway?.friction ?? 20 },
                                                             set: { rig.bones[bone].sway?.friction = $0 }), in: 0...200)
                    }
                    Button("Delete Bone", role: .destructive) {
                        rig.removeBone(bone)
                        selectedBone = nil
                    }
                }
                Button("Deselect") { selectedBone = nil }
                    .disabled(selectedBone == nil)
            } header: {
                Text("Bones (\(rig.bones.count))")
            }
        case .animate:
            Section("Animation") {
                if rig.animations.isEmpty {
                    Button("Add Animation") { addAnimation() }
                } else {
                    Picker("Animation", selection: $animation) {
                        ForEach(rig.animations.indices, id: \.self) { Text(verbatim: rig.animations[$0].name).tag($0) }
                    }
                    TextField("Name", text: $rig.animations[animation].name)
                    NumberRow("Length", value: Binding(
                        get: { Double(rig.animations[animation].length) / rig.animations[animation].framesPerSecond },
                        set: { rig.animations[animation].length = max(1, Int(($0 * rig.animations[animation].framesPerSecond).rounded())) }
                    ), in: 0.5...30, step: 0.1, suffix: "s")
                    Picker("Plays", selection: $rig.animations[animation].mode) {
                        Text("Over and Over").tag("loop")
                        Text("There and Back").tag("mirror")
                        Text("Once").tag("single")
                    }
                    Button("Add Animation") { addAnimation() }
                }
            }
            if let bone = selectedBone, rig.bones.indices.contains(bone), !rig.animations.isEmpty {
                Section("Bone at This Frame") {
                    NumberRow("Turn", value: Binding(
                        get: { currentKey(of: bone).angle * 180 / .pi },
                        set: { var key = currentKey(of: bone); key.angle = $0 * .pi / 180; setKey(key, bone: bone) }
                    ), in: -180...180, suffix: "°")
                    NumberRow("Tilt X", value: Binding(
                        get: { currentKey(of: bone).tiltX * 180 / .pi },
                        set: { var key = currentKey(of: bone); key.tiltX = $0 * .pi / 180; setKey(key, bone: bone) }
                    ), in: -180...180, suffix: "°")
                    NumberRow("Tilt Y", value: Binding(
                        get: { currentKey(of: bone).tiltY * 180 / .pi },
                        set: { var key = currentKey(of: bone); key.tiltY = $0 * .pi / 180; setKey(key, bone: bone) }
                    ), in: -180...180, suffix: "°")
                    NumberRow("Move X", value: Binding(
                        get: { currentKey(of: bone).dx },
                        set: { var key = currentKey(of: bone); key.dx = $0; setKey(key, bone: bone) }
                    ), in: -rig.width / 2...rig.width / 2)
                    NumberRow("Move Y", value: Binding(
                        get: { currentKey(of: bone).dy },
                        set: { var key = currentKey(of: bone); key.dy = $0; setKey(key, bone: bone) }
                    ), in: -rig.height / 2...rig.height / 2)
                    Button("Remove Key") {
                        rig.animations[animation].keys[bone]?.removeAll { $0.frame == Int(frame.rounded()) }
                    }
                }
            } else {
                Section {
                    Text("Select a joint, then drag the bones below it — or set the turn here. A key is made at the frame you are on.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - The timeline

    private var timeline: some View {
        HStack(spacing: 12) {
            Button {
                playing.toggle()
            } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
            }
            .disabled(rig.animations.isEmpty)
            if rig.animations.indices.contains(animation) {
                let length = Double(rig.animations[animation].length)
                ZStack(alignment: .leading) {
                    Slider(value: $frame, in: 0...max(length, 1), step: 1)
                    GeometryReader { geometry in
                        let frames = Set((selectedBone.map { rig.animations[animation].keys[$0] ?? [] }
                                          ?? rig.animations[animation].keys.values.flatMap { $0 }).map(\.frame))
                        ForEach(Array(frames), id: \.self) { key in
                            Image(systemName: "diamond.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.accentColor)
                                .position(x: 10 + (geometry.size.width - 20) * Double(key) / max(length, 1), y: -6)
                        }
                    }
                    .allowsHitTesting(false)
                }
                Text(String(format: "%.2f s", frame / rig.animations[animation].framesPerSecond))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: - Changes

    private func load() {
        guard !loaded else { return }
        loaded = true
        picture = model.document.picture(ofObject: object, projectFolder: model.projectFolder)
        let size = model.value(object, "size")?.vector ?? [Double(picture?.width ?? 100), Double(picture?.height ?? 100)]
        let width = size.first ?? 100, height = size.count > 1 ? size[1] : 100
        if let existing = model.document.puppetRig(ofObject: object, projectFolder: model.projectFolder, width: width, height: height) {
            rig = existing
            mode = .bones
        } else {
            rig = WallpaperEnginePuppetRig(width: width, height: height)
            spacing = max(16, (max(width, height) / 30).rounded())
            makeMesh()
        }
    }

    private func makeMesh() {
        guard let picture else { return }
        rig.makeMesh(from: picture, spacing: spacing)
    }

    private func addAnimation() {
        let used = Set(rig.animations.map(\.id))
        var id = model.document.newID()
        while used.contains(id) { id += 1 }
        rig.animations.append(WallpaperEnginePuppetRig.Animation(
            id: id, name: String(format: NSLocalizedString("Animation %d", comment: "Name of a new animation"), rig.animations.count + 1)))
        animation = rig.animations.count - 1
        frame = 0
    }

    private func currentKey(of bone: Int) -> WallpaperEnginePuppetRig.Key {
        guard rig.animations.indices.contains(animation) else { return .init(frame: 0) }
        var key = rig.pose(of: bone, in: rig.animations[animation], at: frame.rounded())
        key.frame = Int(frame.rounded())
        return key
    }

    private func setKey(_ key: WallpaperEnginePuppetRig.Key, bone: Int) {
        guard rig.animations.indices.contains(animation) else { return }
        var key = key
        key.frame = Int(frame.rounded())
        // A bone's first key also holds it at the start, so it does not jump there.
        if rig.animations[animation].keys[bone]?.isEmpty ?? true, key.frame != 0 {
            rig.setKey(.init(frame: 0), bone: bone, animation: animation)
        }
        rig.setKey(key, bone: bone, animation: animation)
    }

    private func save() {
        do {
            try model.change { try $0.setPuppet(rig, ofObject: object, projectFolder: model.projectFolder) }
            model.markNewFiles()
            dismiss()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func removePuppet() {
        model.change { document in
            guard let modelName = document.object(object)?["image"]?.plain.stringValue, var value = document.file(modelName) else { return }
            value["puppet"] = nil
            document.setFile(modelName, value)
            document.update(object) { $0["animationlayers"] = nil }
        }
        model.markNewFiles()
        dismiss()
    }
}

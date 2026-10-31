import AppKit
import SwiftUI
import WallpaperCore

/// The right-hand side of the editor: the properties of the selected object, or of the scene
/// when none is selected, by topic: a scene can have hundreds of effects, and its properties in
/// one column would have to be looked through every time.
struct EngineInspector: View {
    @ObservedObject var model: EngineEditorModel

    var body: some View {
        VStack(spacing: 0) {
            if let id = model.selection, model.document.object(id) != nil {
                EngineObjectTabs(model: model, id: id)
            } else {
                tabs(selection: $model.sceneTab) {
                    Text("Scene").tag(EngineEditorModel.SceneTab.scene)
                    Text("View").tag(EngineEditorModel.SceneTab.view)
                    Text("Environment").tag(EngineEditorModel.SceneTab.environment)
                    Text("Settings").tag(EngineEditorModel.SceneTab.settings)
                }
                Form {
                    EngineSceneProperties(model: model)
                }
                .formStyle(.grouped)
            }
        }
    }
}

/// The row of topics at the top of the properties.
@ViewBuilder
private func tabs<Tab: Hashable, Content: View>(selection: Binding<Tab>, @ViewBuilder content: () -> Content) -> some View {
    Picker("", selection: selection, content: content)
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 2)
}

/// The topics an object has. One takes the name of the object's kind, as what it holds does.
private struct EngineObjectTabs: View {
    @ObservedObject var model: EngineEditorModel
    let id: Int

    private var kind: WallpaperEngineDocument.ObjectKind { model.kind(of: id) }
    private var hasKindTab: Bool { ![.model, .group, .fullscreen].contains(kind) }
    private var hasEffects: Bool { [.image, .text, .solid, .composition, .fullscreen].contains(kind) }

    /// The topic left open, unless this object has no such thing.
    private var tab: Binding<EngineEditorModel.ObjectTab> {
        Binding(
            get: {
                switch model.objectTab {
                case .kind where !hasKindTab, .effects where !hasEffects: return .object
                default: return model.objectTab
                }
            },
            set: { model.objectTab = $0 }
        )
    }

    var body: some View {
        tabs(selection: tab) {
            Text("Object").tag(EngineEditorModel.ObjectTab.object)
            if hasKindTab {
                Text(verbatim: EngineEditorModel.kindTitle(kind)).tag(EngineEditorModel.ObjectTab.kind)
            }
            if hasEffects {
                Text("Effects").tag(EngineEditorModel.ObjectTab.effects)
            }
        }
        Form {
            EngineObjectProperties(model: model, id: id, tab: tab.wrappedValue)
        }
        .formStyle(.grouped)
    }
}

// MARK: - An object

private struct EngineObjectProperties: View {
    @ObservedObject var model: EngineEditorModel
    let id: Int
    let tab: EngineEditorModel.ObjectTab

    private var kind: WallpaperEngineDocument.ObjectKind { model.kind(of: id) }

    var body: some View {
        switch tab {
        case .object: objectTab
        case .kind: kindSection
        case .effects: EngineEffectsSection(model: model, id: id)
        }
    }

    @ViewBuilder
    private var objectTab: some View {
        Section {
            TextField("Name", text: model.text(id, "name"))
            LabeledContent("Kind") { Text(EngineEditorModel.kindTitle(kind)) }
            Toggle("Visible", isOn: model.flag(id, "visible", default: true))
                .disabled(model.isScripted(id, "visible"))
            if ![.sound, .light, .camera].contains(kind) {
                Toggle("Show on Lock Screen", isOn: model.showsOnLockScreen(id))
            }
        }
        if kind != .sound {
            Section("Position") {
                let size = model.document.size
                // What hangs on another, and a camera, are placed from a middle.
                let hangs = model.document.parent(of: id) != nil || kind == .camera
                NumberRow("X", value: model.part(id, "origin", 0, default: [0, 0, 0]),
                          in: hangs ? -size.width...size.width : -size.width / 2...size.width * 1.5)
                    .disabled(model.isScripted(id, "origin"))
                NumberRow("Y", value: model.part(id, "origin", 1, default: [0, 0, 0]),
                          in: hangs ? -size.height...size.height : -size.height / 2...size.height * 1.5)
                    .disabled(model.isScripted(id, "origin"))
                NumberRow("Scale", value: model.uniformScale(id), in: 1...400, suffix: "%")
                    .disabled(model.isScripted(id, "scale"))
                NumberRow("Rotation", value: model.rotation(id), in: -180...180, suffix: "°")
                    .disabled(model.isScripted(id, "angles"))
                NumberRow("Parallax Depth", value: model.part(id, "parallaxDepth", 0, default: [1, 1]), in: 0...4, step: 0.01)
            }
        }
        if [.image, .text, .solid, .composition, .fullscreen].contains(kind) {
            Section("Appearance") {
                NumberRow("Opacity", value: model.part(id, "alpha", 0, default: [1], scale: 100), in: 0...100, suffix: "%")
                    .disabled(model.isScripted(id, "alpha"))
                ColorRow("Color", hex: model.color(id, "color"))
                    .disabled(model.isScripted(id, "color"))
                if kind != .text {
                    Picker("Blend Mode", selection: model.number(id, "colorBlendMode", default: 0)) {
                        ForEach(Self.blendModes, id: \.value) { mode in
                            Text(mode.title).tag(mode.value)
                        }
                    }
                }
            }
        }
        EngineObjectLinks(model: model, id: id)
        Section {
            HStack {
                Button("Duplicate") { model.duplicate(id) }
                Spacer()
                Button("Delete", role: .destructive) { model.delete(id) }
            }
        }
    }

    @ViewBuilder
    private var kindSection: some View {
        switch kind {
        case .image:
            Section("Image") {
                LabeledContent("Size") {
                    let size = model.value(id, "size")?.vector ?? [0, 0]
                    Text(verbatim: "\(Int(size.first ?? 0)) × \(Int(size.count > 1 ? size[1] : 0))")
                        .foregroundStyle(.secondary)
                }
                Button("Replace Picture…") { model.replacePicture(of: id) }
                Button("Puppet Warp…") { model.puppetObject = id }
            }
            if model.document.material(ofObject: id) != nil {
                lightingSection
            }
        case .solid:
            Section("Size") {
                let scene = model.document.size
                NumberRow("Width", value: model.part(id, "size", 0, default: [100, 100]), in: 1...max(scene.width * 2, 100))
                NumberRow("Height", value: model.part(id, "size", 1, default: [100, 100]), in: 1...max(scene.height * 2, 100))
            }
        case .text:
            Section("Text") {
                if model.isScripted(id, "text") {
                    LabeledContent("Text") {
                        Text("Set by a Script").foregroundStyle(.secondary)
                    }
                } else {
                    TextEditor(text: model.textValue(id))
                        .font(.body)
                        .frame(height: 64)
                        .scrollContentBackground(.hidden)
                }
                Picker("Font", selection: model.text(id, "font", default: "systemfont_arial")) {
                    ForEach(fonts, id: \.self) { font in
                        Text(verbatim: Self.fontTitle(font)).tag(font)
                    }
                }
                Button("Add Font…") { model.importFont(for: id) }
                NumberRow("Size", value: model.number(id, "pointsize", default: 32), in: 4...400)
                    .disabled(model.isScripted(id, "pointsize"))
                Picker("Alignment", selection: model.text(id, "horizontalalign", default: "center")) {
                    Text("Left").tag("left")
                    Text("Center").tag("center")
                    Text("Right").tag("right")
                }
                Picker("Vertical Alignment", selection: model.text(id, "verticalalign", default: "center")) {
                    Text("Top").tag("top")
                    Text("Center").tag("center")
                    Text("Bottom").tag("bottom")
                }
                NumberRow("Padding", value: model.part(id, "padding", 0, default: [32, 32]), in: 0...200)
                NumberRow("Letter Spacing", value: model.part(id, "spacing", 0, default: [0, 0]), in: -50...100, step: 0.1)
                NumberRow("Line Spacing", value: model.part(id, "spacing", 1, default: [0, 0]), in: -100...200, step: 0.1)
                Toggle("Background", isOn: model.flag(id, "opaquebackground", default: false))
                if model.value(id, "opaquebackground")?.boolValue == true {
                    ColorRow("Background Color", hex: model.color(id, "backgroundcolor", default: [0, 0, 0]))
                }
            }
            Section("Text Box") {
                Toggle("Limit Width", isOn: model.flag(id, "limitwidth", default: false))
                if model.value(id, "limitwidth")?.boolValue == true {
                    NumberRow("Width", value: model.number(id, "maxwidth", default: 500), in: 10...4000)
                }
                Toggle("Limit Lines", isOn: model.flag(id, "limitrows", default: false))
                if model.value(id, "limitrows")?.boolValue == true {
                    NumberRow("Lines", value: model.number(id, "maxrows", default: 1), in: 1...50)
                }
                Toggle("Ellipsis Where Cut", isOn: model.flag(id, "limituseellipsis", default: false))
                Picker("Keep to Screen Edge", selection: model.text(id, "anchor", default: "none")) {
                    Text("No").tag("none")
                    Text("Center").tag("center")
                    Text("Left").tag("left")
                    Text("Right").tag("right")
                    Text("Top").tag("top")
                    Text("Bottom").tag("bottom")
                    Text("Top Left").tag("topleft")
                    Text("Top Right").tag("topright")
                    Text("Bottom Left").tag("bottomleft")
                    Text("Bottom Right").tag("bottomright")
                }
            }
            Section("Outline and Shadow") {
                Toggle("Outline", isOn: model.flag(id, "outline", default: false))
                if model.value(id, "outline")?.boolValue == true {
                    ColorRow("Outline Color", hex: model.color(id, "outlinecolor", default: [0, 0, 0]))
                    NumberRow("Outline Thickness", value: model.number(id, "outlinethickness", default: 1), in: 0...30, step: 0.1)
                }
                Toggle("Shadow", isOn: model.flag(id, "dropshadow", default: false))
                if model.value(id, "dropshadow")?.boolValue == true {
                    ColorRow("Shadow Color", hex: model.color(id, "dropshadowcolor", default: [0, 0, 0]))
                    NumberRow("Shadow X", value: model.part(id, "dropshadowoffset", 0, default: [4, 4]), in: -100...100)
                    NumberRow("Shadow Y", value: model.part(id, "dropshadowoffset", 1, default: [4, 4]), in: -100...100)
                    NumberRow("Shadow Softness", value: model.number(id, "dropshadowsize", default: 4), in: 0...50, step: 0.1)
                    NumberRow("Shadow Opacity", value: model.number(id, "dropshadowopacity", default: 1), in: 0...3, step: 0.01)
                }
                Toggle("Blur", isOn: model.flag(id, "blur", default: false))
                if model.value(id, "blur")?.boolValue == true {
                    NumberRow("Blur Amount", value: model.number(id, "blursize", default: 2), in: 0...50, step: 0.1)
                }
            }
        case .particles:
            Section("Particles") {
                NumberRow("Amount", value: model.override(id, "count"), in: 0...500, suffix: "%")
                NumberRow("Rate", value: model.override(id, "rate"), in: 0...500, suffix: "%")
                NumberRow("Speed", value: model.override(id, "speed"), in: 0...500, suffix: "%")
                NumberRow("Size", value: model.override(id, "size"), in: 0...500, suffix: "%")
                NumberRow("Lifetime", value: model.override(id, "lifetime"), in: 0...500, suffix: "%")
                NumberRow("Opacity", value: model.override(id, "alpha"), in: 0...100, suffix: "%")
                let color = model.particleColor(id)
                Toggle("Recolor", isOn: Binding(get: { color.wrappedValue != nil }, set: { color.wrappedValue = $0 ? "#FFFFFF" : nil }))
                if let hex = color.wrappedValue {
                    ColorRow("Color", hex: Binding(get: { hex }, set: { color.wrappedValue = $0 }))
                }
            }
            EngineParticleSystemSections(model: model, object: id)
        case .sound:
            Section("Sound") {
                NumberRow("Volume", value: model.part(id, "volume", 0, default: [1], scale: 100), in: 0...100, suffix: "%")
                Picker("Playback", selection: model.text(id, "playbackmode", default: "loop")) {
                    Text("Repeat").tag("loop")
                    Text("Random Order").tag("random")
                    Text("Once").tag("single")
                }
            }
        case .composition:
            Section("Composition Layer") {
                Toggle("Show What Is Under It", isOn: Binding(
                    get: { model.document.object(id)?["config"]?["passthrough"]?.boolValue ?? false },
                    set: { value in model.document.update(id) { $0["config"] = .object(["passthrough": .bool(value)]) } }
                ))
            }
        case .light:
            Section("Light Source") {
                Picker("Kind", selection: Binding(
                    get: { model.value(id, "light")?.stringValue ?? "lpoint" },
                    set: { kind in model.change { document in
                        document.update(id) { $0["light"] = .string(kind) }
                        document.countLights()
                    } }
                )) {
                    ForEach(WallpaperEngineDocument.LightKind.allCases, id: \.self) { kind in
                        Text(EngineEditorModel.lightTitle(kind)).tag(kind.rawValue)
                    }
                }
                ColorRow("Color", hex: model.color(id, "color"))
                    .disabled(model.isScripted(id, "color"))
                NumberRow("Brightness", value: model.number(id, "intensity", default: 1), in: 0...20, step: 0.01)
                NumberRow("Reach", value: model.number(id, "radius", default: 500), in: 0...max(model.document.size.width * 2, 1000))
                NumberRow("Falloff", value: model.number(id, "exponent", default: 1), in: 0.01...10, step: 0.01)
                NumberRow("Height", value: model.part(id, "origin", 2, default: [0, 0, 200]), in: -500...2000)
            }
        case .camera:
            Section {
                NumberRow("Zoom Level", value: model.number(id, "zoom", default: 1), in: 0.1...10, step: 0.01)
                    .disabled(model.isScripted(id, "zoom"))
                NumberRow("Field of View", value: model.number(id, "fov", default: 50), in: 10...120, suffix: "°")
            } header: {
                Text("Camera")
            } footer: {
                Text("X and Y move the view from the middle of the scene. Of the cameras that show, the scene is seen through the topmost in the list of layers; hide a camera to use another.")
            }
        case .model, .group, .fullscreen:
            EmptyView()
        }
    }

    /// How a picture takes the scene's lights, and reflects what is behind it.
    @ViewBuilder
    private var lightingSection: some View {
        let lighting = model.materialCombo(id, "LIGHTING")
        let reflection = model.materialCombo(id, "REFLECTION")
        let normalMap = model.materialTexture(id, slot: 1)
        Section {
            Toggle("Lighting", isOn: lighting)
            Toggle("Reflection", isOn: reflection)
            if lighting.wrappedValue || reflection.wrappedValue {
                LabeledContent("Normal Map") {
                    Text(verbatim: normalMap.map { ($0 as NSString).lastPathComponent } ?? NSLocalizedString("None", comment: "No normal map"))
                        .foregroundStyle(.secondary)
                }
                Button("Choose Normal Map…") { model.chooseNormalMap(of: id) }
                if normalMap != nil {
                    Button("Remove Normal Map", role: .destructive) { model.setMaterialTexture(id, slot: 1, to: nil) }
                }
                if reflection.wrappedValue && normalMap == nil {
                    Text("A picture reflects only with a normal map.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                NumberRow("Metalness", value: model.materialValue(id, "metallic", default: 0.5), in: 0...1, step: 0.01)
                NumberRow("Surface Roughness", value: model.materialValue(id, "roughness", default: 0.5), in: 0...1, step: 0.01)
                if reflection.wrappedValue {
                    NumberRow("Reflectivity", value: model.materialValue(id, "reflectivity", default: 1), in: 0...1, step: 0.01)
                }
            }
        } header: {
            Text("Lighting and Reflections")
        } footer: {
            if lighting.wrappedValue && !model.document.objects.contains(where: { $0["light"] != nil }) {
                Text("The scene has no lights yet: add one with Add → Light Source.")
            }
        }
    }

    /// The fonts a text may be written in: the system's that Wallpaper Engine knows on every
    /// computer, and the project's own.
    private var fonts: [String] {
        var list = Self.systemFonts
        let folder = model.projectFolder.appendingPathComponent("fonts")
        let own = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { ["ttf", "otf"].contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
            .map { "fonts/\($0)" }
        list += own
        if let current = model.value(id, "font")?.stringValue, !list.contains(current) {
            list.append(current)
        }
        return list
    }

    static let systemFonts = ["systemfont_arial", "systemfont_segoeui", "systemfont_timesnewroman", "systemfont_couriernew",
                              "systemfont_consolas", "systemfont_georgia", "systemfont_verdana", "systemfont_tahoma",
                              "systemfont_trebuchetms", "systemfont_impact", "systemfont_comicsansms"]

    static func fontTitle(_ font: String) -> String {
        let names = ["systemfont_arial": "Arial", "systemfont_segoeui": "Segoe UI", "systemfont_timesnewroman": "Times New Roman",
                     "systemfont_couriernew": "Courier New", "systemfont_consolas": "Consolas", "systemfont_georgia": "Georgia",
                     "systemfont_verdana": "Verdana", "systemfont_tahoma": "Tahoma", "systemfont_trebuchetms": "Trebuchet MS",
                     "systemfont_impact": "Impact", "systemfont_comicsansms": "Comic Sans MS"]
        return names[font] ?? ((font as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// The blend modes of a picture, by the numbers Wallpaper Engine gives them.
    static let blendModes: [(title: String, value: Double)] = [
        (NSLocalizedString("Normal", comment: "Blend mode"), 0),
        (NSLocalizedString("Darken", comment: "Blend mode"), 1),
        (NSLocalizedString("Multiply", comment: "Blend mode"), 2),
        (NSLocalizedString("Color Burn", comment: "Blend mode"), 3),
        (NSLocalizedString("Linear Burn", comment: "Blend mode"), 4),
        (NSLocalizedString("Lighten", comment: "Blend mode"), 6),
        (NSLocalizedString("Screen", comment: "Blend mode"), 7),
        (NSLocalizedString("Color Dodge", comment: "Blend mode"), 8),
        (NSLocalizedString("Add", comment: "Blend mode"), 9),
        (NSLocalizedString("Overlay", comment: "Blend mode"), 11),
        (NSLocalizedString("Soft Light", comment: "Blend mode"), 12),
        (NSLocalizedString("Hard Light", comment: "Blend mode"), 13),
        (NSLocalizedString("Difference", comment: "Blend mode"), 18),
        (NSLocalizedString("Exclusion", comment: "Blend mode"), 19),
        (NSLocalizedString("Subtract", comment: "Blend mode"), 20),
    ]
}

// MARK: - Effects

/// The effects of an object, in the order they are applied, each with its values. They are
/// folded, so that the order can be seen, and the button that adds one stays at the top.
private struct EngineEffectsSection: View {
    @ObservedObject var model: EngineEditorModel
    let id: Int
    @State private var open: Set<Int> = []

    var body: some View {
        let effects = model.document.object(id)?["effects"]?.arrayValue ?? []
        Section {
            Button {
                model.sheet = .effects(object: id)
            } label: {
                Label("Add Effect…", systemImage: "plus")
            }
            ForEach(Array(effects.indices), id: \.self) { index in
                let described = model.description?.object(id)?.effects.first { $0.id == index }
                FoldingRows(isOpen: $open.contains(index)) {
                    Toggle("", isOn: model.effectVisible(id, effect: index))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                    Text(verbatim: title(of: effects[index], described: described))
                    Spacer()
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .help("Drag to change the order")
                        .draggable(String(index))
                    Menu {
                        Button("Move Up") { model.change { $0.moveEffect(from: index, to: index - 1, of: id) } }
                            .disabled(index == 0)
                        Button("Move Down") { model.change { $0.moveEffect(from: index, to: index + 1, of: id) } }
                            .disabled(index == effects.count - 1)
                        Divider()
                        Button("Remove", role: .destructive) { model.change { $0.removeEffect(at: index, of: id) } }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                } content: {
                    if let described {
                        ForEach(described.switches ?? []) { item in
                            EngineEffectSwitchRow(model: model, object: id, effect: index, item: item)
                        }
                        ForEach(described.values) { value in
                            EngineEffectValueRows(value: value, numbers: model.effectValue(id, effect: index, value))
                        }
                        ForEach(model.paintableMasks(of: described, object: id)) { mask in
                            EngineMaskRow(model: model, target: .init(object: id, effect: index, mask: mask))
                        }
                    } else {
                        Text("Its values show once the scene plays it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .dropDestination(for: String.self) { dropped, _ in
                    guard let source = dropped.first.flatMap(Int.init), source != index else { return false }
                    model.change { $0.moveEffect(from: source, to: index, of: id) }
                    open = []
                    return true
                }
            }
        } header: {
            HStack {
                Text("Effects")
                Spacer()
                if !effects.isEmpty {
                    Button(open.isEmpty ? "Expand All" : "Collapse All") {
                        open = open.isEmpty ? Set(effects.indices) : []
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                }
            }
        }
        .onChange(of: id) { _ in open = [] }
    }

    private func title(of effect: JSONValue, described: EngineSceneDescription.Effect?) -> String {
        let file = effect["file"]?.stringValue ?? ""
        if let own = WallpaperEngineEffect.all.first(where: { $0.file == file }) {
            return own.title
        }
        if let described { return described.title }
        let folder = (file as NSString).deletingLastPathComponent
        return (folder as NSString).lastPathComponent
    }
}

/// A switch of an effect: its shader is made anew with it, so that the scene starts over.
private struct EngineEffectSwitchRow: View {
    @ObservedObject var model: EngineEditorModel
    let object: Int
    let effect: Int
    let item: EngineSceneDescription.Switch

    private var value: Binding<Double> {
        Binding(get: { item.value }, set: { model.setEffectSwitch(item, to: $0, object: object, effect: effect) })
    }

    var body: some View {
        if item.kind == "options", item.options.isEmpty {
            Toggle(isOn: Binding(get: { item.value != 0 }, set: { value.wrappedValue = $0 ? 1 : 0 })) {
                Text(verbatim: item.title)
            }
        } else {
            Picker(selection: value) {
                ForEach(choices, id: \.value) { choice in
                    Text(verbatim: choice.title).tag(choice.value)
                }
            } label: {
                Text(verbatim: item.title)
            }
        }
    }

    private var choices: [(title: String, value: Double)] {
        var list: [(title: String, value: Double)]
        switch item.kind {
        case "imageblending":
            list = EngineObjectProperties.blendModes
        case "audioprocessingoptions":
            list = [(NSLocalizedString("Off", comment: "A sound channel an effect follows"), 0),
                    (NSLocalizedString("Left Channel", comment: "A sound channel an effect follows"), 1),
                    (NSLocalizedString("Right Channel", comment: "A sound channel an effect follows"), 2),
                    (NSLocalizedString("Both Channels", comment: "A sound channel an effect follows"), 3)]
        default:
            list = item.options.map { ($0.title, $0.value) }
        }
        // A mode the list does not name is shown by its number, not lost.
        if !list.contains(where: { $0.value == item.value }) { list.append((String(format: "%g", item.value), item.value)) }
        return list
    }
}

/// A value of an effect: a color, a number, or a number for each of its axes.
struct EngineEffectValueRows: View {
    let value: EngineSceneDescription.Value
    @Binding var numbers: [Double]

    private static let axes = ["X", "Y", "Z", "W"]

    var body: some View {
        if value.isColor {
            ColorRow(title: Text(verbatim: value.title), hex: color)
        } else if value.count == 1 {
            NumberRow(title: Text(verbatim: value.title), value: part(0), in: range, step: step, suffix: value.inDegrees ? "°" : "")
        } else {
            ForEach(0..<min(value.count, Self.axes.count), id: \.self) { index in
                NumberRow(title: Text(verbatim: "\(value.title) \(Self.axes[index])"), value: part(index), in: range, step: step,
                          suffix: value.inDegrees ? "°" : "")
            }
        }
    }

    private var shown: Double { value.inDegrees ? 180 / .pi : 1 }

    private func part(_ index: Int) -> Binding<Double> {
        Binding(
            get: { (index < numbers.count ? numbers[index] : 0) * shown },
            set: { new in
                var list = numbers
                while list.count <= index { list.append(0) }
                list[index] = new / shown
                numbers = list
            }
        )
    }

    private var range: ClosedRange<Double> {
        if let given = value.range, given.count == 2, given[1] > given[0] {
            return given[0] * shown...given[1] * shown
        }
        if value.inDegrees { return 0...360 }
        let largest = max(1, (value.value.map(abs).max() ?? 0) * 2)
        return value.value.contains { $0 < 0 } ? -largest...largest : 0...largest
    }

    private var step: Double { value.isWhole ? 1 : 0.001 }

    private var color: Binding<String> {
        Binding(
            get: { EngineEditorModel.hex(numbers) },
            set: { hex in
                guard let parts = EngineEditorModel.numbers(hex: hex) else { return }
                var list = numbers
                while list.count < 3 { list.append(1) }
                list[0] = parts[0]
                list[1] = parts[1]
                list[2] = parts[2]
                numbers = list
            }
        )
    }
}

// MARK: - The scene

private struct EngineSceneProperties: View {
    @ObservedObject var model: EngineEditorModel

    var body: some View {
        switch model.sceneTab {
        case .scene: sceneTab
        case .view: viewTab
        case .environment: environmentTab
        case .settings: EngineUserProperties(model: model)
        }
    }

    @ViewBuilder
    private var sceneTab: some View {
        Section("Scene") {
            TextField("Title", text: Binding(get: { model.document.title }, set: { model.document.title = $0 }))
            LabeledContent("Size") {
                Text(verbatim: "\(Int(model.document.size.width)) × \(Int(model.document.size.height))")
                    .foregroundStyle(.secondary)
            }
            ColorRow("Background Color", hex: model.generalColor("clearcolor", default: [0, 0, 0]))
        }
    }

    @ViewBuilder
    private var viewTab: some View {
        Section("Camera") {
            Toggle("Parallax", isOn: model.generalFlag("cameraparallax", default: false))
            if model.document[general: "cameraparallax"]?.plain.boolValue == true {
                NumberRow("Amount", value: model.general("cameraparallaxamount", default: 0.5), in: 0...2, step: 0.01)
                NumberRow("Delay", value: model.general("cameraparallaxdelay", default: 0.1), in: 0...1, step: 0.01)
                NumberRow("Pointer Influence", value: model.general("cameraparallaxmouseinfluence", default: 0), in: 0...1, step: 0.01)
            }
            Toggle("Shake", isOn: model.generalFlag("camerashake", default: false))
            if model.document[general: "camerashake"]?.plain.boolValue == true {
                NumberRow("Amplitude", value: model.general("camerashakeamplitude", default: 0.5), in: 0...5, step: 0.01)
                NumberRow("Speed", value: model.general("camerashakespeed", default: 3), in: 0...10, step: 0.01)
                NumberRow("Roughness", value: model.general("camerashakeroughness", default: 1), in: 0...5, step: 0.01)
            }
            NumberRow("Camera Zoom", value: model.general("zoom", default: 1), in: 0.5...3, step: 0.01)
        }
        Section("Bloom") {
            Toggle("Bloom", isOn: model.generalFlag("bloom", default: false))
            if model.document[general: "bloom"]?.plain.boolValue == true {
                NumberRow("Strength", value: model.general("bloomstrength", default: 2), in: 0...5, step: 0.01)
                NumberRow("Threshold", value: model.general("bloomthreshold", default: 0.65), in: 0...1, step: 0.01)
            }
        }
    }

    @ViewBuilder
    private var environmentTab: some View {
        Section("Physics") {
            NumberRow("Gravity", value: model.general("gravitystrength", default: 1), in: 0...5, step: 0.01)
            Toggle("Wind", isOn: model.generalFlag("windenabled", default: false))
            if model.document[general: "windenabled"]?.plain.boolValue == true {
                NumberRow("Wind Strength", value: model.general("windstrength", default: 1), in: 0...5, step: 0.01)
                NumberRow("Wind Direction", value: model.windDirection(), in: -180...180, suffix: "°")
            }
        }
        Section("Scene Light") {
            ColorRow("Ambient Light", hex: model.generalColor("ambientcolor", default: [0.3, 0.3, 0.3]))
            ColorRow("Sky Light", hex: model.generalColor("skylightcolor", default: [0.3, 0.3, 0.3]))
        }
    }
}

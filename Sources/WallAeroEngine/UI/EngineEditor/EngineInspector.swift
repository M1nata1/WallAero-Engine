import AppKit
import SwiftUI
import WallpaperCore

/// The right-hand side of the editor: the properties of the selected object, or of the scene
/// when none is selected.
struct EngineInspector: View {
    @ObservedObject var model: EngineEditorModel

    var body: some View {
        Form {
            if let id = model.selection, model.document.object(id) != nil {
                EngineObjectProperties(model: model, id: id)
            } else {
                EngineSceneProperties(model: model)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - An object

private struct EngineObjectProperties: View {
    @ObservedObject var model: EngineEditorModel
    let id: Int

    private var kind: WallpaperEngineDocument.ObjectKind { model.kind(of: id) }

    var body: some View {
        Section {
            TextField("Name", text: model.text(id, "name"))
            LabeledContent("Kind") { Text(EngineEditorModel.kindTitle(kind)) }
            Toggle("Visible", isOn: model.flag(id, "visible", default: true))
                .disabled(model.isScripted(id, "visible"))
            if kind != .sound {
                Toggle("Show on Lock Screen", isOn: model.showsOnLockScreen(id))
            }
        }
        if kind != .sound {
            Section("Position") {
                let size = model.document.size
                let hangs = model.document.parent(of: id) != nil
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
        kindSection
        EngineObjectLinks(model: model, id: id)
        if [.image, .text, .solid, .composition, .fullscreen].contains(kind) {
            EngineEffectsSection(model: model, id: id)
        }
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
                Button("Puppet Warp…") { model.sheet = .puppet(object: id) }
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
                NumberRow("Padding", value: model.number(id, "padding", default: 32), in: 0...200)
                Toggle("Background", isOn: model.flag(id, "opaquebackground", default: false))
                if model.value(id, "opaquebackground")?.boolValue == true {
                    ColorRow("Background Color", hex: model.color(id, "backgroundcolor", default: [0, 0, 0]))
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
                Button("Edit Particle System…") { model.sheet = .particles(object: id) }
            }
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
        case .model, .light, .group, .fullscreen:
            EmptyView()
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

/// The effects of an object, in the order they are applied, each with its values.
private struct EngineEffectsSection: View {
    @ObservedObject var model: EngineEditorModel
    let id: Int

    var body: some View {
        let effects = model.document.object(id)?["effects"]?.arrayValue ?? []
        Section {
            ForEach(Array(effects.indices), id: \.self) { index in
                let described = model.description?.object(id)?.effects.first { $0.id == index }
                DisclosureGroup {
                    if let described {
                        ForEach(described.values) { value in
                            EngineEffectValueRows(value: value, numbers: model.effectValue(id, effect: index, value))
                        }
                    } else {
                        Text("Its values show once the scene plays it.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    HStack {
                        Toggle("", isOn: model.effectVisible(id, effect: index))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        Text(verbatim: title(of: effects[index], described: described))
                        Spacer()
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
                    }
                }
            }
            Button {
                model.sheet = .effects(object: id)
            } label: {
                Label("Add Effect…", systemImage: "plus")
            }
        } header: {
            Text("Effects")
        }
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
        Section("Scene") {
            TextField("Title", text: Binding(get: { model.document.title }, set: { model.document.title = $0 }))
            LabeledContent("Size") {
                Text(verbatim: "\(Int(model.document.size.width)) × \(Int(model.document.size.height))")
                    .foregroundStyle(.secondary)
            }
            ColorRow("Background Color", hex: model.generalColor("clearcolor", default: [0, 0, 0]))
        }
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
        Section("Scene Light") {
            ColorRow("Ambient Light", hex: model.generalColor("ambientcolor", default: [0.3, 0.3, 0.3]))
            ColorRow("Sky Light", hex: model.generalColor("skylightcolor", default: [0.3, 0.3, 0.3]))
        }
        EngineUserProperties(model: model)
    }
}

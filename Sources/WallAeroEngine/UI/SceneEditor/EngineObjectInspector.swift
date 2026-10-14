import AppKit
import SwiftUI
import WallpaperCore

/// The properties of an object of the Wallpaper Engine scene the background plays. What is
/// changed here is kept apart from the scene's files (`WallpaperScene.ObjectChange`); a value
/// set back to what the scene has is no change any more. A value an animation or a script of
/// the scene changes as it plays cannot be changed here: what the editor made of it would not
/// show.
struct EngineObjectInspector: View {
    let object: EngineSceneDescription.Object
    let scene: EngineSceneDescription
    @Binding var change: WallpaperScene.ObjectChange
    let model: SceneEditorModel

    var body: some View {
        Section("Object") {
            LabeledContent("Kind") {
                Text(object.kind.title)
            }
            Toggle("Visible", isOn: value(\.isVisible, object.isVisible))
                .disabled(object.isSteered("visible"))
        }
        Section("Position") {
            NumberRow("X", value: value(\.x, object.x), in: span(scene.width))
                .disabled(object.isSteered("origin"))
            NumberRow("Y", value: value(\.y, object.y), in: span(scene.height))
                .disabled(object.isSteered("origin"))
            NumberRow("Scale", value: scale, in: 1...400, suffix: "%")
                .disabled(object.isSteered("scale"))
            NumberRow("Rotation", value: value(\.rotation, object.rotation), in: -180...180, suffix: "°")
                .disabled(object.isSteered("angles"))
        }
        Section("Appearance") {
            NumberRow("Opacity", value: value(\.opacity, object.opacity), in: 0...100, suffix: "%")
                .disabled(object.isSteered("alpha"))
            if object.kind.isTinted {
                ColorRow("Color", hex: value(\.color, object.color))
                    .disabled(object.isSteered("color"))
            }
        }
        kindSection
        ForEach(object.effects) { effect in
            Section {
                Toggle("Enabled", isOn: effectVisible(effect))
                    .disabled(effect.isSteered)
                if change[effect: effect.id].isVisible ?? effect.isVisible {
                    ForEach(effect.values) { value in
                        EffectValueRows(value: value, numbers: numbers(of: effect, value))
                            .disabled(value.isSteered)
                    }
                }
            } header: {
                Text(verbatim: effect.title)
            }
        }
        Section {
            Button("Revert to Original") {
                model.revert(object.id)
            }
            .disabled(change.isEmpty)
        }
    }

    @ViewBuilder
    private var kindSection: some View {
        switch object.kind {
        case .text:
            Section("Text") {
                if object.isSteered("text") {
                    // A clock, say: what the text says is the script's to say.
                    LabeledContent("Text") {
                        Text("Set by a Script")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    TextEditor(text: value(\.text, object.text ?? ""))
                        .font(.body)
                        .frame(height: 64)
                        .scrollContentBackground(.hidden)
                }
                NumberRow("Size", value: value(\.fontSize, object.fontSize ?? 32), in: 4...300)
                    .disabled(object.isSteered("pointsize"))
            }
        case .particles:
            Section("Particles") {
                NumberRow("Amount", value: value(\.particleCount, object.particleCount ?? 100), in: 0...500, suffix: "%")
                NumberRow("Rate", value: value(\.particleRate, object.particleRate ?? 100), in: 0...500, suffix: "%")
                NumberRow("Speed", value: value(\.particleSpeed, object.particleSpeed ?? 100), in: 0...500, suffix: "%")
                NumberRow("Size", value: value(\.particleSize, object.particleSize ?? 100), in: 0...500, suffix: "%")
                NumberRow("Lifetime", value: value(\.particleLifetime, object.particleLifetime ?? 100), in: 0...500, suffix: "%")
                NumberRow("Opacity", value: value(\.particleOpacity, object.particleOpacity ?? 100), in: 0...100, suffix: "%")
                if let own = object.particleColor {
                    ColorRow("Color", hex: value(\.particleColor, own))
                } else {
                    // Without a color of their own, the particles have the colors their system
                    // gives them; one color can be put in their place.
                    Toggle("Recolor", isOn: Binding(
                        get: { change.particleColor != nil },
                        set: { change.particleColor = $0 ? "#FFFFFF" : nil }
                    ))
                    if let color = change.particleColor {
                        ColorRow("Color", hex: Binding(get: { color }, set: { change.particleColor = $0 }))
                    }
                }
            }
        case .sound:
            Section("Sound") {
                NumberRow("Volume", value: value(\.volume, object.volume ?? 100), in: 0...100, suffix: "%")
                    .disabled(object.isSteered("volume"))
            }
        case .image, .model, .light, .group:
            EmptyView()
        }
    }

    // MARK: - Bindings

    /// A value of the object: as the editor has changed it, else as the scene has it.
    private func value<T: Equatable>(_ path: WritableKeyPath<WallpaperScene.ObjectChange, T?>, _ original: T) -> Binding<T> {
        Binding(
            get: { change[keyPath: path] ?? original },
            set: { change[keyPath: path] = $0 == original ? nil : $0 }
        )
    }

    /// Where the object may be put: about the scene, or about the object it hangs on.
    private func span(_ size: Double) -> ClosedRange<Double> {
        let size = max(size, 1)
        return object.parent == nil ? -size / 2...size * 1.5 : -size...size
    }

    /// One scale for both sides, which keep their proportions. A mirrored object stays so.
    private var scale: Binding<Double> {
        Binding(
            get: { abs(change.scaleX ?? object.scaleX) * 100 },
            set: { percent in
                let x = change.scaleX ?? object.scaleX, y = change.scaleY ?? object.scaleY
                let newX = (x < 0 ? -1 : 1) * percent / 100
                let newY = x != 0 ? y * newX / x : (y < 0 ? -1 : 1) * percent / 100
                change.scaleX = abs(newX - object.scaleX) < 1e-9 ? nil : newX
                change.scaleY = abs(newY - object.scaleY) < 1e-9 ? nil : newY
            }
        )
    }

    private func effectVisible(_ effect: EngineSceneDescription.Effect) -> Binding<Bool> {
        Binding(
            get: { change[effect: effect.id].isVisible ?? effect.isVisible },
            set: { change[effect: effect.id].isVisible = $0 == effect.isVisible ? nil : $0 }
        )
    }

    private func numbers(of effect: EngineSceneDescription.Effect, _ value: EngineSceneDescription.Value) -> Binding<[Double]> {
        Binding(
            get: { change[effect: effect.id].values[value.name] ?? value.value },
            set: { change[effect: effect.id].values[value.name] = $0 == value.value ? nil : $0 }
        )
    }
}

/// A value of an effect: a color, a number, or a number for each of its axes.
private struct EffectValueRows: View {
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

    /// An angle is shown in degrees and kept in radians.
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

    /// What the effect says the value may be, else what is around what it is now.
    private var range: ClosedRange<Double> {
        if let given = value.range, given.count == 2, given[1] > given[0] {
            return given[0] * shown...given[1] * shown
        }
        if value.inDegrees {
            return 0...360
        }
        let largest = max(1, (value.value.map(abs).max() ?? 0) * 2)
        return value.value.contains { $0 < 0 } ? -largest...largest : 0...largest
    }

    private var step: Double { value.isWhole ? 1 : 0.001 }

    private var color: Binding<String> {
        Binding(
            get: {
                let parts = (0..<3).map { index -> Int in
                    let part = index < numbers.count ? numbers[index] : 1
                    return Int((min(max(part, 0), 1) * 255).rounded())
                }
                return String(format: "#%02X%02X%02X", parts[0], parts[1], parts[2])
            },
            set: { hex in
                guard let color = NSColor(cssHex: hex)?.usingColorSpace(.sRGB) else { return }
                var list = numbers
                while list.count < 3 { list.append(1) }
                list[0] = Double(color.redComponent)
                list[1] = Double(color.greenComponent)
                list[2] = Double(color.blueComponent)
                numbers = list
            }
        )
    }
}

import AppKit
import SwiftUI
import WallpaperCore

/// Bindings of the inspector's fields to values of the scene's objects and of the scene itself.
/// A value that stands behind a setting of the wallpaper, a script or an animation keeps what
/// it stands behind; only its value changes.
extension EngineEditorModel {
    /// A value of an object, as it is in the scene.
    func value(_ id: Int, _ key: String) -> JSONValue? {
        document.object(id)?[key]?.plain
    }

    private func set(_ id: Int, _ key: String, _ value: JSONValue) {
        document.update(id) { object in
            object[key] = (object[key] ?? .null).replacingPlain(with: value)
        }
    }

    func number(_ id: Int, _ key: String, default fallback: Double) -> Binding<Double> {
        Binding(
            get: { [weak self] in self?.value(id, key)?.numberValue ?? fallback },
            set: { [weak self] in self?.set(id, key, .number($0)) }
        )
    }

    func flag(_ id: Int, _ key: String, default fallback: Bool) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.value(id, key)?.boolValue ?? fallback },
            set: { [weak self] in self?.set(id, key, .bool($0)) }
        )
    }

    func text(_ id: Int, _ key: String, default fallback: String = "") -> Binding<String> {
        Binding(
            get: { [weak self] in self?.value(id, key)?.stringValue ?? fallback },
            set: { [weak self] in self?.set(id, key, .string($0)) }
        )
    }

    /// One number of a value written as several: a place, a scale.
    func part(_ id: Int, _ key: String, _ index: Int, default fallback: [Double], scale: Double = 1) -> Binding<Double> {
        Binding(
            get: { [weak self] in
                let numbers = self?.value(id, key)?.vector ?? fallback
                return (index < numbers.count ? numbers[index] : fallback[min(index, fallback.count - 1)]) * scale
            },
            set: { [weak self] new in
                guard let self else { return }
                var numbers = self.value(id, key)?.vector ?? fallback
                while numbers.count < fallback.count { numbers.append(fallback[numbers.count]) }
                numbers[index] = new / scale
                self.set(id, key, .vector(numbers))
            }
        )
    }

    /// A color, "1 0.5 0" in the scene, as the inspector's "#FF8000".
    func color(_ id: Int, _ key: String, default fallback: [Double] = [1, 1, 1]) -> Binding<String> {
        Binding(
            get: { [weak self] in Self.hex(self?.value(id, key)?.vector ?? fallback) },
            set: { [weak self] in
                guard let self, let numbers = Self.numbers(hex: $0) else { return }
                self.set(id, key, .vector(numbers))
            }
        )
    }

    /// The text of a text object; a script that writes it keeps doing so.
    func textValue(_ id: Int) -> Binding<String> {
        Binding(
            get: { [weak self] in self?.document.object(id)?["text"]?.plain.stringValue ?? "" },
            set: { [weak self] new in
                self?.document.update(id) { object in
                    var text = object["text"] ?? .object([:])
                    if text.objectValue != nil {
                        text["value"] = .string(new)
                    } else {
                        text = .object(["value": .string(new)])
                    }
                    object["text"] = text
                }
            }
        )
    }

    func isScripted(_ id: Int, _ key: String) -> Bool {
        guard let raw = document.object(id)?[key], let dictionary = raw.objectValue else { return false }
        return dictionary["script"] != nil || dictionary["animation"] != nil
    }

    // MARK: - Turning

    /// The turn of an object in the picture's plane, in degrees clockwise, as the editor shows it.
    func rotation(_ id: Int) -> Binding<Double> {
        Binding(
            get: { [weak self] in
                let angles = self?.value(id, "angles")?.vector ?? [0, 0, 0]
                let degrees = -(angles.count > 2 ? angles[2] : 0) * 180 / .pi
                // Not "−0".
                return degrees == 0 ? 0 : degrees
            },
            set: { [weak self] degrees in
                guard let self else { return }
                var angles = self.value(id, "angles")?.vector ?? [0, 0, 0]
                while angles.count < 3 { angles.append(0) }
                angles[2] = -degrees * .pi / 180
                self.set(id, "angles", .vector(angles))
            }
        )
    }

    /// One scale for both sides, in percent; the sides keep their proportions.
    func uniformScale(_ id: Int) -> Binding<Double> {
        Binding(
            get: { [weak self] in abs(self?.value(id, "scale")?.vector?.first ?? 1) * 100 },
            set: { [weak self] percent in
                guard let self else { return }
                var scale = self.value(id, "scale")?.vector ?? [1, 1, 1]
                while scale.count < 3 { scale.append(1) }
                let x = scale[0] == 0 ? 1 : scale[0]
                let factor = (x < 0 ? -1 : 1) * percent / 100 / x
                scale[0] *= factor
                scale[1] *= factor
                self.set(id, "scale", .vector(scale))
            }
        )
    }

    // MARK: - Particles

    /// A value of how a system of particles is played, against its file: 1 is as the file says.
    func override(_ id: Int, _ key: String) -> Binding<Double> {
        Binding(
            get: { [weak self] in (self?.document.object(id)?["instanceoverride"]?[key]?.plain.numberValue ?? 1) * 100 },
            set: { [weak self] percent in
                self?.document.update(id) { object in
                    var over = object["instanceoverride"] ?? .object([:])
                    over[key] = .number(percent / 100)
                    object["instanceoverride"] = over
                }
            }
        )
    }

    /// The one color the particles are given in place of their own, if they are.
    func particleColor(_ id: Int) -> Binding<String?> {
        Binding(
            get: { [weak self] in
                guard let color = self?.document.object(id)?["instanceoverride"]?["colorn"]?.vector else { return nil }
                return Self.hex(color)
            },
            set: { [weak self] hex in
                self?.document.update(id) { object in
                    var over = object["instanceoverride"] ?? .object([:])
                    over["colorn"] = hex.flatMap(Self.numbers(hex:)).map { .vector($0) }
                    over["color"] = nil
                    object["instanceoverride"] = over
                }
            }
        )
    }

    // MARK: - Effects

    /// The value of an effect, as its material names it: what the scene sets, else what the
    /// player says the effect has.
    func effectValue(_ id: Int, effect index: Int, _ value: EngineSceneDescription.Value) -> Binding<[Double]> {
        Binding(
            get: { [weak self] in
                guard let self, let effect = self.document.object(id)?["effects"]?[index] else { return value.value }
                for pass in effect["passes"]?.arrayValue ?? [] {
                    if let set = pass["constantshadervalues"]?[value.name]?.plain {
                        if let numbers = set.vector { return numbers }
                        if let flag = set.boolValue { return [flag ? 1 : 0] }
                    }
                }
                return value.value
            },
            set: { [weak self] numbers in
                let written: JSONValue = numbers.count == 1 ? .number(numbers[0]) : .string(numbers.map { Self.short($0) }.joined(separator: " "))
                self?.document.setEffectValue(written, named: value.name, effect: index, of: id)
            }
        )
    }

    func effectVisible(_ id: Int, effect index: Int) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.document.object(id)?["effects"]?[index]?["visible"]?.plain.boolValue ?? true },
            set: { [weak self] in self?.document.setEffectVisible($0, effect: index, of: id) }
        )
    }

    // MARK: - The material of a picture

    /// Changes the first pass of the material a picture is drawn with.
    private func changeMaterial(of id: Int, _ change: (inout JSONValue) -> Void) {
        guard let material = document.material(ofObject: id) else { return }
        var value = material.value
        guard var passes = value["passes"]?.arrayValue, !passes.isEmpty else { return }
        change(&passes[0])
        value["passes"] = .array(passes)
        document.setFile(material.name, value)
    }

    private func materialPass(of id: Int) -> JSONValue? {
        document.material(ofObject: id)?.value["passes"]?[0]
    }

    /// A switch of the material's shader: lighting, reflection.
    func materialCombo(_ id: Int, _ name: String) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.materialPass(of: id)?["combos"]?[name]?.numberValue == 1 },
            set: { [weak self] on in
                self?.changeMaterial(of: id) { pass in
                    var combos = pass["combos"] ?? .object([:])
                    combos[name] = on ? .number(1) : nil
                    pass["combos"] = combos
                }
            }
        )
    }

    /// A value of the material, as its shader names it.
    func materialValue(_ id: Int, _ name: String, default fallback: Double) -> Binding<Double> {
        Binding(
            get: { [weak self] in self?.materialPass(of: id)?["constantshadervalues"]?[name]?.plain.numberValue ?? fallback },
            set: { [weak self] new in
                self?.changeMaterial(of: id) { pass in
                    var values = pass["constantshadervalues"] ?? .object([:])
                    values[name] = .number(new)
                    pass["constantshadervalues"] = values
                }
            }
        )
    }

    /// The texture in a slot of the material after the picture itself: 1 the normal map.
    func materialTexture(_ id: Int, slot: Int) -> String? {
        guard let textures = materialPass(of: id)?["textures"]?.arrayValue, slot < textures.count else { return nil }
        return textures[slot].stringValue
    }

    func setMaterialTexture(_ id: Int, slot: Int, to texture: String?) {
        changeMaterial(of: id) { pass in
            var textures = pass["textures"]?.arrayValue ?? []
            while textures.count <= slot { textures.append(.null) }
            textures[slot] = texture.map { .string($0) } ?? .null
            // What is left empty at the end is not written.
            while let last = textures.last, last.isNull, textures.count > 1 { textures.removeLast() }
            pass["textures"] = .array(textures)
        }
    }

    // MARK: - The scene

    func general(_ key: String, default fallback: Double) -> Binding<Double> {
        Binding(
            get: { [weak self] in self?.document[general: key]?.plain.numberValue ?? fallback },
            set: { [weak self] new in
                guard let self else { return }
                self.document[general: key] = (self.document[general: key] ?? .null).replacingPlain(with: .number(new))
            }
        )
    }

    func generalFlag(_ key: String, default fallback: Bool) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.document[general: key]?.plain.boolValue ?? fallback },
            set: { [weak self] new in
                guard let self else { return }
                self.document[general: key] = (self.document[general: key] ?? .null).replacingPlain(with: .bool(new))
            }
        )
    }

    /// Where the scene's wind blows, as an angle in degrees from blowing to the right, up
    /// counting positive: the scene keeps it as a direction, "0.707 0.707 0".
    func windDirection() -> Binding<Double> {
        Binding(
            get: { [weak self] in
                let direction = self?.document[general: "winddirection"]?.vector ?? [0.707, 0.707, 0]
                let degrees = atan2(direction.count > 1 ? direction[1] : 0, direction.first ?? 1) * 180 / .pi
                return degrees.rounded()
            },
            set: { [weak self] degrees in
                guard let self else { return }
                let radians = degrees * .pi / 180
                let direction = [(cos(radians) * 1000).rounded() / 1000, (sin(radians) * 1000).rounded() / 1000, 0]
                self.document[general: "winddirection"] = (self.document[general: "winddirection"] ?? .null).replacingPlain(with: .vector(direction))
            }
        )
    }

    func generalColor(_ key: String, default fallback: [Double]) -> Binding<String> {
        Binding(
            get: { [weak self] in Self.hex(self?.document[general: key]?.vector ?? fallback) },
            set: { [weak self] hex in
                guard let self, let numbers = Self.numbers(hex: hex) else { return }
                self.document[general: key] = (self.document[general: key] ?? .null).replacingPlain(with: .vector(numbers))
            }
        )
    }

    // MARK: - Colors

    nonisolated static func hex(_ numbers: [Double]) -> String {
        let parts = (0..<3).map { index -> Int in
            let part = index < numbers.count ? numbers[index] : 1
            return Int((min(max(part, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", parts[0], parts[1], parts[2])
    }

    nonisolated static func numbers(hex: String) -> [Double]? {
        guard let color = NSColor(cssHex: hex)?.usingColorSpace(.sRGB) else { return nil }
        return [color.redComponent, color.greenComponent, color.blueComponent].map { (Double($0) * 100_000).rounded() / 100_000 }
    }

    nonisolated static func short(_ number: Double) -> String {
        number == number.rounded() && abs(number) < 1e9 ? String(Int(number)) : String(format: "%.5f", number)
    }
}

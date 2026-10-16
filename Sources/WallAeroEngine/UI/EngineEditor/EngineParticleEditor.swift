import SwiftUI
import WallpaperCore

/// What a system of particles is made of, as Wallpaper Engine describes it: where particles are
/// made (emitters), what each starts with (initializers), what happens to it as it lives
/// (operators), and how it is drawn (the renderer). Each part has values of its own.
struct ParticleComponentKind: Identifiable {
    enum Section: String, CaseIterable {
        case emitter, initializer, `operator`, renderer

        var title: LocalizedStringKey {
            switch self {
            case .emitter: return "Emitters"
            case .initializer: return "Initial Values"
            case .operator: return "Over Time"
            case .renderer: return "Drawing"
            }
        }
    }

    enum ValueKind {
        case number(ClosedRange<Double>)
        case vector(Int)
        /// A color from 0 to 255 a channel.
        case color255
        /// A color from 0 to 1 a channel.
        case color1
    }

    struct Value {
        let key: String
        let title: String
        let kind: ValueKind
        let fallback: JSONValue
    }

    let name: String
    let title: String
    let section: Section
    let values: [Value]

    var id: String { name }

    private static func number(_ key: String, _ title: String, _ fallback: Double, _ range: ClosedRange<Double>) -> Value {
        Value(key: key, title: title, kind: .number(range), fallback: .number(fallback))
    }

    private static func vector(_ key: String, _ title: String, _ fallback: [Double]) -> Value {
        Value(key: key, title: title, kind: .vector(fallback.count), fallback: .string(fallback.map { EngineEditorModel.short($0) }.joined(separator: " ")))
    }

    private static func color(_ key: String, _ title: String, _ fallback: String, of255: Bool = true) -> Value {
        Value(key: key, title: title, kind: of255 ? .color255 : .color1, fallback: .string(fallback))
    }

    private static let t = { (key: String) in NSLocalizedString(key, comment: "A value of a part of a system of particles") }

    static let all: [ParticleComponentKind] = [
        // Emitters
        .init(name: "boxrandom", title: t("Box"), section: .emitter, values: [
            number("rate", t("Rate"), 10, 0...2000), vector("distancemin", t("Least Distance"), [0, 0, 0]),
            vector("distancemax", t("Greatest Distance"), [256, 256, 0]), vector("origin", t("Place"), [0, 0, 0]),
            vector("directions", t("Directions"), [1, 1, 0]), number("speedmin", t("Least Speed"), 0, 0...2000),
            number("speedmax", t("Greatest Speed"), 0, 0...2000), number("instantaneous", t("At Once"), 0, 0...2000),
        ]),
        .init(name: "sphererandom", title: t("Sphere"), section: .emitter, values: [
            number("rate", t("Rate"), 10, 0...2000), number("distancemin", t("Least Distance"), 0, 0...4000),
            number("distancemax", t("Greatest Distance"), 256, 0...4000), vector("origin", t("Place"), [0, 0, 0]),
            vector("directions", t("Directions"), [1, 1, 0]), number("speedmin", t("Least Speed"), 0, 0...2000),
            number("speedmax", t("Greatest Speed"), 0, 0...2000), number("instantaneous", t("At Once"), 0, 0...2000),
        ]),
        // Initializers
        .init(name: "lifetimerandom", title: t("Lifetime"), section: .initializer, values: [
            number("min", t("Least"), 1, 0...60), number("max", t("Greatest"), 1, 0...60),
        ]),
        .init(name: "sizerandom", title: t("Size"), section: .initializer, values: [
            number("min", t("Least"), 20, 0...1000), number("max", t("Greatest"), 20, 0...1000),
        ]),
        .init(name: "colorrandom", title: t("Color"), section: .initializer, values: [
            color("min", t("From"), "255 255 255"), color("max", t("To"), "255 255 255"),
        ]),
        .init(name: "alpharandom", title: t("Opacity"), section: .initializer, values: [
            number("min", t("Least"), 1, 0...1), number("max", t("Greatest"), 1, 0...1),
        ]),
        .init(name: "velocityrandom", title: t("Velocity"), section: .initializer, values: [
            vector("min", t("Least"), [-32, -32, 0]), vector("max", t("Greatest"), [32, 32, 0]),
        ]),
        .init(name: "rotationrandom", title: t("Rotation"), section: .initializer, values: [
            vector("min", t("Least"), [0, 0, 0]), vector("max", t("Greatest"), [0, 0, 6.28]),
        ]),
        .init(name: "angularvelocityrandom", title: t("Spin"), section: .initializer, values: [
            vector("min", t("Least"), [0, 0, -2]), vector("max", t("Greatest"), [0, 0, 2]),
        ]),
        .init(name: "turbulentvelocityrandom", title: t("Turbulent Velocity"), section: .initializer, values: [
            number("speedmin", t("Least Speed"), 100, 0...2000), number("speedmax", t("Greatest Speed"), 250, 0...2000),
            number("scale", t("Scale"), 1, 0...10), number("offset", t("Offset"), 0, -10...10),
        ]),
        // Operators
        .init(name: "movement", title: t("Movement"), section: .operator, values: [
            vector("gravity", t("Gravity"), [0, 0, 0]), number("drag", t("Drag"), 0, 0...10),
        ]),
        .init(name: "alphafade", title: t("Fade In and Out"), section: .operator, values: [
            number("fadeintime", t("Fade In"), 0.5, 0...1), number("fadeouttime", t("Fade Out"), 0.5, 0...1),
        ]),
        .init(name: "sizechange", title: t("Size Change"), section: .operator, values: [
            number("starttime", t("Start"), 0, 0...1), number("endtime", t("End"), 1, 0...1),
            number("startvalue", t("From"), 1, 0...10), number("endvalue", t("To"), 0, 0...10),
        ]),
        .init(name: "alphachange", title: t("Opacity Change"), section: .operator, values: [
            number("starttime", t("Start"), 0, 0...1), number("endtime", t("End"), 1, 0...1),
            number("startvalue", t("From"), 1, 0...1), number("endvalue", t("To"), 0, 0...1),
        ]),
        .init(name: "colorchange", title: t("Color Change"), section: .operator, values: [
            number("starttime", t("Start"), 0, 0...1), number("endtime", t("End"), 1, 0...1),
            color("startvalue", t("From"), "1 1 1", of255: false), color("endvalue", t("To"), "1 1 1", of255: false),
        ]),
        .init(name: "turbulence", title: t("Turbulence"), section: .operator, values: [
            number("scale", t("Scale"), 0.005, 0...0.1), number("speedmin", t("Least Speed"), 500, 0...3000),
            number("speedmax", t("Greatest Speed"), 1000, 0...3000), vector("mask", t("Axes"), [1, 1, 0]),
        ]),
        .init(name: "vortex", title: t("Vortex"), section: .operator, values: [
            vector("axis", t("Axis"), [0, 0, 1]), vector("offset", t("Place"), [0, 0, 0]),
            number("distanceinner", t("Inner Distance"), 500, 0...4000), number("distanceouter", t("Outer Distance"), 650, 0...4000),
            number("speedinner", t("Inner Speed"), 2500, -5000...5000), number("speedouter", t("Outer Speed"), 0, -5000...5000),
        ]),
        .init(name: "oscillatealpha", title: t("Flicker"), section: .operator, values: [
            number("frequencymin", t("Least Frequency"), 0, 0...20), number("frequencymax", t("Greatest Frequency"), 10, 0...20),
            number("scalemin", t("Least"), 0, 0...1), number("scalemax", t("Greatest"), 1, 0...1),
        ]),
        .init(name: "oscillatesize", title: t("Size Pulse"), section: .operator, values: [
            number("frequencymin", t("Least Frequency"), 0, 0...20), number("frequencymax", t("Greatest Frequency"), 10, 0...20),
            number("scalemin", t("Least"), 0.8, 0...4), number("scalemax", t("Greatest"), 1.2, 0...4),
        ]),
        .init(name: "oscillateposition", title: t("Wobble"), section: .operator, values: [
            number("frequencymin", t("Least Frequency"), 0, 0...20), number("frequencymax", t("Greatest Frequency"), 5, 0...20),
            number("scalemin", t("Least"), 0, 0...200), number("scalemax", t("Greatest"), 10, 0...200), vector("mask", t("Axes"), [1, 1, 0]),
        ]),
        .init(name: "controlpointattract", title: t("Pull to the Pointer"), section: .operator, values: [
            number("controlpoint", t("Point"), 1, 0...7), number("scale", t("Strength"), 300, -5000...5000),
            number("threshold", t("Reach"), 200, 0...4000), vector("origin", t("Place"), [0, 0, 0]),
        ]),
        // Renderers
        .init(name: "sprite", title: t("Sprites"), section: .renderer, values: []),
        .init(name: "spritetrail", title: t("Trails"), section: .renderer, values: [
            number("length", t("Length"), 0.05, 0...1), number("maxlength", t("Greatest Length"), 100, 0...2000),
        ]),
    ]

    static func named(_ name: String) -> ParticleComponentKind? {
        all.first { $0.name == name.lowercased() }
    }
}

/// Changes the file of a system of particles: its parts and their values. The system shows in
/// the scene as it changes.
struct EngineParticleEditor: View {
    @ObservedObject var model: EngineEditorModel
    let object: Int
    @Environment(\.dismiss) private var dismiss

    private var fileName: String? { model.document.object(object)?["particle"]?.plain.stringValue }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Particle System").font(.headline)
                Spacer()
                if let fileName {
                    Text(verbatim: fileName).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
            Divider()
            if let fileName, model.document.file(fileName) != nil {
                Form {
                    Section("Whole System") {
                        NumberRow("Most Particles", value: systemNumber(fileName, "maxcount", 100), in: 1...5000)
                        NumberRow("Warmed Up For", value: systemNumber(fileName, "starttime", 0), in: 0...60, step: 0.1, suffix: "s")
                        Picker("Blending", selection: blending(fileName)) {
                            Text("Add Light").tag("additive")
                            Text("Over What Is Behind").tag("translucent")
                            Text("Normal").tag("normal")
                        }
                    }
                    ForEach(ParticleComponentKind.Section.allCases, id: \.self) { section in
                        componentSection(section, fileName: fileName)
                    }
                }
                .formStyle(.grouped)
            } else {
                Spacer()
                Text("The system's file is not in the project.").foregroundStyle(.secondary)
                Spacer()
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560, height: 680)
    }

    @ViewBuilder
    private func componentSection(_ section: ParticleComponentKind.Section, fileName: String) -> some View {
        let parts = model.document.file(fileName)?[section.rawValue]?.arrayValue ?? []
        Section {
            ForEach(Array(parts.indices), id: \.self) { index in
                let name = parts[index]["name"]?.stringValue ?? ""
                DisclosureGroup {
                    if let kind = ParticleComponentKind.named(name) {
                        ForEach(kind.values, id: \.key) { value in
                            valueRow(value, section: section, index: index, fileName: fileName)
                        }
                    } else {
                        Text("Its values are kept as they are.").font(.callout).foregroundStyle(.secondary)
                    }
                } label: {
                    HStack {
                        Text(verbatim: ParticleComponentKind.named(name)?.title ?? name)
                        Spacer()
                        if section != .renderer || parts.count > 1 {
                            Button {
                                change(fileName) { system in
                                    var list = system[section.rawValue]?.arrayValue ?? []
                                    list.remove(at: index)
                                    system[section.rawValue] = .array(list)
                                }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove")
                        }
                    }
                }
            }
            Menu {
                ForEach(ParticleComponentKind.all.filter { $0.section == section }) { kind in
                    Button(kind.title) { add(kind, fileName: fileName) }
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } header: {
            Text(section.title)
        }
    }

    @ViewBuilder
    private func valueRow(_ value: ParticleComponentKind.Value, section: ParticleComponentKind.Section, index: Int, fileName: String) -> some View {
        let binding = Binding<JSONValue>(
            get: { model.document.file(fileName)?[section.rawValue]?[index]?[value.key] ?? value.fallback },
            set: { new in
                change(fileName) { system in
                    var list = system[section.rawValue]?.arrayValue ?? []
                    guard list.indices.contains(index) else { return }
                    list[index][value.key] = new
                    system[section.rawValue] = .array(list)
                }
            }
        )
        switch value.kind {
        case .number(let range):
            NumberRow(title: Text(verbatim: value.title), value: Binding(
                get: { binding.wrappedValue.numberValue ?? 0 },
                set: { binding.wrappedValue = .number($0) }
            ), in: range, step: range.upperBound <= 1 ? 0.01 : (range.upperBound <= 20 ? 0.1 : 1))
        case .vector(let count):
            LabeledContent {
                HStack(spacing: 4) {
                    ForEach(0..<count, id: \.self) { axis in
                        TextField("", value: Binding(
                            get: {
                                let numbers = binding.wrappedValue.vector ?? []
                                return axis < numbers.count ? numbers[axis] : (numbers.count == 1 ? numbers[0] : 0)
                            },
                            set: { new in
                                var numbers = binding.wrappedValue.vector ?? []
                                if numbers.count == 1 { numbers = Array(repeating: numbers[0], count: count) }
                                while numbers.count < count { numbers.append(0) }
                                numbers[axis] = new
                                binding.wrappedValue = .string(numbers.map { EngineEditorModel.short($0) }.joined(separator: " "))
                            }
                        ), format: .number.precision(.fractionLength(0...3)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 58)
                    }
                }
            } label: {
                Text(verbatim: value.title)
            }
        case .color255, .color1:
            let scale: Double = { if case .color255 = value.kind { return 255 } else { return 1 } }()
            ColorRow(title: Text(verbatim: value.title), hex: Binding(
                get: { EngineEditorModel.hex((binding.wrappedValue.vector ?? [scale, scale, scale]).map { $0 / scale }) },
                set: { hex in
                    guard let numbers = EngineEditorModel.numbers(hex: hex) else { return }
                    binding.wrappedValue = .string(numbers.map { EngineEditorModel.short(scale == 255 ? ($0 * 255).rounded() : $0) }.joined(separator: " "))
                }
            ))
        }
    }

    // MARK: - Changing the file

    private func change(_ fileName: String, _ body: (inout JSONValue) -> Void) {
        guard var system = model.document.file(fileName) else { return }
        body(&system)
        model.document.setFile(fileName, system)
    }

    private func add(_ kind: ParticleComponentKind, fileName: String) {
        model.endGesture()
        change(fileName) { system in
            var list = system[kind.section.rawValue]?.arrayValue ?? []
            if kind.section == .renderer { list = [] }
            // A number no part of the system has.
            var highest = 0
            for section in ParticleComponentKind.Section.allCases {
                for part in system[section.rawValue]?.arrayValue ?? [] {
                    highest = max(highest, Int(part["id"]?.numberValue ?? 0))
                }
            }
            var part: [String: JSONValue] = ["name": .string(kind.name), "id": .number(Double(highest + 1))]
            for value in kind.values { part[value.key] = value.fallback }
            list.append(.object(part))
            system[kind.section.rawValue] = .array(list)
        }
        model.endGesture()
    }

    private func systemNumber(_ fileName: String, _ key: String, _ fallback: Double) -> Binding<Double> {
        Binding(
            get: { model.document.file(fileName)?[key]?.numberValue ?? fallback },
            set: { new in change(fileName) { $0[key] = .number(new) } }
        )
    }

    /// How the particles are laid over what is behind them: their material's blending.
    private func blending(_ fileName: String) -> Binding<String> {
        Binding(
            get: {
                guard let material = model.document.file(fileName)?["material"]?.stringValue else { return "additive" }
                return model.document.file(material)?["passes"]?[0]?["blending"]?.stringValue ?? "additive"
            },
            set: { new in
                guard let material = model.document.file(fileName)?["material"]?.stringValue, var value = model.document.file(material),
                      var passes = value["passes"]?.arrayValue, !passes.isEmpty
                else {
                    return
                }
                // Other systems may be drawn with the same material: this one gets one of its own,
                // as the material is but for its blending.
                passes[0]["blending"] = .string(new)
                value["passes"] = .array(passes)
                var base = (material as NSString).deletingPathExtension
                for suffix in ["_additive", "_translucent", "_normal"] where base.hasSuffix(suffix) {
                    base.removeLast(suffix.count)
                }
                let own = "\(base)_\(new).json"
                if model.document.file(own) == nil { model.document.setFile(own, value) }
                change(fileName) { $0["material"] = .string(own) }
            }
        )
    }
}

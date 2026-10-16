import SwiftUI
import WallpaperCore

/// The wallpaper's settings, which whoever uses it changes: in Wallpaper Engine and in this
/// app's wallpaper settings alike. They are kept in the project, `general.properties`; an
/// object's value follows one when it is linked to it.
extension EngineEditorModel {
    struct UserProperty: Identifiable, Equatable {
        enum Kind: String, CaseIterable {
            case bool, slider, color, combo, textinput

            var title: String {
                switch self {
                case .bool: return NSLocalizedString("Checkbox", comment: "Kind of a wallpaper setting")
                case .slider: return NSLocalizedString("Slider", comment: "Kind of a wallpaper setting")
                case .color: return NSLocalizedString("Color", comment: "Kind of a wallpaper setting")
                case .combo: return NSLocalizedString("List", comment: "Kind of a wallpaper setting")
                case .textinput: return NSLocalizedString("Text", comment: "Kind of a wallpaper setting")
                }
            }
        }

        var id: String
        var kind: Kind
        var value: JSONValue
    }

    /// The settings the wallpaper has, in their order; the scheme color every wallpaper has is
    /// left out.
    var userProperties: [UserProperty] {
        let properties = document.project["general"]?["properties"]?.objectValue ?? [:]
        return properties.compactMap { name, value -> (Double, UserProperty)? in
            guard name != "schemecolor", let kind = UserProperty.Kind(rawValue: value["type"]?.stringValue?.lowercased() ?? "") else { return nil }
            return (value["order"]?.numberValue ?? 0, UserProperty(id: name, kind: kind, value: value))
        }
        .sorted { $0.0 == $1.0 ? $0.1.id < $1.1.id : $0.0 < $1.0 }
        .map(\.1)
    }

    func addUserProperty(_ kind: UserProperty.Kind) {
        let existing = Set(document.project["general"]?["properties"]?.objectValue?.keys.map { $0 } ?? [])
        var number = 1
        while existing.contains("setting\(number)") { number += 1 }
        let name = "setting\(number)"
        var property: [String: JSONValue] = [
            "type": .string(kind.rawValue),
            "text": .string(String(format: NSLocalizedString("Setting %d", comment: "Name of a new wallpaper setting"), number)),
            "order": .number(Double(100 + userProperties.count)),
        ]
        switch kind {
        case .bool: property["value"] = .bool(true)
        case .slider:
            property["value"] = .number(1)
            property["min"] = .number(0)
            property["max"] = .number(1)
            property["step"] = .number(0.01)
            property["precision"] = .number(2)
            property["fraction"] = .bool(true)
        case .color: property["value"] = .string("1 1 1")
        case .combo:
            property["value"] = .string("1")
            property["options"] = .array([
                .object(["label": .string(NSLocalizedString("First", comment: "Option of a new list setting")), "value": .string("1")]),
                .object(["label": .string(NSLocalizedString("Second", comment: "Option of a new list setting")), "value": .string("2")]),
            ])
        case .textinput: property["value"] = .string("")
        }
        change { document in
            var general = document.project["general"] ?? .object([:])
            var properties = general["properties"] ?? .object([:])
            properties[name] = .object(property)
            general["properties"] = properties
            document.project["general"] = general
        }
    }

    func removeUserProperty(_ name: String) {
        change { document in
            document.project["general"]?["properties"]?[name] = nil
            // What was linked to it keeps the value it has.
            document.objects = document.objects.map { Self.unlinking(name, in: $0) }
        }
    }

    private static func unlinking(_ name: String, in value: JSONValue) -> JSONValue {
        switch value {
        case .object(var dictionary):
            if dictionary["user"]?.stringValue == name || dictionary["user"]?["name"]?.stringValue == name {
                return dictionary["value"] ?? .null
            }
            for (key, inner) in dictionary { dictionary[key] = unlinking(name, in: inner) }
            return .object(dictionary)
        case .array(let array):
            return .array(array.map { unlinking(name, in: $0) })
        default:
            return value
        }
    }

    /// What a setting is called, as whoever uses the wallpaper reads it: its label without the
    /// HTML Wallpaper Engine lets it have, translated if the project has a translation of it.
    func userPropertyTitle(_ name: String) -> String {
        var label = document.project["general"]?["properties"]?[name]?["text"]?.stringValue ?? name
        if let tables = document.project["general"]?["localization"]?.objectValue {
            let wanted = Locale.preferredLanguages.map { String($0.lowercased().prefix(2)) } + ["en"]
            for language in wanted {
                if let table = tables.first(where: { $0.key.lowercased().hasPrefix(language) })?.value,
                   let text = table[label]?.stringValue, !text.isEmpty {
                    label = text
                    break
                }
            }
        }
        var plain = label.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, character) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            plain = plain.replacingOccurrences(of: entity, with: character)
        }
        plain = plain.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return plain.isEmpty ? name : plain
    }

    func userPropertyField(_ name: String, _ key: String) -> Binding<JSONValue?> {
        Binding(
            get: { [weak self] in self?.document.project["general"]?["properties"]?[name]?[key] },
            set: { [weak self] in self?.document.project["general"]?["properties"]?[name]?[key] = $0 }
        )
    }

    /// The setting an object's value follows, if it follows one.
    func link(_ id: Int, _ key: String) -> Binding<String?> {
        Binding(
            get: { [weak self] in self?.document.object(id)?[key]?["user"]?.stringValue },
            set: { [weak self] name in
                self?.document.update(id) { object in
                    let plain = object[key]?.plain ?? .null
                    if let name {
                        object[key] = .object(["user": .string(name), "value": plain])
                    } else {
                        object[key] = plain.isNull ? nil : plain
                    }
                }
            }
        )
    }
}

/// The settings of the wallpaper, in the scene's properties.
struct EngineUserProperties: View {
    @ObservedObject var model: EngineEditorModel

    var body: some View {
        Section {
            ForEach(model.userProperties) { property in
                DisclosureGroup {
                    TextField("Label", text: string(property.id, "text"))
                    switch property.kind {
                    case .bool:
                        Toggle("On", isOn: Binding(
                            get: { model.userPropertyField(property.id, "value").wrappedValue?.boolValue ?? false },
                            set: { model.userPropertyField(property.id, "value").wrappedValue = .bool($0) }
                        ))
                    case .slider:
                        numberField("Minimum", property.id, "min")
                        numberField("Maximum", property.id, "max")
                        numberField("Value", property.id, "value")
                    case .color:
                        ColorRow("Value", hex: Binding(
                            get: { EngineEditorModel.hex(model.userPropertyField(property.id, "value").wrappedValue?.vector ?? [1, 1, 1]) },
                            set: { hex in
                                if let numbers = EngineEditorModel.numbers(hex: hex) {
                                    model.userPropertyField(property.id, "value").wrappedValue = .string(numbers.map { EngineEditorModel.short($0) }.joined(separator: " "))
                                }
                            }
                        ))
                    case .combo:
                        Text("Options are named in the project file.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    case .textinput:
                        TextField("Value", text: string(property.id, "value"))
                    }
                    Button("Remove Setting", role: .destructive) { model.removeUserProperty(property.id) }
                } label: {
                    Label {
                        Text(verbatim: model.userPropertyTitle(property.id))
                            .lineLimit(2)
                    } icon: {
                        Image(systemName: symbol(property.kind))
                    }
                }
            }
            Menu {
                ForEach(EngineEditorModel.UserProperty.Kind.allCases, id: \.self) { kind in
                    Button(kind.title) { model.addUserProperty(kind) }
                }
            } label: {
                Label("Add Setting", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        } header: {
            Text("Wallpaper Settings")
        }
    }

    private func string(_ name: String, _ key: String) -> Binding<String> {
        Binding(
            get: { model.userPropertyField(name, key).wrappedValue?.stringValue ?? "" },
            set: { model.userPropertyField(name, key).wrappedValue = .string($0) }
        )
    }

    private func numberField(_ title: LocalizedStringKey, _ name: String, _ key: String) -> some View {
        LabeledContent(title) {
            TextField("", value: Binding(
                get: { model.userPropertyField(name, key).wrappedValue?.numberValue ?? 0 },
                set: { model.userPropertyField(name, key).wrappedValue = .number($0) }
            ), format: .number)
            .multilineTextAlignment(.trailing)
            .frame(width: 80)
        }
    }

    private func symbol(_ kind: EngineEditorModel.UserProperty.Kind) -> String {
        switch kind {
        case .bool: return "checkmark.square"
        case .slider: return "slider.horizontal.3"
        case .color: return "paintpalette"
        case .combo: return "list.bullet"
        case .textinput: return "character.cursor.ibeam"
        }
    }
}

/// The values of an object that may follow a setting of the wallpaper, each with the settings
/// of a kind to fit it.
struct EngineObjectLinks: View {
    @ObservedObject var model: EngineEditorModel
    let id: Int

    var body: some View {
        let properties = model.userProperties
        if !properties.isEmpty {
            Section("Follows a Setting") {
                picker("Visible", key: "visible", kinds: [.bool], properties: properties)
                if [.image, .text, .solid, .composition].contains(model.kind(of: id)) {
                    picker("Opacity", key: "alpha", kinds: [.slider], properties: properties)
                    picker("Color", key: "color", kinds: [.color], properties: properties)
                }
                if model.kind(of: id) == .text {
                    picker("Text", key: "text", kinds: [.textinput], properties: properties)
                }
            }
        }
    }

    private func picker(_ title: LocalizedStringKey, key: String, kinds: [EngineEditorModel.UserProperty.Kind],
                        properties: [EngineEditorModel.UserProperty]) -> some View {
        Picker(title, selection: model.link(id, key)) {
            Text("None").tag(String?.none)
            ForEach(properties.filter { kinds.contains($0.kind) }) { property in
                Text(verbatim: model.userPropertyTitle(property.id)).tag(Optional(property.id))
            }
        }
    }
}

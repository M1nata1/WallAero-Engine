import SwiftUI
import WallpaperCore

/// The effects that can be put on an object, by group, with what each does.
struct EngineEffectGallery: View {
    @ObservedObject var model: EngineEditorModel
    let object: Int
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var effects: [WallpaperEngineEffect] {
        let wanted = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return WallpaperEngineEffect.all }
        return WallpaperEngineEffect.all.filter { $0.title.lowercased().contains(wanted) || $0.summary.lowercased().contains(wanted) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Effect")
                    .font(.headline)
                Spacer()
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            .padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(WallpaperEngineEffect.Group.allCases, id: \.self) { group in
                        let inGroup = effects.filter { $0.group == group }
                        if !inGroup.isEmpty {
                            Text(group.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                                ForEach(inGroup) { effect in
                                    Button {
                                        model.addEffect(effect, to: object)
                                        dismiss()
                                    } label: {
                                        EffectTile(effect: effect)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 640, height: 520)
    }
}

private struct EffectTile: View {
    let effect: WallpaperEngineEffect
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: effect.symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(effect.title)
                    .font(.body.weight(.medium))
                Text(effect.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

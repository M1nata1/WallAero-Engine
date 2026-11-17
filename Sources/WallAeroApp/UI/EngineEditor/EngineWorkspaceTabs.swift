import SwiftUI

/// The workspaces as Blender's tabs along the top: Layout, Animation, Scripting. Control-Page
/// Up and Page Down go from one to the next, T between Layout and Animation.
struct EngineWorkspaceTabs: View {
    @ObservedObject var model: EngineEditorModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(EngineEditorModel.Workspace.allCases, id: \.self) { workspace in
                let chosen = model.workspace == workspace
                Button {
                    model.workspace = workspace
                } label: {
                    Text(verbatim: workspace.title)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .foregroundStyle(chosen ? Color.primary : Color.secondary)
                        .background(chosen ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.clear),
                                    in: RoundedRectangle(cornerRadius: SystemLook.innerCornerRadius + 2, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 8)
        .frame(height: 34)
    }
}

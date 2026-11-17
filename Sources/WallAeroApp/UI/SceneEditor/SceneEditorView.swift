import SwiftUI
import WallpaperCore

/// The scene editor's window: layers and variables on the left, the live preview in the middle,
/// the properties of what is selected on the right.
struct SceneEditorView: View {
    @ObservedObject var model: SceneEditorModel
    let preview: SceneEditorPreviewController

    var body: some View {
        // No least width is named here: the three parts have their own, and macOS 26 adds the
        // room the toolbar's buttons need. A smaller number would let the window get narrower
        // than its content, which then sticks out of it at both sides.
        layout
            .frame(minHeight: 600)
    }

    /// Laid out as Blender is, as the editor of Wallpaper Engine's scenes: the workspaces'
    /// tabs, the page with its header and view controls and its time under it; on the right the
    /// layers and variables over the properties.
    @ViewBuilder
    private var layout: some View {
        if #available(macOS 14.0, *) {
            NavigationSplitView(columnVisibility: .constant(.detailOnly)) {
                Color.clear
                    .toolbar(removing: .sidebarToggle)
            } detail: {
                middle
                    .toolbar {
                        ToolbarItemGroup {
                            undoButton
                            redoButton
                        }
                    }
            }
            .inspector(isPresented: .constant(true)) {
                side
                    .inspectorColumnWidth(min: 300, ideal: 360, max: 460)
                    .toolbar {
                        Spacer()
                        showFolderButton
                    }
            }
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    undoButton
                    redoButton
                    Spacer()
                    showFolderButton
                        .labelStyle(.titleAndIcon)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
                HStack(spacing: 0) {
                    middle
                    Divider()
                    side.frame(width: 360)
                }
            }
        }
    }

    private var side: some View {
        VSplitView {
            LayerList(model: model)
                .frame(minHeight: 140, idealHeight: 300)
            SceneInspector(model: model)
                .frame(minHeight: 240, idealHeight: 500)
        }
    }

    private var middle: some View {
        VStack(spacing: 0) {
            SceneWorkspaceTabs(model: model)
            Divider()
            if model.workspace == .scripting {
                HSplitView {
                    viewport
                        .frame(minWidth: 300, idealWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                    WebCodeEditor(model: model)
                        .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                viewport
            }
        }
        .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        .bottomBar {
            VStack(spacing: 0) {
                SceneTimeBar(time: .init(seconds: model.timelineSeconds, rate: model.timelineRate, length: model.playLength,
                                         isPlaying: model.isPlaying, go: { model.timelineSeconds = $0 },
                                         play: { model.isPlaying = $0 }))
            }
        }
    }

    private var viewport: some View {
        VStack(spacing: 0) {
            WebViewportHeader(model: model, addLayerMenu: addLayerMenu, addVariableMenu: addVariableMenu)
            Divider()
            SceneEditorPreview(controller: preview, model: model)
                .overlay(alignment: .topLeading) { WebViewportCaption(model: model).padding(12) }
                .overlay(alignment: .topTrailing) { WebNavigationGizmo(model: model) }
        }
    }

    // MARK: - Tools

    private var addLayerMenu: some View {
        Menu {
            ForEach(WallpaperScene.Layer.Kind.allCases, id: \.self) { kind in
                Button {
                    model.addLayer(kind)
                } label: {
                    Label(SceneEditorModel.defaultName(for: kind), systemImage: SceneEditorModel.symbol(for: kind))
                }
            }
        } label: {
            Label("Add Layer", systemImage: "plus")
        }
        .labelStyle(.titleAndIcon)
    }

    private var addVariableMenu: some View {
        Menu {
            ForEach(WallpaperScene.Variable.Kind.allCases, id: \.self) { kind in
                Button {
                    model.addVariable(kind)
                } label: {
                    Label(SceneEditorModel.defaultTitle(for: kind), systemImage: SceneEditorModel.symbol(for: kind))
                }
            }
        } label: {
            Label("Add Variable", systemImage: "slider.horizontal.3")
        }
        .labelStyle(.titleAndIcon)
    }

    private var undoButton: some View {
        Button(action: model.undo) {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }
        .labelStyle(.iconOnly)
        .disabled(!model.canUndo)
        .keyboardShortcut("z", modifiers: .command)
        .help("Undo")
    }

    private var redoButton: some View {
        Button(action: model.redo) {
            Label("Redo", systemImage: "arrow.uturn.forward")
        }
        .labelStyle(.iconOnly)
        .disabled(!model.canRedo)
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .help("Redo")
    }

    private var showFolderButton: some View {
        Button {
            NSWorkspace.shared.open(model.folder)
        } label: {
            Label("Show Folder", systemImage: "folder")
        }
        .help("Show Folder")
    }
}

/// The layers, the one in front first, the objects of the Wallpaper Engine scene the background
/// plays, the scene's variables, and the background below them all.
private struct LayerList: View {
    @ObservedObject var model: SceneEditorModel

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $model.selection) {
                Section("Layers") {
                    ForEach(model.layersFrontFirst) { layer in
                        row(for: layer)
                            .tag(SceneEditorItem.layer(layer.id))
                            .contextMenu {
                                Button("Duplicate") { model.duplicateLayer(layer.id) }
                                Button("Delete", role: .destructive) { model.deleteLayer(layer.id) }
                            }
                    }
                    .onMove { source, destination in
                        model.moveLayers(fromOffsets: source, toOffset: destination)
                    }
                    if model.scene.layers.isEmpty {
                        Text("No layers yet")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                if let engineScene = model.engineScene, model.scene.background.kind == .engine {
                    Section("Scene Objects") {
                        ForEach(engineScene.rows, id: \.object.id) { row in
                            self.row(for: row.object, depth: row.depth)
                                .tag(SceneEditorItem.object(row.object.id))
                                .contextMenu {
                                    Button(model.isVisible(row.object) ? LocalizedStringKey("Hide") : LocalizedStringKey("Show")) {
                                        model.toggleVisibility(of: row.object)
                                    }
                                    Button("Revert to Original") { model.revert(row.object.id) }
                                        .disabled(model.scene.background.engine[object: row.object.id].isEmpty)
                                }
                        }
                    }
                }
                if !model.scene.variables.isEmpty {
                    Section("Variables") {
                        ForEach(model.scene.variables) { variable in
                            HStack(spacing: 8) {
                                Image(systemName: SceneEditorModel.symbol(for: variable.kind))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                Text(verbatim: variable.title)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .tag(SceneEditorItem.variable(variable.id))
                            .contextMenu {
                                Button("Delete", role: .destructive) { model.delete(variable.id) }
                            }
                        }
                        .onMove { source, destination in
                            model.moveVariables(fromOffsets: source, toOffset: destination)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .onDeleteCommand {
                switch model.selection {
                case .layer(let id), .variable(let id):
                    model.delete(id)
                case .object, nil:
                    // The scene's objects are hidden, not deleted: its files stay as they came.
                    break
                }
            }
            Divider()
            Button {
                model.selection = nil
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text("Background")
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .background(model.selection == nil ? Color.accentColor.opacity(0.25) : Color.clear)
            }
            .buttonStyle(.plain)
        }
    }

    private func row(for layer: WallpaperScene.Layer) -> some View {
        HStack(spacing: 8) {
            Image(systemName: SceneEditorModel.symbol(for: layer.kind))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(layer.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .opacity(layer.isVisible ? 1 : 0.45)
            Spacer(minLength: 4)
            Button {
                model.toggleVisibility(of: layer.id)
            } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Visible")
        }
    }

    private func row(for object: EngineSceneDescription.Object, depth: Int) -> some View {
        let isVisible = model.isVisible(object)
        return HStack(spacing: 8) {
            Image(systemName: object.kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(verbatim: object.title)
                .lineLimit(1)
                .truncationMode(.middle)
                .opacity(isVisible ? 1 : 0.45)
            Spacer(minLength: 4)
            Button {
                model.toggleVisibility(of: object)
            } label: {
                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Visible")
        }
        // What hangs on an object is listed under it, a step further in.
        .padding(.leading, CGFloat(min(depth, 6)) * 14)
    }
}

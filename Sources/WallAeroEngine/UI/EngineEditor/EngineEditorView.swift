import SwiftUI
import WallpaperCore

/// The editor of a Wallpaper Engine scene: the objects on the left, the scene in the middle,
/// what is selected on the right. What there is to edit and what it is called is Wallpaper
/// Engine's; the way of working is Blender's: tools on the scene and a line saying what they do,
/// properties by topic, keys that stand for tools. Its look is that of a Mac app.
struct EngineEditorView: View {
    @ObservedObject var model: EngineEditorModel
    let preview: EngineEditorPreviewController

    var body: some View {
        layout
            .frame(minHeight: 620)
            .sheet(item: $model.sheet) { sheet in
                switch sheet {
                case .effects(let object):
                    EngineEffectGallery(model: model, object: object)
                case .animation(_, let target, let isNew, let fallback):
                    EngineAnimationOptionsSheet(model: model, target: target, isNew: isNew, fallback: fallback)
                case .events(let target):
                    EngineAnimationEventsSheet(model: model, target: target)
                }
            }
    }

    /// Laid out as Blender is: the scene in the middle with its header, tools and view controls
    /// on it and the timeline under it; on the right the outliner over the properties.
    @ViewBuilder
    private var layout: some View {
        if #available(macOS 14.0, *) {
            NavigationSplitView(columnVisibility: .constant(.detailOnly)) {
                Color.clear
                    .toolbar(removing: .sidebarToggle)
            } detail: {
                middle
                    .toolbar { toolbarContent }
            }
            .inspector(isPresented: .constant(true)) {
                side
                    .inspectorColumnWidth(min: 320, ideal: 380, max: 480)
                    .toolbar {
                        Spacer()
                        exportButton
                    }
            }
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    undoButton
                    redoButton
                    if !preview.drawsNatively { playButton }
                    Spacer()
                    exportButton.labelStyle(.titleAndIcon)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
                HStack(spacing: 0) {
                    middle
                    Divider()
                    side.frame(width: 380)
                }
            }
        }
    }

    /// The outliner over the properties, as Blender has them; the line between can be dragged.
    private var side: some View {
        VSplitView {
            hierarchy
                .frame(minHeight: 140, idealHeight: 320)
            properties
                .frame(minHeight: 240, idealHeight: 520)
        }
    }

    /// The layers, which stay in view but are not to be changed while a part of one is worked
    /// on; where that is its bones, they take the place of the layers.
    @ViewBuilder
    private var hierarchy: some View {
        if model.mode == .rig || model.mode == .weights || model.mode == .pose {
            EngineBoneList(model: model)
        } else {
            EngineHierarchy(model: model)
                .disabled(model.mode != .object)
        }
    }

    /// The properties, or what the mode has at the side.
    @ViewBuilder
    private var properties: some View {
        if let painting = model.painting {
            EngineBrushPanel(model: model, paint: painting)
        } else if model.mode.isRig {
            EngineRigPanel(model: model)
        } else {
            HStack(spacing: 0) {
                EnginePropertyTabs(model: model)
                Divider()
                EngineInspector(model: model)
            }
        }
    }

    /// The workspaces' tabs over what each shows: the scene, with the keys under it in
    /// Animation, beside the scripts in Scripting; the scene's time under them all.
    private var middle: some View {
        VStack(spacing: 0) {
            if preview.drawsNatively {
                EngineWorkspaceTabs(model: model)
                Divider()
            }
            if model.workspace == .scripting {
                HSplitView {
                    viewport
                        .frame(minWidth: 300, idealWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                    EngineScriptPanel(model: model, fillsHeight: true)
                        .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                viewport
            }
        }
        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        .bottomBar {
            VStack(spacing: 0) {
                if model.workspace == .animation {
                    EngineTimelineView(model: model)
                    Divider()
                }
                if preview.drawsNatively {
                    EngineTransportBar(model: model)
                    Divider()
                }
                statusLine
            }
        }
    }

    /// The scene with its header, and the tools and view controls on it.
    private var viewport: some View {
        let size = model.document.size
        return VStack(spacing: 0) {
            if preview.drawsNatively {
                EngineViewportHeader(model: model, addMenu: addMenu)
                Divider()
            }
            EngineEditorPreview(model: model, controller: preview, aspectRatio: size.height > 0 ? size.width / size.height : 16 / 9)
                .overlay(alignment: .topLeading) {
                    if preview.drawsNatively {
                        HStack(alignment: .top, spacing: 0) {
                            if !model.mode.tools.isEmpty { EngineToolStrip(model: model) }
                            EngineViewportCaption(model: model)
                                .padding(.top, 12)
                                .padding(.leading, model.mode.tools.isEmpty ? 12 : 2)
                        }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if preview.drawsNatively { EngineNavigationGizmo(model: model) }
                }
        }
    }

    /// The panels under the scene, and how the scene is shown. What a tool does is said when the
    /// pointer rests on it.
    private var statusLine: some View {
        HStack(spacing: SystemLook.barSpacing) {
            Spacer(minLength: SystemLook.barSpacing)
            Text(verbatim: "\(Int(model.document.size.width)) × \(Int(model.document.size.height))")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if preview.drawsNatively {
                Button {
                    model.fitView()
                } label: {
                    Text(verbatim: "\(Int((model.viewZoom * 100).rounded()))%")
                        .monospacedDigit()
                }
                .barButtonStyle()
                .disabled(model.viewZoom == 1)
                .help("Fit in Window (Home)")
            }
        }
        .font(.callout)
        .barPadding()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // The mode and what is added are in the scene's own header, as in Blender.
        if !preview.drawsNatively {
            ToolbarItemGroup {
                addMenu
            }
        }
        ToolbarItemGroup {
            undoButton
            redoButton
        }
        // The scene's time is played from the bar under it, where the scene is drawn by the app.
        if !preview.drawsNatively {
            ToolbarItemGroup {
                playButton
            }
        }
    }

    private var addMenu: some View {
        Menu {
            Button { model.addPicture() } label: { Label("Image…", systemImage: "photo") }
            Button { model.addVideo() } label: { Label("Video…", systemImage: "film") }
            Button { model.addText() } label: { Label("Text", systemImage: "textformat") }
            Button { model.addSolid() } label: { Label("Solid Color", systemImage: "square.fill") }
            Divider()
            Menu {
                ForEach(WallpaperEngineParticlePreset.all) { preset in
                    Button { model.addParticles(preset) } label: { Label(preset.title, systemImage: preset.symbol) }
                }
            } label: {
                Label("Particles", systemImage: "sparkles")
            }
            Button { model.addSound() } label: { Label("Sound…", systemImage: "speaker.wave.2") }
            Menu {
                ForEach(WallpaperEngineDocument.LightKind.allCases, id: \.self) { kind in
                    Button(EngineEditorModel.lightTitle(kind)) { model.addLight(kind) }
                }
            } label: {
                Label("Light Source", systemImage: "lightbulb")
            }
            Button { model.addCamera() } label: { Label("Camera", systemImage: "video") }
            Divider()
            Button { model.addComposition() } label: { Label("Composition Layer", systemImage: "square.stack.3d.up") }
            Button { model.addGroup() } label: { Label("Group", systemImage: "square.dashed") }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .labelStyle(.titleAndIcon)
        .disabled(model.mode != .object)
        .help("Add an object to the scene")
    }

    private var undoButton: some View {
        Button(action: model.undo) {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }
        .labelStyle(.iconOnly)
        .disabled(!model.canUndo && !model.showsScripts)
        .keyboardShortcut("z", modifiers: .command)
        .help("Undo")
    }

    private var redoButton: some View {
        Button(action: model.redo) {
            Label("Redo", systemImage: "arrow.uturn.forward")
        }
        .labelStyle(.iconOnly)
        .disabled(!model.canRedo && !model.showsScripts)
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .help("Redo")
    }

    private var playButton: some View {
        Button {
            model.isPlaying.toggle()
        } label: {
            Label(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill")
        }
        .labelStyle(.iconOnly)
        .help(model.isPlaying ? "Pause" : "Play")
    }

    private var exportButton: some View {
        Menu {
            Button("Export for Wallpaper Engine…") { EngineExport.exportFolder(model) }
            Button("Export as ZIP Archive…") { EngineExport.exportArchive(model) }
            Divider()
            Button("Show Project in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.projectFolder]) }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .help("Export the scene so that Wallpaper Engine opens it")
    }
}

/// The tools that say what a drag over the scene does, standing on the scene.
private struct EngineToolStrip: View {
    @ObservedObject var model: EngineEditorModel

    var body: some View {
        VStack(spacing: 2) {
            ForEach(model.mode.tools, id: \.self) { tool in
                Button {
                    model.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 30, height: 30)
                        .foregroundStyle(tool == model.tool ? Color.white : Color.primary)
                        .background(tool == model.tool ? Color.accentColor : Color.clear,
                                    in: RoundedRectangle(cornerRadius: SystemLook.innerCornerRadius, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text(tool.title) + Text(verbatim: "\n") + Text(hint(for: tool)))
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: SystemLook.insetCornerRadius, style: .continuous))
        .padding(10)
    }

    /// What a drag over the scene does with the tool, in the mode the editor is in.
    private func hint(for tool: EngineEditorModel.Tool) -> LocalizedStringKey {
        switch model.mode {
        case .mesh: return "Drag corners of the mesh, or a box round several. X deletes those selected."
        case .pose: return tool == .move ? "Drag a bone to move it. Moving bends a picture more than turning." : "Drag a bone to turn it about its joint. Shift turns by 15°."
        case .rig where tool == .multi: return "Drag a joint, an end or a whole bone. X deletes the selected one."
        default: return tool.hint
        }
    }
}

// MARK: - The objects

/// The scene at the head of its objects, the one in front first, with what hangs on each under it.
struct EngineHierarchy: View {
    @ObservedObject var model: EngineEditorModel
    @State private var renaming: Int?
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $model.layerFilter, prompt: NSLocalizedString("Find a Layer", comment: "Placeholder"))
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 8)
            sceneRow
            Divider()
            List(selection: $model.selection) {
                Section("Layers") {
                    ForEach(model.shownRows, id: \.id) { row in
                        self.row(row.id, depth: row.depth)
                            .tag(Optional(row.id))
                    }
                    .onMove(perform: model.layerFilter.isEmpty ? { source, destination in
                        model.moveRows(fromOffsets: source, toOffset: destination)
                    } : nil)
                    if model.document.objects.isEmpty {
                        Text("Add a picture, text or particles with the + button.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)
            // Made when it is opened: one menu per row, each naming every layer to move into,
            // kept a scene of hundreds of objects from ever being shown.
            .contextMenu(forSelectionType: Int?.self) { ids in
                if ids.count == 1, let id = ids.first ?? nil { menu(for: id) }
            }
            .onDeleteCommand {
                if let selection = model.selection { model.delete(selection) }
            }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let renaming { model.rename(renaming, to: newName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private var sceneRow: some View {
        Button {
            model.selection = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text("Scene")
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(model.selection == nil ? Color.accentColor.opacity(0.25) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func row(_ id: Int, depth: Int) -> some View {
        let visible = model.isVisible(id)
        return HStack(spacing: 8) {
            Image(systemName: EngineEditorModel.symbol(model.kind(of: id)))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(verbatim: model.name(of: id))
                .lineLimit(1)
                .truncationMode(.middle)
                .opacity(visible ? 1 : 0.45)
            Spacer(minLength: 4)
            Button {
                model.toggleVisibility(of: id)
            } label: {
                Image(systemName: visible ? "eye" : "eye.slash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Visible")
        }
        .padding(.leading, CGFloat(min(depth, 6)) * 14)
    }

    @ViewBuilder
    private func menu(for id: Int) -> some View {
        Button("Rename…") {
            newName = model.name(of: id)
            renaming = id
        }
        Button("Duplicate") { model.duplicate(id) }
        Divider()
        Button("Bring Forward") { model.move(id, forward: true) }
        Button("Send Backward") { model.move(id, forward: false) }
        Menu("Move Into") {
            let holders = model.rows.map(\.id).filter { other in
                other != id && !model.isInside(other, id) && [.composition, .group, .image, .solid].contains(model.kind(of: other))
            }
            ForEach(holders, id: \.self) { other in
                Button(model.name(of: other)) { model.setParent(of: id, to: other) }
            }
        }
        if model.document.parent(of: id) != nil {
            Button("Move Out") { model.setParent(of: id, to: nil) }
        }
        Divider()
        Button("Delete", role: .destructive) { model.delete(id) }
    }
}

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

    @ViewBuilder
    private var layout: some View {
        if #available(macOS 14.0, *) {
            NavigationSplitView(columnVisibility: .constant(.all)) {
                hierarchy
                    .toolbar(removing: .sidebarToggle)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 340)
            } detail: {
                middle
                    .toolbar { toolbarContent }
            }
            .inspector(isPresented: showsInspector) {
                inspector
                    .inspectorColumnWidth(min: 320, ideal: 360, max: 440)
                    .toolbar {
                        Spacer()
                        exportButton
                    }
            }
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    addMenu.fixedSize()
                    undoButton
                    redoButton
                    playButton
                    Spacer()
                    exportButton.labelStyle(.titleAndIcon)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider()
                HStack(spacing: 0) {
                    hierarchy.frame(width: 240)
                    Divider()
                    middle
                    if showsInspector.wrappedValue {
                        Divider()
                        inspector.frame(width: 360)
                    }
                }
            }
        }
    }

    /// While a puppet warp is edited or a mask painted, the layers stay in view but are not to
    /// be changed.
    private var hierarchy: some View {
        EngineHierarchy(model: model)
            .disabled(model.puppetObject != nil || model.painting != nil)
    }

    /// The properties, or the brush while a mask is painted.
    @ViewBuilder
    private var inspector: some View {
        if let painting = model.painting {
            EngineBrushPanel(model: model, paint: painting)
        } else {
            EngineInspector(model: model)
        }
    }

    /// The puppet warp has a panel of its own, so it takes the place of the properties too.
    private var showsInspector: Binding<Bool> {
        Binding(get: { model.puppetObject == nil }, set: { _ in })
    }

    /// The scene, which stays where it is under a puppet warp being edited.
    private var middle: some View {
        ZStack {
            canvas
            if let object = model.puppetObject {
                EnginePuppetEditor(model: model, object: object)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .id(object)
            }
        }
    }

    private var canvas: some View {
        let size = model.document.size
        return EngineEditorPreview(model: model, controller: preview, aspectRatio: size.height > 0 ? size.width / size.height : 16 / 9)
            .overlay(alignment: .topLeading) {
                if preview.drawsNatively, model.painting == nil {
                    EngineToolStrip(model: model)
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            .bottomBar {
                VStack(spacing: 0) {
                    if model.showsTimeline {
                        EngineTimelineView(model: model)
                        Divider()
                    }
                    if model.showsScripts {
                        EngineScriptPanel(model: model)
                        Divider()
                    }
                    statusLine
                }
            }
    }

    /// What the tool in hand does, and how the scene is shown.
    private var statusLine: some View {
        HStack(spacing: 12) {
            if preview.drawsNatively {
                Text(model.painting == nil ? model.tool.hint : "Paint over the object. Control and drag changes the size, Shift and drag the opacity.")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if preview.drawsNatively {
                Toggle(isOn: $model.showsTimeline) {
                    Label("Timeline", systemImage: "timeline.selection")
                }
                .toggleStyle(.button)
                .help("Timeline (T)")
                Toggle(isOn: $model.showsScripts) {
                    Label("Scripts", systemImage: "curlybraces")
                }
                .toggleStyle(.button)
                .help("Scripts of the selection")
            }
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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            addMenu
        }
        ToolbarItemGroup {
            undoButton
            redoButton
        }
        ToolbarItemGroup {
            playButton
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
        .disabled(model.puppetObject != nil || model.painting != nil)
        .help("Add an object to the scene")
    }

    private var undoButton: some View {
        Button(action: model.undo) {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }
        .labelStyle(.iconOnly)
        .disabled((!model.canUndo && !model.showsScripts) || model.puppetObject != nil)
        .keyboardShortcut("z", modifiers: .command)
        .help("Undo")
    }

    private var redoButton: some View {
        Button(action: model.redo) {
            Label("Redo", systemImage: "arrow.uturn.forward")
        }
        .labelStyle(.iconOnly)
        .disabled((!model.canRedo && !model.showsScripts) || model.puppetObject != nil)
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
            ForEach(EngineEditorModel.Tool.allCases, id: \.self) { tool in
                Button {
                    model.tool = tool
                } label: {
                    Image(systemName: tool.symbol)
                        .frame(width: 30, height: 30)
                        .foregroundStyle(tool == model.tool ? Color.white : Color.primary)
                        .background(tool == model.tool ? Color.accentColor : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tool.title)
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(10)
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
                            .contextMenu { menu(for: row.id) }
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

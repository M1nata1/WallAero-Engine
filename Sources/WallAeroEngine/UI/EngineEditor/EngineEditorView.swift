import SwiftUI
import WallpaperCore

/// The editor of a Wallpaper Engine scene: the objects on the left, the scene in the middle,
/// what is selected on the right — as Wallpaper Engine's own editor lays them out, in the
/// manner of a Mac app.
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
                case .particles(let object):
                    EngineParticleEditor(model: model, object: object)
                case .puppet(let object):
                    EnginePuppetEditor(model: model, object: object)
                }
            }
    }

    @ViewBuilder
    private var layout: some View {
        if #available(macOS 14.0, *) {
            NavigationSplitView(columnVisibility: .constant(.all)) {
                EngineHierarchy(model: model)
                    .toolbar(removing: .sidebarToggle)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 340)
            } detail: {
                canvas
                    .toolbar { toolbarContent }
            }
            .inspector(isPresented: .constant(true)) {
                EngineInspector(model: model)
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 440)
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
                    EngineHierarchy(model: model).frame(width: 240)
                    Divider()
                    canvas
                    Divider()
                    EngineInspector(model: model).frame(width: 340)
                }
            }
        }
    }

    private var canvas: some View {
        let size = model.document.size
        return EngineEditorPreview(controller: preview, aspectRatio: size.height > 0 ? size.width / size.height : 16 / 9)
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
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
        .help("Add an object to the scene")
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

// MARK: - The objects

/// The scene's objects, the one in front first, with what hangs on each under it.
struct EngineHierarchy: View {
    @ObservedObject var model: EngineEditorModel
    @State private var renaming: Int?
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $model.selection) {
                Section("Layers") {
                    ForEach(model.rows, id: \.id) { row in
                        self.row(row.id, depth: row.depth)
                            .tag(Optional(row.id))
                            .contextMenu { menu(for: row.id) }
                    }
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
            Divider()
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
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let renaming { model.rename(renaming, to: newName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
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

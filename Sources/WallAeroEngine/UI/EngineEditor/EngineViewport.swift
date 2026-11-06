import SwiftUI
import WallpaperCore

/// The header of the scene, as Blender's 3D view has it: the mode, then the menus of the view,
/// of selecting, of adding and of the object; at its end how the scene is looked at.
struct EngineViewportHeader<Add: View>: View {
    @ObservedObject var model: EngineEditorModel
    let addMenu: Add

    /// All of it where there is room; where there is not, as in Scripting's narrow column, the
    /// mode, the view and how it is looked at.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            full
            compact
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private var compact: some View {
        HStack(spacing: 10) {
            EngineModeMenu(model: model)
                .menuStyle(.borderlessButton)
                .labelStyle(.iconOnly)
            viewMenu
            Spacer(minLength: 4)
            Picker("", selection: Binding(get: { model.viewsFreely }, set: { model.setViewsFreely($0) })) {
                Image(systemName: "video").tag(false)
                Image(systemName: "move.3d").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Look through the scene's camera, as the wallpaper shows it, or freely (0)")
        }
    }

    private var full: some View {
        HStack(spacing: 14) {
            EngineModeMenu(model: model)
                .menuStyle(.borderlessButton)
            viewMenu
            selectMenu
            addMenu
                .labelStyle(.titleOnly)
                .menuStyle(.borderlessButton)
                .fixedSize()
            objectMenu
            Spacer(minLength: 8)
            if model.viewsFreely, model.isInDepth, model.movesIn3D {
                Button { model.alignCameraToView() } label: {
                    Label("Camera to View", systemImage: "camera.viewfinder")
                }
                .buttonStyle(.borderless)
                .disabled(!model.canAlignCamera)
                .help(model.canAlignCamera ? "Put the camera where the view is (Control-Option-0)"
                                           : "The camera hangs on another object or is moved by a script")
            }
            // Unity's 2D button: how the free view moves.
            Toggle(isOn: Binding(get: { !model.movesIn3D }, set: { model.setViewIn3D(!$0) })) {
                Text(verbatim: "2D").fontWeight(.semibold)
            }
            .toggleStyle(.button)
            .help("2D: the free view moves and zooms, flat. Off: it turns about in depth.")
            Picker("", selection: Binding(get: { model.viewsFreely }, set: { model.setViewsFreely($0) })) {
                Label("Camera View", systemImage: "video").tag(false)
                Label("Free View", systemImage: "move.3d").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Look through the scene's camera, as the wallpaper shows it, or freely (0)")
        }
    }

    private var viewMenu: some View {
        Menu("View") {
            Toggle("Camera View", isOn: Binding(get: { !model.viewsFreely }, set: { model.setViewsFreely(!$0) }))
            Button("Frame All") { model.fitView() }
            Button("Zoom In") { zoom(1.25) }
            Button("Zoom Out") { zoom(0.8) }
            Toggle("2D View", isOn: Binding(get: { !model.movesIn3D }, set: { model.setViewIn3D(!$0) }))
            if model.viewsFreely, model.isInDepth, model.movesIn3D {
                Divider()
                Button("Align Camera to View") { model.alignCameraToView() }
                    .disabled(!model.canAlignCamera)
            }
            Divider()
            Picker("Workspace", selection: $model.workspace) {
                ForEach(EngineEditorModel.Workspace.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
            }
            Divider()
            Button(model.isPlaying ? "Pause" : "Play") { model.isPlaying.toggle() }
            Button("Jump to Start") { model.jumpToStart() }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func zoom(_ factor: CGFloat) {
        model.navigateZoom(by: factor, around: .zero)
    }

    private var selectMenu: some View {
        Menu("Select") {
            Button("None") { model.selection = nil }
            Button("Parent") {
                if let id = model.selection { model.selection = model.document.parent(of: id) }
            }
            .disabled(model.selection.flatMap { model.document.parent(of: $0) } == nil)
            Button("Child") {
                if let id = model.selection { model.selection = model.document.children(of: id).first }
            }
            .disabled(model.selection.map { model.document.children(of: $0).isEmpty } ?? true)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.mode != .object)
    }

    private var objectMenu: some View {
        Menu("Object") {
            if let id = model.selection {
                Button("Duplicate") { model.duplicate(id) }
                Button(model.isVisible(id) ? "Hide" : "Show") { model.toggleVisibility(of: id) }
                Divider()
                Button("Bring Forward") { model.move(id, forward: true) }
                Button("Send Backward") { model.move(id, forward: false) }
                Divider()
                Button("Delete", role: .destructive) { model.delete(id) }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.selection == nil || model.mode != .object)
    }
}

/// What the scene is looked at as and what is selected, in its top corner as Blender says it:
/// the view, then the frame, the scene and the object.
struct EngineViewportCaption: View {
    @ObservedObject var model: EngineEditorModel

    private var viewTitle: LocalizedStringKey {
        if !model.viewsFreely { return "Camera View" }
        return model.movesIn3D ? "User Perspective" : "User Orthographic"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewTitle)
            Text(verbatim: "(\(Int((model.timelineSeconds * model.timelineRate).rounded()))) " + caption)
        }
        .font(.callout)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.8), radius: 2)
        .allowsHitTesting(false)
    }

    private var caption: String {
        let scene = NSLocalizedString("Scene", comment: "The scene in the viewport's caption")
        guard let id = model.selection, model.document.object(id) != nil else { return scene }
        return scene + " | " + model.name(of: id)
    }
}

/// The buttons in the scene's other top corner, as Blender's: drag the magnifier to come
/// nearer, the hand to move the view, the turning arrows (looking freely in three dimensions)
/// to turn about; the camera looks through the scene's camera or freely.
struct EngineNavigationGizmo: View {
    @ObservedObject var model: EngineEditorModel
    @State private var last: CGSize = .zero

    private var size: CGSize { model.preview?.view.bounds.size ?? CGSize(width: 800, height: 500) }

    var body: some View {
        VStack(spacing: 6) {
            if model.viewsFreely, model.movesIn3D {
                dragged("rotate.3d", help: "Drag to turn the view about") {
                    model.navigate(by: $0, moving: false, within: size)
                }
            }
            dragged("plus.magnifyingglass", help: "Drag to zoom the view") { distance in
                model.navigateZoom(by: pow(1.01, -distance.height), around: .zero)
            }
            dragged("hand.raised", help: "Drag to move the view") { distance in
                model.navigate(by: distance, moving: true, within: size)
            }
            Button { model.toggleCameraView() } label: {
                circle(model.viewsFreely ? "video" : "video.fill", lit: !model.viewsFreely)
            }
            .buttonStyle(.plain)
            .help("Look through the scene's camera, as the wallpaper shows it, or freely (0)")
        }
        .padding(12)
    }

    private func circle(_ symbol: String, lit: Bool = false) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .frame(width: 30, height: 30)
            .foregroundStyle(lit ? Color.white : Color.primary)
            .background(lit ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.regularMaterial), in: Circle())
            .contentShape(Circle())
    }

    private func dragged(_ symbol: String, help: LocalizedStringKey, by: @escaping (CGSize) -> Void) -> some View {
        circle(symbol)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    by(CGSize(width: drag.translation.width - last.width, height: drag.translation.height - last.height))
                    last = drag.translation
                }
                .onEnded { _ in last = .zero })
            .help(help)
    }
}

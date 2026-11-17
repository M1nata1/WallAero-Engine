import AppKit
import SwiftUI
import WallpaperCore

/// The workspaces as Blender's tabs along the top: Layout, and Scripting for the page's code.
struct SceneWorkspaceTabs: View {
    @ObservedObject var model: SceneEditorModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SceneEditorModel.Workspace.allCases, id: \.self) { workspace in
                let chosen = model.workspace == workspace
                Button {
                    model.workspace = workspace
                    if workspace == .scripting { model.findCodeFiles() }
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

/// The header of the page, as Blender's 3D view has it: the view, what can be added, and how
/// the page is looked at.
struct WebViewportHeader<AddLayer: View, AddVariable: View>: View {
    @ObservedObject var model: SceneEditorModel
    let addLayerMenu: AddLayer
    let addVariableMenu: AddVariable

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                viewMenu
                addLayerMenu.menuStyle(.borderlessButton).fixedSize()
                addVariableMenu.menuStyle(.borderlessButton).fixedSize()
                Spacer(minLength: 8)
                dimension
                lookPicker
            }
            HStack(spacing: 10) {
                viewMenu
                Spacer(minLength: 4)
                lookPicker
            }
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private var viewMenu: some View {
        Menu("View") {
            Toggle("Camera View", isOn: Binding(get: { !model.viewsFreely }, set: { model.setViewsFreely(!$0) }))
            Toggle("2D View", isOn: Binding(get: { !model.viewIn3D }, set: { model.setViewIn3D(!$0) }))
            Button("Frame All") { model.fitView() }
            Button("Zoom In") { model.navigateZoom(by: 1.25, around: .zero) }
            Button("Zoom Out") { model.navigateZoom(by: 0.8, around: .zero) }
            Divider()
            Picker("Workspace", selection: $model.workspace) {
                ForEach(SceneEditorModel.Workspace.allCases, id: \.self) { Text(verbatim: $0.title).tag($0) }
            }
            Divider()
            Button(model.isPlaying ? "Pause" : "Play") { model.isPlaying.toggle() }
            Button("Jump to Start") { model.timelineSeconds = 0 }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var dimension: some View {
        Toggle(isOn: Binding(get: { !model.viewIn3D }, set: { model.setViewIn3D(!$0) })) {
            Text(verbatim: "2D").fontWeight(.semibold)
        }
        .toggleStyle(.button)
        .help("2D: the free view moves and zooms, flat. Off: it turns about in depth.")
    }

    private var lookPicker: some View {
        Picker("", selection: Binding(get: { model.viewsFreely }, set: { model.setViewsFreely($0) })) {
            Label("Camera View", systemImage: "video").tag(false)
            Label("Free View", systemImage: "move.3d").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Look at the page as the wallpaper shows it, or freely (0)")
    }
}

/// How the page is looked at and what is selected, in its top corner as Blender says it.
struct WebViewportCaption: View {
    @ObservedObject var model: SceneEditorModel

    private var viewTitle: LocalizedStringKey {
        if !model.viewsFreely { return "Camera View" }
        return model.viewIn3D ? "User Perspective" : "User Orthographic"
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
        switch model.selection {
        case .layer(let id):
            return model.scene.layers.first { $0.id == id }?.name ?? ""
        case .variable(let id):
            return model.scene.variables.first { $0.id == id }?.title ?? ""
        case .object(let id):
            return model.engineScene?.object(id)?.title ?? ""
        case nil:
            return NSLocalizedString("Background", comment: "The page in the viewport's caption")
        }
    }
}

/// The buttons in the page's other top corner, as Blender's: drag the magnifier to come
/// nearer, the hand to move the view, the turning arrows (in depth) to turn the page about;
/// the camera looks as the wallpaper shows or freely.
struct WebNavigationGizmo: View {
    @ObservedObject var model: SceneEditorModel
    @State private var last: CGSize = .zero
    private let size = CGSize(width: 2000, height: 1200)

    var body: some View {
        VStack(spacing: 6) {
            if model.showsCard {
                dragged("rotate.3d", help: "Drag to turn the view about") { model.navigate(by: $0, moving: false, within: size) }
            }
            dragged("plus.magnifyingglass", help: "Drag to zoom the view") { model.navigateZoom(by: pow(1.01, -$0.height), around: .zero) }
            dragged("hand.raised", help: "Drag to move the view") { model.navigate(by: $0, moving: true, within: size) }
            Button { model.setViewsFreely(!model.viewsFreely) } label: {
                circle(model.viewsFreely ? "video" : "video.fill", lit: !model.viewsFreely)
            }
            .buttonStyle(.plain)
            .help("Look at the page as the wallpaper shows it, or freely (0)")
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

/// The page's code, as Blender's text editor in Scripting: its files on the left, the one open
/// on the right. ⌘S writes it, and the page is loaded anew at the timeline's moment.
struct WebCodeEditor: View {
    @ObservedObject var model: SceneEditorModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Files").font(.headline)
                    Spacer()
                }
                .padding(10)
                Divider()
                List(selection: Binding(get: { model.codeFile }, set: { model.openCode($0) })) {
                    ForEach(model.codeFiles, id: \.self) { path in
                        Label {
                            Text(verbatim: path).lineLimit(1).truncationMode(.head)
                        } icon: {
                            Image(systemName: Self.symbol(path))
                        }
                        .help(path)
                        .tag(Optional(path))
                    }
                }
                .listStyle(.plain)
            }
            .frame(width: 190)
            Divider()
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text(verbatim: model.codeFile ?? "")
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.head)
                    if model.codeChanged {
                        Circle().fill(Color.secondary).frame(width: 6, height: 6)
                            .help("Not written yet")
                    }
                    Spacer()
                    Button("Revert") { model.revertCode() }
                        .disabled(!model.codeChanged)
                    Button("Save") { model.saveCode() }
                        .keyboardShortcut("s", modifiers: .command)
                        .disabled(!model.codeChanged)
                        .help("Write the file; the page loads anew at the timeline's moment (⌘S)")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 10)
                .frame(height: 38)
                Divider()
                if model.codeFile != nil {
                    WebCodeText(text: $model.codeDraft)
                } else {
                    Text("This wallpaper has no code of its own to write.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let problem = model.codeProblem {
                    Divider()
                    Text(verbatim: problem)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }
        }
        .onAppear { model.findCodeFiles() }
    }

    private static func symbol(_ path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "html", "htm": return "chevron.left.forwardslash.chevron.right"
        case "js", "mjs": return "curlybraces"
        case "css": return "paintbrush"
        case "json": return "doc.text"
        default: return "doc.plaintext"
        }
    }
}

/// The text of a file of the page, with line numbers and the colors of a script.
private struct WebCodeText: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = EngineScriptTextView(frame: scroll.bounds)
        view.autoresizingMask = [.width]
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.textContainerInset = NSSize(width: 4, height: 4)
        view.font = EngineScriptTextView.font
        view.isRichText = false
        view.allowsUndo = true
        view.usesFindBar = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.smartInsertDeleteEnabled = false
        view.textColor = .labelColor
        view.backgroundColor = .textBackgroundColor
        view.delegate = context.coordinator
        scroll.documentView = view
        scroll.drawsBackground = true
        scroll.hasVerticalRuler = true
        scroll.verticalRulerView = EngineScriptRuler(text: view, scroll: scroll)
        scroll.rulersVisible = true
        view.string = text
        view.showColors(problemLine: nil)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? EngineScriptTextView, view.string != text else { return }
        view.string = text
        view.undoManager?.removeAllActions(withTarget: view.textStorage as Any)
        view.showColors(problemLine: nil)
        scroll.verticalRulerView?.needsDisplay = true
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? EngineScriptTextView else { return }
            text.wrappedValue = view.string
            view.showColors(problemLine: nil)
            view.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
    }
}

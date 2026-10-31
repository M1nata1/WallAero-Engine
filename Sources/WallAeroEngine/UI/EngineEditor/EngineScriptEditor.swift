import AppKit
import SwiftUI
import WallpaperCore

/// What went wrong with a script: in reading it, or in running it.
struct EngineScriptProblem: Equatable {
    var message: String
    /// The line of the script, from 1; 0 if nobody knows.
    var line: Int
    /// The function it happened in, for one that happened while running.
    var during: String?
}

/// The scripts of a scene, as Wallpaper Engine has them: a script stands behind a value of an
/// object, of an effect or of the scene. What is typed is a draft until it is applied, which
/// reads it first; the scene is played anew with it.
extension EngineEditorModel {
    typealias ScriptTarget = WallpaperEngineScriptTarget

    /// The scripts of the selected object, or of the scene.
    var scriptTargets: [ScriptTarget] {
        selection.map(document.scriptTargets(of:)) ?? document.sceneScriptTargets
    }

    /// What of the selection can be given a script.
    var scriptOffers: [ScriptTarget] {
        var offers: [ScriptTarget] = []
        if let id = selection {
            var keys = ["visible", "origin", "scale", "angles"]
            if [.image, .solid, .text].contains(kind(of: id)) { keys += ["alpha", "color"] }
            if kind(of: id) == .text { keys += ["text", "pointsize"] }
            offers = keys.map { .value(object: id, key: $0) }
            for effect in description?.object(id)?.effects ?? [] {
                offers += effect.values.map { .effect(object: id, index: effect.id, pass: effectPass(of: $0.name, in: effect.id, object: id), name: $0.name) }
            }
        } else {
            offers = ["bloomstrength", "bloomthreshold", "ambientcolor", "skylightcolor", "fov"].map { .general($0) }
        }
        return offers.filter { document.script(of: $0) == nil }
    }

    private func effectPass(of name: String, in effect: Int, object: Int) -> Int {
        let passes = document.object(object)?["effects"]?[effect]?["passes"]?.arrayValue ?? []
        return passes.firstIndex { $0["constantshadervalues"]?[name] != nil } ?? 0
    }

    func title(of target: ScriptTarget) -> String {
        switch target {
        case .value(_, let key):
            let titles = ["origin": "Position", "scale": "Scale", "angles": "Rotation", "alpha": "Opacity", "color": "Color", "visible": "Visible",
                          "text": "Text", "pointsize": "Font Size"]
            return titles[key].map { NSLocalizedString($0, comment: "A value of an object a script stands behind") } ?? key
        case .effect(let object, let index, _, let name):
            guard let effect = description?.object(object)?.effects.first(where: { $0.id == index }) else { return name }
            return "\(effect.title): \(effect.values.first { $0.name == name }?.title ?? name)"
        case .general(let key):
            let titles = ["bloomstrength": "Bloom Strength", "bloomthreshold": "Bloom Threshold", "ambientcolor": "Ambient Color",
                          "skylightcolor": "Sky Color", "fov": "Field of View"]
            return titles[key].map { NSLocalizedString($0, comment: "A value of the scene a script stands behind") } ?? key
        }
    }

    /// The type a script of this value gets and gives, as the documentation names it.
    func scriptType(of target: ScriptTarget) -> String {
        switch target {
        case .value(_, let key):
            switch key {
            case "origin", "scale", "angles", "color": return "Vec3"
            case "visible": return "Boolean"
            case "text": return "String"
            default: return "Number"
            }
        case .effect(let object, let index, _, let name):
            let value = description?.object(object)?.effects.first { $0.id == index }?.values.first { $0.name == name }
            return [2: "Vec2", 3: "Vec3", 4: "Vec4"][value?.count ?? 1] ?? "Number"
        case .general(let key):
            return key.hasSuffix("color") ? "Vec3" : "Number"
        }
    }

    private func scriptKey(of target: ScriptTarget) -> String {
        switch target {
        case .value(_, let key), .general(let key): return key
        case .effect(_, _, _, let name): return name
        }
    }

    /// What a value is when the scene does not write it down.
    private func scriptFallback(of target: ScriptTarget) -> JSONValue {
        switch scriptType(of: target) {
        case "Boolean": return .bool(true)
        case "String": return .string("")
        case "Number": return .number(scriptKey(of: target) == "alpha" ? 1 : 0)
        case "Vec2": return .string("0 0")
        case "Vec4": return .string("0 0 0 0")
        default: return .string(scriptKey(of: target) == "scale" || scriptKey(of: target) == "color" ? "1 1 1" : "0 0 0")
        }
    }

    /// A script runs as it was when the scene started, so that the scene starts anew with this.
    private func changeScripts(_ body: (inout WallpaperEngineDocument) -> Void) {
        playAnew(body)
    }

    /// A change the player cannot follow as it plays.
    func playAnew(_ body: (inout WallpaperEngineDocument) -> Void) {
        preview?.playsAnewOnNextChange = true
        change(body)
        preview?.playsAnewOnNextChange = false
    }

    func setEffectSwitch(_ item: EngineSceneDescription.Switch, to value: Double, object: Int, effect: Int) {
        playAnew { $0.setEffectCombo(item.name, to: value, object: object, effect: effect, passes: item.passes) }
    }

    /// Another object was selected: its first script is opened.
    func scriptsDidChangeObject() {
        guard showsScripts else { return }
        openScript(scriptTargets.first)
    }

    /// What was typed goes in with the next script, if it can be read; if not, it waits.
    private func leaveScript() {
        guard let target = scriptTarget, scriptIsChanged else { return }
        if preview?.checkScript(scriptDraft) == nil {
            changeScripts { $0.setScript(scriptDraft, of: target, fallback: scriptFallback(of: target)) }
            scriptDrafts[target] = nil
        } else {
            scriptDrafts[target] = scriptDraft
        }
    }

    var scriptIsChanged: Bool {
        scriptTarget.map { document.script(of: $0) != scriptDraft } ?? false
    }

    func openScript(_ target: ScriptTarget?) {
        if target != scriptTarget { leaveScript() }
        scriptTarget = target
        scriptDraft = target.flatMap { scriptDrafts[$0] ?? document.script(of: $0) } ?? ""
        scriptProblem = target == nil ? nil : preview?.checkScript(scriptDraft)
        scriptLog = []
        readScriptSettings()
    }

    /// Gives a value a script: a new one, or one ready made.
    func addScript(_ target: ScriptTarget, text: String? = nil) {
        let text = text ?? WallpaperEngineScriptText.template(type: scriptType(of: target), key: scriptKey(of: target))
        leaveScript()
        changeScripts { $0.setScript(text, of: target, fallback: scriptFallback(of: target)) }
        showsScripts = true
        openScript(target)
    }

    /// Reads what was typed and, if it can be read, gives it to the scene.
    @discardableResult
    func applyScript() -> Bool {
        guard let target = scriptTarget else { return false }
        scriptProblem = preview?.checkScript(scriptDraft)
        guard scriptProblem == nil else { return false }
        scriptDrafts[target] = nil
        changeScripts { $0.setScript(scriptDraft, of: target, fallback: scriptFallback(of: target)) }
        scriptLog = []
        readScriptSettings()
        return true
    }

    func revertScript() {
        guard let target = scriptTarget else { return }
        scriptDrafts[target] = nil
        scriptDraft = document.script(of: target) ?? ""
        scriptProblem = nil
        readScriptSettings()
    }

    func removeScript() {
        guard let target = scriptTarget else { return }
        scriptDrafts[target] = nil
        changeScripts { $0.removeScript(of: target) }
        scriptTarget = nil
        openScript(scriptTargets.first)
    }

    func readScriptSettings() {
        guard let target = scriptTarget else {
            scriptSettings = []
            return
        }
        scriptSettings = (preview?.scriptDeclares(scriptDraft) ?? []).compactMap(WallpaperEngineScriptSetting.init)
        scriptValues = [:]
        for setting in scriptSettings {
            if let given = document.scriptProperty(setting.name, of: target) { scriptValues[setting.name] = given.plain }
        }
    }

    /// A setting of the script changed. The scene is played anew with it once it stops changing.
    func setScriptValue(_ name: String, to value: JSONValue) {
        scriptValues[name] = value
        guard let target = scriptTarget else { return }
        scriptValueTask?.cancel()
        scriptValueTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else { return }
            self.changeScripts { document in
                for (name, value) in self.scriptValues where document.scriptProperty(name, of: target)?.plain != value {
                    document.setScriptProperty(name, to: value, of: target)
                }
            }
        }
    }

    /// What happened to the script open while the scene ran, and what scripts wrote.
    func readScriptReport() {
        guard let report = preview?.scriptReport() else { return }
        if !report.log.isEmpty {
            scriptLog.append(contentsOf: report.log)
            if scriptLog.count > 200 { scriptLog.removeFirst(scriptLog.count - 200) }
        }
        guard !scriptIsChanged, let target = scriptTarget, let text = document.script(of: target) else { return }
        if let found = report.errors[text], found != scriptProblem { scriptProblem = found }
    }

    /// Puts a ready-made script in place of what is there, as one step of typing.
    func useExample(_ example: WallpaperEngineScriptText.Example) {
        scriptView?.replaceAll(with: example.text)
    }

    /// Adds a setting to the script, under a name it does not have yet.
    func addScriptSetting(_ kind: WallpaperEngineScriptSetting.Kind) {
        var number = 1
        while scriptDraft.contains("'\(kind.rawValue)\(number)'") { number += 1 }
        scriptView?.replaceAll(with: WallpaperEngineScriptText.adding(kind, name: "\(kind.rawValue)\(number)", to: scriptDraft))
        readScriptSettings()
    }
}

/// The panel of scripts, under the scene: those of the selection, the one open, and its settings.
struct EngineScriptPanel: View {
    @ObservedObject var model: EngineEditorModel
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(width: 160)
            Divider()
            if model.scriptTarget != nil {
                VStack(spacing: 0) {
                    header
                    Divider()
                    EngineScriptCode(model: model)
                    if model.scriptProblem != nil || !model.scriptLog.isEmpty {
                        Divider()
                        messages
                    }
                }
                if !model.scriptSettings.isEmpty {
                    Divider()
                    settings
                        .frame(width: 220)
                }
            } else {
                Text(model.selection == nil ? "The scene has no scripts yet." : "This object has no scripts yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 320)
        .onReceive(timer) { _ in model.readScriptReport() }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scripts").font(.headline)
                Spacer()
                Menu {
                    ForEach(model.scriptOffers, id: \.self) { target in
                        Button(model.title(of: target)) { model.addScript(target) }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.scriptOffers.isEmpty)
                .help("Add a script to a value")
            }
            .padding(10)
            Divider()
            List(selection: Binding(get: { model.scriptTarget }, set: { model.openScript($0) })) {
                ForEach(model.scriptTargets, id: \.self) { target in
                    Text(verbatim: model.title(of: target))
                        .lineLimit(1)
                        .tag(target)
                }
            }
            .listStyle(.plain)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(fitting) { example in
                    Button(Self.title(of: example)) { model.useExample(example) }
                }
            } label: {
                Image(systemName: "wand.and.stars")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(fitting.isEmpty)
            .help("Put a ready-made script in place of this one")
            Menu {
                Button("Slider") { model.addScriptSetting(.slider) }
                Button("Checkbox") { model.addScriptSetting(.checkbox) }
                Button("Color") { model.addScriptSetting(.color) }
                Button("List") { model.addScriptSetting(.combo) }
                Button("Text") { model.addScriptSetting(.text) }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Declare a setting the script reads")
            Button {
                model.removeScript()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete Script")
            Spacer(minLength: 4)
            if model.scriptIsChanged {
                Button {
                    model.revertScript()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Revert")
            }
            Button("Apply") { model.applyScript() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!model.scriptIsChanged)
                .fixedSize()
                .help("Read the script and play the scene with it (⌘S)")
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var fitting: [WallpaperEngineScriptText.Example] {
        guard let target = model.scriptTarget else { return [] }
        return WallpaperEngineScriptText.examples.filter { $0.type == model.scriptType(of: target) }
    }

    private static func title(of example: WallpaperEngineScriptText.Example) -> LocalizedStringKey {
        switch example.id {
        case "spin": return "Spin"
        case "rainbow": return "Rainbow"
        case "flicker": return "Flicker"
        case "sound": return "Follow the Sound"
        case "follow": return "Follow the Pointer"
        case "clock": return "Clock"
        default: return "Show and Hide by Click"
        }
    }

    /// The problem of the script, which leads to its line, and what scripts wrote.
    private var messages: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let problem = model.scriptProblem {
                Button {
                    model.scriptView?.show(line: problem.line)
                } label: {
                    Label {
                        Text(verbatim: Self.line(of: problem))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                }
                .buttonStyle(.plain)
            }
            if !model.scriptLog.isEmpty {
                ScrollView {
                    Text(verbatim: model.scriptLog.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 56)
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private static func line(of problem: EngineScriptProblem) -> String {
        guard problem.line > 0 else { return problem.message }
        let format = NSLocalizedString("Line %d: %@", comment: "A problem of a script")
        return String(format: format, problem.line, problem.message)
    }

    private var settings: some View {
        Form {
            Section("Script Settings") {
                ForEach(model.scriptSettings) { setting in
                    row(setting)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func row(_ setting: WallpaperEngineScriptSetting) -> some View {
        let given = model.scriptValues[setting.name]
        switch setting.kind {
        case .slider:
            NumberRow(title: Text(verbatim: setting.label),
                      value: Binding(get: { given?.numberValue ?? setting.number }, set: { model.setScriptValue(setting.name, to: .number($0)) }),
                      in: setting.minimum...max(setting.maximum, setting.minimum + 0.001), step: setting.isWhole ? 1 : 0.01, suffix: "")
        case .checkbox:
            Toggle(isOn: Binding(get: { given?.boolValue ?? setting.isOn }, set: { model.setScriptValue(setting.name, to: .bool($0)) })) {
                Text(verbatim: setting.label)
            }
        case .color:
            ColorRow(title: Text(verbatim: setting.label), hex: Binding(
                get: { EngineEditorModel.hex((given?.stringValue ?? setting.text).split(separator: " ").compactMap { Double($0) }) },
                set: { hex in
                    guard let parts = EngineEditorModel.numbers(hex: hex) else { return }
                    model.setScriptValue(setting.name, to: .string(parts.map { String($0) }.joined(separator: " ")))
                }))
        case .combo:
            Picker(selection: Binding(get: { given?.stringValue ?? setting.text }, set: { model.setScriptValue(setting.name, to: .string($0)) })) {
                ForEach(setting.options, id: \.value) { option in
                    Text(verbatim: option.label).tag(option.value)
                }
            } label: {
                Text(verbatim: setting.label)
            }
        case .text:
            TextField(text: Binding(get: { given?.stringValue ?? setting.text }, set: { model.setScriptValue(setting.name, to: .string($0)) })) {
                Text(verbatim: setting.label)
            }
        }
    }
}

// MARK: - The text

/// The text of a script: monospaced, colored by what its parts are, with its lines numbered.
struct EngineScriptCode: NSViewRepresentable {
    @ObservedObject var model: EngineEditorModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let text = EngineScriptTextView(frame: scroll.bounds)
        text.autoresizingMask = [.width]
        text.minSize = NSSize(width: 0, height: 0)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        text.textContainerInset = NSSize(width: 4, height: 4)
        text.font = EngineScriptTextView.font
        text.isRichText = false
        text.allowsUndo = true
        text.usesFindBar = true
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.isContinuousSpellCheckingEnabled = false
        text.isGrammarCheckingEnabled = false
        text.smartInsertDeleteEnabled = false
        text.textColor = .labelColor
        text.backgroundColor = .textBackgroundColor
        text.delegate = context.coordinator
        scroll.documentView = text
        scroll.drawsBackground = true
        scroll.hasVerticalRuler = true
        scroll.verticalRulerView = EngineScriptRuler(text: text, scroll: scroll)
        scroll.rulersVisible = true
        model.scriptView = text
        text.string = model.scriptDraft
        context.coordinator.showColors(in: text)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? EngineScriptTextView else { return }
        if text.string != model.scriptDraft {
            text.string = model.scriptDraft
            text.undoManager?.removeAllActions(withTarget: text.textStorage as Any)
            scroll.verticalRulerView?.needsDisplay = true
        }
        context.coordinator.showColors(in: text)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private let model: EngineEditorModel
        /// What the colors are of: the panel updates far oftener than the text changes.
        private var shown: (text: String, line: Int?)?

        func showColors(in text: EngineScriptTextView) {
            let line = model.scriptProblem?.line
            guard shown?.text != text.string || shown?.line != line else { return }
            shown = (text.string, line)
            text.showColors(problemLine: line)
        }

        init(model: EngineEditorModel) {
            self.model = model
        }

        func textDidChange(_ notification: Notification) {
            guard let text = notification.object as? NSTextView else { return }
            model.scriptDraft = text.string
            // What was wrong with the text before says nothing of this one.
            model.scriptProblem = nil
            text.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
    }
}

/// Keeps the indent of the line before, and offers names.
final class EngineScriptTextView: NSTextView {
    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    /// Colors parts of the text without touching the text, so that they are no step to undo.
    func showColors(problemLine: Int?) {
        guard let layout = layoutManager else { return }
        let whole = NSRange(location: 0, length: (string as NSString).length)
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
        layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
        for (range, kind) in WallpaperEngineScriptText.tokens(in: string) {
            let color: NSColor
            switch kind {
            case .comment: color = .secondaryLabelColor
            case .string: color = .systemRed
            case .number: color = .systemPurple
            case .keyword: color = .systemPink
            case .known: color = .systemTeal
            }
            layout.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: range)
        }
        if let problemLine, let range = range(ofLine: problemLine) {
            layout.addTemporaryAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.25), forCharacterRange: range)
        }
    }

    private func range(ofLine number: Int) -> NSRange? {
        guard number > 0 else { return nil }
        let text = string as NSString
        var line = 1, at = 0
        while line < number, at < text.length {
            at = NSMaxRange(text.lineRange(for: NSRange(location: at, length: 0)))
            line += 1
        }
        return line == number ? text.lineRange(for: NSRange(location: min(at, text.length), length: 0)) : nil
    }

    func show(line number: Int) {
        guard let range = range(ofLine: number) else { return }
        window?.makeFirstResponder(self)
        setSelectedRange(NSRange(location: range.location, length: 0))
        scrollRangeToVisible(range)
    }

    /// All of the text replaced, as one step of typing to undo.
    func replaceAll(with text: String) {
        insertText(text, replacementRange: NSRange(location: 0, length: (string as NSString).length))
    }

    override func insertNewline(_ sender: Any?) {
        let text = string as NSString
        let line = text.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let before = text.substring(with: NSRange(location: line.location, length: selectedRange().location - line.location))
        var indent = String(before.prefix { $0 == "\t" || $0 == " " })
        if before.trimmingCharacters(in: .whitespaces).hasSuffix("{") { indent += "\t" }
        super.insertNewline(sender)
        insertText(indent, replacementRange: selectedRange())
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49, event.modifierFlags.intersection([.control, .command, .option]) == [.control] {
            complete(nil)
            return
        }
        super.keyDown(with: event)
    }

    override func insertText(_ text: Any, replacementRange: NSRange) {
        super.insertText(text, replacementRange: replacementRange)
        if text as? String == ".", !names(after: selectedRange().location).isEmpty { complete(nil) }
    }

    /// The name before a dot that ends at a place of the text, and what it has.
    private func names(after place: Int) -> [String] {
        let text = string as NSString
        var start = place - 1
        guard start >= 0, text.character(at: start) == 46 else { return [] }
        while start > 0, let unit = UnicodeScalar(text.character(at: start - 1)), CharacterSet.alphanumerics.contains(unit) { start -= 1 }
        return WallpaperEngineScriptText.members(of: text.substring(with: NSRange(location: start, length: place - 1 - start)))
    }

    override var rangeForUserCompletion: NSRange {
        let text = string as NSString, end = selectedRange().location
        var start = end
        while start > 0, let unit = UnicodeScalar(text.character(at: start - 1)), CharacterSet.alphanumerics.contains(unit) { start -= 1 }
        return NSRange(location: start, length: end - start)
    }

    override func completions(forPartialWordRange range: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        let typed = (string as NSString).substring(with: range).lowercased()
        let members = names(after: range.location)
        let names = members.isEmpty ? WallpaperEngineScriptText.globalNames : members
        return names.filter { typed.isEmpty || $0.lowercased().hasPrefix(typed) }.sorted()
    }
}

/// The numbers of the lines, at the side of the text.
final class EngineScriptRuler: NSRulerView {
    private weak var text: NSTextView?

    init(text: NSTextView, scroll: NSScrollView) {
        self.text = text
        super.init(scrollView: scroll, orientation: .verticalRuler)
        clientView = text
        ruleThickness = 40
        // The ruler's own line runs past it otherwise, over what stands above the panel.
        clipsToBounds = true
        NotificationCenter.default.addObserver(self, selector: #selector(moved), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func moved() {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let text, let layout = text.layoutManager, let container = text.textContainer else { return }
        let words = text.string as NSString
        let shown = layout.glyphRange(forBoundingRect: text.visibleRect, in: container)
        let characters = layout.characterRange(forGlyphRange: shown, actualGlyphRange: nil)
        var line = 1, at = 0
        while at < characters.location {
            at = NSMaxRange(words.lineRange(for: NSRange(location: at, length: 0)))
            line += 1
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor.tertiaryLabelColor]
        let top = text.textContainerOrigin.y - text.visibleRect.minY
        while at <= NSMaxRange(characters), at < words.length || line == 1 {
            let range = words.lineRange(for: NSRange(location: at, length: 0))
            let box = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: min(at, max(0, words.length - 1))), effectiveRange: nil)
            let number = NSAttributedString(string: String(line), attributes: attributes)
            number.draw(at: NSPoint(x: ruleThickness - number.size().width - 6, y: box.minY + top + 2))
            line += 1
            if NSMaxRange(range) == at { break }
            at = NSMaxRange(range)
        }
    }
}

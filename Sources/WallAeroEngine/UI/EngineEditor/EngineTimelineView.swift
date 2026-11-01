import SwiftUI
import WallpaperCore

/// The panel under the scene: on the left what of the selected object is animated, on the right
/// its moments along the time, or the curves of the one chosen. The keys are Wallpaper Engine's:
/// K a moment, A moments made by themselves, the arrows through the frames.
struct EngineTimelineView: View {
    @ObservedObject var model: EngineEditorModel

    static let height: CGFloat = 230

    private var object: Int? { model.selection }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if object == nil {
                placeholder("Select an object to animate it.")
            } else if model.timelineTargets.isEmpty {
                placeholder(model.mode == .pose ? "Select a bone, or turn one on the scene." : "Nothing of this object is animated. Choose what to animate with the Animate button.")
            } else {
                HStack(spacing: 0) {
                    properties
                        .frame(width: 190)
                    Divider()
                    if model.timelineCurves {
                        EngineTimelineCurves(model: model)
                    } else {
                        EngineTimelineKeys(model: model)
                    }
                }
            }
        }
        .frame(height: Self.height)
    }

    private func placeholder(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - The controls

    private var header: some View {
        HStack(spacing: 8) {
            EngineAnimateMenu(model: model)
            if let rig = model.selectedRig, !rig.animations.isEmpty {
                EngineBoneAnimationMenu(model: model, rig: rig)
            }
            Divider().frame(height: 16)
            Button { model.jump(toEnd: false) } label: { Image(systemName: "backward.end.fill") }
                .help("Jump to Start")
            Button { model.setTimelinePlaying(!model.timelinePlaying) } label: {
                Image(systemName: model.timelinePlaying ? "pause.fill" : "play.fill")
            }
            .help(model.timelinePlaying ? "Pause" : "Play")
            Button { model.jump(toEnd: true) } label: { Image(systemName: "forward.end.fill") }
                .help("Jump to End")
            if let animation = model.activeAnimation {
                Text(verbatim: "\(Int(model.timelineFrame)) / \(Int(animation.length))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            Divider().frame(height: 16)
            Button(action: model.toggleKey) { Image(systemName: "diamond.fill") }
                .help("Add or Remove a Keyframe (K)")
                .disabled(model.activeAnimation == nil)
            Toggle(isOn: $model.autoKey) { Image(systemName: "record.circle") }
                .toggleStyle(.button)
                .help("Auto Keyframe (A)")
            Button {
                if let target = model.timelineTarget { model.sheet = .events(target: target) }
            } label: {
                Image(systemName: "alarm")
            }
            .help("SceneScript Animation Events")
            .disabled(model.activeAnimation == nil)
            if let interpolation = model.selectedInterpolation {
                Picker("Interpolation", selection: Binding(get: { interpolation }, set: { model.setSelectedInterpolation($0) })) {
                    Text("Smooth").tag(WallpaperEngineAnimation.Interpolation.automatic)
                    Text("Straight").tag(WallpaperEngineAnimation.Interpolation.linear)
                    Divider()
                    Text("Handle Before").tag(WallpaperEngineAnimation.Interpolation.back)
                    Text("Handle After").tag(WallpaperEngineAnimation.Interpolation.front)
                    Text("Both Handles").tag(WallpaperEngineAnimation.Interpolation.both)
                }
                .labelsHidden()
                .fixedSize()
            }
            if let locks = model.selectedLocks {
                Toggle(isOn: Binding(get: { locks.angle }, set: { model.setSelectedLocks(angle: $0, length: locks.length) })) {
                    Image(systemName: "angle")
                }
                .toggleStyle(.button)
                .help("Lock Handle Angles")
                Toggle(isOn: Binding(get: { locks.length }, set: { model.setSelectedLocks(angle: locks.angle, length: $0) })) {
                    Image(systemName: "ruler")
                }
                .toggleStyle(.button)
                .help("Lock Handle Lengths")
            }
            Spacer(minLength: 8)
            Button(action: model.fitTimeline) { Image(systemName: "arrow.left.and.right") }
                .help("Show the Whole Animation")
                .disabled(model.timelineSpan == nil && model.curveRange == nil)
            Picker("View", selection: $model.timelineCurves) {
                Text("Keyframes").tag(false)
                Text("Curves").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    // MARK: - What is animated

    private var properties: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(model.timelineTargets, id: \.self) { target in
                    row(target)
                }
            }
            .padding(.top, EngineTimelineKeys.rulerHeight)
            .background(GeometryReader { list in
                Color.clear.preference(key: TimelineRowsOffset.self, value: list.frame(in: .named("rows")).minY)
            })
        }
        .coordinateSpace(name: "rows")
        .onPreferenceChange(TimelineRowsOffset.self) { model.timelineRowsOffset = max(0, -$0) }
    }

    private func row(_ target: WallpaperEngineAnimationTarget) -> some View {
        Button {
            model.pickTrack(target)
        } label: {
            Text(verbatim: model.title(of: target))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: EngineTimelineKeys.rowHeight, alignment: .leading)
                .contentShape(Rectangle())
                .background(model.timelineTarget == target ? Color.accentColor.opacity(0.25) : Color.clear)
        }
        .buttonStyle(.plain)
        .help(model.title(of: target))
        .contextMenu {
            Button("Animation Options…") {
                if let object { model.sheet = .animation(object: object, target: target, isNew: false, fallback: []) }
            }
            Divider()
            if case .bone = target {
                Button("Remove Keys of the Bone", role: .destructive) { model.unbindAnimation(target) }
            } else {
                Button("Remove Animation", role: .destructive) { model.unbindAnimation(target) }
            }
        }
    }
}

/// Which animation of its bones the picture is on, as Blender's actions, and those to add.
private struct EngineBoneAnimationMenu: View {
    @ObservedObject var model: EngineEditorModel
    let rig: WallpaperEnginePuppetRig

    var body: some View {
        Menu {
            ForEach(rig.animations.indices, id: \.self) { index in
                Toggle(isOn: Binding(get: { model.rigAnimation == index }, set: { _ in model.setRigAnimation(index) })) {
                    Text(verbatim: rig.animations[index].name)
                }
            }
            Divider()
            Button("New Animation of Bones") { model.addRigAnimation() }
            Button("Animation Options…") {
                if let object = model.selection {
                    model.sheet = .animation(object: object, target: .bone(animation: model.rigAnimation, bone: 0), isNew: false, fallback: [])
                }
            }
            Toggle("Only Selected Bone", isOn: $model.timelineOnlySelected)
            Divider()
            Button("Delete Animation of Bones", role: .destructive) { model.removeRigAnimation() }
        } label: {
            Label {
                Text(verbatim: rig.animations.indices.contains(model.rigAnimation) ? rig.animations[model.rigAnimation].name : "")
            } icon: {
                Image(systemName: "figure.walk")
            }
        }
        .labelStyle(.titleAndIcon)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("The animation of the bones")
    }
}

/// The menu of what can be animated of the selected object.
private struct EngineAnimateMenu: View {
    @ObservedObject var model: EngineEditorModel

    private var hasColor: Bool {
        guard let id = model.selection else { return false }
        return [.image, .text, .solid, .composition, .fullscreen].contains(model.kind(of: id))
    }

    var body: some View {
        Menu {
            if let id = model.selection {
                value("Position", "origin", fallback: [0, 0, 0], id)
                value("Scale", "scale", fallback: [1, 1, 1], id)
                value("Rotation", "angles", fallback: [0, 0, 0], id)
                if hasColor {
                    value("Opacity", "alpha", fallback: [1], id)
                    value("Color", "color", fallback: [1, 1, 1], id)
                }
                if let effects = model.description?.object(id)?.effects, !effects.isEmpty {
                    Divider()
                    ForEach(effects, id: \.id) { effect in
                        Menu {
                            ForEach(effect.values) { value in
                                let target = model.document.effectTarget(named: value.name, effect: effect.id, of: id)
                                Button {
                                    model.prepareEffectValue(value, effect: effect.id, of: id)
                                    model.sheet = .animation(object: id, target: model.document.effectTarget(named: value.name, effect: effect.id, of: id),
                                                             isNew: true, fallback: value.value)
                                } label: {
                                    Text(verbatim: value.title)
                                }
                                .disabled(model.document.animation(of: id, target) != nil)
                            }
                        } label: {
                            Text(verbatim: effect.title)
                        }
                    }
                }
            }
        } label: {
            Label("Animate", systemImage: "plus")
        }
        .labelStyle(.titleAndIcon)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.selection == nil)
    }

    private func value(_ title: LocalizedStringKey, _ key: String, fallback: [Double], _ id: Int) -> some View {
        let target = WallpaperEngineAnimationTarget.value(key)
        return Button(title) {
            model.sheet = .animation(object: id, target: target, isNew: true, fallback: fallback)
        }
        .disabled(model.document.animation(of: id, target) != nil)
    }
}

/// How far the rows of the timeline are scrolled.
private struct TimelineRowsOffset: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// How the time of the timeline lies across its width.
private struct TimelineScale {
    let width: CGFloat
    let start: Double
    let seconds: Double
    let total: Double
    static let margin: CGFloat = 12

    @MainActor init(_ model: EngineEditorModel, width: CGFloat) {
        self.width = width
        start = model.timelineStart
        seconds = model.timelineShown
        total = model.timelineTotal
    }

    func x(_ time: Double) -> CGFloat {
        Self.margin + CGFloat((time - start) / max(seconds, 0.001)) * (width - Self.margin * 2)
    }

    /// The time at a place, within the animations.
    func time(_ x: CGFloat) -> Double {
        max(0, min(total, start + Double((x - Self.margin) / max(width - Self.margin * 2, 1)) * seconds))
    }

    /// By how much the time goes with a distance across.
    func seconds(across distance: CGFloat) -> Double {
        Double(distance / max(width - Self.margin * 2, 1)) * seconds
    }

    /// Lines every so many seconds, as many as have room.
    var tick: Double {
        [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 30, 60].first { x(start + $0) - x(start) >= 56 } ?? 120
    }
}

/// The time at the top of the tracks, its lines, and where the scripts are told of something.
@MainActor
private func drawRuler(_ context: GraphicsContext, _ scale: TimelineScale, model: EngineEditorModel, full: CGFloat) {
    let height = EngineTimelineKeys.rulerHeight
    let tick = scale.tick
    var time = (scale.start / tick).rounded(.down) * tick
    while time <= scale.start + scale.seconds + 0.0001 {
        let x = scale.x(time)
        var line = Path()
        line.move(to: CGPoint(x: x, y: height - 6))
        line.addLine(to: CGPoint(x: x, y: full))
        context.stroke(line, with: .color(.primary.opacity(0.1)))
        context.draw(Text(verbatim: time.formatted(.number.precision(.fractionLength(0...3)))).font(.caption2).foregroundColor(.secondary),
                     at: CGPoint(x: x, y: 2), anchor: .top)
        time += tick
    }
    if let animation = model.activeAnimation {
        for event in animation.events {
            let x = scale.x(event.frame / animation.rate)
            context.fill(Path(ellipseIn: CGRect(x: x - 3, y: height - 7, width: 6, height: 6)), with: .color(.orange))
        }
    }
}

private func drawPlayhead(_ context: GraphicsContext, x: CGFloat, height: CGFloat) {
    var line = Path()
    line.move(to: CGPoint(x: x, y: 0))
    line.addLine(to: CGPoint(x: x, y: height))
    context.stroke(line, with: .color(.accentColor), lineWidth: 1.5)
}

private func drawBox(_ context: GraphicsContext, _ box: CGRect?) {
    guard let box else { return }
    context.fill(Path(box), with: .color(.accentColor.opacity(0.15)))
    context.stroke(Path(box), with: .color(.accentColor), lineWidth: 1)
}

/// What a press on the timeline has taken hold of.
private enum TimelineHold {
    case time
    case box
    case keys(frameAtPress: [EngineTimelineKey], base: WallpaperEngineDocument)
    case handle(WallpaperEngineAnimation.Side, EngineTimelineKey, moment: WallpaperEngineAnimation.Key)
}

/// Keeps where the tracks are, for the wheel over them.
private struct TimelineAreaReporter: View {
    let model: EngineEditorModel

    var body: some View {
        GeometryReader { area in
            Color.clear
                .onAppear { model.timelineArea = area.frame(in: .global) }
                .onChange(of: area.frame(in: .global)) { model.timelineArea = $0 }
        }
    }
}

private var extendsSelection: Bool {
    !NSEvent.modifierFlags.intersection([.shift, .command, .control]).isEmpty
}

/// The moments of what is animated, a row for each, along the time. A press on the time at the
/// top moves it; a drag over the rows draws a box round moments; a moment is dragged along.
struct EngineTimelineKeys: View {
    @ObservedObject var model: EngineEditorModel
    static let rulerHeight: CGFloat = 22
    static let rowHeight: CGFloat = 24

    @State private var hold: TimelineHold?
    @State private var box: CGRect?

    var body: some View {
        GeometryReader { area in
            let scale = TimelineScale(model, width: area.size.width)
            Canvas { context, size in
                drawRuler(context, scale, model: model, full: size.height)
                for (row, target) in model.timelineTargets.enumerated() {
                    guard let animation = model.animation(target) else { continue }
                    let top = Self.rulerHeight + CGFloat(row) * Self.rowHeight - model.timelineRowsOffset
                    guard top + Self.rowHeight > Self.rulerHeight else { continue }
                    if target == model.timelineTarget {
                        context.fill(Path(CGRect(x: 0, y: top, width: size.width, height: Self.rowHeight)), with: .color(.accentColor.opacity(0.12)))
                    }
                    var bar = Path()
                    bar.move(to: CGPoint(x: scale.x(0), y: top + Self.rowHeight / 2))
                    bar.addLine(to: CGPoint(x: scale.x(animation.duration), y: top + Self.rowHeight / 2))
                    context.stroke(bar, with: .color(.primary.opacity(0.15)), lineWidth: 2)
                    for frame in animation.keyFrames {
                        let isSelected = model.selectedKeys.contains { $0.target == target && $0.frame == frame }
                        let x = scale.x(frame / animation.rate), y = top + Self.rowHeight / 2, r: CGFloat = 5.5
                        var diamond = Path()
                        diamond.move(to: CGPoint(x: x, y: y - r))
                        diamond.addLine(to: CGPoint(x: x + r, y: y))
                        diamond.addLine(to: CGPoint(x: x, y: y + r))
                        diamond.addLine(to: CGPoint(x: x - r, y: y))
                        diamond.closeSubpath()
                        context.fill(diamond, with: .color(isSelected ? .accentColor : .primary.opacity(0.75)))
                    }
                }
                drawBox(context, box)
                drawPlayhead(context, x: scale.x(model.timelineSeconds), height: size.height)
            }
            .contentShape(Rectangle())
            .background(TimelineAreaReporter(model: model))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in changed(drag, scale) }
                .onEnded { drag in ended(drag, scale) })
        }
    }

    private func key(at point: CGPoint, _ scale: TimelineScale) -> EngineTimelineKey? {
        let row = Int((point.y - Self.rulerHeight + model.timelineRowsOffset) / Self.rowHeight)
        guard point.y >= Self.rulerHeight, model.timelineTargets.indices.contains(row) else { return nil }
        let target = model.timelineTargets[row]
        guard let animation = model.animation(target) else { return nil }
        return animation.keyFrames.first { abs(scale.x($0 / animation.rate) - point.x) <= 7 }
            .map { EngineTimelineKey(target: target, frame: $0, channel: nil) }
    }

    private func changed(_ drag: DragGesture.Value, _ scale: TimelineScale) {
        if hold == nil {
            if let found = key(at: drag.startLocation, scale) {
                model.pickTrack(found.target)
                if extendsSelection {
                    if model.selectedKeys.remove(found) == nil { model.selectedKeys.insert(found) }
                } else if !model.selectedKeys.contains(found) {
                    model.selectedKeys = [found]
                }
                hold = .keys(frameAtPress: Array(model.selectedKeys), base: model.document)
            } else {
                hold = drag.startLocation.y < Self.rulerHeight ? .time : .box
            }
        }
        switch hold {
        case .keys(let keys, let base):
            model.moveKeys(keys, from: base, bySeconds: scale.seconds(across: drag.translation.width))
        case .box:
            box = CGRect(x: min(drag.startLocation.x, drag.location.x), y: min(drag.startLocation.y, drag.location.y),
                         width: abs(drag.translation.width), height: abs(drag.translation.height))
        default:
            if let animation = model.activeAnimation {
                model.timelineSeconds = (scale.time(drag.location.x) * animation.rate).rounded() / animation.rate
            }
        }
    }

    private func ended(_ drag: DragGesture.Value, _ scale: TimelineScale) {
        if case .box = hold {
            var found: Set<EngineTimelineKey> = extendsSelection ? model.selectedKeys : []
            if let box, box.width > 2 || box.height > 2 {
                for (row, target) in model.timelineTargets.enumerated() {
                    guard let animation = model.animation(target) else { continue }
                    let y = Self.rulerHeight + (CGFloat(row) + 0.5) * Self.rowHeight - model.timelineRowsOffset
                    for frame in animation.keyFrames where box.contains(CGPoint(x: scale.x(frame / animation.rate), y: y)) {
                        found.insert(EngineTimelineKey(target: target, frame: frame, channel: nil))
                    }
                }
            }
            model.selectedKeys = found
        }
        hold = nil
        box = nil
        model.endGesture()
    }
}

/// The curves of the value chosen, one for each of its numbers in the colors Wallpaper Engine
/// has for them, with their moments to drag along the time and up and down, and the handles of
/// a moment selected that has them.
struct EngineTimelineCurves: View {
    @ObservedObject var model: EngineEditorModel
    @State private var hold: TimelineHold?
    @State private var box: CGRect?
    /// The heights the drag started with: they stay while a moment is dragged past them.
    @State private var frozen: ClosedRange<Double>?

    private static let colors: [Color] = [.red, .green, .blue, .yellow, .purple]
    private static let top: CGFloat = EngineTimelineKeys.rulerHeight + 8

    /// The heights the curves reach, with room above and below.
    private func range(_ animation: WallpaperEngineAnimation) -> ClosedRange<Double> {
        if let frozen { return frozen }
        if let shown = model.curveRange { return shown }
        return Self.fitted(animation)
    }

    static func fitted(_ animation: WallpaperEngineAnimation) -> ClosedRange<Double> {
        let zero = Array(repeating: 0.0, count: animation.channelCount)
        let samples = stride(from: 0.0, through: max(animation.length, 1), by: max(animation.length, 1) / 120)
            .flatMap { animation.numbers(atFrame: $0, base: zero) }
        let low = samples.min() ?? 0, high = samples.max() ?? 1
        let room = max((high - low) * 0.12, max(abs(high), 1) * 0.02)
        return (low - room)...(high + room)
    }

    private func y(_ value: Double, _ range: ClosedRange<Double>, height: CGFloat) -> CGFloat {
        Self.top + CGFloat((range.upperBound - value) / (range.upperBound - range.lowerBound)) * (height - Self.top - 8)
    }

    private func perPoint(_ range: ClosedRange<Double>, height: CGFloat) -> Double {
        (range.upperBound - range.lowerBound) / Double(max(height - Self.top - 8, 1))
    }

    var body: some View {
        GeometryReader { area in
            let scale = TimelineScale(model, width: area.size.width)
            Canvas { context, size in
                drawRuler(context, scale, model: model, full: size.height)
                if let animation = model.activeAnimation {
                    draw(animation, context, scale, size)
                }
                drawBox(context, box)
                drawPlayhead(context, x: scale.x(model.timelineSeconds), height: size.height)
            }
            .contentShape(Rectangle())
            .background(TimelineAreaReporter(model: model))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in changed(drag, scale, area.size.height) }
                .onEnded { drag in ended(drag, scale, area.size.height) })
        }
    }

    /// The ends of the handles of a selected moment, where the screen has them.
    private func handles(_ animation: WallpaperEngineAnimation, _ key: WallpaperEngineAnimation.Key, channel: Int, _ scale: TimelineScale,
                         _ range: ClosedRange<Double>, height: CGFloat) -> [(side: WallpaperEngineAnimation.Side, at: CGPoint)] {
        // A bone's keys ease by themselves: there is nothing to drag.
        if case .bone? = model.timelineTarget { return [] }
        return [(WallpaperEngineAnimation.Side.back, key.back), (.front, key.front)].compactMap { side, handle in
            guard let handle, !handle.magic else { return nil }
            let reach = animation.reach(side, frame: key.frame, channel: channel)
            return (side, CGPoint(x: scale.x((key.frame + handle.x * reach) / animation.rate), y: y(key.value + handle.y, range, height: height)))
        }
    }

    private func draw(_ animation: WallpaperEngineAnimation, _ context: GraphicsContext, _ scale: TimelineScale, _ size: CGSize) {
        let range = range(animation)
        let zero = Array(repeating: 0.0, count: animation.channelCount)
        guard let target = model.timelineTarget else { return }
        for channel in 0..<animation.channelCount {
            let color = Self.colors[channel % Self.colors.count]
            var curve = Path()
            let first = max(scale.x(0), 0), end = min(scale.x(animation.duration), size.width)
            for x in stride(from: first, through: max(end, first + 1), by: 2) {
                let frame = scale.time(x) * animation.rate
                let point = CGPoint(x: x, y: y(animation.numbers(atFrame: frame, base: zero)[channel], range, height: size.height))
                if curve.isEmpty { curve.move(to: point) } else { curve.addLine(to: point) }
            }
            context.stroke(curve, with: .color(color), lineWidth: 1.5)
            for key in animation.keys(channel) {
                let selected = model.selectedKeys.contains(EngineTimelineKey(target: target, frame: key.frame, channel: channel))
                let at = CGPoint(x: scale.x(key.frame / animation.rate), y: y(key.value, range, height: size.height))
                if selected {
                    for handle in handles(animation, key, channel: channel, scale, range, height: size.height) {
                        var line = Path()
                        line.move(to: at)
                        line.addLine(to: handle.at)
                        context.stroke(line, with: .color(.primary.opacity(0.5)))
                        context.fill(Path(ellipseIn: CGRect(x: handle.at.x - 3.5, y: handle.at.y - 3.5, width: 7, height: 7)), with: .color(.primary))
                    }
                }
                let dot = Path(ellipseIn: CGRect(x: at.x - 4, y: at.y - 4, width: 8, height: 8))
                context.fill(dot, with: .color(selected ? .accentColor : color))
                context.stroke(dot, with: .color(.primary.opacity(0.6)))
            }
        }
    }

    private func press(_ point: CGPoint, _ animation: WallpaperEngineAnimation, _ target: WallpaperEngineAnimationTarget,
                       _ scale: TimelineScale, _ height: CGFloat) -> TimelineHold {
        let range = range(animation)
        frozen = range
        // The handles of what is selected stand over everything.
        for channel in 0..<animation.channelCount {
            for key in animation.keys(channel) where model.selectedKeys.contains(EngineTimelineKey(target: target, frame: key.frame, channel: channel)) {
                for handle in handles(animation, key, channel: channel, scale, range, height: height) where hypot(handle.at.x - point.x, handle.at.y - point.y) <= 7 {
                    return .handle(handle.side, EngineTimelineKey(target: target, frame: key.frame, channel: channel), moment: key)
                }
            }
        }
        for channel in 0..<animation.channelCount {
            let found = animation.keys(channel).first {
                hypot(scale.x($0.frame / animation.rate) - point.x, y($0.value, range, height: height) - point.y) <= 7
            }
            if let found {
                let key = EngineTimelineKey(target: target, frame: found.frame, channel: channel)
                if extendsSelection {
                    if model.selectedKeys.remove(key) == nil { model.selectedKeys.insert(key) }
                } else if !model.selectedKeys.contains(key) {
                    model.selectedKeys = [key]
                }
                return .keys(frameAtPress: Array(model.selectedKeys), base: model.document)
            }
        }
        return point.y < EngineTimelineKeys.rulerHeight ? .time : .box
    }

    private func changed(_ drag: DragGesture.Value, _ scale: TimelineScale, _ height: CGFloat) {
        guard let animation = model.activeAnimation, let target = model.timelineTarget else { return }
        if hold == nil {
            hold = press(drag.startLocation, animation, target, scale, height)
        }
        let range = frozen ?? self.range(animation)
        let unit = perPoint(range, height: height)
        switch hold {
        case .keys(let keys, let base):
            model.moveKeys(keys, from: base, bySeconds: scale.seconds(across: drag.translation.width),
                           value: -Double(drag.translation.height) * unit)
        case .handle(let side, let key, let moment):
            let frame = scale.time(drag.location.x) * animation.rate
            let value = range.upperBound - Double(drag.location.y - Self.top) * unit
            let reach = key.channel.map { animation.reach(side, frame: key.frame, channel: $0) } ?? 1
            model.moveHandle(side, of: key, x: (frame - moment.frame) / reach, y: value - moment.value)
        case .box:
            box = CGRect(x: min(drag.startLocation.x, drag.location.x), y: min(drag.startLocation.y, drag.location.y),
                         width: abs(drag.translation.width), height: abs(drag.translation.height))
        default:
            model.timelineSeconds = (scale.time(drag.location.x) * animation.rate).rounded() / animation.rate
        }
    }

    private func ended(_ drag: DragGesture.Value, _ scale: TimelineScale, _ height: CGFloat) {
        if case .box = hold, let animation = model.activeAnimation, let target = model.timelineTarget {
            var found: Set<EngineTimelineKey> = extendsSelection ? model.selectedKeys : []
            if let box, box.width > 2 || box.height > 2, let range = frozen {
                for channel in 0..<animation.channelCount {
                    for key in animation.keys(channel)
                    where box.contains(CGPoint(x: scale.x(key.frame / animation.rate), y: y(key.value, range, height: height))) {
                        found.insert(EngineTimelineKey(target: target, frame: key.frame, channel: channel))
                    }
                }
            }
            model.selectedKeys = found
        }
        hold = nil
        box = nil
        frozen = nil
        model.endGesture()
    }
}

/// The names scripts are told of as the animation passes a frame.
struct EngineAnimationEventsSheet: View {
    @ObservedObject var model: EngineEditorModel
    let target: WallpaperEngineAnimationTarget
    @Environment(\.dismiss) private var dismiss
    @State private var events: [WallpaperEngineAnimation.Event] = []

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    ForEach(events.indices, id: \.self) { index in
                        HStack {
                            TextField("Name", text: $events[index].name)
                                .labelsHidden()
                            TextField("Frame", value: $events[index].frame, format: .number.grouping(.never))
                                .labelsHidden()
                                .frame(width: 64)
                            Button {
                                events.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove")
                        }
                    }
                    Button {
                        events.append(.init(frame: model.timelineFrame, name: ""))
                    } label: {
                        Label("Add Event", systemImage: "plus")
                    }
                } header: {
                    Text(verbatim: model.title(of: target))
                } footer: {
                    Text("A script of the same layer is told with animationEvent(event, value) when the animation passes the frame.")
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") {
                    model.setEvents(events.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }, of: target)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 420, height: 340)
        .onAppear { events = model.animation(target)?.events ?? [] }
    }
}

/// How an animation plays: asked for when one is made, and for one there is from its menu.
struct EngineAnimationOptionsSheet: View {
    @ObservedObject var model: EngineEditorModel
    let target: WallpaperEngineAnimationTarget
    let isNew: Bool
    let fallback: [Double]
    @Environment(\.dismiss) private var dismiss
    @State private var options = WallpaperEngineAnimation.Options()
    @State private var seconds = 3.0
    /// The value of the same object it plays along with, if any.
    @State private var leader: String?

    private var isLinked: Bool { leader != nil }
    /// A bone's animation has only what Wallpaper Engine writes of one.
    private var isBone: Bool {
        if case .bone = target { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if !isNew, !model.possibleLeaders(of: target).isEmpty || leader != nil {
                        Picker("Combine With", selection: $leader) {
                            Text("Nothing").tag(String?.none)
                            ForEach(model.possibleLeaders(of: target), id: \.self) { key in
                                Text(verbatim: model.title(of: .value(key))).tag(Optional(key))
                            }
                        }
                    }
                    // What follows another lasts and plays as that one does.
                    Group {
                        Picker("Mode", selection: $options.mode) {
                            Text("Loop").tag(WallpaperEngineAnimation.Mode.loop)
                            Text("Back and Forth").tag(WallpaperEngineAnimation.Mode.mirror)
                            Text("Once").tag(WallpaperEngineAnimation.Mode.single)
                        }
                        NumberRow("Duration", value: $seconds, in: 0.1...120, step: 0.1,
                                  suffix: NSLocalizedString("s", comment: "Seconds, after a number"))
                        Picker("Frames per Second", selection: $options.fps) {
                            ForEach([options.fps] + [15.0, 24, 30, 60].filter { $0 != options.fps }, id: \.self) { rate in
                                Text(verbatim: rate.formatted()).tag(rate)
                            }
                        }
                    }
                    .disabled(isLinked)
                    TextField("Name", text: $options.name)
                    if !isBone {
                        Toggle("Start Paused", isOn: $options.startsPaused)
                    }
                    if options.mode == .loop, !isBone {
                        Toggle("Smooth Loop", isOn: $options.wrapsLoop)
                            .disabled(isLinked)
                    }
                } header: {
                    Text(verbatim: model.title(of: target))
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Animate" : "OK") {
                    options.length = (seconds * options.fps).rounded()
                    if isNew {
                        model.bindAnimation(target, options: options, fallback: fallback)
                    } else {
                        model.setOptions(options, of: target, leader: leader)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 420, height: 360)
        .onAppear {
            options = isNew ? model.newAnimationOptions(for: target) : model.animation(target)?.options ?? options
            let length = isNew ? options.length : model.animation(target)?.length ?? options.length
            seconds = length / max(options.fps, 1)
            leader = isNew ? nil : model.animation(target)?.leader
        }
    }
}

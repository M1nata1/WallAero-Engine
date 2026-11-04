import SwiftUI
import WallpaperCore

/// The scene's time, always under the scene, as Blender's timeline has it: a header with how
/// it plays, the buttons to go through it, the frame it stands at and the part played; under it
/// the frames, where the selected object's keys are marked and a drag goes along. The scene
/// moves only by it: the editor opens with the scene standing at the start.
struct EngineTransportBar: View {
    @ObservedObject var model: EngineEditorModel

    var body: some View {
        VStack(spacing: 0) {
            header
            EngineFrameRuler(model: model)
        }
    }

    private var rate: Double { model.timelineRate }

    private var header: some View {
        HStack(spacing: 10) {
            Menu("Playback") {
                Toggle("Play Round and Round", isOn: $model.playsRound)
                Button("Set End to the Longest Animation") { model.playEnd = nil }
                    .disabled(model.playEnd == nil)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                Button { model.jump(toEnd: false) } label: { Image(systemName: "backward.end.fill") }
                    .help("Jump to Start (Shift ←)")
                Button { model.jumpToKey(forward: false) } label: { Image(systemName: "backward.frame.fill") }
                    .help("Previous Keyframe (↓)")
                    .disabled(model.activeAnimation == nil)
                Button { model.isPlaying.toggle() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 22)
                }
                .help(model.isPlaying ? "Pause (Space)" : "Play (Space)")
                Button { model.jumpToKey(forward: true) } label: { Image(systemName: "forward.frame.fill") }
                    .help("Next Keyframe (↑)")
                    .disabled(model.activeAnimation == nil)
                Button { model.jump(toEnd: true) } label: { Image(systemName: "forward.end.fill") }
                    .help("Jump to End (Shift →)")
            }
            .buttonStyle(.borderless)
            Spacer(minLength: 8)
            frameField(Binding(get: { model.timelineSeconds * rate }, set: { model.timelineSeconds = max(0, $0) / rate }))
                .help("Frame")
            Toggle(isOn: $model.playsRound) { Image(systemName: "repeat") }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help("Play Round and Round")
            HStack(spacing: 4) {
                Text("Start").foregroundStyle(.secondary)
                frameField(Binding(get: { model.playStart * rate },
                                   set: { model.playStart = max(0, min($0 / rate, model.playLength - 1 / rate)) }))
                Text("End").foregroundStyle(.secondary)
                frameField(Binding(get: { model.playLength * rate },
                                   set: { model.playEnd = max($0 / rate, model.playStart + 1 / rate) }))
            }
            .help("The part of the time played. With no end set, the longest animation of the scene ends it.")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    private func frameField(_ value: Binding<Double>) -> some View {
        TextField("", value: Binding(get: { value.wrappedValue.rounded() }, set: { value.wrappedValue = $0.rounded() }),
                  format: .number.precision(.fractionLength(0)))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .frame(width: 56)
            .labelsHidden()
    }
}

/// The frames of the scene from its start to past the end played, numbered as Blender numbers
/// them; the part played is lit, the selected object's keys are marked, and the frame the scene
/// stands at is boxed with its number. A drag goes along it.
private struct EngineFrameRuler: View {
    @ObservedObject var model: EngineEditorModel
    static let height: CGFloat = 40

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let rate = model.timelineRate
            let margin: CGFloat = 16
            // A little past the end, so that the end shows as a line and not as the edge.
            let frames = max(model.playLength * rate * 1.04, 2)
            Canvas { context, size in
                func x(_ frame: Double) -> CGFloat { margin + CGFloat(frame / frames) * (size.width - margin * 2) }
                let start = x(model.playStart * rate), end = x(model.playLength * rate)
                context.fill(Path(CGRect(x: start, y: 0, width: max(0, end - start), height: size.height)), with: .color(.accentColor.opacity(0.07)))
                // A number every so many frames, as many as have room.
                let step = [1.0, 2, 5, 10, 12, 24, 30, 50, 60, 100, 120, 250, 500].first { x($0) - x(0) >= 42 } ?? 1000
                var frame = 0.0
                while frame <= frames {
                    let at = x(frame)
                    var line = Path()
                    line.move(to: CGPoint(x: at, y: 18))
                    line.addLine(to: CGPoint(x: at, y: size.height))
                    context.stroke(line, with: .color(.primary.opacity(0.1)))
                    context.draw(Text(verbatim: "\(Int(frame))").font(.caption).foregroundColor(.secondary),
                                 at: CGPoint(x: at, y: 3), anchor: .top)
                    frame += step
                }
                for edge in [start, end] {
                    var line = Path()
                    line.move(to: CGPoint(x: edge, y: 18))
                    line.addLine(to: CGPoint(x: edge, y: size.height))
                    context.stroke(line, with: .color(.primary.opacity(0.35)), lineWidth: 1)
                }
                // The selected object's keys, each round of its animations as the scene plays them.
                for seconds in model.keyMoments(upTo: frames / rate) {
                    let at = x(seconds * rate), r: CGFloat = 4, y = size.height - 10
                    var diamond = Path()
                    diamond.move(to: CGPoint(x: at, y: y - r))
                    diamond.addLine(to: CGPoint(x: at + r, y: y))
                    diamond.addLine(to: CGPoint(x: at, y: y + r))
                    diamond.addLine(to: CGPoint(x: at - r, y: y))
                    diamond.closeSubpath()
                    context.fill(diamond, with: .color(.primary.opacity(0.7)))
                }
                let current = (model.timelineSeconds * rate).rounded()
                let head = x(min(current, frames))
                var line = Path()
                line.move(to: CGPoint(x: head, y: 16))
                line.addLine(to: CGPoint(x: head, y: size.height))
                context.stroke(line, with: .color(.accentColor), lineWidth: 2)
                let label = Text(verbatim: "\(Int(current))").font(.caption.monospacedDigit().weight(.semibold)).foregroundColor(.white)
                let box = CGRect(x: head - 16, y: 0, width: 32, height: 17)
                context.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(.accentColor))
                context.draw(label, at: CGPoint(x: head, y: 8.5), anchor: .center)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let share = Double((drag.location.x - margin) / max(width - margin * 2, 1))
                model.timelineSeconds = (max(0, min(1, share)) * frames).rounded() / rate
            })
        }
        .frame(height: Self.height)
        .help("Drag to go along the scene's time")
    }
}

extension EngineEditorModel {
    /// The moments of the scene the selected object's keys stand at, up to a moment.
    func keyMoments(upTo end: Double) -> [Double] {
        guard let id = selection else { return [] }
        var moments: Set<Double> = []
        for target in document.animatedTargets(of: id) {
            guard let animation = document.animation(of: id, target), animation.duration > 0 else { continue }
            let duration = animation.duration
            var round = 0.0
            while round * duration <= end, moments.count < 2000 {
                for frame in animation.keyFrames {
                    let own = frame / animation.rate
                    let seconds: Double
                    switch animation.options.mode {
                    case .loop: seconds = round * duration + own
                    case .mirror: seconds = round * duration + (Int(round) % 2 == 0 ? own : duration - own)
                    case .single: seconds = round == 0 ? own : .infinity
                    }
                    if seconds <= end { moments.insert(seconds) }
                }
                if animation.options.mode == .single { break }
                round += 1
            }
        }
        return Array(moments)
    }
}

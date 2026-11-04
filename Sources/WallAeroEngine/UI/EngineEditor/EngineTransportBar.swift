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
            Text(verbatim: Self.clock(model.timelineSeconds))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help("The moment of the scene")
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                Button { model.jumpToStart() } label: { Image(systemName: "backward.end.fill") }
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
            }
            .buttonStyle(.borderless)
            Spacer(minLength: 8)
            frameField(Binding(get: { model.timelineSeconds * rate }, set: { model.timelineSeconds = max(0, $0) / rate }))
                .help("Frame")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    /// A moment as minutes, seconds and hundredths.
    static func clock(_ seconds: Double) -> String {
        let whole = max(0, seconds)
        return String(format: "%d:%05.2f", Int(whole) / 60, whole.truncatingRemainder(dividingBy: 60))
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
    @State private var dragFrames: Double?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let rate = model.timelineRate
            let margin: CGFloat = 16
            // While dragged, the ruler keeps the length it had: it would grow under the pointer.
            let frames = dragFrames ?? max(model.playLength * rate, 2)
            Canvas { context, size in
                func x(_ frame: Double) -> CGFloat { margin + CGFloat(frame / frames) * (size.width - margin * 2) }
                // A number every so many frames, as many as have room.
                let step = [1.0, 2, 5, 10, 12, 24, 30, 50, 60, 100, 120, 250, 500, 1000, 2500, 5000].first { x($0) - x(0) >= 42 } ?? 1000
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
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if dragFrames == nil { dragFrames = frames }
                    let share = Double((drag.location.x - margin) / max(width - margin * 2, 1))
                    model.timelineSeconds = (max(0, min(1, share)) * frames).rounded() / rate
                }
                .onEnded { _ in dragFrames = nil })
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

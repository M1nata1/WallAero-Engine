import SwiftUI
import WallpaperCore

/// The scene's time, always under the scene, as Blender's timeline has it: playing and holding,
/// going to the start, the end and the keys, the moment, the part of the time played, and a
/// ruler to go along it. The scene moves only by it: the editor opens with the scene standing
/// at the start.
struct EngineTransportBar: View {
    @ObservedObject var model: EngineEditorModel

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Button { model.jump(toEnd: false) } label: { Image(systemName: "backward.end.fill") }
                    .help("Jump to Start (Shift ←)")
                Button { model.jumpToKey(forward: false) } label: { Image(systemName: "backward.frame.fill") }
                    .help("Previous Keyframe (↓)")
                    .disabled(model.activeAnimation == nil)
                Button { model.isPlaying.toggle() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 18)
                }
                .help(model.isPlaying ? "Pause (Space)" : "Play (Space)")
                Button { model.jumpToKey(forward: true) } label: { Image(systemName: "forward.frame.fill") }
                    .help("Next Keyframe (↑)")
                    .disabled(model.activeAnimation == nil)
                Button { model.jump(toEnd: true) } label: { Image(systemName: "forward.end.fill") }
                    .help("Jump to End (Shift →)")
            }
            .buttonStyle(.borderless)
            secondsField(Binding(get: { model.timelineSeconds }, set: { model.timelineSeconds = max(0, $0) }))
                .help("The moment of the scene, in seconds")
            Text(verbatim: "\(Int((model.timelineSeconds * model.timelineRate).rounded()))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .leading)
                .help("Frame")
            EngineTransportRuler(model: model)
                .frame(minWidth: 120, maxWidth: .infinity)
            HStack(spacing: 4) {
                Text("Start").foregroundStyle(.secondary)
                secondsField(Binding(get: { model.playStart }, set: { model.playStart = max(0, min($0, model.playLength - 1 / 30)) }))
                Text("End").foregroundStyle(.secondary)
                secondsField(Binding(get: { model.playLength }, set: { model.playEnd = max($0, model.playStart + 1 / 30) }))
            }
            .help("The part of the time played. With no end set, the longest animation of the scene ends it.")
            Toggle(isOn: $model.playsRound) { Image(systemName: "repeat") }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help("Play Round and Round")
        }
        .font(.callout)
        .padding(.horizontal, SystemLook.barHorizontalPadding)
        .padding(.vertical, 4)
    }

    private func secondsField(_ value: Binding<Double>) -> some View {
        TextField("", value: value, format: .number.precision(.fractionLength(0...2)))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 56)
            .labelsHidden()
    }
}

/// The scene's time from its start to the end played: the part played is lit, the selected
/// object's keys are marked, and a drag goes along it.
private struct EngineTransportRuler: View {
    @ObservedObject var model: EngineEditorModel

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width, height = geometry.size.height
            let length = max(model.playLength, 0.001)
            Canvas { context, size in
                func x(_ seconds: Double) -> CGFloat { CGFloat(seconds / length) * size.width }
                let track = CGRect(x: 0, y: size.height / 2 - 3, width: size.width, height: 6)
                context.fill(Path(roundedRect: track, cornerRadius: 3), with: .color(.primary.opacity(0.1)))
                let played = CGRect(x: x(model.playStart), y: track.minY, width: max(0, x(model.playLength) - x(model.playStart)), height: track.height)
                context.fill(Path(roundedRect: played, cornerRadius: 3), with: .color(.accentColor.opacity(0.25)))
                // The selected object's keys, each round of its animations as the scene plays them.
                for seconds in model.keyMoments(upTo: length) {
                    let at = x(seconds), r: CGFloat = 3.5, y = size.height / 2
                    var diamond = Path()
                    diamond.move(to: CGPoint(x: at, y: y - r))
                    diamond.addLine(to: CGPoint(x: at + r, y: y))
                    diamond.addLine(to: CGPoint(x: at, y: y + r))
                    diamond.addLine(to: CGPoint(x: at - r, y: y))
                    diamond.closeSubpath()
                    context.fill(diamond, with: .color(.primary.opacity(0.6)))
                }
                let head = x(min(model.timelineSeconds, length))
                var line = Path()
                line.move(to: CGPoint(x: head, y: 2))
                line.addLine(to: CGPoint(x: head, y: size.height - 2))
                context.stroke(line, with: .color(.accentColor), lineWidth: 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let rate = model.timelineRate
                let seconds = Double(max(0, min(width, drag.location.x)) / max(width, 1)) * length
                model.timelineSeconds = (seconds * rate).rounded() / rate
            })
            .frame(height: height)
        }
        .frame(height: 22)
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

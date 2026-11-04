import AppKit
import SwiftUI
import WallpaperCore

/// A moment of the timeline: of one number of a value, or of them all.
struct EngineTimelineKey: Hashable {
    let target: WallpaperEngineAnimationTarget
    var frame: Double
    var channel: Int?
}

/// A moment put aside by Copy, with where it stands from the first of those copied.
struct EngineCopiedKey {
    let target: WallpaperEngineAnimationTarget
    let offset: Double
    let channel: Int
    let value: Double
}

/// The timeline of the selected object: Wallpaper Engine's timeline animations, shown and played
/// by the editor. It stands at a moment of the scene, in seconds, and what is changed of an
/// animated value in the inspector or on the scene is written as a moment there.
extension EngineEditorModel {
    typealias Target = WallpaperEngineAnimationTarget

    /// What of the selected object has an animation.
    var timelineTargets: [Target] {
        let values = selection.map(document.animatedTargets(of:)) ?? []
        return mode == .pose ? boneTargets + values : values + boneTargets
    }

    /// The bones on the timeline: with Only Selected on in Pose Mode the one selected, else
    /// those that have keys in the animation it is on.
    private var boneTargets: [Target] {
        guard let rig = selectedRig, rig.animations.indices.contains(rigAnimation) else { return [] }
        if mode == .pose, timelineOnlySelected, let selectedBone { return [.bone(animation: rigAnimation, bone: selectedBone)] }
        var bones = rig.animations[rigAnimation].keys.filter { !$0.value.isEmpty }.keys.sorted()
        if let selectedBone, !bones.contains(selectedBone) { bones.append(selectedBone) }
        return bones.map { .bone(animation: rigAnimation, bone: $0) }
    }

    func animation(_ target: Target) -> WallpaperEngineAnimation? {
        selection.flatMap { document.animation(of: $0, target) }
    }

    /// The animation the timeline's keys are for.
    var activeAnimation: WallpaperEngineAnimation? {
        timelineTarget.flatMap(animation) ?? animation(.bone(animation: rigAnimation, bone: 0))
    }

    /// Goes on to a row of the timeline; a bone's row selects the bone.
    func pickTrack(_ target: Target) {
        timelineTarget = target
        selectedKeys = []
        if case .bone(_, let bone) = target { selectedBone = bone }
    }

    /// The frame the timeline stands at, of the animation it is on: round its loop, as it plays.
    var timelineFrame: Double {
        guard let activeAnimation else { return 0 }
        return frame(of: activeAnimation)
    }

    /// The frame of an animation at the scene's moment.
    func frame(of animation: WallpaperEngineAnimation) -> Double {
        (Self.ownSeconds(timelineSeconds, length: animation.duration, mode: animation.options.mode) * animation.rate).rounded()
    }

    /// The moment the keys of the animation the timeline is on stand at.
    var keySeconds: Double {
        guard let activeAnimation else { return timelineSeconds }
        return Self.ownSeconds(timelineSeconds, length: activeAnimation.duration, mode: activeAnimation.options.mode)
    }

    /// Has the keys stand at a moment of their animation: in the round of a loop the scene is
    /// in, else from the start.
    func setKeySeconds(_ seconds: Double) {
        guard let animation = activeAnimation, animation.options.mode == .loop else {
            timelineSeconds = max(0, seconds)
            return
        }
        timelineSeconds = max(0, timelineSeconds - keySeconds + seconds)
    }

    /// A moment of the scene as a moment of an animation that lasts so long and plays so: it
    /// starts over, comes back, or stays at its end.
    static func ownSeconds(_ seconds: Double, length: Double, mode: WallpaperEngineAnimation.Mode) -> Double {
        guard length > 0, seconds > 0 else { return max(0, seconds) }
        switch mode {
        case .loop:
            // Its last moment is its first again: at the end of a round it stands at the end.
            let into = seconds.truncatingRemainder(dividingBy: length)
            return into < 1e-9 ? length : into
        case .mirror:
            let into = seconds.truncatingRemainder(dividingBy: length * 2)
            return into > length ? length * 2 - into : into
        case .single:
            return min(seconds, length)
        }
    }

    /// The target to show when another object is selected.
    func timelineDidChangeObject() {
        selectedKeys = []
        timelineTarget = timelineTargets.first
    }

    func title(of target: Target) -> String {
        switch target {
        case .value(let key):
            let titles = ["origin": "Position", "scale": "Scale", "angles": "Rotation", "alpha": "Opacity", "color": "Color"]
            return titles[key].map { NSLocalizedString($0, comment: "A value of an object on the timeline") } ?? key
        case .effect(let index, _, let name):
            guard let id = selection, let effect = description?.object(id)?.effects.first(where: { $0.id == index }) else { return name }
            let value = effect.values.first { $0.name == name }
            return "\(effect.title): \(value?.title ?? name)"
        case .bone(_, let bone):
            guard let rig = selectedRig, rig.bones.indices.contains(bone) else { return "" }
            return boneTitle(rig.bones[bone])
        }
    }

    /// The numbers of a value at the moment the timeline stands at.
    func numbers(of id: Int, _ target: Target, base: [Double]) -> [Double]? {
        document.animation(of: id, target)?.numbers(atSeconds: timelineSeconds, base: base)
    }

    private func baseNumbers(of id: Int, _ target: Target, fallback: [Double] = []) -> [Double] {
        if case .bone = target { return Array(repeating: 0, count: 5) }
        var numbers = document.rawValue(of: id, target)?.vector ?? fallback
        let wanted = document.animation(of: id, target)?.channelCount ?? 0
        while numbers.count < wanted { numbers.append(0) }
        return numbers
    }

    /// Writes numbers of an animated value at the moment the timeline stands at. Without
    /// `autoKey` only moments that are there take them. False when the value has no animation.
    func writeAnimated(_ id: Int, _ target: Target, numbers new: [Double]) -> Bool {
        guard var animation = document.animation(of: id, target) else { return false }
        let base = baseNumbers(of: id, target, fallback: new)
        let shown = animation.numbers(atSeconds: timelineSeconds, base: base)
        let frame = self.frame(of: animation)
        for channel in 0..<min(new.count, animation.channelCount) where abs(new[channel] - shown[channel]) > 1e-6 {
            guard autoKey || animation.keys(channel).contains(where: { $0.frame == frame }) else { continue }
            animation.setKey(frame: frame, channel: channel, value: new[channel] - (animation.isRelative ? base[channel] : 0))
        }
        document.setAnimation(animation, of: id, target)
        if !showsTimeline { showsTimeline = true }
        return true
    }

    // MARK: - Binding

    /// How a new animation starts out: as long as the last one made, and three seconds at first.
    func newAnimationOptions(for target: Target) -> WallpaperEngineAnimation.Options {
        if let last = timelineTargets.last.flatMap(animation) {
            var options = last.options
            options.name = ""
            options.startsPaused = false
            return options
        }
        return .init()
    }

    func bindAnimation(_ target: Target, options: WallpaperEngineAnimation.Options, fallback: [Double]) {
        guard let id = selection else { return }
        change { $0.bindAnimation(of: id, target, options: options, fallback: fallback) }
        timelineTarget = target
        selectedKeys = []
        showsTimeline = true
    }

    func unbindAnimation(_ target: Target) {
        guard let id = selection else { return }
        change { $0.unbindAnimation(of: id, target) }
        if timelineTarget == target { timelineTarget = timelineTargets.first }
        selectedKeys = []
    }

    /// How it plays; those that play along with it take that on, and it is said which it plays
    /// along with itself, if any. That is settled as the scene starts, so it starts anew then.
    func setOptions(_ options: WallpaperEngineAnimation.Options, of target: Target, leader: String?) {
        guard let id = selection, var animation = document.animation(of: id, target) else { return }
        animation.options = options
        let relinks = animation.leader != leader
        change { document in
            document.setAnimation(animation, of: id, target)
            for follower in animation.followers {
                guard var own = document.animation(of: id, .value(follower)) else { continue }
                var said = own.options
                said.fps = options.fps
                said.length = options.length
                said.mode = options.mode
                said.wrapsLoop = options.wrapsLoop
                own.options = said
                document.setAnimation(own, of: id, .value(follower))
            }
            if relinks, case .value(let key) = target { document.linkAnimation(of: id, key, to: leader) }
        }
        if relinks { preview?.reload() }
    }

    /// The values of the selected object an animation can play along with: those animated
    /// that lead, or play on their own, other than itself and those that follow it.
    func possibleLeaders(of target: Target) -> [String] {
        guard let animation = animation(target) else { return [] }
        return timelineTargets.compactMap { other -> String? in
            guard other != target, case .value(let key) = other, !animation.followers.contains(key),
                  self.animation(other)?.leader == nil else { return nil }
            return key
        }
    }

    /// Whether the selected moments' handles are locked together.
    var selectedLocks: (angle: Bool, length: Bool)? {
        guard let key = selectedKeys.first, let channel = key.channel, let animation = animation(key.target),
              selectedInterpolation == .both else { return nil }
        return animation.locks(frame: key.frame, channel: channel)
    }

    func setSelectedLocks(angle: Bool, length: Bool) {
        editSelected { key, animation in
            guard let channel = key.channel else { return }
            animation.setLocks(angle: angle, length: length, frame: key.frame, channel: channel)
        }
    }

    // MARK: - Moments

    private func editActive(_ edit: (inout WallpaperEngineAnimation) -> Void) {
        guard let id = selection, let target = timelineTarget, var animation = document.animation(of: id, target) else { return }
        edit(&animation)
        change { $0.setAnimation(animation, of: id, target) }
    }

    /// Puts a moment at the frame the timeline stands at, or takes away the one there.
    func toggleKey() {
        guard let id = selection, let target = timelineTarget, let animation = activeAnimation else { return }
        let frame = timelineFrame
        if animation.keyFrames.contains(frame) {
            editActive { $0.removeKey(frame: frame) }
            selectedKeys = []
            return
        }
        let base = baseNumbers(of: id, target)
        let shown = draftNumbers(of: target) ?? animation.numbers(atSeconds: timelineSeconds, base: base)
        poseDraft = [:]
        editActive { edited in
            // A bone's first key also holds it at the start, so it does not jump there.
            if case .bone = target, edited.keyFrames.isEmpty, frame != 0 {
                for channel in 0..<edited.channelCount { edited.setKey(frame: 0, channel: channel, value: 0) }
            }
            for channel in 0..<edited.channelCount where channel < shown.count {
                edited.setKey(frame: frame, channel: channel, value: shown[channel] - (edited.isRelative ? base[channel] : 0))
            }
        }
        selectedKeys = [EngineTimelineKey(target: target, frame: frame, channel: nil)]
    }

    /// Changes the animations the selected moments belong to, as one step to take back.
    private func editSelected(_ edit: (EngineTimelineKey, inout WallpaperEngineAnimation) -> Void) {
        guard let id = selection else { return }
        change { document in
            for (target, keys) in Dictionary(grouping: selectedKeys, by: \.target) {
                guard var animation = document.animation(of: id, target) else { continue }
                keys.forEach { edit($0, &animation) }
                document.setAnimation(animation, of: id, target)
            }
        }
    }

    func deleteSelectedKeys() {
        editSelected { key, animation in animation.removeKey(frame: key.frame, channel: key.channel) }
        selectedKeys = []
    }

    /// Moves the selected moments by the same time, and on the curves up or down, from how they
    /// stood when the drag began; what it does is one step to take back.
    func moveKeys(_ keys: [EngineTimelineKey], from base: WallpaperEngineDocument, bySeconds seconds: Double, value: Double? = nil) {
        guard let id = selection else { return }
        var moved = base
        var selected: Set<EngineTimelineKey> = []
        for (target, group) in Dictionary(grouping: keys, by: \.target) {
            guard var animation = base.animation(of: id, target) else { continue }
            // None goes before the start, and the group keeps its shape.
            let earliest = group.map(\.frame).min() ?? 0
            let by = max((seconds * animation.rate).rounded(), -earliest)
            for key in group.sorted(by: { by > 0 ? $0.frame > $1.frame : $0.frame < $1.frame }) {
                let frame = key.frame + by
                if let value, let channel = key.channel,
                   let old = base.animation(of: id, target)?.keys(channel).first(where: { $0.frame == key.frame }) {
                    animation.moveKey(from: key.frame, to: frame, channel: channel)
                    animation.setKey(frame: frame, channel: channel, value: old.value + value)
                } else {
                    animation.moveKey(from: key.frame, to: frame, channel: key.channel)
                }
                selected.insert(EngineTimelineKey(target: target, frame: frame, channel: key.channel))
            }
            moved.setAnimation(animation, of: id, target)
        }
        document = moved
        selectedKeys = selected
    }

    /// Moves the end of a handle of a moment, in frames and in value from the moment.
    func moveHandle(_ side: WallpaperEngineAnimation.Side, of key: EngineTimelineKey, x: Double, y: Double) {
        guard let id = selection, let channel = key.channel, var animation = document.animation(of: id, key.target) else { return }
        animation.moveHandle(side, frame: key.frame, channel: channel, x: x, y: y)
        document.setAnimation(animation, of: id, key.target)
    }

    var selectedInterpolation: WallpaperEngineAnimation.Interpolation? {
        // A bone eases from key to key, as its animation is written to Wallpaper Engine.
        guard let key = selectedKeys.first else { return nil }
        if case .bone = key.target { return nil }
        return animation(key.target)?.interpolation(frame: key.frame, channel: key.channel)
    }

    func setSelectedInterpolation(_ interpolation: WallpaperEngineAnimation.Interpolation) {
        editSelected { key, animation in animation.setInterpolation(interpolation, frame: key.frame, channel: key.channel) }
    }

    // MARK: - Copying moments

    func copySelectedKeys() {
        guard let id = selection else { return }
        let first = selectedKeys.map(\.frame).min() ?? 0
        timelineClipboard = selectedKeys.flatMap { key -> [EngineCopiedKey] in
            guard let animation = document.animation(of: id, key.target) else { return [] }
            return (key.channel.map { [$0] } ?? Array(0..<animation.channelCount)).compactMap { channel in
                animation.keys(channel).first { $0.frame == key.frame }.map {
                    EngineCopiedKey(target: key.target, offset: key.frame - first, channel: channel, value: $0.value)
                }
            }
        }
    }

    /// Puts the moments copied at the moment the timeline stands at. Copied from one value they
    /// go on the one the timeline is on, if it has their numbers; from several, back on those.
    func pasteKeys() {
        guard let id = selection, !timelineClipboard.isEmpty else { return }
        let targets = Set(timelineClipboard.map(\.target))
        var selected: Set<EngineTimelineKey> = []
        change { document in
            for copied in timelineClipboard {
                let target = targets.count == 1 ? timelineTarget ?? copied.target : copied.target
                guard var animation = document.animation(of: id, target), copied.channel < animation.channelCount else { continue }
                let frame = self.frame(of: animation) + copied.offset
                animation.setKey(frame: frame, channel: copied.channel, value: copied.value)
                document.setAnimation(animation, of: id, target)
                selected.insert(EngineTimelineKey(target: target, frame: frame, channel: nil))
            }
        }
        selectedKeys = selected
    }

    func setEvents(_ events: [WallpaperEngineAnimation.Event], of target: Target) {
        guard let id = selection, var animation = document.animation(of: id, target) else { return }
        animation.events = events.sorted { $0.frame < $1.frame }
        change { $0.setAnimation(animation, of: id, target) }
    }

    // MARK: - How the time is shown

    /// How many seconds there are to show: to the end of the longest animation of the object.
    var timelineTotal: Double {
        max(timelineTargets.compactMap { animation($0)?.duration }.max() ?? 1, 0.1)
    }

    /// The seconds the width of the timeline shows.
    var timelineShown: Double { timelineSpan ?? timelineTotal }

    /// Enlarges the time around a place of the timeline, given as a share of its width.
    func zoomTimeline(by factor: Double, atShare share: Double) {
        let total = timelineTotal, shown = timelineShown
        let next = min(max(shown / factor, min(total, 2 / max(activeAnimation?.rate ?? 30, 1) * 8)), total)
        timelineStart = max(0, min(total - next, timelineStart + (shown - next) * share))
        timelineSpan = next >= total ? nil : next
    }

    func panTimeline(bySeconds seconds: Double) {
        timelineStart = max(0, min(timelineTotal - timelineShown, timelineStart + seconds))
    }

    /// Enlarges the heights of the curves around their middle.
    func zoomCurves(by factor: Double, around range: ClosedRange<Double>) {
        let middle = (range.lowerBound + range.upperBound) / 2, half = (range.upperBound - range.lowerBound) / 2 / factor
        curveRange = (middle - half)...(middle + half)
    }

    /// The heights of the curves changed from the wheel: from what they show now.
    func zoomCurvesFromWheel(by factor: Double) {
        guard let animation = activeAnimation else { return }
        zoomCurves(by: factor, around: curveRange ?? EngineTimelineCurves.fitted(animation))
    }

    func fitTimeline() {
        timelineSpan = nil
        timelineStart = 0
        curveRange = nil
    }

    // MARK: - Going through time

    /// How long the timeline is: the end set, or the longest animation of the scene, and ten
    /// seconds at least: particles and scripts take a while to show what they do.
    var playLength: Double {
        if let playEnd { return max(playEnd, playStart + 1 / 30) }
        return max(longestAnimation, 10, playStart + 1 / 30)
    }

    /// The longest of the scene's animations, in seconds.
    var longestAnimation: Double {
        var longest = 0.0
        for object in document.objects {
            guard let number = object["id"]?.numberValue else { continue }
            let id = Int(number)
            for target in document.animatedTargets(of: id) {
                longest = max(longest, document.animation(of: id, target)?.duration ?? 0)
            }
        }
        if let rig = selectedRig {
            longest = max(longest, rig.animations.map { Double($0.length) / max($0.framesPerSecond, 1) }.max() ?? 0)
        }
        return longest
    }

    /// Frames a second of the timeline: the animation's it is on, else thirty.
    var timelineRate: Double { activeAnimation?.rate ?? 30 }

    /// Moves the scene's moment by frames.
    func stepFrame(_ by: Double) {
        let rate = timelineRate
        timelineSeconds = max(0, ((timelineSeconds * rate).rounded() + by) / rate)
    }

    /// Goes to the next key of the animation the timeline is on, or the one before, in the
    /// round of it the scene is in.
    func jumpToKey(forward: Bool) {
        guard let animation = activeAnimation else { return }
        let frame = timelineFrame
        let next = forward ? animation.keyFrames.first { $0 > frame } : animation.keyFrames.last { $0 < frame }
        if let next { timelineSeconds = max(0, timelineSeconds + (next - frame) / animation.rate) }
    }

    func jump(toEnd: Bool) {
        timelineSeconds = toEnd ? playLength : playStart
    }

    /// Plays the scene from where the timeline stands, or holds it there.
    func setTimelinePlaying(_ playing: Bool) {
        isPlaying = playing
    }

    /// Stops playing and goes back to where the timeline stood before it played, as Escape does
    /// in Blender.
    func cancelPlaying() {
        guard isPlaying else { return }
        isPlaying = false
        timelineSeconds = playedFrom
    }

    /// The scene plays on by itself; the timeline follows it, and from its end goes back to the
    /// start, or stops there.
    func playingDidChange() {
        playTimer?.invalidate()
        playTimer = nil
        if isPlaying {
            if timelineSeconds >= playLength - 1e-6 || timelineSeconds < playStart { timelineSeconds = playStart }
            playedFrom = timelineSeconds
        }
        preview?.setPlaying(isPlaying)
        guard isPlaying else {
            // Where it stopped is where it stands, on to the next whole frame: a moment gone
            // by would have the scene played anew to come back to it.
            let rate = timelineRate
            followsPlayback = true
            timelineSeconds = ((preview?.sceneTime ?? timelineSeconds) * rate - 1e-6).rounded(.up) / rate
            followsPlayback = false
            showTimelineMoment()
            return
        }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followPlaying() }
        }
        RunLoop.main.add(timer, forMode: .common)
        playTimer = timer
    }

    private func followPlaying() {
        guard isPlaying, let preview, let now = preview.sceneTime else { return }
        guard now >= playLength else {
            followsPlayback = true
            timelineSeconds = now
            followsPlayback = false
            showRig()
            if viewsFreely { refreshCameraView() }
            return
        }
        if playsRound {
            timelineSeconds = playStart
            preview.setPlaying(true)
        } else {
            followsPlayback = true
            isPlaying = false
            followsPlayback = false
            timelineSeconds = playLength
        }
    }
}

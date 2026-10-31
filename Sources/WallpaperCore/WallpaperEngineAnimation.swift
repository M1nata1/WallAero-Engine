import Foundation

/// A value of a scene's object that changes over time: Wallpaper Engine's timeline animation.
/// A scene keeps it beside the value, as `{"animation": {"c0": [...], "options": {...}}, "value": …}`,
/// a list of moments for each of the value's numbers. What the app does not know of it (events,
/// other animations it plays along with) stays as it came.
public struct WallpaperEngineAnimation: Equatable, Sendable {
    /// Where a curve leaving or reaching a moment is drawn towards, as Wallpaper Engine's editor
    /// draws it: `x` in halves of the way to the moment on that side, from 0 to 2 before its
    /// sign, `y` in the value's own numbers. One marked `magic` is worked out from the moments
    /// around it whenever they change, and written like any other.
    public struct Handle: Equatable, Sendable {
        public var x, y: Double
        public var magic: Bool
    }

    public struct Key: Equatable, Sendable {
        public var frame, value: Double
        public var front, back: Handle?
    }

    public enum Mode: String, CaseIterable, Sendable {
        case loop
        case mirror
        case single
    }

    public struct Options: Equatable, Sendable {
        public var fps: Double
        /// How many frames it lasts.
        public var length: Double
        public var mode: Mode
        public var name: String
        public var startsPaused: Bool
        /// Whether a loop goes on from its last moment to its first, so that it has no jump.
        public var wrapsLoop: Bool

        public init(fps: Double = 30, length: Double = 90, mode: Mode = .loop, name: String = "",
                    startsPaused: Bool = false, wrapsLoop: Bool = false) {
            self.fps = fps
            self.length = length
            self.mode = mode
            self.name = name
            self.startsPaused = startsPaused
            self.wrapsLoop = wrapsLoop
        }
    }

    /// How a moment joins the curve on both sides: Wallpaper Engine's five.
    public enum Interpolation: CaseIterable, Sendable {
        /// Smoothly, as the player sees fit, which is what a new moment does.
        case automatic
        /// In straight lines.
        case linear
        /// With a handle to draw the curve by on the side before the moment, after it, or both.
        case back
        case front
        case both
    }

    public enum Side: String, Sendable {
        case back
        case front
    }

    /// A name scripts are told of when the animation passes a frame.
    public struct Event: Equatable, Sendable {
        public var frame: Double
        public var name: String

        public init(frame: Double, name: String) {
            self.frame = frame
            self.name = name
        }
    }

    /// The `animation` of the value, as the scene has it.
    public private(set) var raw: JSONValue

    public init?(raw: JSONValue) {
        guard raw.objectValue != nil else { return nil }
        self.raw = raw
        guard channelCount > 0 else { return nil }
    }

    /// A new animation, with a first moment on every number of the value.
    public init(values: [Double], options: Options) {
        raw = .object([:])
        self.options = options
        for (channel, value) in values.enumerated() {
            setKey(frame: 0, channel: channel, value: value)
        }
    }

    public var channelCount: Int {
        let names = raw.objectValue?.keys.compactMap { $0.hasPrefix("c") ? Int($0.dropFirst()) : nil } ?? []
        return (names.max() ?? -1) + 1
    }

    /// Whether the numbers are counted from what the scene says of the value.
    public var isRelative: Bool { raw["relative"]?.boolValue == true }

    public var options: Options {
        get {
            let said = raw["options"]
            return Options(fps: said?["fps"]?.numberValue ?? 30, length: said?["length"]?.numberValue ?? 0,
                           mode: Mode(rawValue: said?["mode"]?.stringValue?.lowercased() ?? "") ?? .loop,
                           name: said?["name"]?.stringValue ?? "", startsPaused: said?["startpaused"]?.boolValue ?? false,
                           wrapsLoop: said?["wraploop"]?.boolValue ?? false)
        }
        set {
            var said = raw["options"] ?? .object([:])
            said["fps"] = .number(newValue.fps)
            said["length"] = .number(newValue.length)
            said["mode"] = .string(newValue.mode.rawValue)
            said["name"] = newValue.name.isEmpty ? nil : .string(newValue.name)
            said["startpaused"] = newValue.startsPaused ? .bool(true) : nil
            said["wraploop"] = .bool(newValue.wrapsLoop)
            raw["options"] = said
        }
    }

    /// The value of the same object this one plays along with.
    public var leader: String? {
        get { raw["options"]?["parent"]?["key"]?.stringValue }
        set {
            var said = raw["options"] ?? .object([:])
            said["parent"] = newValue.map { .object(["key": .string($0)]) }
            raw["options"] = said
        }
    }

    /// The values of the same object that play along with this one.
    public var followers: [String] {
        get { (raw["options"]?["children"]?.arrayValue ?? []).compactMap { $0["key"]?.stringValue } }
        set {
            var said = raw["options"] ?? .object([:])
            said["children"] = newValue.isEmpty ? nil : .array(newValue.map { .object(["key": .string($0)]) })
            raw["options"] = said
        }
    }

    /// Takes on how long another lasts and how it plays.
    mutating func playsAlong(with leader: WallpaperEngineAnimation) {
        var own = options
        let theirs = leader.options
        own.fps = theirs.fps
        own.length = theirs.length
        own.mode = theirs.mode
        own.wrapsLoop = theirs.wrapsLoop
        options = own
    }

    public var events: [Event] {
        get {
            (raw["options"]?["events"]?.arrayValue ?? []).compactMap { each in
                guard let frame = each["frame"]?.numberValue, let name = each["name"]?.stringValue else { return nil }
                return Event(frame: frame, name: name)
            }
        }
        set {
            var said = raw["options"] ?? .object([:])
            said["events"] = newValue.isEmpty ? nil : .array(newValue.map {
                .object(["frame": .number($0.frame), "name": .string($0.name)])
            })
            raw["options"] = said
        }
    }

    /// How many frames a play through lasts: what it says, or up to its last moment.
    public var length: Double {
        let said = options.length
        guard said <= 0 else { return said }
        return (0..<channelCount).compactMap { keys($0).last?.frame }.max() ?? 0
    }

    public var rate: Double { options.fps > 0 ? options.fps : 30 }
    public var duration: Double { length / rate }

    // MARK: - Moments

    public func keys(_ channel: Int) -> [Key] {
        (raw["c\(channel)"]?.arrayValue ?? []).compactMap { each in
            guard let frame = each["frame"]?.numberValue, let value = each["value"]?.numberValue else { return nil }
            return Key(frame: frame, value: value, front: Self.handle(each["front"]), back: Self.handle(each["back"]))
        }
        .sorted { $0.frame < $1.frame }
    }

    private static func handle(_ said: JSONValue?) -> Handle? {
        guard let said, said["enabled"]?.boolValue == true else { return nil }
        return Handle(x: said["x"]?.numberValue ?? 0, y: said["y"]?.numberValue ?? 0, magic: said["magic"]?.boolValue == true)
    }

    /// The frames that have a moment on any of the numbers, in order.
    public var keyFrames: [Double] {
        Array(Set((0..<channelCount).flatMap { keys($0).map(\.frame) })).sorted()
    }

    private mutating func editKeys(_ channel: Int, _ change: (inout [JSONValue]) -> Void) {
        var list = raw["c\(channel)"]?.arrayValue ?? []
        change(&list)
        list.sort { ($0["frame"]?.numberValue ?? 0) < ($1["frame"]?.numberValue ?? 0) }
        workOutMagicHandles(&list)
        raw["c\(channel)"] = .array(list)
    }

    /// The handles left to the app, by Wallpaper Engine's own sums: as steep as the way from the
    /// moment before to the one after, leaning towards the side that has the shorter way. Only
    /// what is edited comes here: a file read and not changed stays as it came.
    private func workOutMagicHandles(_ list: inout [JSONValue]) {
        let round = wraps
        let frames = list.map { $0["frame"]?.numberValue ?? 0 }, values = list.map { $0["value"]?.numberValue ?? 0 }
        for index in list.indices {
            var before = index > 0 ? index - 1 : (round ? list.count - 1 : 0)
            var after = index + 1 < list.count ? index + 1 : (round ? 0 : list.count - 1)
            if !round {
                if index == list.count - 1 { after = before } else if index == 0 { before = after }
            }
            let rise = values[after] - values[before]
            var gapBefore = abs(frames[index] - frames[before]), gapAfter = abs(frames[after] - frames[index])
            if frames[before] > frames[index] { gapBefore = frames[index] + length - frames[before] }
            if frames[after] < frames[index] { gapAfter = frames[after] + length - frames[index] }
            if gapBefore == 0 { gapBefore = 1 }
            if gapAfter == 0 { gapAfter = 1 }
            let ratio = gapAfter / gapBefore
            var riseBack = rise, riseFront = rise, sideBack = 0.5, sideFront = 0.5
            if ratio > 1 {
                riseBack /= ratio
                sideFront /= ratio
            } else if ratio < 1 {
                riseFront *= ratio
                sideBack *= ratio
            }
            if list[index]["back"]?["magic"]?.boolValue == true {
                list[index]["back"]?["x"] = .number(-0.5 - sideBack)
                list[index]["back"]?["y"] = .number(-0.1 * riseBack)
            }
            if list[index]["front"]?["magic"]?.boolValue == true {
                list[index]["front"]?["x"] = .number(0.5 + sideFront)
                list[index]["front"]?["y"] = .number(0.1 * riseFront)
            }
        }
    }

    /// How many frames across one `x` of a handle is at a moment: half the way to the next.
    public func reach(_ side: Side, frame: Double, channel: Int) -> Double {
        let keys = self.keys(channel)
        guard let index = keys.firstIndex(where: { $0.frame == frame }) else { return 1 }
        guard let other = beside(keys, index, by: side == .back ? -1 : 1), other.frame != frame else { return 1 }
        return abs(other.frame - frame) / 2
    }

    /// How the moment's handles hang together when one is moved.
    public func locks(frame: Double, channel: Int) -> (angle: Bool, length: Bool) {
        let list = raw["c\(channel)"]?.arrayValue ?? []
        let key = list.first { $0["frame"]?.numberValue == frame }
        return (key?["lockangle"]?.boolValue != false, key?["locklength"]?.boolValue != false)
    }

    public mutating func setLocks(angle: Bool, length: Bool, frame: Double, channel: Int) {
        editKeys(channel) { list in
            guard let index = list.firstIndex(where: { $0["frame"]?.numberValue == frame }) else { return }
            list[index]["lockangle"] = .bool(angle)
            list[index]["locklength"] = .bool(length)
        }
    }

    /// A moment as Wallpaper Engine writes a new one.
    private static func newKey(frame: Double, value: Double) -> JSONValue {
        func handle(_ x: Double) -> JSONValue {
            .object(["enabled": .bool(true), "magic": .bool(true), "x": .number(x), "y": .number(0)])
        }
        return .object(["frame": .number(frame), "value": .number(value), "back": handle(-1), "front": handle(1),
                        "lockangle": .bool(true), "locklength": .bool(true)])
    }

    /// Gives a number its value at a frame: a moment there changes, or there is a new one.
    public mutating func setKey(frame: Double, channel: Int, value: Double) {
        editKeys(channel) { list in
            if let index = list.firstIndex(where: { $0["frame"]?.numberValue == frame }) {
                list[index]["value"] = .number(value)
            } else {
                list.append(Self.newKey(frame: frame, value: value))
            }
        }
    }

    /// Takes away the moments of a frame; of a number, or of them all. A number keeps its last.
    public mutating func removeKey(frame: Double, channel: Int? = nil) {
        for each in channel.map({ [$0] }) ?? Array(0..<channelCount) {
            guard keys(each).count > 1 else { continue }
            editKeys(each) { list in list.removeAll { $0["frame"]?.numberValue == frame } }
        }
    }

    /// Moves the moments of a frame to another; of a number, or of them all. One that stood
    /// there already gives way.
    public mutating func moveKey(from frame: Double, to target: Double, channel: Int? = nil) {
        guard frame != target else { return }
        for each in channel.map({ [$0] }) ?? Array(0..<channelCount) {
            editKeys(each) { list in
                guard let index = list.firstIndex(where: { $0["frame"]?.numberValue == frame }) else { return }
                var moved = list.remove(at: index)
                moved["frame"] = .number(target)
                list.removeAll { $0["frame"]?.numberValue == target }
                list.append(moved)
            }
        }
    }

    /// Sets how a moment joins the curve. A handle stays where it was when it stops being
    /// worked out, so the curve runs on as it did.
    public mutating func setInterpolation(_ interpolation: Interpolation, frame: Double, channel: Int? = nil) {
        for each in channel.map({ [$0] }) ?? Array(0..<channelCount) {
            editKeys(each) { list in
                guard let index = list.firstIndex(where: { $0["frame"]?.numberValue == frame }) else { return }
                for side in [Side.back, .front] {
                    let wanted = interpolation == .both || interpolation == (side == .back ? .back : .front)
                    var handle = list[index][side.rawValue] ?? .object(["x": .number(side == .back ? -1 : 1), "y": .number(0)])
                    handle["enabled"] = .bool(wanted || interpolation == .automatic)
                    handle["magic"] = interpolation == .automatic ? .bool(true) : nil
                    list[index][side.rawValue] = handle
                }
            }
        }
    }

    public func interpolation(frame: Double, channel: Int? = nil) -> Interpolation {
        for each in channel.map({ [$0] }) ?? Array(0..<channelCount) {
            guard let key = keys(each).first(where: { $0.frame == frame }) else { continue }
            switch (key.back, key.front) {
            case (nil, nil): return .linear
            case (let back?, _) where back.magic: return .automatic
            case (_, let front?) where front.magic: return .automatic
            case (_?, _?): return .both
            case (_?, nil): return .back
            case (nil, _?): return .front
            }
        }
        return .linear
    }

    /// Puts the end of a handle somewhere. The moment's other handle, if it has one drawn by
    /// hand, follows as Wallpaper Engine has it: with the angle locked it stays straight
    /// opposite, with the length locked it is as long.
    public mutating func moveHandle(_ side: Side, frame: Double, channel: Int, x: Double, y: Double) {
        let sign: Double = side == .back ? -1 : 1
        let x = sign * min(abs(x), 2)
        editKeys(channel) { list in
            guard let index = list.firstIndex(where: { $0["frame"]?.numberValue == frame }) else { return }
            var handle = list[index][side.rawValue] ?? .object([:])
            handle["enabled"] = .bool(true)
            handle["magic"] = nil
            handle["x"] = .number(x)
            handle["y"] = .number(y)
            list[index][side.rawValue] = handle
            let otherName = side == .back ? Side.front.rawValue : Side.back.rawValue
            guard var other = list[index][otherName], other["enabled"]?.boolValue == true, other["magic"]?.boolValue != true else { return }
            let lockedAngle = list[index]["lockangle"]?.boolValue != false, lockedLength = list[index]["locklength"]?.boolValue != false
            var otherX = other["x"]?.numberValue ?? 0, otherY = other["y"]?.numberValue ?? 0
            let moved = max(hypot(x, y), 1e-9), own = hypot(otherX, otherY)
            if lockedAngle {
                let share = lockedLength ? 1 : own / moved
                otherX = -x * share
                otherY = -y * share
            } else if lockedLength, own > 0 {
                otherX *= moved / own
                otherY *= moved / own
            }
            other["x"] = .number(side == .back ? min(2, max(0, otherX)) : max(-2, min(0, otherX)))
            other["y"] = .number(otherY)
            list[index][otherName] = other
        }
    }

    // MARK: - The curve

    /// The numbers a moment after the start, as the player works them out; a number the
    /// animation does not have is left as `base` has it.
    public func numbers(atSeconds seconds: Double, base: [Double]) -> [Double] {
        var frame = seconds * rate
        let length = self.length
        if length > 0 {
            switch options.mode {
            case .mirror:
                frame = frame.truncatingRemainder(dividingBy: length * 2)
                if frame > length { frame = length * 2 - frame }
            case .single: frame = min(frame, length)
            case .loop: frame = frame.truncatingRemainder(dividingBy: length)
            }
        }
        return numbers(atFrame: frame, base: base)
    }

    public func numbers(atFrame frame: Double, base: [Double]) -> [Double] {
        var result = base
        for channel in 0..<channelCount where channel < result.count {
            let keys = self.keys(channel)
            guard !keys.isEmpty else { continue }
            result[channel] = (isRelative ? base[channel] : 0) + value(keys, at: frame)
        }
        return result
    }

    private var wraps: Bool { options.mode == .loop && options.wrapsLoop && length > 0 }

    private func beside(_ keys: [Key], _ index: Int, by: Int) -> Key? {
        let other = index + by
        if keys.indices.contains(other) { return keys[other] }
        guard wraps else { return nil }
        var key = by > 0 ? keys[0] : keys[keys.count - 1]
        key.frame += Double(by) * length
        // A loop arrives at its first moment as that moment leaves.
        if by > 0, let front = key.front { key.back = Handle(x: -front.x, y: -front.y, magic: front.magic) }
        return key
    }

    private static func along(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ t: Double) -> Double {
        let rest = 1 - t
        return rest * rest * rest * a + 3 * rest * rest * t * b + 3 * rest * t * t * c + t * t * t * d
    }

    private func span(_ from: Key, _ to: Key, _ frame: Double) -> Double {
        let wide = to.frame - from.frame
        guard wide > 0 else { return to.value }
        if from.front == nil, to.back == nil {
            return from.value + (to.value - from.value) * (frame - from.frame) / wide
        }
        var x1 = from.frame, y1 = from.value, x2 = to.frame, y2 = to.value
        if let front = from.front {
            x1 += max(0, min(2, front.x)) * wide / 2
            y1 += front.y
        }
        if let back = to.back {
            x2 += max(-2, min(0, back.x)) * wide / 2
            y2 += back.y
        }
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if Self.along(from.frame, x1, x2, to.frame, middle) < frame { low = middle } else { high = middle }
        }
        return Self.along(from.value, y1, y2, to.value, (low + high) / 2)
    }

    private func value(_ keys: [Key], at frame: Double) -> Double {
        let last = keys.count - 1
        if frame <= keys[0].frame {
            if let before = beside(keys, 0, by: -1), frame < keys[0].frame {
                return span(before, keys[0], frame)
            }
            return keys[0].value
        }
        if frame >= keys[last].frame {
            if let after = beside(keys, last, by: 1), frame > keys[last].frame {
                return span(keys[last], after, frame)
            }
            return keys[last].value
        }
        var index = 1
        while keys[index].frame < frame { index += 1 }
        return span(keys[index - 1], keys[index], frame)
    }
}

/// What of an object can have an animation: one of its values, or a value of one of its effects.
public enum WallpaperEngineAnimationTarget: Hashable, Sendable {
    case value(String)
    case effect(index: Int, pass: Int, name: String)
}

extension WallpaperEngineDocument {
    /// What the scene says of a value, with whatever stands behind it.
    public func rawValue(of id: Int, _ target: WallpaperEngineAnimationTarget) -> JSONValue? {
        switch target {
        case .value(let key):
            return object(id)?[key]
        case .effect(let index, let pass, let name):
            return object(id)?["effects"]?[index]?["passes"]?[pass]?["constantshadervalues"]?[name]
        }
    }

    private mutating func setRawValue(_ value: JSONValue?, of id: Int, _ target: WallpaperEngineAnimationTarget) {
        update(id) { object in
            switch target {
            case .value(let key):
                object[key] = value
            case .effect(let index, let pass, let name):
                guard var effects = object["effects"]?.arrayValue, effects.indices.contains(index),
                      var passes = effects[index]["passes"]?.arrayValue, passes.indices.contains(pass) else { return }
                var constants = passes[pass]["constantshadervalues"] ?? .object([:])
                constants[name] = value
                passes[pass]["constantshadervalues"] = constants
                effects[index]["passes"] = .array(passes)
                object["effects"] = .array(effects)
            }
        }
    }

    public func animation(of id: Int, _ target: WallpaperEngineAnimationTarget) -> WallpaperEngineAnimation? {
        rawValue(of: id, target)?["animation"].flatMap(WallpaperEngineAnimation.init(raw:))
    }

    public mutating func setAnimation(_ animation: WallpaperEngineAnimation, of id: Int, _ target: WallpaperEngineAnimationTarget) {
        guard var value = rawValue(of: id, target) else { return }
        value["animation"] = animation.raw
        setRawValue(value, of: id, target)
    }

    /// Gives a value an animation that starts from what it is. `fallback` is the value of one
    /// the scene does not write down.
    public mutating func bindAnimation(of id: Int, _ target: WallpaperEngineAnimationTarget, options: WallpaperEngineAnimation.Options,
                                       fallback: [Double]) {
        let plain = rawValue(of: id, target)?.plain
        let numbers = plain?.vector ?? fallback
        let written: JSONValue = plain ?? (numbers.count == 1 ? .number(numbers[0]) : .vector(numbers))
        var value = rawValue(of: id, target) ?? .object(["value": written])
        if value.objectValue == nil { value = .object(["value": written]) }
        value["animation"] = WallpaperEngineAnimation(values: numbers, options: options).raw
        setRawValue(value, of: id, target)
    }

    /// Has an animation of an object's value play along with another of the same object, or on
    /// its own again: Wallpaper Engine's "combine", written on both, with the one that leads
    /// saying how long it lasts and how it plays.
    public mutating func linkAnimation(of id: Int, _ key: String, to leader: String?) {
        let target = WallpaperEngineAnimationTarget.value(key)
        guard var animation = animation(of: id, target) else { return }
        if let old = animation.leader, var own = self.animation(of: id, .value(old)) {
            own.followers.removeAll { $0 == key }
            setAnimation(own, of: id, .value(old))
        }
        animation.leader = leader
        if let leader, var own = self.animation(of: id, .value(leader)) {
            if !own.followers.contains(key) { own.followers.append(key) }
            setAnimation(own, of: id, .value(leader))
            animation.playsAlong(with: own)
        }
        setAnimation(animation, of: id, target)
    }

    /// Takes the animation off a value, which stays as the scene says it plainly.
    public mutating func unbindAnimation(of id: Int, _ target: WallpaperEngineAnimationTarget) {
        guard var value = rawValue(of: id, target) else { return }
        value["animation"] = nil
        if let rest = value.objectValue, rest.count == 1, let plain = rest["value"] {
            value = plain
        }
        setRawValue(value, of: id, target)
    }

    /// What of an object has an animation: its values, the usual ones first, then its effects'.
    public func animatedTargets(of id: Int) -> [WallpaperEngineAnimationTarget] {
        guard let object = object(id), let keys = object.objectValue?.keys else { return [] }
        let usual = ["origin", "scale", "angles", "alpha", "color"]
        let own = keys.filter { object[$0]?["animation"] != nil }
            .sorted { (usual.firstIndex(of: $0) ?? usual.count, $0) < (usual.firstIndex(of: $1) ?? usual.count, $1) }
        var result = own.map(WallpaperEngineAnimationTarget.value)
        for (index, effect) in (object["effects"]?.arrayValue ?? []).enumerated() {
            for (step, pass) in (effect["passes"]?.arrayValue ?? []).enumerated() {
                let names = pass["constantshadervalues"]?.objectValue?.keys.filter { pass["constantshadervalues"]?[$0]?["animation"] != nil } ?? []
                result += names.sorted().map { .effect(index: index, pass: step, name: $0) }
            }
        }
        return result
    }

    /// Where a value of an effect is written: the pass that sets it, or the first.
    public func effectTarget(named name: String, effect index: Int, of id: Int) -> WallpaperEngineAnimationTarget {
        let passes = object(id)?["effects"]?[index]?["passes"]?.arrayValue ?? []
        let pass = passes.firstIndex { $0["constantshadervalues"]?[name] != nil } ?? 0
        return .effect(index: index, pass: pass, name: name)
    }
}

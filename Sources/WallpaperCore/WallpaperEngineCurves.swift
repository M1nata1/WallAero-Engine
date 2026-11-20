import Foundation
import JavaScriptCore

/// Wallpaper Engine's timeline curves worked out by the player's own code, `Player/curves.js`,
/// run alone in a context of its own: the editor's timeline and inspector show what the scene
/// will play, with no second copy of the sums to drift from it (docs/we-format.md, row 16).
///
/// A curve is made once for an animation and kept while it stays the same; the editor asks many
/// moments of the same few animations as it draws.
final class WallpaperEngineCurves: @unchecked Sendable {
    static let shared = WallpaperEngineCurves()

    private let lock = NSLock()
    private let context: JSContext
    private let make: JSValue
    /// The curves made last, the latest first.
    private var made: [(raw: JSONValue, curve: JSValue?)] = []
    private static let kept = 32

    private init() {
        context = JSContext()
        context.name = "WallAero Engine curves"
        guard let script = WallpaperEngineRuntime.file(named: "curves.js") else {
            fatalError("the scene player's curves.js is missing")
        }
        context.evaluateScript(script)
        // Many frames in one call, flat: the timeline draws hundreds at once.
        context.evaluateScript("""
            function framesOf(curve, frames, base) {
              var all = [];
              for (var i = 0; i < frames.length; i++) Array.prototype.push.apply(all, curve.atFrame(frames[i], base));
              return all;
            }
            """)
        make = context.objectForKeyedSubscript("curveOf")
        framesOf = context.objectForKeyedSubscript("framesOf")
    }

    private let framesOf: JSValue

    /// The numbers at each of `frames`, in one go.
    func numbers(_ raw: JSONValue, frames: [Double], base: [Double]) -> [[Double]] {
        lock.lock()
        defer { lock.unlock() }
        guard !frames.isEmpty else { return [] }
        guard let curve = curve(raw),
              let flat = framesOf.call(withArguments: [curve, frames, base])?.toArray() as? [NSNumber],
              flat.count == frames.count * base.count
        else { return Array(repeating: base, count: frames.count) }
        guard !base.isEmpty else { return Array(repeating: [], count: frames.count) }
        return stride(from: 0, to: flat.count, by: base.count).map { start in flat[start..<(start + base.count)].map(\.doubleValue) }
    }

    /// The numbers at a moment, in seconds since the start (`seconds`) or at a frame of one play
    /// through (`frame`); a number the animation does not have is left as `base` has it.
    func numbers(_ raw: JSONValue, seconds: Double? = nil, frame: Double? = nil, base: [Double]) -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        guard let curve = curve(raw) else { return base }
        let answer: JSValue?
        if let frame {
            answer = curve.forProperty("atFrame").call(withArguments: [frame, base])
        } else {
            answer = curve.call(withArguments: [seconds ?? 0, base])
        }
        guard let numbers = answer?.toArray() as? [NSNumber], numbers.count == base.count else { return base }
        return numbers.map(\.doubleValue)
    }

    private func curve(_ raw: JSONValue) -> JSValue? {
        if let index = made.firstIndex(where: { $0.raw == raw }) {
            let found = made.remove(at: index)
            made.insert(found, at: 0)
            return found.curve
        }
        let text = JSStringCreateWithCFString(String(decoding: raw.data(readable: false), as: UTF8.self) as CFString)
        defer { JSStringRelease(text) }
        var curve: JSValue?
        if let parsed = JSValueMakeFromJSONString(context.jsGlobalContextRef, text) {
            curve = make.call(withArguments: [JSValue(jsValueRef: parsed, in: context) as Any])
        }
        let kept = curve.flatMap { $0.isObject ? $0 : nil }
        made.insert((raw, kept), at: 0)
        if made.count > Self.kept { made.removeLast() }
        return kept
    }
}

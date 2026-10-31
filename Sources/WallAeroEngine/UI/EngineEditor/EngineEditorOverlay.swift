import AppKit
import MetalScene
import WallpaperCore

/// The editor's hold on a scene the app draws itself: over the scene, the frame of the selected
/// object with handles to move, scale and turn it, as `SceneEditorScript` gives them on the
/// scene's page. Where an object is and what lies under the pointer the scene's player says;
/// what is changed is shown at once, as the editor's changes, and reported to `onChange`.
@MainActor
final class EngineEditorOverlay: NSView {
    /// The scene, once it plays; asked where things are.
    weak var player: MetalScenePlayer?
    /// An object was picked in the preview; nil for none.
    var onSelect: ((Int?) -> Void)?
    /// An object was moved, scaled or turned; the values are the scene's own.
    var onChange: ((Int, [String: Double]) -> Void)?
    /// The gesture is over: what it did is one step to take back.
    var onCommit: (() -> Void)?
    /// The scene is to be enlarged by a factor around a point, given from the middle of this view.
    var onZoom: ((CGFloat, CGSize) -> Void)?
    /// The scene is to be moved.
    var onPan: ((CGSize) -> Void)?
    /// The menu of a point of the scene.
    var onMenu: ((CGPoint) -> NSMenu?)?
    /// Where an object stands now if an animation has it elsewhere than the scene says.
    var animatedPlace: ((Int, String) -> Double?)?
    /// What a drag over the scene does.
    var tool = EngineEditorModel.Tool.multi {
        didSet { needsDisplay = true }
    }

    /// The mask painted over the scene, which takes the mouse for as long as it is.
    var painting: EngineMaskPaint? {
        didSet {
            maskPicture = nil
            paintGesture = nil
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }
    private var brushAt: CGPoint?
    private var gestureKeys = NSEvent.ModifierFlags()
    /// A press with Option moves the view: every other drag paints.
    private var paintPans = false
    private var maskPicture: CGImage?
    /// The brush's settings as a press with a modifier key took hold of them, as in Wallpaper Engine.
    private var paintGesture: (from: CGPoint, size: Double, opacity: Double, hardness: Double)?

    /// The selected object, by its number.
    private(set) var object: Int?
    /// The scene's objects as its player describes them, by number.
    private var described: [Int: [String: Any]] = [:]
    /// What the editor changed of the scene and has not yet been written: `{"objects": [...]}`.
    private(set) var changes: [String: Any] = [:]
    private var outline: (middle: CGPoint, corners: [CGPoint]?, visible: Bool)?
    private var objectSize: CGSize?
    private var drag: Drag?
    private var follow: Timer?
    private var reported: [Int: [String: Double]] = [:]
    private var reportWaits = false

    private struct Drag {
        let mode: String
        let pointer: CGPoint
        let place: CGPoint
        let middle: CGPoint
        let x, y, scaleX, scaleY, rotation: Double
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    // MARK: - What the scene has

    /// The scene was played anew: what it has is read again, and given to `onDescribe`.
    func describe() -> String? {
        guard let scene = player?.ask("describe") as? [String: Any] else { return nil }
        described = [:]
        for each in scene["objects"] as? [[String: Any]] ?? [] {
            if let id = (each["id"] as? NSNumber)?.intValue { described[id] = each }
        }
        placeFrame()
        guard let data = try? JSONSerialization.data(withJSONObject: scene) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// What the editor changed and showed is in the scene's files now.
    func forgetChanges() {
        changes = [:]
    }

    func selectObject(_ id: Int?, tellingTheApp: Bool = false) {
        object = id
        placeFrame()
        follow?.invalidate()
        follow = nil
        if id != nil {
            // The scene moves as it plays — with the pointer, by its scripts — and the frame with it.
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.placeFrame() }
            }
            RunLoop.main.add(timer, forMode: .common)
            follow = timer
        }
        if tellingTheApp { onSelect?(id) }
    }

    private func value(_ id: Int, _ name: String) -> Double {
        if let animated = animatedPlace?(id, name) { return animated }
        for each in changes["objects"] as? [[String: Any]] ?? [] where (each["id"] as? NSNumber)?.intValue == id {
            if let value = (each[name] as? NSNumber)?.doubleValue { return value }
        }
        return (described[id]?[name] as? NSNumber)?.doubleValue ?? 0
    }

    // MARK: - The frame

    private func placeFrame() {
        defer { needsDisplay = true }
        guard let object, let found = player?.ask("outline", [object]) as? [String: Any],
              let middle = found["middle"] as? [NSNumber], middle.count >= 2 else {
            outline = nil
            return
        }
        objectSize = (found["size"] as? [NSNumber]).flatMap { $0.count >= 2 ? CGSize(width: $0[0].doubleValue, height: $0[1].doubleValue) : nil }
        let corners = (found["corners"] as? [[NSNumber]])?.compactMap { $0.count >= 2 ? CGPoint(x: $0[0].doubleValue, y: $0[1].doubleValue) : nil }
        outline = (CGPoint(x: middle[0].doubleValue, y: middle[1].doubleValue), corners?.count == 4 ? corners : nil,
                   (found["visible"] as? NSNumber)?.boolValue ?? true)
    }

    /// The frame's size and turn: from the corners the player gives, or a small mark.
    private var shape: (width: CGFloat, height: CGFloat, turn: CGFloat)? {
        guard let outline else { return nil }
        guard let c = outline.corners else { return (14, 14, 0) }
        let width = max(4, hypot(c[1].x - c[0].x, c[1].y - c[0].y))
        let height = max(4, hypot(c[2].x - c[1].x, c[2].y - c[1].y))
        return (width, height, atan2(c[1].y - c[0].y, c[1].x - c[0].x))
    }

    /// Where each handle is, in the view: the corners, and the round one above the top edge.
    private var handles: [(name: String, point: CGPoint)] {
        guard tool == .multi, let outline, outline.corners != nil, let shape else { return [] }
        let local: [(String, CGPoint)] = [("nw", CGPoint(x: -shape.width / 2, y: -shape.height / 2)),
                                          ("ne", CGPoint(x: shape.width / 2, y: -shape.height / 2)),
                                          ("sw", CGPoint(x: -shape.width / 2, y: shape.height / 2)),
                                          ("se", CGPoint(x: shape.width / 2, y: shape.height / 2)),
                                          ("rotate", CGPoint(x: 0, y: -shape.height / 2 - 24))]
        return local.map { name, point in
            (name, CGPoint(x: outline.middle.x + point.x * cos(shape.turn) - point.y * sin(shape.turn),
                           y: outline.middle.y + point.x * sin(shape.turn) + point.y * cos(shape.turn)))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if let painting {
            drawPainting(painting)
            return
        }
        guard let outline, let shape else { return }
        let accent = NSColor.controlAccentColor
        let transform = NSAffineTransform()
        transform.translateX(by: outline.middle.x, yBy: outline.middle.y)
        transform.rotate(byRadians: shape.turn)
        let frame = outline.corners == nil
            ? NSBezierPath(ovalIn: NSRect(x: -7, y: -7, width: 14, height: 14))
            : NSBezierPath(rect: NSRect(x: -shape.width / 2, y: -shape.height / 2, width: shape.width, height: shape.height))
        frame.transform(using: transform as AffineTransform)
        frame.lineWidth = 1.5
        // A hidden object has its frame dashed.
        if !outline.visible { frame.setLineDash([5, 3], count: 2, phase: 0) }
        accent.setStroke()
        frame.stroke()
        if tool == .rotate {
            // The ring the object is turned on, round its middle.
            let radius = max(40, min(max(shape.width, shape.height) / 2, min(bounds.width, bounds.height) * 0.4))
            let ring = NSBezierPath(ovalIn: NSRect(x: outline.middle.x - radius, y: outline.middle.y - radius,
                                                   width: radius * 2, height: radius * 2))
            ring.lineWidth = 1.5
            ring.stroke()
        }
        for handle in handles {
            let rect = NSRect(x: handle.point.x - 5, y: handle.point.y - 5, width: 10, height: 10)
            let mark = handle.name == "rotate" ? NSBezierPath(ovalIn: rect) : NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            NSColor.white.setFill()
            mark.fill()
            mark.lineWidth = 1.5
            accent.setStroke()
            mark.stroke()
        }
    }

    // MARK: - The mouse

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseMoved(with event: NSEvent) {
        let at = point(event)
        player?.pointer("move", x: at.x, y: at.y)
        if painting != nil {
            brushAt = at
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        player?.pointer("leave", x: 0, y: 0)
        brushAt = nil
        if painting != nil { needsDisplay = true }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        painting == nil ? onMenu?(point(event)) : nil
    }

    override func resetCursorRects() {
        if painting != nil { addCursorRect(bounds, cursor: .crosshair) }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let at = point(event)
        if let painting {
            pressBrush(painting, at, event)
            return
        }
        player?.pointer("down", x: at.x, y: at.y)
        if object != nil {
            // These two take hold anywhere; a click without a drag picks what is under it.
            if tool == .rotate || tool == .scale {
                startDrag(at, mode: tool == .rotate ? "rotate" : "scale")
                return
            }
            if let handle = handles.first(where: { abs($0.point.x - at.x) <= 7 && abs($0.point.y - at.y) <= 7 }) {
                startDrag(at, mode: handle.name)
                return
            }
            // An object with no size of its own is taken by its mark.
            if let outline, outline.corners == nil, abs(at.x - outline.middle.x) <= 12, abs(at.y - outline.middle.y) <= 12 {
                startDrag(at, mode: "move")
                return
            }
        }
        guard let hit = (player?.ask("hit", [at.x, at.y]) as? NSNumber)?.intValue else {
            selectObject(nil)
            return
        }
        if hit != object { selectObject(hit, tellingTheApp: true) }
        startDrag(at, mode: "move")
    }

    private func startDrag(_ at: CGPoint, mode: String) {
        guard let object, let outline else { return }
        let place = (player?.ask("placeAt", [object, at.x, at.y]) as? [NSNumber]).map { CGPoint(x: $0[0].doubleValue, y: $0[1].doubleValue) } ?? .zero
        drag = Drag(mode: mode, pointer: at, place: place, middle: outline.middle, x: value(object, "x"), y: value(object, "y"),
                    scaleX: value(object, "scaleX"), scaleY: value(object, "scaleY"), rotation: value(object, "rotation"))
    }

    override func mouseDragged(with event: NSEvent) {
        let at = point(event)
        if let painting {
            if paintPans {
                onPan?(CGSize(width: event.deltaX, height: event.deltaY))
            } else {
                dragBrush(painting, at)
            }
            return
        }
        guard let drag, let object else {
            player?.pointer("move", x: at.x, y: at.y)
            return
        }
        var patch: [String: Double] = [:]
        switch drag.mode {
        case "move":
            if let place = player?.ask("placeAt", [object, at.x, at.y]) as? [NSNumber], place.count >= 2 {
                var by = CGPoint(x: place[0].doubleValue - drag.place.x, y: place[1].doubleValue - drag.place.y)
                if tool == .move, event.modifierFlags.contains(.shift) {
                    if abs(by.x) < abs(by.y) { by.x = 0 } else { by.y = 0 }
                }
                patch["x"] = Self.round(drag.x + by.x)
                patch["y"] = Self.round(drag.y + by.y)
            }
        case "rotate":
            let from = atan2(drag.pointer.y - drag.middle.y, drag.pointer.x - drag.middle.x)
            let to = atan2(at.y - drag.middle.y, at.x - drag.middle.x)
            var angle = drag.rotation + (to - from) * 180 / .pi
            if event.modifierFlags.contains(.shift) {
                angle = (angle / 15).rounded() * 15
            } else {
                let nearest = (angle / 90).rounded() * 90
                if abs(angle - nearest) < 3 { angle = nearest }
            }
            patch["rotation"] = Self.round(((angle + 180).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) - 180)
        default:
            // From the middle, as far as the pointer is now against where it took hold.
            let before = hypot(drag.pointer.x - drag.middle.x, drag.pointer.y - drag.middle.y)
            let by = before > 1 ? max(0.01, hypot(at.x - drag.middle.x, at.y - drag.middle.y) / before) : 1
            patch["scaleX"] = (drag.scaleX * by * 1000).rounded() / 1000
            patch["scaleY"] = (drag.scaleY * by * 1000).rounded() / 1000
        }
        change(object, patch)
    }

    override func mouseUp(with event: NSEvent) {
        let at = point(event)
        if let painting {
            paintGesture = nil
            paintPans = false
            painting.endStroke()
            return
        }
        player?.pointer("up", x: at.x, y: at.y)
        guard let drag else { return }
        self.drag = nil
        if tool != .multi, drag.mode != "move", hypot(at.x - drag.pointer.x, at.y - drag.pointer.y) < 3 {
            let hit = (player?.ask("hit", [at.x, at.y]) as? NSNumber)?.intValue
            if hit != object { selectObject(hit, tellingTheApp: true) }
            return
        }
        // After the change that carries the last move.
        DispatchQueue.main.async { [weak self] in
            self?.flushReports()
            self?.onCommit?()
        }
    }

    // MARK: - The mask

    /// A point of this view as a point of the mask.
    private func maskPoint(_ at: CGPoint, _ mask: WallpaperEngineMask) -> (x: Double, y: Double)? {
        guard let c = outline?.corners else { return nil }
        let across = CGPoint(x: c[1].x - c[0].x, y: c[1].y - c[0].y), down = CGPoint(x: c[3].x - c[0].x, y: c[3].y - c[0].y)
        let area = across.x * down.y - across.y * down.x
        guard abs(area) > 1e-6 else { return nil }
        let x = at.x - c[0].x, y = at.y - c[0].y
        return ((x * down.y - y * down.x) / area * Double(mask.width), (across.x * y - across.y * x) / area * Double(mask.height))
    }

    /// How far a pixel of the mask reaches in pixels of the scene, each way.
    private func sceneScale(_ mask: WallpaperEngineMask) -> (x: Double, y: Double) {
        guard let object, let objectSize else { return (1, 1) }
        return (max(1e-3, abs(value(object, "scaleX"))) * objectSize.width / Double(mask.width),
                max(1e-3, abs(value(object, "scaleY"))) * objectSize.height / Double(mask.height))
    }

    private func dab(_ painting: EngineMaskPaint, _ at: CGPoint) {
        guard let place = maskPoint(at, painting.mask) else { return }
        let scale = sceneScale(painting.mask)
        painting.paint(atX: place.x, y: place.y, radiusX: painting.size / 2 / scale.x, radiusY: painting.size / 2 / scale.y)
    }

    private func pressBrush(_ painting: EngineMaskPaint, _ at: CGPoint, _ event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            paintPans = true
            return
        }
        if !event.modifierFlags.intersection([.control, .shift]).isEmpty {
            paintGesture = (at, painting.size, painting.opacity, painting.hardness)
            gestureKeys = event.modifierFlags
            return
        }
        if painting.isPicking {
            if let place = maskPoint(at, painting.mask) { painting.pickValue(atX: place.x, y: place.y) }
            return
        }
        painting.startStroke()
        dab(painting, at)
    }

    private func dragBrush(_ painting: EngineMaskPaint, _ at: CGPoint) {
        brushAt = at
        needsDisplay = true
        guard let gesture = paintGesture else {
            dab(painting, at)
            return
        }
        let x = at.x - gesture.from.x, y = at.y - gesture.from.y
        let control = gestureKeys.contains(.control), shift = gestureKeys.contains(.shift)
        if control, shift {
            painting.hardness = min(100, max(0, (gesture.hardness + 0.25 * x).rounded()))
        } else if control {
            painting.size = min(2000, max(1, (gesture.size + x).rounded()))
            painting.hardness = min(100, max(0, (gesture.hardness + 0.25 * y).rounded()))
        } else {
            painting.opacity = min(100, max(1, (gesture.opacity + 0.25 * x).rounded()))
        }
    }

    /// The mask changed, or the way it is shown.
    func maskChanged() {
        maskPicture = nil
        needsDisplay = true
    }

    /// Arrows over the object, the way the picture moves and as far as it does.
    private func drawDirections(_ mask: WallpaperEngineMask, _ c: [CGPoint]) {
        let across = CGPoint(x: c[1].x - c[0].x, y: c[1].y - c[0].y), down = CGPoint(x: c[3].x - c[0].x, y: c[3].y - c[0].y)
        let gap: CGFloat = 26
        let columns = max(1, Int(hypot(across.x, across.y) / gap)), rows = max(1, Int(hypot(down.x, down.y) / gap))
        let arrows = NSBezierPath()
        for row in 0..<rows {
            for column in 0..<columns {
                let u = (Double(column) + 0.5) / Double(columns), v = (Double(row) + 0.5) / Double(rows)
                let flow = mask.flow(atX: u * Double(mask.width), y: v * Double(mask.height))
                let strength = min(1, hypot(flow.x, flow.y))
                guard strength > 0.03 else { continue }
                let from = CGPoint(x: c[0].x + across.x * u + down.x * v, y: c[0].y + across.y * u + down.y * v)
                // Along the object's own sides, which may be turned.
                let wayX = (across.x * flow.x + down.x * flow.y), wayY = (across.y * flow.x + down.y * flow.y)
                let length = max(1e-6, hypot(wayX, wayY)), reach = gap * 0.8 * strength
                let to = CGPoint(x: from.x + wayX / length * reach, y: from.y + wayY / length * reach)
                let turn = atan2(to.y - from.y, to.x - from.x), wing = min(6, reach * 0.45)
                arrows.move(to: from)
                arrows.line(to: to)
                arrows.line(to: CGPoint(x: to.x - wing * cos(turn - 0.5), y: to.y - wing * sin(turn - 0.5)))
                arrows.move(to: to)
                arrows.line(to: CGPoint(x: to.x - wing * cos(turn + 0.5), y: to.y - wing * sin(turn + 0.5)))
            }
        }
        NSColor.black.withAlphaComponent(0.55).setStroke()
        arrows.lineWidth = 3
        arrows.stroke()
        NSColor.white.setStroke()
        arrows.lineWidth = 1.25
        arrows.stroke()
    }

    private func drawPainting(_ painting: EngineMaskPaint) {
        guard let context = NSGraphicsContext.current?.cgContext, let c = outline?.corners else { return }
        let accent = NSColor.controlAccentColor
        if painting.showsMask {
            let mask = painting.mask
            if painting.target.mask.isFlow {
                drawDirections(mask, c)
            } else {
                if maskPicture == nil, let provider = CGDataProvider(data: Data(mask.pixels) as CFData) {
                    maskPicture = CGImage(width: mask.width, height: mask.height, bitsPerComponent: 8, bitsPerPixel: 8 * mask.channels,
                                          bytesPerRow: mask.width * mask.channels,
                                          space: mask.channels == 3 ? CGColorSpaceCreateDeviceRGB() : CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGBitmapInfo(), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
                }
                if let maskPicture {
                    context.saveGState()
                    // A picture stands with its top at 1, and the view counts downwards.
                    context.concatenate(CGAffineTransform(a: c[1].x - c[0].x, b: c[1].y - c[0].y, c: c[0].x - c[3].x, d: c[0].y - c[3].y, tx: c[3].x, ty: c[3].y))
                    let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
                    if mask.channels == 3 {
                        context.setAlpha(painting.maskOpacity / 100)
                        context.draw(maskPicture, in: whole)
                    } else {
                        context.clip(to: whole, mask: maskPicture)
                        context.setFillColor(accent.withAlphaComponent(painting.maskOpacity / 100).cgColor)
                        context.fill(whole)
                    }
                    context.restoreGState()
                }
            }
        }
        let frame = NSBezierPath()
        frame.move(to: c[0])
        c.dropFirst().forEach(frame.line(to:))
        frame.close()
        frame.lineWidth = 1
        accent.withAlphaComponent(0.6).setStroke()
        frame.stroke()
        guard let brushAt, !painting.isPicking else { return }
        let scale = sceneScale(painting.mask)
        let wide = painting.size / scale.x / Double(painting.mask.width) * hypot(c[1].x - c[0].x, c[1].y - c[0].y)
        let high = painting.size / scale.y / Double(painting.mask.height) * hypot(c[3].x - c[0].x, c[3].y - c[0].y)
        let ring = NSBezierPath(ovalIn: NSRect(x: -wide / 2, y: -high / 2, width: wide, height: high))
        let transform = NSAffineTransform()
        transform.translateX(by: brushAt.x, yBy: brushAt.y)
        transform.rotate(byRadians: atan2(c[1].y - c[0].y, c[1].x - c[0].x))
        ring.transform(using: transform as AffineTransform)
        ring.lineWidth = 1.5
        accent.setStroke()
        ring.stroke()
    }

    // MARK: - The view

    /// From the middle of this view, where the scene is enlarged around.
    private func fromMiddle(_ event: NSEvent) -> CGSize {
        let at = point(event)
        return CGSize(width: at.x - bounds.midX, height: at.y - bounds.midY)
    }

    /// A mouse wheel enlarges the scene. On a trackpad two fingers move it, and enlarge it with
    /// Command; so does pinching.
    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas, !event.modifierFlags.contains(.command) {
            onPan?(CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
        } else {
            onZoom?(pow(event.hasPreciseScrollingDeltas ? 1.01 : 1.1, event.scrollingDeltaY), fromMiddle(event))
        }
    }

    override func magnify(with event: NSEvent) {
        onZoom?(1 + event.magnification, fromMiddle(event))
    }

    /// With a mouse, the scene is moved by its middle button.
    override func otherMouseDragged(with event: NSEvent) {
        onPan?(CGSize(width: event.deltaX, height: event.deltaY))
    }

    override func keyDown(with event: NSEvent) {
        guard let object else { return super.keyDown(with: event) }
        // A pixel of the scene at a time, or ten; the scene counts upwards.
        let by: Double = event.modifierFlags.contains(.shift) ? 10 : 1
        var patch: [String: Double]
        switch event.keyCode {
        case 123: patch = ["x": Self.round(value(object, "x") - by)]
        case 124: patch = ["x": Self.round(value(object, "x") + by)]
        case 126: patch = ["y": Self.round(value(object, "y") + by)]
        case 125: patch = ["y": Self.round(value(object, "y") - by)]
        default: return super.keyDown(with: event)
        }
        change(object, patch)
    }

    // MARK: - Changes

    /// Changes an object in the scene shown and has it shown at once; the app is told once a moment.
    private func change(_ id: Int, _ patch: [String: Double]) {
        var list = changes["objects"] as? [[String: Any]] ?? []
        if let index = list.firstIndex(where: { ($0["id"] as? NSNumber)?.intValue == id }) {
            for (name, value) in patch { list[index][name] = value }
        } else {
            var own: [String: Any] = ["id": id]
            for (name, value) in patch { own[name] = value }
            list.append(own)
        }
        changes["objects"] = list
        player?.editorUpdate(settings: nil, changes: changes)
        placeFrame()
        reported[id, default: [:]].merge(patch) { $1 }
        guard !reportWaits else { return }
        reportWaits = true
        DispatchQueue.main.async { [weak self] in self?.flushReports() }
    }

    private func flushReports() {
        reportWaits = false
        let waiting = reported
        reported = [:]
        for (id, patch) in waiting { onChange?(id, patch) }
    }

    private static func round(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}

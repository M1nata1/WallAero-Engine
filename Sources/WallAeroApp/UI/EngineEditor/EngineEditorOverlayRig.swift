import AppKit
import WallpaperCore

/// What a press has taken hold of of a picture's rig.
enum RigGesture {
    case head(Int)
    case tail(Int)
    case wholeBone(Int, from: WallpaperEnginePuppetRig.Point, head: WallpaperEnginePuppetRig.Point, tail: WallpaperEnginePuppetRig.Point)
    case newBone(Int)
    case corners(from: WallpaperEnginePuppetRig.Point, start: [Int: WallpaperEnginePuppetRig.Point])
    case box(from: CGPoint, to: CGPoint)
    case turn(Int, key: WallpaperEnginePuppetRig.Key, pivot: WallpaperEnginePuppetRig.Point, from: Double)
    case move(Int, key: WallpaperEnginePuppetRig.Key, from: WallpaperEnginePuppetRig.Point, parent: CGAffineTransform?)
    case weight
}

/// The picture's own flat in this view: places of the rig, in pixels from its middle, y up, and
/// back, whichever way the object stands in the scene.
struct RigPlane {
    let corner: CGPoint
    let across: CGPoint
    let down: CGPoint
    let width: Double
    let height: Double

    func view(_ point: WallpaperEnginePuppetRig.Point) -> CGPoint {
        let u = point.x / width + 0.5, v = 0.5 - point.y / height
        return CGPoint(x: corner.x + across.x * u + down.x * v, y: corner.y + across.y * u + down.y * v)
    }

    func rig(_ at: CGPoint) -> WallpaperEnginePuppetRig.Point? {
        let area = across.x * down.y - across.y * down.x
        guard abs(area) > 1e-6 else { return nil }
        let x = at.x - corner.x, y = at.y - corner.y
        let u = (x * down.y - y * down.x) / area, v = (across.x * y - across.y * x) / area
        return .init(x: (u - 0.5) * width, y: (0.5 - v) * height)
    }

    /// Points of this view to a pixel of the picture.
    var scale: Double { hypot(across.x, across.y) / max(width, 1) }
}

/// A bone on the scene, from where it turns about to where it ends.
struct RigBoneShape {
    let index: Int
    let head: CGPoint
    let tail: CGPoint
    let parent: Int?

    /// How far a point is from the bone, along its length.
    func distance(_ at: CGPoint) -> CGFloat {
        let dx = tail.x - head.x, dy = tail.y - head.y
        let length = dx * dx + dy * dy
        let t = length > 0 ? min(max(((at.x - head.x) * dx + (at.y - head.y) * dy) / length, 0), 1) : 0
        return hypot(at.x - (head.x + t * dx), at.y - (head.y + t * dy))
    }
}

extension EngineEditorOverlay {
    private var rig: WallpaperEnginePuppetRig? { model?.selectedRig }

    private var plane: RigPlane? {
        guard let c = outline?.corners, let rig else { return nil }
        return RigPlane(corner: c[0], across: CGPoint(x: c[1].x - c[0].x, y: c[1].y - c[0].y),
                        down: CGPoint(x: c[3].x - c[0].x, y: c[3].y - c[0].y), width: rig.width, height: rig.height)
    }

    /// The mode changed, or what is selected in it.
    func modeChanged() {
        rigGesture = nil
        weightCache = nil
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    /// The bones as they stand now on the scene. In Object Mode, with nothing to hold them, the
    /// player says where they have got to as it plays.
    private func boneShapes(_ rig: WallpaperEnginePuppetRig, _ plane: RigPlane) -> [RigBoneShape] {
        guard let model else { return [] }
        var moves = model.standingBones(of: rig)
        if model.mode == .object, !model.showsTimeline, let object,
           let said = player?.ask("bones", [object]) as? [[NSNumber]], said.count == moves.count {
            moves = said.map { m in
                m.count >= 6 ? CGAffineTransform(a: m[0].doubleValue, b: m[1].doubleValue, c: m[2].doubleValue, d: m[3].doubleValue,
                                                 tx: m[4].doubleValue, ty: m[5].doubleValue) : .identity
            }
        }
        return rig.bones.map { bone in
            let move = moves[bone.index]
            let tail = rig.alongBone(bone.index, rig.restTail(of: bone.index))
            return RigBoneShape(index: bone.index, head: plane.view(.init(x: move.tx, y: move.ty)),
                                tail: plane.view(.init(x: move.a * tail.x + move.c * tail.y + move.tx, y: move.b * tail.x + move.d * tail.y + move.ty)),
                                parent: bone.parent)
        }
    }

    // MARK: - Drawing

    /// Draws what the mode shows of the rig. False leaves the object's frame to be drawn, with
    /// the bones of a picture that has them under it.
    func drawRig() -> Bool {
        guard let model else { return false }
        guard let rig, let plane else { return model.mode.isRig }
        let shapes = model.mode == .mesh ? [] : boneShapes(rig, plane)
        switch model.mode {
        case .object:
            drawBones(shapes, selected: nil, faint: true)
            return false
        case .mesh:
            drawMesh(rig, plane, corners: true)
        case .weights:
            drawWeights(rig, plane)
            drawBones(shapes, selected: model.selectedBone, faint: true)
            drawBrush(plane)
        default:
            drawBones(shapes, selected: model.selectedBone, faint: false)
        }
        if case .box(let from, let to) = rigGesture {
            let box = NSBezierPath(rect: NSRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y)))
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
            box.fill()
            NSColor.controlAccentColor.setStroke()
            box.stroke()
        }
        return true
    }

    private func drawMesh(_ rig: WallpaperEnginePuppetRig, _ plane: RigPlane, corners: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let points = rig.points.map(plane.view)
        context.beginPath()
        for index in stride(from: 0, to: rig.triangles.count - 2, by: 3) {
            context.addLines(between: [points[rig.triangles[index]], points[rig.triangles[index + 1]], points[rig.triangles[index + 2]]])
            context.closePath()
        }
        context.setLineWidth(0.75)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        context.strokePath()
        guard corners, let model else { return }
        // On a fine mesh the corners would hide the picture: the selected ones always show.
        let all = plane.scale * sqrt(rig.width * rig.height / Double(max(rig.points.count, 1))) > 7
        for (index, at) in points.enumerated() {
            let selected = model.selectedPoints.contains(index)
            guard selected || all else { continue }
            let size: CGFloat = selected ? 7 : 5
            let dot = CGRect(x: at.x - size / 2, y: at.y - size / 2, width: size, height: size)
            context.setFillColor((selected ? NSColor.controlAccentColor : NSColor.white).cgColor)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.6).cgColor)
            context.setLineWidth(1)
            context.addRect(dot)
            context.drawPath(using: .fillStroke)
        }
    }

    /// Blue where the bone holds nothing, through green, to red where it holds all.
    private func heat(_ value: Double) -> CGColor {
        let hue = (1 - min(1, max(0, value))) * 0.66
        return NSColor(hue: hue, saturation: 0.9, brightness: 0.95, alpha: 0.6).cgColor
    }

    private func drawWeights(_ rig: WallpaperEnginePuppetRig, _ plane: RigPlane) {
        guard let context = NSGraphicsContext.current?.cgContext, let bone = model?.selectedBone else {
            drawMesh(rig, plane, corners: false)
            return
        }
        if weightCache?.bone != bone || weightCache?.rig != rig {
            weightCache = (rig, bone, rig.weights(of: bone))
        }
        let values = weightCache?.values ?? []
        let points = rig.points.map(plane.view)
        for index in stride(from: 0, to: rig.triangles.count - 2, by: 3) {
            let a = rig.triangles[index], b = rig.triangles[index + 1], c = rig.triangles[index + 2]
            context.beginPath()
            context.addLines(between: [points[a], points[b], points[c]])
            context.closePath()
            context.setFillColor(heat((values[a] + values[b] + values[c]) / 3))
            context.fillPath()
        }
    }

    private func drawBrush(_ plane: RigPlane) {
        guard let brushAt, let model else { return }
        let radius = model.weightSize / 2 * plane.scale
        let ring = NSBezierPath(ovalIn: NSRect(x: brushAt.x - radius, y: brushAt.y - radius, width: radius * 2, height: radius * 2))
        ring.lineWidth = 1.5
        NSColor.controlAccentColor.setStroke()
        ring.stroke()
    }

    /// Bones the way Blender draws them: wide near the joint they turn about, narrowing to where
    /// they end, each with its joint; a thin line joins one to a parent it does not start from.
    private func drawBones(_ shapes: [RigBoneShape], selected: Int?, faint: Bool) {
        let accent = NSColor.controlAccentColor
        let body = NSColor.white.withAlphaComponent(faint ? 0.45 : 0.8)
        let edge = NSColor.black.withAlphaComponent(faint ? 0.5 : 0.75)
        for shape in shapes {
            guard let parent = shape.parent, shapes.indices.contains(parent) else { continue }
            let from = shapes[parent].tail
            guard hypot(from.x - shape.head.x, from.y - shape.head.y) > 2 else { continue }
            let line = NSBezierPath()
            line.move(to: shapes[parent].head)
            line.line(to: shape.head)
            line.setLineDash([4, 3], count: 2, phase: 0)
            line.lineWidth = 1
            edge.setStroke()
            line.stroke()
        }
        for shape in shapes where shape.index != selected { drawBone(shape, fill: body, edge: edge, joint: body) }
        if let chosen = shapes.first(where: { $0.index == selected }) {
            drawBone(chosen, fill: accent.withAlphaComponent(0.9), edge: NSColor.white, joint: accent)
        }
    }

    private func drawBone(_ shape: RigBoneShape, fill: NSColor, edge: NSColor, joint: NSColor) {
        let dx = shape.tail.x - shape.head.x, dy = shape.tail.y - shape.head.y
        let length = max(hypot(dx, dy), 1)
        let way = CGPoint(x: dx / length, y: dy / length), side = CGPoint(x: -way.y, y: way.x)
        let wide = min(max(length * 0.11, 3.5), 11)
        let shoulder = CGPoint(x: shape.head.x + way.x * min(length * 0.16, 16), y: shape.head.y + way.y * min(length * 0.16, 16))
        let kite = NSBezierPath()
        kite.move(to: shape.head)
        kite.line(to: CGPoint(x: shoulder.x + side.x * wide, y: shoulder.y + side.y * wide))
        kite.line(to: shape.tail)
        kite.line(to: CGPoint(x: shoulder.x - side.x * wide, y: shoulder.y - side.y * wide))
        kite.close()
        fill.setFill()
        kite.fill()
        kite.lineWidth = 1
        edge.setStroke()
        kite.stroke()
        let size: CGFloat = 8
        let dot = NSBezierPath(ovalIn: NSRect(x: shape.head.x - size / 2, y: shape.head.y - size / 2, width: size, height: size))
        joint.setFill()
        dot.fill()
        dot.stroke()
    }

    // MARK: - The mouse

    private func nearestBone(_ at: CGPoint, _ shapes: [RigBoneShape]) -> RigBoneShape? {
        shapes.min { $0.distance(at) < $1.distance(at) }.flatMap { $0.distance(at) <= 9 ? $0 : nil }
    }

    /// A press over the scene in a mode of the rig. False leaves it to the object's frame.
    func rigMouseDown(_ at: CGPoint, _ event: NSEvent) -> Bool {
        guard let model, model.mode.isRig else { return false }
        guard let rig, let plane, let place = plane.rig(at) else { return true }
        let shapes = model.mode == .mesh ? [] : boneShapes(rig, plane)
        switch model.mode {
        case .mesh:
            pressMesh(at, place, rig, plane, event)
        case .rig:
            pressRig(at, place, rig, shapes)
        case .pose:
            let found = nearestBone(at, shapes)
            model.selectBone(found?.index)
            if let found {
                let moves = model.standingBones(of: rig)
                let pivot = WallpaperEnginePuppetRig.Point(x: moves[found.index].tx, y: moves[found.index].ty)
                if model.tool == .move {
                    rigGesture = .move(found.index, key: model.pose(of: found.index), from: place, parent: found.parent.map { moves[$0] })
                } else {
                    rigGesture = .turn(found.index, key: model.pose(of: found.index), pivot: pivot, from: atan2(place.y - pivot.y, place.x - pivot.x))
                }
            }
        case .weights:
            if event.modifierFlags.contains(.control) {
                model.selectBone(nearestBone(at, shapes)?.index)
            } else if model.selectedBone != nil {
                rigGesture = .weight
                paintWeight(place, event)
            }
        default:
            break
        }
        needsDisplay = true
        return true
    }

    private func pressMesh(_ at: CGPoint, _ place: WallpaperEnginePuppetRig.Point, _ rig: WallpaperEnginePuppetRig, _ plane: RigPlane, _ event: NSEvent) {
        guard let model else { return }
        let near = rig.points.indices.min {
            let a = plane.view(rig.points[$0]), b = plane.view(rig.points[$1])
            return hypot(a.x - at.x, a.y - at.y) < hypot(b.x - at.x, b.y - at.y)
        }
        if let near, hypot(plane.view(rig.points[near]).x - at.x, plane.view(rig.points[near]).y - at.y) <= 9 {
            if event.modifierFlags.contains(.shift) {
                if model.selectedPoints.remove(near) == nil { model.selectedPoints.insert(near) }
            } else if !model.selectedPoints.contains(near) {
                model.selectedPoints = [near]
            }
            rigGesture = .corners(from: place, start: Dictionary(uniqueKeysWithValues: model.selectedPoints.map { ($0, rig.points[$0]) }))
        } else {
            if !event.modifierFlags.contains(.shift) { model.selectedPoints = [] }
            rigGesture = .box(from: at, to: at)
        }
    }

    private func pressRig(_ at: CGPoint, _ place: WallpaperEnginePuppetRig.Point, _ rig: WallpaperEnginePuppetRig, _ shapes: [RigBoneShape]) {
        guard let model else { return }
        if model.tool == .addBone {
            // From the end of the selected bone if the press is there, as Blender's extrude.
            var start = place
            let parent = model.selectedBone.flatMap { rig.bones.indices.contains($0) ? $0 : nil }
            if let parent, let shape = shapes.first(where: { $0.index == parent }), hypot(shape.tail.x - at.x, shape.tail.y - at.y) <= 10 {
                start = rig.restTail(of: parent)
            }
            var made = 0
            model.editRig { made = $0.addBone(at: start, parent: parent) }
            model.selectBone(made)
            rigGesture = .newBone(made)
            return
        }
        if let shape = shapes.reversed().first(where: { hypot($0.tail.x - at.x, $0.tail.y - at.y) <= 8 }) {
            model.selectBone(shape.index)
            rigGesture = .tail(shape.index)
        } else if let shape = shapes.reversed().first(where: { hypot($0.head.x - at.x, $0.head.y - at.y) <= 8 }) {
            model.selectBone(shape.index)
            rigGesture = .head(shape.index)
        } else if let shape = nearestBone(at, shapes) {
            model.selectBone(shape.index)
            rigGesture = .wholeBone(shape.index, from: place, head: rig.bones[shape.index].joint, tail: rig.restTail(of: shape.index))
        } else {
            model.selectBone(nil)
        }
    }

    func rigMouseDragged(_ at: CGPoint, _ event: NSEvent) -> Bool {
        guard let model, model.mode.isRig else { return false }
        guard let plane, let place = plane.rig(at), let gesture = rigGesture else { return true }
        switch gesture {
        case .head(let bone):
            model.editRig { $0.bones[bone].joint = place }
        case .tail(let bone), .newBone(let bone):
            model.editRig { rig in
                let before = rig.restTail(of: bone)
                rig.bones[bone].tail = place
                // What starts where the bone ends goes with it.
                for child in rig.bones.indices where rig.bones[child].parent == bone &&
                    hypot(rig.bones[child].joint.x - before.x, rig.bones[child].joint.y - before.y) < 0.5 {
                    rig.bones[child].joint = place
                }
            }
        case .wholeBone(let bone, let from, let head, let tail):
            let x = place.x - from.x, y = place.y - from.y
            model.editRig { rig in
                rig.bones[bone].joint = .init(x: head.x + x, y: head.y + y)
                rig.bones[bone].tail = .init(x: tail.x + x, y: tail.y + y)
            }
        case .corners(let from, let start):
            let x = place.x - from.x, y = place.y - from.y
            model.editRig { rig in
                for (index, point) in start where rig.points.indices.contains(index) {
                    rig.points[index] = .init(x: point.x + x, y: point.y + y)
                }
            }
        case .box(let from, _):
            rigGesture = .box(from: from, to: at)
        case .turn(let bone, var key, let pivot, let from):
            var by = atan2(place.y - pivot.y, place.x - pivot.x) - from
            if event.modifierFlags.contains(.shift) { by = (by / (.pi / 12)).rounded() * (.pi / 12) }
            key.angle += atan2(sin(by), cos(by))
            model.setPose(key, of: bone)
        case .move(let bone, var key, let from, let parent):
            var x = place.x - from.x, y = place.y - from.y
            if let parent {
                // Counted along the parent, however it stands.
                let back = parent.inverted()
                (x, y) = (back.a * x + back.c * y, back.b * x + back.d * y)
            }
            key.dx += x
            key.dy += y
            model.setPose(key, of: bone)
        case .weight:
            paintWeight(place, event)
        }
        brushAt = at
        needsDisplay = true
        return true
    }

    func rigMouseUp(_ at: CGPoint, _ event: NSEvent) -> Bool {
        guard let model, model.mode.isRig else { return false }
        if case .box(let from, let to) = rigGesture, let rig, let plane {
            let box = CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y))
            model.selectedPoints.formUnion(rig.points.indices.filter { box.contains(plane.view(rig.points[$0])) })
        }
        rigGesture = nil
        model.endGesture()
        needsDisplay = true
        return true
    }

    private func paintWeight(_ place: WallpaperEnginePuppetRig.Point, _ event: NSEvent) {
        guard let model, let bone = model.selectedBone else { return }
        let adds = model.weightAdds != event.modifierFlags.contains(.shift)
        model.editRig {
            $0.paintWeight(bone: bone, at: place, radius: model.weightSize / 2, strength: model.weightStrength / 100, target: adds ? 1 : 0)
        }
    }
}

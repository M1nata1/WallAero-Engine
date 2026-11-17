import AppKit
import simd
import WallpaperCore

/// Where an eye is, what it looks at and which way is up, in the scene's units.
struct EngineLook: Equatable {
    var eye: SIMD3<Double>
    var center: SIMD3<Double>
    var up: SIMD3<Double>

    var forPlayer: [String: Any] {
        ["eye": [eye.x, eye.y, eye.z], "center": [center.x, center.y, center.z], "up": [up.x, up.y, up.z]]
    }
}

/// What the scene's camera shows: of a flat scene the middle of what it shows, from the scene's
/// middle, and how near; of one in three dimensions where it looks from and to.
struct EngineCameraView: Equatable {
    var inDepth: Bool
    var x = 0.0, y = 0.0, zoom = 1.0
    var look: EngineLook?
    /// The camera object looked through, if one, and whether it hangs on another.
    var camera: Int?
    var hangs = false
    var scripted = false
    /// How wide the camera sees, up and down, in degrees.
    var fov = 50.0

    init?(_ said: [String: Any]) {
        inDepth = said["depth"] as? Bool ?? false
        func number(_ name: String) -> Double { (said[name] as? NSNumber)?.doubleValue ?? 0 }
        func three(_ name: String) -> SIMD3<Double>? {
            guard let list = said[name] as? [NSNumber], list.count >= 3 else { return nil }
            return SIMD3(list[0].doubleValue, list[1].doubleValue, list[2].doubleValue)
        }
        if inDepth {
            guard let eye = three("eye"), let center = three("center"), let up = three("up") else { return nil }
            look = EngineLook(eye: eye, center: center, up: up)
            camera = (said["camera"] as? NSNumber)?.intValue
            hangs = said["hangs"] as? Bool ?? false
            scripted = said["scripted"] as? Bool ?? false
            fov = (said["fov"] as? NSNumber)?.doubleValue ?? 50
        } else {
            x = number("x")
            y = number("y")
            zoom = max(number("zoom"), 0.01)
        }
    }
}

/// The view of the scene, as Blender's viewport has it: through the scene's camera (0 on the
/// keypad, or the 0 key), or freely — a scene in three dimensions turned about with two fingers
/// or the middle button, moved with Shift, brought nearer with a pinch or the wheel; a flat one
/// seen whole, with what its camera shows framed. Control-Option-0 puts the camera where the
/// free eye is.
extension EngineEditorModel {
    var isInDepth: Bool { cameraView?.inDepth ?? false }

    /// Asks the player what its camera shows now.
    func refreshCameraView() {
        cameraView = preview?.cameraView()
    }

    func toggleCameraView() {
        setViewsFreely(!viewsFreely)
    }

    func setViewsFreely(_ free: Bool) {
        refreshCameraView()
        if free, isInDepth, freeLook == nil { freeLook = cameraView?.look }
        viewsFreely = free
        if !free { fitView() }
        showFreeView()
    }

    /// Whether the free view moves in depth: as chosen, else as the scene is.
    var movesIn3D: Bool { viewIn3D ?? isInDepth }

    /// Has the free view move flat or in depth, as Unity's 2D button does; looking through the
    /// camera, it looks freely then.
    func setViewIn3D(_ inDepth: Bool) {
        viewIn3D = inDepth
        if viewsFreely { showFreeView() } else { setViewsFreely(true) }
    }

    /// Hands the player and the preview the view as it now is.
    private func showFreeView() {
        guard viewsFreely else {
            preview?.setCard(nil)
            preview?.setView(free: false, look: nil, flat: nil)
            return
        }
        if isInDepth {
            preview?.setCard(nil)
            if movesIn3D {
                preview?.setView(free: true, look: freeLook, flat: nil)
            } else {
                if flatLook == nil, let from = freeLook ?? cameraView?.look {
                    // Straight on from the front, as far as the eye was, seeing as much there.
                    let reach = max(simd_length(from.eye - from.center), 0.001)
                    flatLook = EngineLook(eye: from.center + SIMD3(0, 0, reach), center: from.center, up: SIMD3(0, 1, 0))
                    flatHeight = reach * tan((cameraView?.fov ?? 50) * .pi / 360)
                }
                preview?.setView(free: true, look: flatLook, flat: flatHeight)
            }
        } else {
            preview?.setView(free: true, look: nil, flat: nil)
            preview?.setCard(movesIn3D ? cardTurn : nil)
        }
    }

    /// A drag of the view — two fingers, the middle button, the hand: in depth it turns the
    /// view about (with Shift it moves it), flat it moves it.
    func navigate(by distance: CGSize, moving: Bool, within size: CGSize) {
        guard viewsFreely else { return panView(by: distance, within: size) }
        switch (isInDepth, movesIn3D) {
        case (true, true): moving ? panLook(by: distance) : orbit(by: distance)
        case (true, false): panFlat(by: distance, within: size)
        case (false, true):
            if moving { panView(by: distance, within: size) } else { turnCard(by: distance) }
        case (false, false): panView(by: distance, within: size)
        }
    }

    /// The view brought nearer or taken further, round a point from the middle of the preview.
    func navigateZoom(by factor: CGFloat, around point: CGSize) {
        guard viewsFreely, isInDepth else { return zoomView(by: factor, around: point) }
        if movesIn3D {
            dollyLook(by: factor)
        } else if factor > 0 {
            flatHeight = max(flatHeight / Double(factor), 1e-4)
            preview?.setView(free: true, look: flatLook, flat: flatHeight)
        }
    }

    /// Moves the flat eye sideways and up, the scene following the pointer.
    private func panFlat(by distance: CGSize, within size: CGSize) {
        guard var look = flatLook, size.height > 0 else { return }
        let perPoint = flatHeight * 2 / Double(size.height)
        let shift = SIMD3(-Double(distance.width) * perPoint, Double(distance.height) * perPoint, 0)
        look.eye += shift
        look.center += shift
        flatLook = look
        preview?.setView(free: true, look: look, flat: flatHeight)
    }

    private func turnCard(by distance: CGSize) {
        cardTurn = CGSize(width: min(max(cardTurn.width + distance.width * 0.4, -85), 85),
                          height: min(max(cardTurn.height + distance.height * 0.4, -85), 85))
        preview?.setCard(cardTurn)
    }

    /// Whether the scene is shown as a card turned in depth, which cannot be worked on.
    var showsCard: Bool { viewsFreely && !isInDepth && movesIn3D }

    /// Turns the free eye round what it looks at: across about the scene's up, along about the
    /// eye's own right, as Blender's turntable does.
    func orbit(by distance: CGSize) {
        guard viewsFreely, isInDepth, var look = freeLook else { return }
        let offset = look.eye - look.center
        let up = simd_normalize(look.up)
        let across = simd_quatd(angle: -Double(distance.width) * 0.008, axis: up)
        var turned = across.act(offset)
        let right = simd_normalize(simd_cross(-turned, up))
        let along = simd_quatd(angle: -Double(distance.height) * 0.008, axis: right)
        let next = along.act(turned)
        // Never over the top: the eye stays off the line straight up and down.
        if abs(simd_dot(simd_normalize(next), up)) < 0.995 { turned = next }
        look.eye = look.center + turned
        setFreeLook(look)
    }

    /// Moves the free eye and what it looks at sideways and up, by points of the preview.
    func panLook(by distance: CGSize) {
        guard viewsFreely, isInDepth, var look = freeLook else { return }
        let forward = look.center - look.eye
        let reach = simd_length(forward)
        let right = simd_normalize(simd_cross(forward, look.up))
        let up = simd_normalize(simd_cross(right, forward))
        let by = reach * 0.0015
        let shift = right * (-Double(distance.width) * by) + up * (Double(distance.height) * by)
        look.eye += shift
        look.center += shift
        setFreeLook(look)
    }

    /// Brings the free eye nearer what it looks at, or takes it further.
    func dollyLook(by factor: CGFloat) {
        guard viewsFreely, isInDepth, var look = freeLook, factor > 0 else { return }
        let offset = (look.eye - look.center) / Double(factor)
        guard simd_length(offset) > 1e-4 else { return }
        look.eye = look.center + offset
        setFreeLook(look)
    }

    private func setFreeLook(_ look: EngineLook) {
        freeLook = look
        preview?.setView(free: true, look: look, flat: nil)
    }

    /// Whether the camera can be put where the free eye is: a camera object that hangs on none,
    /// or the scene's own camera where there is no camera object.
    var canAlignCamera: Bool {
        guard viewsFreely, isInDepth, movesIn3D, freeLook != nil, let cameraView else { return false }
        return !cameraView.scripted && !(cameraView.camera != nil && cameraView.hangs)
    }

    /// Puts the scene's camera where the free eye is, looking where it looks, and looks through it.
    func alignCameraToView() {
        guard canAlignCamera, let look = freeLook, let cameraView else { return }
        endGesture()
        if let id = cameraView.camera {
            guard let placing = preview?.cameraPlacing(look) else { return }
            set(id, "origin", .vector(placing.origin))
            set(id, "angles", .vector(placing.angles))
        } else {
            func text(_ v: SIMD3<Double>) -> JSONValue { .vector([v.x, v.y, v.z]) }
            change { document in
                var camera = document.scene["camera"] ?? .object([:])
                camera["eye"] = text(look.eye)
                camera["center"] = text(look.center)
                camera["up"] = text(look.up)
                document.scene["camera"] = camera
            }
        }
        endGesture()
        setViewsFreely(false)
    }
}

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
        preview?.setView(free: free, look: free && isInDepth ? freeLook : nil)
    }

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
        preview?.setView(free: true, look: look)
    }

    /// Whether the camera can be put where the free eye is: a camera object that hangs on none,
    /// or the scene's own camera where there is no camera object.
    var canAlignCamera: Bool {
        guard viewsFreely, isInDepth, freeLook != nil, let cameraView else { return false }
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

import AppKit

/// Passes the mouse on to web wallpapers.
///
/// A wallpaper's window lies under the desktop's icons and lets clicks through to them, so the
/// page in it gets no mouse of its own. This watches the pointer wherever it is, and while it
/// is over the desktop — no window of any app under it — tells the page where it is and when
/// the button goes down and comes up. Wallpapers that turn to the pointer or take clicks, as
/// many made for Wallpaper Engine do, work that way. A click goes to the desktop as well, as
/// ever: this only listens.
@MainActor
final class PointerForwarder {
    enum Kind: String {
        case move, down, up
        /// The pointer has gone from the wallpaper: over a window, or to another display.
        case leave
    }

    /// A wallpaper that takes the pointer.
    struct Target {
        /// Tells two targets apart; the wallpaper's view.
        let id: ObjectIdentifier
        /// Where it is, in the coordinates of the screens.
        let frame: NSRect
        /// Tells the page. The point is in the wallpaper, from its top left corner.
        let send: (Kind, CGPoint) -> Void
    }

    /// The wallpapers that take the pointer now.
    var targets: () -> [Target] = { [] }

    /// Whether the pointer is watched at all. It is not while no page is there to be told.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            if isActive {
                start()
            } else {
                stop()
            }
        }
    }

    private var monitors: [Any] = []
    private var activation: [NSObjectProtocol] = []
    private var ownMoves: Timer?
    private var lastLocation = NSPoint(x: -1, y: -1)
    /// The wallpaper the pointer is over, and the one the button went down on.
    private var hovered: ObjectIdentifier?
    private var pressed: ObjectIdentifier?
    private var lastMove = 0.0
    private var hasMoveWaiting = false
    /// Whether a window is part of the desktop, by its number; asked anew every few seconds,
    /// as numbers come to stand for other windows.
    private var desktopWindows: [Int: (isDesktop: Bool, asked: Double)] = [:]

    /// Pages are told of the pointer's moves this often at most.
    private static let moveInterval = 1.0 / 60

    private func start() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        // The mouse in other apps, the desktop's own among them. Watching the mouse this way
        // needs no permission; only the keyboard does.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event.type) }
        }) {
            monitors.append(monitor)
        }
        // While the app itself is in front, the pointer's moves come to no one else, and to
        // the app only inside its windows. For as long as that lasts the pointer is looked up
        // instead; the rest of the time nothing runs between one move of the mouse and the next.
        let center = NotificationCenter.default
        activation = [
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lookUpOwnMoves(true) }
            },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lookUpOwnMoves(false) }
            },
        ]
        lookUpOwnMoves(NSApp.isActive)
    }

    private func lookUpOwnMoves(_ looking: Bool) {
        ownMoves?.invalidate()
        ownMoves = nil
        guard looking else { return }
        ownMoves = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let location = NSEvent.mouseLocation
                if location != self.lastLocation {
                    self.handle(.move, at: location)
                }
            }
        }
    }

    private func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        activation.forEach(NotificationCenter.default.removeObserver)
        activation = []
        lookUpOwnMoves(false)
        leave()
        pressed = nil
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown: handle(.down)
        case .leftMouseUp: handle(.up)
        default: handle(.move)
        }
    }

    /// What the mouse did, wherever it is now. Also the way a test stands in for the mouse.
    func handle(_ kind: Kind, at location: NSPoint = NSEvent.mouseLocation) {
        lastLocation = location
        switch kind {
        case .down:
            guard let target = target(at: location) else { return }
            hover(target, at: location)
            pressed = target.id
            target.send(.down, point(location, in: target))
        case .up:
            guard let id = pressed else { return }
            pressed = nil
            guard let target = targets().first(where: { $0.id == id }) else { return }
            target.send(.up, point(location, in: target))
            // The button may have come up over a window the pointer was dragged onto.
            if self.target(at: location)?.id != id {
                leave()
            }
        case .move:
            let now = CFAbsoluteTimeGetCurrent()
            guard now - lastMove >= Self.moveInterval else {
                // The place the pointer comes to rest in is told, if a little later.
                if !hasMoveWaiting {
                    hasMoveWaiting = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.moveInterval) { [weak self] in
                        self?.hasMoveWaiting = false
                        self?.handle(.move)
                    }
                }
                return
            }
            lastMove = now
            if let id = pressed {
                // A drag that began on the wallpaper goes on wherever the pointer is taken.
                if let target = targets().first(where: { $0.id == id }) {
                    target.send(.move, point(location, in: target))
                }
            } else if let target = target(at: location) {
                hover(target, at: location)
                target.send(.move, point(location, in: target))
            } else {
                leave()
            }
        case .leave:
            leave()
        }
    }

    private func hover(_ target: Target, at location: NSPoint) {
        if hovered != target.id {
            leave()
            hovered = target.id
        }
    }

    private func leave() {
        guard let id = hovered else { return }
        hovered = nil
        targets().first { $0.id == id }?.send(.leave, .zero)
    }

    /// The wallpaper under the pointer, if nothing lies between the two.
    private func target(at location: NSPoint) -> Target? {
        guard isDesktop(at: location) else { return nil }
        return targets().first { $0.frame.contains(location) }
    }

    private func point(_ location: NSPoint, in target: Target) -> CGPoint {
        CGPoint(x: location.x - target.frame.minX, y: target.frame.maxY - location.y)
    }

    /// Whether the topmost window at a place on the screens is the desktop: the wallpaper's own
    /// window, or Finder's with the icons, which lies over it. Windows of apps, the Dock and
    /// the menu bar are all on levels above those.
    func isDesktop(at location: NSPoint) -> Bool {
        let number = NSWindow.windowNumber(at: location, belowWindowWithWindowNumber: 0)
        guard number != 0 else { return true }
        let now = CFAbsoluteTimeGetCurrent()
        if let known = desktopWindows[number], now - known.asked < 5 {
            return known.isDesktop
        }
        let windows = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(number)) as? [[String: Any]]
        let level = windows?.first?[kCGWindowLayer as String] as? Int ?? 0
        let isDesktop = level <= Int(CGWindowLevelForKey(.desktopIconWindow))
        if desktopWindows.count > 200 {
            desktopWindows.removeAll()
        }
        desktopWindows[number] = (isDesktop, now)
        return isDesktop
    }
}

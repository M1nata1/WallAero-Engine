import AppKit

/// Tells how much of a display's desktop can be seen around the windows that lie over it.
///
/// A wallpaper's own window is no help with that: macOS calls it visible as long as any of it
/// is, and the strip under the see-through menu bar always is — so a wallpaper went on playing,
/// at full cost, under a window that filled the whole screen. Here a grid of tiny see-through
/// windows lies over the wallpaper instead, and macOS says of each whether it is covered. It
/// says so by itself whenever that changes, so nothing has to be looked up on a timer, and it
/// knows what no list of windows tells: what is see-through, and that the windows have been
/// moved aside to show the desktop.
@MainActor
final class DesktopVisibility {
    /// Called when `isCovered` changes.
    var onChange: (() -> Void)?

    /// Whether windows cover the desktop but for slivers. A wallpaper is not worth drawing then.
    private(set) var isCovered = false

    /// The desktop counts as covered when less than this share of it shows.
    static let smallestShare = 0.1
    private static let columns = 8
    private static let rows = 5
    /// A window dragged across the screen covers the desktop for a moment; only a cover that
    /// stays is taken for one. The desktop coming back into view is taken at once.
    private static let coverMustLast: TimeInterval = 0.6

    private var probes: [NSWindow] = []
    private var area: NSRect
    private var isShown = false
    private var observer: NSObjectProtocol?
    private var recount: DispatchWorkItem?
    private var cover: DispatchWorkItem?

    init(screen: NSScreen) {
        area = screen.visibleFrame
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// The share of the probes that can be seen, from 0 to 1.
    var seenShare: Double {
        guard isShown, !probes.isEmpty else { return 1 }
        return Double(probes.filter { $0.occlusionState.contains(.visible) }.count) / Double(probes.count)
    }

    /// Follows the display to where it is now. The probes keep off the menu bar and the Dock:
    /// those are see-through, and what lies under them would always count as seen.
    func move(to screen: NSScreen) {
        guard screen.visibleFrame != area else { return }
        area = screen.visibleFrame
        place()
    }

    /// Starts watching; the wallpaper is on the display.
    func show() {
        guard !isShown else { return }
        isShown = true
        if probes.isEmpty {
            probes = (0..<(Self.columns * Self.rows)).map { _ in Self.makeProbe() }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                              object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, let window = note.object as? NSWindow, self.probes.contains(where: { $0 === window }) else { return }
                    self.probesDidChange()
                }
            }
        }
        place()
        probes.forEach { $0.orderFrontRegardless() }
        probesDidChange()
    }

    /// Stops watching; nothing is on the display to be paused.
    func hide() {
        guard isShown else { return }
        isShown = false
        probes.forEach { $0.orderOut(nil) }
        recount?.cancel()
        cover?.cancel()
        isCovered = false
    }

    private func place() {
        let side = 2.0
        for (index, probe) in probes.enumerated() {
            // The middle of each cell of the grid.
            let x = area.minX + (Double(index % Self.columns) + 0.5) * area.width / Double(Self.columns)
            let y = area.minY + (Double(index / Self.columns) + 0.5) * area.height / Double(Self.rows)
            probe.setFrame(NSRect(x: x - side / 2, y: y - side / 2, width: side, height: side), display: false)
        }
    }

    /// macOS tells of the probes one by one; they are counted once it has told of them all.
    private func probesDidChange() {
        recount?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.count() }
        recount = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func count() {
        guard isShown else { return }
        let covered = seenShare < Self.smallestShare
        cover?.cancel()
        cover = nil
        guard covered != isCovered else { return }
        if covered {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isShown, self.seenShare < Self.smallestShare, !self.isCovered else { return }
                self.isCovered = true
                self.onChange?()
            }
            cover = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.coverMustLast, execute: work)
        } else {
            isCovered = false
            onChange?()
        }
    }

    /// A window with nothing in it, just over the wallpaper and under the desktop's icons, on
    /// every Space as the wallpaper is. It is never drawn and takes no clicks.
    private static func makeProbe() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 2, height: 2), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isExcludedFromWindowsMenu = true
        window.animationBehavior = .none
        window.canHide = false
        // Not something to pick in a list of windows to share, nor for VoiceOver to read out.
        window.sharingType = .none
        window.setAccessibilityElement(false)
        return window
    }
}

import Foundation

/// Which wallpapers of the library are selected, and how clicks change that — the way the
/// Finder has it. A click selects a wallpaper alone; with Command it is added to those selected
/// or taken from them; with Shift every wallpaper from the one clicked before to this one is
/// selected. Several are selected to be deleted together.
public struct WallpaperSelection: Equatable, Sendable {
    public enum Click: Sendable {
        /// A plain click.
        case alone
        /// With Command held.
        case toggling
        /// With Shift held.
        case extending
    }

    /// The wallpapers selected.
    public private(set) var ids: Set<UUID> = []
    /// The one selected last, if any is: the wallpaper whose settings are shown while it is
    /// the only one.
    public private(set) var last: UUID?
    /// Where a run selected with Shift starts.
    private var anchor: UUID?

    public init() {}

    /// Selects one wallpaper alone, or none.
    public mutating func select(_ id: UUID?) {
        ids = id.map { [$0] } ?? []
        last = id
        anchor = id
    }

    /// What a click on a wallpaper does.
    /// - Parameter order: the wallpapers as the library shows them.
    public mutating func click(_ id: UUID, _ click: Click, in order: [UUID]) {
        switch click {
        case .alone:
            select(id)
        case .toggling:
            if ids.contains(id) {
                ids.remove(id)
                if last == id {
                    last = order.last(where: ids.contains)
                }
                anchor = last
            } else {
                ids.insert(id)
                last = id
                anchor = id
            }
        case .extending:
            guard let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) else {
                select(id)
                return
            }
            ids = Set(order[min(from, to)...max(from, to)])
            last = id
        }
    }

    /// Selects every wallpaper the library shows.
    public mutating func selectAll(_ order: [UUID]) {
        ids = Set(order)
        if last.map(ids.contains) != true {
            last = order.first
        }
        if anchor.map(ids.contains) != true {
            anchor = last
        }
    }

    /// Lets go of the selected wallpapers that are not among those the library shows: what is
    /// out of sight is not deleted with the rest.
    public mutating func keep(_ shown: [UUID]) {
        let kept = ids.intersection(shown)
        guard kept != ids else { return }
        ids = kept
        if last.map(kept.contains) != true {
            last = shown.last(where: kept.contains)
        }
        if anchor.map(kept.contains) != true {
            anchor = last
        }
    }
}

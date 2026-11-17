import AppKit
import SwiftUI

/// What differs between the looks of macOS. Since macOS 26 bars are glass over the content, which
/// scrolls under them, and corners are rounder; before it a line parts a bar from the content.
///
/// macOS 26 shows the new look only to an app built with its SDK, the one that comes with
/// Swift 6.2. Older tools cannot compile that code, so they leave it out and build the app in
/// the look it had.
enum SystemLook {
    static let isGlass: Bool = {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return true
        }
        #endif
        return false
    }()

    // The corners, from the largest to the smallest. Everything round in the app takes one of
    // these, so that what is alike is rounded alike.

    /// The corners of the frames around the whole library: the empty one, and where files drop.
    static let frameCornerRadius: CGFloat = isGlass ? 24 : 18
    /// The corners of a wallpaper's picture standing on its own: in the library, the Workshop
    /// and the editor.
    static let tileCornerRadius: CGFloat = isGlass ? 14 : 10
    /// The corners of a picture inside a group of settings, and of a card or a panel of tools.
    static let insetCornerRadius: CGFloat = isGlass ? 12 : 8
    /// The corners of what stands inside such a card: a tool, a placeholder, a label.
    static let innerCornerRadius: CGFloat = insetCornerRadius - 4

    /// The height of what is in a bar: bars side by side keep their lines level.
    static let barContentHeight: CGFloat = 28
    /// The room at the sides of a bar, and above and below what is in it.
    static let barHorizontalPadding: CGFloat = 16
    static let barVerticalPadding: CGFloat = 8
    /// The room between the things in a bar.
    static let barSpacing: CGFloat = 12
    /// The room between the parts of a wallpaper's summary at the side of the window.
    static let summarySpacing: CGFloat = 12
}

extension View {
    /// The room around what is in a bar, above or below the content, the same in every window.
    func barPadding() -> some View {
        frame(minHeight: SystemLook.barContentHeight)
            .padding(.horizontal, SystemLook.barHorizontalPadding)
            .padding(.vertical, SystemLook.barVerticalPadding)
    }

    /// The row of topics at the top of a side panel, lined up with the groups of the form under it.
    func panelTabs() -> some View {
        pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }
}

/// What a wallpaper is, in rows of a name and a value: in its settings, and in the Workshop's panel.
struct PropertyGrid<Rows: View>: View {
    @ViewBuilder let rows: Rows

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            rows
        }
    }
}

/// A row of a `PropertyGrid`.
struct PropertyRow<Value: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let value: Value

    init(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    var body: some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            value
        }
    }
}

extension PropertyRow where Value == Text {
    init(_ title: LocalizedStringKey, verbatim value: String) {
        self.init(title) { Text(verbatim: value) }
    }
}

/// A tag shown as a capsule: the Workshop's, and the library's own.
struct TagCapsule<Content: View>: View {
    let content: Content
    let leading: CGFloat
    let trailing: CGFloat

    /// A button at the end of the tag stands closer to the edge than the text at its start.
    init(leading: CGFloat = 8, trailing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.leading = leading
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        content
            .font(.caption)
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}

extension View {
    /// Puts a bar of buttons below the view.
    @ViewBuilder
    func bottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            // The bar has text in it as well as buttons, so what scrolls under it is hidden
            // for good rather than left to show through.
            safeAreaBar(edge: .bottom, spacing: 0) { bar() }
                .scrollEdgeEffectStyle(.hard, for: .bottom)
        } else {
            linedBottomBar(bar)
        }
        #else
        linedBottomBar(bar)
        #endif
    }

    private func linedBottomBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        VStack(spacing: 0) {
            self
            Divider()
            bar()
        }
    }

    /// Puts a bar above the view, right under the window's toolbar.
    @ViewBuilder
    func topBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            safeAreaBar(edge: .top, spacing: 0) { bar() }
        } else {
            linedTopBar(bar)
        }
        #else
        linedTopBar(bar)
        #endif
    }

    private func linedTopBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        VStack(spacing: 0) {
            bar()
            Divider()
            self
        }
    }

    /// The style of a button in such a bar: glass since macOS 26, tinted for the main action.
    @ViewBuilder
    func barButtonStyle(isMainAction: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if isMainAction {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// The style of the main button of a bar that has no default button to take Return: tinted
    /// as the window's main action is.
    @ViewBuilder
    func mainActionButtonStyle() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            barButtonStyle(isMainAction: true)
        } else {
            buttonStyle(.borderedProminent)
        }
        #else
        buttonStyle(.borderedProminent)
        #endif
    }

    /// The system's search field draws its frame a point inside the room it is given, so that
    /// in a bar it stood a point further from the edge and from what is next to it than the
    /// buttons and menus do. This takes the point back.
    func barSearchField() -> some View {
        padding(.horizontal, -1)
    }
}

extension View {
    /// The style of a button that shows something is on, like Tags while tags are ticked:
    /// tinted then, and glass since macOS 26, as it stands in a bar there.
    @ViewBuilder
    func pressedButtonStyle(_ isPressed: Bool) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            barButtonStyle(isMainAction: isPressed)
        } else {
            borderedButtonStyle(isProminent: isPressed)
        }
        #else
        borderedButtonStyle(isProminent: isPressed)
        #endif
    }

    @ViewBuilder
    private func borderedButtonStyle(isProminent: Bool) -> some View {
        if isProminent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}

extension View {
    /// Leaves the window's title out of its toolbar, where a control in the title's place says
    /// what the window shows. macOS 14 has no way to ask for that.
    @ViewBuilder
    func withoutWindowTitle() -> some View {
        if #available(macOS 15.0, *) {
            toolbar(removing: .title)
        } else {
            self
        }
    }
}

extension NSMenuItem {
    /// macOS 26 puts a symbol next to some items by itself — a gear by "Settings…" — and indents the
    /// rest of that group to line up with it, so a menu looks ragged. There every item gets its
    /// own symbol, as in the system's menus; earlier systems draw menus without symbols.
    func setSymbol(_ name: String) {
        if #available(macOS 26, *) {
            image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
    }
}

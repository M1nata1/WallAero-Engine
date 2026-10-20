import CoreGraphics
import CoreText
import Foundation

/// A canvas a page draws on in 2D — texts, the shapes of particles — done with CoreGraphics and
/// CoreText, as much of the web's canvas as the scene player uses. Its rows run from the top,
/// as a page's do; its colors are kept multiplied by alpha and read back not.
final class Canvas2D {
    private(set) var width: Int
    private(set) var height: Int
    private var context: CGContext?

    private struct Style {
        var fill: Paint = .color(CGColor(gray: 0, alpha: 1))
        var stroke: Paint = .color(CGColor(gray: 0, alpha: 1))
        var lineWidth: CGFloat = 1
        var lineJoin: CGLineJoin = .miter
        var alpha: CGFloat = 1
        var font: CTFont = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
        var baseline = "alphabetic"
        var align = "start"
        var shadowColor = CGColor(gray: 0, alpha: 0)
        var shadowBlur: CGFloat = 0
        var shadowOffset = CGSize.zero
    }
    enum Paint { case color(CGColor), gradient(Gradient) }
    private var style = Style()
    private var saved: [Style] = []

    /// The fonts pages have given, by the family name they gave them.
    static var fonts: [String: CTFontDescriptor] = [:]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        makeContext()
    }

    func resize(width: Int, height: Int) {
        self.width = width
        self.height = height
        saved = []
        style = Style()
        makeContext()
    }

    private func makeContext() {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        context = CGContext(data: nil, width: max(1, width), height: max(1, height), bitsPerComponent: 8, bytesPerRow: max(1, width) * 4,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        // Rows from the top, as on a page.
        context?.translateBy(x: 0, y: CGFloat(max(1, height)))
        context?.scaleBy(x: 1, y: -1)
    }

    // MARK: Properties

    func set(_ name: String, _ value: Any?) {
        switch name {
        case "fillStyle": if let paint = paint(value) { style.fill = paint }
        case "strokeStyle": if let paint = paint(value) { style.stroke = paint }
        case "lineWidth": style.lineWidth = CGFloat((value as? NSNumber)?.doubleValue ?? 1)
        case "lineJoin": style.lineJoin = value as? String == "round" ? .round : (value as? String == "bevel" ? .bevel : .miter)
        case "globalAlpha": style.alpha = CGFloat((value as? NSNumber)?.doubleValue ?? 1)
        case "font": style.font = Self.font(from: value as? String ?? "")
        case "textBaseline": style.baseline = value as? String ?? "alphabetic"
        case "textAlign": style.align = value as? String ?? "start"
        case "shadowColor": style.shadowColor = Self.color(value as? String ?? "") ?? CGColor(gray: 0, alpha: 0)
        case "shadowBlur": style.shadowBlur = CGFloat((value as? NSNumber)?.doubleValue ?? 0)
        case "shadowOffsetX": style.shadowOffset.width = CGFloat((value as? NSNumber)?.doubleValue ?? 0)
        case "shadowOffsetY": style.shadowOffset.height = CGFloat((value as? NSNumber)?.doubleValue ?? 0)
        default: break
        }
    }

    private func paint(_ value: Any?) -> Paint? {
        if let text = value as? String { return Self.color(text).map(Paint.color) }
        if let dictionary = value as? [String: Any], let id = (dictionary["gradient"] as? NSNumber)?.intValue, let gradient = Gradient.all[id] {
            return .gradient(gradient)
        }
        return nil
    }

    // MARK: Calls

    func call(_ name: String, _ a: [Any]) {
        guard let c = context else { return }
        func n(_ i: Int) -> CGFloat { i < a.count ? CGFloat((a[i] as? NSNumber)?.doubleValue ?? 0) : 0 }
        switch name {
        case "save": saved.append(style); c.saveGState()
        case "restore": if let back = saved.popLast() { style = back }; c.restoreGState()
        case "beginPath": c.beginPath()
        case "closePath": c.closePath()
        case "moveTo": c.move(to: CGPoint(x: n(0), y: n(1)))
        case "lineTo": c.addLine(to: CGPoint(x: n(0), y: n(1)))
        case "quadraticCurveTo": c.addQuadCurve(to: CGPoint(x: n(2), y: n(3)), control: CGPoint(x: n(0), y: n(1)))
        case "bezierCurveTo": c.addCurve(to: CGPoint(x: n(4), y: n(5)), control1: CGPoint(x: n(0), y: n(1)), control2: CGPoint(x: n(2), y: n(3)))
        case "rect": c.addRect(CGRect(x: n(0), y: n(1), width: n(2), height: n(3)))
        case "arc":
            let counter = a.count > 5 && (a[5] as? NSNumber)?.boolValue == true
            c.addArc(center: CGPoint(x: n(0), y: n(1)), radius: max(0, n(2)), startAngle: n(3), endAngle: n(4), clockwise: counter)
        case "ellipse":
            // A circle stretched and turned; the path keeps its points as they were placed.
            let counter = a.count > 7 && (a[7] as? NSNumber)?.boolValue == true
            c.saveGState()
            c.translateBy(x: n(0), y: n(1))
            c.rotate(by: n(4))
            c.scaleBy(x: max(0.0001, n(2)), y: max(0.0001, n(3)))
            c.addArc(center: .zero, radius: 1, startAngle: n(5), endAngle: n(6), clockwise: counter)
            c.restoreGState()
        case "fill": fillPath(c)
        case "stroke": strokePath(c)
        case "clip": c.clip()
        case "fillRect":
            c.beginPath()
            c.addRect(CGRect(x: n(0), y: n(1), width: n(2), height: n(3)))
            fillPath(c)
        case "strokeRect":
            c.beginPath()
            c.addRect(CGRect(x: n(0), y: n(1), width: n(2), height: n(3)))
            strokePath(c)
        case "clearRect": c.clear(CGRect(x: n(0), y: n(1), width: n(2), height: n(3)))
        case "translate": c.translateBy(x: n(0), y: n(1))
        case "rotate": c.rotate(by: n(0))
        case "scale": c.scaleBy(x: n(0), y: n(1))
        case "transform": c.concatenate(CGAffineTransform(a: n(0), b: n(1), c: n(2), d: n(3), tx: n(4), ty: n(5)))
        case "setTransform":
            // Back to the page's own rows, then as given.
            c.concatenate(c.ctm.inverted())
            c.translateBy(x: 0, y: CGFloat(max(1, height)))
            c.scaleBy(x: 1, y: -1)
            c.concatenate(CGAffineTransform(a: n(0), b: n(1), c: n(2), d: n(3), tx: n(4), ty: n(5)))
        case "fillText", "strokeText": text(a.first as? String ?? "", x: n(1), y: n(2), stroked: name == "strokeText", in: c)
        default: break
        }
    }

    private func withShadow(_ c: CGContext, _ draw: () -> Void) {
        c.saveGState()
        c.setAlpha(style.alpha)
        if style.shadowColor.alpha > 0 && (style.shadowBlur > 0 || style.shadowOffset != .zero) {
            // In the page's rows, down is positive; CoreGraphics's shadows go by its own.
            c.setShadow(offset: CGSize(width: style.shadowOffset.width, height: -style.shadowOffset.height), blur: style.shadowBlur, color: style.shadowColor)
        }
        draw()
        c.restoreGState()
    }

    private func fillPath(_ c: CGContext) {
        guard let path = c.path else { return }
        withShadow(c) {
            switch style.fill {
            case .color(let color):
                c.addPath(path)
                c.setFillColor(color)
                c.fillPath()
            case .gradient(let gradient):
                c.addPath(path)
                c.clip()
                gradient.draw(in: c)
            }
        }
        c.addPath(path)
    }

    private func strokePath(_ c: CGContext) {
        guard let path = c.path else { return }
        withShadow(c) {
            c.addPath(path)
            c.setLineWidth(style.lineWidth)
            c.setLineJoin(style.lineJoin)
            if case .color(let color) = style.stroke { c.setStrokeColor(color) }
            c.strokePath()
        }
        c.addPath(path)
    }

    private func line(_ text: String, color: CGColor?) -> CTLine {
        var attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): style.font]
        if let color { attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color }
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    private func text(_ text: String, x: CGFloat, y: CGFloat, stroked: Bool, in c: CGContext) {
        let paint = stroked ? style.stroke : style.fill
        var color: CGColor? = nil
        if case .color(let chosen) = paint { color = chosen }
        let made = line(text, color: color)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(made, &ascent, &descent, nil))
        var origin = CGPoint(x: x, y: y)
        switch style.align {
        case "center": origin.x -= width / 2
        case "right", "end": origin.x -= width
        default: break
        }
        switch style.baseline {
        case "top", "hanging": origin.y += CTFontGetAscent(style.font)
        case "middle": origin.y += (CTFontGetAscent(style.font) - CTFontGetDescent(style.font)) / 2
        case "bottom", "ideographic": origin.y -= CTFontGetDescent(style.font)
        default: break
        }
        withShadow(c) {
            // The page's rows run down; a line of text is set the right way up.
            c.saveGState()
            c.translateBy(x: origin.x, y: origin.y)
            c.scaleBy(x: 1, y: -1)
            c.textPosition = .zero
            if stroked {
                c.setTextDrawingMode(.stroke)
                c.setLineWidth(style.lineWidth)
                c.setLineJoin(style.lineJoin)
                if let color { c.setStrokeColor(color) }
            }
            CTLineDraw(made, c)
            c.restoreGState()
        }
    }

    /// What `measureText` gives: the width, and how far the font reaches above and below.
    func measure(_ text: String) -> [String: Double] {
        let made = line(text, color: nil)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(made, &ascent, &descent, nil)
        let bounds = CTLineGetBoundsWithOptions(made, .useGlyphPathBounds)
        return ["width": width, "fontBoundingBoxAscent": Double(CTFontGetAscent(style.font)),
                "fontBoundingBoxDescent": Double(CTFontGetDescent(style.font)),
                "actualBoundingBoxAscent": Double(bounds.maxY), "actualBoundingBoxDescent": Double(-bounds.minY),
                "actualBoundingBoxLeft": Double(-bounds.minX), "actualBoundingBoxRight": Double(bounds.maxX)]
    }

    /// Pixels, RGBA, top row first, colors not multiplied by alpha: as a page reads a canvas.
    func pixels(x: Int = 0, y: Int = 0, width w: Int? = nil, height h: Int? = nil) -> Data {
        let w = w ?? width, h = h ?? height
        guard let c = context, let base = c.data, w > 0, h > 0 else { return Data(count: max(0, (w ?? 0) * (h ?? 0) * 4)) }
        let row = c.bytesPerRow
        var out = Data(count: w * h * 4)
        out.withUnsafeMutableBytes { raw in
            let o = raw.bindMemory(to: UInt8.self)
            let i = base.assumingMemoryBound(to: UInt8.self)
            for yy in 0..<h {
                let sy = y + yy
                guard sy >= 0, sy < height else { continue }
                for xx in 0..<w {
                    let sx = x + xx
                    guard sx >= 0, sx < width else { continue }
                    let s = sy * row + sx * 4, d = (yy * w + xx) * 4
                    let a = i[s + 3]
                    o[d + 3] = a
                    if a == 0 { continue }
                    if a == 255 { o[d] = i[s]; o[d + 1] = i[s + 1]; o[d + 2] = i[s + 2]; continue }
                    o[d] = UInt8(min(255, (Int(i[s]) * 255 + Int(a) / 2) / Int(a)))
                    o[d + 1] = UInt8(min(255, (Int(i[s + 1]) * 255 + Int(a) / 2) / Int(a)))
                    o[d + 2] = UInt8(min(255, (Int(i[s + 2]) * 255 + Int(a) / 2) / Int(a)))
                }
            }
        }
        return out
    }

    // MARK: Fonts and colors

    /// "bold 32px "Name", sans-serif": the size and the first family there is a font for.
    static func font(from text: String) -> CTFont {
        var size: CGFloat = 10
        if let match = text.range(of: #"([0-9.]+)px"#, options: .regularExpression) {
            size = CGFloat(Double(text[match].dropLast(2)) ?? 10)
        }
        let afterSize = text.range(of: #"[0-9.]+px\s*"#, options: .regularExpression).map { String(text[$0.upperBound...]) } ?? text
        let families = afterSize.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
        let bold = text.contains("bold")
        for family in families where !family.isEmpty {
            if let descriptor = fonts[family] { return CTFontCreateWithFontDescriptor(descriptor, size, nil) }
            let lower = family.lowercased()
            if ["-apple-system", "system-ui", "sans-serif", "blinkmacsystemfont"].contains(lower) {
                return CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
            }
            if lower == "serif" { return CTFontCreateWithName("Times New Roman" as CFString, size, nil) }
            if lower == "monospace" { return CTFontCreateWithName("Menlo" as CFString, size, nil) }
            let made = CTFontCreateWithName(family as CFString, size, nil)
            let madeFamily = (CTFontCopyFamilyName(made) as String).lowercased()
            if madeFamily == lower || (CTFontCopyPostScriptName(made) as String).lowercased() == lower {
                return made
            }
        }
        return CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    /// A color as CSS writes it: "#rgb", "#rrggbb", "rgb(…)", "rgba(…)" or a few names.
    static func color(_ text: String) -> CGColor? {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        func make(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> CGColor? {
            CGColor(colorSpace: space, components: [CGFloat(r / 255), CGFloat(g / 255), CGFloat(b / 255), CGFloat(max(0, min(1, a)))])
        }
        if value.hasPrefix("#") {
            let hex = Array(value.dropFirst())
            func part(_ s: ArraySlice<Character>) -> Double { Double(Int(String(s), radix: 16) ?? 0) }
            if hex.count == 3 { return make(part(hex[0...0]) * 17, part(hex[1...1]) * 17, part(hex[2...2]) * 17, 1) }
            if hex.count >= 6 { return make(part(hex[0...1]), part(hex[2...3]), part(hex[4...5]), hex.count == 8 ? part(hex[6...7]) / 255 : 1) }
            return nil
        }
        if value.hasPrefix("rgb") {
            let inside = value.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }
            let parts = inside.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count >= 3 else { return nil }
            return make(parts[0], parts[1], parts[2], parts.count > 3 ? parts[3] : 1)
        }
        switch value {
        case "white": return make(255, 255, 255, 1)
        case "black": return make(0, 0, 0, 1)
        case "transparent": return make(0, 0, 0, 0)
        case "red": return make(255, 0, 0, 1)
        default: return nil
        }
    }

    // MARK: Gradients

    final class Gradient {
        static var all: [Int: Gradient] = [:]
        static var next = 1
        let points: [CGFloat]   // linear: x0 y0 x1 y1; radial: x0 y0 r0 x1 y1 r1
        var stops: [(offset: CGFloat, color: CGColor)] = []

        init(points: [CGFloat]) { self.points = points }

        static func make(_ points: [CGFloat]) -> Int {
            let id = next
            next += 1
            all[id] = Gradient(points: points)
            return id
        }

        func draw(in c: CGContext) {
            let sorted = stops.sorted { $0.offset < $1.offset }
            guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: sorted.map(\.color) as CFArray,
                                            locations: sorted.map(\.offset)) else { return }
            let options: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            if points.count >= 6 {
                c.drawRadialGradient(gradient, startCenter: CGPoint(x: points[0], y: points[1]), startRadius: points[2],
                                     endCenter: CGPoint(x: points[3], y: points[4]), endRadius: points[5], options: options)
            } else if points.count >= 4 {
                c.drawLinearGradient(gradient, start: CGPoint(x: points[0], y: points[1]), end: CGPoint(x: points[2], y: points[3]), options: options)
            }
        }
    }
}

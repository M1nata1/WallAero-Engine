import AppKit
import CoreText
import CoreVideo
import Foundation
import JavaScriptCore
import Metal
import QuartzCore
import ShaderTranslation

/// A scene of Wallpaper Engine's drawn by the app itself: the scene player — the same script
/// the scene's page runs in Chromium — runs in JavaScriptCore, and what it asks of WebGL is done
/// with Metal (`MetalGL`). No web engine, no second process, no copy of every frame on its way
/// to the screen.
public final class MetalScenePlayer {
    /// What the scene is shown in: the view's layer. The canvas lies in it as a page's canvas
    /// does with `object-fit`, cut or with bars.
    public let layer: CALayer
    /// What the scene is drawn into.
    private let metalLayer: CAMetalLayer
    public private(set) var notes: [String] = []
    /// Frames a second; nought for as many as the screen shows.
    public var frameRate: Int = 30 { didSet { restartClock() } }
    /// Frames a second of the screen the scene is on, for a `frameRate` of nought.
    public var screenRate: Int = 60 { didSet { restartClock() } }
    /// Called when the scene's first frame is on the screen.
    public var onFirstFrame: (() -> Void)?

    private let folder: URL
    private let engineScript: String
    private let context: JSContext
    private let gl: MetalGL
    private let textureCache: CVMetalTextureCache?
    private var canvases: [Int: Canvas2D] = [:]
    private var media: [Int: MediaElement] = [:]
    private var captured: [Int: GLSource] = [:]
    private var nextHandle = 1
    private var timers: [Int: Timer] = [:]
    private var frameWanted = false
    private var clock: Timer?
    private var playing = true
    private let started = CACurrentMediaTime()
    /// The page's size in points, and pixels to a point.
    private var size = CGSize(width: 1, height: 1), scale: CGFloat = 2
    /// How the canvas fills the view: `object-fit` and `object-position` of a page's canvas.
    private var fit = "cover", position = 50.0

    /// The scene's videos as files AVFoundation plays, by the address the scene gives them.
    public var videoFiles: [String: URL] = [:]

    /// Whether a script of the scene listens to the Mac's sound.
    public private(set) var listensToSound = false
    public var onListensToSound: ((Bool) -> Void)?
    /// Whether a script of the scene wants to know what music the Mac plays.
    public private(set) var listensToMedia = false
    public var onListensToMedia: ((Bool) -> Void)?

    /// - Parameters:
    ///   - folder: the scene's folder, where its `engine/files.js` and the files it names are.
    ///   - engineScript: the scene player (`WallpaperEngineRuntime.script`).
    public init?(folder: URL, engineScript: String) {
        guard let device = MTLCreateSystemDefaultDevice(), let gl = MetalGL(device: device), let context = JSContext() else { return nil }
        self.folder = folder
        self.engineScript = engineScript
        self.gl = gl
        self.context = context
        layer = CALayer()
        layer.masksToBounds = true
        layer.isOpaque = true
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .rgba8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.contentsGravity = .resize
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
        layer.addSublayer(metalLayer)
        gl.layer = metalLayer
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        textureCache = cache
        gl.sources = { [weak self] handle in self?.captured.removeValue(forKey: handle) }
        context.exceptionHandler = { [weak self] _, exception in
            let text = exception?.toString() ?? "an error"
            let line = exception?.objectForKeyedSubscript("line")?.toString() ?? "?"
            let stack = exception?.objectForKeyedSubscript("stack")?.toString() ?? ""
            self?.note("script: \(text) at line \(line) \(stack.prefix(400))")
        }
        installNative()
    }

    deinit {
        stop()
    }

    private func note(_ text: String) {
        if notes.count < 200 { notes.append(text) }
    }

    // MARK: Starting and stopping

    /// Plays the scene: its files, its settings by the names the scene has for them, what the
    /// editor changed of it, and how it fills the screen.
    public func start(settings: [String: Any], changes: [String: Any], fit: String, position: Double) {
        self.fit = fit
        self.position = position
        context.evaluateScript(MetalSceneScripts.environment, withSourceURL: URL(string: "wallaero://environment.js"))
        context.evaluateScript(MetalSceneScripts.metalGL, withSourceURL: URL(string: "wallaero://metalgl.js"))
        call("__wallaeroHost.apply", [hostSettings])
        applySize()
        let table = folder.appendingPathComponent("engine/files.js")
        guard let files = try? String(contentsOf: table, encoding: .utf8) else {
            note("no engine/files.js in \(folder.path)")
            return
        }
        context.evaluateScript(files, withSourceURL: table)
        context.evaluateScript(engineScript, withSourceURL: URL(string: "wallaero://engine.js"))
        call("__start", [settings, changes, fit, position])
        restartClock()
    }

    public func stop() {
        clock?.invalidate()
        clock = nil
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        media.values.forEach { $0.call("remove") }
        call("__player.stop")
    }

    /// Pauses and resumes: a paused scene draws nothing and asks for nothing.
    public func setPlaying(_ playing: Bool, rate: Double = 1) {
        self.playing = playing
        host(["playing": playing, "rate": rate])
        media.values.forEach { if $0.kind != .image { $0.call(playing ? "resume" : "suspend") } }
        restartClock()
    }

    /// The wallpaper's sound: every sound of the scene plays at its share of `volume`.
    public func setAudio(muted: Bool, volume: Float) {
        host(["muted": muted, "volume": Double(max(0, min(1, volume)))])
    }

    /// What the app says of the wallpaper's media, kept for a scene not started yet.
    private var hostSettings: [String: Any] = ["playing": true, "rate": 1.0, "muted": true, "volume": 1.0]
    private func host(_ settings: [String: Any]) {
        hostSettings.merge(settings) { $1 }
        call("__wallaeroHost.apply", [settings])
    }

    public func setSettings(_ settings: [String: Any]) {
        call("__player.setProperties", [settings])
        flush()
    }

    /// The size of what the scene is shown in, in points, and pixels to a point.
    public func setViewSize(_ size: CGSize, scale: CGFloat) {
        self.size = size
        self.scale = scale
        applySize()
        placeCanvas()
        call("__dispatchWindow", ["resize", [:] as [String: Any]])
    }

    /// Where the whole canvas is in the view, in points from the top left; parts of it may be
    /// cut off. As the scene player works it out for the pointer (`shownAt`).
    private func canvasFrame(canvas: CGSize) -> CGRect {
        guard canvas.width > 0, canvas.height > 0 else { return CGRect(origin: .zero, size: size) }
        if fit == "fill" { return CGRect(origin: .zero, size: size) }
        let by = fit == "contain" ? min(size.width / canvas.width, size.height / canvas.height)
                                  : max(size.width / canvas.width, size.height / canvas.height)
        let width = canvas.width * by, height = canvas.height * by
        return CGRect(x: (size.width - width) * position / 100, y: (size.height - height) * position / 100, width: width, height: height)
    }

    private func placeCanvas() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame.size = size
        var frame = canvasFrame(canvas: metalLayer.drawableSize)
        // A layer counts from the bottom.
        frame.origin.y = size.height - frame.maxY
        metalLayer.frame = frame
        metalLayer.contentsScale = scale
        CATransaction.commit()
    }

    private func applySize() {
        let object = JSValue(object: ["width": Double(size.width), "height": Double(size.height), "ratio": Double(scale)], in: context)
        context.setObject(object, forKeyedSubscript: "__size" as NSString)
    }

    /// The pointer over the scene, in points from the top left: `kind` is move, down, up or leave.
    public func pointer(_ kind: String, x: Double, y: Double) {
        let name = kind == "leave" ? "pointerleave" : "pointer" + kind
        call("__dispatchWindow", [name, ["clientX": x, "clientY": y, "button": 0, "buttons": kind == "down" ? 1 : 0]])
    }

    /// The spectrum of what the Mac plays, as Wallpaper Engine hands it to scenes.
    public func sound(_ levels: [Float]) {
        call("__wallaeroHost.sound", [levels.map(Double.init)])
    }

    /// Runs a script the app has for pages — the sound's levels, what music plays — in the
    /// scene, as it would run in the scene's page; what it changes is drawn.
    public func perform(_ script: String) {
        context.evaluateScript(script)
    }

    public var report: String {
        context.evaluateScript("window.WallaeroEngine && window.WallaeroEngine.report ? window.WallaeroEngine.report() : ''")?.toString() ?? ""
    }

    public func evaluate(_ script: String) -> String? {
        context.evaluateScript(script)?.toString()
    }


    /// Calls a function of the page's, if there is one by that name — a path of names.
    @discardableResult
    private func call(_ path: String, _ arguments: [Any] = []) -> JSValue? {
        var target: JSValue? = context.globalObject
        var owner: JSValue? = nil
        for name in path.split(separator: ".") {
            owner = target
            target = target?.objectForKeyedSubscript(String(name))
            if target == nil || target!.isUndefined || target!.isNull { return nil }
        }
        guard let function = target, function.isObject else { return nil }
        if let owner, path.contains(".") { return function.invokeMethod("call", withArguments: [owner] + arguments) }
        return function.call(withArguments: arguments)
    }

    // MARK: Frames

    private func restartClock() {
        clock?.invalidate()
        clock = nil
        // A scene paused from the start still draws until it has shown itself.
        guard playing || !hasShownItself else { return }
        let rate = frameRate > 0 ? Double(frameRate) : Double(max(30, screenRate))
        let timer = Timer(timeInterval: 1 / rate, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    /// A frame: only if the player asked for one; a scene in which nothing moves costs nothing.
    private func tick() {
        if !playing, hasShownItself {
            restartClock()
            return
        }
        guard frameWanted else { return }
        frameWanted = false
        let now = (CACurrentMediaTime() - started) * 1000
        call("__frame", [now])
        gl.present()
        if gl.framesShown == 1 { onFirstFrame?() }
    }

    /// Whether the scene has been on the screen a while: long enough for its pictures to come.
    private var hasShownItself: Bool {
        gl.framesShown > 0 && CACurrentMediaTime() - started > 1.5
    }

    private func flush() {
        call("__flushAll")
    }

    /// A picture of what the view shows now. A scene in which nothing moves is not drawn again
    /// for it: the screen keeps its last frame, and that is what is taken.
    public func snapshot() -> CGImage? {
        if frameWanted { tick() }
        gl.finish()
        guard let screen = gl.shown else { return nil }
        let width = screen.width, height = screen.height
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: screen.pixelFormat, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        guard let copy = gl.device.makeTexture(descriptor: descriptor), let commands = gl.queue.makeCommandBuffer(),
              let blit = commands.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: screen, to: copy)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        copy.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        // The screen's picture has its rows from the top, as a CGImage has.
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let picture = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        // Placed in the view as the screen shows it.
        let viewWidth = Int((size.width * scale).rounded()), viewHeight = Int((size.height * scale).rounded())
        guard let shown = CGContext(data: nil, width: viewWidth, height: viewHeight, bitsPerComponent: 8, bytesPerRow: viewWidth * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return picture }
        shown.setFillColor(CGColor(gray: 0, alpha: 1))
        shown.fill(CGRect(x: 0, y: 0, width: viewWidth, height: viewHeight))
        shown.interpolationQuality = .high
        let frame = canvasFrame(canvas: CGSize(width: width, height: height))
        shown.draw(picture, in: CGRect(x: frame.minX * scale, y: (size.height - frame.maxY) * scale, width: frame.width * scale, height: frame.height * scale))
        return shown.makeImage() ?? picture
    }

    // MARK: The page's side

    private func installNative() {
        let native = JSValue(newObjectIn: context)!
        func define(_ name: String, _ block: Any) {
            native.setObject(block, forKeyedSubscript: name as NSString)
        }
        let contextRef = context.jsGlobalContextRef!

        // WebGL
        let run: @convention(block) (JSValue, Int, JSValue) -> Void = { [weak self] stream, length, payloads in
            guard let self else { return }
            guard let pointer = Self.bytes(of: stream, in: contextRef) else { return }
            let doubles = UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: Double.self), count: length)
            self.gl.run(doubles) { index in
                guard let value = payloads.atIndex(index), let raw = Self.bytes(of: value, in: contextRef) else { return nil }
                return Data(bytes: raw, count: Self.byteLength(of: value, in: contextRef))
            }
        }
        define("run", run)
        let link: @convention(block) (Int, String, String, JSValue) -> [String: Any] = { [weak self] id, vertex, fragment, attributes in
            guard let self else { return ["ok": false, "error": "gone"] }
            var bound: [String: Int] = [:]
            for (name, value) in (attributes.toDictionary() as? [String: NSNumber]) ?? [:] { bound[name] = value.intValue }
            let (program, error) = self.gl.link(id: id, vertex: vertex, fragment: fragment, attributes: bound)
            guard let program else {
                let said = Self.browserMessages(error ?? "", vertex: vertex, fragment: fragment)
                self.note("a shader does not translate: \(said.prefix(300))")
                return ["ok": false, "error": said]
            }
            return ["ok": true,
                    "uniforms": program.activeUniforms.map { ["name": $0.name, "type": $0.type, "size": $0.size] },
                    "names": program.uniformNames]
        }
        define("link", link)
        let checkShader: @convention(block) (Bool, String) -> String = { fragment, source in
            let log = ShaderCache.answer(["check", fragment ? "fragment" : "vertex", source]) {
                guard let log = shader_check(fragment ? 1 : 0, source) else { return "" }
                defer { free(log) }
                return String(cString: log)
            } ?? ""
            return log.isEmpty ? "" : Self.browserMessages(log, vertex: "", fragment: source)
        }
        define("checkShader", checkShader)
        let atob: @convention(block) (String) -> String = { text in
            guard let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return "" }
            return String(data: data, encoding: .isoLatin1) ?? ""
        }
        define("atob", atob)
        let capture: @convention(block) (JSValue) -> Int = { [weak self] element in
            guard let self, let handle = element.objectForKeyedSubscript("__handle")?.toNumber()?.intValue else { return 0 }
            let source: GLSource?
            if let canvas = self.canvases[handle] {
                source = .pixels(canvas.pixels(), width: canvas.width, height: canvas.height)
            } else if let item = self.media[handle] {
                switch item.kind {
                case .image: source = item.pixels.map { GLSource.pixels($0, width: item.pictureSize.0, height: item.pictureSize.1) }
                case .video: source = self.textureCache.flatMap(item.frame(cache:)).map(GLSource.texture)
                case .audio: source = nil
                }
            } else {
                source = nil
            }
            guard let source else { return 0 }
            let id = self.nextHandle
            self.nextHandle += 1
            self.captured[id] = source
            return id
        }
        define("capture", capture)
        let readPixels: @convention(block) (Int, Int, Int, Int) -> JSValue = { [weak self] x, y, width, height in
            guard let self else { return JSValue(nullIn: JSContext.current()) }
            let data = self.gl.readPixels(x: x, y: y, width: width, height: height)
            return Self.typedArray(data, kind: kJSTypedArrayTypeUint8Array, in: self.context)
        }
        define("readPixels", readPixels)
        let setCanvasSize: @convention(block) (Int, Int) -> Void = { [weak self] width, height in
            self?.metalLayer.drawableSize = CGSize(width: max(1, width), height: max(1, height))
            self?.placeCanvas()
        }
        define("setCanvasSize", setCanvasSize)

        // 2D canvases
        let canvasMake: @convention(block) (Int, Int) -> Int = { [weak self] width, height in
            guard let self else { return 0 }
            let id = self.nextHandle
            self.nextHandle += 1
            self.canvases[id] = Canvas2D(width: width, height: height)
            return id
        }
        define("canvasMake", canvasMake)
        let canvasResize: @convention(block) (Int, Int, Int) -> Void = { [weak self] handle, width, height in
            self?.canvases[handle]?.resize(width: width, height: height)
        }
        define("canvasResize", canvasResize)
        let canvasSet: @convention(block) (Int, String, JSValue) -> Void = { [weak self] handle, name, value in
            self?.canvases[handle]?.set(name, value.toObject())
        }
        define("canvasSet", canvasSet)
        let canvasCall: @convention(block) (Int, String, JSValue) -> Void = { [weak self] handle, name, arguments in
            self?.canvases[handle]?.call(name, (arguments.toArray() ?? []) as [Any])
        }
        define("canvasCall", canvasCall)
        let canvasMeasure: @convention(block) (Int, String) -> [String: Double] = { [weak self] handle, text in
            self?.canvases[handle]?.measure(text) ?? ["width": 0]
        }
        define("canvasMeasure", canvasMeasure)
        let canvasRead: @convention(block) (Int, Int, Int, Int, Int) -> JSValue = { [weak self] handle, x, y, width, height in
            guard let self, let canvas = self.canvases[handle] else { return JSValue(nullIn: JSContext.current()) }
            return Self.typedArray(canvas.pixels(x: x, y: y, width: width, height: height), kind: kJSTypedArrayTypeUint8ClampedArray, in: self.context)
        }
        define("canvasRead", canvasRead)
        let gradientMake: @convention(block) (JSValue) -> Int = { points in
            Canvas2D.Gradient.make(((points.toArray() as? [NSNumber]) ?? []).map { CGFloat($0.doubleValue) })
        }
        define("gradientMake", gradientMake)
        let gradientStop: @convention(block) (Int, Double, String) -> Void = { id, offset, color in
            if let parsed = Canvas2D.color(color) { Canvas2D.Gradient.all[id]?.stops.append((CGFloat(offset), parsed)) }
        }
        define("gradientStop", gradientStop)

        // Media
        let mediaMake: @convention(block) (String) -> Int = { [weak self] kind in
            guard let self else { return 0 }
            let id = self.nextHandle
            self.nextHandle += 1
            let element = MediaElement(kind: MediaElement.Kind(rawValue: kind) ?? .image, handle: id, folder: self.folder)
            element.videoFiles = self.videoFiles
            if !self.playing { element.call("suspend") }
            element.event = { [weak self] type in
                self?.call("__mediaEvent", [id, type])
            }
            self.media[id] = element
            return id
        }
        define("mediaMake", mediaMake)
        let mediaSet: @convention(block) (Int, String, JSValue) -> Void = { [weak self] handle, name, value in
            self?.media[handle]?.set(name, value.toObject())
        }
        define("mediaSet", mediaSet)
        let mediaGet: @convention(block) (Int, String) -> Any = { [weak self] handle, name in
            self?.media[handle]?.get(name) ?? NSNull()
        }
        define("mediaGet", mediaGet)
        let mediaCall: @convention(block) (Int, String) -> Void = { [weak self] handle, name in
            self?.media[handle]?.call(name)
            if name == "remove" { self?.media[handle] = nil }
        }
        define("mediaCall", mediaCall)
        let fontLoad: @convention(block) (String, String) -> Bool = { [weak self] family, path in
            guard let self else { return false }
            let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : self.folder.appendingPathComponent(path)
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  let first = descriptors.first else { return false }
            Canvas2D.fonts[family] = first
            return true
        }
        define("fontLoad", fontLoad)

        // Time
        let timer: @convention(block) (Int, Double, Bool) -> Void = { [weak self] id, delay, repeats in
            guard let self else { return }
            let made = Timer(timeInterval: max(0.001, delay / 1000), repeats: repeats) { [weak self] fired in
                guard let self else { return }
                if !repeats { self.timers[id] = nil }
                self.call("__timer", [id])
                if !repeats { fired.invalidate() }
            }
            RunLoop.main.add(made, forMode: .common)
            self.timers[id] = made
        }
        define("timer", timer)
        let cancelTimer: @convention(block) (Int) -> Void = { [weak self] id in
            self?.timers.removeValue(forKey: id)?.invalidate()
        }
        define("cancelTimer", cancelTimer)
        let wantFrame: @convention(block) () -> Void = { [weak self] in self?.frameWanted = true }
        define("wantFrame", wantFrame)
        let now: @convention(block) () -> Double = { [weak self] in ((CACurrentMediaTime() - (self?.started ?? 0)) * 1000) }
        define("now", now)
        let log: @convention(block) (String, String) -> Void = { [weak self] level, text in
            if level == "error" || level == "warn" { self?.note("\(level): \(text.prefix(300))") }
        }
        define("log", log)
        let listens: @convention(block) (Bool) -> Void = { [weak self] on in
            guard let self, self.listensToSound != on else { return }
            self.listensToSound = on
            self.onListensToSound?(on)
        }
        define("listensToSound", listens)
        let listensToMedia: @convention(block) (Bool) -> Void = { [weak self] on in
            guard let self, self.listensToMedia != on else { return }
            self.listensToMedia = on
            self.onListensToMedia?(on)
        }
        define("listensToMedia", listensToMedia)
        context.setObject(native, forKeyedSubscript: "__native" as NSString)
    }

    // MARK: What the compiler says

    /// glslang's messages in the words browsers use, which the scene player knows how to mend
    /// shaders by: the same complaints, said a little differently.
    static func browserMessages(_ log: String, vertex: String, fragment: String) -> String {
        var lines: [String] = []
        let all = log.components(separatedBy: "\n")
        var index = 0
        while index < all.count {
            var line = all[index].replacingOccurrences(of: "' :  ", with: "' : ")
            line = line.replacingOccurrences(of: "wrong operand types: no operation", with: "wrong operand types - no operation")
            if let match = line.range(of: #"l-value required "(\w+)" \(can't modify shader input\)"#, options: .regularExpression) {
                let name = line[match].split(separator: "\"")[1]
                line.replaceSubrange(match, with: "l-value required (can't modify an input \"\(name)\")")
            }
            // "Types must match:" and the two declarations on the lines after it.
            if line.contains("Types must match"), index + 1 < all.count {
                let declared = all[index + 1]
                // A setting: "name: " uniform …" in stage vertex versus …".
                if let named = declared.range(of: #"^\s*(\w+):\s*""#, options: .regularExpression) {
                    let name = declared[named].trimmingCharacters(in: CharacterSet(charactersIn: " :\"\t"))
                    let kind = declared.contains(" uniform ") ? "uniform" : "varying"
                    line = "ERROR: Types of \(kind) '\(name)' differ between VERTEX and FRAGMENT shaders"
                } else if let quote = declared.range(of: #"" [^"]*""#, options: .regularExpression) {
                    let words = declared[quote].trimmingCharacters(in: CharacterSet(charactersIn: "\" ")).split(separator: " ")
                    if let name = words.last {
                        let isUniform = (vertex + fragment).range(of: #"uniform\s+(\w+\s+)*\w+\s+"# + name + #"\b"#, options: .regularExpression) != nil
                        line = "ERROR: Types of \(isUniform ? "uniform" : "varying") '\(name)' differ between VERTEX and FRAGMENT shaders"
                    }
                }
            }
            lines.append(line)
            index += 1
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Typed arrays

    /// Where a typed array's bytes are: nil for anything else. Arrays made by `metalgl.js` start
    /// at the beginning of their buffers.
    static func bytes(of value: JSValue, in context: JSContextRef) -> UnsafeMutableRawPointer? {
        guard let object = JSValueToObject(context, value.jsValueRef, nil) else { return nil }
        guard JSValueGetTypedArrayType(context, value.jsValueRef, nil) != kJSTypedArrayTypeNone else { return nil }
        guard let base = JSObjectGetTypedArrayBytesPtr(context, object, nil) else { return nil }
        return base + JSObjectGetTypedArrayByteOffset(context, object, nil)
    }

    static func byteLength(of value: JSValue, in context: JSContextRef) -> Int {
        guard let object = JSValueToObject(context, value.jsValueRef, nil) else { return 0 }
        return JSObjectGetTypedArrayByteLength(context, object, nil)
    }

    static func typedArray(_ data: Data, kind: JSTypedArrayType, in context: JSContext) -> JSValue {
        let length = data.count
        let memory = malloc(max(1, length))!
        data.withUnsafeBytes { if length > 0 { memory.copyMemory(from: $0.baseAddress!, byteCount: length) } }
        let made = JSObjectMakeTypedArrayWithBytesNoCopy(context.jsGlobalContextRef, kind, memory, length, { bytes, _ in free(bytes) }, nil, nil)
        return JSValue(jsValueRef: made, in: context)
    }
}

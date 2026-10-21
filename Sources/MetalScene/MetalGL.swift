import Foundation
import Metal
import QuartzCore
import ShaderTranslation

/// WebGL 2 as the scene player uses it, done with Metal: the player's calls come as a stream of
/// numbers (see `metalgl.js`), one stream a frame, and are carried out here in order, with the
/// state WebGL keeps — what is bound where, how colors blend — kept the way WebGL keeps it.
///
/// Pictures are kept in memory the way WebGL keeps them, bottom row first: the vertex shaders
/// are made to turn what they draw over (SPIRV-Cross's `flip_vert_y`), so that drawing, copying
/// and reading a picture go by the same rows in both. Only the screen has its rows the other way.
final class MetalGL {
    let device: MTLDevice
    let queue: MTLCommandQueue
    /// The screen: what is drawn to framebuffer 0.
    var layer: CAMetalLayer?
    /// Other screens that show the same frame: each gets a copy of it, drawn once.
    var mirrors: [CAMetalLayer] = []
    /// Frames copied to other screens so far.
    private(set) var mirroredFrames = 0
    /// What the screen shows now: the last frame given to it.
    private(set) var shown: MTLTexture?

    // MARK: Objects

    final class Buffer { var data = Data(); var metal: MTLBuffer? }
    struct Attribute { var buffer = 0; var size = 4; var type = GLConstant.float; var normalized = false; var stride = 0; var offset = 0; var divisor = 0; var enabled = false }
    final class VertexArray { var attributes: [Int: Attribute] = [:]; var elements = 0 }
    final class Texture {
        var metal: MTLTexture?
        var width = 0, height = 0
        var format: MTLPixelFormat = .rgba8Unorm
        var wrapS = GLConstant.repeat, wrapT = GLConstant.repeat, mag = GLConstant.linear, min = GLConstant.linear
    }
    /// What a program's pipeline is made for: the target, the blending and the vertex layout.
    struct PipelineKey: Hashable {
        var format: UInt, depth: Bool, blendOn: Bool, blend: [Int], inputs: [Int]
    }
    final class Framebuffer { var color: (renderbuffer: Bool, id: Int)?; var depth: Int? }
    final class Program {
        let translated: TranslatedProgram
        /// Attribute name → the index WebGL bound it to.
        var attributes: [String: Int] = [:]
        var block: Data
        var samplerUnits: [String: Int] = [:]
        var pipelines: [PipelineKey: MTLRenderPipelineState] = [:]
        init(translated: TranslatedProgram) {
            self.translated = translated
            block = Data(count: translated.blockSize)
        }
    }
    struct SamplerParameters: Hashable { var wrapS = GLConstant.repeat, wrapT = GLConstant.repeat, mag = GLConstant.linear, min = GLConstant.linear }

    private var buffers: [Int: Buffer] = [:], arrays: [Int: VertexArray] = [0: VertexArray()], textures: [Int: Texture] = [:]
    private var renderbuffers: [Int: Texture] = [:], framebuffers: [Int: Framebuffer] = [:]
    private(set) var programs: [Int: Program] = [:]
    private var samplers: [Int: SamplerParameters] = [:]

    // MARK: WebGL's state

    private var unit = 0
    private var unitTextures: [Int: Int] = [:], unitSamplers: [Int: Int] = [:]
    private var program = 0, vertexArray = 0, arrayBuffer = 0, renderbuffer = 0
    private var drawFB = 0, readFB = 0
    private var viewport = (0, 0, 1, 1)
    private var blendOn = false, blendFunc = (1, 0, 1, 0), blendEquation = GLConstant.funcAdd
    private var depthOn = false, depthMask = true, depthFunc = 0x201, cullOn = false, frontCCW = true, cullMode = 0x0405
    private var clearColor: [Double] = [0, 0, 0, 0]
    private var flipY = false, premultiply = false

    // MARK: Metal's state

    private var commandBuffer: MTLCommandBuffer?
    private var encoder: MTLRenderCommandEncoder?
    private var encoderFB = -1
    private var pendingClear: [Int: (color: [Double]?, depth: Bool)] = [:]
    private var drawable: CAMetalDrawable?
    private var screenTexture: MTLTexture?
    private var samplerStates: [SamplerParameters: MTLSamplerState] = [:]
    private var depthStates: [Int: MTLDepthStencilState] = [:]
    private let white: MTLTexture
    private var blitPipelines: [MTLPixelFormat: MTLRenderPipelineState] = [:]
    private let blitVertex: MTLFunction, blitFragment: MTLFunction
    /// Pictures and frames of videos to upload, by the handle the page knows them by.
    var sources: (Int) -> GLSource? = { _ in nil }
    /// How many frames were shown.
    private(set) var framesShown = 0

    init?(device: MTLDevice) {
        guard let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        guard let white = device.makeTexture(descriptor: descriptor) else { return nil }
        var pixel: [UInt8] = [255, 255, 255, 255]
        white.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &pixel, bytesPerRow: 4)
        self.white = white
        guard let library = try? device.makeLibrary(source: Self.blitSource, options: nil),
              let vertex = library.makeFunction(name: "blitVertex"), let fragment = library.makeFunction(name: "blitFragment")
        else {
            return nil
        }
        blitVertex = vertex
        blitFragment = fragment
    }

    /// A picture copied from one place to another, scaled or turned over on the way.
    private static let blitSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct Out { float4 position [[position]]; float2 uv; };
    struct Rects { float4 src; float4 dst; float2 srcSize; float2 pad; };
    vertex Out blitVertex(uint id [[vertex_id]], constant Rects& r [[buffer(0)]]) {
      float2 corner = float2(id & 1, id >> 1);
      Out out;
      out.position = float4(mix(r.dst.xy, r.dst.zw, corner), 0, 1);
      out.uv = mix(r.src.xy, r.src.zw, corner) / r.srcSize;
      return out;
    }
    fragment float4 blitFragment(Out in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]]) {
      return t.sample(s, in.uv);
    }
    """

    // MARK: Programs

    /// Makes a program of the two shaders; nil and the reason if it cannot be made.
    func link(id: Int, vertex: String, fragment: String, attributes: [String: Int]) -> (TranslatedProgram?, String?) {
        let (translated, error) = TranslatedProgram.make(device: device, vertex: vertex, fragment: fragment)
        guard let translated else { return (nil, error) }
        let made = Program(translated: translated)
        made.attributes = attributes
        programs[id] = made
        return (translated, nil)
    }

    // MARK: The stream

    /// Carries out a stream of commands: each its operation, then its numbers. `payloads` holds
    /// what a command hands over besides numbers: bytes, by index.
    func run(_ stream: UnsafeBufferPointer<Double>, payload: (Int) -> Data?) {
        var at = 0
        func next() -> Double {
            defer { at += 1 }
            return at < stream.count ? stream[at] : 0
        }
        func int() -> Int { Int(next()) }
        while at < stream.count {
            let op = int()
            switch op {
            case GLOp.bindFramebuffer:
                let target = int(), fb = int()
                if target == GLConstant.framebuffer || target == GLConstant.drawFramebuffer { drawFB = fb }
                if target == GLConstant.framebuffer || target == GLConstant.readFramebuffer { readFB = fb }
            case GLOp.bindVertexArray: vertexArray = int()
            case GLOp.bindTexture: _ = int(); unitTextures[unit] = int()
            case GLOp.activeTexture: unit = int() - GLConstant.texture0
            case GLOp.viewport: viewport = (int(), int(), int(), int())
            case GLOp.enable, GLOp.disable:
                let on = op == GLOp.enable, cap = int()
                switch cap { case GLConstant.blend: blendOn = on; case GLConstant.depthTest: depthOn = on; case GLConstant.cullFace: cullOn = on; default: break }
            case GLOp.bindBuffer:
                let target = int(), id = int()
                if target == GLConstant.arrayBuffer { arrayBuffer = id } else if target == GLConstant.elementArrayBuffer { array.elements = id }
            case GLOp.vertexAttribPointer:
                let index = int()
                var attribute = array.attributes[index] ?? Attribute()
                attribute.buffer = arrayBuffer
                attribute.size = int(); attribute.type = int(); attribute.normalized = int() != 0; attribute.stride = int(); attribute.offset = int()
                array.attributes[index] = attribute
            case GLOp.enableVertexAttribArray: array.attributes[int(), default: Attribute()].enabled = true
            case GLOp.disableVertexAttribArray: array.attributes[int()]?.enabled = false
            case GLOp.vertexAttribDivisor: let index = int(); array.attributes[index, default: Attribute()].divisor = int()
            case GLOp.useProgram: program = int()
            case GLOp.uniform, GLOp.uniformInteger:
                let location = int(), count = int()
                var values: [Double] = []
                for _ in 0..<count { values.append(next()) }
                setUniform(location, values, integer: op == GLOp.uniformInteger)
            case GLOp.uniformPayload:
                let location = int(), index = int()
                let data = payload(index) ?? Data()
                let values = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)).map(Double.init) }
                setUniform(location, values, integer: false)
            case GLOp.blendFuncSeparate: blendFunc = (int(), int(), int(), int())
            case GLOp.blendFunc: let s = int(), d = int(); blendFunc = (s, d, s, d)
            case GLOp.blendEquation: blendEquation = int()
            case GLOp.bufferData, GLOp.bufferSubData:
                let target = int()
                let offset = op == GLOp.bufferSubData ? int() : 0
                let index = int(), size = int()
                let id = target == GLConstant.elementArrayBuffer ? array.elements : arrayBuffer
                let buffer = buffers[id] ?? { let made = Buffer(); buffers[id] = made; return made }()
                let bytes = index >= 0 ? (payload(index) ?? Data()) : Data(count: max(0, size))
                if op == GLOp.bufferData {
                    buffer.data = bytes
                } else {
                    if buffer.data.count < offset + bytes.count { buffer.data.append(Data(count: offset + bytes.count - buffer.data.count)) }
                    buffer.data.replaceSubrange(offset..<(offset + bytes.count), with: bytes)
                }
                // A new buffer each time: what was drawn from the old one in this frame keeps it.
                buffer.metal = buffer.data.isEmpty ? nil : buffer.data.withUnsafeBytes {
                    device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
                }
            case GLOp.drawArrays: draw(mode: int(), first: int(), count: int(), instances: 1, indexType: nil, indexOffset: 0)
            case GLOp.drawElements: draw(mode: int(), first: 0, count: int(), instances: 1, indexType: int(), indexOffset: int())
            case GLOp.drawArraysInstanced: draw(mode: int(), first: int(), count: int(), instances: int(), indexType: nil, indexOffset: 0)
            case GLOp.texParameteri:
                _ = int()
                let name = int(), value = int()
                // Set before the texture has a picture as often as after: it is made here then.
                if unitTextures[unit] ?? 0 != 0 {
                    let texture = currentTexture
                    switch name {
                    case GLConstant.wrapS: texture.wrapS = value
                    case GLConstant.wrapT: texture.wrapT = value
                    case GLConstant.magFilter: texture.mag = value
                    case GLConstant.minFilter: texture.min = value
                    default: break
                    }
                }
            case GLOp.samplerParameteri:
                let id = int(), name = int(), value = int()
                var parameters = samplers[id] ?? SamplerParameters()
                switch name {
                case GLConstant.wrapS: parameters.wrapS = value
                case GLConstant.wrapT: parameters.wrapT = value
                case GLConstant.magFilter: parameters.mag = value
                case GLConstant.minFilter: parameters.min = value
                default: break
                }
                samplers[id] = parameters
            case GLOp.bindSampler: let index = int(), id = int(); unitSamplers[index] = id == 0 ? nil : id
            case GLOp.texImage2D:
                _ = int(); _ = int()
                let internalFormat = int(), width = int(), height = int(), format = int(), type = int(), index = int()
                texImage(internalFormat: internalFormat, format: format, type: type, width: width, height: height, pixels: index >= 0 ? payload(index) : nil)
            case GLOp.texImageSource:
                _ = int(); _ = int()
                let internalFormat = int(), format = int(), type = int(), handle = int()
                texImageSource(internalFormat: internalFormat, format: format, type: type, handle: handle)
            case GLOp.pixelStorei:
                let name = int(), value = int()
                if name == GLConstant.unpackFlipY { flipY = value != 0 }
                if name == GLConstant.unpackPremultiply { premultiply = value != 0 }
            case GLOp.blitFramebuffer:
                var numbers: [Int] = []
                for _ in 0..<10 { numbers.append(int()) }
                blit(numbers)
            case GLOp.clear:
                let mask = int()
                if encoderFB == drawFB { endEncoder() }
                pendingClear[drawFB] = (mask & GLConstant.colorBufferBit != 0 ? clearColor : pendingClear[drawFB]?.color, mask & GLConstant.depthBufferBit != 0)
            case GLOp.clearColor: clearColor = [next(), next(), next(), next()]
            case GLOp.depthMask: depthMask = int() != 0
            case GLOp.depthFunc: depthFunc = int()
            case GLOp.frontFace: frontCCW = int() == GLConstant.ccw
            case GLOp.cullFace: cullMode = int()
            case GLOp.framebufferTexture2D:
                let target = int(), attachment = int()
                _ = int()
                let texture = int()
                _ = int()
                let fb = target == GLConstant.readFramebuffer ? readFB : drawFB
                let framebuffer = framebuffers[fb] ?? { let made = Framebuffer(); framebuffers[fb] = made; return made }()
                if attachment == GLConstant.colorAttachment0 { framebuffer.color = (false, texture) }
            case GLOp.framebufferRenderbuffer:
                let target = int(), attachment = int()
                _ = int()
                let id = int()
                let fb = target == GLConstant.readFramebuffer ? readFB : drawFB
                let framebuffer = framebuffers[fb] ?? { let made = Framebuffer(); framebuffers[fb] = made; return made }()
                if attachment == GLConstant.depthAttachment { framebuffer.depth = id } else { framebuffer.color = (true, id) }
            case GLOp.bindRenderbuffer: _ = int(); renderbuffer = int()
            case GLOp.renderbufferStorage:
                _ = int()
                let internalFormat = int(), width = int(), height = int()
                let made = renderbuffers[renderbuffer] ?? Texture()
                renderbuffers[renderbuffer] = made
                allocate(made, width: width, height: height, format: pixelFormat(internalFormat: internalFormat, type: 0))
            case GLOp.generateMipmap: _ = int(); generateMipmap()
            case GLOp.delete:
                let kind = int(), id = int()
                switch kind {
                case 1: textures[id] = nil
                case 2: buffers[id] = nil
                case 3: framebuffers[id] = nil
                case 4: renderbuffers[id] = nil
                case 5: programs[id] = nil
                case 6: arrays[id] = nil
                case 7: samplers[id] = nil
                default: break
                }
            default:
                // Unknown: nothing after it can be read rightly.
                return
            }
        }
    }

    private var array: VertexArray {
        if let made = arrays[vertexArray] { return made }
        let made = VertexArray()
        arrays[vertexArray] = made
        return made
    }

    // MARK: Passes

    private func ensureCommandBuffer() -> MTLCommandBuffer {
        if let commandBuffer { return commandBuffer }
        let made = queue.makeCommandBuffer()!
        commandBuffer = made
        return made
    }

    func endEncoder() {
        encoder?.endEncoding()
        encoder = nil
        encoderFB = -1
    }

    private func colorTexture(of fb: Int) -> MTLTexture? {
        if fb == 0 {
            if screenTexture == nil, let layer {
                drawable = layer.nextDrawable()
                screenTexture = drawable?.texture
            }
            return screenTexture
        }
        guard let attachment = framebuffers[fb]?.color else { return nil }
        return attachment.renderbuffer ? renderbuffers[attachment.id]?.metal : textures[attachment.id]?.metal
    }

    private func depthTexture(of fb: Int) -> MTLTexture? {
        guard fb != 0, let id = framebuffers[fb]?.depth else { return nil }
        return renderbuffers[id]?.metal
    }

    private func beginPass(_ fb: Int) -> MTLRenderCommandEncoder? {
        if let encoder, encoderFB == fb { return encoder }
        endEncoder()
        guard let color = colorTexture(of: fb) else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].storeAction = .store
        if let clear = pendingClear[fb], let c = clear.color {
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: c[0], green: c[1], blue: c[2], alpha: c[3])
        } else {
            pass.colorAttachments[0].loadAction = .load
        }
        if let depth = depthTexture(of: fb) {
            pass.depthAttachment.texture = depth
            pass.depthAttachment.loadAction = pendingClear[fb]?.depth == true ? .clear : .load
            pass.depthAttachment.clearDepth = 1
            pass.depthAttachment.storeAction = .store
        }
        pendingClear[fb] = nil
        let made = ensureCommandBuffer().makeRenderCommandEncoder(descriptor: pass)
        encoder = made
        encoderFB = fb
        return made
    }

    private func flushClear(_ fb: Int) {
        if pendingClear[fb] != nil {
            _ = beginPass(fb)
            endEncoder()
        }
    }

    // MARK: Textures

    private func pixelFormat(internalFormat: Int, type: Int) -> MTLPixelFormat {
        switch internalFormat {
        case 0x8229, 0x1903: return .r8Unorm
        case 0x822B, 0x8227: return .rg8Unorm
        case 0x881A: return .rgba16Float
        case 0x8814: return .rgba32Float
        case 0x81A5, 0x81A6, 0x1902: return .depth32Float
        default: return type == GLConstant.halfFloat ? .rgba16Float : .rgba8Unorm
        }
    }

    private func allocate(_ texture: Texture, width: Int, height: Int, format: MTLPixelFormat, mipmapped: Bool = false) {
        texture.width = max(1, width)
        texture.height = max(1, height)
        texture.format = format
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: texture.width, height: texture.height, mipmapped: mipmapped)
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private
        texture.metal = device.makeTexture(descriptor: descriptor)
    }

    private var currentTexture: Texture {
        let id = unitTextures[unit] ?? 0
        if let made = textures[id] { return made }
        let made = Texture()
        textures[id] = made
        return made
    }

    private func texImage(internalFormat: Int, format: Int, type: Int, width: Int, height: Int, pixels: Data?) {
        let texture = currentTexture
        let metalFormat = pixelFormat(internalFormat: internalFormat, type: type)
        if texture.metal == nil || texture.width != width || texture.height != height || texture.format != metalFormat {
            allocate(texture, width: width, height: height, format: metalFormat)
        }
        guard let pixels else { return }
        let bytesPerPixel = metalFormat == .r8Unorm ? 1 : (metalFormat == .rg8Unorm ? 2 : (metalFormat == .rgba16Float ? 8 : 4))
        upload(texture, pixels: pixels, width: width, height: height, bytesPerPixel: bytesPerPixel)
    }

    private func texImageSource(internalFormat: Int, format: Int, type: Int, handle: Int) {
        guard let source = sources(handle) else { return }
        let texture = currentTexture
        switch source {
        case .pixels(let rgba, let width, let height):
            let metalFormat = pixelFormat(internalFormat: internalFormat, type: type)
            if texture.metal == nil || texture.width != width || texture.height != height || texture.format != metalFormat {
                allocate(texture, width: width, height: height, format: metalFormat)
            }
            if metalFormat == .r8Unorm || metalFormat == .rg8Unorm {
                // The source comes as RGBA; a texture of fewer channels takes the first of them.
                let channels = metalFormat == .r8Unorm ? 1 : 2
                var narrow = Data(count: width * height * channels)
                narrow.withUnsafeMutableBytes { out in
                    rgba.withUnsafeBytes { input in
                        let o = out.bindMemory(to: UInt8.self), i = input.bindMemory(to: UInt8.self)
                        for p in 0..<(width * height) where p * 4 + channels <= i.count {
                            for c in 0..<channels { o[p * channels + c] = i[p * 4 + c] }
                        }
                    }
                }
                upload(texture, pixels: narrow, width: width, height: height, bytesPerPixel: channels)
            } else {
                upload(texture, pixels: rgba, width: width, height: height, bytesPerPixel: 4)
            }
        case .texture(let frame):
            // A frame of a video, already on the graphics chip: copied as it is.
            if texture.metal == nil || texture.width != frame.width || texture.height != frame.height || texture.format != frame.pixelFormat {
                allocate(texture, width: frame.width, height: frame.height, format: frame.pixelFormat)
            }
            guard let target = texture.metal else { return }
            endEncoder()
            let blit = ensureCommandBuffer().makeBlitCommandEncoder()!
            if flipY {
                blit.endEncoding()
                drawQuad(source: frame, into: target, sourceRect: (0, frame.height, frame.width, 0), targetRect: (0, 0, frame.width, frame.height), smooth: false)
            } else {
                blit.copy(from: frame, to: target)
                blit.endEncoding()
            }
        }
    }

    private func upload(_ texture: Texture, pixels: Data, width: Int, height: Int, bytesPerPixel: Int) {
        guard let target = texture.metal, width > 0, height > 0, pixels.count >= width * height * bytesPerPixel else { return }
        var rows = pixels
        if flipY || (premultiply && bytesPerPixel == 4) {
            rows = Data(count: width * height * bytesPerPixel)
            let flip = flipY, premultiplied = premultiply && bytesPerPixel == 4
            rows.withUnsafeMutableBytes { out in
                pixels.withUnsafeBytes { input in
                    let o = out.bindMemory(to: UInt8.self), i = input.bindMemory(to: UInt8.self)
                    let rowBytes = width * bytesPerPixel
                    for y in 0..<height {
                        let from = (flip ? height - 1 - y : y) * rowBytes, to = y * rowBytes
                        for x in 0..<rowBytes { o[to + x] = i[from + x] }
                        if premultiplied {
                            for x in 0..<width {
                                let p = to + x * 4, a = UInt16(o[p + 3])
                                o[p] = UInt8(UInt16(o[p]) * a / 255)
                                o[p + 1] = UInt8(UInt16(o[p + 1]) * a / 255)
                                o[p + 2] = UInt8(UInt16(o[p + 2]) * a / 255)
                            }
                        }
                    }
                }
            }
        }
        // Through a shared staging texture, since the target is private.
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.format, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        guard let staging = device.makeTexture(descriptor: descriptor) else { return }
        rows.withUnsafeBytes {
            staging.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: width * bytesPerPixel)
        }
        endEncoder()
        let blit = ensureCommandBuffer().makeBlitCommandEncoder()!
        blit.copy(from: staging, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: target, destinationSlice: 0,
                  destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
    }

    private func generateMipmap() {
        let texture = currentTexture
        guard let current = texture.metal else { return }
        endEncoder()
        if current.mipmapLevelCount == 1 {
            allocate(texture, width: texture.width, height: texture.height, format: texture.format, mipmapped: true)
            let blit = ensureCommandBuffer().makeBlitCommandEncoder()!
            blit.copy(from: current, sourceSlice: 0, sourceLevel: 0, to: texture.metal!, destinationSlice: 0, destinationLevel: 0, sliceCount: 1, levelCount: 1)
            blit.endEncoding()
        }
        let blit = ensureCommandBuffer().makeBlitCommandEncoder()!
        blit.generateMipmaps(for: texture.metal!)
        blit.endEncoding()
    }

    private func samplerState(_ parameters: SamplerParameters) -> MTLSamplerState {
        if let made = samplerStates[parameters] { return made }
        let d = MTLSamplerDescriptor()
        func wrap(_ v: Int) -> MTLSamplerAddressMode { v == GLConstant.clampToEdge ? .clampToEdge : (v == 0x8370 ? .mirrorRepeat : .repeat) }
        d.sAddressMode = wrap(parameters.wrapS)
        d.tAddressMode = wrap(parameters.wrapT)
        d.magFilter = parameters.mag == GLConstant.nearest ? .nearest : .linear
        d.minFilter = [0x2600, 0x2700, 0x2702].contains(parameters.min) ? .nearest : .linear
        d.mipFilter = [0x2700, 0x2701].contains(parameters.min) ? .nearest : ([0x2702, 0x2703].contains(parameters.min) ? .linear : .notMipmapped)
        let made = device.makeSamplerState(descriptor: d)!
        samplerStates[parameters] = made
        return made
    }

    // MARK: Uniforms

    /// `location`: the uniform's place in the program's list (see `TranslatedProgram.uniformNames`).
    private func setUniform(_ location: Int, _ values: [Double], integer: Bool) {
        guard let p = programs[program], location >= 0, location < p.translated.uniformNames.count else { return }
        let name = p.translated.uniformNames[location]
        if p.translated.isSampler(name) {
            p.samplerUnits[name] = Int(values.first ?? 0)
            return
        }
        guard let member = p.translated.uniforms[name] else { return }
        p.block.withUnsafeMutableBytes { raw in
            let base = raw.baseAddress!
            func put(_ value: Double, at offset: Int) {
                guard offset >= 0, offset + 4 <= raw.count else { return }
                if member.basetype == 13 { base.storeBytes(of: Float(value), toByteOffset: offset, as: Float.self) }
                else { base.storeBytes(of: Int32(value), toByteOffset: offset, as: Int32.self) }
            }
            if member.columns > 1 {
                // A matrix, column by column, each column at the matrix's stride.
                let rows = member.vecsize
                for c in 0..<member.columns {
                    for r in 0..<rows where c * rows + r < values.count {
                        put(values[c * rows + r], at: member.offset + c * member.matrixStride + r * 4)
                    }
                }
                return
            }
            if member.count > 1 || member.arrayStride > 0 {
                var index = 0, element = 0
                while index < values.count, element < member.count {
                    for k in 0..<member.vecsize where index + k < values.count {
                        put(values[index + k], at: member.offset + element * member.arrayStride + k * 4)
                    }
                    index += member.vecsize
                    element += 1
                }
                return
            }
            for (k, value) in values.prefix(member.vecsize).enumerated() { put(value, at: member.offset + k * 4) }
        }
    }

    // MARK: Drawing

    private func vertexFormat(_ a: Attribute) -> MTLVertexFormat {
        switch (a.type, a.size, a.normalized) {
        case (GLConstant.float, 1, _): return .float
        case (GLConstant.float, 2, _): return .float2
        case (GLConstant.float, 3, _): return .float3
        case (GLConstant.float, 4, _): return .float4
        case (GLConstant.unsignedByte, 4, true): return .uchar4Normalized
        case (GLConstant.unsignedByte, 4, false): return .uchar4
        case (GLConstant.unsignedShort, 2, _): return .ushort2
        case (GLConstant.unsignedShort, 4, _): return .ushort4
        default: return .float4
        }
    }

    private func typeSize(_ type: Int) -> Int {
        [GLConstant.float: 4, GLConstant.unsignedByte: 1, 0x1400: 1, GLConstant.unsignedShort: 2, 0x1402: 2, 0x1405: 4, GLConstant.halfFloat: 2][type] ?? 4
    }

    private func blendFactor(_ v: Int) -> MTLBlendFactor {
        switch v {
        case 0: return .zero
        case 1: return .one
        case 0x300: return .sourceColor
        case 0x301: return .oneMinusSourceColor
        case 0x302: return .sourceAlpha
        case 0x303: return .oneMinusSourceAlpha
        case 0x304: return .destinationAlpha
        case 0x305: return .oneMinusDestinationAlpha
        case 0x306: return .destinationColor
        case 0x307: return .oneMinusDestinationColor
        case 0x308: return .sourceAlphaSaturated
        default: return .one
        }
    }

    private func draw(mode: Int, first: Int, count: Int, instances: Int, indexType: Int?, indexOffset: Int) {
        guard count > 0, let p = programs[program], let va = arrays[vertexArray] else { return }
        let t = p.translated
        guard let encoder = beginPass(drawFB), let color = colorTexture(of: drawFB) else { return }
        let depth = depthTexture(of: drawFB)
        // The vertex layout: a buffer binding of its own for each attribute.
        var key = PipelineKey(format: color.pixelFormat.rawValue, depth: depth != nil, blendOn: blendOn,
                              blend: [blendFunc.0, blendFunc.1, blendFunc.2, blendFunc.3, blendEquation], inputs: [])
        var bindings: [(index: Int, buffer: MTLBuffer, offset: Int)] = []
        var inputs: [(location: Int, format: MTLVertexFormat, stride: Int, divisor: Int)] = []
        for (name, glIndex) in p.attributes {
            guard let location = t.inputs[name], let a = va.attributes[glIndex], a.enabled, let buffer = buffers[a.buffer]?.metal else { continue }
            let format = vertexFormat(a)
            let stride = a.stride > 0 ? a.stride : a.size * typeSize(a.type)
            bindings.append((16 + location, buffer, a.offset))
            inputs.append((location, format, stride, a.divisor))
            key.inputs += [location, Int(format.rawValue), stride, a.divisor]
        }
        let pipeline: MTLRenderPipelineState
        if let made = p.pipelines[key] {
            pipeline = made
        } else {
            let vd = MTLVertexDescriptor()
            for input in inputs {
                let slot = 16 + input.location
                vd.attributes[input.location].format = input.format
                vd.attributes[input.location].offset = 0
                vd.attributes[input.location].bufferIndex = slot
                vd.layouts[slot].stride = input.stride
                vd.layouts[slot].stepFunction = input.divisor > 0 ? .perInstance : .perVertex
                vd.layouts[slot].stepRate = max(1, input.divisor)
            }
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = t.vertex
            d.fragmentFunction = t.fragment
            d.vertexDescriptor = vd
            d.colorAttachments[0].pixelFormat = color.pixelFormat
            if blendOn {
                d.colorAttachments[0].isBlendingEnabled = true
                d.colorAttachments[0].sourceRGBBlendFactor = blendFactor(blendFunc.0)
                d.colorAttachments[0].destinationRGBBlendFactor = blendFactor(blendFunc.1)
                d.colorAttachments[0].sourceAlphaBlendFactor = blendFactor(blendFunc.2)
                d.colorAttachments[0].destinationAlphaBlendFactor = blendFactor(blendFunc.3)
                let operation: MTLBlendOperation
                switch blendEquation {
                case 0x800A: operation = .subtract
                case 0x800B: operation = .reverseSubtract
                case 0x8007: operation = .min
                case 0x8008: operation = .max
                default: operation = .add
                }
                d.colorAttachments[0].rgbBlendOperation = operation
                d.colorAttachments[0].alphaBlendOperation = operation
            }
            if let depth { d.depthAttachmentPixelFormat = depth.pixelFormat }
            guard let made = try? device.makeRenderPipelineState(descriptor: d) else { return }
            p.pipelines[key] = made
            pipeline = made
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setViewport(MTLViewport(originX: Double(viewport.0), originY: Double(viewport.1), width: Double(viewport.2),
                                        height: Double(viewport.3), znear: 0, zfar: 1))
        if depth != nil {
            let depthKey = (depthOn ? 1 : 0) | (depthMask ? 2 : 0) | depthFunc << 2
            let state: MTLDepthStencilState
            if let made = depthStates[depthKey] {
                state = made
            } else {
                let d = MTLDepthStencilDescriptor()
                if depthOn {
                    let functions: [Int: MTLCompareFunction] = [0x200: .never, 0x201: .less, 0x202: .equal, 0x203: .lessEqual,
                                                                0x204: .greater, 0x205: .notEqual, 0x206: .greaterEqual, 0x207: .always]
                    d.depthCompareFunction = functions[depthFunc] ?? .less
                    d.isDepthWriteEnabled = depthMask
                }
                state = device.makeDepthStencilState(descriptor: d)!
                depthStates[depthKey] = state
            }
            encoder.setDepthStencilState(state)
        }
        // The vertices turned over turn the winding round.
        encoder.setFrontFacing(frontCCW ? .clockwise : .counterClockwise)
        // Both sides culled: nothing is drawn.
        if cullOn && cullMode == 0x0408 { return }
        encoder.setCullMode(cullOn ? (cullMode == 0x0404 ? .front : .back) : .none)
        for binding in bindings { encoder.setVertexBuffer(binding.buffer, offset: binding.offset, index: binding.index) }
        p.block.withUnsafeBytes { raw in
            let large = raw.count > 4096 ? device.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared) : nil
            if t.vertexBuffer >= 0 && t.vertexBuffer < 16 {
                if let large { encoder.setVertexBuffer(large, offset: 0, index: t.vertexBuffer) }
                else { encoder.setVertexBytes(raw.baseAddress!, length: raw.count, index: t.vertexBuffer) }
            }
            if t.fragmentBuffer >= 0 && t.fragmentBuffer < 16 {
                if let large { encoder.setFragmentBuffer(large, offset: 0, index: t.fragmentBuffer) }
                else { encoder.setFragmentBytes(raw.baseAddress!, length: raw.count, index: t.fragmentBuffer) }
            }
        }
        func source(_ name: String) -> (MTLTexture, MTLSamplerState) {
            let unitIndex = p.samplerUnits[name] ?? 0
            let texture = textures[unitTextures[unitIndex] ?? -1]
            var parameters = SamplerParameters()
            if let s = unitSamplers[unitIndex], let set = samplers[s] {
                parameters = set
            } else if let texture {
                let mipmapped = (texture.metal?.mipmapLevelCount ?? 1) > 1
                parameters = SamplerParameters(wrapS: texture.wrapS, wrapT: texture.wrapT, mag: texture.mag,
                                               min: mipmapped ? texture.min : ([0x2600, 0x2700, 0x2702].contains(texture.min) ? GLConstant.nearest : GLConstant.linear))
            }
            return (texture?.metal ?? white, samplerState(parameters))
        }
        for texture in t.textures {
            let (metal, sampler) = source(texture.name)
            encoder.setFragmentTexture(metal, index: texture.texture)
            if texture.sampler >= 0 && texture.sampler < 16 { encoder.setFragmentSamplerState(sampler, index: texture.sampler) }
        }
        for texture in t.vertexTextures {
            let (metal, sampler) = source(texture.name)
            encoder.setVertexTexture(metal, index: texture.texture)
            if texture.sampler >= 0 && texture.sampler < 16 { encoder.setVertexSamplerState(sampler, index: texture.sampler) }
        }
        let primitive: MTLPrimitiveType = [0: .point, 1: .line, 3: .lineStrip, 4: .triangle, 5: .triangleStrip][mode] ?? .triangle
        if let indexType, let elements = buffers[va.elements]?.metal {
            encoder.drawIndexedPrimitives(type: primitive, indexCount: count, indexType: indexType == 0x1405 ? .uint32 : .uint16,
                                          indexBuffer: elements, indexBufferOffset: indexOffset, instanceCount: max(1, instances))
        } else {
            encoder.drawPrimitives(type: primitive, vertexStart: first, vertexCount: count, instanceCount: max(1, instances))
        }
    }

    // MARK: Copies

    private func blit(_ n: [Int]) {
        var s = (n[0], n[1], n[2], n[3]), d = (n[4], n[5], n[6], n[7])
        let filter = n[9]
        flushClear(readFB)
        guard let source = colorTexture(of: readFB) else { return }
        flushClear(drawFB)
        guard let target = colorTexture(of: drawFB) else { return }
        // As WebGL does: what of the source lies outside its picture is not copied, and what
        // of the target lies outside its own is not drawn; the other rectangle loses as much.
        guard let clipped = Self.clip(source: s, target: d, sourceSize: (source.width, source.height),
                                      targetSize: (target.width, target.height)) else { return }
        (s, d) = clipped
        let sameSize = (s.2 - s.0) == (d.2 - d.0) && (s.3 - s.1) == (d.3 - d.1) && s.2 > s.0 && s.3 > s.1
        if sameSize && drawFB != 0 && source.pixelFormat == target.pixelFormat && source !== target {
            endEncoder()
            let w = min(s.2 - s.0, source.width - s.0, target.width - d.0), h = min(s.3 - s.1, source.height - s.1, target.height - d.1)
            guard w > 0, h > 0, s.0 >= 0, s.1 >= 0, d.0 >= 0, d.1 >= 0 else { return }
            let blit = ensureCommandBuffer().makeBlitCommandEncoder()!
            blit.copy(from: source, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: s.0, y: s.1, z: 0),
                      sourceSize: MTLSize(width: w, height: h, depth: 1), to: target, destinationSlice: 0, destinationLevel: 0,
                      destinationOrigin: MTLOrigin(x: d.0, y: d.1, z: 0))
            blit.endEncoding()
            return
        }
        drawQuad(source: source, into: target, sourceRect: s, targetRect: d, smooth: filter != GLConstant.nearest, toScreen: drawFB == 0)
    }

    typealias Rect = (Int, Int, Int, Int)

    /// The two rectangles of a copy cut to the pictures they lie in, each by as much as the
    /// other loses; nil if nothing is left. Only rectangles that run forwards are cut.
    static func clip(source s: Rect, target d: Rect, sourceSize: (Int, Int), targetSize: (Int, Int)) -> (Rect, Rect)? {
        guard s.2 > s.0, s.3 > s.1, d.2 > d.0, d.3 > d.1 else { return (s, d) }
        var s0 = [Double(s.0), Double(s.1)], s1 = [Double(s.2), Double(s.3)]
        var d0 = [Double(d.0), Double(d.1)], d1 = [Double(d.2), Double(d.3)]
        let sourceLimit = [Double(sourceSize.0), Double(sourceSize.1)], targetLimit = [Double(targetSize.0), Double(targetSize.1)]
        for axis in 0..<2 {
            let scale = (d1[axis] - d0[axis]) / (s1[axis] - s0[axis])
            if s0[axis] < 0 { d0[axis] -= s0[axis] * scale; s0[axis] = 0 }
            if s1[axis] > sourceLimit[axis] { d1[axis] -= (s1[axis] - sourceLimit[axis]) * scale; s1[axis] = sourceLimit[axis] }
            if d0[axis] < 0 { s0[axis] -= d0[axis] / scale; d0[axis] = 0 }
            if d1[axis] > targetLimit[axis] { s1[axis] -= (d1[axis] - targetLimit[axis]) / scale; d1[axis] = targetLimit[axis] }
            guard s1[axis] > s0[axis], d1[axis] > d0[axis] else { return nil }
        }
        func r(_ v: Double) -> Int { Int(v.rounded()) }
        return ((r(s0[0]), r(s0[1]), r(s1[0]), r(s1[1])), (r(d0[0]), r(d0[1]), r(d1[0]), r(d1[1])))
    }

    /// A rectangle of `source` drawn into one of `target`, rows as WebGL counts them; the
    /// screen's rows run the other way.
    private func drawQuad(source: MTLTexture, into target: MTLTexture, sourceRect s: (Int, Int, Int, Int), targetRect d: (Int, Int, Int, Int),
                          smooth: Bool, toScreen: Bool = false) {
        let fb = toScreen ? 0 : -2
        let encoder: MTLRenderCommandEncoder
        if toScreen, let made = beginPass(0) {
            encoder = made
        } else {
            endEncoder()
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .load
            pass.colorAttachments[0].storeAction = .store
            guard let made = ensureCommandBuffer().makeRenderCommandEncoder(descriptor: pass) else { return }
            encoder = made
        }
        let pipeline: MTLRenderPipelineState
        if let made = blitPipelines[target.pixelFormat] {
            pipeline = made
        } else {
            let p = MTLRenderPipelineDescriptor()
            p.vertexFunction = blitVertex
            p.fragmentFunction = blitFragment
            p.colorAttachments[0].pixelFormat = target.pixelFormat
            guard let made = try? device.makeRenderPipelineState(descriptor: p) else { return }
            blitPipelines[target.pixelFormat] = made
            pipeline = made
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(target.width), height: Double(target.height), znear: 0, zfar: 1))
        encoder.setCullMode(.none)
        func clip(_ x: Int, _ y: Int) -> (Float, Float) {
            let cx = Float(x) / Float(target.width) * 2 - 1
            var cy = Float(y) / Float(target.height) * 2 - 1
            if !toScreen { cy = -cy }
            return (cx, cy)
        }
        let c0 = clip(d.0, d.1), c1 = clip(d.2, d.3)
        var rects: [Float] = [Float(s.0), Float(s.1), Float(s.2), Float(s.3), c0.0, c0.1, c1.0, c1.1, Float(source.width), Float(source.height), 0, 0]
        encoder.setVertexBytes(&rects, length: rects.count * 4, index: 0)
        encoder.setFragmentTexture(source, index: 0)
        let filter = smooth ? GLConstant.linear : GLConstant.nearest
        encoder.setFragmentSamplerState(samplerState(SamplerParameters(wrapS: GLConstant.clampToEdge, wrapT: GLConstant.clampToEdge, mag: filter, min: filter)), index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        if !toScreen { encoder.endEncoding() }
        _ = fb
    }

    // MARK: Frames

    /// Hands what was drawn this frame to the graphics chip, and the screen's picture to the
    /// screen if one was drawn.
    func present() {
        endEncoder()
        for fb in Array(pendingClear.keys) { flushClear(fb) }
        if let drawable, let commandBuffer {
            if let screenTexture { copy(screenTexture, toMirrorsIn: commandBuffer) }
            commandBuffer.present(drawable)
            shown = screenTexture
        }
        commandBuffer?.commit()
        if drawable != nil { framesShown += 1 }
        commandBuffer = nil
        drawable = nil
        screenTexture = nil
    }

    /// The frame on the screen copied to the other screens: as it is, the copy costs nearly
    /// nothing next to drawing it again.
    private func copy(_ frame: MTLTexture, toMirrorsIn commands: MTLCommandBuffer) {
        for mirror in mirrors {
            guard Int(mirror.drawableSize.width) == frame.width, Int(mirror.drawableSize.height) == frame.height,
                  mirror.pixelFormat == frame.pixelFormat, let target = mirror.nextDrawable(),
                  let blit = commands.makeBlitCommandEncoder() else { continue }
            blit.copy(from: frame, to: target.texture)
            blit.endEncoding()
            commands.present(target)
            mirroredFrames += 1
        }
    }

    /// Gives the other screens the frame shown now: one just added, or one resized, would
    /// otherwise wait for the next frame, which a scene in which nothing moves never draws.
    func refreshMirrors() {
        guard let shown, !mirrors.isEmpty, let commands = queue.makeCommandBuffer() else { return }
        copy(shown, toMirrorsIn: commands)
        commands.commit()
    }

    /// Waits until everything sent so far is done.
    func finish() {
        present()
        let wait = queue.makeCommandBuffer()!
        wait.commit()
        wait.waitUntilCompleted()
    }

    /// The pixels of the read framebuffer, as WebGL's `readPixels` gives them: RGBA, bottom row first.
    func readPixels(x: Int, y: Int, width: Int, height: Int) -> Data {
        guard width > 0, height > 0, let source = colorTexture(of: readFB) else { return Data() }
        present()
        let length = width * height * 4
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared), let commands = queue.makeCommandBuffer(),
              let blit = commands.makeBlitCommandEncoder() else { return Data() }
        blit.copy(from: source, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: x, y: y, z: 0),
                  sourceSize: MTLSize(width: min(width, source.width - x), height: min(height, source.height - y), depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: width * 4, destinationBytesPerImage: length)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        return Data(bytes: buffer.contents(), count: length)
    }
}

/// What a picture handed to `texImage2D` is, by the time it gets here.
enum GLSource {
    /// RGBA, as the page's picture would be read: top row first, colors not multiplied by alpha.
    case pixels(Data, width: Int, height: Int)
    /// A frame already on the graphics chip — of a video.
    case texture(MTLTexture)
}

/// The numbers of WebGL the stream and the executor share.
enum GLConstant {
    static let texture2D = 0x0DE1, texture0 = 0x84C0
    static let framebuffer = 0x8D40, readFramebuffer = 0x8CA8, drawFramebuffer = 0x8CA9
    static let arrayBuffer = 0x8892, elementArrayBuffer = 0x8893
    static let blend = 0x0BE2, depthTest = 0x0B71, cullFace = 0x0B44
    static let colorBufferBit = 0x4000, depthBufferBit = 0x100
    static let float = 0x1406, unsignedByte = 0x1401, unsignedShort = 0x1403, halfFloat = 0x140B
    static let wrapS = 0x2802, wrapT = 0x2803, magFilter = 0x2800, minFilter = 0x2801
    static let `repeat` = 0x2901, clampToEdge = 0x812F, nearest = 0x2600, linear = 0x2601
    static let unpackFlipY = 0x9240, unpackPremultiply = 0x9241
    static let colorAttachment0 = 0x8CE0, depthAttachment = 0x8D00
    static let funcAdd = 0x8006, ccw = 0x0901
}

/// The operations of the stream, as `metalgl.js` writes them.
enum GLOp {
    static let bindFramebuffer = 1, bindVertexArray = 2, bindTexture = 3, activeTexture = 4, viewport = 5, enable = 6, disable = 7
    static let bindBuffer = 8, vertexAttribPointer = 9, enableVertexAttribArray = 10, disableVertexAttribArray = 11
    static let vertexAttribDivisor = 12, useProgram = 13, uniform = 14, uniformPayload = 15, uniformInteger = 16
    static let blendFuncSeparate = 17, blendFunc = 18, blendEquation = 19, bufferData = 20, bufferSubData = 21
    static let drawArrays = 22, drawElements = 23, drawArraysInstanced = 24, texParameteri = 25, samplerParameteri = 26
    static let bindSampler = 27, texImage2D = 28, texImageSource = 29, pixelStorei = 30, blitFramebuffer = 31, clear = 32
    static let clearColor = 33, depthMask = 34, depthFunc = 35, frontFace = 36, cullFace = 37, framebufferTexture2D = 38
    static let framebufferRenderbuffer = 39, bindRenderbuffer = 40, renderbufferStorage = 41, generateMipmap = 42, delete = 43
}

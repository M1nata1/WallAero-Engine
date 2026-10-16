import Foundation

/// The effects the editor puts on objects: the app's own, written for this app in the shader
/// language of Wallpaper Engine's effects, so that they look the same there. An effect brought
/// into a scene is laid into its project — `effects/wallaero/<name>/effect.json`, its materials
/// and shaders — as effects from the Workshop are.
public struct WallpaperEngineEffect: Identifiable, Sendable {
    public enum Group: String, CaseIterable, Sendable {
        case colorize, blur, animate, distort, enhance

        public var title: String {
            switch self {
            case .colorize: return NSLocalizedString("Color", comment: "Group of effects")
            case .blur: return NSLocalizedString("Blur", comment: "Group of effects")
            case .animate: return NSLocalizedString("Motion", comment: "Group of effects")
            case .distort: return NSLocalizedString("Distortion", comment: "Group of effects")
            case .enhance: return NSLocalizedString("Light and Texture", comment: "Group of effects")
            }
        }
    }

    /// The name of its folder.
    public let id: String
    public let title: String
    public let summary: String
    public let symbol: String
    public let group: Group
    /// Its passes: the shader each draws with, and the combos the material sets.
    let passes: [Pass]
    /// Buffers its passes draw into besides the object, by name, and how much smaller than the
    /// object they are.
    let buffers: [(name: String, scale: Int)]
    /// The shaders, by name, as text: a vertex and a fragment shader each.
    let shaders: [String: (vertex: String, fragment: String)]

    struct Pass {
        var shader: String
        var combos: [String: Int] = [:]
        /// Where it draws to: a buffer, or the object when nil.
        var target: String?
        /// What its textures are: "previous" — what the object is before this pass — or a buffer,
        /// by the slot.
        var bind: [(name: String, index: Int)] = [(name: "previous", index: 0)]
    }

    /// The file a scene names for the effect.
    public var file: String { "effects/wallaero/\(id)/effect.json" }

    /// The number of passes, for the scene's entry of the effect.
    public var passCount: Int { passes.count }

    /// Its files, by their names in a project.
    public var files: [(name: String, data: Data)] {
        var result: [(String, Data)] = []
        var materials: [String] = []
        var passList: [JSONValue] = []
        for (index, pass) in passes.enumerated() {
            let material = "materials/effects/wallaero/\(id)\(passes.count > 1 ? "_\(index + 1)" : "").json"
            materials.append(material)
            var materialPass: [String: JSONValue] = [
                "shader": .string("effects/wallaero/\(pass.shader)"),
                "blending": .string("normal"),
                "depthtest": .string("disabled"),
                "depthwrite": .string("disabled"),
                "cullmode": .string("nocull"),
            ]
            if !pass.combos.isEmpty {
                materialPass["combos"] = .object(pass.combos.mapValues { .number(Double($0)) })
            }
            result.append((material, JSONValue.object(["passes": .array([.object(materialPass)])]).data()))
            var entry: [String: JSONValue] = ["material": .string(material)]
            if let target = pass.target { entry["target"] = .string(target) }
            if pass.bind.count != 1 || pass.bind[0].name != "previous" || pass.bind[0].index != 0 || !buffers.isEmpty {
                entry["bind"] = .array(pass.bind.map { .object(["name": .string($0.name), "index": .number(Double($0.index))]) })
            }
            passList.append(.object(entry))
        }
        var shaderFiles: [String] = []
        for (name, shader) in shaders.sorted(by: { $0.key < $1.key }) {
            let base = "shaders/effects/wallaero/\(name)"
            result.append((base + ".vert", Data(shader.vertex.utf8)))
            result.append((base + ".frag", Data(shader.fragment.utf8)))
            shaderFiles += [base + ".frag", base + ".vert"]
        }
        var effect: [String: JSONValue] = [
            "version": .number(1),
            "name": .string(title),
            "description": .string(summary),
            "group": .string(group.rawValue),
            "passes": .array(passList),
            "dependencies": .array((materials + shaderFiles).map(JSONValue.string)),
        ]
        if !buffers.isEmpty {
            effect["fbos"] = .array(buffers.map { .object(["name": .string($0.name), "scale": .number(Double($0.scale)),
                                                           "format": .string("rgba_backbuffer")]) })
        }
        result.insert((file, JSONValue.object(effect).data()), at: 0)
        return result
    }
}

extension WallpaperEngineDocument {
    /// Puts an effect on an object, after its others; its files go into the project if they are
    /// not there yet.
    public mutating func addEffect(_ effect: WallpaperEngineEffect, to object: Int, projectFolder: URL) throws {
        for file in effect.files {
            let url = projectFolder.appendingPathComponent(file.name)
            if file.name.hasSuffix(".json"), let value = JSONValue(data: file.data) {
                // The JSON files are the document's, written with it.
                if self.file(file.name) == nil { setFile(file.name, value) }
                continue
            }
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try file.data.write(to: url, options: .atomic)
            }
        }
        let id = newID()
        let passes: [JSONValue] = (0..<effect.passCount).map { index in
            .object(["id": .number(Double(id + 1 + index)), "constantshadervalues": .object([:])])
        }
        let entry: JSONValue = .object([
            "file": .string(effect.file),
            "id": .number(Double(id)),
            "name": .string(""),
            "passes": .array(passes),
            "visible": .bool(true),
        ])
        update(object) { value in
            var effects = value["effects"]?.arrayValue ?? []
            effects.append(entry)
            value["effects"] = .array(effects)
        }
    }

    /// A value of an effect of an object, as its material names it; set on every pass of the
    /// effect, since passes of one effect share their values.
    public mutating func setEffectValue(_ value: JSONValue, named name: String, effect index: Int, of object: Int) {
        update(object) { object in
            guard var effects = object["effects"]?.arrayValue, effects.indices.contains(index) else { return }
            var effect = effects[index]
            var passes = effect["passes"]?.arrayValue ?? [.object([:])]
            if passes.isEmpty { passes = [.object([:])] }
            passes = passes.map { pass in
                var pass = pass
                var constants = pass["constantshadervalues"] ?? .object([:])
                constants[name] = constants[name].map { $0.replacingPlain(with: value) } ?? value
                pass["constantshadervalues"] = constants
                return pass
            }
            effect["passes"] = .array(passes)
            effects[index] = effect
            object["effects"] = .array(effects)
        }
    }

    public mutating func setEffectVisible(_ visible: Bool, effect index: Int, of object: Int) {
        update(object) { object in
            guard var effects = object["effects"]?.arrayValue, effects.indices.contains(index) else { return }
            effects[index]["visible"] = effects[index]["visible"].map { $0.replacingPlain(with: .bool(visible)) } ?? .bool(visible)
            object["effects"] = .array(effects)
        }
    }

    public mutating func removeEffect(at index: Int, of object: Int) {
        update(object) { object in
            guard var effects = object["effects"]?.arrayValue, effects.indices.contains(index) else { return }
            effects.remove(at: index)
            object["effects"] = .array(effects)
        }
    }

    public mutating func moveEffect(from source: Int, to destination: Int, of object: Int) {
        update(object) { object in
            guard var effects = object["effects"]?.arrayValue, effects.indices.contains(source) else { return }
            let effect = effects.remove(at: source)
            effects.insert(effect, at: min(max(destination, 0), effects.count))
            object["effects"] = .array(effects)
        }
    }
}

// MARK: - The effects

extension WallpaperEngineEffect {
    /// Every effect, in the order the editor offers them.
    public static let all: [WallpaperEngineEffect] = [
        tint, colorAdjust, opacity, vignette,
        blur, pixelate,
        shake, sway, scroll, spin, pulse,
        waterRipple, waterWaves, chromaticAberration,
        shine, filmGrain,
    ]

    public static func named(_ id: String) -> WallpaperEngineEffect? {
        all.first { $0.id == id }
    }

    /// The vertex shader most effects draw with: the object's corners, its picture's place,
    /// and where on the mask that place is.
    static let plainVertex = """
    uniform mat4 g_ModelViewProjectionMatrix;
    #if MASK
    uniform vec4 g_Texture1Resolution;
    #endif

    attribute vec3 a_Position;
    attribute vec2 a_TexCoord;

    varying vec4 v_TexCoord;

    void main() {
    \tgl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
    \tv_TexCoord = a_TexCoord.xyxy;
    #if MASK
    \tv_TexCoord.zw = vec2(v_TexCoord.x * g_Texture1Resolution.z / g_Texture1Resolution.x,
    \t\tv_TexCoord.y * g_Texture1Resolution.w / g_Texture1Resolution.y);
    #endif
    }

    """

    /// What every fragment shader of these effects starts with: the picture, and a mask that
    /// says where the effect shows.
    static func fragmentHead(_ uniforms: String) -> String {
        """
        varying vec4 v_TexCoord;

        uniform sampler2D g_Texture0; // {"hidden":true}
        uniform sampler2D g_Texture1; // {"label":"ui_editor_properties_opacity_mask","mode":"opacitymask","combo":"MASK","paintdefaultcolor":"0 0 0 1"}
        uniform float g_Time;
        \(uniforms)

        float effectMask() {
        #if MASK
        \treturn texSample2D(g_Texture1, v_TexCoord.zw).r;
        #else
        \treturn 1.0;
        #endif
        }

        """
    }

    static func single(_ id: String, title: String, summary: String, symbol: String, group: Group, fragment: String) -> WallpaperEngineEffect {
        WallpaperEngineEffect(id: id, title: title, summary: summary, symbol: symbol, group: group,
                              passes: [Pass(shader: id)], buffers: [], shaders: [id: (plainVertex, fragment)])
    }

    // MARK: Color

    static let tint = single(
        "tint", title: NSLocalizedString("Tint", comment: "Effect"),
        summary: NSLocalizedString("Lays a color over the picture, in a blend mode.", comment: "Effect"),
        symbol: "paintbrush", group: .colorize,
        fragment: """
        // [COMBO] {"material":"ui_editor_properties_blend_mode","combo":"BLENDMODE","type":"imageblending","default":2}
        #include "common_blending.h"
        """ + "\n" + fragmentHead("""
        uniform float g_BlendAlpha; // {"material":"alpha","label":"ui_editor_properties_alpha","default":1,"range":[0,1]}
        uniform vec3 g_TintColor; // {"material":"color","label":"ui_editor_properties_color","type":"color","default":"1 0.5 0"}
        """) + """
        void main() {
        \tvec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
        \talbedo.rgb = ApplyBlending(BLENDMODE, albedo.rgb, g_TintColor, g_BlendAlpha * effectMask());
        \tgl_FragColor = albedo;
        }

        """)

    static let colorAdjust = single(
        "coloradjust", title: NSLocalizedString("Color Adjustment", comment: "Effect"),
        summary: NSLocalizedString("Brightness, contrast, saturation and hue.", comment: "Effect"),
        symbol: "slider.horizontal.3", group: .colorize,
        fragment: "#include \"common.h\"\n" + fragmentHead("""
        uniform float g_Brightness2; // {"material":"brightness","label":"ui_editor_properties_brightness","default":1,"range":[0,3]}
        uniform float g_Contrast; // {"material":"contrast","label":"ui_editor_properties_contrast","default":1,"range":[0,3]}
        uniform float g_Saturation; // {"material":"saturation","label":"ui_editor_properties_saturation","default":1,"range":[0,3]}
        uniform float g_HueShift; // {"material":"hue","label":"ui_editor_properties_hue","default":0,"range":[-1,1]}
        """) + """
        void main() {
        \tvec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
        \tvec3 color = albedo.rgb * g_Brightness2;
        \tcolor = (color - 0.5) * g_Contrast + 0.5;
        \tfloat grey = dot(color, vec3(0.299, 0.587, 0.114));
        \tcolor = mix(vec3(grey, grey, grey), color, g_Saturation);
        \tvec3 hsv = rgb2hsv(clamp(color, 0.0, 1.0));
        \thsv.x = frac(hsv.x + g_HueShift);
        \tcolor = hsv2rgb(hsv);
        \talbedo.rgb = mix(albedo.rgb, color, effectMask());
        \tgl_FragColor = albedo;
        }

        """)

    static let opacity = single(
        "opacity", title: NSLocalizedString("Opacity", comment: "Effect"),
        summary: NSLocalizedString("Makes the picture see-through, everywhere or where a mask says.", comment: "Effect"),
        symbol: "circle.lefthalf.filled", group: .colorize,
        fragment: fragmentHead("""
        uniform float g_UserAlpha2; // {"material":"alpha","label":"ui_editor_properties_alpha","default":1,"range":[0,1]}
        """) + """
        void main() {
        \tvec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
        \talbedo.a *= mix(1.0, g_UserAlpha2, 1.0) * effectMask();
        \tgl_FragColor = albedo;
        }

        """)

    static let vignette = single(
        "vignette", title: NSLocalizedString("Vignette", comment: "Effect"),
        summary: NSLocalizedString("Darkens the picture toward its edges.", comment: "Effect"),
        symbol: "circle.dashed", group: .colorize,
        fragment: fragmentHead("""
        uniform float g_Strength; // {"material":"strength","label":"ui_editor_properties_strength","default":0.6,"range":[0,1]}
        uniform float g_Radius; // {"material":"radius","label":"ui_editor_properties_radius","default":0.75,"range":[0,1.5]}
        uniform float g_Softness; // {"material":"softness","label":"ui_editor_properties_smoothness","default":0.45,"range":[0.01,1]}
        uniform vec3 g_VignetteColor; // {"material":"color","label":"ui_editor_properties_color","type":"color","default":"0 0 0"}
        """) + """
        void main() {
        \tvec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
        \tfloat reach = length(v_TexCoord.xy - 0.5) * 1.41421356;
        \tfloat shade = smoothstep(g_Radius - g_Softness, g_Radius, reach) * g_Strength * effectMask();
        \talbedo.rgb = mix(albedo.rgb, g_VignetteColor, shade);
        \tgl_FragColor = albedo;
        }

        """)

    // MARK: Blur

    static let blur = WallpaperEngineEffect(
        id: "blur", title: NSLocalizedString("Blur", comment: "Effect"),
        summary: NSLocalizedString("Softens the picture.", comment: "Effect"),
        symbol: "drop", group: .blur,
        passes: [
            Pass(shader: "blur", target: "_rt_FullCompoBuffer1"),
            Pass(shader: "blur", combos: ["VERTICAL": 1], bind: [(name: "_rt_FullCompoBuffer1", index: 0), (name: "previous", index: 2)]),
        ],
        buffers: [(name: "_rt_FullCompoBuffer1", scale: 1)],
        shaders: ["blur": (plainVertex, """
        // [COMBO] {"material":"ui_editor_properties_vertical","combo":"VERTICAL","type":"options","default":0}
        varying vec4 v_TexCoord;

        uniform sampler2D g_Texture0; // {"hidden":true}
        uniform sampler2D g_Texture1; // {"label":"ui_editor_properties_opacity_mask","mode":"opacitymask","combo":"MASK","paintdefaultcolor":"0 0 0 1"}
        uniform sampler2D g_Texture2; // {"hidden":true}
        uniform vec4 g_Texture0Resolution;
        uniform float g_BlurScale; // {"material":"scale","label":"ui_editor_properties_scale","default":4,"range":[0,32]}

        void main() {
        #if VERTICAL
        \tvec2 stride = vec2(0.0, g_BlurScale / max(g_Texture0Resolution.y, 1.0));
        #else
        \tvec2 stride = vec2(g_BlurScale / max(g_Texture0Resolution.x, 1.0), 0.0);
        #endif
        \tvec4 sum = texSample2D(g_Texture0, v_TexCoord.xy) * 0.2270270270;
        \tsum += texSample2D(g_Texture0, v_TexCoord.xy + stride * 1.3846153846) * 0.3162162162;
        \tsum += texSample2D(g_Texture0, v_TexCoord.xy - stride * 1.3846153846) * 0.3162162162;
        \tsum += texSample2D(g_Texture0, v_TexCoord.xy + stride * 3.2307692308) * 0.0702702703;
        \tsum += texSample2D(g_Texture0, v_TexCoord.xy - stride * 3.2307692308) * 0.0702702703;
        #if VERTICAL
        \tfloat mask = 1.0;
        #if MASK
        \tmask = texSample2D(g_Texture1, v_TexCoord.zw).r;
        #endif
        \tsum = mix(texSample2D(g_Texture2, v_TexCoord.xy), sum, mask);
        #endif
        \tgl_FragColor = sum;
        }

        """)])

    static let pixelate = single(
        "pixelate", title: NSLocalizedString("Pixelate", comment: "Effect"),
        summary: NSLocalizedString("Turns the picture into large squares.", comment: "Effect"),
        symbol: "square.grid.3x3", group: .blur,
        fragment: fragmentHead("""
        uniform vec4 g_Texture0Resolution;
        uniform float g_PixelSize; // {"material":"size","label":"ui_editor_properties_size","default":12,"range":[1,128]}
        """) + """
        void main() {
        \tvec2 cells = max(g_Texture0Resolution.xy / max(g_PixelSize, 1.0), vec2(1.0, 1.0));
        \tvec2 coords = (floor(v_TexCoord.xy * cells) + 0.5) / cells;
        \tgl_FragColor = mix(texSample2D(g_Texture0, v_TexCoord.xy), texSample2D(g_Texture0, coords), effectMask());
        }

        """)

    // MARK: Motion

    static let shake = single(
        "shake", title: NSLocalizedString("Shake", comment: "Effect"),
        summary: NSLocalizedString("Moves the picture back and forth in place.", comment: "Effect"),
        symbol: "water.waves", group: .animate,
        fragment: fragmentHead("""
        uniform float g_Speed; // {"material":"speed","label":"ui_editor_properties_speed","default":1,"range":[0,10]}
        uniform float g_Amp; // {"material":"strength","label":"ui_editor_properties_strength","default":0.02,"range":[0,0.2]}
        uniform float g_Direction; // {"material":"direction","label":"ui_editor_properties_direction","default":0,"range":[0,6.28318],"direction":true}
        """) + """
        void main() {
        \tvec2 way = vec2(cos(g_Direction), sin(g_Direction));
        \tfloat move = sin(g_Time * g_Speed * 6.28318) * g_Amp * effectMask();
        \tgl_FragColor = texSample2D(g_Texture0, v_TexCoord.xy + way * move);
        }

        """)

    static let sway = single(
        "sway", title: NSLocalizedString("Sway", comment: "Effect"),
        summary: NSLocalizedString("Bends the picture to and fro, as wind does grass and leaves.", comment: "Effect"),
        symbol: "wind", group: .animate,
        fragment: fragmentHead("""
        uniform float g_Speed; // {"material":"speed","label":"ui_editor_properties_speed","default":0.6,"range":[0,5]}
        uniform float g_Amp; // {"material":"strength","label":"ui_editor_properties_strength","default":0.03,"range":[0,0.2]}
        uniform float g_Scale2; // {"material":"scale","label":"ui_editor_properties_scale","default":3,"range":[0.1,20]}
        """) + """
        void main() {
        \t// What is higher bends further; the bottom stays where it is.
        \tfloat height = 1.0 - v_TexCoord.y;
        \tfloat wave = sin(g_Time * g_Speed * 6.28318 + v_TexCoord.x * g_Scale2) + 0.4 * sin(g_Time * g_Speed * 11.0 + v_TexCoord.y * g_Scale2 * 2.0);
        \tvec2 coords = v_TexCoord.xy - vec2(wave * g_Amp * height * height * effectMask(), 0.0);
        \tgl_FragColor = texSample2D(g_Texture0, coords);
        }

        """)

    static let scroll = single(
        "scroll", title: NSLocalizedString("Scroll", comment: "Effect"),
        summary: NSLocalizedString("Moves the picture on endlessly, as a band.", comment: "Effect"),
        symbol: "arrow.left.and.right", group: .animate,
        fragment: fragmentHead("""
        uniform vec2 g_ScrollSpeed; // {"material":"speed","label":"ui_editor_properties_speed","default":"0.1 0"}
        """) + """
        void main() {
        \tvec2 coords = frac(v_TexCoord.xy - g_ScrollSpeed * g_Time);
        \tgl_FragColor = mix(texSample2D(g_Texture0, v_TexCoord.xy), texSample2D(g_Texture0, coords), effectMask());
        }

        """)

    static let spin = single(
        "spin", title: NSLocalizedString("Spin", comment: "Effect"),
        summary: NSLocalizedString("Turns the picture about its middle.", comment: "Effect"),
        symbol: "arrow.triangle.2.circlepath", group: .animate,
        fragment: fragmentHead("""
        uniform float g_Speed; // {"material":"speed","label":"ui_editor_properties_speed","default":0.2,"range":[-5,5]}
        uniform vec2 g_SpinCenter; // {"material":"center","label":"ui_editor_properties_center","default":"0.5 0.5"}
        """) + """
        void main() {
        \tfloat turn = g_Time * g_Speed * 6.28318 * effectMask();
        \tvec2 from = v_TexCoord.xy - g_SpinCenter;
        \tvec2 coords = vec2(from.x * cos(turn) - from.y * sin(turn), from.x * sin(turn) + from.y * cos(turn)) + g_SpinCenter;
        \tvec4 albedo = texSample2D(g_Texture0, coords);
        \tif (coords.x < 0.0 || coords.y < 0.0 || coords.x > 1.0 || coords.y > 1.0) albedo.a = 0.0;
        \tgl_FragColor = albedo;
        }

        """)

    static let pulse = single(
        "pulse", title: NSLocalizedString("Pulse", comment: "Effect"),
        summary: NSLocalizedString("Makes the picture brighten and fade in a rhythm.", comment: "Effect"),
        symbol: "waveform.path.ecg", group: .animate,
        fragment: fragmentHead("""
        uniform float g_Speed; // {"material":"speed","label":"ui_editor_properties_speed","default":1,"range":[0,10]}
        uniform float g_PulseLow; // {"material":"low","label":"ui_editor_properties_minimum","default":0.4,"range":[0,2]}
        uniform float g_PulseHigh; // {"material":"high","label":"ui_editor_properties_maximum","default":1.2,"range":[0,3]}
        """) + """
        void main() {
        \tvec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
        \tfloat beat = mix(g_PulseLow, g_PulseHigh, 0.5 + 0.5 * sin(g_Time * g_Speed * 6.28318));
        \talbedo.rgb *= mix(1.0, beat, effectMask());
        \tgl_FragColor = albedo;
        }

        """)

    // MARK: Distortion

    static let waterRipple = single(
        "waterripple", title: NSLocalizedString("Water Ripple", comment: "Effect"),
        summary: NSLocalizedString("Rings spread from a point as on water.", comment: "Effect"),
        symbol: "drop.circle", group: .distort,
        fragment: fragmentHead("""
        uniform float g_Speed; // {"material":"speed","label":"ui_editor_properties_speed","default":1,"range":[0,10]}
        uniform float g_Amp; // {"material":"strength","label":"ui_editor_properties_strength","default":0.01,"range":[0,0.1]}
        uniform float g_Frequency; // {"material":"frequency","label":"ui_editor_properties_frequency","default":40,"range":[1,200]}
        uniform vec2 g_RippleCenter; // {"material":"center","label":"ui_editor_properties_center","default":"0.5 0.5"}
        """) + """
        void main() {
        \tvec2 from = v_TexCoord.xy - g_RippleCenter;
        \tfloat reach = length(from);
        \tfloat ring = sin(reach * g_Frequency - g_Time * g_Speed * 6.28318);
        \tvec2 coords = v_TexCoord.xy + normalize(from + vec2(0.00001, 0.0)) * ring * g_Amp * effectMask();
        \tgl_FragColor = texSample2D(g_Texture0, coords);
        }

        """)

    static let waterWaves = single(
        "waterwaves", title: NSLocalizedString("Water Waves", comment: "Effect"),
        summary: NSLocalizedString("Waves run across the picture.", comment: "Effect"),
        symbol: "water.waves", group: .distort,
        fragment: fragmentHead("""
        uniform float g_Speed; // {"material":"speed","label":"ui_editor_properties_speed","default":1,"range":[0,10]}
        uniform float g_Amp; // {"material":"strength","label":"ui_editor_properties_strength","default":0.005,"range":[0,0.05]}
        uniform float g_Scale2; // {"material":"scale","label":"ui_editor_properties_scale","default":30,"range":[1,200]}
        uniform float g_Direction; // {"material":"direction","label":"ui_editor_properties_direction","default":0,"range":[0,6.28318],"direction":true}
        """) + """
        void main() {
        \tvec2 way = vec2(cos(g_Direction), sin(g_Direction));
        \tvec2 across = vec2(-way.y, way.x);
        \tfloat along = dot(v_TexCoord.xy, way);
        \tfloat wave = sin(along * g_Scale2 + g_Time * g_Speed * 3.0) + 0.5 * sin(dot(v_TexCoord.xy, across) * g_Scale2 * 0.7 - g_Time * g_Speed * 2.0);
        \tgl_FragColor = texSample2D(g_Texture0, v_TexCoord.xy + across * wave * g_Amp * effectMask());
        }

        """)

    static let chromaticAberration = single(
        "chromaticaberration", title: NSLocalizedString("Color Fringes", comment: "Effect"),
        summary: NSLocalizedString("Shifts red and blue apart, as a cheap lens does.", comment: "Effect"),
        symbol: "camera.filters", group: .distort,
        fragment: fragmentHead("""
        uniform float g_Amp; // {"material":"strength","label":"ui_editor_properties_strength","default":0.004,"range":[0,0.05]}
        uniform float g_Direction; // {"material":"direction","label":"ui_editor_properties_direction","default":0,"range":[0,6.28318],"direction":true}
        """) + """
        void main() {
        \tvec2 shift = vec2(cos(g_Direction), sin(g_Direction)) * g_Amp * effectMask();
        \tvec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
        \talbedo.r = texSample2D(g_Texture0, v_TexCoord.xy + shift).r;
        \talbedo.b = texSample2D(g_Texture0, v_TexCoord.xy - shift).b;
        \tgl_FragColor = albedo;
        }

        """)

    // MARK: Light and texture

    static let shine = single(
        "shine", title: NSLocalizedString("Shine", comment: "Effect"),
        summary: NSLocalizedString("A band of light passes over the picture now and then.", comment: "Effect"),
        symbol: "sparkle", group: .enhance,
        fragment: fragmentHead("""
        uniform float g_Speed; // {"material":"speed","label":"ui_editor_properties_speed","default":0.4,"range":[0,5]}
        uniform float g_ShineWidth; // {"material":"width","label":"ui_editor_properties_width","default":0.08,"range":[0.01,0.5]}
        uniform float g_Direction; // {"material":"direction","label":"ui_editor_properties_direction","default":0.6,"range":[0,6.28318],"direction":true}
        uniform vec3 g_ShineColor; // {"material":"color","label":"ui_editor_properties_color","type":"color","default":"1 1 1"}
        uniform float g_ShineStrength; // {"material":"strength","label":"ui_editor_properties_strength","default":0.6,"range":[0,2]}
        """) + """
        void main() {
        \tvec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
        \tvec2 way = vec2(cos(g_Direction), sin(g_Direction));
        \tfloat along = dot(v_TexCoord.xy - 0.5, way) + 0.5;
        \tfloat place = frac(g_Time * g_Speed) * 3.0 - 1.0;
        \tfloat band = 1.0 - smoothstep(0.0, g_ShineWidth, abs(along - place));
        \talbedo.rgb += g_ShineColor * band * g_ShineStrength * effectMask() * albedo.a;
        \tgl_FragColor = albedo;
        }

        """)

    static let filmGrain = single(
        "filmgrain", title: NSLocalizedString("Film Grain", comment: "Effect"),
        summary: NSLocalizedString("Fine moving noise, as on film.", comment: "Effect"),
        symbol: "circle.grid.3x3.fill", group: .enhance,
        fragment: fragmentHead("""
        uniform float g_Amp; // {"material":"strength","label":"ui_editor_properties_strength","default":0.08,"range":[0,0.5]}
        uniform float g_Speed; // {"material":"speed","label":"ui_editor_properties_speed","default":24,"range":[0,60]}
        """) + """
        float grain(vec2 at) {
        \treturn frac(sin(dot(at, vec2(12.9898, 78.233))) * 43758.5453);
        }

        void main() {
        \tvec4 albedo = texSample2D(g_Texture0, v_TexCoord.xy);
        \tfloat frame = floor(g_Time * g_Speed);
        \tfloat noise = grain(v_TexCoord.xy * 1000.0 + frame) - 0.5;
        \talbedo.rgb += noise * g_Amp * effectMask();
        \tgl_FragColor = albedo;
        }

        """)
}

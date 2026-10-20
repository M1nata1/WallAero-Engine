import Foundation
import Metal
import ShaderTranslation

/// A WebGL program made over for Metal (see `ShaderTranslation`): its two functions, where its
/// vertex inputs are, and where each of its uniforms lies in the one block both stages read.
final class TranslatedProgram {
    struct Member {
        let offset: Int, size: Int, arrayStride: Int, matrixStride: Int, columns: Int, vecsize: Int, count: Int
        /// SPIRV-Cross's kind of number: 13 a float; integers and booleans otherwise.
        let basetype: Int
    }
    struct TextureSlot { let name: String; let texture: Int; let sampler: Int }

    let vertex: MTLFunction
    let fragment: MTLFunction
    /// Attribute name → Metal attribute index.
    let inputs: [String: Int]
    let uniforms: [String: Member]
    let blockSize: Int
    let vertexBuffer: Int
    let fragmentBuffer: Int
    let textures: [TextureSlot]
    let vertexTextures: [TextureSlot]
    /// Every uniform and sampler, in the order WebGL's `getActiveUniform` gives them here.
    let uniformNames: [String]
    /// What `getActiveUniform` says of each: WebGL's name (arrays with "[0]"), kind and size.
    let activeUniforms: [(name: String, type: Int, size: Int)]

    private let samplerNames: Set<String>
    func isSampler(_ name: String) -> Bool { samplerNames.contains(name) }

    private init(vertex: MTLFunction, fragment: MTLFunction, inputs: [String: Int], uniforms: [String: Member], blockSize: Int,
                 vertexBuffer: Int, fragmentBuffer: Int, textures: [TextureSlot], vertexTextures: [TextureSlot]) {
        self.vertex = vertex
        self.fragment = fragment
        self.inputs = inputs
        self.uniforms = uniforms
        self.blockSize = blockSize
        self.vertexBuffer = vertexBuffer
        self.fragmentBuffer = fragmentBuffer
        self.textures = textures
        self.vertexTextures = vertexTextures
        let samplers = Array(Set(textures.map(\.name) + vertexTextures.map(\.name))).sorted()
        samplerNames = Set(samplers)
        let numbers = uniforms.keys.sorted()
        uniformNames = numbers + samplers
        var active: [(String, Int, Int)] = []
        for name in numbers {
            let m = uniforms[name]!
            let isArray = m.count > 1 || m.arrayStride > 0
            active.append((isArray ? name + "[0]" : name, Self.glType(m), max(1, m.count)))
        }
        for name in samplers { active.append((name, 0x8B5E, 1)) }
        activeUniforms = active
    }

    /// WebGL's number for the kind of a uniform.
    private static func glType(_ m: Member) -> Int {
        if m.columns > 1 { return [2: 0x8B5A, 3: 0x8B5B, 4: 0x8B5C][m.columns] ?? 0x8B5C }
        if m.basetype == 13 { return [1: 0x1406, 2: 0x8B50, 3: 0x8B51, 4: 0x8B52][m.vecsize] ?? 0x1406 }
        if m.basetype == 2 { return [1: 0x8B56, 2: 0x8B57, 3: 0x8B58, 4: 0x8B59][m.vecsize] ?? 0x8B56 }
        return [1: 0x1404, 2: 0x8B53, 3: 0x8B54, 4: 0x8B55][m.vecsize] ?? 0x1404
    }

    /// The program, or why it cannot be made.
    static func make(device: MTLDevice, vertex: String, fragment: String) -> (TranslatedProgram?, String?) {
        let fragment = matchVaryingTypes(vertex: vertex, fragment: fragment)
        let answer = ShaderCache.answer(["translate", vertex, fragment]) {
            guard let raw = shader_translate(vertex, fragment) else { return nil }
            defer { free(raw) }
            return String(cString: raw)
        }
        guard let answer, let json = try? JSONSerialization.jsonObject(with: Data(answer.utf8)) as? [String: Any] else {
            return (nil, "the shaders could not be translated")
        }
        if let error = json["error"] as? String { return (nil, error) }
        var vertexSource = json["vertex"] as? String ?? ""
        var fragmentSource = json["fragment"] as? String ?? ""
        matchVaryings(vertex: &vertexSource, fragment: &fragmentSource)
        if let folder = ProcessInfo.processInfo.environment["WALLAERO_SHADER_DUMP"] {
            let name = String(format: "%08x", UInt32(truncatingIfNeeded: (vertex + fragment).hashValue))
            for (suffix, text) in [("vert", vertex), ("frag", fragment), ("vert.metal", vertexSource), ("frag.metal", fragmentSource),
                                   ("json", answer)] {
                try? text.write(toFile: "\(folder)/\(name).\(suffix)", atomically: false, encoding: .utf8)
            }
        }
        func function(_ source: String) -> (MTLFunction?, String?) {
            do {
                let library = try device.makeLibrary(source: source, options: nil)
                return (library.makeFunction(name: "main0"), nil)
            } catch {
                return (nil, error.localizedDescription)
            }
        }
        let (v, vertexError) = function(vertexSource)
        let (f, fragmentError) = function(fragmentSource)
        guard let v, let f else { return (nil, vertexError ?? fragmentError ?? "Metal refused the shaders") }
        var inputs: [String: Int] = [:]
        for input in json["inputs"] as? [[String: Any]] ?? [] {
            inputs[input["name"] as? String ?? ""] = (input["location"] as? NSNumber)?.intValue ?? 0
        }
        var members: [String: Member] = [:]
        var size = 0
        for list in [json["vertexUniforms"], json["fragmentUniforms"]] {
            for m in list as? [[String: Any]] ?? [] {
                func n(_ key: String) -> Int { (m[key] as? NSNumber)?.intValue ?? 0 }
                let member = Member(offset: n("offset"), size: n("size"), arrayStride: n("arrayStride"), matrixStride: n("matrixStride"),
                                    columns: max(1, n("columns")), vecsize: max(1, n("vecsize")), count: max(1, n("count")), basetype: n("basetype"))
                members[m["name"] as? String ?? ""] = member
                size = max(size, member.offset + member.size)
            }
        }
        func slots(_ key: String) -> [TextureSlot] {
            (json[key] as? [[String: Any]] ?? []).compactMap { entry in
                let texture = (entry["texture"] as? NSNumber)?.intValue ?? -1
                guard texture >= 0 && texture < 31 else { return nil }
                return TextureSlot(name: entry["name"] as? String ?? "", texture: texture, sampler: (entry["sampler"] as? NSNumber)?.intValue ?? -1)
            }
        }
        func bufferIndex(_ key: String) -> Int {
            let index = (json[key] as? NSNumber)?.intValue ?? -1
            return index >= 0 && index < 16 ? index : -1
        }
        return (TranslatedProgram(vertex: v, fragment: f, inputs: inputs, uniforms: members, blockSize: max(16, (size + 15) / 16 * 16),
                                  vertexBuffer: bufferIndex("vertexBuffer"), fragmentBuffer: bufferIndex("fragmentBuffer"),
                                  textures: slots("textures"), vertexTextures: slots("vertexTextures")), nil)
    }

    /// Browsers let a fragment shader take as a smaller vector what its vertex shader hands over
    /// as a larger one; glslang does not. Such an input is taken as the vertex shader gives it,
    /// under another name, and its own name stands for the part of it the shader wants.
    static func matchVaryingTypes(vertex: String, fragment: String) -> String {
        let declaration = #"(?m)^[ \t]*((?:flat|smooth|centroid)\s+)?(in|out)\s+((?:highp|mediump|lowp)\s+)?(float|vec2|vec3|vec4)\s+(\w+)\s*;"#
        guard let pattern = try? NSRegularExpression(pattern: declaration) else { return fragment }
        func declared(_ source: String, _ direction: String) -> [String: (type: String, range: NSRange)] {
            var found: [String: (String, NSRange)] = [:]
            for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let directionRange = Range(match.range(at: 2), in: source), source[directionRange] == direction,
                      let typeRange = Range(match.range(at: 4), in: source), let nameRange = Range(match.range(at: 5), in: source) else { continue }
                found[String(source[nameRange])] = (String(source[typeRange]), match.range)
            }
            return found
        }
        let outputs = declared(vertex, "out")
        var result = fragment
        let size: [String: Int] = ["float": 1, "vec2": 2, "vec3": 3, "vec4": 4]
        for (name, input) in declared(fragment, "in").sorted(by: { $0.value.range.location > $1.value.range.location }) {
            guard let output = outputs[name], output.type != input.type, let from = size[output.type], let to = size[input.type],
                  let range = Range(input.range, in: result) else { continue }
            let wide = name + "_given"
            let part: String
            if to < from {
                part = "(\(wide).\(String("xyzw".prefix(to))))"
            } else {
                let padding = Array(repeating: "0.0", count: to - from).joined(separator: ", ")
                part = "\(input.type)(\(wide), \(padding))"
            }
            result.replaceSubrange(range, with: "in \(output.type) \(wide);\n#define \(name) \(part)")
        }
        return result
    }

    /// WebGL matches what the vertex shader hands the fragment shader by name, and lets a
    /// fragment input go unmatched if it is never used; Metal matches by place and takes no
    /// unmatched input. Each fragment input takes the place its vertex output has; one the
    /// vertex shader lacks is given as nought, at a free place.
    static func matchVaryings(vertex: inout String, fragment: inout String) {
        func members(_ source: String, of name: String) -> [(name: String, location: String, line: String)] {
            guard let start = source.range(of: "struct \(name)\n{") else { return [] }
            let body = source[start.upperBound...].prefix { $0 != "}" }
            return body.split(separator: "\n").compactMap { line in
                guard let at = line.range(of: "[[user(locn") else { return nil }
                let location = String(line[at.upperBound...].prefix { $0 != ")" })
                guard let member = line[..<at.lowerBound].split(separator: " ").last else { return nil }
                return (String(member), location, String(line))
            }
        }
        let outputs = members(vertex, of: "main0_out")
        var byName: [String: String] = [:]
        for output in outputs { byName[output.name] = output.location }
        var used = Set(outputs.map(\.location))
        var added: [String] = []
        for input in members(fragment, of: "main0_in") {
            let original = "[[user(locn\(input.location))]]"
            // An input taken under another name by `matchVaryingTypes` is still the vertex output's.
            let given = input.name.hasSuffix("_given") ? String(input.name.dropLast("_given".count)) : input.name
            if let location = byName[input.name] ?? byName[given] {
                if location != input.location {
                    fragment = fragment.replacingOccurrences(of: input.line, with: input.line.replacingOccurrences(of: original, with: "[[user(locn\(location))]]"))
                }
            } else {
                var free = 20
                while used.contains(String(free)) { free += 1 }
                used.insert(String(free))
                fragment = fragment.replacingOccurrences(of: input.line, with: input.line.replacingOccurrences(of: original, with: "[[user(locn\(free))]]"))
                let type = input.line.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? "float4"
                added.append("    \(type) _unmatched\(free) [[user(locn\(free))]];\n")
            }
        }
        if !added.isEmpty, let start = vertex.range(of: "struct main0_out\n{\n") {
            vertex.insert(contentsOf: added.joined(), at: start.upperBound)
        }
    }
}

import Foundation
import JavaScriptCore
import ShaderTranslation
@testable import WallpaperCore
import XCTest

/// The scene player's own tests: those written for node (Tests/PlayerTests), run where node is,
/// and Wallpaper Engine's own shaders translated by the player and compiled by glslang, as the
/// native renderer compiles them, mended as the player mends them when refused.
final class PlayerScriptTests: XCTestCase {
    private static var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Shaders glslang refuses when they are translated with no combos at all, and what it says
    /// (2026-11-17). In a scene the material's combos and the engine's own defines are given;
    /// which of them each needs is not yet worked out.
    private static let refusedWithoutCombos: [String: String] = [
        "shaders/chroma4.vert": "'BuildTangentSpace': no matching overloaded function found",
        "shaders/foliage4.vert": "'BuildTangentSpace': no matching overloaded function found",
        "shaders/fur4.vert": "'BuildTangentSpace': no matching overloaded function found",
        "shaders/shadowcasterfoliage4.vert": "'BuildTangentSpace': no matching overloaded function found",
        "shaders/shadowcasterfur4.vert": "'BuildTangentSpace': no matching overloaded function found",
        "shaders/fur4.frag": "'TEX8FORMAT': undeclared identifier",
        "shaders/puppettexturechannels.vert": "'BLENDROWCOUNT': undeclared identifier",
        "shaders/generic.frag": "'ComputeMaterialSpecularPower': no matching overloaded function found",
        "shaders/generic2.frag": "'ComputeMaterialSpecularPower': no matching overloaded function found",
        "shaders/shadowcaster.vert": "'gl_InstanceID': identifiers starting with gl_ are reserved",
        "shaders/volumetricsfront.frag": "syntax error, unexpected IDENTIFIER, expecting COMMA or SEMICOLON",
    ]

    /// The line a compiler's message names: "ERROR: 0:12: …" names 12.
    private static func lineNamed(in message: String) -> String? {
        let pattern = try! NSRegularExpression(pattern: "ERROR: \\d+:(\\d+)")
        guard let match = pattern.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range(at: 1), in: message) else { return nil }
        return String(message[range])
    }

    func testNodeTests() throws {
        let folder = Self.repository.appendingPathComponent("Tests/PlayerTests")
        let tests = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".test.js") }.sorted()
        let finder = Process()
        finder.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        finder.arguments = ["sh", "-lc", "command -v node"]
        let found = Pipe()
        finder.standardOutput = found
        try finder.run()
        finder.waitUntilExit()
        let node = String(decoding: found.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard finder.terminationStatus == 0, !node.isEmpty else { throw XCTSkip("node is not installed: the player's own tests are not run") }
        let run = Process()
        run.executableURL = URL(fileURLWithPath: node)
        run.arguments = ["--test"] + tests.map { folder.appendingPathComponent($0).path }
        let output = Pipe()
        run.standardOutput = output
        run.standardError = output
        try run.run()
        let said = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        run.waitUntilExit()
        XCTAssertEqual(run.terminationStatus, 0, said)
    }

    func testStockShadersCompile() throws {
        let shaders = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Personalization/WallPaperEngine/assets/shaders")
        guard FileManager.default.fileExists(atPath: shaders.path) else {
            throw XCTSkip("Wallpaper Engine is not installed in ~/Documents/Personalization/WallPaperEngine")
        }
        var files: [String: String] = [:]
        let walker = FileManager.default.enumerator(at: shaders, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let relative = url.path.replacingOccurrences(of: shaders.path + "/", with: "")
            files["shaders/" + relative] = text
        }
        let context = try XCTUnwrap(JSContext())
        var thrown: String?
        context.exceptionHandler = { _, exception in thrown = exception?.toString() }
        context.evaluateScript("""
            var window = this;
            var document = { createElement: function () { return { getContext: function () { return null; }, style: {}, addEventListener: function () {} }; },
                             addEventListener: function () {}, body: { appendChild: function () {} } };
            """)
        context.evaluateScript(WallpaperEngineRuntime.source)
        XCTAssertNil(thrown, "the player does not load")
        let engine = try XCTUnwrap(context.objectForKeyedSubscript("WallaeroEngine"))
        let table = JSValue(object: files, in: context)!

        var refused: [String] = []
        var compiled = 0
        for name in files.keys.sorted() where (name.hasSuffix(".frag") || name.hasSuffix(".vert")) && !name.hasPrefix("shaders/HLSL/") {
            let fragment = name.hasSuffix(".frag")
            guard var source = engine.invokeMethod("translate", withArguments: [files[name]!, fragment ? "fragment" : "vertex", [:], table])?.toString() else {
                refused.append("\(name): not translated")
                continue
            }
            // As the player does: what the compiler says of the line it names, mended and tried again.
            var problem: String?
            for _ in 0..<24 {
                guard let said = shader_check(fragment ? 1 : 0, source) else { problem = nil; break }
                let text = String(cString: said)
                free(said)
                problem = text
                let lines = text.split(separator: "\n").map(String.init)
                let first = lines.first.flatMap(Self.lineNamed)
                let ofLine = lines.filter { first != nil && Self.lineNamed(in: $0) == first }
                let mended = engine.invokeMethod("mend", withArguments: [source, ofLine, Int(first ?? "0") ?? 0])
                guard let mended, !mended.isNull, !mended.isUndefined, let next = mended.toString(), next != source else { break }
                source = next
            }
            if let problem { refused.append("\(name): \(problem.split(separator: "\n").first ?? "")") } else { compiled += 1 }
        }
        XCTAssertGreaterThan(compiled, 50)
        let names = Set(refused.map { String($0.prefix { $0 != ":" }) })
        let new = refused.filter { !Self.refusedWithoutCombos.keys.contains(String($0.prefix { $0 != ":" })) }
        XCTAssertTrue(new.isEmpty, "refused by glslang, not refused before:\n" + new.joined(separator: "\n"))
        let mended = Self.refusedWithoutCombos.keys.filter { !names.contains($0) }.sorted()
        XCTAssertTrue(mended.isEmpty, "now compiled, to be taken off refusedWithoutCombos: " + mended.joined(separator: ", "))
    }
}

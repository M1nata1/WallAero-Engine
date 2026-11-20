import XCTest
@testable import WallpaperCore

/// The shared cases of Wallpaper Engine's format (`Tests/Fixtures/we-format`, see
/// docs/we-format.md): what the app works out must be what the player works out.
final class WallpaperEngineFormatTests: XCTestCase {
    static func fixture(_ name: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/we-format/\(name).json")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testCurvesAreWorkedOutAsThePlayerDoes() throws {
        let fixture = try Self.fixture("curves")
        let animations = try XCTUnwrap(fixture["animations"] as? [String: Any])
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 30)
        for each in cases {
            let name = try XCTUnwrap(each["animation"] as? String)
            let animation = try XCTUnwrap(WallpaperEngineAnimation(raw: JSONValue(any: try XCTUnwrap(animations[name]))))
            let base = try XCTUnwrap(each["base"] as? [Double])
            let expected = try XCTUnwrap(each["expected"] as? [Double])
            let got: [Double]
            if let frame = each["frame"] as? Double {
                got = animation.numbers(atFrame: frame, base: base)
            } else {
                got = animation.numbers(atSeconds: try XCTUnwrap(each["seconds"] as? Double), base: base)
            }
            XCTAssertEqual(got.count, expected.count, "\(name) \(each)")
            for (a, b) in zip(got, expected) {
                XCTAssertEqual(a, b, accuracy: 1e-6, "\(name) at \(each["frame"] ?? each["seconds"] ?? "")")
            }
        }
    }
}

/// Wallpaper Engine's JSON files read as written (`WallpaperEngineJSON`).
final class WallpaperEngineJSONTests: XCTestCase {
    func testWhatIsReadIsWrittenAsItCameWithoutSpaces() throws {
        let text = #"{ "b": 1.50, "a": [true, null, -2e3], "s": "x\"yé\\", "b": "again", "o": {} }"#
        let json = try XCTUnwrap(WallpaperEngineJSON(text: text))
        XCTAssertEqual(json.text, #"{"b":1.50,"a":[true,null,-2e3],"s":"x\"yé\\","b":"again","o":{}}"#)
        guard case .object(let members) = json else { return XCTFail() }
        XCTAssertEqual(members.map(\.key), ["b", "a", "s", "b", "o"], "keys in their order, twice if written twice")
        XCTAssertEqual(members[2].value.stringValue, "x\"yé\\")
    }

    func testACommaBeforeTheEndIsPassedOver() throws {
        XCTAssertEqual(WallpaperEngineJSON(text: #"{"a": [1, 2,], "b": {"c": 3,},}"#)?.text, #"{"a":[1,2],"b":{"c":3}}"#)
    }

    func testWhatThePlayerCannotReadDoesNotReadHereEither() {
        for bad in ["{\"a\": 1.}", "{\"a\": +1}", "{\"a\": NaN}", "{\"a\": 01}", "{\"a\": \"x\ny\"}", "{\"a\": 1", "[1 2]", "{} x", "{'a': 1}"] {
            XCTAssertNil(WallpaperEngineJSON(text: bad), bad)
        }
    }

    func testOneMemberIsReadWithoutTheOthers() throws {
        let table = Data(#"{"format":1,"big":{"x":[1,2,{"y":"]}"}]},"files":{"scene.json":"{\"objects\":[]}"},"puppets":{}}"#.utf8)
        let files = try XCTUnwrap(WallpaperEngineJSON.member("files", ofObjectIn: table))
        XCTAssertEqual(files.text, #"{"scene.json":"{\"objects\":[]}"}"#)
        XCTAssertNil(WallpaperEngineJSON.member("nothing", ofObjectIn: table))
    }

    func testTheTableIsReadForThePlayer() throws {
        let table = Data(#"{"format":1,"files":{"scene.json":"{ \"objects\" : [ ], }","shaders/a.frag":"void main() {}"},"puppets":{}}"#.utf8)
        let read = try XCTUnwrap(WallpaperEngineSceneReading.readTable(table))
        XCTAssertEqual(read, #"{"scene.json":"{\"objects\":[]}"}"#, "JSON files only, read")
        XCTAssertEqual(WallpaperEngineSceneReading.read(["scene.json": "{ \"a\":1 }", "x.frag": "{"]), ["scene.json": "{\"a\":1}"])
    }
}

/// Not a test: with WALLAERO_READ_CHECK=<library folder>:<out folder>, writes what is read of every
/// laid-out scene's table to `<out>/<scene>.json`, for Tests/PlayerTests/read-check.js to compare
/// with the files as written.
final class WallpaperEngineReadCheck: XCTestCase {
    func testWriteWhatIsRead() throws {
        guard let asked = ProcessInfo.processInfo.environment["WALLAERO_READ_CHECK"] else { throw XCTSkip("no library asked for") }
        let parts = asked.split(separator: ":").map(String.init)
        let library = URL(fileURLWithPath: parts[0]), out = URL(fileURLWithPath: parts[1])
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var count = 0
        for folder in (try? FileManager.default.contentsOfDirectory(at: library.appendingPathComponent("Web"), includingPropertiesForKeys: nil)) ?? [] {
            guard case .success(let data) = WallpaperEngineSceneData.read(scene: folder), let read = WallpaperEngineSceneReading.readTable(data) else { continue }
            try Data(read.utf8).write(to: out.appendingPathComponent(folder.lastPathComponent + ".json"))
            count += 1
        }
        print("read-check: \(count) scenes")
    }
}

/// The player's table of values left unsaid, read by the app (`WallpaperEngineDefaults`).
final class WallpaperEngineDefaultsTests: XCTestCase {
    func testTheAppReadsThePlayersOwnTable() {
        XCTAssertEqual(WallpaperEngineDefaults.particle("operator", "turbulence", "speedmax")?.numberValue, 200)
        XCTAssertEqual(WallpaperEngineDefaults.particle("operator", "turbulence", "starttime")?.numberValue, 0, "what all operators take")
        XCTAssertEqual(WallpaperEngineDefaults.particle("initializer", "sizerandom", "min")?.numberValue, 20)
        XCTAssertEqual(WallpaperEngineDefaults.particle("emitter", "boxrandom", "rate")?.numberValue, 5)
        XCTAssertEqual(WallpaperEngineDefaults.particle("system", nil, "maxcount")?.numberValue, 100)
        XCTAssertEqual(WallpaperEngineDefaults.particle("initializer", "rotationrandom", "max")?.arrayValue?.last?.numberValue ?? 0, 2 * .pi, accuracy: 1e-12)
        XCTAssertNil(WallpaperEngineDefaults.particle("renderer", "sprite", "x"))
    }
}

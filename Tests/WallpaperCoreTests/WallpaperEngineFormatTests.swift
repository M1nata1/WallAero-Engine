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

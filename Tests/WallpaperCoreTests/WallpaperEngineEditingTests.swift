import XCTest
@testable import WallpaperCore

/// Scenes of Wallpaper Engine's made and changed in the app: the files are written as
/// Wallpaper Engine writes them, and read back as they were written.
final class WallpaperEngineEditingTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = try TestMedia.directory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func pngFile(width: Int = 30, height: Int = 20) throws -> Data {
        let url = root.appendingPathComponent("picture-\(UUID().uuidString).png")
        try TestMedia.writePNG(to: url, size: CGSize(width: width, height: height))
        return try Data(contentsOf: url)
    }

    func testAPictureTextureIsReadBackAsThePictureItHolds() throws {
        let png = try pngFile()
        let data = WallpaperEngineWriter.texture(picture: png, width: 30, height: 20, clamped: true)
        let texture = try XCTUnwrap(WallpaperEngineTexture.texture(from: data))
        XCTAssertEqual(texture.pictures.count, 1)
        XCTAssertEqual(texture.pictures[0].image.width, 30)
        XCTAssertEqual(texture.pictures[0].image.height, 20)
        // Kept whole, so the player writes it out as it is.
        XCTAssertEqual(texture.pictures[0].file?.data, png)
        XCTAssertTrue(texture.isClamped)
        XCTAssertTrue(texture.isSmooth)
        // The canvas has sides that are powers of two, as Wallpaper Engine's have.
        XCTAssertEqual(Array(data[26..<34]), [32, 0, 0, 0, 32, 0, 0, 0])
        XCTAssertFalse(try XCTUnwrap(WallpaperEngineTexture.texture(from: WallpaperEngineWriter.texture(picture: png, width: 30, height: 20,
                                                                                                         clamped: false, smooth: false))).isSmooth)
    }

    func testAVideoTextureHoldsTheVideo() throws {
        // A file that is a row of parts as MP4 files are: its length, a name of four letters.
        var movie = Data([0, 0, 0, 16]) + Data("ftypisom".utf8) + Data(count: 4)
        movie += Data([0, 0, 0, 40]) + Data("free".utf8) + Data(count: 32)
        let data = WallpaperEngineWriter.texture(video: movie, width: 640, height: 360)
        let texture = try XCTUnwrap(WallpaperEngineTexture.texture(from: data))
        XCTAssertEqual(texture.video?.file, movie)
        XCTAssertEqual(texture.video?.width, 640)
        XCTAssertEqual(texture.video?.height, 360)
    }

    func testAPackageIsReadBackFileByFile() throws {
        let files: [(name: String, data: Data)] = [("scene.json", Data("{}".utf8)), ("materials/a.tex", Data([1, 2, 3]))]
        let package = try XCTUnwrap(WallpaperEnginePackage(data: WallpaperEngineWriter.package(files)))
        XCTAssertEqual(package.names, ["scene.json", "materials/a.tex"])
        XCTAssertEqual(package.data(named: "materials/A.tex"), Data([1, 2, 3]))
        XCTAssertEqual(package.data(named: "scene.json"), Data("{}".utf8))
    }

    func testJSONValuesKeepWhatTheyStandBehind() throws {
        let value = try XCTUnwrap(JSONValue(data: Data(#"{"alpha": {"user": "fade", "value": 0.5}, "on": true, "n": 2}"#.utf8)))
        XCTAssertEqual(value["alpha"]?.plain, .number(0.5))
        XCTAssertEqual(value["on"], .bool(true))
        let changed = value["alpha"]!.replacingPlain(with: .number(1))
        XCTAssertEqual(changed["user"], .string("fade"))
        XCTAssertEqual(changed["value"], .number(1))
        XCTAssertEqual(JSONValue.vector([1, 0.5, 0]).vector, [1, 0.5, 0])
        // A whole number is written without a fraction.
        XCTAssertEqual(String(decoding: value["n"]!.data(readable: false), as: UTF8.self), "2")
    }

    func testANewSceneIsWrittenAndReadBack() throws {
        let folder = root.appendingPathComponent("project")
        var document = WallpaperEngineDocument.empty(title: "Test", width: 1920, height: 1080)
        try WallpaperEngineProjectFolder.write(document, previous: nil, to: folder)
        // What was last written, to write only what changed since.
        var written = document

        let source = root.appendingPathComponent("sky.png")
        try pngFile(width: 64, height: 32).write(to: source)
        let picture = try WallpaperEngineProjectFolder.addPicture(source, to: folder)
        XCTAssertEqual(picture.texture, "sky")
        let image = document.addImage(texture: picture.texture, width: picture.width, height: picture.height, name: "Sky")
        let text = document.addText("Hello", name: "Title", under: image)
        try WallpaperEngineProjectFolder.write(document, previous: written, to: folder)
        written = document
        document.update(text) { $0["pointsize"] = .number(40) }
        try WallpaperEngineProjectFolder.write(document, previous: written, to: folder)

        let read = try WallpaperEngineProjectFolder.read(from: folder)
        XCTAssertEqual(read, document)
        XCTAssertEqual(read.objectIDs, [image, text])
        XCTAssertEqual(read.parent(of: text), image)
        XCTAssertEqual(read.children(of: image), [text])
        XCTAssertEqual(WallpaperEngineDocument.kind(of: try XCTUnwrap(read.object(image))), .image)
        XCTAssertEqual(read.material(ofObject: image)?.value["passes"]?[0]?["textures"]?[0], .string("sky"))
        XCTAssertEqual(read.size, CGSize(width: 1920, height: 1080))

        // A second picture of the same name gets a name of its own.
        try pngFile(width: 40, height: 40).write(to: source)
        XCTAssertEqual(try WallpaperEngineProjectFolder.addPicture(source, to: folder).texture, "sky_2")

        // The project opens as a Wallpaper Engine scene, and lays out for the player.
        let project = try XCTUnwrap(WallpaperEngineProject(folder: folder))
        XCTAssertEqual(project.kind, .scene)
        XCTAssertEqual(project.title, "Test")
        let package = try XCTUnwrap(WallpaperEnginePackage(folder: folder))
        let scene = root.appendingPathComponent("scene")
        _ = try WallpaperEngineScene.export(package, into: scene)
        let pictures = scene.appendingPathComponent("engine/tex")
        let laidOut = try FileManager.default.contentsOfDirectory(atPath: pictures.path)
        XCTAssertEqual(laidOut.count, 2)
        // Laid out again, nothing is written anew; a file the scene no longer has goes.
        func dates() throws -> [String: Date] {
            var dates: [String: Date] = [:]
            for name in try FileManager.default.contentsOfDirectory(atPath: pictures.path) {
                dates[name] = try FileManager.default.attributesOfItem(atPath: pictures.appendingPathComponent(name).path)[.modificationDate] as? Date
            }
            return dates
        }
        let before = try dates()
        try FileManager.default.removeItem(at: folder.appendingPathComponent("materials/sky_2.tex"))
        Thread.sleep(forTimeInterval: 1.1)
        _ = try WallpaperEngineScene.export(try XCTUnwrap(WallpaperEnginePackage(folder: folder)), into: scene)
        let after = try dates()
        XCTAssertEqual(after.count, 1)
        let kept = try XCTUnwrap(after.first)
        XCTAssertEqual(before[kept.key], kept.value)
    }

    func testAPictureChosenForASettingIsLaidOutAndKept() throws {
        let scene = root.appendingPathComponent("scene")
        let folder = scene.appendingPathComponent(WallpaperEngineProjectFolder.folderName)
        var document = WallpaperEngineDocument.empty(title: "Test", width: 1920, height: 1080)
        try WallpaperEngineProjectFolder.write(document, previous: nil, to: folder)
        let source = root.appendingPathComponent("sky.png")
        try pngFile(width: 64, height: 32).write(to: source)
        let picture = try WallpaperEngineProjectFolder.addPicture(source, to: folder)
        let image = document.addImage(texture: picture.texture, width: picture.width, height: picture.height, name: "Sky")
        // The picture's material takes the one chosen for the setting "custombg", as Wallpaper
        // Engine's editor writes it.
        let material = try XCTUnwrap(document.material(ofObject: image))
        var value = material.value
        var passes = try XCTUnwrap(value["passes"]?.arrayValue)
        passes[0]["usertextures"] = .array([.string("custombg")])
        value["passes"] = .array(passes)
        document.setFile(material.name, value)
        var general = document.project["general"] ?? .object([:])
        general["properties"] = .object(["custombg": .object(["type": .string("scenetexture"), "text": .string("Custom <b>background</b>"),
                                                               "value": .string(""), "order": .number(100)])])
        document.project["general"] = general
        try WallpaperEngineProjectFolder.write(document, previous: nil, to: folder)

        let project = try XCTUnwrap(WallpaperEngineProject(folder: folder))
        XCTAssertEqual(project.pictureSettingTitles, [.init(name: "custombg", title: "Custom background")])

        func laidOutTextures() throws -> [String] {
            let script = try String(contentsOf: scene.appendingPathComponent("engine/files.js"), encoding: .utf8)
            let json = try XCTUnwrap(script.range(of: "= ").map { String(script[$0.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: ";\n")) })
            let table = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            return ((table["textures"] as? [String: Any]) ?? [:]).keys.sorted()
        }
        try WallpaperEngineProjectFolder.layOut(scene: scene)
        XCTAssertFalse(try laidOutTextures().contains("user/custombg"))

        let chosen = root.appendingPathComponent("mine.png")
        try pngFile(width: 16, height: 16).write(to: chosen)
        try WallpaperEngineProjectFolder.keep(chosen, for: "custombg", scene: scene)
        XCTAssertEqual(Array(WallpaperEngineProjectFolder.chosenPictures(scene: scene).keys), ["custombg"])
        try WallpaperEngineProjectFolder.layOut(scene: scene)
        XCTAssertTrue(try laidOutTextures().contains("user/custombg"))

        // Taken away, the scene's own shows again.
        try WallpaperEngineProjectFolder.keep(nil, for: "custombg", scene: scene)
        XCTAssertTrue(WallpaperEngineProjectFolder.chosenPictures(scene: scene).isEmpty)
        try WallpaperEngineProjectFolder.layOut(scene: scene)
        XCTAssertFalse(try laidOutTextures().contains("user/custombg"))
    }

    func testRemovingAnObjectTakesWhatHangsOnItAlong() {
        var document = WallpaperEngineDocument.empty(title: "", width: 100, height: 100)
        let group = document.addGroup(name: "Group")
        let inner = document.addSolid(color: [1, 0, 0], width: 10, height: 10, name: "Red", under: group)
        let other = document.addSolid(color: [0, 1, 0], width: 10, height: 10, name: "Green")
        _ = document.addText("x", name: "Deep", under: inner)
        document.remove(group)
        XCTAssertEqual(document.objectIDs, [other])

        let copy = document.duplicate(other)
        XCTAssertNotNil(copy)
        XCTAssertNotEqual(copy, other)
        XCTAssertEqual(document.objectIDs, [other, copy!])
        document.reorder([copy!, other])
        XCTAssertEqual(document.objectIDs, [copy!, other])
    }

    func testLightsAreCountedAsWallpaperEngineCountsThem() throws {
        var document = WallpaperEngineDocument.empty(title: "", width: 1920, height: 1080)
        XCTAssertNil(document[general: "lightconfig"])
        let point = document.addLight(.point, name: "Point")
        _ = document.addLight(.point, name: "Point 2")
        _ = document.addLight(.spot, name: "Spot")
        XCTAssertEqual(document[general: "lightconfig"], .object(["point": .number(2), "spot": .number(1)]))
        let light = try XCTUnwrap(document.object(point))
        XCTAssertEqual(light["light"], .string("lpoint"))
        XCTAssertEqual(light["origin"]?.vector, [960, 540, 200])
        document.remove(point)
        document.countLights()
        XCTAssertEqual(document[general: "lightconfig"], .object(["point": .number(1), "spot": .number(1)]))
    }

    func testACameraIsMadeWithItsPathsFile() throws {
        var document = WallpaperEngineDocument.empty(title: "", width: 1920, height: 1080)
        let id = document.addCamera(name: "Camera")
        let camera = try XCTUnwrap(document.object(id))
        XCTAssertEqual(WallpaperEngineDocument.kind(of: camera), .camera)
        XCTAssertEqual(camera["origin"]?.vector, [0, 0, 500])
        let paths = try XCTUnwrap(camera["path"]?.stringValue)
        XCTAssertEqual(document.file(paths), .object(["paths": .array([])]))
    }
}

/// Not a test: with WALLAERO_EFFECT_DEMO set to a folder, lays out there a scene with each of
/// the app's effects on a picture of its own, to be played and looked at.
final class WallpaperEngineEffectDemo: XCTestCase {
    func testMakeDemo() throws {
        guard let path = ProcessInfo.processInfo.environment["WALLAERO_EFFECT_DEMO"] else { throw XCTSkip("no demo folder asked for") }
        let scene = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: scene)
        let project = scene.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        var document = WallpaperEngineDocument.empty(title: "Effects", width: 1600, height: 900)
        let source = scene.appendingPathComponent("tile.png")
        try TestMedia.writePNG(to: source, size: CGSize(width: 360, height: 200))
        let picture = try WallpaperEngineProjectFolder.addPicture(source, to: project)
        for (index, effect) in WallpaperEngineEffect.all.enumerated() {
            let id = document.addImage(texture: picture.texture, width: picture.width, height: picture.height, name: effect.id)
            let column = Double(index % 4), row = Double(index / 4)
            document.update(id) { $0["origin"] = .vector([200 + column * 400, 900 - (112 + row * 225), 0]) }
            try document.addEffect(effect, to: id, projectFolder: project)
        }
        try WallpaperEngineProjectFolder.write(document, previous: nil, to: project)
        try WallpaperEngineProjectFolder.layOut(scene: scene)
    }
}

/// Not a test: with WALLAERO_PARTICLE_DEMO set to a folder, lays out there a scene with each of
/// the app's systems of particles.
final class WallpaperEngineParticleDemo: XCTestCase {
    func testMakeDemo() throws {
        guard let path = ProcessInfo.processInfo.environment["WALLAERO_PARTICLE_DEMO"] else { throw XCTSkip("no demo folder asked for") }
        let scene = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: scene)
        let project = scene.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        var document = WallpaperEngineDocument.empty(title: "Particles", width: 1920, height: 1080)
        document.addSolid(color: [0.08, 0.1, 0.16], width: 1920, height: 1080, name: "Sky")
        let only = ProcessInfo.processInfo.environment["WALLAERO_PARTICLE_ONLY"]
        for preset in WallpaperEngineParticlePreset.all where only == nil || only == preset.id {
            try document.addParticles(preset, projectFolder: project)
        }
        try WallpaperEngineProjectFolder.write(document, previous: nil, to: project)
        try WallpaperEngineProjectFolder.layOut(scene: scene)
    }
}

final class WallpaperEnginePuppetRigTests: XCTestCase {
    private func picture(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Opaque only in the left half.
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        return context.makeImage()!
    }

    func testARigIsWrittenAsWallpaperEngineReadsIt() throws {
        var rig = WallpaperEnginePuppetRig(width: 200, height: 100)
        rig.makeMesh(from: picture(width: 200, height: 100), spacing: 25)
        // Only the opaque half is covered: four squares across, four down.
        XCTAssertEqual(rig.triangles.count, 4 * 4 * 6)
        XCTAssertTrue(rig.points.allSatisfy { $0.x <= 0.001 })
        let root = rig.addBone(at: .init(x: -80, y: 0), parent: nil)
        let arm = rig.addBone(at: .init(x: -20, y: 0), parent: root)
        rig.bones[arm].sway = .init(kind: .hanging)
        var animation = WallpaperEnginePuppetRig.Animation(id: 7, name: "Wave")
        animation.length = 30
        rig.animations = [animation]
        rig.setKey(.init(frame: 0), bone: arm, animation: 0)
        rig.setKey(.init(frame: 30, angle: 0.5), bone: arm, animation: 0)

        let data = rig.mdl(material: "materials/arm.json")
        let read = try XCTUnwrap(WallpaperEnginePuppet(data: data))
        XCTAssertEqual(read.triangles.map(Int.init), rig.triangles)
        XCTAssertEqual(read.bones.map(\.parent), [-1, 0])
        XCTAssertEqual(read.bones.map(\.name), ["Bone 1", "Bone 2"].map { String(format: NSLocalizedString("Bone %d", comment: ""), Int($0.last!.wholeNumberValue!)) })
        XCTAssertEqual(read.bones[1].matrix[12], 60)
        XCTAssertTrue(read.bones[1].physics?.contains("\"re\":true") == true)
        XCTAssertEqual(read.material, "materials/arm.json")
        XCTAssertEqual(read.animations.count, 1)
        let played = read.animations[0]
        XCTAssertEqual(played.id, 7)
        XCTAssertEqual(played.frameCount, 31)
        // The arm's last frame: turned half a radian, where it is at rest.
        let last = (1 * played.frameCount + 30) * 9
        XCTAssertEqual(Double(played.frames[last + 5]), 0.5, accuracy: 1e-6)
        XCTAssertEqual(Double(played.frames[last]), 60, accuracy: 1e-6)
        // Halfway, eased: halfway turned.
        XCTAssertEqual(Double(played.frames[(1 * played.frameCount + 15) * 9 + 5]), 0.25, accuracy: 1e-6)

        // A corner by the arm's tip follows the arm at the end.
        let at30 = rig.posedPoints(animation: 0, frame: 30)
        let rest = rig.points
        let moved = zip(at30, rest).contains { abs($0.x - $1.x) + abs($0.y - $1.y) > 1 }
        XCTAssertTrue(moved)
    }

    func testABoneTiltedAboutXIsSqueezedAndWrittenWhereWallpaperEngineKeepsIt() throws {
        var rig = WallpaperEnginePuppetRig(width: 200, height: 100)
        rig.makeMesh(from: picture(width: 200, height: 100), spacing: 25)
        let root = rig.addBone(at: .init(x: -50, y: 0), parent: nil)
        var animation = WallpaperEnginePuppetRig.Animation(id: 1, name: "Blink")
        animation.length = 10
        rig.animations = [animation]
        rig.setKey(.init(frame: 0), bone: root, animation: 0)
        rig.setKey(.init(frame: 10, tiltX: .pi / 2), bone: root, animation: 0)

        // A quarter turn about x: every corner seen on the bone's line.
        let posed = rig.posedPoints(animation: 0, frame: 10)
        XCTAssertTrue(posed.allSatisfy { abs($0.y) < 1e-6 })
        XCTAssertFalse(rig.points.allSatisfy { abs($0.y) < 1e-6 })

        let read = try XCTUnwrap(WallpaperEnginePuppet(data: rig.mdl(material: "materials/eye.json")))
        let last = 10 * 9
        XCTAssertEqual(Double(read.animations[0].frames[last + 3]), .pi / 2, accuracy: 1e-6)
        XCTAssertEqual(Double(read.animations[0].frames[last + 4]), 0, accuracy: 1e-6)

        // Keys saved before there were tilts have none.
        let old = try JSONDecoder().decode(WallpaperEnginePuppetRig.Key.self, from: Data(#"{"frame":3,"angle":1,"dx":2,"dy":4}"#.utf8))
        XCTAssertEqual(old, .init(frame: 3, angle: 1, dx: 2, dy: 4))
    }
}

/// Not a test: with WALLAERO_PUPPET_DEMO set to a folder, lays out there a scene with a picture
/// bent by three bones that swing.
final class WallpaperEnginePuppetDemo: XCTestCase {
    func testMakeDemo() throws {
        guard let path = ProcessInfo.processInfo.environment["WALLAERO_PUPPET_DEMO"] else { throw XCTSkip("no demo folder asked for") }
        let scene = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: scene)
        let project = scene.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        var document = WallpaperEngineDocument.empty(title: "Puppet", width: 1600, height: 900)
        let source = scene.appendingPathComponent("arm.png")
        try TestMedia.writePNG(to: source, size: CGSize(width: 800, height: 160))
        let picture = try WallpaperEngineProjectFolder.addPicture(source, to: project)
        let id = document.addImage(texture: picture.texture, width: picture.width, height: picture.height, name: "Arm")
        var rig = WallpaperEnginePuppetRig(width: 800, height: 160)
        rig.makeMesh(from: try XCTUnwrap(document.picture(ofObject: id, projectFolder: project)), spacing: 20)
        let a = rig.addBone(at: .init(x: -380, y: 0), parent: nil)
        let b = rig.addBone(at: .init(x: -120, y: 0), parent: a)
        let c = rig.addBone(at: .init(x: 140, y: 0), parent: b)
        _ = rig.addBone(at: .init(x: 390, y: 0), parent: c)
        var animation = WallpaperEnginePuppetRig.Animation(id: 900, name: "Swing")
        animation.length = 60
        animation.mode = "mirror"
        rig.animations = [animation]
        for bone in [a, b, c] {
            rig.setKey(.init(frame: 0, angle: -0.25), bone: bone, animation: 0)
            rig.setKey(.init(frame: 60, angle: 0.25), bone: bone, animation: 0)
        }
        try document.setPuppet(rig, ofObject: id, projectFolder: project)
        try WallpaperEngineProjectFolder.write(document, previous: nil, to: project)
        try WallpaperEngineProjectFolder.layOut(scene: scene)
    }
}

final class WallpaperSceneConversionTests: XCTestCase {
    func testASceneOfTheAppBecomesOneOfWallpaperEngines() async throws {
        let folder = try TestMedia.directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var scene = WallpaperScene(background: .init(kind: .color, source: nil, color: "#203040"))
        var clock = WallpaperScene.Layer(kind: .text, name: "Clock")
        clock.text = "{greeting} {HH}:{mm}"
        clock.x = 50
        clock.y = 25
        clock.fontSize = 10
        clock.color = "#FF8000"
        var box = WallpaperScene.Layer(kind: .shape, name: "Box")
        box.width = 20
        box.height = 10
        box.fill = "#00FF00"
        box.animation = "pulse"
        box.animationDuration = 2
        scene.layers = [box, clock]
        var greeting = WallpaperScene.Variable(kind: .text, title: "Greeting", key: "greeting")
        greeting.text = "Hi"
        scene.variables = [greeting]
        try SceneProject.create(at: folder, scene: scene)
        let code = WallpaperScene(background: .init(kind: .color, source: nil), layers: [WallpaperScene.Layer(kind: .code, name: "Page")])
        XCTAssertFalse(WallpaperSceneConversion.canConvert(code))
        XCTAssertTrue(WallpaperSceneConversion.canConvert(scene))

        try await WallpaperSceneConversion.convert(sceneIn: folder, size: CGSize(width: 1000, height: 500), title: "Mine")
        let document = try WallpaperEngineProjectFolder.read(from: folder.appendingPathComponent("project"))
        XCTAssertEqual(document.title, "Mine")
        XCTAssertEqual(document[general: "clearcolor"]?.vector?.map { ($0 * 255).rounded() }, [32, 48, 64])
        let objects = document.objects
        XCTAssertEqual(objects.count, 2)
        XCTAssertEqual(WallpaperEngineDocument.kind(of: objects[0]), .solid)
        XCTAssertEqual(objects[0]["effects"]?[0]?["file"]?.stringValue, "effects/wallaero/pulse/effect.json")
        let text = objects[1]
        XCTAssertEqual(WallpaperEngineDocument.kind(of: text), .text)
        // A quarter down from the top, in a scene that counts upward.
        XCTAssertEqual(text["origin"]?.vector?[1], 375)
        XCTAssertTrue(text["text"]?["script"]?.stringValue?.contains("export function update") == true)
        XCTAssertEqual(text["text"]?.plain.stringValue, "{greeting} {HH}:{mm}")
        XCTAssertEqual(document.project["general"]?["properties"]?["greeting"]?["type"]?.stringValue, "textinput")
        // Laid out for the player, with the settings as the scene's.
        let laidOut = try SceneProject.read(from: folder)
        XCTAssertEqual(laidOut.background.kind, .engine)
        XCTAssertEqual(laidOut.variables.map(\.property), ["greeting"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("scene.before-wallpaper-engine.json").path))
    }
}

/// Not a test: with WALLAERO_CONVERT_DEMO set to a folder, makes there a scene of the app's own
/// format — a clock and a greeting from a setting — and makes it one of Wallpaper Engine's.
final class WallpaperSceneConversionDemo: XCTestCase {
    func testMakeDemo() async throws {
        guard let path = ProcessInfo.processInfo.environment["WALLAERO_CONVERT_DEMO"] else { throw XCTSkip("no demo folder asked for") }
        let folder = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var scene = WallpaperScene(background: .init(kind: .color, source: nil, color: "#203040"))
        var clock = WallpaperScene.Layer(kind: .text, name: "Clock")
        clock.text = "{greeting} {HH}:{mm}"
        clock.fontSize = 12
        clock.color = "#FFFFFF"
        var box = WallpaperScene.Layer(kind: .shape, name: "Box")
        box.y = 80
        box.width = 30
        box.height = 10
        box.fill = "#FF8000"
        scene.layers = [box, clock]
        var greeting = WallpaperScene.Variable(kind: .text, title: "Greeting", key: "greeting")
        greeting.text = "Привет"
        scene.variables = [greeting]
        try SceneProject.create(at: folder, scene: scene)
        try await WallpaperSceneConversion.convert(sceneIn: folder, size: CGSize(width: 1600, height: 900), title: "Converted")
        // An object that follows a setting: the box shows as a checkbox says.
        let project = folder.appendingPathComponent("project")
        var document = try WallpaperEngineProjectFolder.read(from: project)
        let before = document
        var general = document.project["general"] ?? .object([:])
        var properties = general["properties"] ?? .object([:])
        properties["showbox"] = .object(["type": .string("bool"), "text": .string("Show box"), "value": .bool(false), "order": .number(200)])
        general["properties"] = properties
        document.project["general"] = general
        let box0 = document.objectIDs[0]
        document.update(box0) { $0["visible"] = .object(["user": .string("showbox"), "value": .bool(true)]) }
        try WallpaperEngineProjectFolder.write(document, previous: before, to: project)
        try WallpaperEngineProjectFolder.layOut(scene: folder)
    }
}

final class WallpaperEngineModelPartsTests: XCTestCase {
    /// A model in three dimensions of two parts, as Wallpaper Engine writes one: the number of
    /// parts in the head, then each part with its material, its bounds and its corners.
    private func model() -> Data {
        func int(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        func float(_ value: Float) -> Data { withUnsafeBytes(of: value.bitPattern.littleEndian) { Data($0) } }
        var file = Data("MDLV0023\0".utf8) + int(0xF) + int(1) + int(2)
        for (index, material) in ["materials/models/doll/body.json", "materials/models/doll/hair.json"].enumerated() {
            if index > 0 { file += Data(count: 6) }
            file += Data("\(material)\0".utf8) + int(0)
            for value in [-1, -1, -1, 1, 1, 1] as [Float] { file += float(value) }
            file += int(0xF)
            var corners = Data()
            for place in [(Float(0), Float(0)), (1, 0), (0, 1)] {
                let corner: [Float] = [place.0 + Float(index), place.1, 0, 0, 0, 1, 1, 0, 0, 1, place.0, place.1]
                corner.forEach { corners += float($0) }
            }
            file += int(UInt32(corners.count)) + corners + int(6)
            for corner in [0, 1, 2] as [UInt16] { file += withUnsafeBytes(of: corner.littleEndian) { Data($0) } }
        }
        return file + Data(count: 7)
    }

    func testEveryPartOfAModelIsRead() throws {
        let read = try XCTUnwrap(WallpaperEnginePuppet(data: model()))
        XCTAssertEqual(read.material, "materials/models/doll/body.json")
        XCTAssertEqual(read.solid?.count, 3 * 8)
        XCTAssertEqual(read.pieces.map(\.material), ["materials/models/doll/hair.json"])
        XCTAssertEqual(read.pieces.first?.solid.first, 1)
        XCTAssertEqual(read.pieces.first?.triangles, [0, 1, 2])
        XCTAssertEqual((read.table["pieces"] as? [[String: Any]])?.count, 1)
    }

    func testAModelOfMoreCornersThanTwoBytesCountIsRead() throws {
        // A planet (3509243656's Earth): the lowest bit after the material says the triangles
        // count their corners in four bytes.
        func int(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        func float(_ value: Float) -> Data { withUnsafeBytes(of: value.bitPattern.littleEndian) { Data($0) } }
        var file = Data("MDLV0023\0".utf8) + int(0xF) + int(1) + int(1) + Data("materials/models/earth/surface.json\0".utf8) + int(1)
        for value in [-1, -1, -1, 1, 1, 1] as [Float] { file += float(value) }
        file += int(0xF)
        let count = 65_541
        var corners = Data(capacity: count * 48)
        for index in 0..<count {
            let corner: [Float] = [Float(index % 100) / 100, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0.5, 0.5]
            corner.forEach { corners += float($0) }
        }
        file += int(UInt32(corners.count)) + corners + int(12) + int(0) + int(65_539) + int(65_540) + Data(count: 7)

        let read = try XCTUnwrap(WallpaperEnginePuppet(data: file))
        XCTAssertEqual(read.solid?.count, count * 8)
        XCTAssertEqual(read.wideTriangles, [0, 65_539, 65_540])
        XCTAssertEqual(read.triangles, [])
        XCTAssertNotNil(read.table["wideTriangles"] as? String)
        XCTAssertEqual(read.table["corners"] as? String, "", "not handed on a second time as a picture that bends")
    }
}

/// Not a test: with WALLAERO_CHOOSE_DEMO set to "<scene folder>|<setting>|<picture>", keeps the
/// picture for the setting of that scene and lays the scene out again, to be played and looked at.
final class WallpaperEngineChosenPictureDemo: XCTestCase {
    func testChoose() throws {
        guard let asked = ProcessInfo.processInfo.environment["WALLAERO_CHOOSE_DEMO"] else { throw XCTSkip("no scene asked for") }
        let parts = asked.components(separatedBy: "|")
        guard parts.count == 3 else { throw XCTSkip("expected <scene>|<setting>|<picture>") }
        let scene = URL(fileURLWithPath: parts[0], isDirectory: true)
        try WallpaperEngineProjectFolder.keep(parts[2].isEmpty ? nil : URL(fileURLWithPath: parts[2]), for: parts[1], scene: scene)
        try WallpaperEngineProjectFolder.layOut(scene: scene)
    }
}

final class NativeSceneChoiceTests: XCTestCase {
    /// Only a scene of Wallpaper Engine's with nothing of the app's own on it is drawn natively.
    func testOnlyABareEngineSceneIsPlayedNatively() throws {
        let folder = try TestMedia.directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var scene = WallpaperScene(background: .init(kind: .engine, source: nil))
        try SceneProject.create(at: folder, scene: scene)
        // Not laid out yet: there is nothing to play.
        XCTAssertFalse(SceneProject.isNativelyPlayable(folder))
        let engine = folder.appendingPathComponent(WallpaperEngineScene.folderName)
        try FileManager.default.createDirectory(at: engine, withIntermediateDirectories: true)
        try "window.wallaeroEngineScene = {};".write(to: engine.appendingPathComponent("files.js"), atomically: true, encoding: .utf8)
        XCTAssertTrue(SceneProject.isNativelyPlayable(folder))

        var dimmed = scene
        dimmed.background.brightness = 80
        XCTAssertFalse(SceneProject.isNativelyPlayable(dimmed, in: folder))
        scene.layers = [WallpaperScene.Layer(kind: .text, name: "Clock")]
        XCTAssertFalse(SceneProject.isNativelyPlayable(scene, in: folder))

        try "document.body.style.filter = 'blur(2px)';".write(to: folder.appendingPathComponent("custom.js"), atomically: true, encoding: .utf8)
        XCTAssertFalse(SceneProject.isNativelyPlayable(folder))
    }
}

final class StockFontTests: XCTestCase {
    /// A font a scene names but does not bring is found among the app's own, if it has it.
    func testOpenFontsAreFoundByTheNameScenesGive() {
        XCTAssertNotNil(WallpaperEngineScene.stockFont(named: "fonts/8bitOperatorPlus8-Regular.ttf"))
        XCTAssertNotNil(WallpaperEngineScene.stockFont(named: "fonts/Segment7Standard.otf"))
        XCTAssertNil(WallpaperEngineScene.stockFont(named: "fonts/Atami-Regular.otf"))
    }
}

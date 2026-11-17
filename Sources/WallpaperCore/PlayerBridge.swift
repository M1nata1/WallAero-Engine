import Foundation

// The bridge between the app and the scripts that draw a scene: the one place where the names of
// those scripts' functions are written. Everything the app tells them is a `PlayerCommand`,
// everything it asks them a `PlayerQuery`, and what they tell the app a `PlayerEvent`. Both
// engines take the same ones: the native player (MetalScenePlayer, the scene player in
// JavaScriptCore with its environment) runs a command's `call`, Chromium (WebWallpaperView) its
// `script`.
//
// The names on the other side: the scene player's own table, `WallaeroEngine.api` (Player/api.js),
// which a debug build checks against `PlayerQuery.names` when a scene starts; the native player's
// environment (MetalSceneScripts.environment); the script WebWallpaperView adds to every page; and
// the page of the app's own scenes (SceneProject.runtime, and the editor's SceneEditorScript).

/// A function of a scene's scripts, by its path from the page's global object, with what it is given.
public struct PlayerCall: Equatable, Sendable {
    public let path: [String]
    public let arguments: [JSONValue]

    init(_ path: String, _ arguments: [JSONValue] = []) {
        self.path = path.split(separator: ".").map(String.init)
        self.arguments = arguments
    }

    /// As a script for a page: the function called as a method of what holds it, or nothing done
    /// where the page has no such function; the script's value is what the function returns.
    public var script: String {
        script(arguments: arguments.map(\.text).joined(separator: ","))
    }

    func script(arguments: String) -> String {
        var owners = ["window"]
        for name in path.dropLast() { owners.append(owners.last! + "." + name) }
        let owner = owners.count == 1 ? "window" : owners.dropFirst().joined(separator: " && ")
        let name = path.last ?? ""
        return "(function (o) { var f = o && o.\(name); return typeof f === 'function' ? f.apply(o, [\(arguments)]) : null; })(\(owner))"
    }
}

/// What the page's media is to do; what is nil stays as it was.
public struct PlayerHostSettings: Equatable, Sendable {
    public var rate: Double?
    public var muted: Bool?
    public var volume: Double?
    /// False while the wallpaper is paused.
    public var playing: Bool?

    public init(rate: Double? = nil, muted: Bool? = nil, volume: Double? = nil, playing: Bool? = nil) {
        self.rate = rate
        self.muted = muted
        self.volume = volume
        self.playing = playing
    }

    /// As the page's host takes them.
    public var json: JSONValue {
        var object: [String: JSONValue] = [:]
        if let rate { object["rate"] = .number(rate) }
        if let muted { object["muted"] = .bool(muted) }
        if let volume { object["volume"] = .number(volume) }
        if let playing { object["playing"] = .bool(playing) }
        return .object(object)
    }
}

/// What the app tells a scene's scripts, wanting no answer.
public enum PlayerCommand: Equatable, Sendable {
    // The page's host, in both engines.
    /// How the page's media plays.
    case host(PlayerHostSettings)
    /// The spectrum of what the Mac plays, as Wallpaper Engine hands it to scenes: 128 levels.
    case sound([Float])
    /// What music plays, all of it or where the track has got to (`NowPlaying`).
    case media(JSONValue)
    /// The pointer over the page, in points from its top left: move, down, up or leave (Chromium;
    /// the native player is given `windowEvent`).
    case pointer(kind: String, x: Double, y: Double)
    /// A web wallpaper's own settings, as JSON text, told the way Wallpaper Engine tells them
    /// (`wallpaperPropertyListener.applyUserProperties`; Chromium).
    case userProperties(String)
    /// How many frames a second the page's scripts may draw; 0 leaves it to the screen (Chromium).
    case frameRate(Int)

    // The page of the app's own scenes, and its editor (Chromium).
    /// The scene, as it is being changed, shown without being saved.
    case showScene(JSONValue)
    /// Set before the page's own scripts run: the scene, as JSON text (a page opened from its
    /// file cannot fetch it).
    case pageScene(String)
    /// The Wallpaper Engine scene in the background read again from its files.
    case reloadEngine
    /// The Wallpaper Engine scene in the background as the editor has just written it, with the
    /// other files it changed: what the editor showed while dragging is in the scene now.
    case showEngineScene(scene: String, files: [String: String])
    /// The page's time held, or let play on; and taken to a moment, in seconds.
    case holdPageClock(Bool)
    case pageClockGoTo(Double)
    /// The editor's frame drawn in the Mac's accent color, a CSS color.
    case editorAccent(String)
    /// The editor's selection: a layer of the app's own scene, or none.
    case editorSelect(String?)
    /// The editor's selection: an object of the Wallpaper Engine scene, or none.
    case editorSelectObject(Int?)

    // The native player's environment.
    /// Starts the scene player: the wallpaper's settings, what the editor changed, how the canvas
    /// fills the view (`object-fit`) and where (`object-position`, in percent).
    case start(settings: JSONValue, changes: JSONValue, fit: String, position: Double)
    case stop
    /// The wallpaper's settings, by the names the scene has for them.
    case setProperties(JSONValue)
    /// The settings and what the editor changed; what cannot be shown so is shown by playing anew.
    case editorUpdate(settings: JSONValue?, changes: JSONValue)
    /// The scene file as the editor has just written it.
    case setSceneFile(String)
    /// Other files as the editor has just written them, by the names the player knows them by.
    case setFiles([String: String])
    /// The scene played anew from its files.
    case replay
    /// An event of the page's window: `resize`, or one of the pointer's, with what it carries.
    case windowEvent(String, JSONValue)
    /// A frame, at the page's time in milliseconds.
    case frame(Double)
    /// A timer the scripts set, gone off.
    case timer(Int)
    /// An event of a video or a sound of the scene's.
    case mediaEvent(Int, String)
    /// What the scripts have drawn, handed on.
    case flush
    /// Set before the scene starts: drawn for the lock screen, what is not to be seen there left out.
    case drawsStill
    /// Set before the scene starts: its time is the editor's.
    case followsEditorClock
    /// Set before the scene starts: the date it is told, in milliseconds since 1970, going on only
    /// with the scene's own time.
    case testEpoch(Double)

    /// The function this is, where it is one.
    public var call: PlayerCall? {
        switch self {
        case .host(let settings): return PlayerCall("__wallaeroHost.apply", [settings.json])
        case .sound(let levels): return PlayerCall("__wallaeroHost.sound", [.array(levels.map { .number(Double($0)) })])
        case .media(let message): return PlayerCall("__wallaeroHost.media", [message])
        case .pointer(let kind, let x, let y): return PlayerCall("__wallaeroHost.pointer", [.string(kind), .number(x), .number(y)])
        case .frameRate(let rate): return PlayerCall("__wallaeroDrawing.setFrameRate", [.number(Double(rate))])
        case .showScene(let scene): return PlayerCall("wallaero.setScene", [scene])
        case .reloadEngine: return PlayerCall("wallaero.reloadEngine")
        case .showEngineScene, .pageScene, .userProperties: return nil
        case .holdPageClock(let held): return PlayerCall("__wallaeroClock.hold", [.bool(held)])
        case .pageClockGoTo(let seconds): return PlayerCall("__wallaeroClock.goTo", [.number(seconds)])
        case .editorAccent(let color): return PlayerCall("wallaeroEditor.setAccent", [.string(color)])
        case .editorSelect(let id): return PlayerCall("wallaeroEditor.select", [id.map(JSONValue.string) ?? .null])
        case .editorSelectObject(let id): return PlayerCall("wallaeroEditor.selectObject", [id.map { .number(Double($0)) } ?? .null])
        case .start(let settings, let changes, let fit, let position):
            return PlayerCall("__start", [settings, changes, .string(fit), .number(position)])
        case .stop: return PlayerCall("__player.stop")
        case .setProperties(let settings): return PlayerCall("__player.setProperties", [settings])
        case .editorUpdate(let settings, let changes): return PlayerCall("__editor.update", [settings ?? .null, changes])
        case .setSceneFile(let text): return PlayerCall("__editor.setScene", [.string(text)])
        case .setFiles(let files): return PlayerCall("__editor.setFiles", [.object(files.mapValues(JSONValue.string))])
        case .replay: return PlayerCall("__replay")
        case .windowEvent(let name, let details): return PlayerCall("__dispatchWindow", [.string(name), details])
        case .frame(let now): return PlayerCall("__frame", [.number(now)])
        case .timer(let id): return PlayerCall("__timer", [.number(Double(id))])
        case .mediaEvent(let id, let type): return PlayerCall("__mediaEvent", [.number(Double(id)), .string(type)])
        case .flush: return PlayerCall("__flushAll")
        case .drawsStill, .followsEditorClock, .testEpoch: return nil
        }
    }

    /// As a script for a page.
    public var script: String {
        switch self {
        case .sound(let levels):
            // Written out by hand: this runs for every band, thirty times a second.
            return PlayerCall("__wallaeroHost.sound").script(arguments: Self.levelsText(levels))
        case .showEngineScene(let scene, let files):
            var changed = files
            let call: String
            if changed.isEmpty {
                call = "window.wallaero.setEngineScene(\(JSONValue.string(scene).text))"
            } else {
                changed["scene.json"] = scene
                call = "window.wallaero.setEngineFiles(\(JSONValue.object(changed.mapValues(JSONValue.string)).text))"
            }
            return """
            (function () {
              if (!window.wallaero) return;
              var scene = window.wallaero.scene;
              if (scene && scene.background) scene.background.engine = {};
              \(call);
              window.wallaero.updateEngine();
              if (window.wallaeroEditor && window.wallaeroEditor.refresh) setTimeout(window.wallaeroEditor.refresh, 0);
            })()
            """
        case .pageScene(let json): return "window.wallaeroScene = \(json);"
        case .userProperties(let json):
            return """
            (function (properties) {
              var listener = window.wallpaperPropertyListener;
              if (listener && typeof listener.applyUserProperties === 'function') listener.applyUserProperties(properties);
            })(\(json));
            """
        case .drawsStill: return "window.wallaeroStill = true;"
        case .followsEditorClock: return "window.__wallaeroEditorClock = true;"
        case .testEpoch(let epoch): return "window.__wallaeroTestEpoch = \(JSONValue.number(epoch).text);"
        default: return call?.script ?? ""
        }
    }

    /// Levels in thousandths, as a JavaScript array's items.
    static func levelsText(_ levels: [Float]) -> String {
        var text = "["
        text.reserveCapacity(levels.count * 6 + 2)
        for (index, level) in levels.enumerated() {
            if index > 0 { text.append(",") }
            let thousandths = Int((min(level, 1) * 1000).rounded())
            if thousandths <= 0 {
                text.append("0")
            } else if thousandths >= 1000 {
                text.append("1")
            } else {
                text.append("0.")
                text.append(contentsOf: String(1000 + thousandths).dropFirst())
            }
        }
        text.append("]")
        return text
    }
}

/// A question to the scene player, `WallaeroEngine.api` in Player/api.js, and what its answer is.
/// The native player asks it through its environment's `__editor.call`, which hands the answer
/// back as JSON; null is no answer.
public struct PlayerQuery<Answer: Decodable>: Sendable {
    public let name: String
    public let arguments: [JSONValue]

    init(_ name: String, _ arguments: [JSONValue] = []) {
        self.name = name
        self.arguments = arguments
    }

    /// The function the native player's environment answers it with: the name and the arguments.
    public var call: PlayerCall { PlayerCall("__editor.call", [.string(name)] + arguments) }

    /// The answer, from the JSON the player gave; nil for none.
    public func answer(_ json: String?) -> Answer? {
        guard let json, json != "null", json != "undefined", let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Answer.self, from: data)
    }
}

/// Every name of `WallaeroEngine.api`: a debug build checks the player's own list against it.
public enum PlayerQueries {
    public static let names: Set<String> = [
        "describe", "hit", "outline", "placeAt", "bones", "cameraView", "cameraPlacing", "checkScript", "scriptDeclares",
        "scriptReport", "curveValue", "seek", "time", "goTo", "holdClock", "paintTexture", "puppet", "holdPuppet", "setView",
        "report", "loading",
    ]

    /// The script that has the native player's environment say the names of its table.
    public static let namesScript = "JSON.stringify(Object.keys((window.WallaeroEngine && window.WallaeroEngine.api) || {}))"

    /// What is wrong with the player's list, said for whoever reads the log; nil when it matches.
    public static func mismatch(_ json: String?) -> String? {
        guard let data = json?.data(using: .utf8), let said = try? JSONDecoder().decode([String].self, from: data) else {
            return "the scene player does not say what it answers (WallaeroEngine.api)"
        }
        let theirs = Set(said)
        let missing = names.subtracting(theirs).sorted(), unknown = theirs.subtracting(names).sorted()
        guard !missing.isEmpty || !unknown.isEmpty else { return nil }
        return "the scene player and PlayerBridge.swift differ: the player lacks \(missing), the app does not know \(unknown)"
    }
}

/// A place: what the player says of an object as it is shown, in points of the page.
public struct PlayerOutline: Decodable, Sendable {
    public let middle: [Double]?
    public let size: [Double]?
    public let corners: [[Double]]?
    public let visible: Bool?
}

/// Where a camera stands and how it is turned to look as an eye does.
public struct PlayerCameraPlacing: Decodable, Sendable {
    public let origin: [Double]
    public let angles: [Double]
}

/// What is wrong with a script: what was said, at which line, and while doing what.
public struct PlayerScriptProblem: Decodable, Sendable {
    public let message: String?
    public let line: Int?
    public let during: String?
}

/// What went wrong with the scene's scripts, by their text, and what they wrote since last asked.
public struct PlayerScriptReport: Decodable, Sendable {
    public let errors: [String: PlayerScriptProblem]?
    public let log: [String]?
}

public extension PlayerQuery where Answer == JSONValue {
    /// The scene's objects and what they are, as the editor shows them.
    static var describe: Self { .init("describe") }
    /// What the scene's camera shows now.
    static var cameraView: Self { .init("cameraView") }
    /// The settings a script declares.
    static func scriptDeclares(_ text: String) -> Self { .init("scriptDeclares", [.string(text)]) }
    /// A picture's mesh and bones as they are edited; nil table makes it a plain picture.
    static func puppet(_ id: Int, table: JSONValue?, layers: JSONValue?) -> Self {
        .init("puppet", [.number(Double(id)), table ?? .null, layers ?? .null])
    }
    /// Holds a picture's bones where the editor has them, or lets them play again.
    static func holdPuppet(_ id: Int, poses: [[Double]]?) -> Self {
        .init("holdPuppet", [.number(Double(id)), poses.map { .array($0.map { .array($0.map(JSONValue.number)) }) } ?? .null])
    }
    /// How the editor looks at the scene: freely or through its camera, from its own eye.
    static func setView(_ said: JSONValue) -> Self { .init("setView", [said]) }
    /// Has the animations show a moment, in seconds, also while paused; nil lets them go on.
    static func seek(_ seconds: Double?) -> Self { .init("seek", [seconds.map(JSONValue.number) ?? .null]) }
}

public extension PlayerQuery where Answer == Int {
    /// The object at a point of the page, if any.
    static func hit(x: Double, y: Double) -> Self { .init("hit", [.number(x), .number(y)]) }
    /// How many of the scene's pictures and files are still coming.
    static var loading: Self { .init("loading") }
}

public extension PlayerQuery where Answer == PlayerOutline {
    static func outline(_ id: Int) -> Self { .init("outline", [.number(Double(id))]) }
}

public extension PlayerQuery where Answer == [Double] {
    /// Where an object would stand for its middle to be at a point of the page.
    static func placeAt(_ id: Int, x: Double, y: Double) -> Self { .init("placeAt", [.number(Double(id)), .number(x), .number(y)]) }
    /// What the player works out of an animation at a moment, from a value.
    static func curveValue(_ animation: JSONValue, seconds: Double, base: [Double]) -> Self {
        .init("curveValue", [animation, .number(seconds), .array(base.map(JSONValue.number))])
    }
}

public extension PlayerQuery where Answer == [[Double]] {
    /// How a picture's bones stand: six numbers each, an affine transform; at rest or as shown.
    static func bones(_ id: Int, atRest: Bool = false) -> Self { .init("bones", [.number(Double(id)), .bool(atRest)]) }
}

public extension PlayerQuery where Answer == PlayerCameraPlacing {
    /// Where a camera object stands to look from an eye at a point, with its up.
    static func cameraPlacing(eye: [Double], center: [Double], up: [Double]) -> Self {
        .init("cameraPlacing", [.array(eye.map(JSONValue.number)), .array(center.map(JSONValue.number)), .array(up.map(JSONValue.number))])
    }
}

public extension PlayerQuery where Answer == PlayerScriptProblem {
    /// What is wrong with the text of a script, without running it; no answer when nothing is.
    static func checkScript(_ text: String) -> Self { .init("checkScript", [.string(text)]) }
}

public extension PlayerQuery where Answer == PlayerScriptReport {
    static var scriptReport: Self { .init("scriptReport") }
}

public extension PlayerQuery where Answer == Double {
    /// The scene's moment, in seconds.
    static var time: Self { .init("time") }
}

public extension PlayerQuery where Answer == Bool {
    /// Takes the scene on to a moment; false for one gone by.
    static func goTo(_ seconds: Double) -> Self { .init("goTo", [.number(seconds)]) }
    /// Holds the scene's time where it is, or lets it play on.
    static func holdClock(_ held: Bool) -> Self { .init("holdClock", [.bool(held)]) }
    /// New pixels for a texture: the native player hands the pixels themselves after these.
    static func paintTexture(_ name: String, width: Int) -> Self { .init("paintTexture", [.string(name), .number(Double(width))]) }
}

public extension PlayerQuery where Answer == String {
    /// What the player says of itself, as JSON: frames drawn, notes, and so on.
    static var report: Self { .init("report") }
}

/// What a scene's scripts tell the app. The native player's environment calls `__native.<name>`;
/// a page in Chromium posts to `window.webkit.messageHandlers.<handler>`.
public enum PlayerEvent: String, CaseIterable, Sendable {
    /// A script of the scene listens to the Mac's sound, or no longer does.
    case listensToSound
    /// A script of the scene wants to know what music plays, or no longer does.
    case listensToMedia
    /// The scene was played anew and can say what it has.
    case engineStarted
    /// The scripts have something to draw: a frame is wanted.
    case wantFrame
}

/// The names the native player's environment (MetalSceneScripts.environment) shares with the
/// player's Swift side.
public enum PlayerEnvironment {
    /// Where the Swift side's functions are: `PlayerEvent`s, and what the environment's DOM and
    /// WebGL are made of.
    public static let native = "__native"
    /// The page's size in points, and pixels to a point: `width`, `height`, `ratio`.
    public static let size = "__size"
    /// What a video, sound or picture element of the environment is known by on the Swift side.
    public static let handle = "__handle"
}

/// The handlers a page in Chromium posts its messages to.
public enum PageMessages {
    /// The host's: what the page listens to, when it is ready.
    public static let host = "wallaeroHost"
    /// The editor's script's, and the page clock's.
    public static let editor = "wallaeroEditor"
}

extension JSONValue: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let flag = try? container.decode(Bool.self) {
            self = .bool(flag)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let text = try? container.decode(String.self) {
            self = .string(text)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }
}

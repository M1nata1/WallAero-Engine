import Foundation

/// The files of one of Wallpaper Engine's own scenes. They come in one file, `scene.pkg` — a
/// list of names with the place of each, then the files one after another — or, for a scene
/// still being worked on, loose in the wallpaper's folder.
///
/// Such a file comes from the web. Nothing in it is trusted: every place it names is checked
/// against the file's length, and names are only ever looked up, never written to disk.
struct WallpaperEnginePackage {
    static let fileName = "scene.pkg"

    /// The names of the files, as the scene writes them.
    let names: [String]
    private let read: (String) -> Data?

    /// The scene of a wallpaper's folder; nil when the folder has none that can be read.
    init?(folder: URL) {
        let packed = folder.appendingPathComponent(Self.fileName)
        if let data = try? Data(contentsOf: packed, options: .mappedIfSafe) {
            self.init(data: data)
        } else {
            self.init(looseFilesIn: folder)
        }
    }

    init?(data: Data) {
        var reader = BinaryReader(data)
        // "PKGV0001" and the like; the files are laid out the same in every version met.
        guard let version = reader.text(), version.hasPrefix("PKGV"),
              let count = reader.uint32(), count <= 200_000
        else {
            return nil
        }
        var places: [(name: String, offset: Int, length: Int)] = []
        for _ in 0..<count {
            guard let name = reader.text(), let offset = reader.uint32(), let length = reader.uint32() else { return nil }
            places.append((name, Int(offset), Int(length)))
        }
        let start = reader.offset
        var ranges: [String: Range<Int>] = [:]
        for place in places {
            let from = start + place.offset
            guard from <= data.count, place.length <= data.count - from else { return nil }
            ranges[Self.key(place.name)] = from..<(from + place.length)
        }
        names = places.map(\.name)
        let base = data.startIndex
        read = { name in
            ranges[Self.key(name)].map { data.subdata(in: (base + $0.lowerBound)..<(base + $0.upperBound)) }
        }
    }

    private init?(looseFilesIn folder: URL) {
        let files = FileManager.default
        guard files.fileExists(atPath: folder.appendingPathComponent("scene.json").path) else { return nil }
        // Paths compared as they really are: a folder may be reached through a link.
        let root = folder.standardizedFileURL.resolvingSymlinksInPath().path
        names = (files.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
            .map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
            .filter { $0.hasPrefix(root + "/") }
            .map { String($0.dropFirst(root.count + 1)) }
        read = { name in
            let name = name.replacingOccurrences(of: "\\", with: "/")
            // A name that leads out of the folder is not followed.
            guard Archive.staysInside(name) else { return nil }
            return try? Data(contentsOf: folder.appendingPathComponent(name), options: .mappedIfSafe)
        }
    }

    func data(named name: String) -> Data? {
        read(name)
    }

    /// A file that holds JSON, as the dictionary in it.
    func json(named name: String) -> [String: Any]? {
        data(named: name).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
    }

    /// Wallpaper Engine is a Windows program: names differ neither by case nor by the slash.
    private static func key(_ name: String) -> String {
        name.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}

/// Reads numbers and texts off a file made on Windows — the low byte first — and gives nil
/// instead of going past the end.
struct BinaryReader {
    private let data: Data
    private(set) var offset = 0

    init(_ data: Data) {
        self.data = data
    }

    var isAtEnd: Bool { offset >= data.count }

    mutating func bytes(_ count: Int) -> Data? {
        guard count >= 0, count <= data.count - offset else { return nil }
        let from = data.startIndex + offset
        offset += count
        return data.subdata(in: from..<(from + count))
    }

    mutating func uint32() -> UInt32? {
        guard let four = bytes(4) else { return nil }
        return four.enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
    }

    mutating func int32() -> Int? {
        uint32().map { Int(Int32(bitPattern: $0)) }
    }

    /// A number with a fraction, in four bytes.
    mutating func float() -> Double? {
        float32().map(Double.init)
    }

    mutating func float32() -> Float? {
        uint32().map { Float(bitPattern: $0) }
    }

    mutating func uint16() -> UInt16? {
        guard let two = bytes(2) else { return nil }
        return UInt16(two[two.startIndex]) | UInt16(two[two.startIndex + 1]) << 8
    }

    /// Passes over bytes that are not wanted; false if there are not that many.
    mutating func skip(_ count: Int) -> Bool {
        guard count >= 0, count <= data.count - offset else { return false }
        offset += count
        return true
    }

    /// Goes on reading from another place of the data, counted from its start; false if it has no such place.
    mutating func seek(to place: Int) -> Bool {
        guard place >= 0, place <= data.count else { return false }
        offset = place
        return true
    }

    /// A text with its length before it.
    mutating func text() -> String? {
        guard let length = uint32(), length <= 4096, let raw = bytes(Int(length)) else { return nil }
        return String(data: raw, encoding: .utf8)
    }

    /// A text that ends with a zero byte, as the marks inside a texture do.
    mutating func textToZero(atMost limit: Int = 64) -> String? {
        var raw = Data()
        while raw.count <= limit {
            guard let byte = bytes(1)?.first else { return nil }
            if byte == 0 {
                return String(data: raw, encoding: .utf8)
            }
            raw.append(byte)
        }
        return nil
    }
}

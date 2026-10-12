import Foundation

/// Unpacks .zip archives with the tools that come with macOS.
public enum Archive {
    /// More than this unpacked is not a wallpaper but a mistake, or an archive made to fill the disk.
    static let largestUnpackedSize: Int64 = 20 * 1024 * 1024 * 1024

    public static func isArchive(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "zip"
    }

    /// Unpacks the archive into `folder`, which is created. What an archive from the web may
    /// carry besides files is left out: nothing is written outside the folder, and links to
    /// other places are removed.
    public static func unpack(_ archive: URL, into folder: URL) throws {
        let names = try run("/usr/bin/zipinfo", ["-1", archive.path]).split(separator: "\n").map(String.init)
        guard !names.isEmpty, names.allSatisfy(staysInside) else {
            throw ImportError.unreadableArchive
        }
        // The last line of the listing: "78 files, 8270573 bytes uncompressed, …".
        let total = try run("/usr/bin/zipinfo", ["-t", archive.path])
        if let size = total.components(separatedBy: " files, ").last?.split(separator: " ").first.flatMap({ Int64($0) }),
           size > largestUnpackedSize {
            throw ImportError.unreadableArchive
        }

        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try run("/usr/bin/ditto", ["-x", "-k", archive.path, folder.path])
        let links = files.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey])?
            .compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true } ?? []
        for link in links {
            try? files.removeItem(at: link)
        }
    }

    /// Whether a file named so in an archive lands inside the folder the archive is unpacked into.
    static func staysInside(_ name: String) -> Bool {
        !name.hasPrefix("/") && !name.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    private static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw ImportError.unreadableArchive
        }
        // Read before waiting: a long listing would fill the pipe and the tool would never finish.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ImportError.unreadableArchive
        }
        return String(decoding: data, as: UTF8.self)
    }
}

import Foundation

/// Unpacks archives with the tools that come with macOS: .zip, and the .rar and .7z that sites
/// with wallpapers also hand out.
public enum Archive {
    /// More than this unpacked is not a wallpaper but a mistake, or an archive made to fill the disk.
    static let largestUnpackedSize: Int64 = 20 * 1024 * 1024 * 1024
    /// The endings of the archives that are unpacked.
    public static let fileExtensions = ["zip", "rar", "7z"]

    public static func isArchive(_ url: URL) -> Bool {
        fileExtensions.contains(url.pathExtension.lowercased())
    }

    /// Unpacks the archive into `folder`, which is created. What an archive from the web may
    /// carry besides files is left out: nothing is written outside the folder, and links to
    /// other places are removed.
    /// - Parameter progress: how far it has come, from 0 to 1, by the bytes unpacked so far.
    public static func unpack(_ archive: URL, into folder: URL, progress: @escaping (Double) -> Void = { _ in }) throws {
        let isZip = archive.pathExtension.lowercased() == "zip"
        let names = try (isZip ? run("/usr/bin/zipinfo", ["-1", archive.path]) : run("/usr/bin/bsdtar", ["-tf", archive.path]))
            .split(separator: "\n").map(String.init)
        guard !names.isEmpty, names.allSatisfy(staysInside) else {
            throw ImportError.unreadableArchive
        }
        var size: Int64?
        if isZip {
            // The last line of the listing: "78 files, 8270573 bytes uncompressed, …".
            let total = try run("/usr/bin/zipinfo", ["-t", archive.path])
            size = total.components(separatedBy: " files, ").last?.split(separator: " ").first.flatMap { Int64($0) }
        } else {
            // A line to a file, as `ls -l` has them: the size is the fifth thing in it.
            size = try run("/usr/bin/bsdtar", ["-tvf", archive.path]).split(separator: "\n").reduce(Int64(0)) { sum, line in
                let fields = line.split(separator: " ", omittingEmptySubsequences: true)
                return sum + (fields.count > 4 ? Int64(fields[4]) ?? 0 : 0)
            }
        }
        if let size, size > largestUnpackedSize {
            throw ImportError.unreadableArchive
        }

        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let process = Process()
        if isZip {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archive.path, folder.path]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
            process.arguments = ["-xf", archive.path, "-C", folder.path, "--no-same-owner", "--no-same-permissions"]
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        // How much is out of the archive, looked at now and then while it is unpacked.
        while process.isRunning {
            Thread.sleep(forTimeInterval: 0.25)
            if let size, size > 0 {
                progress(min(1, Double(Self.size(of: folder)) / Double(size)))
            }
        }
        guard process.terminationStatus == 0 else { throw ImportError.unreadableArchive }
        progress(1)
        let links = files.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey])?
            .compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true } ?? []
        for link in links {
            try? files.removeItem(at: link)
        }
    }

    /// How many bytes the files of a folder hold.
    static func size(of folder: URL) -> Int64 {
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let url = walker?.nextObject() as? URL {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    /// Whether a file named so in an archive lands inside the folder the archive is unpacked into.
    public static func staysInside(_ name: String) -> Bool {
        !name.hasPrefix("/") && !name.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    private static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        // An app has no language of its own for the tools it runs, and without one bsdtar
        // gives up on names that are not plain Latin letters.
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "en_US.UTF-8"
        process.environment = environment
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

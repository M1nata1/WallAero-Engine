import Darwin
import Foundation
import os

/// Valve's console client, the one way to get a Workshop item's files outside Steam. It is not
/// open source and may not be handed on with the app, so the app fetches it from Valve the first
/// time it is needed. Its own home folder keeps its sign-in apart from the Steam app's, which
/// would otherwise overwrite it.
public struct SteamCMD: Sendable {
    public static let installerURL = URL(string: "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz")!

    fileprivate static let log = Logger(subsystem: "com.fadevec.WallAeroEngine", category: "SteamCMD")

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    private var home: URL { folder.appendingPathComponent("home", isDirectory: true) }
    /// Where it puts what it downloads. Nothing in there outlives the import.
    public var downloadsURL: URL { folder.appendingPathComponent("Downloads", isDirectory: true) }

    /// Valve's script that starts the program, and starts it again whenever it has updated
    /// itself: the first time it does that, what the archive holds is replaced altogether.
    private var script: URL { folder.appendingPathComponent("steamcmd.sh") }

    public var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: script.path) }

    /// The folder of an item it has downloaded.
    public func itemFolder(_ id: String) -> URL {
        downloadsURL.appendingPathComponent("steamapps/workshop/content/\(SteamWorkshop.appID)/\(id)", isDirectory: true)
    }

    /// Fetches the program from Valve. It fetches the rest of itself when first started.
    public func install() async throws {
        let (archive, _) = try await URLSession.shared.download(from: Self.installerURL)
        defer { try? FileManager.default.removeItem(at: archive) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", archive.path, "-C", folder.path]
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0, isInstalled else { throw CocoaError(.fileReadCorruptFile) }
    }

    /// Forgets the account: the program's whole home folder goes, and it makes itself a new one.
    public func forgetAccount() {
        try? FileManager.default.removeItem(at: home)
    }

    public func emptyDownloads() {
        try? FileManager.default.removeItem(at: downloadsURL)
    }

    /// Signs in, leaving the account remembered by the program.
    public func signIn(account: String) throws -> Run {
        try start(["+login", account, "+quit"])
    }

    /// Downloads items into `downloadsURL`. A Windows machine's files are the ones wallpapers
    /// have, so that is the kind of machine the program is told it is on.
    public func download(_ ids: [String], account: String, app: String = SteamWorkshop.appID) throws -> Run {
        try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
        let items = ids.flatMap { ["+workshop_download_item", app, $0] }
        return try start(["+@sSteamCmdForcePlatformType", "windows", "+force_install_dir", downloadsURL.path,
                          "+login", account] + items + ["+quit"])
    }

    func start(_ arguments: [String]) throws -> Run {
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        return try Run(script: script, arguments: arguments, directory: folder, environment: environment)
    }

    /// What the program says along the way.
    public enum Event: Equatable, Sendable {
        /// It is updating itself, so far by the percentage given.
        case updating(Int)
        case needsPassword
        case needsCode(Code)
        /// It waits for the sign-in to be confirmed in the Steam app on a phone.
        case needsConfirmation
        case signedIn
        /// Steam refused the sign-in, for the reason it gave. It may yet ask for a code.
        case signInRefused(String)
        case downloaded(String)
        case downloadFailed(id: String, reason: String)
        /// The program has ended. The last event of a run.
        case finished
    }

    /// Where a Steam Guard code is to be found.
    public enum Code: Sendable {
        case email
        case authenticator
    }

    /// One start of the program, with the terminal it thinks it is in. The terminal is a real one,
    /// with nothing shown of what is typed, as the program works best at one. What it prints is
    /// not kept anywhere.
    public final class Run: @unchecked Sendable {
        public let events: AsyncStream<Event>
        private let continuation: AsyncStream<Event>.Continuation
        private let process = Process()
        private let master: Int32
        /// What the program had written by the time it was signed in.
        private let writtenBefore = OSAllocatedUnfairLock<Int64?>(initialState: nil)

        init(script: URL, arguments: [String], directory: URL, environment: [String: String]) throws {
            var master: Int32 = -1, slave: Int32 = -1
            guard openpty(&master, &slave, nil, nil, nil) == 0 else { throw POSIXError(.ENOTTY) }
            var settings = termios()
            tcgetattr(slave, &settings)
            settings.c_lflag &= ~tcflag_t(ECHO)
            tcsetattr(slave, TCSANOW, &settings)
            self.master = master
            (events, continuation) = AsyncStream.makeStream(of: Event.self)
            process.executableURL = script
            process.arguments = arguments
            process.currentDirectoryURL = directory
            process.environment = environment
            let terminal = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
            process.standardInput = terminal
            process.standardOutput = terminal
            process.standardError = terminal
            // With no end of it left open, reading the other end stops.
            process.terminationHandler = { ended in
                SteamCMD.log.notice("ended: reason \(ended.terminationReason.rawValue), status \(ended.terminationStatus)")
                close(slave)
            }
            do {
                try process.run()
            } catch {
                close(slave)
                close(master)
                continuation.finish()
                throw error
            }
            DispatchQueue.global(qos: .userInitiated).async { [self] in readOutput() }
        }

        /// Types a line, as a password or a code is typed.
        public func send(_ line: String) {
            let bytes = Array((line + "\n").utf8)
            _ = bytes.withUnsafeBytes { write(master, $0.baseAddress, $0.count) }
        }

        /// Stops the program. The script only waits for it and would not pass the word on.
        public func cancel() {
            guard process.isRunning else { return }
            children.forEach { kill($0, SIGTERM) }
            process.terminate()
        }

        /// The processes the script has started.
        private var children: [pid_t] {
            var children = [pid_t](repeating: 0, count: 8)
            let found = proc_listchildpids(process.processIdentifier, &children,
                                           Int32(children.count * MemoryLayout<pid_t>.size))
            return children.prefix(Int(max(found, 0))).filter { $0 > 0 }
        }

        /// How much the program has written since it signed in, in bytes: nearly all of that is
        /// what it downloads. The files say nothing of this, since Steam gives them their full
        /// size before the first byte arrives.
        public var bytesDownloaded: Int64 {
            guard let before = writtenBefore.withLock({ $0 }) else { return 0 }
            return max(0, bytesWritten - before)
        }

        private var bytesWritten: Int64 {
            guard process.isRunning else { return 0 }
            return children.reduce(0) { sum, child in
                var usage = rusage_info_v4()
                let result = withUnsafeMutablePointer(to: &usage) {
                    $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(child, RUSAGE_INFO_V4, $0) }
                }
                return result == 0 ? sum + Int64(usage.ri_logical_writes) : sum
            }
        }

        private func readOutput() {
            var output = Output()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = read(master, &buffer, buffer.count)
                // A signal to the app breaks off the waiting, and is no end of anything: closing
                // the terminal then would take the program down with it.
                if count < 0, errno == EINTR {
                    continue
                }
                guard count > 0 else { break }
                for event in output.append(String(decoding: buffer[..<count], as: UTF8.self)) {
                    if case .signedIn = event {
                        let written = bytesWritten
                        writtenBefore.withLock { $0 = written }
                    }
                    continuation.yield(event)
                }
            }
            SteamCMD.log.notice("last said: \(output.lastLine, privacy: .public)")
            close(master)
            continuation.yield(.finished)
            continuation.finish()
        }
    }

    /// Makes events out of what the program prints. A question ends with no new line, so what
    /// has come of a line so far is looked at too.
    struct Output {
        private var line = ""
        /// The last whole line, to tell how a run ended. A password is not shown, so not in it.
        private(set) var lastLine = ""

        mutating func append(_ text: String) -> [Event] {
            var events: [Event] = []
            for character in text {
                if character.isNewline {
                    events += Self.events(inLine: line)
                    if !line.isEmpty {
                        lastLine = line
                    }
                    line = ""
                } else {
                    line.append(character)
                }
            }
            let asked = line.trimmingCharacters(in: .whitespaces).lowercased()
            if asked.hasSuffix("password:") {
                events.append(.needsPassword)
                line = ""
            } else if asked.hasSuffix("steam guard code:") {
                events.append(.needsCode(.email))
                line = ""
            } else if asked.hasSuffix("two-factor code:") {
                events.append(.needsCode(.authenticator))
                line = ""
            }
            return events
        }

        private static func events(inLine line: String) -> [Event] {
            if let id = first(#"Success\. Downloaded item (\d+)"#, in: line) {
                return [.downloaded(id[0])]
            }
            if let failure = first(#"Download item (\d+) failed \(([^)]*)\)"#, in: line) {
                return [.downloadFailed(id: failure[0], reason: failure[1])]
            }
            if let percent = first(#"\[\s*(\d+)%\]\s*Download"#, in: line), let value = Int(percent[0]) {
                return [.updating(value)]
            }
            if line.localizedCaseInsensitiveContains("confirm the login in the Steam Mobile app") {
                return [.needsConfirmation]
            }
            if line.hasPrefix("Waiting for user info"), line.hasSuffix("OK") {
                return [.signedIn]
            }
            if let reason = first(#"(?:FAILED|ERROR)[^()]*\(([^)]+)\)"#, in: line) ?? first(#"FAILED login with result code (.+)$"#, in: line) {
                return [.signInRefused(reason[0].trimmingCharacters(in: .whitespaces))]
            }
            return []
        }

        /// The groups of the first match of a pattern.
        private static func first(_ pattern: String, in line: String) -> [String]? {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
            else {
                return nil
            }
            return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: line).map { String(line[$0]) } }
        }
    }
}

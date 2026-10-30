import Foundation
import WallpaperCore

/// The Steam Workshop as the app shows it: what is listed, the account, and the wallpapers on
/// their way into the library. Downloading is only ever what the user clicked, one at a time:
/// Steam's terms have no room for anything that fetches on its own. The password goes straight
/// to SteamCMD and is not kept, and a sign-in Steam refused is never tried again by itself: too
/// many of those and Steam locks the account out for a while.
@MainActor
final class WorkshopStore: ObservableObject {
    enum SignIn: Equatable {
        case idle
        case working
        /// SteamCMD is updating itself, so far by the percentage given.
        case updating(Int)
        case needsCode(SteamCMD.Code)
        case needsConfirmation
    }

    struct Download: Identifiable {
        enum Phase: Equatable {
            case waiting
            case downloading(Double)
            case adding
        }

        let item: SteamWorkshop.Item
        var phase = Phase.waiting
        var id: String { item.id }
    }

    private static let accountKey = "steamAccount"

    @Published var query = SteamWorkshop.Query()
    @Published private(set) var items: [SteamWorkshop.Item] = []
    @Published private(set) var isLoading = false
    @Published private(set) var cannotLoad = false
    /// The account SteamCMD is signed in to, as far as is known.
    @Published private(set) var account: String?
    @Published private(set) var signIn = SignIn.idle
    @Published var showsSignIn = false
    @Published var signInError: String?
    @Published private(set) var downloads: [Download] = []
    @Published var downloadError: String?

    let previews = SteamWorkshopPreviews(folder: SteamWorkshopPreviews.defaultFolder)
    private let steam: SteamCMD
    private let library: WallpaperLibrary
    private let importer: ImportCoordinator
    private let defaults: UserDefaults?
    private var reachedEnd = false
    private var loading: Task<Void, Never>?
    private var signInRun: SteamCMD.Run?
    private var downloadRun: SteamCMD.Run?
    private var isDownloading = false
    /// Whether the user stopped the download under way.
    private var cancelledDownload = false

    /// Without defaults no account is read or remembered: the screenshot helper works that way,
    /// next to the copy in use.
    init(library: WallpaperLibrary, importer: ImportCoordinator, defaults: UserDefaults? = .standard) {
        self.library = library
        self.importer = importer
        self.defaults = defaults
        steam = SteamCMD(folder: library.rootURL.appendingPathComponent("SteamCMD", isDirectory: true))
        account = defaults?.string(forKey: Self.accountKey)
        Task.detached(priority: .utility) { [previews] in previews.removeExpired() }
    }

    // MARK: - The list

    /// Starts the list over, as the query now says.
    func reload() {
        loading?.cancel()
        items = []
        query.page = 1
        reachedEnd = false
        loadPage()
    }

    /// Called as the end of the list comes into view.
    func loadMore() {
        guard !isLoading, !reachedEnd, !items.isEmpty else { return }
        query.page += 1
        loadPage()
    }

    private func loadPage() {
        isLoading = true
        cannotLoad = false
        let query = query
        loading = Task {
            do {
                let found = try await SteamWorkshop.items(for: query)
                guard !Task.isCancelled else { return }
                let known = Set(items.map(\.id))
                let new = found.filter { !known.contains($0.id) }
                reachedEnd = new.isEmpty
                items += new
            } catch {
                guard !Task.isCancelled else { return }
                cannotLoad = true
            }
            isLoading = false
        }
    }

    // MARK: - The account

    /// Signs in with what the user typed. Steam may then ask for a code or a confirmation.
    func signIn(account: String, password: String) {
        let account = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard signIn == .idle, !account.isEmpty, !password.isEmpty else { return }
        signIn = .working
        signInError = nil
        Task {
            var passwordIsSent = false
            var refusal: String?
            var isSignedIn = false
            do {
                try await installIfNeeded()
                guard showsSignIn else {
                    signIn = .idle
                    return
                }
                let run = try steam.signIn(account: account)
                signInRun = run
                for await event in run.events {
                    switch event {
                    case .updating(let percent):
                        signIn = .updating(percent)
                    case .needsPassword:
                        // Asked again, it was wrong: that is for the user to look at.
                        if passwordIsSent {
                            run.cancel()
                        } else {
                            passwordIsSent = true
                            run.send(password)
                            signIn = .working
                        }
                    case .needsCode(let code):
                        refusal = nil
                        signIn = .needsCode(code)
                    case .needsConfirmation:
                        signIn = .needsConfirmation
                    case .signedIn:
                        isSignedIn = true
                    case .signInRefused(let reason):
                        refusal = reason
                    case .downloaded, .downloadFailed, .finished:
                        break
                    }
                }
            } catch {
                signInError = NSLocalizedString("Could not get SteamCMD from Valve. Check your internet connection.",
                                                comment: "Workshop sign-in error")
            }
            let wasCancelled = signInRun == nil
            signInRun = nil
            signIn = .idle
            if isSignedIn {
                self.account = account
                defaults?.set(account, forKey: Self.accountKey)
                showsSignIn = false
                startDownloads()
            } else if !wasCancelled, signInError == nil {
                signInError = Self.message(forRefusal: refusal)
            }
        }
    }

    /// The Steam Guard code the user typed.
    func send(code: String) {
        signInRun?.send(code.trimmingCharacters(in: .whitespacesAndNewlines))
        signIn = .working
    }

    func cancelSignIn() {
        let run = signInRun
        signInRun = nil
        run?.cancel()
        showsSignIn = false
        // What was waiting for the sign-in is not going to get it.
        if account == nil {
            downloads.removeAll { $0.phase == .waiting }
        }
    }

    func signOut() {
        account = nil
        defaults?.removeObject(forKey: Self.accountKey)
        steam.forgetAccount()
    }

    private func installIfNeeded() async throws {
        if !steam.isInstalled {
            try await steam.install()
        }
    }

    private static func message(forRefusal reason: String?) -> String {
        switch reason?.lowercased() {
        case "invalid password":
            NSLocalizedString("Wrong account name or password.", comment: "Workshop sign-in error")
        case "rate limit exceeded":
            NSLocalizedString("Steam isn't letting you sign in right now: too many attempts. Wait half an hour and try again.",
                              comment: "Workshop sign-in error")
        case let reason? where reason.contains("mismatch") || reason.contains("auth code"):
            NSLocalizedString("The code is wrong.", comment: "Workshop sign-in error")
        case let reason?:
            String(format: NSLocalizedString("Steam didn't let you in: %@.", comment: "Workshop sign-in error"), reason)
        case nil:
            NSLocalizedString("Couldn't sign in to Steam.", comment: "Workshop sign-in error")
        }
    }

    // MARK: - Downloads

    func isInLibrary(_ item: SteamWorkshop.Item) -> Bool {
        library.items.contains { $0.workshopID == item.id }
    }

    func download(for item: SteamWorkshop.Item) -> Download? {
        downloads.first { $0.id == item.id }
    }

    /// Puts an item in the queue; with nobody signed in, signing in comes first.
    func get(_ item: SteamWorkshop.Item) {
        guard download(for: item) == nil else { return }
        downloads.append(Download(item: item))
        if account == nil {
            showsSignIn = true
        } else {
            startDownloads()
        }
    }

    /// Takes an item off the queue; the one on its way is stopped.
    func cancel(_ item: SteamWorkshop.Item) {
        if download(for: item)?.phase == .waiting {
            downloads.removeAll { $0.id == item.id }
        } else if case .downloading? = download(for: item)?.phase {
            cancelledDownload = true
            downloadRun?.cancel()
        }
    }

    /// Lets nothing outlive the app.
    func stop() {
        signInRun?.cancel()
        downloadRun?.cancel()
    }

    private func startDownloads() {
        guard !isDownloading, account != nil else { return }
        isDownloading = true
        Task {
            while let account, let next = downloads.first(where: { $0.phase == .waiting }) {
                await fetch(next.item, account: account)
            }
            isDownloading = false
        }
    }

    private func setPhase(_ phase: Download.Phase, of item: SteamWorkshop.Item) {
        guard let index = downloads.firstIndex(where: { $0.id == item.id }) else { return }
        downloads[index].phase = phase
    }

    private func fetch(_ item: SteamWorkshop.Item, account: String) async {
        steam.emptyDownloads()
        defer { steam.emptyDownloads() }
        setPhase(.downloading(0), of: item)
        let total = max(item.fileSize, 1)
        let watching = Task {
            while !Task.isCancelled {
                let bytes = await Task.detached { [steam] in steam.downloadedBytes() }.value
                guard !Task.isCancelled else { return }
                // What it has downloaded gets copied into place at the end, which counts twice.
                setPhase(.downloading(min(0.99, Double(bytes) / Double(total))), of: item)
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        defer { watching.cancel() }

        // Settings made for another wallpaper come without it, and it goes in next to them.
        var ids = [item.id]
        while let id = ids.first {
            switch await download(id, account: account) {
            case .done:
                ids.removeFirst()
                let project = WallpaperEngineProject(folder: steam.itemFolder(id))
                if project?.kind == .preset, let base = project?.dependency, base.allSatisfy(\.isNumber),
                   !FileManager.default.fileExists(atPath: steam.itemFolder(base).path) {
                    ids.append(base)
                }
            case .needsSigningIn:
                // Kept in the queue, and picked up once the user has signed in again.
                self.account = nil
                setPhase(.waiting, of: item)
                signInError = NSLocalizedString("Sign in to Steam again.", comment: "Workshop sign-in error")
                showsSignIn = true
                return
            case .failed(let message):
                downloadError = message.map { String(format: $0, item.title) }
                downloads.removeAll { $0.id == item.id }
                return
            }
        }

        watching.cancel()
        setPhase(.adding, of: item)
        let added = await importer.importDownload(steam.itemFolder(item.id), title: item.title)
        if !added.isEmpty {
            library.setWorkshopID(item.id, for: added.map(\.id))
        }
        downloads.removeAll { $0.id == item.id }
    }

    private enum Outcome {
        case done
        case needsSigningIn
        /// With what to say, its argument the item's title; with nothing, it was cancelled.
        case failed(String?)
    }

    private func download(_ id: String, account: String) async -> Outcome {
        let cannotGet = NSLocalizedString("Steam didn't give out “%@”. Make sure this account owns Wallpaper Engine.",
                                          comment: "Workshop download error")
        guard let run = try? steam.download([id], account: account) else { return .failed(cannotGet) }
        downloadRun = run
        defer { downloadRun = nil }
        cancelledDownload = false
        // Ending with neither a result nor the user stopping it is a failure like any other.
        var outcome = Outcome.failed(NSLocalizedString("SteamCMD stopped before “%@” finished downloading. Try again.",
                                                       comment: "Workshop download error"))
        for await event in run.events {
            switch event {
            case .downloaded:
                outcome = .done
            case .downloadFailed:
                outcome = .failed(cannotGet)
            case .needsPassword, .needsCode, .needsConfirmation:
                // The sign-in it remembers has run out.
                run.cancel()
                outcome = .needsSigningIn
            case .updating, .signedIn, .signInRefused, .finished:
                break
            }
        }
        return cancelledDownload ? .failed(nil) : outcome
    }
}

import Foundation
import WallpaperCore

/// Imports files one at a time (conversion is CPU-heavy) and reports progress to the UI.
@MainActor
final class ImportCoordinator: ObservableObject {
    struct Job: Identifiable {
        var id = UUID()
        let url: URL
        let appliesWhenDone: Bool
        /// What to call it, when the file's name says nothing.
        var title: String?
        /// Told what was added, nothing if it failed, once the job is over.
        var whenDone: (([Wallpaper]) -> Void)?
        /// Told how far it has come.
        var whileWorking: ((Double) -> Void)?
        var progress: Double = 0
        /// Whether its videos are being made into WebM: the long part.
        var isConverting = false

        var name: String { title ?? url.lastPathComponent }
    }

    struct Failure: Identifiable {
        let id = UUID()
        let fileName: String
        let message: String
    }

    /// A wallpaper that was added, but not all of it.
    struct Notice: Identifiable {
        let id = UUID()
        let name: String
    }

    /// Pending and running imports; the first one is in progress.
    @Published private(set) var jobs: [Job] = []
    /// Errors of the last batch, published once the whole batch is done.
    @Published var failures: [Failure] = []
    /// Scenes of Wallpaper Engine in the last batch with something in them that is not played,
    /// published once the whole batch is done.
    @Published var notices: [Notice] = []
    /// The latest successfully imported wallpaper, so the library can select it.
    @Published private(set) var lastImportedID: UUID?

    private let library: WallpaperLibrary
    private let manager: WallpaperManager
    private var batchFailures: [Failure] = []
    private var batchNotices: [Notice] = []
    private var isRunning = false
    /// The job under way, if the user stopped it: it is over once what it was in the middle of is.
    private var cancelled: UUID?
    private var conversion: Task<Void, Never>?

    init(library: WallpaperLibrary, manager: WallpaperManager) {
        self.library = library
        self.manager = manager
    }

    /// Queues files and folders (searched recursively) for import. `applyWhenDone` sets each
    /// imported file as the wallpaper, as expected when a file is opened with the app.
    func importFiles(_ urls: [URL], applyWhenDone: Bool) {
        let files = urls.flatMap(Self.expand)
        if files.isEmpty, !urls.isEmpty {
            failures = [Failure(
                fileName: urls[0].lastPathComponent,
                message: NSLocalizedString("No videos or pictures were found.", comment: "Import error")
            )]
            return
        }
        jobs += files.map { Job(url: $0, appliesWhenDone: applyWhenDone) }
        runQueue()
    }

    /// Queues the folder of an item downloaded from the Steam Workshop and waits for it to be
    /// added. Returns what was added; nothing, if the job given by `id` was cancelled.
    func importDownload(_ folder: URL, title: String, id: UUID, progress: @escaping (Double) -> Void) async -> [Wallpaper] {
        await withCheckedContinuation { continuation in
            jobs.append(Job(id: id, url: folder, appliesWhenDone: false, title: title,
                            whenDone: { continuation.resume(returning: $0) }, whileWorking: progress))
            runQueue()
        }
    }

    /// Takes a job off the queue. The one under way stops its videos at once, and leaves nothing
    /// in the library.
    func cancel(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        if index == 0 {
            cancelled = id
            conversion?.cancel()
        } else {
            jobs.remove(at: index).whenDone?([])
        }
    }

    private func runQueue() {
        guard !isRunning else { return }
        isRunning = true
        Task {
            while let job = jobs.first {
                do {
                    let jobID = job.id
                    let report: @Sendable (Double) -> Void = { [weak self] progress in
                        Task { @MainActor in self?.setProgress(progress, for: jobID) }
                    }
                    // A wallpaper of an archive or a folder may have videos to turn into WebM
                    // after it is added. That is by far the longest part of the work — a minute
                    // and a half against seconds — so it has the most of the bar.
                    let mayConvert = Archive.isArchive(job.url)
                        || (try? job.url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                    let addingShare = 0.25
                    let adding: @Sendable (Double) -> Void = { report(mayConvert ? $0 * addingShare : $0) }
                    // The settings of a wallpaper made for Wallpaper Engine are named in the
                    // language the app is shown in.
                    let languages = Bundle.main.preferredLocalizations
                    let added = try await library.importItem(at: job.url, languages: languages, progress: adding)
                    let pages = added.filter { $0.kind == .web }
                    if !pages.isEmpty, let index = jobs.firstIndex(where: { $0.id == jobID }) {
                        jobs[index].isConverting = true
                    }
                    let library = library
                    conversion = Task {
                        for (index, item) in pages.enumerated() where !Task.isCancelled {
                            // Its videos as Chromium plays them, before anything is drawn of it.
                            let done = Double(index), count = Double(pages.count)
                            await MediaConversion.shared.convert(library.projectURL(for: item)) { part in
                                report(addingShare + (done + part) / count * (1 - addingShare))
                            }
                        }
                    }
                    if cancelled == jobID {
                        conversion?.cancel()
                    }
                    await conversion?.value
                    conversion = nil
                    if cancelled == jobID {
                        cancelled = nil
                        library.remove(Set(added.map(\.id)))
                        job.whenDone?([])
                        jobs.removeFirst()
                        continue
                    }
                    report(1)
                    // A video the media engine cannot decode is made over afterwards, while it plays.
                    MediaConversion.shared.makeVideosDecodableInHardware(added, in: library) { [weak manager] item in
                        manager?.videoFileDidChange(item)
                    }
                    for item in added where item.kind == .web && item.thumbnailFileName == nil {
                        // No preview came with the page; draw one.
                        await manager.refreshPictures(of: item)
                    }
                    batchNotices += added.filter { library.leftOutOnImport[$0.id] != nil }.map { Notice(name: $0.name) }
                    if let item = added.last {
                        lastImportedID = item.id
                        if job.appliesWhenDone || !manager.hasWallpaper {
                            manager.setWallpaper(item.id, for: .all)
                        }
                    }
                    job.whenDone?(added)
                } catch {
                    if cancelled == job.id {
                        cancelled = nil
                    } else {
                        batchFailures.append(Failure(fileName: job.name, message: error.localizedDescription))
                    }
                    job.whenDone?([])
                }
                jobs.removeFirst()
            }
            isRunning = false
            if !batchFailures.isEmpty {
                failures = batchFailures
                batchFailures = []
            }
            if !batchNotices.isEmpty {
                notices = batchNotices
                batchNotices = []
            }
        }
    }

    private func setProgress(_ progress: Double, for jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        // Reports come from several tasks; the bar never goes back.
        jobs[index].progress = max(jobs[index].progress, min(1, progress))
        jobs[index].whileWorking?(jobs[index].progress)
    }

    /// A folder becomes the importable files inside it; a file is kept as is, so that
    /// unsupported files produce a clear error instead of being silently skipped.
    private static func expand(_ url: URL) -> [URL] {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        guard isDirectory else { return [url] }
        // A folder with a page in it, or one of a wallpaper made for Wallpaper Engine, is one
        // wallpaper, not a pile of pictures to look through.
        if WebProject(folder: url) != nil || WallpaperEngineProject(folder: url) != nil {
            return [url]
        }
        // So is each of the folders inside it that hold such a wallpaper: an unpacked archive
        // has one, next to files of the site it came from. Their pictures are parts of the
        // wallpapers, not wallpapers themselves.
        let inside = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let wallpapers = inside.filter { WallpaperEngineProject(folder: $0) != nil }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        if !wallpapers.isEmpty {
            // Settings made for another wallpaper are brought in together with it, as one
            // wallpaper; a folder that has such settings is taken whole.
            let hasSettings = wallpapers.contains { WallpaperEngineProject(folder: $0)?.kind == .preset }
            return hasSettings ? [url] : wallpapers
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        return enumerator
            .compactMap { $0 as? URL }
            .filter(MediaImporter.canImport)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

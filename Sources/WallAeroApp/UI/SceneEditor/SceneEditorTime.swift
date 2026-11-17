import AppKit
import SwiftUI
import WallpaperCore

/// The time, the view and the code of a web wallpaper in the editor, as the editor of Wallpaper
/// Engine's scenes has them: the page stands until the timeline plays it, goes to the moment
/// the timeline names, is looked at through the screen or freely, and its code can be written.
/// The page and its project stay as Wallpaper Engine takes them.
extension SceneEditorModel {
    enum Workspace: CaseIterable {
        case layout, scripting

        var title: String {
            switch self {
            case .layout: return "Layout"
            case .scripting: return "Scripting"
            }
        }
    }

    /// Frames a second of the page's timeline.
    var timelineRate: Double { 30 }

    /// How much of the time the ruler shows: ten seconds, and more as the page plays on.
    var playLength: Double { max(10, timelineSeconds * 1.15) }

    // MARK: - Time

    func playingDidChange() {
        if isPlaying {
            playedFrom = timelineSeconds
            stopping = false
        } else {
            // The moment it stopped at comes back from the page.
            stopping = true
        }
        preview?.setClockHeld(!isPlaying)
    }

    /// The page says its moment: as it plays, the timeline follows it.
    func pageClock(seconds: Double, held: Bool) {
        guard isPlaying || stopping else { return }
        if held { stopping = false }
        let rate = timelineRate
        followsPlayback = true
        timelineSeconds = held ? (seconds * rate - 1e-6).rounded(.up) / rate : seconds
        followsPlayback = false
        // On to the whole frame, which the page is not at yet.
        if held, timelineSeconds > seconds + 1e-6 { preview?.show(moment: timelineSeconds) }
    }

    /// Stops playing and goes back to where it began, as Escape does in Blender.
    func cancelPlaying() {
        guard isPlaying else { return }
        isPlaying = false
        stopping = false
        timelineSeconds = playedFrom
        preview?.show(moment: playedFrom)
    }

    func stepFrame(_ by: Double) {
        timelineSeconds = max(0, ((timelineSeconds * timelineRate).rounded() + by) / timelineRate)
    }

    // MARK: - The view

    /// Through the screen, as the wallpaper shows; or freely: made smaller to see round it,
    /// moved, or — with 2D off — turned about as a card in depth, to be looked at.
    func setViewsFreely(_ free: Bool) {
        viewsFreely = free
        if !free { fitView() }
        preview?.setCard(showsCard ? cardTurn : nil)
    }

    func setViewIn3D(_ inDepth: Bool) {
        viewIn3D = inDepth
        if !viewsFreely { viewsFreely = true }
        preview?.setCard(showsCard ? cardTurn : nil)
    }

    var showsCard: Bool { viewsFreely && viewIn3D }

    func navigate(by distance: CGSize, moving: Bool, within size: CGSize) {
        if showsCard, !moving {
            cardTurn = CGSize(width: min(max(cardTurn.width + distance.width * 0.4, -85), 85),
                              height: min(max(cardTurn.height + distance.height * 0.4, -85), 85))
            preview?.setCard(cardTurn)
            return
        }
        guard viewZoom > 1 || viewsFreely else { return }
        viewPan = CGSize(width: min(max(viewPan.width + distance.width, -size.width), size.width),
                         height: min(max(viewPan.height + distance.height, -size.height), size.height))
    }

    func navigateZoom(by factor: CGFloat, around point: CGSize) {
        let zoom = min(max(viewZoom * factor, viewsFreely ? 0.25 : 1), 4)
        let share = zoom / viewZoom
        viewPan = zoom == 1 && !viewsFreely ? .zero : CGSize(width: viewPan.width + point.width * (1 - share),
                                                             height: viewPan.height + point.height * (1 - share))
        viewZoom = zoom
    }

    func fitView() {
        viewZoom = 1
        viewPan = .zero
        if showsCard {
            cardTurn = CGSize(width: -25, height: 15)
            preview?.setCard(cardTurn)
        }
    }

    // MARK: - Code

    /// The page's own files: its markup, scripts, styles and settings. What the app writes for
    /// the page itself — the frame it is shown in, the scene file — is not among them.
    func findCodeFiles() {
        let kinds: Set<String> = ["html", "htm", "js", "mjs", "css", "json", "glsl", "frag", "vert", "txt", "svg"]
        let generated: Set<String> = ["index.html", "runtime.js", "scene.json", "engine.js"]
        var found: [String] = []
        let root = folder.standardizedFileURL.path
        if let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                                       options: [.skipsHiddenFiles]) {
            for case let url as URL in walker {
                let path = String(url.standardizedFileURL.path.dropFirst(root.count + 1))
                if path.hasPrefix("engine/") || path.hasPrefix("media/") || path.hasPrefix("project/") || path.hasPrefix("Fonts/") {
                    walker.skipDescendants()
                    continue
                }
                guard kinds.contains(url.pathExtension.lowercased()), !generated.contains(path),
                      let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                      values.isRegularFile == true, (values.fileSize ?? 0) < 4_000_000 else { continue }
                found.append(path)
            }
        }
        // The page first, then its scripts and styles; the app's own custom files last.
        func rank(_ path: String) -> Int {
            if path.hasSuffix("index.html") || path.hasSuffix(".htm") || path.hasSuffix(".html") { return 0 }
            if path.hasPrefix("custom.") { return 3 }
            if path.hasSuffix(".json") { return 2 }
            return 1
        }
        codeFiles = found.sorted { (rank($0), $0.lowercased()) < (rank($1), $1.lowercased()) }
        if codeFile == nil || !codeFiles.contains(codeFile!) { openCode(codeFiles.first) }
    }

    var codeChanged: Bool { codeFile != nil && codeDraft != codeSaved }

    /// Opens a file of the page; what was typed in the one before is written first.
    func openCode(_ path: String?) {
        if codeChanged { saveCode() }
        codeFile = path
        codeProblem = nil
        guard let path, let text = try? String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8) else {
            codeDraft = ""
            codeSaved = ""
            if path != nil { codeProblem = NSLocalizedString("This file is not text the editor can read.", comment: "Code editor") }
            return
        }
        codeDraft = text
        codeSaved = text
    }

    /// Writes the file and loads the page anew, at the moment the timeline stands at.
    func saveCode() {
        guard let codeFile, codeChanged else { return }
        do {
            try codeDraft.write(to: folder.appendingPathComponent(codeFile), atomically: true, encoding: .utf8)
            codeSaved = codeDraft
            codeProblem = nil
            preview?.reloadPage()
        } catch {
            codeProblem = error.localizedDescription
        }
    }

    func revertCode() {
        codeDraft = codeSaved
    }
}

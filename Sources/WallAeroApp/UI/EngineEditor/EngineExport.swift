import AppKit
import UniformTypeIdentifiers
import WallpaperCore

/// Gives a scene made in the editor to Wallpaper Engine: the project folder as Wallpaper
/// Engine's own editor keeps one — to be put in its `projects/myprojects` folder, or opened
/// there — or the same folder in a ZIP archive. A preview picture of the scene as it is now
/// goes with it, for Wallpaper Engine to show the wallpaper by.
@MainActor
enum EngineExport {
    static func exportFolder(_ model: EngineEditorModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = NSLocalizedString("Export", comment: "Export panel button")
        panel.message = NSLocalizedString("Choose where the project folder goes. Put it into Wallpaper Engine's projects/myprojects folder to open it there.",
                                          comment: "Export panel")
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        Task {
            do {
                let folder = try await write(model, into: parent)
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    static func exportArchive(_ model: EngineEditorModel) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = safeName(model.document.title.isEmpty ? model.title : model.document.title) + ".zip"
        panel.prompt = NSLocalizedString("Export", comment: "Export panel button")
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("WallAero-Export-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: staging) }
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                let folder = try await write(model, into: staging)
                try? FileManager.default.removeItem(at: destination)
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                process.arguments = ["-c", "-k", "--keepParent", "--norsrc", "--noextattr", "--noacl", folder.path, destination.path]
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    /// Writes the project into a new folder of `parent`, named after the scene; returns it.
    private static func write(_ model: EngineEditorModel, into parent: URL) async throws -> URL {
        model.saveNow()
        let name = safeName(model.document.title.isEmpty ? model.title : model.document.title)
        var folder = parent.appendingPathComponent(name, isDirectory: true)
        var number = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = parent.appendingPathComponent("\(name) \(number)", isDirectory: true)
            number += 1
        }
        try FileManager.default.copyItem(at: model.projectFolder, to: folder)
        // The preview the project names: the scene as the editor shows it now.
        let previewName = model.document.project["preview"]?.stringValue ?? "preview.jpg"
        if Archive.staysInside(previewName), let image = await model.preview?.snapshot() {
            try? Thumbnailer.writeJPEG(image, to: folder.appendingPathComponent(previewName))
        }
        return folder
    }

    private static func safeName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "[/:\\\\]", with: "-", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Wallpaper" : String(cleaned.prefix(80))
    }
}

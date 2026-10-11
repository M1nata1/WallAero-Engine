import SwiftUI
import WallpaperCore

/// The music of one wallpaper, in its settings: the folder, and once it is chosen, the playlist
/// and the order. While the wallpaper is on, the music plays in place of its own sound.
struct MusicSettingsRows: View {
    @EnvironmentObject private var library: WallpaperLibrary
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var manager: WallpaperManager
    let item: Wallpaper

    private var music: Wallpaper.Settings.Music? { item.shownSettings.music }

    var body: some View {
        LabeledContent("Music folder") {
            HStack(spacing: 8) {
                if let music {
                    Text(URL(fileURLWithPath: music.folderPath).lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button(music == nil ? "Choose Folder…" : "Change…", action: chooseFolder)
                if music != nil {
                    Button("Remove") {
                        set(nil)
                    }
                }
            }
        }
        // The folder is read to list its playlists; the wallpaper need not be the one on screen.
        .task(id: music?.folderPath) {
            if let path = music?.folderPath {
                manager.readMusicFolder(at: path)
            }
        }
        if let music {
            if let playlists = manager.musicFolders[music.folderPath]?.playlists, !playlists.isEmpty {
                Picker("Playlist", selection: playlist(of: music, among: playlists)) {
                    Text("All Music").tag(String?.none)
                    ForEach(playlists) { playlist in
                        Text(playlist.name).tag(String?.some(playlist.name))
                    }
                }
            }
            Toggle("Shuffle", isOn: Binding(get: { music.isShuffled }, set: { isOn in
                var changed = music
                changed.isShuffled = isOn
                set(changed)
            }))
        }
    }

    /// The chosen playlist. One that was renamed or deleted shows as all the music, which is
    /// what plays then.
    private func playlist(of music: Wallpaper.Settings.Music, among playlists: [MusicFolder.Playlist]) -> Binding<String?> {
        Binding(
            get: { playlists.contains { $0.name == music.playlist } ? music.playlist : nil },
            set: { name in
                var changed = music
                changed.playlist = name
                set(changed)
            }
        )
    }

    private func set(_ music: Wallpaper.Settings.Music?) {
        var settings = library.item(withID: item.id)?.shownSettings ?? item.shownSettings
        settings.music = music
        library.setSettings(settings, for: item.id)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = NSLocalizedString("Choose", comment: "Open panel button")
        panel.message = NSLocalizedString("Choose a folder with music. Its subfolders and .m3u files become playlists.", comment: "Open panel")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            let folder = await Task.detached(priority: .userInitiated) { MusicFolder.scan(url) }.value
            guard !folder.allTracks.isEmpty else {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("No music was found in that folder.", comment: "Music folder alert")
                alert.informativeText = NSLocalizedString("MP3, M4A, AAC, WAV, AIFF and FLAC files are supported.", comment: "Music folder alert")
                alert.runModal()
                return
            }
            manager.remember(folder)
            set(Wallpaper.Settings.Music(folderPath: url.path, isShuffled: music?.isShuffled ?? false))
            // Whoever picks music wants to hear it.
            preferences.playsSound = true
        }
    }
}

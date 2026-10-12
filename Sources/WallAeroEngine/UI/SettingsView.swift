import SwiftUI
import WallpaperCore

/// The settings at the side of the main window: the selected wallpaper's and the app's own, one
/// kind at a time.
struct SettingsPanel: View {
    @EnvironmentObject private var state: MainWindowState
    /// Opens a wallpaper in the scene editor, from its settings.
    let edit: (Wallpaper) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $state.settingsTab) {
                Text("settings.tab.wallpaper").tag(MainWindowState.SettingsTab.wallpaper)
                Text("settings.tab.general").tag(MainWindowState.SettingsTab.general)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
            switch state.settingsTab {
            case .wallpaper: WallpaperSettingsView(edit: edit)
            case .general: SettingsView()
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// The app's own settings. The form scrolls when the window is shorter than its sections.
struct SettingsView: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var library: WallpaperLibrary
    @State private var opensAtLogin = LaunchAtLogin.isEnabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section("Playback") {
                Toggle("Play sound", isOn: $preferences.playsSound)
                Slider(value: $preferences.volume, in: 0...1) {
                    Text("Volume")
                } minimumValueLabel: {
                    Image(systemName: "speaker.fill")
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3.fill")
                }
                .disabled(!preferences.playsSound)
            }

            Section("Energy") {
                Toggle("Pause when windows cover the desktop", isOn: $preferences.pauseWhenCovered)
                Toggle("Pause on battery power", isOn: $preferences.pauseOnBattery)
                Toggle("Pause in Low Power Mode", isOn: $preferences.pauseInLowPowerMode)
                Picker("Frame rate of web wallpapers", selection: $preferences.frameRate) {
                    ForEach(Preferences.frameRates, id: \.self) { rate in
                        Text(String(format: NSLocalizedString("%d fps", comment: "A frame rate to choose: frames per second"), rate)).tag(rate)
                    }
                }
                Toggle("Draw web wallpapers at Retina resolution", isOn: $preferences.drawsAtFullDensity)
            }

            CursorSettingsSection()

            Section("General") {
                Toggle("Open at login", isOn: $opensAtLogin)
                    .onChange(of: opensAtLogin) { enabled in
                        updateLoginItem(enabled)
                    }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle("Show the wallpaper on the lock screen", isOn: $preferences.setsSystemWallpaper)
                LabeledContent("Library folder") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.open(library.rootURL)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxHeight: .infinity)
    }

    private func updateLoginItem(_ enabled: Bool) {
        guard enabled != LaunchAtLogin.isEnabled else { return }
        do {
            try LaunchAtLogin.setEnabled(enabled)
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
            // Put the switch back; the guard above stops the resulting onChange from looping.
            opensAtLogin = LaunchAtLogin.isEnabled
        }
    }

}

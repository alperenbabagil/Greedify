import GreedifyKit
import SwiftUI

/// Settings window (spec §4.12, §5).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            ThemeSettings().tabItem { Label("Themes", systemImage: "paintpalette") }
            PlaybackSettings().tabItem { Label("Playback", systemImage: "hifispeaker") }
            StorageSettings().tabItem { Label("Storage", systemImage: "internaldrive") }
            AccountSettings().tabItem { Label("Account", systemImage: "person.crop.circle") }
            DiagnosticsSettings().tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            CreditsSettings().tabItem { Label("Credits", systemImage: "heart.text.square") }
        }
        .frame(width: 480)
        .padding(.vertical, 8)
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin).onChange(of: launchAtLogin) { LoginItem.set(launchAtLogin) }
            Toggle("Block Apple Music", isOn: Binding(get: { settings.blockAppleMusic }, set: { model.setBlockAppleMusic($0) }))
            Toggle("Lyrics in menu bar", isOn: $settings.lyricsInMenuBar).onChange(of: settings.lyricsInMenuBar) { model.rescheduleLabel() }
            Picker("Appearance", selection: $settings.appearance) {
                Text("System").tag(AppearanceMode.system)
                Text("Light").tag(AppearanceMode.light)
                Text("Dark").tag(AppearanceMode.dark)
            }
            .onChange(of: settings.appearance) { model.applyAppearance() }
            .disabled(!model.themes.current.isSystem)
            if !model.themes.current.isSystem {
                Text("Set by the theme").font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("Media keys") {
                if model.mediaKeysActive { Text("Working").foregroundStyle(.secondary) }
                else { Button("Allow Accessibility") { MediaKeyTap.requestPermission(); model.startMediaKeys() } }
            }
        }
        .formStyle(.grouped)
    }
}

struct PlaybackSettings: View {
    @Environment(AppModel.self) private var model
    @State private var nameDraft = ""

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            TextField("Device name", text: $nameDraft)
                .onSubmit(commitName)
                .onAppear { nameDraft = settings.deviceName }
                .onDisappear(perform: commitName)
            Picker("Audio quality", selection: $settings.bitrate) {
                ForEach(AppSettings.bitrateOptions, id: \.self) { Text("\($0) kbps").tag($0) }
            }
            .onChange(of: settings.bitrate) { apply() }
            Toggle("Volume normalisation", isOn: $settings.normalisation).onChange(of: settings.normalisation) { apply() }
        }
        .formStyle(.grouped)
    }

    /// Applies the typed name on Return or when Settings closes; empty names are ignored.
    func commitName() {
        let name = nameDraft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != model.settings.deviceName else { nameDraft = model.settings.deviceName; return }
        model.settings.deviceName = name
        apply()
    }

    func apply() {
        model.player.localDeviceName = model.settings.deviceName
        model.applySpeakerSettings()
    }
}

struct StorageSettings: View {
    @Environment(AppModel.self) private var model
    @State private var appCacheBytes = 0
    @State private var audioCacheBytes = 0

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Picker("Artwork in memory", selection: $settings.artworkMemoryMB) {
                ForEach(AppSettings.artworkMemoryOptions, id: \.self) { Text("\($0) MB").tag($0) }
            }
            .onChange(of: settings.artworkMemoryMB) { model.images.setMemoryLimit(settings.artworkMemoryMB * 1_048_576) }

            LabeledContent("App cache") {
                HStack {
                    Text(bytes(appCacheBytes)).foregroundStyle(.secondary).monospacedDigit()
                    Picker("", selection: $settings.appCacheMB) {
                        ForEach(AppSettings.appCacheOptions, id: \.self) { Text($0 >= 1024 ? "\($0 / 1024) GB" : "\($0) MB").tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    Button("Clear") { Task { await model.dataCache.clear(); model.images.clearMemory(); await measure() } }
                }
            }
            .onChange(of: settings.appCacheMB) { Task { await model.dataCache.setLimit(settings.appCacheMB * 1_048_576); await measure() } }

            LabeledContent("Audio cache") {
                HStack {
                    Text(bytes(audioCacheBytes)).foregroundStyle(.secondary).monospacedDigit()
                    Picker("", selection: $settings.audioCacheGB) {
                        ForEach(AppSettings.audioCacheOptions, id: \.self) { Text($0 == 0 ? "Off" : "\($0) GB").tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    Button("Clear") { Task { await model.librespot.clearAudioCache(settings.librespotConfig); await measure() } }
                }
            }
            .onChange(of: settings.audioCacheGB) { model.applySpeakerSettings() }

            HStack {
                Spacer()
                Button("Clear All") {
                    Task {
                        await model.dataCache.clear(); model.images.clearMemory()
                        await model.librespot.clearAudioCache(settings.librespotConfig)
                        await measure()
                    }
                }
            }
            Text("Clearing never logs you out. Clearing the audio cache restarts the Mac speaker for about a second.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .task { await measure() }
    }

    func measure() async {
        appCacheBytes = await model.dataCache.sizeBytes()
        audioCacheBytes = Self.directorySize(GreedifyPaths.librespotAudioCache)
    }

    static func directorySize(_ url: URL) -> Int {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let f as URL in e { total += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        return total
    }

    func bytes(_ n: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file) }
}

struct AccountSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var confirmReset = false

    var body: some View {
        Form {
            LabeledContent("Spotify account", value: model.library.user?.displayName ?? model.library.user?.id ?? "Not logged in")
            Button("Log Out") { model.logOut(); openWindow(id: WindowID.setup) }
            Button("Reset Greedify…", role: .destructive) { confirmReset = true }
                .confirmationDialog("Reset Greedify?", isPresented: $confirmReset) {
                    Button("Reset", role: .destructive) { Task { await model.reset(); openWindow(id: WindowID.setup) } }
                } message: {
                    Text("This removes your login, the Mac speaker's login, all caches and settings.")
                }
        }
        .formStyle(.grouped)
    }
}

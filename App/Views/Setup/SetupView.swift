import GreedifyKit
import SwiftUI

/// First-run setup (spec §4.11). Steps run in order; each shows a checkmark when done.
struct SetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var clientID = ""
    @State private var loggedIn = false
    @State private var speakerReady = false
    @State private var busy = false
    @State private var error: String?
    @State private var login = SpotifyLogin()
    @State private var launchAtLogin = true // spec §4.11 step 5: on by default
    @State private var spotifyLink: URL?
    @State private var speakerLink: URL?

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                Text("Greedify talks to Spotify through your own developer app. This takes about two minutes.")
                    .foregroundStyle(.secondary)
            }
            Section("1. Create a Spotify developer app") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("• Open developer.spotify.com/dashboard and create an app.")
                    Text("• Redirect URI: greedify://callback")
                    Text("• APIs used: Web API. Under User Management, add your Spotify email.")
                }
                .textSelection(.enabled)
                Link("Open Spotify Dashboard", destination: URL(string: "https://developer.spotify.com/dashboard")!)
                TextField("Client ID", text: $clientID)
            }
            Section("2. Log in to Spotify") {
                stepRow(done: loggedIn, title: "Allow Greedify to control playback and read your library") {
                    Button("Copy Link") { Task { await logIn(presentSheet: false) } }
                        .disabled(clientID.isEmpty || busy)
                        .hoverHelp("Copy the login link to paste into any browser")
                    Button("Log In") { Task { await logIn(presentSheet: true) } }.disabled(clientID.isEmpty || busy)
                }
                if !loggedIn, let spotifyLink { CopyLinkRow(url: spotifyLink) }
            }
            Section("3. Connect this Mac as a speaker") {
                stepRow(done: speakerReady, title: "Your browser opens once so the Mac can play Spotify audio") {
                    Button("Copy Link") { Task { await connectSpeaker(openBrowser: false) } }
                        .disabled(!loggedIn || busy)
                        .hoverHelp("Copy the login link to paste into any browser")
                    Button("Connect") { Task { await connectSpeaker(openBrowser: true) } }.disabled(!loggedIn || busy)
                }
                if !speakerReady, let speakerLink { CopyLinkRow(url: speakerLink) }
            }
            Section("4. Media keys (optional)") {
                stepRow(done: MediaKeyTap.hasPermission, title: "Allow Accessibility so ▶︎ ⏭ ⏮ control Spotify") {
                    Button("Allow") { MediaKeyTap.requestPermission() }
                }
            }
            Section("5. Launch at login") {
                Toggle("Start Greedify and the Mac speaker when you log in", isOn: $launchAtLogin)
            }
            if let error { Text(error).foregroundStyle(.red) }
            Section {
                Button("Finish") { finish() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!loggedIn || !speakerReady)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        // Spotify redirecting to greedify://callback from a browser the link was pasted into.
        .onOpenURL { url in login.handleCallback(url) }
        .onAppear {
            clientID = settings.clientID
            loggedIn = model.tokens.load() != nil
            speakerReady = model.librespot.hasCredentials
        }
    }

    func stepRow<B: View>(done: Bool, title: String, @ViewBuilder button: () -> B) -> some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? Color.accentColor : .secondary)
            Text(title)
            Spacer()
            if !done { button() }
        }
    }

    func logIn(presentSheet: Bool) async {
        // Copying doesn't block: the user may still press Log In instead (it replaces the copied attempt).
        if presentSheet { busy = true }
        error = nil
        defer { if presentSheet { busy = false } }
        model.settings.clientID = clientID.trimmingCharacters(in: .whitespaces)
        model.rebuildClients()
        do {
            try await login.logIn(auth: model.authService, store: model.tokens, presentSheet: presentSheet) { url in
                spotifyLink = url
                if !presentSheet { copy(url) }
            }
            loggedIn = true
        } catch is CancellationError {
            // replaced by a newer attempt
        } catch {
            self.error = "Login failed: \(error.localizedDescription). Check the client ID and the redirect URI."
        }
    }

    func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func connectSpeaker(openBrowser: Bool) async {
        busy = true; error = nil
        defer { busy = false }
        guard let binary = Bundle.main.url(forAuxiliaryExecutable: "librespot") else {
            error = "librespot is missing from the app bundle. Rebuild Greedify."
            return
        }
        speakerReady = await model.librespot.interactiveLogin(model.settings.librespotConfig, librespotURL: binary) { url in
            Task { @MainActor in
                guard speakerLink == nil else { return } // librespot may print the URL more than once
                speakerLink = url
                if openBrowser { NSWorkspace.shared.open(url) } else { copy(url) }
            }
        }
        if !speakerReady { error = "The speaker login didn't finish. Try Connect again." }
    }

    func finish() {
        LoginItem.set(launchAtLogin)
        model.settings.onboardingDone = true
        model.start()
        dismissWindow(id: WindowID.setup)
    }
}

/// Shown after a login link was opened or copied, so it can be copied again.
struct CopyLinkRow: View {
    let url: URL

    var body: some View {
        HStack {
            Text("Paste the link into any browser on this Mac, then allow access.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Copy Again") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            }
            .controlSize(.small)
        }
    }
}

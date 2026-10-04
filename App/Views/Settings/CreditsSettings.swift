import GreedifyKit
import SwiftUI

/// Settings → Credits: where the curated themes' art comes from, and what Greedify is built on.
struct CreditsSettings: View {
    @Environment(AppModel.self) private var model

    static let app: [Theme.Credit] = [
        Theme.Credit(title: "librespot", detail: "The Spotify Connect speaker that plays the audio.", url: URL(string: "https://github.com/librespot-org/librespot")),
        Theme.Credit(title: "LRCLIB", detail: "Synced lyrics.", url: URL(string: "https://lrclib.net")),
        Theme.Credit(title: "Spotify Web API", detail: "Library, search and playback control.", url: URL(string: "https://developer.spotify.com")),
    ]

    var body: some View {
        let themed = model.themes.entries.compactMap { entry -> (String, [Theme.Credit])? in
            guard let theme = entry.theme, !theme.credits.isEmpty else { return nil }
            return (theme.name, theme.credits)
        }
        Form {
            ForEach(themed, id: \.0) { name, credits in
                Section(name) { ForEach(credits, id: \.title) { CreditRow(credit: $0) } }
            }
            Section("Greedify") { ForEach(Self.app, id: \.title) { CreditRow(credit: $0) } }
        }
        .formStyle(.grouped)
        .frame(height: 360)
    }
}

private struct CreditRow: View {
    let credit: Theme.Credit
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let url = credit.url { Link(credit.title, destination: url).fontWeight(.medium) } else { Text(credit.title).fontWeight(.medium) }
            Text(credit.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if let url = credit.url { Text(url.absoluteString).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle).textSelection(.enabled) }
        }
    }
}

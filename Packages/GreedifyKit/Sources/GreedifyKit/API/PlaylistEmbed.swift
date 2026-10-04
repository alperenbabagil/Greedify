import Foundation

/// Reads the track list out of Spotify's playlist embed page (`open.spotify.com/embed/playlist/<id>`).
///
/// Development mode (2026) won't list the songs of a playlist the user doesn't own, but the public embed page
/// carries its first 100 in a `__NEXT_DATA__` script. Unofficial: each song has a title, artist names, duration
/// and URI, but no album and no artist ids.
enum PlaylistEmbed {
    private struct Page: Decodable {
        struct Props: Decodable { let pageProps: PageProps }
        struct PageProps: Decodable { let state: State }
        struct State: Decodable { let data: DataBox }
        struct DataBox: Decodable { let entity: Entity }
        struct Entity: Decodable { let trackList: [Item] }
        struct Item: Decodable {
            let uri: String
            let title: String
            let subtitle: String?
            let duration: Int?
            let isPlayable: Bool?
            let entityType: String?
        }
        let props: Props
    }

    static func tracks(fromHTML data: Data) throws -> [Track] {
        let html = String(decoding: data, as: UTF8.self)
        guard let open = html.range(of: #"<script id="__NEXT_DATA__"[^>]*>"#, options: .regularExpression),
              let close = html.range(of: "</script>", range: open.upperBound..<html.endIndex) else {
            throw SpotifyError.decoding("embed: no __NEXT_DATA__")
        }
        let page: Page
        do { page = try JSONDecoder().decode(Page.self, from: Data(html[open.upperBound..<close.lowerBound].utf8)) }
        catch { throw SpotifyError.decoding("embed: \(error)") }
        return page.props.pageProps.state.data.entity.trackList.compactMap { item in
            guard let id = item.uri.split(separator: ":").last.map(String.init) else { return nil }
            // Artists are joined with ",\u{00a0}".
            let names = (item.subtitle ?? "").components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{00a0}"))) }
                .filter { !$0.isEmpty }
            var track = Track(id: id, name: item.title, uri: item.uri, durationMs: item.duration ?? 0,
                              artists: names.map { ArtistRef(id: nil, name: $0, uri: "") }, album: nil)
            track.isPlayable = item.isPlayable
            if item.entityType == "episode" { track.kind = .episode }
            return track
        }
    }
}

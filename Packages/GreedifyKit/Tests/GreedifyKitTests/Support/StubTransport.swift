import Foundation
@testable import GreedifyKit

/// Records requests and answers them from a handler. `@unchecked Sendable`: guarded by a lock.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (Int, String, [String: String])
    private let lock = NSLock()
    private var handler: Handler
    private(set) var requestsStore: [URLRequest] = []

    init(_ handler: @escaping Handler) { self.handler = handler }

    var requests: [URLRequest] { lock.withLock { requestsStore } }
    func setHandler(_ h: @escaping Handler) { lock.withLock { handler = h } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let h = lock.withLock { requestsStore.append(request); return handler }
        let (status, body, headers) = try h(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (Data(body.utf8), response)
    }
}

extension URLRequest {
    var bodyString: String { httpBody.map { String(decoding: $0, as: UTF8.self) } ?? "" }
    var bodyJSON: [String: Any] { (httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:] }
    func query(_ name: String) -> String? {
        URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}

enum Fixture {
    static let trackJSON = """
    {"id":"t1","name":"Paper Satellites","uri":"spotify:track:t1","duration_ms":245000,
     "artists":[{"id":"a1","name":"The Quiet Harbor","uri":"spotify:artist:a1"}],
     "album":{"id":"al1","name":"Low Orbit","uri":"spotify:album:al1",
              "images":[{"url":"https://i.scdn.co/640","width":640,"height":640},{"url":"https://i.scdn.co/300","width":300,"height":300}]}}
    """
    static let track = try! SpotifyJSON.decoder.decode(Track.self, from: Data(trackJSON.utf8))

    static func track(_ id: String, name: String = "Song", durationMs: Int = 200_000) -> Track {
        Track(id: id, name: name, uri: "spotify:track:\(id)", durationMs: durationMs,
              artists: [ArtistRef(id: "a", name: "Artist", uri: "spotify:artist:a")],
              album: AlbumRef(id: "al", name: "Album", uri: "spotify:album:al", images: []))
    }

    static func playlistJSON(id: String = "p1", owner: String = "me", snapshot: String = "s1", total: Int = 2) -> String {
        """
        {"id":"\(id)","name":"Late Night Drive","uri":"spotify:playlist:\(id)","images":[],
         "owner":{"id":"\(owner)","display_name":"Me"},"collaborative":false,"snapshot_id":"\(snapshot)",
         "items":{"href":"x","total":\(total)}}
        """
    }

    static func page(_ items: [String], next: String? = nil, total: Int? = nil, offset: Int = 0) -> String {
        let n = next.map { "\"\($0)\"" } ?? "null"
        return #"{"items":[\#(items.joined(separator: ","))],"next":\#(n),"offset":\#(offset),"limit":50,"total":\#(total ?? items.count)}"#
    }
}

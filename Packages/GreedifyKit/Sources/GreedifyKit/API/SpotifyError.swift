import Foundation

public enum SpotifyError: Error, Equatable, Sendable {
    /// No tokens stored; the user has never logged in (or logged out).
    case notAuthenticated
    /// The refresh token is expired or revoked; the user must log in again.
    case reauthRequired
    case rateLimited(retryAfter: TimeInterval, quotaExceeded: Bool)
    case noActiveDevice
    case forbidden(String)
    case notFound
    case http(status: Int, message: String)
    case transport(String)
    case decoding(String)

    /// Builds an error from a non-2xx Web API response.
    /// Body shape: `{"error":{"status":404,"message":"...","reason":"NO_ACTIVE_DEVICE"}}`.
    public static func from(status: Int, headers: [AnyHashable: Any], body: Data) -> SpotifyError {
        struct Envelope: Decodable {
            struct Inner: Decodable { let message: String?; let reason: String? }
            let error: Inner?
        }
        let inner = (try? JSONDecoder().decode(Envelope.self, from: body))?.error
        let message = inner?.message ?? ""
        let reason = inner?.reason ?? ""
        switch status {
        case 429:
            let header = headers.first { "\($0.key)".lowercased() == "retry-after" }?.value
            let seconds = TimeInterval("\(header ?? "")") ?? 5
            return .rateLimited(retryAfter: seconds, quotaExceeded: reason == "QUOTA_EXCEEDED" || message.contains("QUOTA_EXCEEDED"))
        case 404 where reason == "NO_ACTIVE_DEVICE" || message.localizedCaseInsensitiveContains("no active device"):
            return .noActiveDevice
        case 404:
            return .notFound
        case 403:
            return .forbidden(message)
        default:
            return .http(status: status, message: message)
        }
    }

    /// Short text for the non-blocking banner.
    public var bannerText: String {
        switch self {
        case .notAuthenticated, .reauthRequired: "Spotify login expired. Log in again."
        case .rateLimited: "Spotify is limiting requests. Retrying shortly."
        case .noActiveDevice: "No Spotify device is available."
        // A player command is rejected with "Player command failed: …"; the rest are edits of someone else's playlist.
        case .forbidden(let message) where message.hasPrefix("Player command failed"): "Spotify didn't accept that command. Try again."
        case .forbidden: "You can only change playlists you own"
        case .notFound: "Spotify couldn't find that item."
        case .http(let status, _): "Spotify returned an error (\(status))."
        case .transport: "Can't reach Spotify. Check your connection."
        case .decoding: "Spotify sent a response Greedify can't read."
        }
    }
}

import Foundation

public struct AuthConfig: Sendable, Equatable {
    public var clientID: String
    public var redirectURI: URL
    public var scopes: [String]

    /// Resume points for episodes (podcasts spec §5).
    public static let playbackPositionScope = "user-read-playback-position"

    public static let defaultScopes = [
        "user-read-playback-state", "user-modify-playback-state", "user-read-currently-playing",
        "user-library-read", "user-library-modify",
        "playlist-read-private", "playlist-read-collaborative",
        "playlist-modify-private", "playlist-modify-public",
        "user-follow-read", "user-follow-modify",
        playbackPositionScope,
    ]

    public init(clientID: String, redirectURI: URL, scopes: [String] = AuthConfig.defaultScopes) {
        self.clientID = clientID; self.redirectURI = redirectURI; self.scopes = scopes
    }
}

public enum AuthError: Error, Equatable, Sendable {
    case stateMismatch
    case denied(String)
    case missingCode
}

/// Authorization Code + PKCE against accounts.spotify.com. Stateless; tokens live in a `TokenStore`.
public struct AuthService: Sendable {
    public let config: AuthConfig
    let transport: HTTPTransport
    let now: @Sendable () -> Date
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    public init(config: AuthConfig, transport: HTTPTransport, now: @escaping @Sendable () -> Date = Date.init) {
        self.config = config; self.transport = transport; self.now = now
    }

    public func authorizationURL(verifier: String, state: String) -> URL {
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: config.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: config.redirectURI.absoluteString),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            .init(name: "state", value: state),
            .init(name: "scope", value: config.scopes.joined(separator: " ")),
        ]
        return c.url!
    }

    /// Extracts the authorization code from the redirect URL.
    public static func code(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") { throw AuthError.denied(error) }
        guard value("state") == expectedState else { throw AuthError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw AuthError.missingCode }
        return code
    }

    public func exchange(code: String, verifier: String) async throws -> Tokens {
        let response = try await postToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI.absoluteString,
            "client_id": config.clientID,
            "code_verifier": verifier,
        ])
        guard let refresh = response.refreshToken else { throw SpotifyError.decoding("No refresh_token in token response") }
        return Tokens(accessToken: response.accessToken, refreshToken: refresh,
                      expiresAt: now().addingTimeInterval(response.expiresIn), scope: response.scope ?? "")
    }

    /// Spotify may or may not rotate the refresh token; keep the old one if none is returned.
    public func refresh(_ tokens: Tokens) async throws -> Tokens {
        let response = try await postToken([
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "client_id": config.clientID,
        ])
        return Tokens(accessToken: response.accessToken, refreshToken: response.refreshToken ?? tokens.refreshToken,
                      expiresAt: now().addingTimeInterval(response.expiresIn), scope: response.scope ?? tokens.scope)
    }

    struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval
        let scope: String?
    }

    private func postToken(_ form: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(form).data(using: .utf8)
        let (data, http) = try await transport.send(request)
        guard (200..<300).contains(http.statusCode) else {
            // `invalid_grant` = refresh token expired/revoked (e.g. the 6-month limit).
            if http.statusCode == 400, String(decoding: data, as: UTF8.self).contains("invalid_grant") {
                throw SpotifyError.reauthRequired
            }
            throw SpotifyError.http(status: http.statusCode, message: String(decoding: data, as: UTF8.self))
        }
        do { return try SpotifyJSON.decoder.decode(TokenResponse.self, from: data) }
        catch { throw SpotifyError.decoding("\(error)") }
    }

    static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
    }
}

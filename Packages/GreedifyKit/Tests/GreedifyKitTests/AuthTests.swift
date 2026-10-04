import CryptoKit
import Foundation
import Testing
@testable import GreedifyKit

extension Fixture {
    static let freshTokens = Tokens(accessToken: "AT", refreshToken: "RT", expiresAt: Date().addingTimeInterval(3600), scope: "")
    static let expiredTokens = Tokens(accessToken: "OLD", refreshToken: "RT", expiresAt: Date().addingTimeInterval(-10), scope: "")
}

struct AuthTests {
    let config = AuthConfig(clientID: "cid", redirectURI: URL(string: "greedify://callback")!)

    @Test func verifierIsValid() {
        let v = PKCE.makeVerifier()
        #expect(v.count == 64)
        #expect(v.allSatisfy { PKCE.alphabet.contains($0) })
        #expect(PKCE.makeVerifier() != v)
    }

    @Test func challengeMatchesRFC7636Example() {
        // RFC 7636 appendix B
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func authorizationURLHasPKCEParams() {
        let url = AuthService(config: config, transport: StubTransport { _ in (200, "", [:]) })
            .authorizationURL(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "st")
        let q = URLRequest(url: url)
        #expect(url.host == "accounts.spotify.com")
        #expect(q.query("code_challenge") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(q.query("code_challenge_method") == "S256")
        #expect(q.query("redirect_uri") == "greedify://callback")
        #expect(q.query("scope")?.contains("user-modify-playback-state") == true)
    }

    @Test func callbackParsing() throws {
        #expect(try AuthService.code(from: URL(string: "greedify://callback?code=abc&state=st")!, expectedState: "st") == "abc")
        #expect(throws: AuthError.stateMismatch) { try AuthService.code(from: URL(string: "greedify://callback?code=abc&state=x")!, expectedState: "st") }
        #expect(throws: AuthError.denied("access_denied")) { try AuthService.code(from: URL(string: "greedify://callback?error=access_denied&state=st")!, expectedState: "st") }
    }

    @Test func exchangeSendsFormAndBuildsTokens() async throws {
        let stub = StubTransport { _ in (200, #"{"access_token":"A","refresh_token":"R","expires_in":3600,"scope":"s"}"#, [:]) }
        let fixed = Date(timeIntervalSince1970: 1000)
        let tokens = try await AuthService(config: config, transport: stub, now: { fixed }).exchange(code: "c", verifier: "v")
        #expect(tokens == Tokens(accessToken: "A", refreshToken: "R", expiresAt: fixed.addingTimeInterval(3600), scope: "s"))
        let body = stub.requests[0].bodyString
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code_verifier=v"))
        #expect(body.contains("redirect_uri=greedify%3A%2F%2Fcallback"))
    }

    @Test func refreshKeepsOldRefreshTokenWhenNotRotated() async throws {
        let stub = StubTransport { _ in (200, #"{"access_token":"A2","expires_in":3600}"#, [:]) }
        let fresh = try await AuthService(config: config, transport: stub).refresh(Fixture.expiredTokens)
        #expect(fresh.accessToken == "A2")
        #expect(fresh.refreshToken == "RT")
    }

    @Test func invalidGrantMeansReauth() async {
        let stub = StubTransport { _ in (400, #"{"error":"invalid_grant","error_description":"Refresh token revoked"}"#, [:]) }
        await #expect(throws: SpotifyError.reauthRequired) {
            try await AuthService(config: config, transport: stub).refresh(Fixture.expiredTokens)
        }
    }

    @Test func tokenExpiryMargin() {
        let now = Date()
        #expect(Tokens(accessToken: "", refreshToken: "", expiresAt: now.addingTimeInterval(30), scope: "").isExpired(now: now))
        #expect(!Tokens(accessToken: "", refreshToken: "", expiresAt: now.addingTimeInterval(120), scope: "").isExpired(now: now))
    }
}

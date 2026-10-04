import AppKit
import AuthenticationServices
import GreedifyKit

/// Runs the PKCE login (setup step 2). The login finishes either in the system sheet or, when the
/// user copied the link into another browser, through `greedify://callback` handed to `handleCallback`.
@MainActor
final class SpotifyLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?

    /// `onLoginURL` receives the authorize URL first, for "Copy Link". With `presentSheet: false` no sheet
    /// opens: the login completes when the copied link's `greedify://callback` reaches `handleCallback`.
    func logIn(auth: AuthService, store: TokenStore, presentSheet: Bool = true, onLoginURL: (URL) -> Void) async throws {
        finish(.failure(CancellationError())) // a newer attempt replaces any pending one
        let verifier = PKCE.makeVerifier()
        let state = PKCE.makeState()
        let url = auth.authorizationURL(verifier: verifier, state: state)
        onLoginURL(url)
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            continuation = cont
            guard presentSheet else { return }
            // The completion handler runs on a background XPC queue; @Sendable keeps it off the main actor
            // (a main-actor closure here trips Swift 6's runtime isolation check and crashes).
            let s = ASWebAuthenticationSession(url: url, callback: .customScheme("greedify")) { @Sendable [weak self] url, error in
                Task { @MainActor in
                    if let url { self?.finish(.success(url)) } else { self?.finish(.failure(error ?? AuthError.missingCode)) }
                }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            session = s
            if !s.start() { finish(.failure(AuthError.missingCode)) } // never leave the continuation hanging
        }
        let code = try AuthService.code(from: callback, expectedState: state)
        store.save(try await auth.exchange(code: code, verifier: verifier))
    }

    /// A `greedify://callback` URL opened from another browser. Returns true if it completed a pending login.
    @discardableResult
    func handleCallback(_ url: URL) -> Bool {
        guard url.scheme == "greedify", continuation != nil else { return false }
        finish(.success(url))
        return true
    }

    /// Resumes the pending login exactly once; closes the sheet if the other browser won.
    private func finish(_ result: Result<URL, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        let s = session
        session = nil
        if case .success = result { s?.cancel() }
        cont.resume(with: result)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor() }
    }
}

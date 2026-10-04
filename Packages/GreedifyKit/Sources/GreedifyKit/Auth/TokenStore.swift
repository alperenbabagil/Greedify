import Foundation
import Security

public struct Tokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var scope: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, scope: String) {
        self.accessToken = accessToken; self.refreshToken = refreshToken
        self.expiresAt = expiresAt; self.scope = scope
    }

    /// Whether Spotify granted `scope` to this token (`scope` is space-separated).
    public func hasScope(_ scope: String) -> Bool { self.scope.split(separator: " ").contains { $0 == scope } }

    /// True when the access token expires within `margin` seconds.
    public func isExpired(now: Date, margin: TimeInterval = 60) -> Bool {
        expiresAt.timeIntervalSince(now) < margin
    }
}

public protocol TokenStore: Sendable {
    func load() -> Tokens?
    func save(_ tokens: Tokens)
    func clear()
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: Tokens?
    public init(_ tokens: Tokens? = nil) { self.tokens = tokens }
    public func load() -> Tokens? { lock.withLock { tokens } }
    public func save(_ tokens: Tokens) { lock.withLock { self.tokens = tokens } }
    public func clear() { lock.withLock { tokens = nil } }
}

/// Stores tokens as one JSON blob in the login keychain.
public struct KeychainTokenStore: TokenStore {
    let service: String
    let account = "spotify-tokens"
    public init(service: String = "com.alperen.greedify") { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() -> Tokens? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else {
            if status != errSecItemNotFound { ErrorLog.shared.record("Keychain read failed: \(Self.describe(status))", category: "auth") }
            return nil
        }
        do { return try JSONDecoder().decode(Tokens.self, from: data) }
        catch { ErrorLog.shared.record("Keychain tokens unreadable: \(error)", category: "auth"); return nil }
    }

    public func save(_ tokens: Tokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(q as CFDictionary, nil)
        }
        if status != errSecSuccess { ErrorLog.shared.record("Keychain save failed: \(Self.describe(status))", category: "auth") }
    }

    static func describe(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?).map { "\($0) (\(status))" } ?? "\(status)"
    }

    public func clear() { SecItemDelete(query as CFDictionary) }
}

/// Keeps tokens in memory in front of a slow store (the Keychain). The Keychain is read once, off the
/// main thread, by `preload()`; until then `load()` returns nil instead of blocking. A Keychain read can
/// block indefinitely while macOS shows an access prompt, which froze the app when done on the main thread.
public final class CachedTokenStore: TokenStore, @unchecked Sendable {
    private let backing: TokenStore
    private let lock = NSLock()
    private var cached: Tokens?
    private var loaded = false

    public init(backing: TokenStore) { self.backing = backing }

    public var isLoaded: Bool { lock.withLock { loaded } }

    /// Reads the backing store once, on a background thread.
    public func preload() async {
        guard !isLoaded else { return }
        let backing = self.backing
        let tokens = await Task.detached(priority: .userInitiated) { backing.load() }.value
        lock.withLock {
            if !loaded { cached = tokens; loaded = true }
        }
    }

    public func load() -> Tokens? { lock.withLock { cached } }

    public func save(_ tokens: Tokens) {
        lock.withLock { cached = tokens; loaded = true }
        backing.save(tokens)
    }

    public func clear() {
        lock.withLock { cached = nil; loaded = true }
        backing.clear()
    }
}

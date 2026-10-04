import Foundation
import Testing
@testable import GreedifyKit

/// A backing store that counts reads and can be slow, like a Keychain waiting on a permission prompt.
final class SlowCountingStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: Tokens?
    private var reads = 0
    let delay: TimeInterval
    init(_ tokens: Tokens?, delay: TimeInterval = 0) { self.tokens = tokens; self.delay = delay }
    var readCount: Int { lock.withLock { reads } }
    func load() -> Tokens? {
        Thread.sleep(forTimeInterval: delay)
        return lock.withLock { reads += 1; return tokens }
    }
    func save(_ t: Tokens) { lock.withLock { tokens = t } }
    func clear() { lock.withLock { tokens = nil } }
}

struct CachedTokenStoreTests {
    @Test func readsTheBackingStoreOnceThenServesFromMemory() async {
        let backing = SlowCountingStore(Fixture.freshTokens)
        let store = CachedTokenStore(backing: backing)
        await store.preload()
        for _ in 0..<100 { _ = store.load() }
        #expect(store.load() == Fixture.freshTokens)
        #expect(backing.readCount == 1)
    }

    @Test func loadBeforePreloadNeverTouchesTheBackingStore() {
        let backing = SlowCountingStore(Fixture.freshTokens, delay: 2)
        let store = CachedTokenStore(backing: backing)
        let start = Date()
        #expect(store.load() == nil)            // not loaded yet: no blocking read on the caller's thread
        #expect(!store.isLoaded)
        #expect(Date().timeIntervalSince(start) < 0.5)
        #expect(backing.readCount == 0)
    }

    @Test func saveAndClearWriteThrough() async {
        let backing = SlowCountingStore(nil)
        let store = CachedTokenStore(backing: backing)
        await store.preload()
        store.save(Fixture.expiredTokens)
        #expect(store.load() == Fixture.expiredTokens)
        #expect(backing.load() == Fixture.expiredTokens)
        store.clear()
        #expect(store.load() == nil)
        #expect(backing.load() == nil)
    }
}

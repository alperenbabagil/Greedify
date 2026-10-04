import Foundation
import Testing
@testable import GreedifyKit

@MainActor
struct QuickPlayItemTests {
    func settings() -> AppSettings { AppSettings(defaults: UserDefaults(suiteName: "greedify-test-\(UUID().uuidString)")!) }
    let list = QuickPlayItem(uri: "spotify:playlist:37i9dQZF1E39vTG3GurFPW", name: "Daily Mix 1")
    let song = QuickPlayItem(uri: "spotify:track:4uLU6hMCjMI75M1A2tKUQC", name: "Never Gonna", subtitle: "Rick Astley")

    @Test func addRemoveAndNoDuplicates() {
        let s = settings()
        s.addToMenuBar(list)
        s.addToMenuBar(song)
        s.addToMenuBar(QuickPlayItem(uri: list.uri, name: "again"))
        #expect(s.quickPlay.map(\.name) == ["Daily Mix 1", "Never Gonna"])
        #expect(s.isInMenuBar(song.uri))
        s.removeFromMenuBar(list.uri)
        #expect(s.quickPlay == [song])
        #expect(!s.isInMenuBar(list.uri))
    }

    @Test func reorders() {
        let defaults = UserDefaults(suiteName: "greedify-test-\(UUID().uuidString)")!
        let s = AppSettings(defaults: defaults)
        let liked = QuickPlayItem(uri: "spotify:user:listener:collection", name: "Liked Songs")
        [list, song, liked].forEach(s.addToMenuBar)
        s.moveInMenuBar(list.uri, to: 2)
        #expect(s.quickPlay == [song, liked, list])
        s.moveInMenuBar(list.uri, to: 0)
        #expect(s.quickPlay == [list, song, liked])
        s.moveInMenuBar(song.uri, to: 1)
        #expect(s.quickPlay == [list, song, liked])
        s.moveInMenuBar(song.uri, to: 9)
        s.moveInMenuBar(song.uri, to: -1)
        s.moveInMenuBar("spotify:track:unknown", to: 0)
        #expect(s.quickPlay == [list, song, liked])
        s.moveInMenuBar(liked.uri, to: 0)
        #expect(AppSettings(defaults: defaults).quickPlay == [liked, list, song])
    }

    @Test func persists() {
        let defaults = UserDefaults(suiteName: "greedify-test-\(UUID().uuidString)")!
        AppSettings(defaults: defaults).addToMenuBar(song)
        #expect(AppSettings(defaults: defaults).quickPlay == [song])
    }

    @Test func aSongPlaysAloneAListPlaysAsAContext() {
        #expect(song.playRequest == .tracks([song.uri]))
        #expect(list.playRequest == .context(list.uri))
        let liked = QuickPlayItem(uri: "spotify:user:listener:collection", name: "Liked Songs")
        #expect(liked.playRequest == .context(liked.uri))
        #expect(song.isSong && !list.isSong)
    }
}

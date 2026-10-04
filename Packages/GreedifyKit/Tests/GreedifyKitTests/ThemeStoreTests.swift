import Foundation
import Testing
@testable import GreedifyKit

/// Built-in themes only; Debug builds add live `dev.` recipes (curated skins spec §4–§5).
@MainActor
struct ThemeStoreTests {
    let builtinIDs = ["builtin.system", "builtin.classic", "builtin.modern", "builtin.paper", "builtin.high-contrast",
                      "builtin.winamp-classic", "builtin.winamp5-classified"]

    func settings(_ themeID: String? = nil) -> AppSettings {
        let d = UserDefaults(suiteName: "greedify-test-\(UUID().uuidString)")!
        if let themeID { d.set(themeID, forKey: "themeID") }
        return AppSettings(defaults: d, hostName: "Mac")
    }
    func themeData(_ name: String, source: String? = nil) -> Data {
        Data(#"{"name":"\#(name)","base":"light"\#(source.map { #","source":"\#($0)""# } ?? "")}"#.utf8)
    }

    @Test func listsTheBuiltinsInOrder() {
        let store = ThemeStore(settings: settings())
        #expect(store.entries.map(\.id) == builtinIDs)
        #expect(store.current.isSystem)
    }

    @Test func curatedRecipesShipWithoutDroppedKeys() throws {
        for slug in ["winamp-classic", "winamp5-classified"] {
            let url = try #require(Theme.builtinURL(slug))
            let theme = try Style.$strict.withValue(true) { try Theme.decode(from: Data(contentsOf: url)) }
            #expect(theme.style?.bar?.layout == .winamp, "\(slug)")
            #expect(theme.source?.hasPrefix("Winamp skin ") == true, "\(slug)")
            // The whole window looks like Winamp (winamp window spec).
            let style = try #require(theme.style)
            #expect(style.list?.layout == .playlist && style.pageHeader?.layout == .strip, "\(slug)")
            #expect(style.frame?.title?.prefix == "WINAMP", "\(slug)")
            #expect(style.bar?.transport == .winamp && style.bar?.readouts == true && style.bar?.analyser?.isEmpty == false, "\(slug)")
            #expect(style.text[.lyrics]?.size != nil, "\(slug)")
        }
        // Classified follows its skin: steel title bars with bold lettering, rounded LCDs, round transport buttons.
        let url = try #require(Theme.builtinURL("winamp5-classified"))
        let classified = try #require(try Style.$strict.withValue(true) { try Theme.decode(from: Data(contentsOf: url)) }.style)
        #expect(classified.frame?.title?.background != nil && classified.frame?.title?.font == .system)
        #expect(classified.lcd?.radius != nil && classified.button?.shape == .circle && classified.button?.labelShape == .pill)
        #expect(classified.list?.font == .family("Arial") && (classified.bar?.analyser?.count ?? 0) >= 8)
    }

    @Test func devRecipesAreListedAndReload() {
        let dev = MemoryThemeFolder()
        dev.files["try.greedifytheme"] = themeData("Try")
        let store = ThemeStore(settings: settings(), devFolder: dev)
        #expect(store.entries.last?.id == "dev.try.greedifytheme" && store.entries.last?.theme?.name == "Try")
        store.select("dev.try.greedifytheme")
        dev.files["try.greedifytheme"] = themeData("Tried")
        store.reload()
        #expect(store.current.theme?.name == "Tried")
    }

    @Test func aBrokenDevRecipeIsListedButNeverCurrent() {
        let dev = MemoryThemeFolder()
        dev.files["bad.greedifytheme"] = Data("{nope".utf8)
        let store = ThemeStore(settings: settings(), devFolder: dev)
        store.select("dev.bad.greedifytheme")
        #expect(store.entries.first { $0.id == "dev.bad.greedifytheme" }?.error != nil)
        #expect(store.current.isSystem)
    }

    @Test func selectionPersists() {
        let s = settings()
        ThemeStore(settings: s).select("builtin.paper")
        #expect(ThemeStore(settings: s).current.id == "builtin.paper")
    }

    @Test func anImportedSkinMapsToItsCuratedTheme() {
        let legacy = MemoryThemeFolder()
        legacy.files["base 2.greedifytheme"] = themeData("base", source: "Winamp skin base-2.91.wsz")
        let s = settings("base 2.greedifytheme")
        let store = ThemeStore(settings: s, legacyFolder: legacy)
        #expect(store.current.id == "builtin.winamp-classic" && s.themeID == "builtin.winamp-classic")
    }

    @Test func anUnreadableImportMapsByFileName() {
        let s = settings("Winamp5_Classified_v5.5.greedifytheme")
        #expect(ThemeStore(settings: s, legacyFolder: MemoryThemeFolder()).current.id == "builtin.winamp5-classified")
    }

    @Test func anyOtherImportMapsToSystem() {
        let s = settings("pinkies.greedifytheme")
        let store = ThemeStore(settings: s, legacyFolder: MemoryThemeFolder())
        #expect(store.current.isSystem && s.themeID == ThemeStore.systemID)
    }

    @Test func diskFolderReadsRecipes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try themeData("Disk").write(to: dir.appendingPathComponent("disk.greedifytheme"))
        let store = ThemeStore(settings: settings(), devFolder: DiskThemeFolder(directory: dir))
        #expect(store.entries.contains { $0.id == "dev.disk.greedifytheme" && $0.theme?.name == "Disk" })
    }
}

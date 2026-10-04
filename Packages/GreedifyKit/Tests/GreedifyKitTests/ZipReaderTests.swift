import Foundation
import Testing
@testable import GreedifyKit

struct ZipReaderTests {
    let text = Data(String(repeating: "Normal=#00FF00\n", count: 200).utf8)

    @Test func readsStoredAndDeflatedEntries() throws {
        var zip = ZipBuilder()
        zip.add("stored.txt", Data("hello".utf8))
        zip.add("deflated.txt", text, deflate: true)
        let reader = try ZipReader(data: zip.build())
        #expect(try reader.contents(of: #require(reader.entry(named: "stored.txt"))) == Data("hello".utf8))
        #expect(try reader.contents(of: #require(reader.entry(named: "deflated.txt"))) == text)
    }

    @Test func findsEntriesInSubfoldersIgnoringCase() throws {
        var zip = ZipBuilder()
        zip.add("My Skin/", Data())
        zip.add("My Skin/PLEDIT.TXT", Data("x".utf8))
        let reader = try ZipReader(data: zip.build())
        #expect(reader.entry(named: "pledit.txt")?.path == "My Skin/PLEDIT.TXT")
        #expect(reader.entries.count == 1) // the folder entry is skipped
    }

    @Test func ignoresAppleDoubleEntries() throws {
        var zip = ZipBuilder()
        zip.add("__MACOSX/._main.bmp", Data("resource fork".utf8))
        zip.add("__MACOSX/main.bmp", Data("also junk".utf8))
        zip.add("main.bmp", Data("real".utf8))
        let reader = try ZipReader(data: zip.build())
        #expect(try reader.contents(of: #require(reader.entry(named: "main.bmp"))) == Data("real".utf8))
    }

    @Test func refusesOversizedArchives() {
        #expect(throws: ZipReader.ZipError.tooLarge) { try ZipReader(data: Data(count: ZipReader.maxArchiveBytes + 1)) }
    }

    @Test func refusesEntriesThatClaimToBeHuge() throws {
        var zip = ZipBuilder()
        zip.add("bomb.txt", text, deflate: true, claimedSize: ZipReader.maxEntryBytes + 1)
        let reader = try ZipReader(data: zip.build())
        #expect(throws: ZipReader.ZipError.tooLarge) { try reader.contents(of: #require(reader.entry(named: "bomb.txt"))) }
    }

    @Test func lyingDeflateSizeIsCorrupt() throws {
        var zip = ZipBuilder()
        zip.add("liar.txt", text, deflate: true, claimedSize: 100) // really 3000 bytes
        let reader = try ZipReader(data: zip.build())
        #expect(throws: ZipReader.ZipError.corrupt) { try reader.contents(of: #require(reader.entry(named: "liar.txt"))) }
    }

    @Test func garbageAndTruncatedArchivesAreCorrupt() {
        var zip = ZipBuilder()
        zip.add("a.txt", Data("a".utf8))
        let good = zip.build()
        #expect(throws: ZipReader.ZipError.corrupt) { try ZipReader(data: Data("definitely not a zip file at all".utf8)) }
        #expect(throws: ZipReader.ZipError.corrupt) { try ZipReader(data: good.dropLast(10)) }
        #expect(throws: ZipReader.ZipError.corrupt) { try ZipReader(data: Data()) }
    }
}

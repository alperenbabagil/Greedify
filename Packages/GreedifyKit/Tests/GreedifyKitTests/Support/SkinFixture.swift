import Foundation

/// Hand-made `.wsz` archives for tests (never real skins: those belong to their authors).
enum SkinFixture {
    static let classicPledit = "[Text]\nNormal=#00FF00\nCurrent=#FFFFFF\nNormalBG=#000000\nSelectedBG=#0000C6\nFont=Arial\n"

    static func wsz(_ files: [String: Data], folder: String = "") -> Data {
        var zip = ZipBuilder()
        for (name, data) in files.sorted(by: { $0.key < $1.key }) { zip.add(folder + name, data, deflate: true) }
        return zip.build()
    }
}

import Foundation
@testable import GreedifyKit

final class MemoryThemeFolder: ThemeFolder {
    var files: [String: Data] = [:]
    var url: URL? { nil }
    func list() throws -> [String] { Array(files.keys) }
    func read(_ name: String) throws -> Data {
        guard let data = files[name] else { throw CocoaError(.fileNoSuchFile) }
        return data
    }
    func write(_ data: Data, as name: String) throws { files[name] = data }
    func delete(_ name: String) throws { files[name] = nil }
}

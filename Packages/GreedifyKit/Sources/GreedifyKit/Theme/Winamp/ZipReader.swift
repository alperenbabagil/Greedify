import Compression
import Foundation

/// Reads a zip archive in memory (spec §3): `stored` and `deflate` entries only, no encryption, no zip64.
/// CRCs aren't checked; the contents are only parsed for colors. Entry paths are matched, never written to disk.
struct ZipReader {
    static let maxArchiveBytes = 10 * 1_048_576
    static let maxEntryBytes = 5 * 1_048_576

    enum ZipError: Error, Equatable { case tooLarge, corrupt, unsupported }

    struct Entry {
        let path: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int

        var fileName: String { path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path }
    }

    private let data: Data
    let entries: [Entry]

    init(data: Data) throws {
        guard data.count <= Self.maxArchiveBytes else { throw ZipError.tooLarge }
        self.data = data
        entries = try Self.readCentralDirectory(data)
    }

    /// The entry whose file name (last path component) is `name`, ignoring case.
    func entry(named name: String) -> Entry? {
        entries.first { $0.fileName.caseInsensitiveCompare(name) == .orderedSame }
    }

    func contents(of entry: Entry) throws -> Data {
        guard entry.uncompressedSize <= Self.maxEntryBytes else { throw ZipError.tooLarge }
        let header = entry.localHeaderOffset
        guard header >= 0, header + 30 <= data.count, data.le32(at: header) == 0x04034b50 else { throw ZipError.corrupt }
        let start = header + 30 + Int(data.le16(at: header + 26)) + Int(data.le16(at: header + 28))
        guard start + entry.compressedSize <= data.count else { throw ZipError.corrupt }
        let raw = data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + entry.compressedSize))
        switch entry.method {
        case 0:
            guard raw.count == entry.uncompressedSize else { throw ZipError.corrupt }
            return raw
        case 8:
            return try Self.inflate(raw, size: entry.uncompressedSize)
        default:
            throw ZipError.unsupported
        }
    }

    /// Raw deflate into a buffer one byte larger than claimed, so an entry that inflates past its
    /// declared size is caught instead of being silently truncated.
    private static func inflate(_ source: Data, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        guard !source.isEmpty else { throw ZipError.corrupt }
        var out = Data(count: size + 1)
        let written = out.withUnsafeMutableBytes { dst in
            source.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size + 1,
                                          src.bindMemory(to: UInt8.self).baseAddress!, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw ZipError.corrupt }
        return Data(out.prefix(size))
    }

    private static func readCentralDirectory(_ d: Data) throws -> [Entry] {
        guard d.count >= 22 else { throw ZipError.corrupt }
        var end: Int?
        var i = d.count - 22
        let floor = max(0, d.count - 22 - 65_535) // the archive comment is at most 64 KB
        while i >= floor {
            if d.le32(at: i) == 0x06054b50 { end = i; break }
            i -= 1
        }
        guard let end else { throw ZipError.corrupt }
        let count = Int(d.le16(at: end + 10))
        var p = Int(d.le32(at: end + 16))
        var entries: [Entry] = []
        for _ in 0..<count {
            guard p + 46 <= d.count, d.le32(at: p) == 0x02014b50 else { throw ZipError.corrupt }
            let flags = d.le16(at: p + 8)
            let method = d.le16(at: p + 10)
            let compressed = Int(d.le32(at: p + 20)), uncompressed = Int(d.le32(at: p + 24))
            let nameLength = Int(d.le16(at: p + 28)), extra = Int(d.le16(at: p + 30)), comment = Int(d.le16(at: p + 32))
            let offset = Int(d.le32(at: p + 42))
            guard p + 46 + nameLength <= d.count else { throw ZipError.corrupt }
            let nameData = d.subdata(in: (d.startIndex + p + 46)..<(d.startIndex + p + 46 + nameLength))
            let path = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) ?? ""
            p += 46 + nameLength + extra + comment
            // Skip encrypted entries, folders and macOS AppleDouble metadata.
            if flags & 1 != 0 || path.hasSuffix("/") || path.hasPrefix("__MACOSX/") { continue }
            entries.append(Entry(path: path, method: method, compressedSize: compressed,
                                 uncompressedSize: uncompressed, localHeaderOffset: offset))
        }
        return entries
    }
}

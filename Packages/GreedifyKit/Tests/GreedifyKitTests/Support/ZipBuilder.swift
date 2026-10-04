import Compression
import Foundation

extension Data {
    mutating func appendLE16(_ v: UInt16) { append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8)]) }
    mutating func appendLE32(_ v: UInt32) { appendLE16(UInt16(v & 0xFFFF)); appendLE16(UInt16(v >> 16)) }
}

/// Builds small zip archives for tests: stored or deflated entries, CRCs left at 0.
struct ZipBuilder {
    private var items: [(path: String, data: Data, deflate: Bool, claimedSize: Int?)] = []

    /// `claimedSize` overrides the uncompressed size written to the headers (for zip-bomb and corrupt-size tests).
    mutating func add(_ path: String, _ data: Data, deflate: Bool = false, claimedSize: Int? = nil) {
        items.append((path, data, deflate && !data.isEmpty, claimedSize))
    }

    func build() -> Data {
        var out = Data(), central = Data()
        for item in items {
            let payload = item.deflate ? Self.deflate(item.data) : item.data
            let name = Data(item.path.utf8)
            let method: UInt16 = item.deflate ? 8 : 0
            let offset = UInt32(out.count)
            let size = UInt32(item.claimedSize ?? item.data.count)
            // Local file header (30 bytes + name).
            out.appendLE32(0x04034b50); out.appendLE16(20); out.appendLE16(0); out.appendLE16(method)
            out.appendLE16(0); out.appendLE16(0); out.appendLE32(0)
            out.appendLE32(UInt32(payload.count)); out.appendLE32(size)
            out.appendLE16(UInt16(name.count)); out.appendLE16(0)
            out.append(name); out.append(payload)
            // Central directory header (46 bytes + name).
            central.appendLE32(0x02014b50); central.appendLE16(20); central.appendLE16(20); central.appendLE16(0)
            central.appendLE16(method); central.appendLE16(0); central.appendLE16(0); central.appendLE32(0)
            central.appendLE32(UInt32(payload.count)); central.appendLE32(size)
            central.appendLE16(UInt16(name.count)); central.appendLE16(0); central.appendLE16(0)
            central.appendLE16(0); central.appendLE16(0); central.appendLE32(0); central.appendLE32(offset)
            central.append(name)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        // End of central directory (22 bytes).
        out.appendLE32(0x06054b50); out.appendLE16(0); out.appendLE16(0)
        out.appendLE16(UInt16(items.count)); out.appendLE16(UInt16(items.count))
        out.appendLE32(UInt32(central.count)); out.appendLE32(centralOffset); out.appendLE16(0)
        return out
    }

    static func deflate(_ data: Data) -> Data {
        var out = Data(count: data.count + 1024)
        let written = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, dst.count,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return Data(out.prefix(written))
    }
}

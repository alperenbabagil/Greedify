import CryptoKit
import Foundation

/// Size-capped disk cache with least-recently-used eviction.
/// Recency is the file modification date, bumped on every read.
public actor DataCache {
    public let directory: URL
    public private(set) var limitBytes: Int
    let fm = FileManager.default

    public init(directory: URL, limitBytes: Int) {
        self.directory = directory
        self.limitBytes = limitBytes
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func fileURL(for key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }

    public func data(for key: String) -> Data? {
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    public func store(_ data: Data, for key: String) {
        do { try data.write(to: fileURL(for: key), options: .atomic) }
        catch { ErrorLog.shared.record("can't write \(key): \(error.localizedDescription)", category: "cache") }
        evictIfNeeded()
    }

    public func value<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        data(for: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    public func store<T: Encodable>(_ value: T, for key: String) {
        if let data = try? JSONEncoder().encode(value) { store(data, for: key) }
    }

    public func remove(_ key: String) { try? fm.removeItem(at: fileURL(for: key)) }

    public func setLimit(_ bytes: Int) {
        limitBytes = bytes
        evictIfNeeded()
    }

    struct Entry { let url: URL; let size: Int; let date: Date }

    func entries() -> [Entry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return Entry(url: url, size: v.fileSize ?? 0, date: v.contentModificationDate ?? .distantPast)
        }
    }

    public func sizeBytes() -> Int { entries().reduce(0) { $0 + $1.size } }

    /// Deletes oldest-used files until the total is within the limit.
    public func evictIfNeeded() {
        var list = entries()
        var total = list.reduce(0) { $0 + $1.size }
        guard total > limitBytes else { return }
        list.sort { $0.date < $1.date }
        for entry in list where total > limitBytes {
            try? fm.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    public func clear() {
        for entry in entries() { try? fm.removeItem(at: entry.url) }
    }
}

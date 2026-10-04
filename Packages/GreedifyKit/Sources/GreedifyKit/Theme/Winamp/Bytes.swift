import Foundation

extension Data {
    /// Little-endian reads at a byte offset from the start; callers check bounds first.
    func le16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    func le32(at offset: Int) -> UInt32 {
        UInt32(le16(at: offset)) | UInt32(le16(at: offset + 2)) << 16
    }
}

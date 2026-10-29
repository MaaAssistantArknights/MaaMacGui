import Foundation

/// AsstGetImage writes PNG bytes and returns their length, or a null-size sentinel. It has no size-query API.
enum PreviewImageBuffer {
    static let capacity = 8 * 1024 * 1024

    static func read(
        nullSize: UInt64, capacity: Int = capacity,
        using read: (UnsafeMutableRawBufferPointer) -> UInt64
    ) throws -> Data {
        guard capacity > 0, capacity <= self.capacity else { throw PreviewError.invalidImage }
        var data = Data(count: capacity)
        let count = data.withUnsafeMutableBytes(read)
        guard count != nullSize, count > 0, count <= UInt64(capacity) else {
            throw PreviewError.invalidImage
        }
        data.count = Int(count)
        return data
    }
}

enum PreviewError: Error {
    case disconnected
    case captureInProgress
    case timedOut
    case invalidImage
}

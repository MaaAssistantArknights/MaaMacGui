import Foundation

/// AsstGetImage writes PNG bytes and returns their length, or a null-size sentinel. It has no size-query API.
enum PreviewImageBuffer {
    static let capacity = 8 * 1024 * 1024
    static let maximumCapacity = 64 * 1024 * 1024

    static func read(
        nullSize: UInt64, capacity: Int = capacity,
        maximumCapacity: Int = maximumCapacity,
        allocate: (Int) -> Data = { Data(count: $0) },
        using read: (UnsafeMutableRawBufferPointer) -> UInt64
    ) throws -> Data {
        guard capacity > 0, capacity <= maximumCapacity, maximumCapacity <= self.maximumCapacity else {
            throw PreviewError.invalidImage
        }
        var capacity = capacity
        while true {
            // Keep each allocation in this scope so a failed attempt is released before retrying.
            let (result, count): (Data?, UInt64) = try {
                var data = allocate(capacity)
                guard data.count == capacity else { throw PreviewError.invalidImage }
                let count = data.withUnsafeMutableBytes(read)
                if count != nullSize, count > 0, count <= UInt64(capacity) {
                    data.count = Int(count)
                    return (data, count)
                }
                return (nil, count)
            }()
            if let result { return result }
            guard count > 0, capacity < maximumCapacity,
                count == nullSize || count <= UInt64(maximumCapacity)
            else { throw PreviewError.invalidImage }
            // Core uses the same sentinel for an invalid handle and an undersized buffer.
            // Bound retries and allocations even when no image can ever be returned.
            capacity = min(maximumCapacity, max(capacity * 2, count == nullSize ? 0 : Int(count)))
        }
    }
}

enum PreviewError: Error {
    case disconnected
    case captureInProgress
    case timedOut
    case invalidImage
}

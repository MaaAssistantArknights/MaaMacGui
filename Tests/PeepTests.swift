import SwiftUI

final class BufferAllocations {
    var allocated = 0
    var released = 0
    var live: Int { allocated - released }

    func allocate(_ capacity: Int) -> Data {
        allocated += 1
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 1)
        return Data(bytesNoCopy: bytes, count: capacity, deallocator: .custom { bytes, _ in
            bytes.deallocate()
            self.released += 1
        })
    }
}

@MainActor final class MAAViewModel {
    var reads = 0
    var delay = false
    var failure = false
    var lastMaxPixelSize: Int?
    func previewFrame(maxPixelSize: Int? = nil) async throws -> PreviewFrame {
        reads += 1
        lastMaxPixelSize = maxPixelSize
        if delay { try await Task.sleep(for: .seconds(1)) }
        if failure { throw PreviewError.disconnected }
        return PreviewFrame(image: NSImage(size: NSSize(width: 2, height: 2)), readAt: Date(), requestedCapture: true)
    }
}

@main struct PeepTests {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ value: Bool, _ name: String) {
            count += 1
            if !value { fatalError("FAIL: \(name)") }
        }
        func rejects(_ name: String, _ read: () throws -> Data) {
            do {
                _ = try read()
                check(false, name)
            } catch PreviewError.invalidImage { check(true, name) }
            catch { fatalError("wrong error for \(name): \(error)") }
        }
        let full = try PreviewImageBuffer.read(nullSize: .max, capacity: 4) { bytes in
            for i in 0..<4 { bytes[i] = UInt8(i) }
            return 4
        }
        check(full == Data([0, 1, 2, 3]), "exact capacity")
        let short = try PreviewImageBuffer.read(nullSize: .max, capacity: 4) { bytes in
            bytes[0] = 9
            return 1
        }
        check(short == Data([9]), "actual length, no uninitialized tail")
        let largeSize = 9 * 1024 * 1024
        var capacities = [Int]()
        let large = try PreviewImageBuffer.read(nullSize: .max) { bytes in
            capacities.append(bytes.count)
            guard bytes.count >= largeSize else { return .max }
            bytes[0] = 17
            bytes[largeSize - 1] = 23
            return UInt64(largeSize)
        }
        check(large.count == largeSize && large.first == 17 && large.last == 23, "image larger than 8 MiB")
        check(capacities == [8 * 1024 * 1024, 16 * 1024 * 1024], "null-size retry grows capacity")
        rejects("null sentinel") { try PreviewImageBuffer.read(nullSize: .max, capacity: 4, maximumCapacity: 4) { _ in .max } }
        rejects("zero bytes") { try PreviewImageBuffer.read(nullSize: .max, capacity: 4) { _ in 0 } }
        rejects("overflow result") { try PreviewImageBuffer.read(nullSize: .max, capacity: 4, maximumCapacity: 4) { _ in 5 } }
        rejects("zero capacity") { try PreviewImageBuffer.read(nullSize: .max, capacity: 0) { _ in 0 } }
        rejects("negative capacity") { try PreviewImageBuffer.read(nullSize: .max, capacity: -1) { _ in 0 } }
        rejects("unbounded allocation") { try PreviewImageBuffer.read(nullSize: .max, capacity: .max) { _ in 0 } }
        rejects("unbounded retry limit") {
            try PreviewImageBuffer.read(nullSize: .max, maximumCapacity: .max) { _ in 0 }
        }
        var reportedCapacities = [Int]()
        let reported = try PreviewImageBuffer.read(nullSize: .max, capacity: 32, maximumCapacity: 128) { bytes in
            reportedCapacities.append(bytes.count)
            guard bytes.count >= 100 else { return 100 }
            bytes[0] = 42
            return 100
        }
        check(reported.count == 100 && reported.first == 42, "reported length can grow buffer")
        check(reportedCapacities == [32, 100], "bounded reported length used for retry")
        let allocations = BufferAllocations()
        for _ in 0..<1000 {
            rejects("failed read rejects") {
                try PreviewImageBuffer.read(nullSize: .max, capacity: 32, maximumCapacity: 32,
                                            allocate: allocations.allocate) { _ in .max }
            }
            check(allocations.live == 0, "every failed read releases its buffer")
        }
        check(allocations.allocated == 1000 && allocations.released == 1000, "all failed allocations accounted for")
        var retryCapacities = [Int]()
        rejects("bounded retry failure") {
            try PreviewImageBuffer.read(nullSize: .max, capacity: 32, maximumCapacity: 128,
                                        allocate: allocations.allocate) { bytes in
                retryCapacities.append(bytes.count)
                check(allocations.live == 1, "previous attempt released before retry")
                return .max
            }
        }
        check(retryCapacities == [32, 64, 128], "sentinel retry stops at limit")
        check(allocations.live == 0 && allocations.released == 1003, "exhausted retries release all buffers")
        rejects("zero-length read releases buffer") {
            try PreviewImageBuffer.read(nullSize: .max, capacity: 32,
                                        allocate: allocations.allocate) { _ in 0 }
        }
        rejects("impossible length releases buffer") {
            try PreviewImageBuffer.read(nullSize: .max, capacity: 32,
                                        allocate: allocations.allocate) { _ in UInt64.max - 1 }
        }
        check(allocations.live == 0 && allocations.released == 1005, "invalid results release buffers")
        do {
            let truncated = try PreviewImageBuffer.read(nullSize: .max, capacity: 32, maximumCapacity: 128,
                                                       allocate: allocations.allocate) { bytes in
                for i in 0..<20 { bytes[i] = UInt8(i) }
                return 20
            }
            check(truncated == Data((0..<20).map(UInt8.init)), "no-copy buffer keeps only written bytes")
        }
        check(allocations.live == 0 && allocations.released == 1006, "truncated no-copy buffer releases once")
        do {
            var filled = PreviewImageBuffer.allocate(4096)
            let written: UInt64 = filled.withUnsafeMutableBytes { bytes in
                for i in 0..<9 { bytes[i] = UInt8(i + 1) }
                return 9
            }
            filled.count = Int(written)
            check(filled == Data((1...9).map(UInt8.init)), "production allocation truncates to written bytes")
        }
        rejects("production failure chain stays bounded") {
            try PreviewImageBuffer.read(nullSize: .max) { _ in .max }
        }
        let source = MAAViewModel()
        let model = PeepViewModel()
        await model.refresh(from: source)
        check(model.frame != nil && model.error == nil && !model.isReading, "successful frame")
        check(source.lastMaxPixelSize == nil, "first frame decodes at full size")
        await model.refresh(from: source, maxPixelSize: 1234)
        check(source.lastMaxPixelSize == 1234 && model.frame != nil, "refresh forwards pixel limit")
        source.failure = true
        await model.refresh(from: source)
        check(model.frame != nil && model.error != nil && !model.isReading, "retain old frame with failure")
        source.failure = false
        source.delay = true
        let request = Task { await model.refresh(from: source) }
        await Task.yield()
        while !model.isReading { await Task.yield() }
        let reads = source.reads
        await model.refresh(from: source)
        check(source.reads == reads, "single in-flight request")
        model.cancel()
        await request.value
        check(!model.isReading, "disappear cancels request")
        let previous = model.frame?.readAt
        try await Task.sleep(for: .milliseconds(30))
        check(model.frame?.readAt == previous, "late cancellation cannot publish")
        source.delay = true
        let older = Task { await model.refresh(from: source) }
        while !model.isReading { await Task.yield() }
        model.cancel()
        source.delay = false
        await model.refresh(from: source)
        let newDate = model.frame?.readAt
        await older.value
        check(model.frame?.readAt == newDate && !model.isReading, "old generation cannot overwrite a new request")
        for _ in 0..<20 {
            await model.refresh(from: source)
            model.cancel()
        }
        check(!model.isReading, "twenty lifecycle cycles release request")
        let cancelled = Task {
            await model.refresh(from: source)
        }
        cancelled.cancel()
        await cancelled.value
        check(!model.isReading, "parent cancellation releases request")
        print("Passed \(count) assertions against production preview buffer and view model")
    }
}

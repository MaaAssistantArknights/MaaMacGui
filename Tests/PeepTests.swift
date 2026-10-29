import SwiftUI

@MainActor final class MAAViewModel {
    var reads = 0
    var delay = false
    var failure = false
    func previewFrame() async throws -> PreviewFrame {
        reads += 1
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
            } catch { check(true, name) }
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
        rejects("null sentinel") { try PreviewImageBuffer.read(nullSize: .max, capacity: 4) { _ in .max } }
        rejects("zero bytes") { try PreviewImageBuffer.read(nullSize: .max, capacity: 4) { _ in 0 } }
        rejects("overflow result") { try PreviewImageBuffer.read(nullSize: .max, capacity: 4) { _ in 5 } }
        rejects("zero capacity") { try PreviewImageBuffer.read(nullSize: .max, capacity: 0) { _ in 0 } }
        rejects("negative capacity") { try PreviewImageBuffer.read(nullSize: .max, capacity: -1) { _ in 0 } }
        rejects("unbounded allocation") { try PreviewImageBuffer.read(nullSize: .max, capacity: .max) { _ in 0 } }
        for _ in 0..<1000 {
            rejects("repeated failure releases owned data") {
                try PreviewImageBuffer.read(nullSize: .max, capacity: 32) { _ in .max }
            }
        }
        let source = MAAViewModel()
        let model = PeepViewModel()
        await model.refresh(from: source)
        check(model.frame != nil && model.error == nil && !model.isReading, "successful frame")
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

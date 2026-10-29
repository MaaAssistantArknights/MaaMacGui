import AppKit
import Foundation

typealias AsstAsyncCallId = Int32
typealias AsstSize = UInt64
struct JSON {
    var ret: Bool
    subscript(_ key: String) -> JSON { self }
    subscript<T>(_ key: String) -> T { get throws { ret as! T } }
}
struct TestLogger { func error(_ message: String) {} }
let logger = TestLogger()
enum MaaCoreError: Error { case getImageFailed }

final class NativeFixture: @unchecked Sendable {
    static let shared = NativeFixture()
    private let lock = NSLock()
    private var connectedValue = true
    private var runningValue = false
    private var count: Int32 = 0
    var connected: Bool { lock.withLock { connectedValue } }
    var running: Bool { lock.withLock { runningValue } }
    var requests: Int32 { lock.withLock { count } }
    func configure(connected: Bool = true, running: Bool = false) {
        lock.withLock {
            connectedValue = connected
            runningValue = running
        }
    }
    func capture() -> Int32 {
        lock.withLock {
            count += 1
            return count
        }
    }
    let png: Data = {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return bitmap.representation(using: .png, properties: [:])!
    }()
}
func AsstConnected(_ handle: Int) -> Bool { NativeFixture.shared.connected }
func AsstRunning(_ handle: Int) -> Bool { NativeFixture.shared.running }
func AsstAsyncScreencap(_ handle: Int, _ block: Int) -> Int32 { NativeFixture.shared.capture() }
func AsstGetNullSize() -> UInt64 { .max }
func AsstGetImage(_ handle: Int, _ buffer: UnsafeMutableRawPointer?, _ size: UInt64) -> UInt64 {
    let data = NativeFixture.shared.png
    guard UInt64(data.count) <= size else { return .max }
    data.copyBytes(to: buffer!.assumingMemoryBound(to: UInt8.self), count: data.count)
    return UInt64(data.count)
}
extension Bool { var isTrue: Bool { self } }

@main struct CorePreviewTests {
    static func main() async throws {
        var checks = 0
        func check(_ value: Bool, _ name: String) {
            checks += 1
            if !value { fatalError("FAIL: \(name)") }
        }
        let native = NativeFixture.shared
        let core = MAAHandle()
        native.configure(connected: false)
        do {
            _ = try await core.previewImage(requestFresh: true)
            fatalError("disconnected accepted")
        } catch { check(error is PreviewError, "disconnected rejects") }
        check(native.requests == 0, "disconnected no capture")
        native.configure(running: true)
        let cached = try await core.previewImage(requestFresh: true)
        check(!cached.1 && cached.0.width == 2 && native.requests == 0, "running only reads cache")
        native.configure()
        let first = Task { try await core.previewImage(requestFresh: true) }
        while native.requests < 1 { await Task.yield() }
        do {
            _ = try await core.previewImage(requestFresh: true)
            fatalError("second capture accepted")
        } catch { check(error is PreviewError, "one native request in flight") }
        let oldToken = await core.previewToken!
        await core.deliver(1, success: true)
        let firstFrame = try await first.value
        check(firstFrame.1 && firstFrame.0.height == 2, "idle confirmed capture")
        let second = Task { try await core.previewImage(requestFresh: true) }
        while native.requests < 2 { await Task.yield() }
        second.cancel()
        do {
            _ = try await second.value
            fatalError("cancel accepted")
        } catch { check(error is CancellationError, "cancel promptly releases waiter") }
        do {
            _ = try await core.previewImage(requestFresh: true)
            fatalError("cancel forgot native call")
        } catch { check(error is PreviewError && native.requests == 2, "cancel retains native reservation") }
        await core.deliver(2, success: true)
        let third = Task { try await core.previewImage(requestFresh: true) }
        while native.requests < 3 { await Task.yield() }
        await core.deliver(3, success: false)
        do {
            _ = try await third.value
            fatalError("failure accepted")
        } catch { check(error is MaaCoreError, "native failure surfaced") }
        let timeout = Task { try await core.previewImage(requestFresh: true) }
        while native.requests < 4 { await Task.yield() }
        do {
            _ = try await timeout.value
            fatalError("timeout accepted")
        } catch { check(error is PreviewError, "ten-second timeout") }
        do {
            _ = try await core.previewImage(requestFresh: true)
            fatalError("timeout forgot native call")
        } catch { check(native.requests == 4, "timeout keeps native reservation") }
        await core.deliver(4, success: true)
        _ = try await core.previewImage(requestFresh: false)
        check(native.requests == 4, "late callback clears reservation, cached read adds no request")
        let newer = Task { try await core.previewImage(requestFresh: true) }
        while native.requests < 5 { await Task.yield() }
        await core.cancelStale(oldToken)
        await core.deliver(5, success: true)
        let recovered = try await newer.value
        check(recovered.1, "stale cancellation token cannot cancel newer capture")
        let cancelled = Task { try await core.previewImage(requestFresh: true) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            fatalError("pre-cancel accepted")
        } catch { check(error is CancellationError, "pre-cancelled task rejected") }
        check(native.requests == 5, "pre-cancelled no native request")
        print("Passed \(checks) production actor preview assertions")
    }
}

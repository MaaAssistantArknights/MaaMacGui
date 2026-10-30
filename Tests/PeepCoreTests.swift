import AppKit
import Foundation

typealias AsstAsyncCallId = Int32
typealias AsstSize = UInt64
struct JSON {
    private let value: Any?
    init(ret: Bool) { value = ["details": ["ret": ret]] }
    init(value: Any?) { self.value = value }
    subscript(_ key: String) -> JSON { JSON(value: (value as? [String: Any])?[key]) }
    subscript<T>(_ key: String) -> T {
        get throws {
            guard let result = (value as? [String: Any])?[key] as? T else {
                throw InvalidJSONValue(key: key)
            }
            return result
        }
    }
}
struct InvalidJSONValue: Error { let key: String }
struct TestLogger { func error(_ message: String) {} }
let logger = TestLogger()
enum MaaCoreError: Error { case getImageFailed }

final class NativeFixture: @unchecked Sendable {
    static let shared = NativeFixture()
    private let lock = NSLock()
    private var connectedValue = true
    private var runningValue = false
    private var count: Int32 = 0
    private var imageValue: Data?
    var connected: Bool { lock.withLock { connectedValue } }
    var running: Bool { lock.withLock { runningValue } }
    var requests: Int32 { lock.withLock { count } }
    var image: Data { lock.withLock { imageValue ?? png } }
    func configure(connected: Bool = true, running: Bool = false, image: Data? = nil) {
        lock.withLock {
            connectedValue = connected
            runningValue = running
            imageValue = image
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
    let data = NativeFixture.shared.image
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
        let payload = JSON(ret: true)
        let result: Bool = try payload["details"]["ret"]
        check(result, "nested callback payload")
        for invalid in [payload["unknown"], JSON(value: ["ret": "true"])] {
            do {
                let _: Bool = try invalid["ret"]
                fatalError("invalid callback lookup accepted")
            } catch is InvalidJSONValue { check(true, "unknown key or wrong type rejects") }
        }
        native.configure(connected: false)
        do {
            _ = try await core.previewImage(requestFresh: true)
            fatalError("disconnected accepted")
        } catch PreviewError.disconnected { check(true, "disconnected rejects") }
        catch { fatalError("wrong disconnected error: \(error)") }
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
        } catch PreviewError.captureInProgress { check(true, "one native request in flight") }
        catch { fatalError("wrong in-flight error: \(error)") }
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
        } catch PreviewError.captureInProgress { check(native.requests == 2, "cancel retains native reservation") }
        catch { fatalError("wrong cancelled reservation error: \(error)") }
        await core.deliver(2, success: true)
        let third = Task { try await core.previewImage(requestFresh: true) }
        while native.requests < 3 { await Task.yield() }
        await core.deliver(3, success: false)
        do {
            _ = try await third.value
            fatalError("failure accepted")
        } catch MaaCoreError.getImageFailed { check(true, "native failure surfaced") }
        catch { fatalError("wrong native failure error: \(error)") }
        let timeout = Task { try await core.previewImage(requestFresh: true) }
        while native.requests < 4 { await Task.yield() }
        do {
            _ = try await timeout.value
            fatalError("timeout accepted")
        } catch PreviewError.timedOut { check(true, "ten-second timeout") }
        catch { fatalError("wrong timeout error: \(error)") }
        check(await core.previewCallID == nil, "timeout releases native reservation without callback")
        let clearedToken = await core.previewToken == nil
        let clearedTimer = await core.previewTimeout == nil
        check(clearedToken && clearedTimer, "timeout clears token and timer")
        let retry = Task { try await core.previewImage(requestFresh: true) }
        while native.requests < 5 { await Task.yield() }
        await core.deliver(4, success: true)
        let retryID = await core.previewCallID
        let retryHasWaiter = await core.previewWaiter != nil
        check(retryID == 5 && retryHasWaiter, "late callback cannot complete retry")
        await core.deliver(5, success: true)
        let retriedFrame = try await retry.value
        check(retriedFrame.1, "preview recovers without old callback or new handle")
        _ = try await core.previewImage(requestFresh: false)
        check(native.requests == 5, "cached read adds no request")
        let newer = Task { try await core.previewImage(requestFresh: true) }
        while native.requests < 6 { await Task.yield() }
        await core.cancelStale(oldToken)
        await core.deliver(6, success: true)
        let recovered = try await newer.value
        check(recovered.1, "stale cancellation token cannot cancel newer capture")
        let cancelled = Task { try await core.previewImage(requestFresh: true) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            fatalError("pre-cancel accepted")
        } catch { check(error is CancellationError, "pre-cancelled task rejected") }
        check(native.requests == 6, "pre-cancelled no native request")
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2048, pixelsHigh: 1536,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        var random: UInt32 = 174
        for i in 0..<(bitmap.bytesPerRow * bitmap.pixelsHigh) {
            random ^= random << 13
            random ^= random >> 17
            random ^= random << 5
            bitmap.bitmapData![i] = UInt8(truncatingIfNeeded: random)
        }
        let largePNG = bitmap.representation(using: .png, properties: [:])!
        check(largePNG.count > 8 * 1024 * 1024, "valid PNG fixture exceeds original capacity")
        native.configure(running: true, image: largePNG)
        let largeFrame = try await core.previewImage(requestFresh: true)
        check(largeFrame.0.width == 2048 && largeFrame.0.height == 1536 && !largeFrame.1,
              "production getImage retries and decodes large PNG")
        print("Passed \(checks) production actor preview assertions")
    }
}

import CoreGraphics
import Foundation
import Testing

@testable import PlayCoverDiagnostics

@Suite struct ScreenCaptureProbeTests {
    @Test func absentSystemCallbackStillTimesOut() async throws {
        let probe = ScreenCaptureProbe()
        let start = ContinuousClock.now
        do {
            _ = try await probe.image(timeout: 0.05) { _ in }
            Issue.record("Unexpected frame")
        } catch MaaToolsError.timedOut {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(start.duration(to: .now) < .seconds(1))
        // Late/duplicate callbacks must not resume a continuation again.
        probe.complete(.failure(CocoaError(.fileNoSuchFile)))
        probe.complete(.failure(CancellationError()))
    }

    @Test func cancellationDoesNotWaitForSystemCallback() async throws {
        let probe = ScreenCaptureProbe()
        let start = ContinuousClock.now
        let task = Task { try await probe.image { _ in } }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Unexpected frame")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(start.duration(to: .now) < .seconds(1))
        probe.complete(.failure(MaaToolsError.timedOut))
    }

    @Test func successfulFrameWinsOverLateFailure() async throws {
        let image = try MaaImageDiagnostics.rgba(Data([1, 2, 3, 255]), size: (1, 1))
        let probe = ScreenCaptureProbe()
        let result = try await probe.image(timeout: 0.1) { probe in
            probe.complete(.success(image))
            probe.complete(.failure(MaaToolsError.timedOut))
        }
        #expect(result.width == 1 && result.height == 1)
    }

    @Test func alreadyCancelledTaskNeverStartsCapture() async throws {
        let probe = ScreenCaptureProbe()
        probe.complete(.failure(CancellationError()))
        do {
            _ = try await probe.image { _ in Issue.record("Cancelled probe started capture") }
            Issue.record("Unexpected frame")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
    }
}

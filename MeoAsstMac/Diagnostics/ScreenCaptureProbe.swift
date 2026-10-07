import CoreGraphics
import CoreMedia
import Foundation
// SDK callback values are used only on the probe's serial queue.
@preconcurrency import ScreenCaptureKit
import VideoToolbox

/// Captures one complete frame using the same window/crop rules as MacSCKHelper.
final class ScreenCaptureProbe: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    // Completion, stream ownership and the deadline share one serial queue.
    // Framework callbacks never hold up the caller's timeout/cancellation.
    private let queue = DispatchQueue(label: "com.hguandl.MeoAsstMac.diagnostics.screen")
    private var completion: CheckedContinuation<CGImage, any Error>?
    private var terminalResult: Result<CGImage, any Error>?
    private var timer: DispatchWorkItem?
    private var captureStream: SCStream?

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        complete(.failure(error))
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // SCStream delivers these callbacks on `queue`.
        guard terminalResult == nil, type == .screen,
            let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            attachments.first?[.status] as? Int == SCFrameStatus.complete.rawValue,
            let pixelBuffer = CMSampleBufferGetImageBuffer(buffer)
        else { return }
        var image: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        guard status == noErr, let image else {
            finish(.failure(MaaImageDiagnostics.Error.corruptedImageData))
            return
        }
        finish(.success(image))
    }

    func complete(_ result: Result<CGImage, any Error>) {
        queue.async { self.finish(result) }
    }

    private func finish(_ result: Result<CGImage, any Error>) {
        guard terminalResult == nil else { return }
        terminalResult = result
        timer?.cancel()
        timer = nil
        if let stream = captureStream {
            captureStream = nil
            try? stream.removeStreamOutput(self, type: .screen)
            stream.stopCapture { _ in }
        }
        completion?.resume(with: result)
        completion = nil
    }

    /// Also used by tests to exercise callbacks that never arrive or arrive late.
    func image(timeout: TimeInterval = 5, start: @escaping @Sendable (ScreenCaptureProbe) -> Void) async throws
        -> CGImage
    {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    if let result = self.terminalResult {
                        continuation.resume(with: result)
                        return
                    }
                    guard self.completion == nil else {
                        continuation.resume(throwing: CocoaError(.featureUnsupported))
                        return
                    }
                    self.completion = continuation
                    let timer = DispatchWorkItem { [weak self] in self?.finish(.failure(MaaToolsError.timedOut)) }
                    self.timer = timer
                    self.queue.asyncAfter(deadline: .now() + timeout, execute: timer)
                    start(self)
                }
            }
        } onCancel: {
            self.complete(.failure(CancellationError()))
        }
    }

    static func matches(bundleID: String?, title: String?, expectedBundleID: String, port: UInt16) -> Bool {
        bundleID == expectedBundleID && title?.contains(String(port)) == true
    }

    static func configuration(
        size: (width: UInt16, height: UInt16),
        rect: (window: MaaToolsClient.Rect, content: MaaToolsClient.Rect)
    ) throws -> SCStreamConfiguration {
        guard size.width > 0, size.height > 0,
            UInt64(size.width) * UInt64(size.height) * 4 <= MaaToolsClient.maximumImageBytes,
            rect.content.size.width > 0, rect.content.size.height > 0
        else {
            throw MaaToolsError.invalidPayload
        }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = false
        let titlebarHeight = Int(rect.window.size.height) - Int(rect.content.size.height)
        if titlebarHeight > 0 {
            configuration.sourceRect = CGRect(
                x: 0, y: titlebarHeight,
                width: Int(rect.content.size.width), height: Int(rect.content.size.height))
        }
        return configuration
    }

    static func capture(
        bundleID: String, port: UInt16, size: (width: UInt16, height: UInt16),
        rect: (window: MaaToolsClient.Rect, content: MaaToolsClient.Rect)
    ) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else { throw CocoaError(.fileReadNoPermission) }
        let probe = ScreenCaptureProbe()
        return try await probe.image { probe in
            SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, error in
                probe.queue.async {
                    guard probe.terminalResult == nil else { return }
                    if let error {
                        probe.finish(.failure(error))
                        return
                    }
                    guard
                        let window = content?.windows.first(where: {
                            matches(
                                bundleID: $0.owningApplication?.bundleIdentifier, title: $0.title,
                                expectedBundleID: bundleID, port: port)
                        })
                    else {
                        probe.finish(.failure(CocoaError(.fileNoSuchFile)))
                        return
                    }
                    do {
                        let configuration = try configuration(size: size, rect: rect)
                        let stream = SCStream(
                            filter: SCContentFilter(desktopIndependentWindow: window),
                            configuration: configuration, delegate: probe)
                        probe.captureStream = stream
                        try stream.addStreamOutput(probe, type: .screen, sampleHandlerQueue: probe.queue)
                        stream.startCapture { error in
                            probe.queue.async {
                                // A late start callback must stop a stream even if
                                // cancellation happened before the stream started.
                                if probe.terminalResult != nil {
                                    try? stream.removeStreamOutput(probe, type: .screen)
                                    stream.stopCapture { _ in }
                                } else if let error {
                                    probe.finish(.failure(error))
                                }
                            }
                        }
                    } catch { probe.finish(.failure(error)) }
                }
            }
        }
    }
}

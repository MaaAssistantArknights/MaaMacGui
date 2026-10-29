import SwiftUI

struct PreviewFrame {
    let image: NSImage
    let readAt: Date
    let requestedCapture: Bool
}

extension Notification.Name {
    static let MAAPreviewFrameDisplayed = Notification.Name("MAAPreviewFrameDisplayed")
}

@MainActor final class PeepViewModel: ObservableObject {
    @Published private(set) var frame: PreviewFrame?
    @Published private(set) var isReading = false
    @Published private(set) var error: String?
    private var generation = UUID()
    private var request: Task<Void, Never>?

    func refresh(from viewModel: MAAViewModel) async {
        guard !isReading else { return }
        let token = generation
        isReading = true
        let request = Task { [weak self] in
            do {
                let frame = try await viewModel.previewFrame()
                try Task.checkCancellation()
                guard let self, self.generation == token else { return }
                self.frame = frame
                self.error = nil
            } catch is CancellationError {
            } catch {
                guard let self, self.generation == token else { return }
                self.error = Self.message(for: error)
            }
        }
        self.request = request
        await withTaskCancellationHandler {
            await request.value
        } onCancel: {
            request.cancel()
        }
        if generation == token {
            isReading = false
            self.request = nil
        }
    }

    func cancel() {
        generation = UUID()
        request?.cancel()
        request = nil
        isReading = false
    }

    private static func message(for error: Error) -> String {
        switch error {
        case PreviewError.disconnected: String(localized: "Peep.Disconnected")
        case PreviewError.captureInProgress: String(localized: "Peep.CaptureInProgress")
        case PreviewError.timedOut: String(localized: "Peep.Timeout")
        default: String(localized: "Peep.NoFrame")
        }
    }
}

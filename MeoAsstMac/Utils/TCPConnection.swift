@preconcurrency import Dispatch
import Foundation
import Network

/// All connection state, timers and continuations are confined to `queue`.
final class TCPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var pending = [UUID: (any Error) -> Void]()
    private var waiting = [UUID: @Sendable () -> Void]()
    private var terminalError: (any Error)?
    private var requestTimer: DispatchWorkItem?
    private let maxRetries: Int
    private var attempts = 0
    private var restartScheduled = false

    init(to endpoint: NWEndpoint, label: String, maxRetries: Int = 0) {
        connection = .init(to: endpoint, using: .tcp)
        queue = .init(label: "com.hguandl.MeoAsstMac.\(label)")
        self.maxRetries = maxRetries
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, terminalError == nil else { return }
            switch state {
            case .ready:
                let operations = Array(waiting.values)
                waiting.removeAll()
                for operation in operations { operation() }
            case .waiting(let error):
                guard attempts < maxRetries else {
                    terminate(with: error)
                    return
                }
                guard !restartScheduled else { return }
                restartScheduled = true
                queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self else { return }
                    restartScheduled = false
                    if terminalError == nil, case .waiting = connection.state {
                        attempts += 1
                        connection.restart()
                    }
                }
            case .failed(let error): terminate(with: error)
            case .cancelled: terminate(with: CancellationError())
            case .setup, .preparing: break
            @unknown default: terminate(with: CocoaError(.featureUnsupported))
            }
        }
        connection.start(queue: queue)
    }

    deinit { connection.cancel() }

    private func terminate(with error: any Error) {
        guard terminalError == nil else { return }
        terminalError = error
        requestTimer?.cancel()
        requestTimer = nil
        connection.cancel()
        let callbacks = Array(pending.values)
        pending.removeAll()
        waiting.removeAll()
        for callback in callbacks { callback(error) }
    }

    func cancel() {
        queue.async { self.terminate(with: CancellationError()) }
    }

    /// Includes send, header and payload in one bounded request deadline.
    func beginRequest(timeout: TimeInterval) {
        queue.async { [self] in
            requestTimer?.cancel()
            let timer = DispatchWorkItem { [weak self] in
                self?.terminate(with: MaaToolsError.timedOut)
            }
            requestTimer = timer
            queue.asyncAfter(deadline: .now() + timeout, execute: timer)
        }
    }

    func endRequest() {
        queue.async { [self] in
            requestTimer?.cancel()
            requestTimer = nil
        }
    }

    private func perform<T: Sendable>(
        timeout: TimeInterval,
        _ body: @escaping @Sendable (NWConnection, @escaping @Sendable (Result<T, any Error>) -> Void) -> Void
    ) async throws -> T {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let id = UUID()
                queue.async { [self] in
                    if let error = self.terminalError {
                        continuation.resume(throwing: error)
                        return
                    }
                    let timer = DispatchWorkItem { [weak self] in
                        guard let self, pending[id] != nil else { return }
                        terminate(with: MaaToolsError.timedOut)
                    }
                    self.pending[id] = { error in
                        timer.cancel()
                        continuation.resume(throwing: error)
                    }
                    let start: @Sendable () -> Void = {
                        body(self.connection) { result in
                            guard self.pending.removeValue(forKey: id) != nil else { return }
                            self.waiting.removeValue(forKey: id)
                            timer.cancel()
                            continuation.resume(with: result)
                        }
                    }
                    self.queue.asyncAfter(deadline: .now() + timeout, execute: timer)
                    if self.connection.state == .ready {
                        start()
                    } else {
                        self.waiting[id] = start
                    }
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func send<D: DataProtocol>(
        _ content: D, endOfStream: Bool = false,
        timeout: TimeInterval = 3
    ) async throws {
        let data = Data(content)
        return try await perform(timeout: timeout) { connection, finish in
            connection.send(
                content: data, contentContext: endOfStream ? .finalMessage : .defaultMessage,
                completion: .contentProcessed { error in
                    if let error { finish(.failure(error)) } else { finish(.success(())) }
                })
        }
    }

    func receive(exactly count: Int, timeout: TimeInterval = 3) async throws -> (
        content: Data, metadata: (endOfStream: Bool, other: [NWProtocolMetadata])
    ) {
        guard count > 0, count <= MaaToolsClient.maximumImageBytes else {
            throw MaaToolsError.invalidPayload
        }
        return try await perform(timeout: timeout) { connection, finish in
            let bytes = ReceiveBuffer()
            @Sendable func receiveNext() {
                let remaining = count - bytes.data.count
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) {
                    content, context, isComplete, error in
                    if let error {
                        finish(.failure(error))
                        return
                    }
                    if let content { bytes.data.append(content) }
                    if bytes.data.count == count {
                        finish(.success((bytes.data, (isComplete, context?.protocolMetadata ?? []))))
                    } else if isComplete || content == nil || content?.isEmpty == true {
                        finish(.failure(MaaToolsError.truncatedResponse))
                    } else {
                        receiveNext()
                    }
                }
            }
            receiveNext()
        }
    }
}

/// Mutated only by receive callbacks on the connection's serial queue.
private final class ReceiveBuffer: @unchecked Sendable {
    var data = Data()
}

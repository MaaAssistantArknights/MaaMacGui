//
//  TCPConnection.swift
//  MAA
//
//  Created by hguandl on 2026/8/28.
//

import Foundation
import Network

final class TCPConnection: @unchecked Sendable {
    private let connection: NWConnection

    private let queue: DispatchQueue

    private var continuations = [CheckedContinuation<Void, any Error>]()
    private var terminalError: (any Error)?

    private let maxRetries: Int
    private var attempts = 0
    private var restartScheduled = false

    init(to endpoint: NWEndpoint, label: String, maxRetries: Int = 0) {
        connection = .init(to: endpoint, using: .tcp)
        queue = .init(label: "com.hguandl.MeoAsstMac.\(label)")
        self.maxRetries = maxRetries
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            guard terminalError == nil else { return }
            switch state {
            case .setup, .preparing:
                break
            case .waiting(let error):
                scheduleRestart(orTerminateWith: error)
            case .ready:
                resume()
            case .failed(let error):
                terminate(with: error)
            case .cancelled:
                terminate(with: CancellationError())
            @unknown default:
                terminate(with: CocoaError(.featureUnsupported))
            }
        }
        connection.start(queue: queue)
    }

    deinit {
        connection.cancel()
    }

    private func resume() {
        attempts = 0
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }

    @discardableResult
    private func terminate(with newError: any Error) -> any Error {
        let error = terminalError ?? newError
        terminalError = error
        connection.cancel()
        continuations.forEach { $0.resume(throwing: error) }
        continuations.removeAll()
        return error
    }

    private func scheduleRestart(orTerminateWith error: any Error) {
        guard terminalError == nil else { return }
        guard !restartScheduled else { return }
        guard attempts < maxRetries else {
            terminate(with: error)
            return
        }
        restartScheduled = true
        queue.asyncAfter(deadline: .now() + 0.5) {
            self.restartScheduled = false
            if self.terminalError == nil, case .waiting = self.connection.state {
                self.attempts += 1
                self.connection.restart()
            }
        }
    }

    private func cancel() {
        queue.async {
            self.terminate(with: CancellationError())
        }
    }

    private func checkReady() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let error = self.terminalError {
                    continuation.resume(throwing: error)
                    return
                }
                switch self.connection.state {
                case .setup, .preparing, .waiting:
                    self.continuations.append(continuation)
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    let error = self.terminate(with: error)
                    continuation.resume(throwing: error)
                case .cancelled:
                    let error = self.terminate(with: CancellationError())
                    continuation.resume(throwing: error)
                @unknown default:
                    let error = self.terminate(with: CocoaError(.featureUnsupported))
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func withConnection<T>(_ body: (CheckedContinuation<T, any Error>) -> Void) async throws -> T {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await checkReady()
            return try await withCheckedThrowingContinuation {
                body($0)
            }
        } onCancel: {
            cancel()
        }
    }

    func send<D: DataProtocol>(_ content: D, endOfStream: Bool = false) async throws {
        return try await withConnection { continuation in
            connection.send(
                content: content,
                contentContext: endOfStream ? .finalMessage : .defaultMessage,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    func receive(exactly: Int) async throws -> (
        content: Data, metadata: (endOfStream: Bool, other: [NWProtocolMetadata])
    ) {
        return try await withConnection { continuation in
            connection.receive(minimumIncompleteLength: exactly, maximumLength: exactly) {
                content, contentContext, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let metadata = (isComplete, contentContext?.protocolMetadata ?? [])
                continuation.resume(returning: (content ?? Data(), metadata))
            }
        }
    }
}

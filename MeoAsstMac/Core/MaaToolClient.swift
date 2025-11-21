//
//  MaaToolClient.swift
//  MAA
//
//  Created by hguandl on 11/12/2023.
//

import Foundation
import Network

actor MaaToolClient {
    private var connection: NWConnection

    init?(address: String) async {
        let parts = address.split(separator: ":")
        guard parts.count >= 2,
            let portNumber = UInt16(parts[1]),
            let port = NWEndpoint.Port(rawValue: portNumber)
        else {
            return nil
        }
        let host = NWEndpoint.Host(String(parts[0]))

        var retryCount = 0
        let maxRetries = 20

        while retryCount < maxRetries {
            connection = NWConnection(host: host, port: port, using: .tcp)

            let states = AsyncStream<NWConnection.State> { continuation in
                connection.stateUpdateHandler = { state in
                        continuation.yield(state)
                }

                continuation.onTermination = { [weak self] reason in
                    guard reason == .cancelled else { return }
                    Task {
                        await self?.cancelActorConnection()
                    }
                }
            }

            connection.start(queue: .global())

            state_enum: for await state in states {
                switch state {
                case .setup, .preparing, .cancelled:
                    break
                case .waiting, .failed:
                    retryCount += 1
                    if retryCount >= maxRetries {
                        connection.cancel()
                        break state_enum
                    }

                    try? await Task.sleep(for: .seconds(0.5))

                    if case .failed = state {
                        // 明确失败，清理旧连接，让外部循环创建新连接
                        connection.cancel()
                        break state_enum
                    } else {
                        // .waiting 状态下，使用 restart()
                        connection.restart()
                    }
                case .ready:
                    return
                @unknown default:
                    fatalError()
                }
            }
        }
        return nil
    }

    // MARK: - Private Methods
    private func cancelActorConnection() {
        connection.cancel()
    }

    // MARK: - Public Methods

    func terminate() async throws {
        guard connection.state == .ready else { return }

        // ['M', 'A', 'A', 0x0, 0x0, 0x4, 'T', 'E', 'R', 'M']
        let data = Data([0x4d, 0x41, 0x41, 0x00, 0x00, 0x04, 0x54, 0x45, 0x52, 0x4d])

        return try await withCheckedThrowingContinuation { continuation in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                })
        }
    }
}

//
//  MaaToolClient.swift
//  MAA
//
//  Created by hguandl on 11/12/2023.
//

import Foundation
import Network
import SwiftUI

actor MaaToolClient {
    private let connection: NWConnection

    init?(address: String, allowscanreporter: Bool, appBundle: URL) async {
        let parts = address.split(separator: ":")
        guard parts.count >= 2,
            let portNumber = UInt16(parts[1]),
            let port = NWEndpoint.Port(rawValue: portNumber)
        else {
            return nil
        }
        let host = NWEndpoint.Host(String(parts[0]))

        connection = NWConnection(host: host, port: port, using: .tcp)

        let states = AsyncStream<NWConnection.State> { continuation in
            connection.stateUpdateHandler = { state in
                if state == .ready {
                    continuation.finish()
                } else {
                    continuation.yield(state)
                }
            }

            continuation.onTermination = { [weak self] reason in
                guard reason == .cancelled else { return }
                self?.connection.cancel()
            }
        }

        connection.start(queue: .global())

        var retryCount = 0
        let maxRetries = 20

        for await state in states {
            switch state {
            case .setup, .preparing, .cancelled:
                break
            case .waiting:
                try? await Task.sleep(for: .seconds(0.5))
                // 开启一个新的异步任务
                Task {
                    if allowscanreporter {
                        let isFound = await ProblemReporterScanner.checkArknights()
                        
                        if isFound {
                            print("成功！在【问题报告程序】中发现了 'Arknights'")
                            try await NSWorkspace.shared.openApplication(at: appBundle, configuration: .init())
                        }
                    } else {
                        await MainActor.run {
                            self.connection.restart()
                        }
                    }
                }
            case .failed:
                retryCount += 1
                if retryCount > maxRetries {
                    connection.cancel()  // 取消连接
                    return nil  // 达到最大重试次数，初始化失败
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
                connection.restart()
            case .ready:
                return
            @unknown default:
                fatalError()
            }
        }
    }

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

//
//  MaaToolsClient.swift
//  MAA
//
//  Created by hguandl on 2026/8/28.
//

import Foundation
import Network

struct MaaToolsClient: ~Copyable {
    private let connection: TCPConnection
    private let handshake: Handshake

    init?<S: StringProtocol>(to hostPort: S, maxRetries: Int = 0) {
        guard let url = URL(string: "tcp://\(hostPort)") else {
            return nil
        }
        connection = .init(to: .url(url), label: "MaaToolsClient", maxRetries: maxRetries)
        handshake = .init(connection: connection)
    }

    mutating func rgbaScreenshot() async throws -> Data {
        try await handshake.check(minimumVersion: 2)
        try await connection.send([0x00, 0x04] + "SCRN".utf8)
        let (header, _) = try await connection.receive(exactly: 4)
        var reader = ByteReader(header)
        let length = try reader.read(UInt32.self)
        let (data, _) = try await connection.receive(exactly: Int(length))
        return data
    }

    mutating func resolution() async throws -> (width: UInt16, height: UInt16) {
        try await handshake.check(minimumVersion: 2)
        try await connection.send([0x00, 0x04] + "SIZE".utf8)
        let (content, _) = try await connection.receive(exactly: 4)
        var reader = ByteReader(content)
        return try (reader.read(), reader.read())
    }

    consuming func terminate() async throws {
        try await handshake.check(minimumVersion: 2)
        try await connection.send([0x00, 0x04] + "TERM".utf8)
    }

    func version() async throws -> UInt32 {
        try await handshake.version()
    }

    static func runningBundle(at address: String) async throws -> String? {
        guard var client = Self(to: address) else { throw MaaToolsError.handshakeFailed }
        do {
            return try await client.bundleName()
        } catch NWError.posix(.ECONNREFUSED), NWError.posix(.ECONNRESET), NWError.posix(.ENOTCONN) {
            return nil
        }
    }

    mutating func bundleName() async throws -> String {
        let socket = connection
        let timeout = Task { try await Task.sleep(for: .seconds(3)); socket.cancel() }
        defer { timeout.cancel() }
        try await handshake.check(minimumVersion: 3)
        try await connection.send([0x00, 0x04] + "BNDL".utf8)
        let (header, _) = try await connection.receive(exactly: 4)
        var reader = ByteReader(header)
        let length = try reader.read(UInt32.self)
        guard (1...8192).contains(length) else { throw MaaToolsError.handshakeFailed }
        let (data, _) = try await connection.receive(exactly: Int(length))
        guard data.count == Int(length) else { throw MaaToolsError.handshakeFailed }
        return String(decoding: data, as: UTF8.self)
    }

    typealias Rect = (origin: (x: Int16, y: Int16), size: (width: Int16, height: Int16))

    private func makePair<T>(_ builder: () throws -> T) rethrows -> (T, T) {
        try (builder(), builder())
    }

    mutating func bounds() async throws -> (window: Rect, content: Rect) {
        try await handshake.check(minimumVersion: 3)
        try await connection.send([0x00, 0x04] + "RECT".utf8)
        let (content, _) = try await connection.receive(exactly: 16)
        var reader = ByteReader(content)
        let result = try makePair {
            try makePair {
                try makePair {
                    try reader.read(Int16.self)
                }
            }
        }
        return result
    }

    mutating func bgrScreenshot() async throws -> ((width: UInt32, height: UInt32), Data) {
        try await handshake.check(minimumVersion: 3)
        try await connection.send([0x00, 0x04] + "BGR".utf8 + [0x01])
        let (header, _) = try await connection.receive(exactly: 12)
        var reader = ByteReader(header)
        let width = try reader.read(UInt32.self)
        let height = try reader.read(UInt32.self)
        let length = try reader.read(UInt32.self)
        let (data, _) = try await connection.receive(exactly: Int(length))
        return ((width, height), data)
    }
}

enum MaaToolsError: Error {
    case handshakeFailed
    case unsupportedVersion
}

private actor Handshake {
    private let connection: TCPConnection

    init(connection: TCPConnection) {
        self.connection = connection
    }

    private var task: Task<UInt32, any Swift.Error>?

    func version() async throws -> UInt32 {
        if let task {
            return try await task.value
        }
        let task = Task {
            try await connection.send("MAA".utf8 + [0x00])
            let (content, metadata) = try await connection.receive(exactly: 4)
            if content.isEmpty && metadata.endOfStream {
                throw NWError.posix(.ENOTCONN)
            }
            if content == Data("OKAY".utf8) {
                try await connection.send([0x00, 0x04] + "VERN".utf8)
                let (content, _) = try await connection.receive(exactly: 4)
                var reader = ByteReader(content)
                return try reader.read(UInt32.self)
            } else {
                throw MaaToolsError.handshakeFailed
            }
        }
        self.task = task
        return try await task.value
    }

    func check(minimumVersion: UInt32) async throws {
        let version = try await version()
        guard version >= minimumVersion else {
            throw MaaToolsError.unsupportedVersion
        }
    }
}

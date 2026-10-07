//
//  MaaToolsClient.swift
//  MAA
//
//  Created by hguandl on 2026/8/28.
//

import Darwin
import Foundation
import Network

struct MaaToolsClient: ~Copyable {
    static let maximumImageBytes = 128 * 1024 * 1024
    private let connection: TCPConnection
    private let handshake: Handshake

    init?<S: StringProtocol>(to hostPort: S, maxRetries: Int = 0) {
        guard let endpoint = MaaToolsEndpoint(String(hostPort)) else {
            return nil
        }
        connection = .init(to: endpoint.networkEndpoint, label: "MaaToolsClient", maxRetries: maxRetries)
        handshake = .init(connection: connection)
    }

    func cancel() { connection.cancel() }

    mutating func rgbaScreenshot() async throws -> Data {
        try await handshake.check(minimumVersion: 2)
        connection.beginRequest(timeout: 5)
        defer { connection.endRequest() }
        try await connection.send([0x00, 0x04] + "SCRN".utf8, timeout: 5)
        let (header, _) = try await connection.receive(exactly: 4, timeout: 5)
        var reader = ByteReader(header)
        let length = try reader.read(UInt32.self)
        guard length > 0 else { throw MaaToolsError.invalidPayload }
        guard length <= Self.maximumImageBytes else { throw MaaToolsError.payloadTooLarge }
        let (data, _) = try await connection.receive(exactly: Int(length), timeout: 5)
        return data
    }

    mutating func resolution() async throws -> (width: UInt16, height: UInt16) {
        try await handshake.check(minimumVersion: 2)
        connection.beginRequest(timeout: 3)
        defer { connection.endRequest() }
        try await connection.send([0x00, 0x04] + "SIZE".utf8)
        let (content, _) = try await connection.receive(exactly: 4)
        var reader = ByteReader(content)
        return try (reader.read(), reader.read())
    }

    consuming func terminate() async throws {
        try await handshake.check(minimumVersion: 2)
        connection.beginRequest(timeout: 3)
        defer { connection.endRequest() }
        try await connection.send([0x00, 0x04] + "TERM".utf8)
    }

    func version(timeout: TimeInterval = 3) async throws -> UInt32 {
        try await handshake.version(timeout: timeout)
    }

    mutating func bundleName() async throws -> String {
        try await handshake.check(minimumVersion: 3)
        connection.beginRequest(timeout: 3)
        defer { connection.endRequest() }
        try await connection.send([0x00, 0x04] + "BNDL".utf8)
        let (header, _) = try await connection.receive(exactly: 4)
        var reader = ByteReader(header)
        let length = try reader.read(UInt32.self)
        guard length > 0, length <= 4096 else { throw MaaToolsError.invalidPayload }
        let (data, _) = try await connection.receive(exactly: Int(length))
        guard let name = String(data: data, encoding: .utf8) else { throw MaaToolsError.invalidPayload }
        return name
    }

    typealias Rect = (origin: (x: Int16, y: Int16), size: (width: Int16, height: Int16))

    private func makePair<T>(_ builder: () throws -> T) rethrows -> (T, T) {
        try (builder(), builder())
    }

    mutating func bounds() async throws -> (window: Rect, content: Rect) {
        try await handshake.check(minimumVersion: 3)
        connection.beginRequest(timeout: 3)
        defer { connection.endRequest() }
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
        connection.beginRequest(timeout: 5)
        defer { connection.endRequest() }
        try await connection.send([0x00, 0x04] + "BGR".utf8 + [0x01], timeout: 5)
        let (header, _) = try await connection.receive(exactly: 12, timeout: 5)
        var reader = ByteReader(header)
        let width = try reader.read(UInt32.self)
        let height = try reader.read(UInt32.self)
        let length = try reader.read(UInt32.self)
        let pixels = UInt64(width) * UInt64(height)
        guard width > 0, height > 0, pixels <= UInt64(UInt32.max) / 3,
            pixels * 3 == UInt64(length)
        else { throw MaaToolsError.invalidPayload }
        guard pixels <= UInt64(Self.maximumImageBytes) / 4 else { throw MaaToolsError.payloadTooLarge }
        let (data, _) = try await connection.receive(exactly: Int(length), timeout: 5)
        return ((width, height), data)
    }
}

enum MaaToolsError: Error, LocalizedError {
    case handshakeFailed
    case unsupportedVersion
    case invalidPayload
    case payloadTooLarge
    case truncatedResponse
    case timedOut

    var errorDescription: String? {
        switch self {
        case .handshakeFailed: String(localized: "服务响应不是 MaaTools 握手，请检查连接地址。")
        case .unsupportedVersion: String(localized: "MaaTools 协议版本不支持当前操作，请更新指定的 PlayCover fork。")
        case .invalidPayload: String(localized: "MaaTools 返回的数据长度或格式无效。")
        case .payloadTooLarge: String(localized: "截图超出 128 MiB 检测内存上限，无法验证画面。")
        case .truncatedResponse: String(localized: "MaaTools 响应未接收完整，连接已关闭。")
        case .timedOut: String(localized: "MaaTools 请求超时，请检查游戏和连接地址。")
        }
    }
}

private actor Handshake {
    private let connection: TCPConnection

    init(connection: TCPConnection) {
        self.connection = connection
    }

    private var task: Task<UInt32, any Swift.Error>?

    func version(timeout: TimeInterval = 3) async throws -> UInt32 {
        try Task.checkCancellation()
        if let task {
            return try await value(of: task)
        }
        let task = Task {
            connection.beginRequest(timeout: timeout)
            defer { connection.endRequest() }
            try await connection.send("MAA".utf8 + [0x00])
            let (content, _) = try await connection.receive(exactly: 4)
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
        return try await value(of: task)
    }

    private func value(of task: Task<UInt32, any Swift.Error>) async throws -> UInt32 {
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await task.value
        } onCancel: {
            task.cancel()
            self.connection.cancel()
        }
    }

    func check(minimumVersion: UInt32) async throws {
        let version = try await version()
        guard version >= minimumVersion else {
            throw MaaToolsError.unsupportedVersion
        }
    }
}

struct MaaToolsEndpoint: Equatable, Sendable {
    let host: String
    let port: UInt16

    init?(_ address: String) {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URLComponents(string: "tcp://\(address)"), url.scheme == "tcp",
            url.user == nil, url.password == nil, url.path.isEmpty,
            url.query == nil, url.fragment == nil,
            let host = url.host, !host.isEmpty,
            let number = url.port, let port = UInt16(exactly: number), port > 0
        else { return nil }
        self.host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        self.port = port
    }

    var isLoopback: Bool {
        if host == "localhost" { return true }
        var ipv4 = in_addr()
        if host.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            return UInt32(bigEndian: ipv4.s_addr) >> 24 == 127
        }
        var ipv6 = in6_addr()
        guard host.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 else { return false }
        return withUnsafeBytes(of: ipv6) { bytes in
            bytes.prefix(15).allSatisfy { $0 == 0 } && bytes[15] == 1
        }
    }
    var address: String { "\(host.contains(":") ? "[\(host)]" : host):\(port)" }
    var networkEndpoint: NWEndpoint { .hostPort(host: .init(host), port: .init(rawValue: port)!) }
    func matchesLocalPort(_ port: Int) -> Bool { isLoopback && Int(self.port) == port }
}

//
//  SMTPClient.swift
//  MAA
//
//  Created by MAA on 2026/9/30.
//

import Darwin
import Foundation
import OSLog
import Security

/// 最小可用 SMTP 客户端，供「SMTP」外部通知渠道发送邮件。
///
/// 行为对齐 WPF 侧 MailKit 的 `ConnectAsync(host, port, useSsl)`：
/// `useSSL` 为真时建立隐式 TLS 连接（端口 465 的典型场景），否则先明文连接，
/// 服务器公告 `STARTTLS` 能力时自动升级为 TLS（`StartTlsWhenAvailable` 语义）。
/// 支持无认证、`AUTH PLAIN` 与 `AUTH LOGIN`。
enum SMTPClient {
    private static let logger = Logger(subsystem: "com.hguandl.MeoAsstMac", category: "SMTPClient")

    /// 连接 / 应答超时（秒）。
    private static let timeout: Int = 15

    struct Request: Sendable {
        let host: String
        let port: UInt16
        let useSSL: Bool
        let requiresAuthentication: Bool
        let user: String
        let password: String
        let from: String
        let to: String
        let subject: String
        let htmlBody: String
    }

    /// 在后台线程发送邮件；返回发送是否成功。低频调用（任务完成 / 出错各一次），
    /// 阻塞式 socket 的短暂占线可以接受。
    static func send(_ request: Request) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                do {
                    try sendSync(request)
                    continuation.resume(returning: true)
                } catch {
                    // SMTP 错误详情可能包含服务器回显，仅记录类型，避免泄露内容。
                    logger.error("Failed to send Email notification: \(String(describing: type(of: error)))")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private static func sendSync(_ request: Request) throws {
        let connection = try connect(host: request.host, port: request.port, useSSL: request.useSSL)
        var finished = false
        defer {
            if !finished {
                connection.close()
            }
        }

        try expect(connection, acceptedCode: 220) // 服务器问候

        try sendCommand(connection, "EHLO \(ProcessInfo.processInfo.hostName)")
        let capabilities = try readMultilineResponse(connection)

        if !request.useSSL {
            // StartTlsWhenAvailable：服务器支持才升级，不支持则继续明文。
            if capabilities.uppercased().contains("STARTTLS") {
                try sendCommand(connection, "STARTTLS")
                try expect(connection, acceptedCode: 220)
                try connection.startTLSAndHandshake(host: request.host)
                try sendCommand(connection, "EHLO \(ProcessInfo.processInfo.hostName)")
                _ = try readMultilineResponse(connection)
            }
        }

        if request.requiresAuthentication {
            try authenticate(connection, user: request.user, password: request.password)
        }

        try sendCommand(connection, "MAIL FROM:<\(request.from)>")
        try expect(connection, acceptedCode: 250)

        try sendCommand(connection, "RCPT TO:<\(request.to)>")
        try expect(connection, acceptedCode: 250)

        try sendCommand(connection, "DATA")
        try expect(connection, acceptedCode: 354)

        try sendMailData(connection, request: request)
        try expect(connection, acceptedCode: 250)

        try sendCommand(connection, "QUIT")
        try expect(connection, acceptedCode: 221)
        finished = true
        connection.close()
    }

    // MARK: - Session Stages

    private static func authenticate(_ connection: Connection, user: String, password: String) throws {
        // 优先 AUTH PLAIN；被拒时退回 AUTH LOGIN。
        try sendCommand(connection, "AUTH PLAIN \(Data("\u{0}\(user)\u{0}\(password)".utf8).base64EncodedString())")
        do {
            try expect(connection, acceptedCode: 235)
            return
        } catch SMTPError.rejectedResponse {
            logger.info("AUTH PLAIN rejected, falling back to AUTH LOGIN")
        }

        try sendCommand(connection, "AUTH LOGIN")
        try expect(connection, acceptedCode: 334)
        try sendCommand(connection, Data(user.utf8).base64EncodedString())
        try expect(connection, acceptedCode: 334)
        try sendCommand(connection, Data(password.utf8).base64EncodedString())
        try expect(connection, acceptedCode: 235)
    }

    /// 发送邮件正文（DATA 阶段）。Subject 与 HTML 正文均为 UTF-8，
    /// 按 RFC 2047 / MIME 以 Base64 encoded-word 与 Base64 正文传输。
    private static func sendMailData(_ connection: Connection, request: Request) throws {
        let subjectEncoded = Data(request.subject.utf8).base64EncodedString()
        let bodyEncoded = Data(request.htmlBody.utf8).base64EncodedString()
            .separated(every: 76, with: "\r\n")

        var mail = ""
        mail += "From: <\(request.from)>\r\n"
        mail += "To: <\(request.to)>\r\n"
        mail += "Subject: =?utf-8?B?\(subjectEncoded)?=\r\n"
        mail += "Date: \(rfc5322Date())\r\n"
        mail += "MIME-Version: 1.0\r\n"
        mail += "Content-Type: text/html; charset=utf-8\r\n"
        mail += "Content-Transfer-Encoding: base64\r\n"
        mail += "\r\n"
        mail += bodyEncoded

        // Dot-stuffing：内容行首为「.」时按 RFC 5321 加倍，防止提前结束 DATA。
        // 必须在追加终止符之前进行——若终止符「.」也参与 stuffing 会被改写成「..」，
        // 服务器将永远等不到 DATA 结束。
        mail = mail
            .split(separator: "\r\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix(".") ? "." + $0 : String($0) }
            .joined(separator: "\r\n")

        // 终止符独立成行并自行结束该行（<CRLF>.<CRLF>），随后才能发送下一命令。
        mail += "\r\n.\r\n"

        try connection.write(Data(mail.utf8))
    }

    private static func rfc5322Date() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
        return formatter.string(from: Date())
    }

    // MARK: - Command / Response

    private static func sendCommand(_ connection: Connection, _ command: String) throws {
        try connection.write(Data((command + "\r\n").utf8))
    }

    /// 校验（可能多行的）应答最后一行的状态码。
    private static func expect(_ connection: Connection, acceptedCode: Int) throws {
        let response = try readMultilineResponse(connection)
        let lastLine = response.split(separator: "\n").last ?? ""
        let code = "\(acceptedCode)"
        guard lastLine.hasPrefix(code) else {
            throw SMTPError.rejectedResponse
        }
        // 状态码后必须是行尾或空格（如 "250"、"250 OK"），排除 "2500" 之类的误匹配。
        let rest = lastLine.dropFirst(code.count)
        guard rest.isEmpty || rest.first == " " else {
            throw SMTPError.rejectedResponse
        }
    }

    /// 读取一条（可能多行的）SMTP 应答，各行以 \n 拼接返回。
    private static func readMultilineResponse(_ connection: Connection) throws -> String {
        var lines = [String]()
        while true {
            let line = try connection.readLine()
            lines.append(line)
            guard line.count >= 4, line[line.index(line.startIndex, offsetBy: 3)] == "-" else { break }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Connection Establishment

    private static func connect(host: String, port: UInt16, useSSL: Bool) throws -> Connection {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "\(port)", &hints, &info) == 0, let first = info else {
            throw SMTPError.hostLookupFailed
        }
        defer { freeaddrinfo(info) }

        for candidate in sequence(first: first, next: { $0.pointee.ai_next }) {
            let fd = socket(
                candidate.pointee.ai_family,
                candidate.pointee.ai_socktype,
                candidate.pointee.ai_protocol)
            guard fd >= 0 else { continue }

            do {
                try establishSocket(fd, candidate)
                let connection = Connection(fd: fd)
                if useSSL {
                    try connection.startTLSAndHandshake(host: host)
                }
                return connection
            } catch {
                Darwin.close(fd)
            }
        }
        throw SMTPError.connectionFailed
    }

    private static func establishSocket(_ fd: Int32, _ info: UnsafeMutablePointer<addrinfo>) throws {
        // 非阻塞 connect + poll 限时，避免无效地址时阻塞默认的 ~75 秒。
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let connectResult = Darwin.connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
        if connectResult != 0 {
            guard errno == EINPROGRESS else { throw SMTPError.connectionFailed }
            var pollFD = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            guard poll(&pollFD, 1, Int32(timeout * 1000)) > 0 else {
                throw SMTPError.connectionFailed
            }
            var soError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &length)
            guard soError == 0 else { throw SMTPError.connectionFailed }
        }

        _ = fcntl(fd, F_SETFL, flags) // 恢复阻塞模式

        var tv = timeval(tv_sec: timeout, tv_usec: 0)
        guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size)) == 0,
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size)) == 0
        else {
            throw SMTPError.socketSetupFailed
        }
    }
}

enum SMTPError: Error {
    case hostLookupFailed
    case connectionFailed
    case socketSetupFailed
    case rejectedResponse
    case tlsHandshakeFailed
    case connectionClosed
}

// MARK: - Connection

/// 明文或 TLS 化的 TCP 连接，提供按行读取与整包写入。
final class Connection {
    private let fd: Int32
    private var sslContext: SSLContext?
    private var buffer = Data()

    init(fd: Int32) {
        self.fd = fd
    }

    /// 将现有明文连接就地升级为 TLS 并完成握手。
    /// - Parameter host: 预期的 SMTP 主机名，用于证书 SAN/CN 匹配；
    ///   缺省时受信任 CA 签发的任意域名证书都会通过校验（主机名不匹配 MITM）。
    func startTLSAndHandshake(host: String) throws {
        guard let context = SSLCreateContext(nil, .clientSide, .streamType) else {
            throw SMTPError.tlsHandshakeFailed
        }

        // 以值方式把 fd 传给 TLS 回调（SSLConnectionRef），避免悬垂指针。
        let fdObject = NSNumber(value: fd)
        let connectionRef = Unmanaged.passRetained(fdObject).toOpaque()
        SSLSetConnection(context, connectionRef)
        SSLSetIOFuncs(
            context,
            { connectionRef, data, dataLength in
                Connection.sslRead(connectionRef: connectionRef, buffer: data, requested: dataLength)
            },
            { connectionRef, data, dataLength in
                Connection.sslWrite(connectionRef: connectionRef, buffer: data, total: dataLength)
            })

        // 设置预期主机名：SSLCopyPeerTrust 产出的 trust 将据此执行 SAN/CN 匹配。
        let setStatus = SSLSetPeerDomainName(context, host, host.utf8.count)
        guard setStatus == noErr else {
            throw SMTPError.tlsHandshakeFailed
        }

        // 启用系统信任链校验：握手在服务器证书验证完成处中断，交由 SecTrust 复核。
        SSLSetSessionOption(context, .breakOnServerAuth, true)
        sslContext = context

        while true {
            let status = SSLHandshake(context)
            switch status {
            case Self.errSSLServerAuthCompleted:
                try verifyServerCertificate(context)
            case noErr:
                Unmanaged.passUnretained(fdObject).release()
                return
            default:
                Unmanaged.passUnretained(fdObject).release()
                throw SMTPError.tlsHandshakeFailed
            }
        }
    }

    /// 握手中断点：服务器证书已接收、等待应用层校验。
    /// 即 SecureTransport 的 `errSSLServerAuthComleted`（Apple 头文件拼写如此，Swift 未导出符号）。
    private static let errSSLServerAuthCompleted: OSStatus = -9481

    private func verifyServerCertificate(_ context: SSLContext) throws {
        var trust: SecTrust?
        guard SSLCopyPeerTrust(context, &trust) == noErr, let trust else {
            throw SMTPError.tlsHandshakeFailed
        }
        do {
            try SecTrustEvaluateWithError(trust, nil)
        } catch {
            throw SMTPError.tlsHandshakeFailed
        }
    }

    func close() {
        if let context = sslContext {
            SSLClose(context)
        }
        Darwin.close(fd)
    }

    // MARK: IO

    func write(_ data: Data) throws {
        var remaining = data
        while !remaining.isEmpty {
            let sent = remaining.withUnsafeBytes { pointer -> Int in
                send(fd, pointer.baseAddress, pointer.count, 0)
            }
            if sent > 0 {
                remaining.removeFirst(sent)
            } else if sent < 0 && errno == EINTR {
                continue
            } else {
                throw SMTPError.connectionClosed
            }
        }
    }

    /// 读取一行（以 CRLF 结尾），返回不含 CRLF 的内容。
    func readLine() throws -> String {
        while true {
            if let range = buffer.range(of: Data("\r\n".utf8)) {
                let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(..<range.upperBound)
                guard let text = String(data: line, encoding: .utf8) else {
                    throw SMTPError.connectionClosed
                }
                return text
            }

            var chunk = Data(repeating: 0, count: 4096)
            let received = chunk.withUnsafeMutableBytes { pointer -> Int in
                recv(fd, pointer.baseAddress, pointer.count, 0)
            }
            if received > 0 {
                buffer.append(chunk.prefix(received))
            } else if received < 0 && errno == EINTR {
                continue
            } else {
                throw SMTPError.connectionClosed
            }
        }
    }

    // MARK: SSL IO Callbacks

    private static func sslRead(connectionRef: SSLConnectionRef?, buffer: UnsafeMutableRawPointer?, requested: UnsafeMutablePointer<Int>) -> OSStatus {
        guard let connectionRef, let buffer, requested.pointee > 0 else {
            return errSSLInternal
        }
        let fd = Unmanaged<NSNumber>.fromOpaque(connectionRef).takeUnretainedValue().int32Value
        while true {
            let received = recv(fd, buffer, requested.pointee, 0)
            if received > 0 {
                requested.pointee = received
                return noErr
            }
            if received == 0 { return errSSLClosedGraceful }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { return errSSLWouldBlock }
            return errSSLClosedAbort
        }
    }

    private static func sslWrite(connectionRef: SSLConnectionRef?, buffer: UnsafeRawPointer?, total: UnsafeMutablePointer<Int>) -> OSStatus {
        guard let connectionRef, let buffer else {
            return errSSLInternal
        }
        let fd = Unmanaged<NSNumber>.fromOpaque(connectionRef).takeUnretainedValue().int32Value
        var offset = 0
        while offset < total.pointee {
            let sent = send(fd, buffer.advanced(by: offset), total.pointee - offset, 0)
            if sent > 0 {
                offset += sent
            } else if sent < 0 && errno == EINTR {
                continue
            } else {
                return errSSLClosedAbort
            }
        }
        return noErr
    }
}

private extension String {
    /// 按每隔若干字符插入分隔符（Base64 折行）。
    func separated(every: Int, with separator: String) -> String {
        guard every > 0 else { return self }
        return stride(from: 0, to: count, by: every)
            .map { offset in
                let start = index(startIndex, offsetBy: offset)
                let end = index(start, offsetBy: min(every, distance(from: start, to: endIndex)), limitedBy: endIndex) ?? endIndex
                return self[start..<end]
            }
            .joined(separator: separator)
    }
}

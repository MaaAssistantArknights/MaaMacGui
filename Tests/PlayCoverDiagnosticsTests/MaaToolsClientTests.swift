import Foundation
import Network
import Testing

@testable import PlayCoverDiagnostics

@Suite struct MaaToolsClientTests {
    @Test func testProtocolVersionsAndFragmentedIdentityResponse() async throws {
        for version: UInt32 in [2, 3, 4] {
            let server = try MockMaaToolsServer(version: version, fragmented: true)
            let address = try await server.start()
            defer { server.stop() }
            var client = try makeClient(address)
            defer { client.cancel() }
            let actual = try await client.version()
            #expect(actual == version)
            let size = try await client.resolution()
            #expect(size.width == 1280)
            #expect(size.height == 720)
            if version >= 3 {
                let identity = try await client.bundleName()
                #expect(identity == "com.hypergryph.arknights")
                let rect = try await client.bounds()
                #expect(rect.content.size.height == 720)
            } else {
                do {
                    _ = try await client.bundleName()
                    Issue.record("Version 2 has no BNDL")
                } catch {}
            }
        }
    }

    @Test func testGuideAndRuntimeShareResolutionVerdict() async throws {
        let server = try MockMaaToolsServer()
        let address = try await server.start()
        defer { server.stop() }
        let guide = try await MaaImageDiagnostics.captureBGR(address: address)
        #expect(guide.diagnosis == .passed)
        let runtime = try await PlayCoverRuntimeChecks.inspect(address: address, mode: "BGR", bundleID: server.bundleID)
        #expect(runtime.first { $0.id == "runtime-capture" }?.status == .passed)
        #expect(server.commands.allSatisfy { ["VERN", "SIZE", "BNDL", "RECT", "BGR\u{1}"].contains($0) })
    }

    @Test func testRGBAProtocolTwoIsCompatibleButIdentityIsUnknown() async throws {
        let server = try MockMaaToolsServer(version: 2)
        let address = try await server.start()
        defer { server.stop() }
        let rows = try await PlayCoverRuntimeChecks.inspect(address: address, mode: "RGBA", bundleID: server.bundleID)
        #expect(rows.first { $0.id == "runtime-identity" }?.status == .unavailable)
        #expect(rows.first { $0.id == "runtime-capture" }?.status == .passed)
        let bgrRows = try await PlayCoverRuntimeChecks.inspect(address: address, mode: "BGR", bundleID: server.bundleID)
        #expect(bgrRows.first { $0.id == "runtime-version" }?.status == .error)
    }

    @Test func testWrongGameStopsBeforeScreenshot() async throws {
        let server = try MockMaaToolsServer()
        let address = try await server.start()
        defer { server.stop() }
        let rows = try await PlayCoverRuntimeChecks.inspect(address: address, mode: "BGR", bundleID: "other.game")
        #expect(rows.first { $0.id == "runtime-identity" }?.status == .error)
        #expect(!(server.commands.contains("BGR\u{1}")))
    }

    @Test func testWrongHandshakeAndTruncatedResponse() async throws {
        for behavior in [MockMaaToolsServer.Behavior.wrongHandshake, .truncated] {
            let server = try MockMaaToolsServer(behavior: behavior)
            let address = try await server.start()
            defer { server.stop() }
            let client = try makeClient(address)
            defer { client.cancel() }
            do {
                _ = try await client.version()
                Issue.record("Must reject invalid response")
            } catch {}
        }
    }

    @Test func testOversizedIdentityAndCorruptedImageAreRejectedBeforeAllocation() async throws {
        for behavior in [MockMaaToolsServer.Behavior.hugeBundle, .badImage] {
            let server = try MockMaaToolsServer(behavior: behavior)
            let address = try await server.start()
            defer { server.stop() }
            var client = try makeClient(address)
            defer { client.cancel() }
            do {
                if behavior == .hugeBundle {
                    _ = try await client.bundleName()
                } else {
                    _ = try await client.bgrScreenshot()
                }
                Issue.record("Must reject invalid length")
            } catch MaaToolsError.invalidPayload {} catch { Issue.record("Unexpected error: \(error)") }
        }
    }

    @Test func testCancellationInterruptsPendingHandshake() async throws {
        let server = try MockMaaToolsServer(behavior: .silent)
        let address = try await server.start()
        defer { server.stop() }
        let start = ContinuousClock.now
        let task = Task {
            let client = try makeClient(address)
            defer { client.cancel() }
            return try await client.version()
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Unexpected success")
        } catch is CancellationError {} catch { Issue.record("\(error)") }
        #expect(start.duration(to: .now) < .seconds(1))
    }

    @Test func testSilentServiceTimesOut() async throws {
        let server = try MockMaaToolsServer(behavior: .silent)
        let address = try await server.start()
        defer { server.stop() }
        let client = try makeClient(address)
        defer { client.cancel() }
        let start = ContinuousClock.now
        do {
            _ = try await client.version()
            Issue.record("Unexpected success")
        } catch MaaToolsError.timedOut {} catch { Issue.record("\(error)") }
        #expect(start.duration(to: .now) < .seconds(4))
    }

    @Test func screenshotHeaderUsesFiveSecondDeadline() async throws {
        let server = try MockMaaToolsServer(behavior: .delayedImageHeader)
        let address = try await server.start()
        defer { server.stop() }
        var client = try makeClient(address)
        defer { client.cancel() }
        let image = try await client.bgrScreenshot()
        #expect(image.1.count == 1280 * 720 * 3)
    }

    @Test func cancellationInterruptsScreenshotPayload() async throws {
        let server = try MockMaaToolsServer(behavior: .stalledImage)
        let address = try await server.start()
        defer { server.stop() }
        let task = Task {
            var client = try makeClient(address)
            defer { client.cancel() }
            return try await client.bgrScreenshot()
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !server.commands.contains("BGR\u{1}"), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(server.commands.contains("BGR\u{1}"))
        let start = ContinuousClock.now
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Unexpected image")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(start.duration(to: .now) < .seconds(1))
    }

    @Test func totalRequestDeadlineAlsoBoundsPendingReceive() async throws {
        let server = try MockMaaToolsServer(behavior: .silent)
        let address = try await server.start()
        defer { server.stop() }
        let connection = TCPConnection(to: MaaToolsEndpoint(address)!.networkEndpoint, label: "request-deadline")
        defer { connection.cancel() }
        let start = ContinuousClock.now
        connection.beginRequest(timeout: 0.1)
        defer { connection.endRequest() }
        do {
            _ = try await connection.receive(exactly: 4)
            Issue.record("Unexpected response")
        } catch MaaToolsError.timedOut {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(start.duration(to: .now) < .seconds(1))
    }

    @Test func cancelBeforeReadyRejectsAllLaterOperations() async throws {
        let server = try MockMaaToolsServer(behavior: .silent)
        let address = try await server.start()
        defer { server.stop() }
        let connection = TCPConnection(to: MaaToolsEndpoint(address)!.networkEndpoint, label: "cancelled")
        connection.cancel()
        do {
            try await connection.send(Data([1]))
            Issue.record("Unexpected send")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        do {
            _ = try await connection.receive(exactly: 1)
            Issue.record("Unexpected receive")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func testShortTransportDeadline() async throws {
        let server = try MockMaaToolsServer(behavior: .silent)
        let address = try await server.start()
        defer { server.stop() }
        let connection = TCPConnection(to: MaaToolsEndpoint(address)!.networkEndpoint, label: "test")
        defer { connection.cancel() }
        do {
            _ = try await connection.receive(exactly: 4, timeout: 0.1)
            Issue.record("Unexpected success")
        } catch MaaToolsError.timedOut {} catch { Issue.record("\(error)") }
    }
}

private func makeClient(_ address: String) throws -> MaaToolsClient {
    guard let client = MaaToolsClient(to: address) else { throw MaaToolsError.invalidPayload }
    return client
}

final class MockMaaToolsServer: @unchecked Sendable {
    enum Behavior {
        case normal, silent, wrongHandshake, truncated, hugeBundle, badImage, badSize, badBounds, truncatedBounds,
            stalledImage, delayedImageHeader, oversizedSize
    }
    let bundleID = "com.hypergryph.arknights"
    private let listener: NWListener
    private let queue = DispatchQueue(label: "plus.maa.test-server")
    private var connections = [NWConnection]()
    private var recordedCommands = [String]()
    var commands: [String] { queue.sync { recordedCommands } }
    private let version: UInt32
    private let behavior: Behavior
    private let fragmented: Bool

    init(version: UInt32 = 3, behavior: Behavior = .normal, fragmented: Bool = false) throws {
        listener = try NWListener(using: .tcp, on: .any)
        self.version = version
        self.behavior = behavior
        self.fragmented = fragmented
    }

    func start() async throws -> String {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connections.append(connection)
            connection.start(queue: queue)
            read(4, from: connection) { [weak self] bytes in
                guard let self, bytes == Data([77, 65, 65, 0]) else {
                    connection.cancel()
                    return
                }
                if behavior == .silent { return }
                if behavior == .truncated {
                    connection.send(
                        content: Data("OK".utf8), contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in })
                    return
                }
                send(Data((behavior == .wrongHandshake ? "NOPE" : "OKAY").utf8), to: connection) { [weak self] in
                    self?.readCommand(from: connection)
                }
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.listener.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    self?.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
        return "localhost:\(listener.port!.rawValue)"
    }

    func stop() {
        queue.sync {
            for connection in connections { connection.cancel() }
            listener.cancel()
        }
    }

    private func read(_ count: Int, from connection: NWConnection, completion: @escaping @Sendable (Data) -> Void) {
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { bytes, _, _, error in
            guard error == nil, let bytes, bytes.count == count else { return }
            completion(bytes)
        }
    }

    private func send(_ data: Data, to connection: NWConnection, completion: @escaping @Sendable () -> Void) {
        if fragmented, data.count > 1 {
            connection.send(
                content: Data(data.prefix(1)),
                completion: .contentProcessed { [weak self] _ in
                    self?.queue.asyncAfter(deadline: .now() + 0.01) {
                        connection.send(
                            content: Data(data.dropFirst()), completion: .contentProcessed { _ in completion() })
                    }
                })
        } else {
            connection.send(content: data, completion: .contentProcessed { _ in completion() })
        }
    }

    private func readCommand(from connection: NWConnection) {
        read(2, from: connection) { [weak self] header in
            guard let self else { return }
            let length = Int(header[0]) * 256 + Int(header[1])
            read(length, from: connection) { [weak self] request in
                guard let self else { return }
                let command = String(decoding: request, as: UTF8.self)
                recordedCommands.append(command)
                let response: Data
                switch command {
                case "VERN": response = self.u32(version)
                case "SIZE":
                    response =
                        behavior == .badSize
                        ? Data([0, 0, 0, 0])
                        : behavior == .oversizedSize ? Data([64, 0, 36, 0]) : Data([5, 0, 2, 208])
                case "BNDL":
                    response =
                        behavior == .hugeBundle
                        ? u32(UInt32.max) : u32(UInt32(bundleID.utf8.count)) + Data(bundleID.utf8)
                case "RECT":
                    if behavior == .truncatedBounds {
                        connection.send(
                            content: Data([0, 0]), contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { _ in })
                        return
                    }
                    response =
                        behavior == .badBounds
                        ? Data(repeating: 0, count: 16)
                        : Data([0, 0, 0, 0, 5, 0, 2, 228, 0, 0, 0, 0, 5, 0, 2, 208])
                case "BGR\u{1}":
                    response =
                        behavior == .badImage
                        ? u32(UInt32.max) + u32(UInt32.max) + u32(UInt32.max)
                        : u32(1280) + u32(720) + u32(1280 * 720 * 3) + Data(repeating: 42, count: 1280 * 720 * 3)
                case "SCRN": response = u32(1280 * 720 * 4) + Data(repeating: 42, count: 1280 * 720 * 4)
                default:
                    connection.cancel()
                    return
                }
                if command == "BGR\u{1}", behavior == .stalledImage {
                    send(Data(response.prefix(12)), to: connection) {}
                } else if command == "BGR\u{1}", behavior == .delayedImageHeader {
                    queue.asyncAfter(deadline: .now() + 3.25) { [weak self] in
                        self?.send(response, to: connection) { [weak self] in self?.readCommand(from: connection) }
                    }
                } else {
                    send(response, to: connection) { [weak self] in self?.readCommand(from: connection) }
                }
            }
        }
    }
    private func u32(_ value: UInt32) -> Data {
        var value = value.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
}

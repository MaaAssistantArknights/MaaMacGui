import Foundation
import Testing

@testable import PlayCoverDiagnostics

@Suite struct RuntimeDependencyTests {
    private func inspect(
        _ server: MockMaaToolsServer, mode: String = "BGR",
        bundleID: String? = nil, permission: Bool? = nil
    ) async throws -> [PlayCoverDiagnosticItem] {
        let address = try await server.start()
        defer { server.stop() }
        return try await PlayCoverRuntimeChecks.inspect(
            address: address, mode: mode,
            bundleID: bundleID ?? server.bundleID, screenPermission: permission)
    }

    private func row(_ id: String, _ items: [PlayCoverDiagnosticItem]) throws -> PlayCoverDiagnosticItem {
        try #require(items.first { $0.id == "runtime-\(id)" })
    }

    @Test func failedHandshakeStopsAllCommandsAndMarksEveryDependentStageSkipped() async throws {
        let server = try MockMaaToolsServer(behavior: .wrongHandshake)
        let items = try await inspect(server)
        #expect(try row("handshake", items).status == .error)
        for id in ["version", "identity", "size", "window", "capture"] {
            let item = try row(id, items)
            #expect(item.status == .unavailable && item.value == "已跳过")
            #expect(item.blockedBy == ["runtime-handshake"])
        }
        #expect(server.commands.isEmpty)
    }

    @Test func unsupportedBaseProtocolStopsBeforeIdentityAndSize() async throws {
        let server = try MockMaaToolsServer(version: 1)
        let items = try await inspect(server)
        #expect(try row("version", items).status == .error)
        #expect(try row("size", items).blockedBy == ["runtime-version"])
        #expect(server.commands == ["VERN"])
    }

    @Test func versionTwoBGRStillReadsIndependentSizeWithoutUnsupportedCommands() async throws {
        let server = try MockMaaToolsServer(version: 2)
        let items = try await inspect(server)
        #expect(try row("version", items).status == .error)
        #expect(try row("identity", items).status == .unavailable)
        #expect(try row("size", items).status == .passed)
        #expect(try row("capture", items).blockedBy == ["runtime-version"])
        #expect(server.commands == ["VERN", "SIZE"])
    }

    @Test func wrongGameNeverReceivesSizeWindowOrScreenshotRequests() async throws {
        let server = try MockMaaToolsServer()
        let items = try await inspect(server, bundleID: "other.game")
        #expect(try row("identity", items).status == .error)
        #expect(try row("capture", items).blockedBy == ["runtime-identity"])
        #expect(server.commands == ["VERN", "BNDL"])
    }

    @Test func corruptedIdentityStopsLaterRequests() async throws {
        let server = try MockMaaToolsServer(behavior: .hugeBundle)
        let items = try await inspect(server)
        #expect(try row("identity", items).status == .error)
        #expect(try row("size", items).blockedBy == ["runtime-identity"])
        #expect(server.commands == ["VERN", "BNDL"])
    }

    @Test func validButOverBudgetSizeIsUnknownRatherThanCorrupt() async throws {
        let server = try MockMaaToolsServer(behavior: .oversizedSize)
        let items = try await inspect(server)
        #expect(try row("size", items).status == .unavailable)
        #expect(try row("size", items).value == "16384×9216")
        #expect(try row("capture", items).blockedBy == ["runtime-size"])
        #expect(server.commands == ["VERN", "BNDL", "SIZE"])
    }

    @Test func invalidSizeStopsWindowAndImageRequests() async throws {
        let server = try MockMaaToolsServer(behavior: .badSize)
        let items = try await inspect(server)
        #expect(try row("size", items).status == .error)
        #expect(try row("window", items).blockedBy == ["runtime-size"])
        #expect(try row("capture", items).blockedBy == ["runtime-size"])
        #expect(server.commands == ["VERN", "BNDL", "SIZE"])
    }

    @Test func incompleteBoundsDoesNotRequestBGRAndDoesNotReportImageFailure() async throws {
        let server = try MockMaaToolsServer(behavior: .truncatedBounds)
        let items = try await inspect(server)
        #expect(try row("window", items).status == .error)
        #expect(try row("capture", items).status == .unavailable)
        #expect(try row("capture", items).blockedBy == ["runtime-window"])
        #expect(server.commands == ["VERN", "BNDL", "SIZE", "RECT"])
    }

    @Test func invalidWindowDimensionsDoNotBlockIndependentBGRImageJudgment() async throws {
        let server = try MockMaaToolsServer(behavior: .badBounds)
        let items = try await inspect(server)
        #expect(try row("window", items).status == .error)
        #expect(try row("capture", items).status == .passed)
        #expect(server.commands.last == "BGR\u{1}")
    }

    @Test func invalidWindowDimensionsBlockMacSCKCropping() async throws {
        let server = try MockMaaToolsServer(behavior: .badBounds)
        let items = try await inspect(server, mode: "MacSCK", permission: true)
        #expect(try row("window", items).status == .error)
        #expect(try row("capture", items).blockedBy == ["runtime-window"])
        #expect(server.commands == ["VERN", "BNDL", "SIZE", "RECT"])
    }

    @Test func deniedScreenPermissionSkipsOnlyMacSCKImageCapture() async throws {
        let server = try MockMaaToolsServer()
        let items = try await inspect(server, mode: "MacSCK", permission: false)
        for id in ["handshake", "version", "identity", "size", "window"] {
            #expect(try row(id, items).status == .passed)
        }
        #expect(try row("capture", items).blockedBy == ["screen-permission"])
        #expect(server.commands == ["VERN", "BNDL", "SIZE", "RECT"])
    }

    @Test func invalidCaptureModeDoesNotHideServiceIdentityOrSize() async throws {
        let server = try MockMaaToolsServer()
        let items = try await inspect(server, mode: "unknown")
        #expect(try row("identity", items).status == .passed)
        #expect(try row("size", items).status == .passed)
        #expect(try row("capture", items).blockedBy == ["capture-mode"])
        #expect(server.commands == ["VERN", "BNDL", "SIZE"])
    }

    @Test func corruptBGRDataReportsOnlyActualCaptureAsFailed() async throws {
        let server = try MockMaaToolsServer(behavior: .badImage)
        let items = try await inspect(server)
        #expect(try row("window", items).status == .passed)
        #expect(try row("capture", items).status == .error)
        #expect(items.filter { $0.status == .error }.map(\.id) == ["runtime-capture"])
        #expect(Set(items.map(\.id)).count == items.count)
    }
}

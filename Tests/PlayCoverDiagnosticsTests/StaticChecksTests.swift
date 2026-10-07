import CoreGraphics
import Foundation
import Testing

@testable import PlayCoverDiagnostics

@Suite struct StaticChecksTests {
    private var snapshot: PlayCoverDiagnosticSnapshot {
        .init(
            address: "localhost:1717", touchMode: "MacPlayTools", screenshotMode: "BGR",
            clientName: "官服", bundleID: "com.hypergryph.arknights", guiVersion: "test", coreVersion: "test")
    }
    private func settings(_ values: [String: Any]) throws -> PlayCoverGameSettings {
        try PlayCoverStaticChecks.readSettings(
            PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        ).settings
    }
    private func status(_ id: String, in items: [PlayCoverDiagnosticItem]) -> PlayCoverDiagnosticStatus? {
        items.first { $0.id == id }?.status
    }

    @Test func testForkOnlyRequiresMAAVersionMarker() {
        for version in ["3.1.0.maa.10", "3.1.0-maa", "maa", "3.1.0.MAA.10"] {
            let info = ["CFBundleShortVersionString": version]
            #expect(PlayCoverStaticChecks.version(info: info).status == .passed)
        }
        let info = [
            "CFBundleShortVersionString": "3.1.0.maa.10", "CFBundleIdentifier": "custom.bundle",
            "SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": "other-key",
        ]
        #expect(PlayCoverStaticChecks.version(info: info).status == .passed)
    }

    @Test func testVersionWithoutMAAMarkerOrReadableValue() {
        for version in ["3.1.0", "3.1.0.custom"] {
            #expect(
                PlayCoverStaticChecks.version(info: ["CFBundleShortVersionString": version]).status == .error)
        }
        for info: [String: Any] in [[:], ["CFBundleShortVersionString": 3], ["CFBundleShortVersionString": "  "]] {
            #expect(
                PlayCoverStaticChecks.version(info: info).status == .unavailable)
        }
    }

    @Test func testMissingFieldsAreUnknownRatherThanDefaulted() throws {
        let items = PlayCoverStaticChecks.settingsItems(try settings([:]))
        #expect(status("maatools", in: items) == .unavailable)
        #expect(status("game-port", in: items) == .unavailable)
        #expect(status("playchain", in: items) == .warning)
        #expect(status("bypass", in: items) == .warning)
        let graphics = PlayCoverStaticChecks.graphics(try settings([:]))
        #expect(graphics.allSatisfy { $0.status == .unavailable })
    }

    @Test func configurationTypesDoNotCoerceBooleansOrFractionalIntegers() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: [
                "maaTools": 1, "maaToolsPort": true, "playChain": true, "bypass": false,
                "windowWidth": 1280.0, "windowHeight": 720.5, "customScaler": 2,
            ], format: .binary, options: 0)
        let read = try PlayCoverStaticChecks.readSettings(data)
        #expect(Set(read.errors.keys) == ["maaTools", "maaToolsPort", "windowHeight"])
        #expect(read.settings.maaTools == nil && read.settings.maaToolsPort == nil)
        #expect(read.settings.playChain == true && read.settings.bypass == false)
        #expect(read.settings.windowWidth == 1280 && read.settings.customScaler == 2)
    }

    @Test func testInvalidConnectionFieldDoesNotEraseValidGraphics() throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: [
                "maaTools": "invalid", "maaToolsPort": 1717,
                "resolution": 5, "windowWidth": 1280, "windowHeight": 720, "customScaler": 2.0, "displayRotation": 0,
            ], format: .binary, options: 0)
        let read = try PlayCoverStaticChecks.readSettings(data)
        let switches = PlayCoverStaticChecks.settingsItems(read.settings, invalidFields: read.errors)
        #expect(status("maatools", in: switches) == .error)
        #expect(status("game-port", in: switches) == .passed)
        #expect(
            PlayCoverStaticChecks.graphics(read.settings, invalidFields: read.errors).allSatisfy {
                $0.status == .passed
            })
    }

    @Test func testMissingPrerequisiteResultsNeverPermitRuntime() {
        let empty = PlayCoverStaticResult(items: [], gameURL: nil, port: nil)
        #expect(empty.runtimeBlockers.count == 6)
        #expect(empty.runtimeBlockers.allSatisfy { $0.status == .unavailable })
    }

    @Test func testRequiredAndRecommendedSwitches() throws {
        let items = PlayCoverStaticChecks.settingsItems(
            try settings([
                "maaTools": false, "maaToolsPort": 65536, "playChain": false, "bypass": false,
            ]))
        #expect(status("maatools", in: items) == .error)
        #expect(status("game-port", in: items) == .error)
        #expect(status("playchain", in: items) == .warning)
        #expect(status("bypass", in: items) == .warning)
    }

    @Test func testGraphicsPreservesStaticChecksAndDoesNotForcePreset() throws {
        let good = try settings([
            "resolution": 5, "windowWidth": 960, "windowHeight": 540,
            "customScaler": 2.0, "displayRotation": 0,
        ])
        #expect(PlayCoverStaticChecks.graphics(good).allSatisfy { $0.status == .passed })
        let bad = try settings([
            "resolution": 6, "windowWidth": 0, "windowHeight": 720,
            "customScaler": -1.0, "displayRotation": 90,
        ])
        let items = PlayCoverStaticChecks.graphics(bad)
        #expect(status("configured-size", in: items) == .error)
        #expect(status("scale", in: items) == .error)
        #expect(status("rotation", in: items) == .error)
        #expect(status("resolution-mode", in: items) == .warning)
    }

    @Test func testEndpointParsingAndLoopbackEquivalence() {
        for address in ["localhost:1717", "127.0.0.1:1717", "127.0.0.2:1717", "[::1]:1717", "[0:0:0:0:0:0:0:1]:1717"] {
            #expect(MaaToolsEndpoint(address)?.matchesLocalPort(1717) == true)
        }
        for address in [
            "localhost", "localhost:0", "localhost:65536", "localhost:abc",
            "localhost:1717/path", "user@localhost:1717", "localhost:1717?x=1", "localhost:1717#x",
        ] {
            #expect(MaaToolsEndpoint(address) == nil)
        }
        #expect(!(MaaToolsEndpoint("localhost:1718")!.matchesLocalPort(1717)))
        #expect(!(MaaToolsEndpoint("example.com:1717")!.matchesLocalPort(1717)))
    }

    @Test func testMAAConfigurationAndScreenPermission() {
        let bad = PlayCoverDiagnosticSnapshot(
            address: "127.0.0.1:5555", touchMode: "maatouch",
            screenshotMode: "MacSCK", clientName: "官服", bundleID: snapshot.bundleID, guiVersion: "test",
            coreVersion: "test")
        let items = PlayCoverStaticChecks.maa(bad, port: 1717, screenPermission: false)
        #expect(status("touch-mode", in: items) == .error)
        #expect(status("address", in: items) == .error)
        #expect(status("screen-permission", in: items) == .error)
        #expect(
            status("address", in: PlayCoverStaticChecks.maa(snapshot, port: nil, screenPermission: false))
                == .unavailable)
    }

    @Test func loopbackIPv6MatchesPortButIsNotAcceptedByCurrentCoreParser() {
        let ipv6 = PlayCoverDiagnosticSnapshot(
            address: "[::1]:1717", touchMode: "MacPlayTools", screenshotMode: "BGR",
            clientName: "官服", bundleID: snapshot.bundleID, guiVersion: "test", coreVersion: "test")
        let rows = PlayCoverStaticChecks.maa(ipv6, port: 1717, screenPermission: false)
        #expect(status("address", in: rows) == .passed)
        #expect(status("address-core", in: rows) == .error)
    }

    @Test func testSharedImageRules() {
        #expect(MaaImageDiagnosis.evaluate(original: (1280, 720), width: 1280, height: 720) == .passed)
        #expect(MaaImageDiagnosis.evaluate(original: (1920, 1080), width: 1920, height: 1080) == .passed)
        #expect(MaaImageDiagnosis.evaluate(original: (1280, 720), width: 1920, height: 1080) == .sizeMismatch)
        #expect(MaaImageDiagnosis.evaluate(original: (1024, 768), width: 1024, height: 768) == .aspectRatio)
        #expect(MaaImageDiagnosis.evaluate(original: (640, 360), width: 640, height: 360) == .lowResolution)
    }

    @Test func testBGRAndRGBAConversionValidatePayloadAndChannels() async throws {
        let bgr = try await CGImage.bgr(((1, 1), Data([10, 20, 30])))
        let rgba = try MaaImageDiagnostics.rgba(Data([30, 20, 10, 255]), size: (1, 1))
        func pixel(_ image: CGImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: 4)
            bytes.withUnsafeMutableBytes {
                let context = CGContext(
                    data: $0.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
                context!.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            return Array(bytes.prefix(3))
        }
        #expect(pixel(bgr) == [30, 20, 10])
        #expect(pixel(rgba) == [30, 20, 10])
        #expect(throws: (any Error).self) { _ = try MaaImageDiagnostics.rgba(Data([1]), size: (1280, 720)) }
        do {
            _ = try await CGImage.bgr(((UInt32.max, UInt32.max), Data([1])))
            Issue.record("Unexpected success")
        } catch {}
    }

    @Test func narrowBGRImageUsesPackedRows() async throws {
        let image = try await CGImage.bgr(((1, 720), Data(repeating: 127, count: 720 * 3)))
        #expect(image.width == 1)
        #expect(image.height == 720)
        #expect(image.bytesPerRow == 4)
        let bytes = try #require(image.dataProvider?.data)
        #expect(CFDataGetLength(bytes) == 720 * 4)
    }

    @Test func testReportRedactsHomeAndDoesNotIncludeUnrelatedSettings() {
        let row = PlayCoverStaticChecks.item("path", .game, "游戏", .passed, "/Users/example/Library/game.app", "", "")
        let report = PlayCoverDiagnosticReport(date: Date(), snapshot: snapshot, items: [row])
        let text = report.text(homePath: "/Users/example")
        #expect(!(text.contains("/Users/example")))
        #expect(text.contains("~/Library/game.app"))
        #expect(text.contains("MAA GUI: test"))
    }

    @Test func testMachOLoadCommandsAndMalformedBinary() throws {
        let binary = macho(library: "/Users/test/Library/Frameworks/PlayTools.framework/PlayTools")
        #expect(try MachOLibraries.read(binary).count == 1)
        #expect(try MachOLibraries.read(binary)[0].hasSuffix("/PlayTools"))
        #expect(throws: (any Error).self) { _ = try MachOLibraries.read(Data(binary.prefix(40))) }
        #expect(throws: (any Error).self) { _ = try MachOLibraries.read(Data()) }
    }

    @Test func testUniversalBinaryUsesOnlyArm64AndChecksSliceBoundaries() throws {
        func be32(_ value: UInt32) -> Data {
            var value = value.bigEndian
            return withUnsafeBytes(of: &value) { Data($0) }
        }
        func be64(_ value: UInt64) -> Data {
            var value = value.bigEndian
            return withUnsafeBytes(of: &value) { Data($0) }
        }
        var x86 = macho(library: "/Tools/PlayTools.framework/PlayTools")
        x86.replaceSubrange(4..<8, with: [7, 0, 0, 1])
        let arm = macho(library: "/usr/lib/libSystem.B.dylib")
        for is64 in [false, true] {
            let tableEnd = UInt64(8 + 2 * (is64 ? 32 : 20))
            var binary = be32(is64 ? 0xcafe_babf : 0xcafe_babe) + be32(2)
            for (cpu, offset, size) in [
                (UInt32(0x0100_0007), tableEnd, UInt64(x86.count)),
                (UInt32(0x0100_000c), tableEnd + UInt64(x86.count), UInt64(arm.count)),
            ] {
                binary += be32(cpu) + be32(0)
                binary += is64 ? be64(offset) + be64(size) : be32(UInt32(offset)) + be32(UInt32(size))
                binary += be32(0)
                if is64 { binary += be32(0) }
            }
            binary += x86 + arm
            #expect(try MachOLibraries.read(binary) == ["/usr/lib/libSystem.B.dylib"])
            #expect(throws: (any Error).self) { _ = try MachOLibraries.read(Data(binary.dropLast())) }
        }
        var unterminated = macho(library: "PlayTools.framework/PlayTools")
        unterminated[unterminated.count - 1] = 1
        #expect(throws: (any Error).self) { _ = try MachOLibraries.read(unterminated) }
        var oversizedCommands = arm
        oversizedCommands.replaceSubrange(20..<24, with: [255, 255, 255, 127])
        #expect(throws: (any Error).self) { _ = try MachOLibraries.read(oversizedCommands) }
    }

    @Test func testFixtureUsesGameInfoPlistForIntrospectionAndLeavesFilesUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("PlayCover.app")
        let data = root.appendingPathComponent("io.playcover.PlayCover")
        let game = data.appendingPathComponent("Applications/\(snapshot.bundleID).app")
        for dir in [
            app.appendingPathComponent("Contents/Frameworks/PlayTools.framework"), game,
            data.appendingPathComponent("App Settings"),
        ] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        func write(_ dictionary: [String: Any], at url: URL) throws {
            try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0).write(to: url)
        }
        try write(
            [
                "CFBundleIdentifier": "io.playcover.PlayCover", "CFBundleShortVersionString": "3.1.0.maa.10",
            ],
            at: app.appendingPathComponent("Contents/Info.plist"))
        try Data([1]).write(to: app.appendingPathComponent("Contents/Frameworks/PlayTools.framework/PlayTools"))
        let gameInfo = game.appendingPathComponent("Info.plist")
        try write(
            [
                "CFBundleIdentifier": snapshot.bundleID, "CFBundleExecutable": "game",
                "LSEnvironment": ["DYLD_LIBRARY_PATH": "/usr/lib/system/introspection:"],
            ], at: gameInfo)
        try macho(library: "/Users/test/Library/Frameworks/PlayTools.framework/PlayTools").write(
            to: game.appendingPathComponent("game"))
        let settingsURL = data.appendingPathComponent("App Settings/\(snapshot.bundleID).plist")
        try write(
            [
                "maaTools": true, "maaToolsPort": 1717, "playChain": true, "bypass": true,
                "injectIntrospection": false, "resolution": 5, "windowWidth": 1280, "windowHeight": 720,
                "customScaler": 1.0, "displayRotation": 0,
            ], at: settingsURL)
        let before = try Data(contentsOf: settingsURL)
        let result = PlayCoverStaticChecks.run(snapshot: snapshot, appURL: app, dataURL: data, screenPermission: false)
        #expect(status("introspection", in: result.items) == .passed)
        #expect(status("injected-tools", in: result.items) == .passed)
        #expect(result.port == 1717)
        #expect(status("fork", in: result.items) == .passed)
        #expect(status("bundled-tools", in: result.items) == .passed)
        #expect(before == (try Data(contentsOf: settingsURL)))
        try write(["CFBundleIdentifier": snapshot.bundleID, "CFBundleExecutable": "game"], at: gameInfo)
        let without = PlayCoverStaticChecks.run(snapshot: snapshot, appURL: app, dataURL: data, screenPermission: false)
        #expect(status("introspection", in: without.items) == .warning)
        try FileManager.default.removeItem(
            at: app.appendingPathComponent("Contents/Frameworks/PlayTools.framework/PlayTools"))
        let missingFramework = PlayCoverStaticChecks.run(
            snapshot: snapshot, appURL: app, dataURL: data, screenPermission: false)
        #expect(status("fork", in: missingFramework.items) == .passed)
        #expect(status("bundled-tools", in: missingFramework.items) == .error)
    }

    @Test func oversizedPlistIsUnknownRatherThanDeclaredCorrupt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("App Settings"), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 1024 * 1024 + 1).write(
            to: root.appendingPathComponent("App Settings/\(snapshot.bundleID).plist"))
        let result = PlayCoverStaticChecks.run(
            snapshot: snapshot, appURL: root.appendingPathComponent("PlayCover.app"), dataURL: root,
            screenPermission: false)
        #expect(status("game-settings", in: result.items) == .unavailable)
        #expect(result.items.first { $0.id == "game-settings" }?.reason.contains("1 MiB") == true)
        #expect(result.items.first { $0.id == "maatools" }?.blockedBy == ["game-settings"])
    }

    @Test func unreadableDirectoriesSkipDependentChecks() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let report = PlayCoverStaticChecks.run(
            snapshot: snapshot, appURL: missing, dataURL: missing, screenPermission: false)
        #expect(status("playcover-location", in: report.items) == .error)
        #expect(status("data-location", in: report.items) == .error)
        #expect(status("game-settings", in: report.items) == .unavailable)
        #expect(status("fork", in: report.items) == .unavailable)
    }

    @Test func testDeniedDataAccessDoesNotReportMissingGameOrPass() {
        for error in [
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError),
            NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)),
            NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM)),
        ] {
            let item = PlayCoverStaticChecks.readFailure("game-install", .game, "游戏安装", error)
            #expect(item.status == .unavailable)
            #expect(item.value == "访问被拒绝")
            #expect(item.remedy.contains("隐私与安全性"))
        }
    }

    @Test func testFailedReadIncludesRedactedAttemptedPathInReport() {
        let home = "/Users/example"
        let url = URL(
            fileURLWithPath: home + "/Library/Containers/io.playcover.PlayCover/Applications/game.app/Info.plist")
        let item = PlayCoverStaticChecks.readFailure(
            "game-install", .game, "游戏安装",
            NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError), path: url)
        let report = PlayCoverDiagnosticReport(date: Date(), snapshot: snapshot, items: [item])
        let text = report.text(homePath: home)
        #expect(item.reason.contains(url.path))
        #expect(!text.contains(home))
        #expect(text.contains("检测路径：~/Library/Containers/io.playcover.PlayCover/Applications/game.app/Info.plist"))
    }

    @Test func testMacSCKWindowSelectionAndTitlebarCrop() throws {
        #expect(
            ScreenCaptureProbe.matches(
                bundleID: "game", title: "Game [localhost:1717]", expectedBundleID: "game", port: 1717))
        #expect(
            !ScreenCaptureProbe.matches(
                bundleID: "other", title: "Game [localhost:1717]", expectedBundleID: "game", port: 1717))
        #expect(
            !ScreenCaptureProbe.matches(
                bundleID: "game", title: "Game [localhost:1718]", expectedBundleID: "game", port: 1717))
        let rect: (window: MaaToolsClient.Rect, content: MaaToolsClient.Rect) = (
            ((0, 0), (1280, 740)), ((0, 0), (1280, 720))
        )
        let configuration = try ScreenCaptureProbe.configuration(size: (1280, 720), rect: rect)
        #expect(configuration.width == 1280)
        #expect(configuration.height == 720)
        #expect(configuration.sourceRect == CGRect(x: 0, y: 20, width: 1280, height: 720))
        #expect(!configuration.showsCursor)
        #expect(throws: (any Error).self) { _ = try ScreenCaptureProbe.configuration(size: (.max, .max), rect: rect) }
    }
}

func macho(library: String) -> Data {
    func u32(_ value: UInt32) -> Data {
        var value = value.littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    let name = Data(library.utf8) + Data([0])
    let size = UInt32(24 + name.count)
    var result = Data()
    for value: UInt32 in [0xfeed_facf, 0x100000c, 0, 2, 1, size, 0, 0, 0xc, size, 24, 0, 0, 0] { result += u32(value) }
    result += name
    return result
}

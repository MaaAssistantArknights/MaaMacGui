import Darwin
import Foundation
import Testing

@testable import PlayCoverDiagnostics

@Suite @MainActor struct DiagnosticModelTests {
    private var snapshot: PlayCoverDiagnosticSnapshot {
        .init(
            address: "localhost:1717", touchMode: "MacPlayTools", screenshotMode: "BGR",
            clientName: "官服", bundleID: "com.hypergryph.arknights", guiVersion: "test", coreVersion: "test")
    }

    private func finish(_ model: PlayCoverDiagnosticModel) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while model.isDetecting && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!model.isDetecting)
    }

    private func withGame(
        settings: [String: Any] = ["maaTools": true, "maaToolsPort": 1717],
        _ body: (PlayCoverAccess) async throws -> Void
    ) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let game = root.appendingPathComponent("Applications/\(snapshot.bundleID).app")
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": snapshot.bundleID, "CFBundleExecutable": "game"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: game.appendingPathComponent("Info.plist"))
        try macho(library: "/Users/test/Library/Frameworks/PlayTools.framework/PlayTools")
            .write(to: game.appendingPathComponent("game"))
        let settingsURL = root.appendingPathComponent("App Settings/\(snapshot.bundleID).plist")
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0).write(to: settingsURL)
        let access = PlayCoverAccess(applicationURL: root.appendingPathComponent("PlayCover.app"), dataURL: root)
        try await body(access)
    }

    @Test func absentLaunchCallbackIsBounded() async throws {
        let launcher = PlayCoverGameLauncher()
        let start = ContinuousClock.now
        do {
            try await launcher.wait(timeout: 0.05) { _ in }
            Issue.record("Unexpected launch completion")
        } catch PlayCoverGameLauncher.Error.timedOut {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(start.duration(to: .now) < .seconds(1))
    }

    @Test func cancelledLaunchDoesNotWaitForSystemCompletion() async throws {
        let launcher = PlayCoverGameLauncher()
        let task = Task { try await launcher.wait { _ in } }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        do {
            try await task.value
            Issue.record("Unexpected completion")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func defaultPathsNeedNoUserSelectionAndExpiredCustomGrantFallsBack() {
        let suite = "PlayCoverDiagnosticsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let access = PlayCoverAccess(defaults: defaults)
        #expect(access.applicationURL == PlayCoverAccess.defaultApplicationURL)
        #expect(access.dataURL == PlayCoverAccess.defaultDataURL)
        #expect(access.message == nil)
        defaults.set(Data([0xff]), forKey: PlayCoverAccess.Location.data.key)
        let expired = PlayCoverAccess(defaults: defaults)
        #expect(expired.dataURL == PlayCoverAccess.defaultDataURL)
        #expect(expired.message != nil)
        expired.useDefaultLocations()
        #expect(expired.message == nil)
        #expect(defaults.data(forKey: PlayCoverAccess.Location.data.key) == nil)
    }

    @Test func realUserHomeMatchesAccountDatabaseRatherThanAppContainer() throws {
        var record = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 1_048_576)
        let (status, path) = buffer.withUnsafeMutableBufferPointer { pointer -> (Int32, String?) in
            let status = getpwuid_r(getuid(), &record, pointer.baseAddress, pointer.count, &result)
            return (status, status == 0 && result != nil ? record.pw_dir.map { String(cString: $0) } : nil)
        }
        #expect(status == 0)
        let realHome = URL(fileURLWithPath: try #require(path), isDirectory: true)
        #expect(PlayCoverAccess.userHome == realHome)
        #expect(
            PlayCoverAccess.defaultDataURL
                == realHome.appendingPathComponent("Library/Containers/io.playcover.PlayCover"))
    }

    @Test func runningGameContinuesWithoutRelaunch() async throws {
        try await withGame { access in
            var opens = 0
            var waits = 0
            var probes = 0
            let model = PlayCoverDiagnosticModel(
                isGameRunning: { _ in true },
                openGame: { _ in opens += 1 }, waitForService: { _ in waits += 1 },
                inspect: { _, _, _, _, _ in
                    probes += 1
                    return []
                })
            model.start(snapshot: snapshot, access: access, runtimeAllowed: true, launch: true)
            try await finish(model)
            #expect(opens == 0 && waits == 0 && probes == 1)
            #expect(model.report?.items.contains { $0.id == "game-process" && $0.status == .passed } == true)
        }
    }

    @Test func timeoutRetainsStaticResultsAndAllowsContinuation() async throws {
        try await withGame { access in
            var running = false
            var opens = 0
            var probes = 0
            let model = PlayCoverDiagnosticModel(
                isGameRunning: { _ in running },
                openGame: { _ in
                    opens += 1
                    running = true
                },
                waitForService: { _ in throw MaaToolsError.timedOut },
                inspect: { _, _, _, _, _ in
                    probes += 1
                    return []
                })
            model.start(snapshot: snapshot, access: access, runtimeAllowed: true, launch: true)
            try await finish(model)
            #expect(opens == 1 && probes == 0)
            #expect(model.report?.items.contains { $0.id == "game-install" && $0.status == .passed } == true)
            #expect(model.report?.items.contains { $0.id == "service-wait" && $0.status == .error } == true)
            model.start(snapshot: snapshot, access: access, runtimeAllowed: true, launch: true)
            try await finish(model)
            #expect(opens == 1 && probes == 1)
        }
    }

    @Test func taskInProgressNeverLaunchesOrConnects() async throws {
        try await withGame { access in
            var opens = 0
            var waits = 0
            var probes = 0
            let model = PlayCoverDiagnosticModel(
                isGameRunning: { _ in false },
                openGame: { _ in opens += 1 }, waitForService: { _ in waits += 1 },
                inspect: { _, _, _, _, _ in
                    probes += 1
                    return []
                })
            model.start(snapshot: snapshot, access: access, runtimeAllowed: false, launch: true)
            try await finish(model)
            #expect(opens == 0 && waits == 0 && probes == 0)
            #expect(model.report?.items.contains { $0.id == "runtime-skipped" && $0.status == .unavailable } == true)
        }
    }

    @Test func missingGameExplainsWhyLaunchCannotContinue() async throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let access = PlayCoverAccess(applicationURL: missing, dataURL: missing)
        var opens = 0
        let model = PlayCoverDiagnosticModel(isGameRunning: { _ in false }, openGame: { _ in opens += 1 })
        model.start(snapshot: snapshot, access: access, runtimeAllowed: true, launch: true)
        try await finish(model)
        #expect(opens == 0)
        #expect(model.report?.items.contains { $0.id == "data-location" && $0.status == .error } == true)
        #expect(model.report?.items.contains { $0.id == "launch-failure" && $0.status == .unavailable } == true)
    }

    @Test func cancellingLaunchWaitEndsDetection() async throws {
        try await withGame { access in
            var waiting = false
            let model = PlayCoverDiagnosticModel(
                isGameRunning: { _ in false }, openGame: { _ in },
                waitForService: { _ in
                    waiting = true
                    try await Task.sleep(for: .seconds(20))
                })
            model.start(snapshot: snapshot, access: access, runtimeAllowed: true, launch: true)
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while !waiting && model.isDetecting && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(waiting)
            model.cancel()
            try await finish(model)
            #expect(model.report?.items.contains { $0.id == "cancelled" && $0.status == .unavailable } == true)
        }
    }

    @Test func disabledUnknownOrInvalidMaaToolsNeverProbesRunningGame() async throws {
        for settings: [String: Any] in [
            ["maaTools": false, "maaToolsPort": 1717],
            ["maaToolsPort": 1717], ["maaTools": "true", "maaToolsPort": 1717],
            ["maaTools": true, "maaToolsPort": 0], ["maaTools": true],
        ] {
            try await withGame(settings: settings) { access in
                var processes = 0
                var probes = 0
                var waits = 0
                let model = PlayCoverDiagnosticModel(
                    isGameRunning: { _ in
                        processes += 1
                        return true
                    },
                    waitForService: { _ in waits += 1 },
                    inspect: { _, _, _, _, _ in
                        probes += 1
                        return []
                    })
                model.start(snapshot: snapshot, access: access, runtimeAllowed: true)
                try await finish(model)
                #expect(processes == 0 && probes == 0 && waits == 0)
                let skipped = try #require(model.report?.items.first { $0.id == "runtime-skipped" })
                #expect(skipped.status == .unavailable && !skipped.blockedBy.isEmpty)
            }
        }
    }

    @Test func explicitLaunchWithMaaToolsDisabledDoesNotWaitForService() async throws {
        try await withGame(settings: ["maaTools": false, "maaToolsPort": 1717]) { access in
            var opens = 0
            var waits = 0
            var probes = 0
            let model = PlayCoverDiagnosticModel(
                isGameRunning: { _ in false },
                openGame: { _ in opens += 1 }, waitForService: { _ in waits += 1 },
                inspect: { _, _, _, _, _ in
                    probes += 1
                    return []
                })
            model.start(snapshot: snapshot, access: access, runtimeAllowed: true, launch: true)
            try await finish(model)
            #expect(opens == 1 && waits == 0 && probes == 0)
            #expect(model.report?.items.first { $0.id == "runtime-skipped" }?.blockedBy.contains("maatools") == true)
        }
    }

    @Test func missingInjectionBlocksServiceButKeepsGraphicsChecks() async throws {
        try await withGame(settings: ["maaTools": true, "maaToolsPort": 1717, "windowWidth": 0, "windowHeight": 720]) {
            access in
            let executable = access.dataURL.appendingPathComponent("Applications/\(snapshot.bundleID).app/game")
            try macho(library: "/usr/lib/libSystem.B.dylib").write(to: executable)
            var probes = 0
            let model = PlayCoverDiagnosticModel(
                isGameRunning: { _ in true },
                inspect: { _, _, _, _, _ in
                    probes += 1
                    return []
                })
            model.start(snapshot: snapshot, access: access, runtimeAllowed: true)
            try await finish(model)
            #expect(probes == 0)
            #expect(model.report?.items.first { $0.id == "injected-tools" }?.status == .error)
            #expect(model.report?.items.first { $0.id == "configured-size" }?.status == .error)
            #expect(
                model.report?.items.first { $0.id == "runtime-skipped" }?.blockedBy.contains("injected-tools") == true)
        }
    }

    @Test func graphicsAndRecommendedSwitchErrorsDoNotBlockService() async throws {
        try await withGame(settings: [
            "maaTools": true, "maaToolsPort": 1717, "playChain": false, "bypass": false,
            "windowWidth": "bad", "windowHeight": 720, "customScaler": -1.0,
        ]) { access in
            var probes = 0
            let model = PlayCoverDiagnosticModel(
                isGameRunning: { _ in true },
                inspect: { _, _, _, _, _ in
                    probes += 1
                    return []
                })
            model.start(snapshot: snapshot, access: access, runtimeAllowed: true)
            try await finish(model)
            #expect(probes == 1)
            #expect(model.report?.items.first { $0.id == "configured-size" }?.status == .error)
            #expect(model.report?.items.first { $0.id == "scale" }?.status == .error)
            #expect(model.report?.items.first { $0.id == "maatools" }?.status == .passed)
            #expect(model.report?.items.first { $0.id == "runtime-skipped" } == nil)
        }
    }

    @Test func badConfiguredAddressStillProbesValidGamePort() async throws {
        for address in ["invalid", "localhost:1718"] {
            try await withGame { access in
                let changed = PlayCoverDiagnosticSnapshot(
                    address: address, touchMode: "wrong", screenshotMode: "BGR",
                    clientName: snapshot.clientName, bundleID: snapshot.bundleID, guiVersion: "test",
                    coreVersion: "test")
                var addresses = [String]()
                let model = PlayCoverDiagnosticModel(
                    isGameRunning: { _ in true },
                    inspect: { _, address, _, _, _ in
                        addresses.append(address)
                        return []
                    })
                model.start(snapshot: changed, access: access, runtimeAllowed: true)
                try await finish(model)
                #expect(addresses == (address == "invalid" ? ["localhost:1717"] : [address, "localhost:1717"]))
                #expect(model.report?.items.first { $0.id == "touch-mode" }?.status == .error)
            }
        }
    }

    @Test func orphanSettingsRemainReadableButMissingGameBlocksRuntime() async throws {
        try await withGame { access in
            try FileManager.default.removeItem(
                at: access.dataURL.appendingPathComponent("Applications/\(snapshot.bundleID).app"))
            var probes = 0
            let model = PlayCoverDiagnosticModel(
                isGameRunning: { _ in true },
                inspect: { _, _, _, _, _ in
                    probes += 1
                    return []
                })
            model.start(snapshot: snapshot, access: access, runtimeAllowed: true)
            try await finish(model)
            #expect(probes == 0)
            #expect(model.report?.items.first { $0.id == "game-install" }?.status == .error)
            #expect(model.report?.items.first { $0.id == "game-settings" }?.status == .passed)
            #expect(model.report?.items.first { $0.id == "injected-tools" }?.blockedBy == ["game-install"])
            let items = try #require(model.report?.items)
            #expect(items.allSatisfy { item in item.blockedBy.allSatisfy { id in items.contains { $0.id == id } } })
        }
    }

    @Test func unreadableSettingsProduceOneRootFailureAndSkipChildren() async throws {
        try await withGame { access in
            let url = access.dataURL.appendingPathComponent("App Settings/\(snapshot.bundleID).plist")
            try Data("broken plist".utf8).write(to: url)
            var probes = 0
            let model = PlayCoverDiagnosticModel(
                isGameRunning: { _ in true },
                inspect: { _, _, _, _, _ in
                    probes += 1
                    return []
                })
            model.start(snapshot: snapshot, access: access, runtimeAllowed: true)
            try await finish(model)
            #expect(probes == 0)
            #expect(model.report?.items.first { $0.id == "game-settings" }?.status == .error)
            for id in ["maatools", "game-port", "graphics-settings"] {
                #expect(model.report?.items.first { $0.id == id }?.blockedBy == ["game-settings"])
            }
        }
    }
}

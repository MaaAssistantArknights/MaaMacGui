import Foundation

struct DailyTask {}

@main struct RunHookTests {
    static var checks = 0
    static func check(_ value: Bool, _ message: String) {
        checks += 1
        if !value { fatalError(message) }
    }
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("maa-hook-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = root.appendingPathComponent("run.json")
        let coordinator = DailyRunCoordinator(journalURL: journal)
        let id = try coordinator.begin(profileID: "配置 name", origin: .schedule)!
        check(try coordinator.begin(profileID: "other", origin: .hotkey) == nil, "duplicate start")
        try coordinator.transition(.preHook, for: id)
        let context = coordinator.active!
        let restarted = DailyRunCoordinator(journalURL: journal)
        check(restarted.active == nil && restarted.lastTerminal?.outcome == .interrupted, "recovery must not replay")
        try coordinator.transition(.postHook, for: id)
        check(try coordinator.begin(profileID: "other", origin: .manual) == nil, "post blocks new run")
        check(try coordinator.finish(UUID(), outcome: .completed, cleanupSucceeded: true) == false, "foreign completion")
        check(try coordinator.finish(id, outcome: .failed, cleanupSucceeded: false), "first finish")
        check(try coordinator.finish(id, outcome: .completed, cleanupSucceeded: true) == false, "duplicate finish")
        check(DailyRunCoordinator(journalURL: journal).lastTerminal?.cleanupSucceeded == false, "terminal persisted")
        let script = root.appendingPathComponent("脚本 with spaces.zsh")
        func command(_ text: String, arguments: [String] = []) throws -> HookCommand {
            try text.write(to: script, atomically: true, encoding: .utf8)
            return HookCommand(bookmark: try script.bookmarkData(options: .withSecurityScope), displayPath: script.path, arguments: arguments)
        }
        let runner = HookRunner()
        let cmd = try command("printf '%s\\n' \"$1\" \"$2\" \"$MAA_RUN_ID\" \"$MAA_RUN_ORIGIN\" \"$MAA_RUN_RESULT\"; printf 'err' >&2", arguments: ["$(touch injected)", "中文 参数"])
        let result = try await runner.run(command: cmd, context: context, outcome: .failed, adbPath: "/test adb", workingDirectory: root)
        check(result.succeeded, "exit success")
        check(result.stdout == "$(touch injected)\n中文 参数\n\(id.uuidString)\nschedule\nfailed\n", "argv environment literal")
        check(result.stderr == "err", "stderr")
        check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("injected").path), "no shell interpolation")
        let native = URL(filePath: "/usr/bin/printf")
        let direct = HookCommand(bookmark: try native.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]), displayPath: native.path,
                                 arguments: ["%s", "中文 $(literal)"], shellScript: false)
        let nativeResult = try await runner.run(command: direct, context: context, outcome: nil, adbPath: "", workingDirectory: root)
        check(nativeResult.succeeded && nativeResult.stdout == "中文 $(literal)", "selected executable receives literal argv")
        var invalid = direct
        invalid.arguments = ["nul\0suffix"]
        do {
            _ = try await runner.run(command: invalid, context: context, outcome: nil, adbPath: "", workingDirectory: root)
            check(false, "NUL arguments rejected")
        } catch { check(true, "NUL arguments rejected") }
        let fail = try command("exit 23")
        let failed = try await runner.run(command: fail, context: context, outcome: nil, adbPath: "", workingDirectory: root)
        check(failed.exitCode == 23 && !failed.succeeded, "nonzero preserved")
        let loud = try command("for i in {1..6000}; do print '1234567890'; print -u2 'abcdefghij'; done")
        let large = try await runner.run(command: loud, context: context, outcome: nil, adbPath: "", workingDirectory: root)
        check(large.succeeded && large.stdout.utf8.count == 32768 && large.stderr.utf8.count == 32768, "bounded streams")
        check(large.stdoutTruncated && large.stderrTruncated, "truncation explicit")
        let hang = try command("trap '' TERM; /bin/sleep 30 & wait")
        let start = Date()
        let timed = try await runner.run(command: hang, context: context, outcome: nil, adbPath: "", workingDirectory: root, timeout: 1)
        check(timed.timedOut && !timed.succeeded && Date().timeIntervalSince(start) < 5, "timeout kills managed group")
        let cancelCommand = try command("/bin/sleep 30 & wait")
        let task = Task { try await runner.run(command: cancelCommand, context: context, outcome: nil, adbPath: "", workingDirectory: root) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let cancelled = try await task.value
        check(cancelled.cancelled && !cancelled.succeeded, "cancellation result")
        let childScript = root.appendingPathComponent("grace-child.zsh")
        let cleanupMarker = root.appendingPathComponent("child-cleaned")
        let childReady = root.appendingPathComponent("child-ready")
        try """
        trap '/bin/sleep 0.5; print cleaned > "$1"; exit 0' TERM
        print ready > "$2"
        while true; do /bin/sleep 1; done
        """.write(to: childScript, atomically: true, encoding: .utf8)
        let grace = try command("/bin/zsh -f \"$1\" \"$2\" \"$3\" & wait",
                                arguments: [childScript.path, cleanupMarker.path, childReady.path])
        let graceful = Task { try await runner.run(command: grace, context: context, outcome: nil, adbPath: "", workingDirectory: root) }
        for _ in 0..<300 where !FileManager.default.fileExists(atPath: childReady.path) { try await Task.sleep(for: .milliseconds(10)) }
        check(FileManager.default.fileExists(atPath: childReady.path), "child installed TERM cleanup")
        graceful.cancel()
        let graceResult = try await graceful.value
        check(graceResult.cancelled && (try? String(contentsOf: cleanupMarker, encoding: .utf8)) == "cleaned\n",
              "child receives full TERM grace after leader exits")
        let detached = try command("/bin/sleep 30 & print done")
        let detachedResult = try await runner.run(command: detached, context: context, outcome: nil, adbPath: "", workingDirectory: root)
        check(detachedResult.succeeded && detachedResult.stdout == "done\n", "orphan pipe holders reaped")
        let suite = "MAAHookTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HookSettingsStore(defaults: defaults)
        check(!store.configuration.enabled && store.configuration.before == nil, "defaults disabled")
        store.configuration = HookConfiguration(enabled: true, before: cmd, after: fail, timeoutSeconds: 42)
        check(HookSettingsStore(defaults: defaults).configuration == store.configuration, "settings roundtrip")
        print("RunHookTests: \(checks) assertions passed")
    }
}

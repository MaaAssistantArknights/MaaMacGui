import AppKit
import Carbon

@main struct HotkeyTests {
    @MainActor static func main() async throws {
        let suite = "MAAHotkeyTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { for name in [suite, suite + "Second", suite + "Third"] { defaults.removePersistentDomain(forName: name) } }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let service = GlobalHotkeyService(defaults: defaults)
        defer { service.shutdown() }
        let chordA = HotkeyChord(keyCode: 32, modifiers: UInt32(cmdKey | controlKey | shiftKey))
        let chordB = HotkeyChord(keyCode: 34, modifiers: UInt32(cmdKey | controlKey | shiftKey))
        if CommandLine.arguments.count > 1 {
            let chord = CommandLine.arguments[1] == "holdB" ? chordB : chordA
            let success = service.save(HotkeyConfiguration(enabled: true, start: chord))
            print(success ? "READY" : "FAIL")
            fflush(stdout)
            if success { _ = readLine() }
            return
        }
        var count = 0
        func check(_ condition: Bool, _ message: String) {
            count += 1
            if !condition { fatalError(message) }
        }
        check(!service.configuration.enabled && service.configuration.start == nil && service.configuration.stop == nil, "default no bindings")
        check(chordA.isValid, "valid command/control chord")
        check(!HotkeyChord(keyCode: 32, modifiers: UInt32(shiftKey)).isValid, "reject shift only")
        check(!HotkeyChord(keyCode: 55, modifiers: UInt32(cmdKey)).isValid, "reject modifier key")
        check(!HotkeyChord(keyCode: 128, modifiers: UInt32(controlKey)).isValid, "key code range")
        check(!HotkeyConfiguration(enabled: true, start: chordA, stop: chordA).isValid, "duplicate commands rejected")
        let encoded = try JSONEncoder().encode(HotkeyConfiguration(enabled: true, start: chordA, stop: chordB))
        check(try JSONDecoder().decode(HotkeyConfiguration.self, from: encoded) == HotkeyConfiguration(enabled: true, start: chordA, stop: chordB), "roundtrip")
        check(!chordA.displayName.isEmpty, "current keyboard layout display")
        let child = Process()
        child.executableURL = URL(filePath: CommandLine.arguments[0])
        child.arguments = ["holdB"]
        let output = Pipe(), input = Pipe()
        child.standardOutput = output; child.standardInput = input
        try child.run()
        let ready = output.fileHandleForReading.readData(ofLength: 6)
        check(String(decoding: ready, as: UTF8.self).hasPrefix("READY"), "second instance owns chord")
        check(service.save(HotkeyConfiguration(enabled: true, start: chordA)), "native registration")
        var delivered = 0
        service.command = { _ in delivered += 1; return true }
        service.handleHotkeyEvent(1, pressed: true)
        service.handleHotkeyEvent(1, pressed: true)
        for _ in 0..<20 { await Task.yield() }
        check(delivered == 1, "held key repeats suppressed")
        service.handleHotkeyEvent(1, pressed: false)
        service.handleHotkeyEvent(1, pressed: true)
        for _ in 0..<20 { await Task.yield() }
        check(delivered == 2, "release allows another command")
        service.handleHotkeyEvent(1, pressed: false)
        check(!service.save(HotkeyConfiguration(enabled: true, start: chordB)), "cross-process exclusive conflict visible")
        check(service.errorMessage != nil && service.configuration.start == chordA, "failed save preserves old configuration")
        let second = GlobalHotkeyService(defaults: UserDefaults(suiteName: suite + "Second")!)
        check(!second.save(HotkeyConfiguration(enabled: true, start: chordA)), "old registration restored after conflict")
        second.shutdown()
        input.fileHandleForWriting.write(Data("exit\n".utf8))
        child.waitUntilExit()
        check(child.terminationStatus == 0, "other app unregisters")
        check(service.save(HotkeyConfiguration(enabled: true, start: chordB)), "registration succeeds after owner exit")
        check(GlobalHotkeyService(defaults: defaults).configuration.start == chordB, "saved preference restored")
        check(service.save(HotkeyConfiguration(enabled: true, start: chordA, stop: chordB)), "both commands registered")
        var dispatched = [HotkeyCommand]()
        service.command = { command in
            dispatched.append(command)
            if command == .start { try? await Task.sleep(for: .milliseconds(200)) }
            return true
        }
        service.handleHotkeyEvent(1, pressed: true)
        for _ in 0..<20 { await Task.yield() }
        service.handleHotkeyEvent(2, pressed: true)
        service.handleHotkeyEvent(2, pressed: true)
        for _ in 0..<20 { await Task.yield() }
        check(dispatched == [.start, .stop], "stop reaches coordinator while start awaits preparation; repeated stop suppressed")
        service.handleHotkeyEvent(1, pressed: false)
        service.handleHotkeyEvent(2, pressed: false)
        try await Task.sleep(for: .milliseconds(250))
        service.beginRecording()
        check(service.isRecording, "recording state")
        let third = GlobalHotkeyService(defaults: UserDefaults(suiteName: suite + "Third")!)
        check(third.save(HotkeyConfiguration(enabled: true, start: chordB)), "recording unregisters shortcut")
        third.shutdown()
        service.endRecording()
        check(!service.isRecording, "recording end")
        check(service.save(HotkeyConfiguration()), "clear disable unregister")
        check(HotkeyChord(keyCode: 12, modifiers: UInt32(cmdKey)).isSystemReserved, "system quit chord reserved")
        check(!HotkeyChord(keyCode: 12, modifiers: UInt32(cmdKey | controlKey | shiftKey)).isSystemReserved, "decorated quit chord allowed")
        check(!service.save(HotkeyConfiguration(enabled: true, start: HotkeyChord(keyCode: 49, modifiers: UInt32(cmdKey)))), "reserved space chord rejected")
        check(!service.configuration.enabled && service.errorMessage != nil, "reserved rejection keeps current bindings")
        check(HotkeyChord(keyCode: 8, modifiers: UInt32(cmdKey)).isSystemReserved, "bare copy chord reserved")
        check(HotkeyChord(keyCode: 1, modifiers: UInt32(cmdKey)).isSystemReserved, "bare save chord reserved")
        check(!HotkeyChord(keyCode: 8, modifiers: UInt32(cmdKey | optionKey)).isSystemReserved, "decorated copy chord allowed")
        check(HotkeyChord(keyCode: 124, modifiers: UInt32(controlKey)).isSystemReserved, "bare control arrow reserved")
        check(!HotkeyChord(keyCode: 124, modifiers: UInt32(controlKey | shiftKey)).isSystemReserved, "decorated control arrow allowed")
        check(HotkeyChord(keyCode: 12, modifiers: UInt32(cmdKey | controlKey)).isSystemReserved, "lock screen chord reserved")
        check(HotkeyChord(keyCode: 0, modifiers: UInt32(cmdKey | controlKey)).isSystemReserved, "AZERTY lock screen chord reserved")
        check(HotkeyChord(keyCode: 3, modifiers: UInt32(cmdKey | controlKey)).isSystemReserved, "full screen chord reserved")
        check(!HotkeyChord(keyCode: 3, modifiers: UInt32(cmdKey | controlKey | optionKey)).isSystemReserved, "decorated full screen chord allowed")
        check(HotkeyChord(keyCode: 4, modifiers: UInt32(cmdKey | optionKey)).isSystemReserved, "hide others chord reserved")
        check(HotkeyChord(keyCode: 2, modifiers: UInt32(cmdKey | optionKey)).isSystemReserved, "dock hide/show chord reserved")
        check(HotkeyChord(keyCode: 43, modifiers: UInt32(cmdKey)).isSystemReserved, "settings chord reserved")
        check(!HotkeyChord(keyCode: 43, modifiers: UInt32(cmdKey | optionKey)).isSystemReserved, "decorated settings chord allowed")
        check(HotkeyChord(keyCode: 16, modifiers: UInt32(cmdKey)).isSystemReserved, "QWERTZ undo chord reserved")
        check(HotkeyChord(keyCode: 41, modifiers: UInt32(cmdKey)).isSystemReserved, "AZERTY minimize chord reserved")
        check(!service.save(HotkeyConfiguration(enabled: true, start: HotkeyChord(keyCode: 8, modifiers: UInt32(cmdKey)))), "reserved edit chord rejected")
        check(!service.configuration.enabled, "edit chord rejection keeps current bindings")
        print("HotkeyTests: \(count) assertions passed; exclusive native conflict used two processes")
    }
}

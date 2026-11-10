import AppKit
import Carbon

struct HotkeyChord: Codable, Equatable, Hashable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let allowedModifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)
    var isValid: Bool {
        keyCode < 128 && modifiers & ~Self.allowedModifiers == 0
            && modifiers & UInt32(cmdKey | controlKey) != 0
            && ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
    }

    /// Chords whose exclusive registration would swallow an OS-wide shortcut:
    /// quit/close/hide/minimize and the universal edit commands under bare ⌘
    /// (⌘Q/⌘W/⌘H/⌘M, ⌘A/⌘S/⌘Z/⌘X/⌘C/⌘V), Spaces/Mission Control/App Exposé
    /// under bare ⌃ arrows, lock screen (⌃⌘Q), Enter Full Screen (⌃⌘F),
    /// Hide Others and Dock
    /// hide/show (⌘⌥H/⌘⌥D), the universal settings chord (⌘,), the
    /// input-source and emoji panels (Space under ⌘/⌃), and the screenshot
    /// range (⌘⇧3…6). Decorated variants are not OS defaults and stay free.
    /// Key codes are ANSI positions and deliberately include the neighbors
    /// of Q/Z/M so QWERTZ ⌘Z (16) and AZERTY ⌘M (41) / ⌃⌘Q (0) are covered.
    var isSystemReserved: Bool {
        let command = modifiers & UInt32(cmdKey) != 0
        let control = modifiers & UInt32(controlKey) != 0
        let option = modifiers & UInt32(optionKey) != 0
        let shift = modifiers & UInt32(shiftKey) != 0
        if keyCode == 49 { return command || control }
        if (20...23).contains(keyCode) { return command && shift && !control && !option }
        if (123...126).contains(keyCode) { return control && !command && !option && !shift }
        if [0, 3, 12].contains(keyCode) && command && control && !option && !shift { return true }
        if [2, 4].contains(keyCode) && command && option && !control && !shift { return true }
        return command && !control && !option && !shift
            && [0, 1, 4, 6, 7, 8, 9, 12, 13, 16, 41, 43, 46].contains(keyCode)
    }

    init(keyCode: UInt32, modifiers: UInt32) { self.keyCode = keyCode; self.modifiers = modifiers }
    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        modifiers = (flags.contains(.command) ? UInt32(cmdKey) : 0)
            | (flags.contains(.control) ? UInt32(controlKey) : 0)
            | (flags.contains(.option) ? UInt32(optionKey) : 0)
            | (flags.contains(.shift) ? UInt32(shiftKey) : 0)
    }

    var displayName: String {
        let prefix = (modifiers & UInt32(controlKey) != 0 ? "⌃" : "")
            + (modifiers & UInt32(optionKey) != 0 ? "⌥" : "")
            + (modifiers & UInt32(shiftKey) != 0 ? "⇧" : "")
            + (modifiers & UInt32(cmdKey) != 0 ? "⌘" : "")
        let special: [UInt32: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        if let name = special[keyCode] { return prefix + name }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return prefix + "[\(keyCode)]" }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        let layout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 8)
        var length = 0
        let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                                    chars.count, &length, &chars)
        guard status == noErr, length > 0 else { return prefix + "[\(keyCode)]" }
        return prefix + String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

struct HotkeyConfiguration: Codable, Equatable {
    var enabled = false
    var start: HotkeyChord?
    var stop: HotkeyChord?
    var isValid: Bool {
        (start?.isValid ?? true) && (stop?.isValid ?? true) && (start == nil || start != stop)
    }

    var hasReservedChord: Bool {
        (start?.isSystemReserved ?? false) || (stop?.isSystemReserved ?? false)
    }
}

enum HotkeyCommand: UInt32 { case start = 1, stop = 2 }

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
}

enum HotkeyCommand: UInt32 { case start = 1, stop = 2 }

import AppKit
import Carbon
import Combine

/// Exclusive registration needs no global keyboard monitor or Input Monitoring permission.
@MainActor
final class GlobalHotkeyService: ObservableObject {
    @Published private(set) var configuration: HotkeyConfiguration
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRecording = false
    var command: ((HotkeyCommand) async -> Bool)?
    private let defaults: UserDefaults
    private var references: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var held = Set<UInt32>()
    private var dispatching = Set<UInt32>()
    private var activeConfiguration: HotkeyConfiguration?
    private static let signature: OSType = 0x4D41414B

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        configuration = defaults.data(forKey: "MAAGlobalHotkeys")
            .flatMap { try? JSONDecoder().decode(HotkeyConfiguration.self, from: $0) } ?? HotkeyConfiguration()
        installHandler()
        if configuration.enabled { _ = register(configuration) }
    }

    deinit { MainActor.assumeIsolated { shutdown() } }

    private func installHandler() {
        var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                      EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let event, let pointer else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x4D41414B else { return OSStatus(eventNotHandledErr) }
            let service = Unmanaged<GlobalHotkeyService>.fromOpaque(pointer).takeUnretainedValue()
            let kind = GetEventKind(event)
            Task { @MainActor [weak service] in service?.handleHotkeyEvent(id.id, pressed: kind == UInt32(kEventHotKeyPressed)) }
            return noErr
        }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        if result != noErr { errorMessage = String(localized: "无法安装全局热键处理器") + " (\(result))" }
    }

    @discardableResult
    func save(_ candidate: HotkeyConfiguration) -> Bool {
        guard !isRecording else { return false }
        guard candidate.isValid else {
            errorMessage = String(localized: "热键须包含 Command 或 Control，开始和停止不能使用同一组合")
            return false
        }
        let previous = configuration
        unregister()
        if candidate.enabled, !register(candidate) {
            let failure = errorMessage
            if previous.enabled, !register(previous) {
                errorMessage = String(localized: "新热键注册失败且旧绑定未能恢复；当前未绑定，请重试")
            } else {
                errorMessage = failure
            }
            return false
        }
        configuration = candidate
        if let data = try? JSONEncoder().encode(candidate) { defaults.set(data, forKey: "MAAGlobalHotkeys") }
        errorMessage = nil
        return true
    }

    func beginRecording() {
        isRecording = true
        unregister()
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        if configuration.enabled { _ = register(configuration) }
    }

    func shutdown() {
        unregister()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
    }

    private func register(_ value: HotkeyConfiguration) -> Bool {
        guard eventHandler != nil, value.isValid else {
            errorMessage = String(localized: "全局热键配置无效或系统处理器不可用")
            return false
        }
        for (command, chord) in [(HotkeyCommand.start, value.start), (.stop, value.stop)] {
            guard let chord else { continue }
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(chord.keyCode, chord.modifiers,
                                             EventHotKeyID(signature: Self.signature, id: command.rawValue),
                                             GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
            guard status == noErr, let reference else {
                unregister()
                errorMessage = String(localized: "热键注册失败，组合可能已被系统或其他应用占用") + " (\(status))"
                return false
            }
            references.append(reference)
        }
        activeConfiguration = value
        return true
    }

    private func unregister() {
        for reference in references { UnregisterEventHotKey(reference) }
        references.removeAll()
        held.removeAll()
        activeConfiguration = nil
    }

    func handleHotkeyEvent(_ id: UInt32, pressed: Bool) {
        guard !isRecording, activeConfiguration != nil else { return }
        if !pressed { held.remove(id); return }
        guard held.insert(id).inserted, !dispatching.contains(id), let action = HotkeyCommand(rawValue: id), let command else { return }
        dispatching.insert(id)
        Task { @MainActor [weak self] in
            let accepted = await command(action)
            self?.dispatching.remove(id)
            if accepted {
                NotificationCenter.default.post(name: Notification.Name("MAAHotkeyCommandAccepted"), object: nil,
                                                userInfo: ["command": action == .start ? "start" : "stop"])
            }
        }
    }
}

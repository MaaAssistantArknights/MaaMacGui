import SwiftUI
import AppKit
import Carbon

struct HotkeySettingsView: View {
    @ObservedObject var service: GlobalHotkeyService
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HotkeyConfiguration
    @State private var recording: HotkeyCommand?
    @State private var recordingError: String?
    @State private var layoutRevision = 0
    @State private var waitingForRelease = false
    @State private var releaseKeyCode: UInt16?

    init(service: GlobalHotkeyService) {
        self.service = service
        _draft = State(initialValue: service.configuration)
    }

    var body: some View {
        Form {
            Toggle("启用全局热键", isOn: $draft.enabled)
            Text("组合须包含 Command 或 Control。开始仅在空闲时执行；停止使用与任务按钮相同的入口。无需输入监控权限。")
                .font(.caption).foregroundStyle(.secondary)
            row(.start, title: "开始日常任务")
            row(.stop, title: "停止当前任务")
            if let recording {
                Text("按下组合键，Esc 取消").foregroundStyle(.secondary)
                HotkeyCapture { event in
                    if event.type == .keyUp {
                        if waitingForRelease, event.keyCode == releaseKeyCode { finishRecording() }
                        return
                    }
                    guard !waitingForRelease else { return }
                    if event.keyCode == 53 {
                        releaseKeyCode = event.keyCode
                        waitingForRelease = true
                        return
                    }
                    let chord = HotkeyChord(event: event)
                    guard chord.isValid else {
                        recordingError = String(localized: "热键须包含 Command 或 Control，开始和停止不能使用同一组合")
                        return
                    }
                    guard !chord.isSystemReserved else {
                        recordingError = String(localized: "该组合为系统保留或通用编辑快捷键（如 ⌘Q、⌘C、⌃→、⌘⇧4），不能注册为全局热键")
                        return
                    }
                    if recording == .start { draft.start = chord } else { draft.stop = chord }
                    recordingError = nil
                    // Resume registration only after the primary key is released;
                    // re-registering a saved chord while held could fire a task.
                    releaseKeyCode = event.keyCode
                    waitingForRelease = true
                }.frame(height: 32)
            }
            if let error = recordingError ?? service.errorMessage {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("取消") { finishRecording(); dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    if service.save(draft) { dismiss() }
                }.keyboardShortcut(.defaultAction).disabled(recording != nil)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 290)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String))) { _ in
            layoutRevision += 1
        }
        .onDisappear { if service.isRecording { service.endRecording() } }
        // A lost keyUp (focus moved away or app deactivated while the key was
        // held) must not wedge recording: recover shortly after.
        .task(id: waitingForRelease) {
            guard waitingForRelease else { return }
            try? await Task.sleep(for: .seconds(2))
            guard waitingForRelease else { return }
            finishRecording()
        }
    }

    private func row(_ command: HotkeyCommand, title: LocalizedStringKey) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text((command == .start ? draft.start : draft.stop)?.displayName ?? String(localized: "未绑定"))
                .id(layoutRevision).monospaced().accessibilityIdentifier(command == .start ? "hotkey.start.value" : "hotkey.stop.value")
            Button("录制") {
                recording = command
                waitingForRelease = false
                recordingError = nil
                service.beginRecording()
            }
            Button("清除热键") { if command == .start { draft.start = nil } else { draft.stop = nil } }
        }
    }

    private func finishRecording() {
        recording = nil
        waitingForRelease = false
        releaseKeyCode = nil
        if service.isRecording { service.endRecording() }
    }
}

private struct HotkeyCapture: NSViewRepresentable {
    let captured: (NSEvent) -> Void
    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.captured = captured
        return view
    }
    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.captured = captured
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView else { return }
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class CaptureView: NSView {
        var captured: ((NSEvent) -> Void)?
        private var keyUpMonitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let keyUpMonitor { NSEvent.removeMonitor(keyUpMonitor) }
            keyUpMonitor = nil
            guard window != nil else { return }
            // Command key equivalents do not reliably deliver keyUp to NSView.
            // This monitor sees only this app's events while this recorder owns focus.
            keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                guard let self, self.window?.firstResponder === self else { return event }
                self.captured?(event)
                return nil
            }
        }

        deinit {
            MainActor.assumeIsolated {
                if let keyUpMonitor { NSEvent.removeMonitor(keyUpMonitor) }
            }
        }

        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) { if !event.isARepeat { captured?(event) } }
        override func keyUp(with event: NSEvent) { captured?(event) }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if !event.isARepeat { captured?(event) }
            return true
        }
    }
}

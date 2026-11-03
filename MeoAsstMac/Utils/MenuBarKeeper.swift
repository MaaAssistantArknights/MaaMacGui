//
//  MenuBarKeeper.swift
//  MAA
//

import AppKit
import SwiftUI

/// 常驻菜单栏：开启后关闭主窗口只会将其隐藏，同时隐藏程序坞图标，需从菜单栏退出。
@MainActor final class MenuBarKeeper: NSObject {
    static let shared = MenuBarKeeper()
    static let enabledKey = "MAAKeepInMenuBar"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    private(set) var isMainWindowHidden = false

    private weak var mainWindow: NSWindow?
    private var delegateProxy: WindowDelegateProxy?
    // 不使用 SwiftUI 的 MenuBarExtra(isInserted:)，它会给状态栏图标加上 .removalAllowed，
    // 导致 Ice 等菜单栏管理工具无法移动该图标
    private var statusItem: NSStatusItem?

    override private init() {}

    func attach(mainWindow window: NSWindow) {
        guard window.delegate !== delegateProxy || mainWindow !== window else { return }

        let proxy = WindowDelegateProxy(forwardingTo: window.delegate) { [weak self] window in
            guard Self.isEnabled, let self else { return true }
            hideMainWindow(window)
            return false
        }
        window.delegate = proxy
        delegateProxy = proxy
        mainWindow = window
    }

    /// 根据设置添加或移除菜单栏图标；关闭设置时若主窗口处于隐藏状态则将其恢复。
    func update() {
        if Self.isEnabled {
            installStatusItem()
        } else {
            removeStatusItem()
            if isMainWindowHidden {
                showMainWindow()
            }
        }
    }

    @objc func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if let mainWindow {
            if mainWindow.isMiniaturized {
                mainWindow.deminiaturize(nil)
            }
            mainWindow.makeKeyAndOrderFront(nil)
        }
        isMainWindowHidden = false
    }

    private func hideMainWindow(_ window: NSWindow) {
        window.orderOut(nil)
        isMainWindowHidden = true
        NSApp.setActivationPolicy(.accessory)
    }

    private func installStatusItem() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.statusItemIcon
        item.button?.toolTip = "MAA"

        let menu = NSMenu()
        let showItem = NSMenuItem(
            title: String(localized: "显示 MAA"), action: #selector(showMainWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: String(localized: "退出 MAA"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
        item.menu = menu

        statusItem = item
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private static let statusItemIcon: NSImage = {
        let image = NSImage(named: NSImage.applicationIconName)?.copy() as? NSImage ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
}

/// 只拦截 `windowShouldClose(_:)`，其余回调全部转发给 SwiftUI 原本的窗口代理。
private final class WindowDelegateProxy: NSObject, NSWindowDelegate {
    private weak var target: NSWindowDelegate?
    private let shouldClose: @MainActor (NSWindow) -> Bool

    init(forwardingTo target: NSWindowDelegate?, shouldClose: @escaping @MainActor (NSWindow) -> Bool) {
        self.target = target
        self.shouldClose = shouldClose
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard shouldClose(sender) else { return false }
        return target?.windowShouldClose?(sender) ?? true
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (target?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let target, target.responds(to: aSelector) {
            return target
        }
        return super.forwardingTarget(for: aSelector)
    }
}

/// 获取 SwiftUI 视图所在的 `NSWindow`。
struct WindowAccessor: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        WindowReportingView(onWindow: onWindow)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowReportingView: NSView {
        let onWindow: @MainActor (NSWindow) -> Void

        init(onWindow: @escaping @MainActor (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // 等 SwiftUI 完成窗口配置（包括设置 delegate）后再接管
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window else { return }
                    self.onWindow(window)
                }
            }
        }
    }
}

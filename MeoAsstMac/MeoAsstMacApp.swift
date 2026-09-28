//
//  MeoAsstMacApp.swift
//  MeoAsstMac
//
//  Created by hguandl on 8/10/2022.
//

import Sparkle
import SwiftUI

@main
struct MeoAsstMacApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var appViewModel: MAAViewModel
    @State private var newViewModel: NewViewModel

    private let updaterController: SPUStandardUpdaterController
    private let updaterDelegate = MaaUpdaterDelegate()

    init() {
        let viewModel = MAAViewModel()
        let newModel = NewViewModel(parent: viewModel)
        _appViewModel = StateObject(wrappedValue: viewModel)
        _newViewModel = State(wrappedValue: newModel)
        #if DEBUG
        let isRelease = false
        #else
        let isRelease = true
        #endif
        updaterController = .init(startingUpdater: isRelease, updaterDelegate: updaterDelegate, userDriverDelegate: nil)
        appDelegate.beforeTermination = {
            await newModel.waitLogStoreToFinish()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appViewModel)
                .environment(newViewModel)
                .onAppear {
                    TaskTimerManager.shared.connectToModel(viewModel: appViewModel)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                OpenLogFileView()
            }
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            SidebarCommands()
            TaskCommands(viewModel: appViewModel)
        }

        Settings {
            TabView {
                ConnectionSettingsView()
                    .tabItem {
                        Label("连接设置", systemImage: "rectangle.connected.to.line.below")
                    }

                GameSettingsView()
                    .tabItem {
                        Label("游戏设置", systemImage: "gamecontroller")
                    }

                UpdaterSettingsView(updater: updaterController.updater)
                    .tabItem {
                        Label("更新设置", systemImage: "square.and.arrow.down")
                    }

                SystemSettingsView()
                    .tabItem {
                        Label("系统设置", systemImage: "wrench.adjustable")
                    }
            }
            .environmentObject(appViewModel)
            .frame(maxWidth: 360, minHeight: 240)
        }
    }
}

final class MaaUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    @AppStorage("MaaUseBetaChannel") private var useBetaChannel = false

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        if useBetaChannel {
            return Set(["beta"])
        } else {
            return Set()
        }
    }
}

private class AppDelegate: NSObject, NSApplicationDelegate {
    fileprivate var beforeTermination: (() async -> Void)?
    private var terminationTask: Task<Void, Never>?
    private var closeDelegate: WindowCloseDelegate?
    private var attachAttempts = 0

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 初始化通知中心（设置 delegate，应用活跃时抑制系统通知展示）。
        _ = MAANotificationCenter.shared
        // 仅当用户开启「任务通知提醒」时才惰性请求系统通知授权；
        // 该偏好默认开启，未写入 UserDefaults 时按开启处理，已拒绝授权则不再弹窗。
        let useNotification = UserDefaults.standard.object(forKey: "MAAUseNotification") as? Bool ?? true
        if useNotification {
            MAANotificationCenter.shared.requestAuthorizationIfNeeded()
        }
        // 等 SwiftUI 创建好主窗口后再接管其关闭事件
        installMainWindowCloseDelegate()
    }

    /// 接管主窗口的关闭事件：关闭改为「隐藏 App」（保留在 Dock），窗口并不销毁。
    /// 这样关窗后再点 Dock 重开，窗口是原封不动的同一个，状态与已加载的资源都保留。
    private func installMainWindowCloseDelegate() {
        guard closeDelegate == nil else { return }

        // 窗口由 SwiftUI 在启动后创建，需等它出现且已设置好自身 delegate 再接管
        guard let window = NSApp.windows.first, window.delegate != nil else {
            attachAttempts += 1
            if attachAttempts < 50 {
                DispatchQueue.main.async { [weak self] in
                    self?.installMainWindowCloseDelegate()
                }
            }
            return
        }

        let delegate = WindowCloseDelegate()
        delegate.originalDelegate = window.delegate
        window.delegate = delegate
        window.isReleasedWhenClosed = false
        closeDelegate = delegate
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let beforeTermination else { return .terminateNow }
        if terminationTask != nil { return .terminateLater }

        terminationTask = Task {
            await beforeTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }

        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 关闭窗口（⌘W）不退出；窗口关闭会被 WindowCloseDelegate 拦截为「隐藏」，
        // 这里返回 false 作为兜底：即便窗口真的被关闭，App 也仅留在 Dock 而非退出。
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 点击 Dock 图标：取消隐藏 App 并只重新显示主窗口（窗口此前只是被隐藏，并未销毁）。
        // 仅恢复 delegate 为 WindowCloseDelegate 的主窗口，避免把「设置」等辅助窗口一并带出。
        if !flag {
            NSApp.unhide(nil)
            if let mainWindow = sender.windows.first(where: { $0.delegate is WindowCloseDelegate }) {
                mainWindow.makeKeyAndOrderFront(self)
            }
        }
        return true
    }
}

/// 主窗口关闭代理：拦截 windowShouldClose 改为隐藏整个 App，
/// 并把自身未处理的 delegate 消息转发给 SwiftUI 原有的 delegate，避免破坏 WindowGroup 生命周期。
private class WindowCloseDelegate: NSObject, NSWindowDelegate {
    var originalDelegate: NSWindowDelegate?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.hide(nil)
        return false
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return originalDelegate?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        originalDelegate
    }
}

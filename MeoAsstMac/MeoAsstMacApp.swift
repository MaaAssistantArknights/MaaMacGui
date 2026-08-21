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
        viewModel.logStore = newModel
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

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
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
        true
    }
}

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
    @StateObject private var appViewModel = MAAViewModel()
    
    private var notificationManager: DingTalkNotificationManager

    private let updaterController: SPUStandardUpdaterController
    private let updaterDelegate = MaaUpdaterDelegate()

    init() {
        #if DEBUG
        let isRelease = false
        #else
        let isRelease = true
        #endif
        updaterController = .init(startingUpdater: isRelease, updaterDelegate: updaterDelegate, userDriverDelegate: nil)
        
        let viewModel = MAAViewModel()
        let manager = DingTalkNotificationManager(viewModel: viewModel)
        self.notificationManager = manager
        
        // 立即开始监听日志
        self.notificationManager.startObserving()

        print("App Started: DingTalkNotificationManager has been initialized and is observing.")
            
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appViewModel)
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
                
                RemoteSettingsView()
                    .tabItem{
                        Label("通知设置", systemImage: "ellipsis.message")
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
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

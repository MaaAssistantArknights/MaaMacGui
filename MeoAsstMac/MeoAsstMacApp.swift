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

    private let updaterController: SPUStandardUpdaterController
    private let updaterDelegate = MaaUpdaterDelegate()

    init() {
        updaterController = .init(startingUpdater: true, updaterDelegate: updaterDelegate, userDriverDelegate: nil)
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
                        Label(NSLocalizedString("连接设置", comment: ""), systemImage: "rectangle.connected.to.line.below")
                    }

                GameSettingsView()
                    .tabItem {
                        Label(NSLocalizedString("游戏设置", comment: ""), systemImage: "gamecontroller")
                    }

                UpdaterSettingsView(updater: updaterController.updater)
                    .tabItem {
                        Label(NSLocalizedString("更新设置", comment: ""), systemImage: "square.and.arrow.down")
                    }

                SystemSettingsView()
                    .tabItem {
                        Label(NSLocalizedString("系统设置", comment: ""), systemImage: "wrench.adjustable")
                    }
            }
            .environmentObject(appViewModel)
            .frame(minWidth: 320, minHeight: 240)
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

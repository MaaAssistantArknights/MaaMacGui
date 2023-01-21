//
//  ContentView.swift
//  MeoAsstMac
//
//  Created by hguandl on 8/10/2022.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appDelegate: AppDelegate

    @State private var tab = 1

    var body: some View {
        TabView(selection: $tab) {
            ManageView().tabItem { Text("一键长草") }.tag(1)
            AutoPilotView().tabItem { Text("自动战斗") }.tag(2)
            Text("敬请期待").tabItem { Text("公招识别") }.tag(3)
            Text("敬请期待").tabItem { Text("仓库识别 beta") }.tag(4)
            SettingsView().tabItem { Text("设置") }.tag(5)
        }
        .padding()
        .sheet(isPresented: $appDelegate.extractingResource, content: {
            ProgressView("解压数据中").padding()
        })
        .onAppear {
            Task {
                await appDelegate.initializeMaa()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            Task {
                await appDelegate.cleanupMaa()
            }
        }
    }
}

// Removes background from List in SwiftUI
extension NSTableView {
    override open func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        backgroundColor = NSColor.clear
        if let esv = enclosingScrollView {
            esv.drawsBackground = false
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppDelegate())
    }
}

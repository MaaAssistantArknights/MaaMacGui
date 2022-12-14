//
//  SettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationView {
            List {
                settingsGroup1()
                settingsGroup2()
                Divider()
                settingsGroup3()
                settingsGroup4()
            }
        }
    }

    private func settingsGroup1() -> some View {
        Group {
            NavigationLink("基建设置") {
                InfrastSettingsView()
            }
            NavigationLink("肉鸽设置") {
                RoguelikeSettingsView()
            }
            NavigationLink("自动公招") {
                RecruitSettingsView()
            }
            NavigationLink("信用商店") {
                MallSettingsView()
            }
        }
    }

    private func settingsGroup2() -> some View {
        Group {
            NavigationLink("理智设置") {
                Text("敬请期待")
            }
        }
    }

    private func settingsGroup3() -> some View {
        Group {
            NavigationLink("连接设置") {
                ConnectionSettingsView()
            }
            NavigationLink("界面设置") {
                Text("敬请期待")
            }
            NavigationLink("启动设置") {
                StartupSettingsView()
            }
        }
    }

    private func settingsGroup4() -> some View {
        Group {
            NavigationLink("软件更新") {
                Text("敬请期待")
            }
            NavigationLink("关于我们") {
                Text("敬请期待")
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}

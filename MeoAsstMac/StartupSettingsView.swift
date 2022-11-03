//
//  StartupSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 30/10/2022.
//

import SwiftUI

struct StartupSettingsView: View {
    @EnvironmentObject private var appDelegate: AppDelegate

    @State private var showingAlert = false

    var body: some View {
        VStack {
            Picker("客户端版本", selection: $appDelegate.clientChannel) {
                ForEach(MaaClientChannel.allCases, id: \.rawValue) { channel in
                    Text("\(channel.description)").tag(channel)
                }
            }
        }
        .padding(.horizontal)
        .alert("已切换客户端版本", isPresented: $showingAlert, actions: {
            Button("好") {}
        }, message: {
            Text("请手动重启App以加载资源文件。")
        })
        .onChange(of: appDelegate.clientChannel) { _ in
            showingAlert = true
        }
    }
}

struct StartupSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        StartupSettingsView()
            .environmentObject(AppDelegate())
    }
}

enum MaaClientChannel: String, Codable, CaseIterable, CustomStringConvertible {
    case `default`
    case Official
    case Bilibili
    case YoStarEN
    case YoStarJP
    case YoStarKR
    case txwy

    var description: String {
        switch self {
        case .default:
            return "不选择"
        case .Official:
            return "国服"
        case .Bilibili:
            return "Bilibili服"
        case .YoStarEN:
            return "国际服（YoStarEN）"
        case .YoStarJP:
            return "日服（YoStarJP）"
        case .YoStarKR:
            return "韩服（YoStarKR）"
        case .txwy:
            return "繁中服（txwy）"
        }
    }
    
    var isGlobal: Bool {
        switch self {
        case .default:
            return false
        case .Official:
            return false
        case .Bilibili:
            return false
        case .YoStarEN:
            return true
        case .YoStarJP:
            return true
        case .YoStarKR:
            return true
        case .txwy:
            return true
        }
    }
}

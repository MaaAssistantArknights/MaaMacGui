//
//  RoguelikeSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct RoguelikeSettingsView: View {
    @EnvironmentObject private var appDelegate: AppDelegate
    
    var body: some View {
        VStack(spacing: 15) {
            Picker("肉鸽主题", selection: $appDelegate.rougelikeTheme) {
                Text("傀影").tag(0)
                Text("水月").tag(1)
            }
            
            Picker("策略", selection: $appDelegate.roguelikeMode) {
                Text("刷蜡烛，尽可能稳定地打更多层数").tag(0)
                Text("刷源石锭，第一层投资完就退出").tag(1)
            }
            
            HStack {
                Text("开始探索N次后停止任务")
                TextField("", value: $appDelegate.roguelikeTimesLimit, format: .number)
            }
            
            Toggle("投资源石锭", isOn: $appDelegate.roguelikeGoldEnabled)
            
            HStack {
                Text("投资N个源石锭后停止任务")
                TextField("", value: $appDelegate.roguelikeGoldLimit, format: .number)
            }
            
            Toggle("储备源石锭达到上限时停止", isOn: $appDelegate.roguelikeStopWhenGoldLimit)
            
            Picker("开局分队", selection: $appDelegate.roguelikeStartingSquad) {
                ForEach(roguelikeSquads, id: \.self) { squad in
                    Text(squad).tag(squad)
                }
            }
            
            Picker("开局职业组", selection: $appDelegate.roguelikeStartingRoles) {
                ForEach(roguelikeRoles, id: \.self) { role in
                    Text(role).tag(role)
                }
            }
            
            HStack {
                Text("开局干员（单个）")
                TextField("", text: $appDelegate.roguelikeCoreChar)
            }
        }
        .padding()
        .onChange(of: appDelegate.rougelikeTheme) { newValue in
            appDelegate.switchRoguelikeTheme(to: newValue)
        }
    }
}

struct RoguelikeSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        RoguelikeSettingsView()
            .environmentObject(AppDelegate())
    }
}

private let roguelikeSquads = [
    "心胜于物分队", "物尽其用分队", "以人为本分队",
    "指挥分队", "集群分队", "后勤分队", "矛头分队",
    "突击战术分队", "堡垒战术分队", "远程战术分队", "破坏战术分队",
    "研究分队", "高规格分队"
]

private let roguelikeRoles = ["先手必胜", "稳扎稳打", "取长补短", "随心所欲"]

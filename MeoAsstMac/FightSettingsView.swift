//
//  FightSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct FightSettingsView: View {
    @EnvironmentObject private var appDelegate: AppDelegate

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Toggle("吃理智药", isOn: $appDelegate.useSanityPotion).frame(width: 80, alignment: .leading)
                TextField("", value: $appDelegate.sanityPotion, format: .number).frame(width: 80)
            }
            HStack {
                Toggle("吃源石*", isOn: $appDelegate.useOriginitePrime).frame(width: 80, alignment: .leading)
                TextField("", value: $appDelegate.originitePrime, format: .number).frame(width: 80)
            }
            HStack {
                Toggle("指定次数*", isOn: $appDelegate.limitPerformBattles).frame(width: 80, alignment: .leading)
                TextField("", value: $appDelegate.performBattles, format: .number).frame(width: 80)
            }.disabled(true)
            Toggle(isOn: .constant(false)) {
                Picker("指定材料", selection: .constant(0)) {}
            }
            .disabled(true)
            Picker("关卡选择", selection: $appDelegate.stageSelect) {
                Text("当前/上次").tag("")
                Text("1-7").tag("1-7")
                Text("CE-6").tag("CE-6")
                Text("AP-5").tag("AP-5")
                Text("CA-5").tag("CA-5")
                Text("LS-6").tag("LS-5")
                Text("剿灭模式").tag("Annihilation")
            }
            Picker("剩余理智", selection: $appDelegate.remainingSanityStage) {
                Text("不选择").tag("")
                Text("1-7")
                Text("龙门币 CE-6").tag("CE-6")
                Text("红票 AP-5").tag("AP-5")
                Text("技能书 CA-5").tag("CA-5")
                Text("经验书 LS-6").tag("LS-5")
                Text("剿灭模式").tag("Annihilation")
            }
            Text("标注 * 的选项重启后不保存").font(.footnote)
        }
    }
}

struct FightSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        FightSettingsView()
            .environmentObject(AppDelegate())
    }
}

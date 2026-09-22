//
//  ThirdPartyServiceSettingsView.swift
//  MAA
//
//  Created by zhangweijian on 22/9/2026.
//

import SwiftUI

struct ThirdPartyServiceSettingsView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("一图流 OpenAPI Token")
                TextField("", text: $viewModel.yituliuOpenApiToken)
            }

            Toggle(isOn: $viewModel.enableOperBoxYituliuApi) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("干员识别从一图流获取")
                    Text(
                        "开启后「更新数据」的干员识别不再连接模拟器截图识别，改为直接读取 Token 对应的一图流练度数据。一图流保存的是练度快照，需先在一图流网站上传过干员数据。相比本地截图识别可额外获取技能等级、专精等级与模组信息。Token 在一图流「个人中心」的「第三方 API Token」中生成，为保护账号数据请仅使用只读 Token。"
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

struct ThirdPartyServiceSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ThirdPartyServiceSettingsView()
            .environmentObject(MAAViewModel())
    }
}

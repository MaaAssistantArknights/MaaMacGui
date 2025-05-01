//
//  UtilityDetail.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import SwiftUI

struct UtilityDetail: View {
    let entry: UtilityEntry?

    var body: some View {
        VStack {
            switch entry {
            case .recruit:
                RecruitView()
            case .depot:
                DepotView()
            case .oper:
                OperBoxView()
            case .video:
                VideoRecogView()
            case .gacha:
                GachaView()
            case .minigame:
                Text("争锋频道：青草城")
                    .font(.title2)
                    .bold()
                    .padding()
                Text("手动跳过教程对话，然后可以直接退出")
                Text("在活动主界面（右下角有“加入赛事”处）开始任务。")
                Text("跟着鸭总喝口汤")
                    .padding()
                    .foregroundStyle(.secondary)
            case .none:
                Text("请选择识别项目")
            }
        }
        .padding()
        .toolbar {
            Text(entry?.description ?? " ")
                .font(.headline)
        }
    }
}

struct UtilityDetail_Previews: PreviewProvider {
    static var previews: some View {
        UtilityDetail(entry: .recruit)
            .environmentObject(MAAViewModel())
    }
}

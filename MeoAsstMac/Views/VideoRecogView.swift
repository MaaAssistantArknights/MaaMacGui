//
//  VideoRecogView.swift
//  MAA
//
//  Created by hguandl on 25/4/2023.
//

import SwiftUI

struct VideoRecogView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("请打开“自动战斗”页，将攻略视频文件拖入作业列表即可。")
            Text("需要视频分辨率为 16:9，且无黑边、模拟器边框、异形屏矫正等干扰因素。")
        }
    }
}

struct VideoRecogView_Previews: PreviewProvider {
    static var previews: some View {
        VideoRecogView()
    }
}

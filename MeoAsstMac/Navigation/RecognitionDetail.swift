//
//  RecognitionDetail.swift
//  MAA
//
//  Created by hguandl on 19/4/2023.
//

import SwiftUI

struct RecognitionDetail: View {
    let entry: RecognitionEntry?

    var body: some View {
        VStack {
            switch entry {
                case .recruit:
                    RecruitView()
                case .depot:
                    DepotView()
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

struct RecognitionDetail_Previews: PreviewProvider {
    static var previews: some View {
        RecognitionDetail(entry: .recruit)
            .environmentObject(MAAViewModel())
    }
}

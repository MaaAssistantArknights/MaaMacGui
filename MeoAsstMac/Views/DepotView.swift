//
//  DepotView.swift
//  MAA
//
//  Created by hguandl on 18/4/2023.
//

import SwiftUI

struct DepotView: View {
    @EnvironmentObject private var viewModel: MAAViewModel

    var body: some View {
        List(viewModel.depot?.contents ?? [], id: \.self) { content in
            Text(content)
        }
        .padding()
        .animation(.default, value: viewModel.depot?.contents)
    }
}

struct DepotView_Previews: PreviewProvider {
    static var previews: some View {
        DepotView()
            .environmentObject(MAAViewModel())
    }
}

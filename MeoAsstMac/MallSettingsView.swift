//
//  MallSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct MallSettingsView: View {
    @EnvironmentObject private var appDelegate: AppDelegate

    var body: some View {
        VStack() {
            HStack(spacing: 50) {
                Spacer()
                Toggle("信用购物", isOn: $appDelegate.socialPtShop)
                Toggle("信用溢出时无视黑名单", isOn: $appDelegate.forceShoppingIfCreditFull)
                Spacer()
            }
            .padding(.horizontal)
            Form {
                TextField("黑名单 子串即可 分号分隔", text: $appDelegate.highPriority)
                TextField("优先购买 子串即可 分号分隔", text: $appDelegate.blacklist)
            }
            .padding(.top)
            .padding(.horizontal)
        }
    }
}

struct MallSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        MallSettingsView()
    }
}

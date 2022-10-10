//
//  ConnectionSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 10/10/2022.
//

import SwiftUI

struct ConnectionSettingsView: View {
    @EnvironmentObject private var appDelegate: AppDelegate
    
    var body: some View {
        VStack {
            HStack {
                Text("ADB地址")
                TextField("", text: $appDelegate.connectionAddress)
            }
        }
        .padding(.horizontal)
    }
}

struct ConnectionSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ConnectionSettingsView()
    }
}

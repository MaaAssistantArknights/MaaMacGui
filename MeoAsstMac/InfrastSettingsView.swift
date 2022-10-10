//
//  InfrastSettingsView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct InfrastSettingsView: View {
    @EnvironmentObject private var appDelegate: AppDelegate

    @Environment(\.defaultMinListRowHeight) private var rowHeight

    var body: some View {
        VStack {
            HStack {
                List {
                    ForEach(appDelegate.facilities, id: \.name) { facility in
                        Toggle(facility.description, isOn: binding(for: facility))
                    }
                    .onMove { source, destination in
                        appDelegate.facilities.move(fromOffsets: source, toOffset: destination)
                    }
                }
                .frame(height: 12 * rowHeight)

                Form {
                    Section {
                        Text("无人机用途")
                        Picker("", selection: $appDelegate.droneUsage) {
                            ForEach(DroneUsage.allCases, id: \.self) { usage in
                                Text(usage.description).tag(usage.rawValue)
                            }
                        }
                        .padding(.bottom)
                    }
                    Divider()
                    Section {
                        Text("基建工作心情阈值: \(appDelegate.dormThreshold * 100, specifier: "%.0f")%")
                        Slider(value: $appDelegate.dormThreshold, in: 0 ... 1)
                    }
                    Divider()
                    Section {
                        Toggle("宿舍空余位置蹭信赖", isOn: $appDelegate.dormTrust)
                        Toggle("不将已进驻的干员放入宿舍", isOn: $appDelegate.dormFilterStationed)
                        Toggle("源石碎片自动补货", isOn: $appDelegate.originiumReplenishment)
                    }
                }
            }
            .padding()

            Toggle("启用自定义基建配置(beta)", isOn: .constant(false)).disabled(true)
                .padding(.vertical)
        }
    }

    // MARK: Custom bindings

    private func binding(for facility: MaaInfrastFacility) -> Binding<Bool> {
        return Binding {
            facility.enabled
        } set: { newValue in
            if let i = appDelegate.facilities.firstIndex(where: { $0.name == facility.name }) {
                appDelegate.facilities[i].enabled = newValue
            }
        }
    }
}

struct InfrastSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        InfrastSettingsView()
    }
}

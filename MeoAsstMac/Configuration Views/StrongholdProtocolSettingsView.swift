//
//  StrongholdProtocolSettingsView.swift
//  MAA
//
//  Created by hguandl on 2026/11/22.
//

import SwiftUI

struct StrongholdProtocolSettingsView: View {
    @Binding var params: Any?

    @AppStorage("StrongholdProtocolConfiguration") private var rawConfig = Data()

    private var config: Binding<Configuration> {
        Binding {
            do {
                return try JSONDecoder().decode(Configuration.self, from: rawConfig)
            } catch {
                return Configuration(mode: "badge", theme: "Regulation", target: 3, runs: 60)
            }
        } set: { newValue in
            do {
                rawConfig = try JSONEncoder().encode(newValue)
            } catch {
                //
            }
        }
    }

    var body: some View {
        Form {
            Picker("卫戍协议主题", selection: config.theme) {
                Text("盟约").tag("Alliance").selectionDisabled()
                Text("规程").tag("Regulation")
            }
            Picker("模式", selection: config.mode) {
                Text("刷角标（完整通关）").tag("badge")
                Text("刷分（放生速通）").tag("score")
            }
            if config.wrappedValue.mode == "badge" {
                Picker("角标目标", selection: config.target) {
                    Text("金色角标（通关3次）").tag(3)
                    Text("彩色角标（通关6次）").tag(6)
                }
                TextField("通关局数", value: config.runs, format: .number)
            }
        }
        .animation(.default, value: config.wrappedValue)
        .onChange(of: config.wrappedValue, initial: true) {
            params = [
                "mode": config.wrappedValue.mode,
                "theme": config.wrappedValue.theme,
                "target": config.wrappedValue.target,
                "runs": config.wrappedValue.runs,
            ]
        }
    }
}

private struct Configuration: Codable, Equatable {
    var mode: String
    var theme: String
    var target: Int
    var runs: Int
}

#Preview {
    StrongholdProtocolSettingsView(params: .constant(nil))
}

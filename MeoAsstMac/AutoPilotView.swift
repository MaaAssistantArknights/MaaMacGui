//
//  AutoPilotView.swift
//  MAA
//
//  Created by hguandl on 19/1/2023.
//

import SwiftUI
import UniformTypeIdentifiers

struct AutoPilotView: View {
    @EnvironmentObject private var appDelegate: AppDelegate
    @State private var showImporter = false
    @State private var fileURL: URL?
    @State private var prtsURL: String = ""
    @State private var formation = false
    @State private var `repeat` = false
    @State private var times = 1
    let prefix = "maa://"

    var body: some View {
        HStack {
            VStack {
                prtsInput().padding()
                fileButton().padding()
                bundledPicker().padding()

                Form {
                    Toggle("自动编队", isOn: $formation)
                    Toggle(isOn: $repeat) {
                        TextField("循环次数", value: $times, format: .number)
                            .frame(maxWidth: 125)
                            .disabled(!`repeat`)
                    }
                }

                if appDelegate.maaRunning == .value(true) {
                    Button("停 止") {
                        Task {
                            appDelegate.maaRunning = .pending
                            _ = await appDelegate.stopMaa()
                            appDelegate.maaRunning = .value(false)
                        }
                    }
                    .padding()
                    .disabled(appDelegate.maaRunning == .pending)
                } else {
                    Button("开 始") {
                        startCopilot()
                    }
                    .padding()
                    .disabled(!maaAvailable)
                }

                Spacer()

                pilotLogging()
            }
            .padding()
            .frame(maxWidth: .infinity)

            Divider()

            ScrollView {
                if let pilot {
                    pilotDescription(pilot: pilot)
                        .textSelection(.enabled)
                        .padding(.horizontal)
                        .padding(.top)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("未选择作业或文件格式错误").padding()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private func prtsInput() -> some View {
        HStack {
            Text("神秘代码：")
            TextField(prefix, text: $prtsURL, onCommit: {
                if self.prtsURL.hasPrefix(prefix) {
                    validateAndJoin2Url()
                    getPrtsCopilotData()
                }
            })
        }
    }

    @ViewBuilder private func fileButton() -> some View {
        VStack {
            Image(systemName: "doc.badge.plus")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 50)

            Text("点击选择或拖拽")
        }
        .padding(.vertical, 15)
        .padding(.horizontal, 40)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary, style: .init(lineWidth: 3, dash: [10, 10]))
        }
        .contentShape(Rectangle())
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            if case let .success(url) = result {
                fileURL = url
            }
        }
        .onTapGesture {
            showImporter = true
        }
        .onDrop(of: [.fileURL], isTargeted: .none) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                guard error == nil else { return }
                fileURL = url
            }
            return true
        }
    }

    @ViewBuilder private func bundledPicker() -> some View {
        Picker("内置作业", selection: $fileURL) {
            Text("请选择").tag(URL?.none)
            ForEach(bundledPilots, id: \.self) { url in
                Text(url.lastPathComponent).tag(URL?.some(url))
            }
            if let fileURL, !bundledPilots.contains(fileURL) {
                Text(fileURL.lastPathComponent).tag(URL?.some(fileURL))
            }
        }
    }

    // TODO: 自动战斗日志显示
    @ViewBuilder private func pilotLogging() -> some View {
        ScrollView {
            Text("")
        }
    }

    @ViewBuilder private func pilotDescription(pilot: MaaAutoPilot) -> some View {
        if let title = pilot.doc?.title {
            Text(title).font(.title2)
        }
        if let details = pilot.doc?.details {
            Text(details)
        }

        if let equipments = pilot.equipment {
            Text("装备：") + Text(equipments.joined(separator: ", "))
        }

        if let strategy = pilot.strategy {
            Text(strategy)
        }

        if pilot.opers.count > 0 {
            VStack {
                ForEach(pilot.opers, id: \.name) { oper in
                    Text(oper.description)
                }
            }
        }

        if let groups = pilot.groups {
            VStack {
                ForEach(groups, id: \.name) { group in
                    Text(group.name) + Text("：")
                        + Text(group.opers.map(\.description).joined(separator: " / "))
                }
            }
        }

        if let toolmen = pilot.tool_men {
            Text(toolmen.sorted { $0.key < $1.key }.map { "\($1)\($0)" }.joined(separator: ", "))
        }
    }

    // MARK: - Methods

    private func startCopilot() {
        guard let fileURL, let pilot else { return }
        let isSSS = pilot.type == "SSS"
        let times = self.repeat ? self.times : 1
        Task {
            appDelegate.maaRunning = .pending
            let success = await appDelegate.startCopilotTask(for: fileURL, formation: formation, sss: isSSS, times: times)
            appDelegate.maaRunning = .value(success)
        }
    }

    private func validateAndJoin2Url() {
        let str = self.prtsURL
        if str.hasPrefix(prefix) {
            let index = str.index(str.startIndex, offsetBy: prefix.count)
            let suffix = str[index...]
            self.prtsURL = "https://prts.maa.plus/copilot/get/\(suffix)"
        }
    }

    private func getPrtsCopilotData() {
        guard let url = URL(string: self.prtsURL) else {
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { (replay, response, error) in
            guard let replay = replay, error == nil else {
                return
            }

            // 解析得到的 JSON 数据
            do {
                let json = try JSONSerialization.jsonObject(with: replay, options: []) as! [String: Any]
                if let statusCode = json["status_code"] as? Int {
                    if statusCode != 200 {
                        return
                    }
                }

                if let data = json["data"] as? [String: Any],
                   let content = data["content"] as? String {
                    do {
                        let temporaryDirectory = NSTemporaryDirectory()
                        let fileUrl = URL(fileURLWithPath: temporaryDirectory).appendingPathComponent("copilot.json")
                        try content.write(to: fileUrl, atomically: true, encoding: .utf8)
                        fileURL = fileUrl
                    } catch {
                        return
                    }
                } else {
                    return
                }
            } catch {
                return
            }
        }
        task.resume()
    }

    // MARK: - Computed properties

    private var pilot: MaaAutoPilot? {
        guard let fileURL else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(MaaAutoPilot.self, from: data)
    }

    private var bundledPilots: [URL] {
        let directory = maaResourceURL.appendingPathComponent("copilot")
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentTypeKey], options: .skipsHiddenFiles) else { return [] }
        return urls.filter { url in
            (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType == .json) ?? false
        }
    }

    private var maaResourceURL: URL {
        Bundle.main.resourceURL!.appendingPathComponent("resource")
    }

    private var maaAvailable: Bool {
        pilot != nil && appDelegate.maaRunning == .value(false)
    }
}

struct AutoPilotView_Previews: PreviewProvider {
    static var previews: some View {
        AutoPilotView()
            .environmentObject(AppDelegate())
    }
}

struct MaaAutoPilot: Codable {
    let stage_name: String
    let opers: [Operator]
    let groups: [Group]?
    let minimum_required: String
    let doc: Documentation?

    /// - Tag: SSS
    let type: String?
    let equipment: [String]?
    let strategy: String?
    let tool_men: [String: Int]?

    struct Operator: Codable {
        let name: String
        let skill: Int?
    }

    struct Group: Codable {
        let name: String
        let opers: [Operator]
    }

    struct Documentation: Codable {
        let title: String?
        let title_color: String?
        let details: String?
        let details_color: String?
    }
}

extension MaaAutoPilot.Operator: CustomStringConvertible {
    var description: String {
        if let skill {
            return "\(name) \(skill)"
        } else {
            return name
        }
    }
}

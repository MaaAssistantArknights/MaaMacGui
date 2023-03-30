//
//  ManageView.swift
//  MeoAsstMac
//
//  Created by hguandl on 9/10/2022.
//

import SwiftUI

struct ManageView: View {
    @EnvironmentObject private var appDelegate: AppDelegate
    
    @Environment(\.defaultMinListRowHeight) private var rowHeight
    
    @State private var showImport = false
        
    let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MM-dd HH:mm:ss"
        return df
    }()

    var body: some View {
        HStack {
            VStack {
                VStack {
                    List {
                        ForEach(appDelegate.tasks, id: \.key) { task in
                            Toggle(task.description, isOn: binding(for: task))
                        }
                        .onMove { source, destination in
                            appDelegate.tasks.move(fromOffsets: source, toOffset: destination)
                        }
                    }
                    .frame(maxHeight: 12 * rowHeight)
                    .onAppear { migrateNewTasks(tasks: &appDelegate.tasks) }
                    HStack {
                        Button {
                            for i in appDelegate.tasks.indices {
                                if !(appDelegate.tasks[i].key == .Roguelike) {
                                    appDelegate.tasks[i].enabled = true
                                }
                            }
                        } label: {
                            Text("全 选").frame(minWidth: 56)
                        }
                        Spacer()
                        Button {
                            for i in appDelegate.tasks.indices {
                                appDelegate.tasks[i].enabled = false
                            }
                        } label: {
                            Text("清 空").frame(minWidth: 56)
                        }
                    }
                }
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.gray, lineWidth: 1.5)
                )
                
                Picker("完成后", selection: .constant("无动作")) {
                    Text("无动作").tag("无动作")
                }
                .padding(.top)
                
                if appDelegate.maaRunning == .value(true) {
                    Button {
                        Task {
                            appDelegate.maaRunning = .pending
                            await _ = appDelegate.stopMaa()
                        }
                    } label: {
                        Text("停 止").padding()
                    }
                    .padding(.top)
                    .disabled(appDelegate.maaRunning == .pending)
                } else {
                    Button {
                        Task {
                            appDelegate.maaRunning = .pending
                            _ = await appDelegate.setupMaa()
                            let success = await appDelegate.startMaa()
                            appDelegate.maaRunning = .value(success)
                        }
                    } label: {
                        Text("Link Start!").padding()
                    }
                    .padding(.top)
                    .disabled(appDelegate.maaRunning == .pending)
                }
            }
            .frame(maxWidth: .infinity)
            
            Divider()
            
            VStack {
                FightSettingsView()
                    .padding()
                
                Divider()
                
                VStack {
                    Text("""
                    周日关卡小提示：
                    货物运送（龙门币）
                    粉碎防御（红票）
                    空中威胁（技能）
                    奶/盾芯片
                    先/辅芯片
                    近/特芯片
                    周日了，记得打剿灭哦～
                    """)
                }
                .padding()
                
                Button("打开日志文件夹") {
                    let url = appDelegate.asstLogURL
                    if FileManager.default.fileExists(atPath: url.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: appDelegate.appDataURL.path)
                    }
                }
                
                Button("安装原生App") {
                    showImport = true
                }
                .fileImporter(isPresented: $showImport, allowedContentTypes: [.fileURL, .init(importedAs: "com.apple.itunes.ipa")]) { result in
                    guard case let .success(url) = result else {
                        return
                    }
                    
                    let connectionToService = NSXPCConnection(serviceName: "com.hguandl.MaaHelper")
                    connectionToService.remoteObjectInterface = NSXPCInterface(with: MaaHelperProtocol.self)
                    connectionToService.resume()

                    if let proxy = connectionToService.remoteObjectProxy as? MaaHelperProtocol {
                        proxy.installApp(url: url) { result in
                            NSLog("Result string was: \(result)")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            
            Divider()
            
            ScrollViewReader { scrollView in
                ScrollView {
                    VStack {
                        ForEach(appDelegate.appLogs, id: \.self) { log in
                            Text(log).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .id("LogScrollView")
                }
                .onChange(of: appDelegate.appLogs) { _ in
                    withAnimation {
                        scrollView.scrollTo("LogScrollView", anchor: .bottom)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
    
    // MARK: - Methods
    
    private func migrateNewTasks(tasks: inout [MaaTask]) {
        tasks.removeAll { task in
            !MaaTask.defaults.map(\.key).contains(task.key)
        }
        
        let newTasks = MaaTask.defaults.filter { task in
            !tasks.map(\.key).contains(task.key)
        }
        tasks.append(contentsOf: newTasks)
    }
    
    // MARK: Custom bindings
    
    private func binding(for task: MaaTask) -> Binding<Bool> {
        return Binding {
            task.enabled
        } set: { newValue in
            if let i = appDelegate.tasks.firstIndex(where: { $0.key == task.key }) {
                appDelegate.tasks[i].enabled = newValue
            }
        }
    }
}

struct ManageView_Previews: PreviewProvider {
    static var previews: some View {
        ManageView()
            .environmentObject(AppDelegate())
    }
}

extension Array: RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Element].self, from: data)
        else {
            return nil
        }
        self = result
    }
    
    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return result
    }
}

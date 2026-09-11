//
//  AboutView.swift
//  MeoAsstMac
//
//  Created by zhangweijian on 11/9/2026.
//

import MaaCore
import SwiftUI

struct AboutView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("关于 MAA") {
            openWindow(id: "about")
        }
    }
}

struct AboutContentView: View {
    private let coreVersion = String(cString: AsstGetVersion())
    private let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("MAA")
                .font(.title2)
                .bold()

            if let bundleVersion, !bundleVersion.isEmpty {
                Text(verbatim: "版本 \(coreVersion) (\(bundleVersion))")
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: "版本 \(coreVersion)")
                    .foregroundStyle(.secondary)
            }

            Text("© MaaAssistantArknights")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .fixedSize()
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutContentView()
    }
}

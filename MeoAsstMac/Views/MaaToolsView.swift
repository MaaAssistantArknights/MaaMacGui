//
//  MaaToolsView.swift
//  MAA
//
//  Created by hguandl on 2026/8/27.
//

import CoreGraphics
import SwiftUI

private enum MaaTestState {
    case initial
    case pending
    case failed(any Error)
    case success(MaaImageResult)
}

struct MaaToolsView: View {
    @AppStorage("MAAConnectionAddress") var connectionAddress = "localhost:1717"
    @AppStorage("MAATouchMode") var touchMode = MaaTouchMode.MacPlayTools

    @State private var state = MaaTestState.initial
    @State private var testTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 8) {
            MaaPresetView()
            Divider()
            HStack(spacing: 12) {
                Button("测试") {
                    withAnimation { state = .pending }
                    testTask = Task {
                        do {
                            let result = try await MaaImageDiagnostics.captureBGR(address: connectionAddress)
                            try Task.checkCancellation()
                            withAnimation { state = .success(result) }
                        } catch is CancellationError {
                            state = .initial
                        } catch {
                            withAnimation { state = .failed(error) }
                        }
                    }
                }
                switch state {
                case .success(let result):
                    result.diagnosisView
                default:
                    EmptyView()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(buttonDisabled)
            if touchMode != .MacPlayTools {
                Text("未启用MacPlayTools触控模式")
            } else {
                switch state {
                case .initial:
                    Text("等待测试")
                case .pending:
                    ProgressView().controlSize(.small)
                case .failed(let error):
                    Text(error.localizedDescription)
                case .success(let result):
                    MaaImageResultView(result: result)
                }
            }
        }
        .animation(.default, value: touchMode)
        .onDisappear { testTask?.cancel() }
    }

    private var buttonDisabled: Bool {
        if touchMode != .MacPlayTools {
            return true
        }
        if case .pending = state {
            return true
        }
        return false
    }

}

private struct MaaPresetView: View {
    @Environment(\.displayScale) private var scale

    @State private var preset = 720.0

    var body: some View {
        VStack(spacing: 12) {
            Text(
                """
                使用多显示器时，请将本窗口与《明日方舟》放置在同一台显示器上。
                基于当前显示器的设定，建议在PlayCover中，将图像设置调整为以下预设之一：
                """
            )
            .fixedSize(horizontal: false, vertical: true)
            Picker("预设", selection: $preset) {
                Text(verbatim: "720p").tag(720.0)
                Text(verbatim: "1080p").tag(1080.0)
            }
            .pickerStyle(.segmented)
            VStack(spacing: 6) {
                Text("分辨率：") + Text("自定义").font(.headline)
                HStack(spacing: 12) {
                    Text("宽度：") + valueText(preset / scale * 16 / 9)
                    Text("高度：") + valueText(preset / scale)
                }
                Text("分辨率缩放：") + valueText(scale, digits: 2)
            }
            .textSelection(.enabled)
            Text(
                """
                运行窗口化的《明日方舟》时，请尝试双击标题栏调整窗口大小，切换并保持为较大的窗口。
                """
            )
            .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.default, value: preset)
    }

    private func valueText(_ value: Double, digits: Int? = 0) -> Text {
        var style = FloatingPointFormatStyle<Double>().grouping(.never)
        if let digits {
            style = style.precision(.significantDigits(digits...))
        }
        return Text(value.formatted(style)).font(.headline)
    }
}

private struct MaaImageResultView: View {
    let result: MaaImageResult

    var body: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing) {
                Text("窗口大小：")
                Text("内容大小：")
            }
            VStack(alignment: .leading) {
                Text(sizeDescription(result.rect.window.size))
                Text(sizeDescription(result.rect.content.size))
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("原始分辨率：")
                Text("截图分辨率：")
            }
            VStack(alignment: .leading) {
                Text(sizeDescription(result.size))
                Text(sizeDescription((result.image.width, result.image.height)))
            }
            Spacer()
        }
        ScrollView {
            Image(result.image, scale: 1.0, label: Text("Arknights Screenshot"))
                .resizable()
                .scaledToFit()
        }
        .scrollIndicators(.never)
    }

    private func sizeDescription<V: BinaryInteger>(_ pair: (V, V)) -> String {
        let style = IntegerFormatStyle<V>().grouping(.never)
        return "\(pair.0.formatted(style))×\(pair.1.formatted(style))"
    }
}

extension MaaImageResult {
    @ViewBuilder fileprivate var diagnosisView: some View {
        Label(diagnosis.message, systemImage: diagnosis == .passed ? "checkmark.circle" : "xmark.circle")
            .foregroundStyle(diagnosis == .passed ? Color.green : Color.red)
    }
}

#Preview {
    MaaToolsView()
        .padding()
        .frame(width: 450, height: 360)
}

//
//  MaaToolsView.swift
//  MAA
//
//  Created by hguandl on 2026/8/27.
//

import Accelerate
import CoreGraphics
import SwiftUI

private enum MaaTestState {
    case initial
    case pending
    case failed(any Error)
    case success(MaaResult)
}

private struct MaaResult {
    let size: (width: UInt16, height: UInt16)
    let rect: (window: Rect, content: Rect)
    let image: CGImage

    typealias Rect = MaaToolsClient.Rect

    enum Error: Swift.Error {
        case invalidAddress
        case unsupportedVersion
        case corruptedImageData
    }
}

struct MaaToolsView: View {
    @AppStorage("MAAConnectionAddress") var connectionAddress = "localhost:1717"
    @AppStorage("MAATouchMode") var touchMode = MaaTouchMode.MacPlayTools

    @State private var state = MaaTestState.initial

    var body: some View {
        VStack(spacing: 8) {
            MaaPresetView()
            Divider()
            HStack(spacing: 12) {
                Button("测试") {
                    withAnimation { state = .pending }
                    Task {
                        do {
                            let result = try await maaResult(address: connectionAddress)
                            withAnimation { state = .success(result) }
                        } catch {
                            withAnimation { state = .failed(error) }
                        }
                    }
                }
                switch state {
                case .success(let result):
                    result.diagnosis
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
                    MaaResultView(result: result)
                }
            }
        }
        .animation(.default, value: touchMode)
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

    private func maaResult(address: String) async throws -> MaaResult {
        guard var client = MaaToolsClient(to: address) else {
            throw MaaResult.Error.invalidAddress
        }
        guard try await client.version() >= 3 else {
            throw MaaResult.Error.unsupportedVersion
        }
        let size = try await client.resolution()
        let rect = try await client.bounds()
        let bgr = try await client.bgrScreenshot()
        let image = try await CGImage.bgr(bgr)
        return MaaResult(size: size, rect: rect, image: image)
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
                Text("720P").tag(720.0)
                Text("1080P").tag(1080.0)
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

private struct MaaResultView: View {
    let result: MaaResult

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

extension MaaResult {
    @ViewBuilder fileprivate var diagnosis: some View {
        if size.width != image.width || size.height != image.height {
            Label("截图与原始分辨率不匹配", systemImage: "xmark.circle")
                .foregroundStyle(.red)
        } else if image.height * 16 != image.width * 9 {
            Label("截图宽高比不符合16:9", systemImage: "xmark.circle")
                .foregroundStyle(.red)
        } else if image.height < 720 {
            Label("截图分辨率不足720P", systemImage: "xmark.circle")
                .foregroundStyle(.red)
        } else {
            Label("成功！", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        }
    }

    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
}

extension CGImage {
    @concurrent static func bgr(_ bgr: ((UInt32, UInt32), Data)) async throws -> CGImage {
        let (width, height) = bgr.0
        let data = bgr.1
        guard data.count == width * height * 3 else {
            throw MaaResult.Error.corruptedImageData
        }

        var dst = try vImage_Buffer(
            width: Int(width), height: Int(height), bitsPerPixel: 32)
        defer {
            dst.free()
        }

        try data.withUnsafeBytes {
            let pointer = UnsafeMutableRawPointer(mutating: $0.baseAddress!)
            var src = vImage_Buffer(
                data: pointer, height: UInt(height),
                width: UInt(width), rowBytes: Int(width) * 3)
            let result = vImageConvert_RGB888toRGBA8888(
                &src, nil, 255, &dst, false, vImage_Flags(kvImageNoFlags))
            guard result == kvImageNoError else {
                throw vImage.Error(vImageError: result)
            }
        }

        let bitmapInfo = CGBitmapInfo(alpha: .noneSkipFirst, byteOrder: .order32Little)

        let format = vImage_CGImageFormat(
            bitsPerComponent: 8, bitsPerPixel: 32,
            colorSpace: MaaResult.colorSpace, bitmapInfo: bitmapInfo)

        return try dst.createCGImage(format: format!)
    }
}

#Preview {
    MaaToolsView()
        .padding()
        .frame(width: 450, height: 360)
}

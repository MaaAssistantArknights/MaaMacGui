//
//  PixelPaintView.swift
//  MAA
//
//  Created by hguandl on 2026/8/14.
//

import SwiftUI

struct PixelPaintView: View {
    @Environment(NewViewModel.self) private var newModel
    @Binding var params: Any?

    @State private var image: CGImage?

    @State private var swipe = true
    @State private var delay = 0.0

    @State private var config = PixelPainterConfig()
    @State private var context = CIContext()
    @State private var showConfig = false
    @State private var includeWhite = false

    private let bounds = CGRect(x: 0, y: 0, width: 24, height: 24)

    var body: some View {
        VStack(spacing: 12) {
            Text("请先手动进入游戏内 24×24 像素画编辑页，再开始。")

            HStack(spacing: 15) {
                Toggle("启用滑动绘制", isOn: $swipe)
                Toggle("也填白色", isOn: $includeWhite)
            }

            Slider(value: $delay, in: 0...500) {
                Text("额外绘制间隔")
            } minimumValueLabel: {
                Text(verbatim: "0")
            } maximumValueLabel: {
                Text(verbatim: "500ms")
            }
            .frame(maxWidth: 250)

            if let painting {
                PixelMapImage(painting: painting, length: bounds.width, white: includeWhite)
                    .onTapGesture {
                        showConfig.toggle()
                    }
            } else {
                VStack(spacing: 15) {
                    Text("请拖入图片")
                        .font(.title2)
                        .bold()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .border(.tertiary, width: 5)
            }
        }
        .animation(.default, value: painting)
        .disabled(disabled)
        .dropDestination(for: Image.self) { items, location in
            guard let item = items.first else { return false }

            let renderer = ImageRenderer(content: item)
            renderer.scale = 1

            image = renderer.cgImage
            return true
        } isTargeted: { _ in
        }
        .popover(isPresented: $showConfig, arrowEdge: .leading) {
            PixelConfigView(config: $config).padding()
        }
        .onChange(of: painting) {
            guard let painting = $1 else { return }
            params = [
                "pixel_paint": [
                    "groups": painting.groups(white: includeWhite),
                    "swipe": swipe,
                    "grid_delay": delay,
                ]
            ]
        }
    }

    private var painting: PixelPainting? {
        guard let image else { return nil }
        let painter = PixelPainter(config: config, context: context)
        return painter.convert(image: image, in: bounds)
    }

    private var disabled: Bool {
        painting == nil || newModel.status != .idle
    }
}

private struct PixelMapImage: View {
    let painting: PixelPainting
    let length: CGFloat
    let white: Bool

    var body: some View {
        Canvas { context, size in
            let pixelSize = size.width / length
            for (xy, color) in painting.cells(includeWhite: white) {
                context.fill(
                    Path(
                        CGRect(
                            x: CGFloat(xy.x) * pixelSize,
                            y: CGFloat(xy.y) * pixelSize,
                            width: pixelSize, height: pixelSize)),
                    with: .color(color))
            }
        }
        .aspectRatio(contentMode: .fit)
    }
}

struct PixelConfigView: View {
    @Binding var config: PixelPainterConfig

    var body: some View {
        Form {
            Picker("缩放算法", selection: $config.scaleFilter) {
                Text("Lanczos").tag(PixelPainterConfig.ScaleFilter.lanczos)
                Text("双三次").tag(PixelPainterConfig.ScaleFilter.bicubic)
            }

            if config.scaleFilter == .bicubic {
                Slider(value: $config.bicubicSoftness, in: 0...1) {
                    Text("平滑度")
                }
            }

            Slider(value: $config.saturation, in: 0...2) {
                Text("饱和度")
            }
            Slider(value: $config.brightness, in: -1...1) {
                Text("亮度")
            }
            Slider(value: $config.contrast, in: 0...2) {
                Text("对比度")
            }

            Toggle("色彩匹配", isOn: $config.perceptual)

            Button("还原默认") {
                config = .init()
            }
        }
        .animation(.default, value: config)
    }
}

#Preview("PixelPaintView") {
    NavigationSplitView {
        EmptyView()
    } content: {
        EmptyView()
    } detail: {
        PixelPaintView(params: .constant(""))
            .padding()
    }
    .environment(NewViewModel(parent: MAAViewModel()))
}

extension PixelPainting {
    fileprivate func groups(white: Bool) -> [Any] {
        colorPoints(includeWhite: white).map {
            [
                "color": $0,
                "points": $1.map { [$0.x, $0.y] },
            ]
        }
    }
}

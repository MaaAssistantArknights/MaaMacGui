//
//  PixelPaintView.swift
//  MAA
//
//  Created by hguandl on 2026/8/14.
//

import SwiftUI

struct PixelPaintView: View {
    @Environment(NewViewModel.self) private var newModel
    @Binding var params: (any Encodable)?

    @State private var pixelMap: PixelMap?
    @State private var failure: Error?

    @State private var swipe = true
    @State private var delay = 0.0

    let website = URL(string: "https://prts.chongxi.us/")!

    var body: some View {
        VStack(spacing: 12) {
            Text("请先手动进入游戏内 24×24 像素画编辑页，再开始。")

            Toggle("启用滑动绘制", isOn: $swipe)

            Slider(value: $delay, in: 0...500) {
                Text("绘制间隔")
            } minimumValueLabel: {
                Text(verbatim: "0")
            } maximumValueLabel: {
                Text(verbatim: "500ms")
            }
            .frame(maxWidth: 250)

            if let pixelMap {
                PixelMapImage(pixelMap: pixelMap)
            } else {
                VStack(spacing: 15) {
                    Text("请拖入坐标颜色JSON")
                        .font(.title2)
                        .bold()

                    Link("前往作画网站", destination: website)
                        .environment(\.isEnabled, true)

                    if let failure {
                        Text(failure.localizedDescription)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .border(.tertiary, width: 5)
            }
        }
        .animation(.default, value: pixelMap)
        .animation(.default, value: failure == nil)
        .disabled(disabled)
        .onDrop(of: [.json], isTargeted: nil) { providers in
            guard let provider = providers.first else {
                return false
            }
            provider.loadItem(forTypeIdentifier: "public.json", completionHandler: processItem)
            return true
        }
    }

    private var disabled: Bool {
        pixelMap == nil || newModel.status != .idle
    }

    @Sendable private nonisolated func processItem(item: NSSecureCoding?, error: Error?) {
        DispatchQueue.main.async {
            self.pixelMap = nil
        }

        if let error {
            DispatchQueue.main.async {
                self.failure = error
            }
            return
        }

        guard let url = item as? URL else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let pixelMap = try JSONDecoder().decode(PixelMap.self, from: data)
            let groups = pixelMap.groups
            DispatchQueue.main.async {
                let delay = Int(self.delay)
                self.params = PixelPaintParams(
                    pixel_paint: .init(groups: groups, swipe: self.swipe, grid_delay: delay))
                self.pixelMap = pixelMap
            }
        } catch {
            DispatchQueue.main.async {
                self.failure = error
            }
        }
    }
}

private struct PixelPaintParams: Codable {
    let pixel_paint: Content

    struct Content: Codable {
        let groups: [Group]
        let swipe: Bool
        let grid_delay: Int
    }

    struct Group: Codable, Hashable {
        let color: Int
        let points: [[Int]]
    }
}

private struct PixelMapImage: View {
    let pixelMap: PixelMap

    var body: some View {
        Canvas { context, size in
            let pixelSize = size.width / CGFloat(pixelMap.size)

            for cell in pixelMap.cells {
                context.fill(
                    Path(
                        CGRect(
                            x: CGFloat(cell.x) * pixelSize,
                            y: CGFloat(cell.y) * pixelSize,
                            width: pixelSize, height: pixelSize)),
                    with: .color(cell.color))
            }
        }
        .aspectRatio(contentMode: .fit)
    }
}

private struct PixelMap: Codable, Hashable {
    let size: Int
    let cells: [Cell]

    struct Cell: Codable, Hashable {
        let x: Int
        let y: Int
        let seq: Int
        let region: Int
        let hex: String
        let palPos: String
    }
}

extension PixelMap {
    var groups: [PixelPaintParams.Group] {
        var dict = [Int: [[Int]]]()

        for cell in cells {
            guard let color = cell.palette else {
                continue
            }
            var points = dict[color, default: [[]]]
            points.append([cell.x, cell.y])
            dict[color] = points
        }

        return dict.map { (color, points) in
            PixelPaintParams.Group(color: color, points: points)
        }
    }
}

extension PixelMap.Cell {
    var color: Color {
        let value = Int(hex.trimmingPrefix("#"), radix: 16)
        guard let value else { return .clear }
        return .init(
            .sRGB,
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255,
            opacity: 1)
    }

    var palette: Int? {
        let pattern = #"第(\d+)行第(\d+)列"#

        guard let match = palPos.range(of: pattern, options: .regularExpression) else {
            return nil
        }

        let value = String(palPos[match])
        let numbers = value.split { !$0.isNumber }
            .compactMap { Int($0) }

        guard numbers.count == 2 else {
            return nil
        }

        return (numbers[0] - 1) * 4 + numbers[1] - 1
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

#Preview("PixelMapImage") {
    let data = NSDataAsset(name: "ChongxiPixelMap")!.data
    let pixelMap = try! JSONDecoder().decode(PixelMap.self, from: data)
    PixelMapImage(pixelMap: pixelMap)
}

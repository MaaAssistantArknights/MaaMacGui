//
//  PixelPainter.swift
//  MAA
//
//  Created by hguandl on 2026/8/15.
//

import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI

struct PixelPainterConfig: Hashable {
    enum ScaleFilter: Hashable {
        case lanczos
        case bicubic
    }

    var scaleFilter = ScaleFilter.lanczos
    var bicubicSoftness = 0.25

    var saturation = 1.0
    var brightness = 0.0
    var contrast = 1.0

    var dithering = 0.0

    var perceptual = true
}

struct PixelPainter {
    let config: PixelPainterConfig

    let context: CIContext

    func convert(image: CGImage, in bounds: CGRect) -> PixelPainting? {
        let inputSize = CGSize(width: image.width, height: image.height)
        let target = AVMakeRect(aspectRatio: inputSize, insideRect: bounds)
        let scale = Float(target.width / inputSize.width)

        var ciImage = CIImage(cgImage: image)

        if scale != 1.0 {
            switch config.scaleFilter {
            case .lanczos:
                let filter = CIFilter.lanczosScaleTransform()
                filter.inputImage = ciImage
                filter.scale = scale
                ciImage = filter.outputImage!
            case .bicubic:
                let filter = CIFilter.bicubicScaleTransform()
                filter.inputImage = ciImage
                filter.scale = scale
                filter.parameterB = Float(config.bicubicSoftness)
                filter.parameterC = Float(1 - config.bicubicSoftness / 2)
                ciImage = filter.outputImage!
            }
            let background = CIImage(color: .black).cropped(to: ciImage.extent)
            ciImage = ciImage.composited(over: background)
        }

        do {
            let filter = CIFilter.colorControls()
            filter.inputImage = ciImage
            filter.saturation = Float(config.saturation)
            filter.brightness = Float(config.brightness)
            filter.contrast = Float(config.contrast)
            ciImage = filter.outputImage!
        }

        if config.dithering > 0 {
            let filter = CIFilter.dither()
            filter.inputImage = ciImage
            filter.intensity = Float(config.dithering)
            ciImage = filter.outputImage!
        }

        do {
            let filter = CIFilter.palettize()
            filter.inputImage = ciImage
            filter.paletteImage = paletteImage
            filter.perceptual = config.perceptual
            ciImage = filter.outputImage!
        }

        let width = Int(ciImage.extent.width)
        let height = Int(ciImage.extent.height)
        let rowBytes = width * 4

        var data = Data(count: height * rowBytes)
        data.withUnsafeMutableBytes {
            guard let pointer = $0.baseAddress else { return }
            context.render(
                ciImage, toBitmap: pointer,
                rowBytes: rowBytes,
                bounds: ciImage.extent,
                format: .RGBA8,
                colorSpace: .init(name: CGColorSpace.sRGB))
        }

        let bitmap = data.withUnsafeBytes {
            $0.bindMemory(to: SIMD4<UInt8>.self).map {
                SIMD3($0.x, $0.y, $0.z)
            }
        }

        return .init(bitmap: bitmap, bounds: bounds, rows: height)
    }
}

struct PixelPainting: Hashable {
    fileprivate let bitmap: [SIMD3<UInt8>]
    fileprivate let bounds: CGRect
    fileprivate let rows: Int

    private let white = SIMD3<UInt8>(255, 255, 255)

    private var pixels: [(xy: SIMD2<Int>, rgb: SIMD3<UInt8>)] {
        let columns = bitmap.count / rows

        var result = [(xy: SIMD2<Int>, rgb: SIMD3<UInt8>)]()
        result.reserveCapacity(rows * columns)

        let offsetX = Int(bounds.midX - Double(columns) / 2)
        let offsetY = Int(bounds.midY - Double(rows) / 2)

        var index = 0
        for y in 0..<rows {
            for x in 0..<columns {
                result.append((SIMD2(x + offsetX, y + offsetY), bitmap[index]))
                index += 1
            }
        }

        return result
    }

    func cells(includeWhite: Bool) -> [(xy: SIMD2<Int>, Color)] {
        pixels.compactMap { (xy, rgb) in
            if !includeWhite, rgb == white {
                return nil
            }
            if let index = paletteRGB.firstIndex(of: rgb) {
                return (xy, paletteColor[index])
            } else {
                return nil
            }
        }
    }

    func colorPoints(includeWhite: Bool) -> [Int: [SIMD2<Int>]] {
        var result = [Int: [SIMD2<Int>]]()
        for pixel in pixels {
            if !includeWhite, pixel.rgb == white { continue }
            let index = paletteRGB.firstIndex(of: pixel.rgb)
            guard let index else { continue }
            result[index, default: []].append(pixel.xy)
        }
        return result
    }
}

private let paletteRGB = [
    (034, 034, 034), (180, 180, 180), (234, 231, 223), (255, 255, 255),
    (211, 047, 054), (156, 010, 000), (214, 012, 074), (230, 150, 141),
    (254, 152, 117), (247, 208, 192), (252, 239, 234), (251, 246, 232),
    (220, 210, 200), (226, 206, 171), (213, 099, 034), (212, 140, 066),
    (242, 153, 000), (249, 201, 051), (252, 228, 153), (179, 180, 122),
    (194, 218, 114), (108, 110, 000), (177, 145, 085), (169, 143, 116),
    (170, 146, 040), (063, 043, 018), (116, 073, 031), (083, 070, 088),
    (042, 036, 070), (057, 069, 153), (090, 069, 157), (186, 163, 215),
    (182, 188, 223), (169, 172, 190), (099, 171, 185), (180, 210, 220),
    (145, 216, 230), (071, 174, 160), (182, 211, 200), (039, 056, 100),
].map { (r, g, b) in
    SIMD3<UInt8>(r, g, b)
}

private let paletteImage = {
    let bitmap = paletteRGB.map { rgb in
        SIMD4(rgb, 255)
    }
    let data = bitmap.withUnsafeBufferPointer {
        Data(buffer: $0)
    }
    return CIImage(
        bitmapData: data,
        bytesPerRow: bitmap.count * 4,
        size: CGSize(width: bitmap.count, height: 1),
        format: .RGBA8,
        colorSpace: .init(name: CGColorSpace.sRGB)
    )
}()

private let paletteColor = paletteRGB.map {
    let rgb = SIMD3<Double>($0) / 255
    return Color(red: rgb.x, green: rgb.y, blue: rgb.z)
}

import Accelerate
import CoreGraphics
import Foundation

struct MaaImageResult {
    let size: (width: UInt16, height: UInt16)
    let rect: (window: MaaToolsClient.Rect, content: MaaToolsClient.Rect)
    let image: CGImage
    var diagnosis: MaaImageDiagnosis { .evaluate(original: size, width: image.width, height: image.height) }
}

enum MaaImageDiagnosis: Equatable, Sendable {
    case passed, sizeMismatch, aspectRatio, lowResolution

    static func evaluate(original: (width: UInt16, height: UInt16), width: Int, height: Int) -> Self {
        if Int(original.width) != width || Int(original.height) != height { return .sizeMismatch }
        if Int64(height) * 16 != Int64(width) * 9 { return .aspectRatio }
        if width < 1280 || height < 720 { return .lowResolution }
        return .passed
    }

    var message: String {
        switch self {
        case .passed: String(localized: "成功！")
        case .sizeMismatch: String(localized: "截图与原始分辨率不匹配")
        case .aspectRatio: String(localized: "截图宽高比不符合16:9")
        case .lowResolution: String(localized: "截图分辨率不足720p")
        }
    }
}

enum MaaImageDiagnostics {
    enum Error: Swift.Error, LocalizedError {
        case invalidAddress, corruptedImageData
        var errorDescription: String? {
            switch self {
            case .invalidAddress: String(localized: "连接地址格式无效。")
            case .corruptedImageData: String(localized: "截图数据不完整或尺寸无效。")
            }
        }
    }

    static func captureBGR(address: String) async throws -> MaaImageResult {
        try Task.checkCancellation()
        guard var client = MaaToolsClient(to: address) else { throw Error.invalidAddress }
        defer { client.cancel() }
        return try await captureBGR(client: &client)
    }

    static func captureBGR(
        client: inout MaaToolsClient,
        size: (width: UInt16, height: UInt16)? = nil,
        didReadBounds: ((MaaToolsClient.Rect, MaaToolsClient.Rect) -> Void)? = nil
    ) async throws -> MaaImageResult {
        guard try await client.version() >= 3 else { throw MaaToolsError.unsupportedVersion }
        let resolvedSize: (width: UInt16, height: UInt16)
        if let size { resolvedSize = size } else { resolvedSize = try await client.resolution() }
        let rect = try await client.bounds()
        didReadBounds?(rect.window, rect.content)
        let image = try await CGImage.bgr(client.bgrScreenshot())
        return .init(size: resolvedSize, rect: rect, image: image)
    }

    static func rgba(_ data: Data, size: (width: UInt16, height: UInt16)) throws -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0, data.count == width * height * 4,
            data.count <= MaaToolsClient.maximumImageBytes,
            let provider = CGDataProvider(data: data as CFData),
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: imageColorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else {
            throw Error.corruptedImageData
        }
        return image
    }
}

private let imageColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

extension CGImage {
    @concurrent static func bgr(_ bgr: ((UInt32, UInt32), Data)) async throws -> CGImage {
        try Task.checkCancellation()
        let (width, height) = bgr.0
        let data = bgr.1
        guard width > 0, height > 0,
            UInt64(width) * UInt64(height) <= UInt64(MaaToolsClient.maximumImageBytes) / 4,
            UInt64(data.count) == UInt64(width) * UInt64(height) * 3,
            data.count <= MaaToolsClient.maximumImageBytes
        else {
            throw MaaImageDiagnostics.Error.corruptedImageData
        }
        // Automatic vImage allocation pads narrow rows, which can exceed the validated pixel budget.
        let rowBytes = Int(width) * 4
        guard let destination = malloc(rowBytes * Int(height)) else {
            throw vImage.Error(vImageError: kvImageMemoryAllocationError)
        }
        defer { free(destination) }
        var dst = vImage_Buffer(data: destination, height: UInt(height), width: UInt(width), rowBytes: rowBytes)
        try data.withUnsafeBytes {
            let pointer = UnsafeMutableRawPointer(mutating: $0.baseAddress!)
            var src = vImage_Buffer(data: pointer, height: UInt(height), width: UInt(width), rowBytes: Int(width) * 3)
            let result = vImageConvert_RGB888toRGBA8888(&src, nil, 255, &dst, false, vImage_Flags(kvImageNoFlags))
            guard result == kvImageNoError else { throw vImage.Error(vImageError: result) }
        }
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        let format = vImage_CGImageFormat(
            bitsPerComponent: 8, bitsPerPixel: 32,
            colorSpace: imageColorSpace, bitmapInfo: bitmapInfo)!
        try Task.checkCancellation()
        return try dst.createCGImage(format: format)
    }
}

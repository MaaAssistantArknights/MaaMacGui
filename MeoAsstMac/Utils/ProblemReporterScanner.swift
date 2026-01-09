//
//  ProblemReporterScanner.swift
//  MAA
//
//  Created by RainYang on 2025/12/12.
//

import Cocoa
import CoreGraphics
import Vision

class ProblemReporterScanner {

    // MARK: - 1. 对外接口：检查并识别
    /// 查找“问题报告程序”并检查是否包含 "Arknights"
    static func checkArknights() async -> Bool {
        // 使用 Task.detached 强制在后台线程执行耗时操作，避免卡主线程
        return await Task.detached(priority: .userInitiated) {
            // 1. 截图
            guard let capturedImage = captureWindow(ownerName: "问题报告程序") else {
                print("⚠️ 未找到名为 '问题报告程序' 的窗口")
                return false
            }

            // 2. 识别
            return containsText(targetText: "Arknights", in: capturedImage)
        }.value
    }

    // MARK: - 2. 核心逻辑：截图指定 App 窗口
    private static func captureWindow(ownerName: String) -> CGImage? {
        // 获取所有屏幕上的窗口信息
        guard let windowInfoList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        else {
            return nil
        }

        // 遍历查找名为 ownerName 的窗口
        for info in windowInfoList {
            // 获取窗口所属的应用名称 (kCGWindowOwnerName)
            if let name = info[kCGWindowOwnerName as String] as? String, name == ownerName {

                // 获取窗口 ID
                guard let windowID = info[kCGWindowNumber as String] as? CGWindowID else { continue }

                // 排除很小的窗口（有时候应用会有不可见的 1x1 窗口）
                if let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                    let width = boundsDict["Width"], width < 50
                {
                    continue
                }

                // 创建截图：只截取该 WindowID 的窗口
                let imageOption: CGWindowListOption = [.optionIncludingWindow]
                let image = CGWindowListCreateImage(.null, imageOption, windowID, .boundsIgnoreFraming)

                return image
            }
        }
        return nil
    }

    // MARK: - 3. 核心逻辑：OCR 文字识别
    private static func containsText(targetText: String, in cgImage: CGImage) -> Bool {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate  // 追求高准确率
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            guard let observations = request.results else { return false }

            for observation in observations {
                // 获取置信度最高的候选词
                if let candidate = observation.topCandidates(1).first {
                    // 不区分大小写匹配
                    if candidate.string.localizedCaseInsensitiveContains(targetText) {
                        // 调试打印：看到了什么文字
                        print("🔎 识别到匹配文本: \(candidate.string)")
                        return true
                    }
                }
            }
        } catch {
            print("OCR Error: \(error)")
        }

        return false
    }
}

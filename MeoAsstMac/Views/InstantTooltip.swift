//
//  InstantTooltip.swift
//  MAA
//
//  Created by RainYang on 2025/8/22.
//

import SwiftUI
import AppKit

// MARK: - AppKit Tooltip Modifier

/// 一个 SwiftUI `ViewModifier`，用于给任何视图添加一个即时的、跟随鼠标的工具提示。
struct AppKitTooltipModifier<TooltipContent: View>: ViewModifier {
    /// 要在工具提示中显示的内容，可以是任何 SwiftUI 视图。
    let tooltipContent: TooltipContent
    
    /// 修改器的主体，将负责追踪鼠标的视图覆盖在原始视图之上。
    func body(content: Content) -> some View {
        content.overlay(
            // 使用自定义的 NSViewRepresentable 来桥接 AppKit 的功能。
            TooltipView(tooltipContent: {
                tooltipContent
            })
        )
    }
}

// MARK: - NSViewRepresentable Bridge

/// 一个 `NSViewRepresentable`，作为 SwiftUI 和 AppKit 之间的桥梁。
/// 它负责创建一个 NSView 来捕获鼠标事件。
fileprivate struct TooltipView<TooltipContent: View>: NSViewRepresentable {
    
    /// 一个闭包，用于构建工具提示的内容视图。
    let tooltipContent: () -> TooltipContent
    
    /// 创建并配置底层的 `NSView`。
    func makeNSView(context: Context) -> NSView {
        // 创建一个空的 NSView，它将作为鼠标追踪区域的容器。
        let view = NSView()
        // 将此视图的引用传递给 Coordinator，以便后续操作。
        context.coordinator.hostView = view
        return view
    }
    
    /// 当 SwiftUI 视图更新时，此方法被调用。我们用它来确保追踪区域的大小正确。
    func updateNSView(_ nsView: NSView, context: Context) {
        // 当视图尺寸变化时，重新计算并设置追踪区域。
        context.coordinator.updateTrackingArea()
    }
    
    /// 创建 `Coordinator` 实例，它将处理来自 AppKit 的事件和回调。
    func makeCoordinator() -> Coordinator {
        Coordinator(tooltipContent: tooltipContent)
    }
    
    // MARK: - Coordinator
    
    /// `Coordinator` 是连接 SwiftUI 和 AppKit 事件处理的核心。
    /// 它作为 AppKit 对象（如 NSTrackingArea）的代理，并管理工具提示窗口的状态。
    class Coordinator: NSObject {
        /// 用于构建工具提示内容的闭包。
        private let tooltipContent: () -> TooltipContent
        /// 对宿主 `NSView` 的弱引用，防止循环引用。
        weak var hostView: NSView?
        
        /// 用于显示工具提示的自定义 NSWindow。
        private var tooltipWindow: NSWindow?
        /// 用于在 NSWindow 中承载 SwiftUI 视图的 NSHostingView。
        /// 其泛型为 `AnyView`，因为内置样式会改变原始视图的类型。
        private var hostingView: NSHostingView<AnyView>?
        /// AppKit 的追踪区域对象，用于侦测鼠标事件。
        private var trackingArea: NSTrackingArea?

        init(tooltipContent: @escaping () -> TooltipContent) {
            self.tooltipContent = tooltipContent
            super.init()
        }
        
        /// 更新或创建鼠标追踪区域。当视图大小改变时需要调用。
        func updateTrackingArea() {
            guard let view = hostView else { return }
            // 如果已存在追踪区域，先移除旧的。
            if let trackingArea = self.trackingArea {
                view.removeTrackingArea(trackingArea)
            }
            // 创建一个新的追踪区域，覆盖整个宿主视图。
            let newTrackingArea = NSTrackingArea(
                rect: view.bounds,
                // 我们关心鼠标的进入、退出和移动事件。
                options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeInKeyWindow],
                owner: self, // Coordinator 自身处理事件。
                userInfo: nil
            )
            // 将新的追踪区域添加到视图中。
            view.addTrackingArea(newTrackingArea)
            self.trackingArea = newTrackingArea
        }
        
        /// 创建并配置用于显示工具提示的 `NSWindow`。
        private func createTooltipWindow() {
            // 如果窗口已存在，先关闭并销毁，以确保内容是最新的。
            if tooltipWindow != nil {
                tooltipWindow?.close()
                tooltipWindow = nil
            }
            
            // --- 内置样式 ---
            // 调用闭包获取用户提供的原始 SwiftUI 视图。
            let styledView = tooltipContent()
                .padding(10) // 添加默认内边距。
                .background(
                    RoundedRectangle(cornerRadius: 8) // 添加圆角矩形背景。
                        .fill(Color(.windowBackgroundColor)) // 使用系统默认的窗口背景色，以支持深色/浅色模式。
                )
                .fixedSize() // 确保视图尺寸由其内容决定，防止被外部布局压缩。
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top))) // 添加一个简单的过渡动画。
            
            // 使用 `AnyView` 进行类型擦除，因为添加修饰符后视图类型会改变。
            let finalView = AnyView(styledView)
            
            // 创建一个 `NSHostingView` 来承载处理过的 SwiftUI 视图。
            let newHostingView = NSHostingView(rootView: finalView)
            newHostingView.frame.size = newHostingView.fittingSize // 自适应内容大小。
            self.hostingView = newHostingView

            // 创建一个无边框的 `NSWindow` 作为工具提示的容器。
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: newHostingView.frame.size),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = newHostingView // 将 hostingView 设置为窗口内容。
            window.isReleasedWhenClosed = false // 关闭时不释放，以便复用。
            window.level = .floating // 确保窗口显示在所有其他应用窗口之上。
            window.backgroundColor = .clear // 窗口背景透明，以便显示 SwiftUI 视图的圆角。
            
            self.tooltipWindow = window
        }
        
        /// 当鼠标进入追踪区域时由 `NSTrackingArea` 调用。
        @objc func mouseEntered(_ event: NSEvent) {
            createTooltipWindow()
            updateTooltipPosition(event)
            tooltipWindow?.orderFront(nil) // 显示窗口。
        }
        
        /// 当鼠标在追踪区域内移动时由 `NSTrackingArea` 调用。
        @objc func mouseMoved(_ event: NSEvent) {
            updateTooltipPosition(event) // 实时更新窗口位置。
        }
        
        /// 当鼠标离开追踪区域时由 `NSTrackingArea` 调用。
        @objc func mouseExited(_ event: NSEvent) {
            tooltipWindow?.orderOut(nil) // 隐藏窗口。
        }

        /// 根据鼠标当前位置计算并更新工具提示窗口的位置。
        private func updateTooltipPosition(_ event: NSEvent) {
            guard let window = tooltipWindow, let windowSize = window.contentView?.frame.size else { return }
            
            // `NSEvent.mouseLocation` 直接提供鼠标在屏幕上的全局坐标。
            let mouseLocation = NSEvent.mouseLocation
            // 在鼠标指针和窗口之间设置一个固定的间隙。
            let gap: CGFloat = 12.0
            
            // 默认将窗口定位在鼠标指针的右下方。
            var newOrigin = NSPoint(
                x: mouseLocation.x + gap,
                y: mouseLocation.y - windowSize.height - gap
            )
            
            // --- 屏幕边界检查 ---
            if let screen = NSScreen.main {
                let screenRect = screen.visibleFrame // 使用 `visibleFrame` 来避开 Dock 和菜单栏。
                
                // 如果窗口超出屏幕右边界，则将其翻转到鼠标左侧。
                if newOrigin.x + windowSize.width > screenRect.maxX {
                    newOrigin.x = mouseLocation.x - windowSize.width - gap
                }
                
                // 如果窗口超出屏幕下边界，则将其翻转到鼠标上方。
                if newOrigin.y < screenRect.minY {
                    newOrigin.y = mouseLocation.y + gap
                }
                
                // 如果（翻转后）窗口超出屏幕左边界，将其贴紧左边界。
                if newOrigin.x < screenRect.minX {
                     newOrigin.x = screenRect.minX
                }
            }
            
            // 应用最终计算出的位置。
            window.setFrameOrigin(newOrigin)
        }
    }
}

// MARK: - View Extension

extension View {
    /// 给视图添加一个即时的、跟随鼠标的工具提示。
    /// - Parameter content: 一个 `@ViewBuilder` 闭包，用于构建工具提示中显示的内容。
    /// - Returns: 一个应用了工具提示修改器的视图。
    func instantTooltip<TooltipContent: View>(@ViewBuilder content: () -> TooltipContent) -> some View {
        self.modifier(AppKitTooltipModifier(tooltipContent: content()))
    }
}

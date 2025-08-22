//
//  InstantTooltip.swift
//  MAA
//
//  Created by RainYang on 2025/8/22.
//


import SwiftUI

struct InstantTooltipModifier<TooltipContent: View>: ViewModifier {
    @State private var isHovering = false
    let tooltipContent: TooltipContent

    func body(content: Content) -> some View {
        content
            // 将 onHover 应用于一个略微放大的、不可见的区域，
            // 这样鼠标在内容和工具提示的边缘移动时不会轻易触发“离开”事件。
            .overlay(
                GeometryReader { geometry in
                    Color.clear
                        .contentShape(Rectangle()) // 确保透明区域可以接收悬停事件
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onHover { hovering in
                            // 添加一个微小的延迟，防止因鼠标快速划过而触发
                            withAnimation(.default.delay(0.05)) {
                                self.isHovering = hovering
                            }
                        }
                }
            )
            .overlay(
                // 将工具提示的视图放在主内容的上方
                Group {
                    if isHovering {
                        tooltipContent
                            // 强制视图使用其理想尺寸，防止文字被截断
                            .fixedSize()
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.windowBackgroundColor))
                                    .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
                            )
                            .offset(y: 40)
                             // 使用平滑的透明度和缩放动画
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                            // 给一个固定的ID有助于SwiftUI在状态切换时识别视图，减少闪烁
                            .id("tooltip")
                    }
                }
                // 将动画应用到 Group 上，而不是 isHovering 的切换上
                .animation(.easeInOut(duration: 0.15), value: isHovering)
            )
    }
}


extension View {
    func instantTooltip<TooltipContent: View>(@ViewBuilder content: () -> TooltipContent) -> some View {
        self.modifier(InstantTooltipModifier(tooltipContent: content()))
    }
}

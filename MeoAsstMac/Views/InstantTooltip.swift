//
//  InstantTooltip.swift
//  MAA
//
//  Created by RainYang on 2025/8/22.
//


import SwiftUI

/// TODO: NavigationSplitView的层级限制问题
struct InstantTooltipModifier<TooltipContent: View>: ViewModifier {
    @State private var isHovering = false
    // 任务句柄，用于管理延迟隐藏
    @State private var hideTask: Task<Void, Never>?

    let tooltipContent: TooltipContent
    
    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                // 取消之前可能存在的“隐藏”任务
                hideTask?.cancel()
                
                if hovering {
                    // 鼠标进入，立即显示
                    isHovering = true
                } else {
                    // 鼠标离开，启动一个可取消的延迟任务来隐藏
                    hideTask = Task {
                        // 延迟 80 毫秒，这个时间足够跨越内容和提示框之间的缝隙
                        try? await Task.sleep(nanoseconds: 80_000_000)
                        // 如果任务没被取消，就执行隐藏
                        isHovering = false
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if isHovering {
                    tooltipContent
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.windowBackgroundColor))
                                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        )
                        .offset(y: 45) // 调整与主内容的垂直距离
                        .transition(.opacity)
                        //提示框永远不参与点击或悬停，确保下方内容可被点击
                        .allowsHitTesting(false)
                        .fixedSize()
                }
            }
            // 使用动画让显示/隐藏更平滑
            .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}


extension View {
    func instantTooltip<TooltipContent: View>(@ViewBuilder content: () -> TooltipContent) -> some View {
        self.modifier(InstantTooltipModifier(tooltipContent: content()))
    }
}

import Foundation
#if canImport(AppKit)
import AppKit

/// 动画执行统一拦截层
/// 根据 AccessibilitySettings 自动选择正常动画或 Reduce Motion 回退
public enum AnimationRunner {

    /// 执行动画，自动处理 Reduce Motion 回退
    /// - Parameters:
    ///   - settings: 无障碍设置（默认读取当前系统设置）
    ///   - animation: 正常动画定义
    ///   - normal: 正常动画执行闭包
    ///   - reduced: Reduce Motion 回退闭包
    public static func animate(
        settings: AccessibilitySettings = .current(),
        animation: AnimationConstants.Animation,
        normal: () -> Void,
        reduced: () -> Void
    ) {
        if settings.reduceMotion {
            reduced()
        } else {
            normal()
        }
    }

    /// 简化版：自动根据 Reduce Motion 决定是否执行动画
    /// - Parameters:
    ///   - settings: 无障碍设置
    ///   - animation: 动画定义
    ///   - block: 动画执行闭包（Reduce Motion 时跳过）
    public static func run(
        settings: AccessibilitySettings = .current(),
        animation: AnimationConstants.Animation,
        block: () -> Void
    ) {
        if settings.reduceMotion {
            // Reduce Motion: 使用回退策略
            switch animation.reduceMotionFallback {
            case .fade(let duration):
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = duration
                    block()
                }
            case .instant:
                block()
            case .scalePulse:
                block()
            }
        } else {
            block()
        }
    }
}
#endif

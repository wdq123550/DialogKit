// DialogDefinitions.swift
// DialogKit 的协议、配置类型与内部包装器定义。

import Foundation
import SwiftUI

// MARK: - DialogPresentable

/// 让 SwiftUI View 遵守此协议，即可交由 `DialogManager` 进行排队展示。
public protocol DialogPresentable: View {

    /// 弹窗的外观与行为配置。
    var dialogConfig: DialogConfiguration { get }

    /// 在出场动画**开始之前**调用。
    func willAppear()
    /// 在出场动画**完成之后**调用。
    func didAppear()
    /// 在关闭动画**开始之前**调用。
    func willDismiss()
    /// 在关闭动画**完成之后**调用。
    func didDismiss()
}

public extension DialogPresentable {
    var dialogConfig: DialogConfiguration { .init() }
    func willAppear() {}
    func didAppear() {}
    func willDismiss() {}
    func didDismiss() {}
}

// MARK: - DialogConfiguration

/// 弹窗的完整配置，包括位置、转场、动画与遮罩颜色。
public struct DialogConfiguration {

    /// 弹窗在屏幕上的停靠位置。
    public var position: DialogPosition

    /// 弹窗的出场 / 退场转场效果。
    public var transition: DialogTransition

    /// 弹窗的动画曲线与时长。
    public var animation: DialogAnimation

    /// 弹窗背后遮罩层的颜色（含透明度）。
    ///
    /// - 设为 `.clear`（即 alpha 通道为 0）有特殊语义：表示遮罩**不拦截点击**，
    ///   点击 dialog 主体之外的区域会穿透到下层视图。此时 `dismissOnBackgroundTap`
    ///   不生效。
    /// - 如果想让背景看起来透明但又**不希望穿透**，请使用任意颜色 + 极低不透明度
    ///   （例如 `.black.withAlphaComponent(0.01)`）。
    public var dimmingColor: UIColor

    /// 弹窗展示后自动关闭的延时（秒）。
    ///
    /// - 设为 `nil`（默认）或 `<= 0` 表示不自动关闭。
    /// - 计时从弹窗的**出场动画完成之后**（即 `didAppear` 触发后）开始。
    /// - 计时仅作用于配置了该值的那个弹窗实例本身：若在计时结束前该弹窗已被
    ///   主动关闭、被插队替换或被 ``DialogManager/dismissAll()`` 清空，
    ///   计时器不会误关后续展示的其它弹窗。
    public var autoDismissDelay: TimeInterval?

    /// 是否允许点击弹窗背后的遮罩区域（即 dialog 主体之外的空白处）来关闭弹窗。
    ///
    /// - 默认 `false`，保持原有行为：遮罩不响应点击。
    /// - 设为 `true` 时，点击 dialog 主体之外的任意位置会触发
    ///   ``DialogManager/dismissCurrent()``。
    /// - 点击 dialog 主体本身不会触发关闭（前提是 dialog 视图有自己的背景，
    ///   这是 SwiftUI 弹窗的常规做法）。
    /// - **当 `dimmingColor` 为 `.clear` 时本配置不生效**：此时遮罩本身不
    ///   拦截点击事件（点击会穿透），自然也无从触发关闭。
    public var dismissOnBackgroundTap: Bool

    public init(
        position: DialogPosition = .center,
        transition: DialogTransition = .init(),
        animation: DialogAnimation = .init(),
        dimmingColor: UIColor = .black.withAlphaComponent(0.8),
        autoDismissDelay: TimeInterval? = nil,
        dismissOnBackgroundTap: Bool = false
    ) {
        self.position = position
        self.transition = transition
        self.animation = animation
        self.dimmingColor = dimmingColor
        self.autoDismissDelay = autoDismissDelay
        self.dismissOnBackgroundTap = dismissOnBackgroundTap
    }
}

// MARK: - DialogPosition

/// 弹窗在屏幕上的停靠位置。
public enum DialogPosition: Equatable, Sendable {
    /// 贴顶部显示；`safeAreaPadding` 为 `true` 时自动避开安全区域。
    case top(safeAreaPadding: Bool = false)
    /// 居中显示。
    case center
    /// 贴底部显示；`safeAreaPadding` 为 `true` 时自动避开安全区域。
    case bottom(safeAreaPadding: Bool = false)
}

// MARK: - DialogTransition

/// 弹窗出场与退场的转场配置。
public struct DialogTransition: Equatable, Sendable {

    /// 出场时使用的转场方向。
    public var appear: DialogTransitionEdge

    /// 退场时使用的转场方向。
    public var disappear: DialogTransitionEdge

    public init(
        appear: DialogTransitionEdge = .centerScale,
        disappear: DialogTransitionEdge = .centerScale
    ) {
        self.appear = appear
        self.disappear = disappear
    }
}

// MARK: - DialogTransitionEdge

/// 单次转场（出场或退场）的动画方式。
public enum DialogTransitionEdge: Equatable, Sendable {
    /// 从屏幕顶部滑入 / 滑出。
    case top
    /// 从屏幕底部滑入 / 滑出。
    case bottom
    /// 在中央以缩放方式出现 / 消失。
    case centerScale
}

// MARK: - DialogAnimationItem

/// 单个动画阶段（出场或退场）的曲线与时长。
public struct DialogAnimationItem {

    /// SwiftUI `Animation` 值。
    public var value: Animation

    /// 动画时长（秒），需与 `value` 中的时长保持一致。
    public var duration: CGFloat

    public init(
        value: Animation = .easeInOut(duration: 0.25),
        duration: CGFloat = 0.25
    ) {
        self.value = value
        self.duration = duration
    }
}

// MARK: - DialogAnimation

/// 弹窗出场与退场的动画配置。
public struct DialogAnimation {

    /// 出场动画。
    public var appear: DialogAnimationItem

    /// 退场动画。
    public var disappear: DialogAnimationItem

    public init(
        appear: DialogAnimationItem = .init(),
        disappear: DialogAnimationItem = .init()
    ) {
        self.appear = appear
        self.disappear = disappear
    }
}

// MARK: - DialogWrapper

/// 内部包装器，为每个弹窗分配唯一 ID 以驱动 SwiftUI 差异更新。
internal struct DialogWrapper: Identifiable {
    let id = UUID()
    let content: any DialogPresentable
}

// DialogManager.swift
// A lightweight, queue-based dialog presentation system for SwiftUI.
// Requires iOS 17+, Swift 5.9+ (uses @Observable and withAnimation completion).

import Foundation
import SwiftUI
import Observation

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

// MARK: - DialogManager

/// 基于队列的弹窗管理器。
///
/// 同一时刻最多展示一个弹窗，后续弹窗会排队等待。
/// 使用 `@Observable` 驱动 SwiftUI 视图刷新，需要 iOS 17+。
///
/// **基本用法：**
/// ```swift
/// ContentView()
///     .overlay { DialogManager.shared.dialogLayer }
///
/// DialogManager.shared.show(MyDialog())
/// ```
@MainActor
@Observable
public final class DialogManager {

    /// 全局单例。
    public static let shared = DialogManager()

    /// 当前正在展示的弹窗包装器。
    private(set) var currentWrapper: DialogWrapper?

    /// 等待展示的弹窗队列。
    private var queue: [DialogWrapper] = []

    private init() {}
}

// MARK: - Public API

public extension DialogManager {

    /// 当前弹窗的动画时长；若无弹窗则返回默认值 `0.25`。
    var currentAnimationDuration: CGFloat {
        currentWrapper?.content.dialogConfig.animation.appear.duration ?? 0.25
    }

    /// 当前是否有弹窗正在展示。
    var isPresenting: Bool {
        currentWrapper != nil
    }

    /// 将弹窗加入队列并展示。
    ///
    /// 如果当前已有弹窗正在展示，新弹窗将排队等待，直到前面的弹窗被关闭后自动展示。
    /// - Parameter dialog: 要展示的弹窗视图（需遵守 `DialogPresentable`）。
    func show(_ dialog: any DialogPresentable) {
        let wrapper = DialogWrapper(content: dialog)
        queue.append(wrapper)
        if currentWrapper == nil {
            showNext()
        }
    }

    /// 关闭当前弹窗并立即展示指定弹窗。
    ///
    /// 新弹窗会被插入队列最前方，当前弹窗关闭后立即展示。
    /// 如果当前没有弹窗，则等同于调用 ``show(_:)``。
    /// - Parameter dialog: 要插队展示的弹窗视图。
    func dismissCurrentAndShow(_ dialog: any DialogPresentable) {
        guard currentWrapper != nil else {
            show(dialog)
            return
        }
        let wrapper = DialogWrapper(content: dialog)
        queue.insert(wrapper, at: 0)
        dismissCurrent()
    }

    /// 关闭当前正在展示的弹窗。
    ///
    /// 关闭后会自动展示队列中的下一个弹窗（如果有）。
    func dismissCurrent() {
        guard let wrapper = currentWrapper else { return }
        let dialog = wrapper.content

        dialog.willDismiss()

        withAnimation(dialog.dialogConfig.animation.disappear.value) {
            currentWrapper = nil
        } completion: {
            dialog.didDismiss()
            Task { @MainActor in
                self.showNext()
            }
        }
    }

    /// 关闭当前弹窗并清空整个等待队列，不带动画。
    func dismissAll() {
        queue.removeAll()

        guard let wrapper = currentWrapper else { return }
        let dialog = wrapper.content

        dialog.willDismiss()
        currentWrapper = nil
        dialog.didDismiss()
    }

    /// 弹窗覆盖层视图，需挂载到应用根视图上。
    ///
    /// 仅忽略 `.container` 安全区域（导航栏 / TabBar / 刘海等），保留对 `.keyboard` 的避让。
    /// 这样键盘弹起时，SwiftUI 会自动将弹窗内容上推以避免被键盘遮挡，业务侧无需手动处理。
    @ViewBuilder
    var dialogLayer: some View {
        Color.clear.overlay {
            dimmingView.overlay {
                contentView
            }
        }
        .ignoresSafeArea(.container, edges: .all)
    }
}

// MARK: - Private Implementation

private extension DialogManager {

    /// 从队列中取出下一个弹窗并以动画展示。
    func showNext() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()

        next.content.willAppear()

        withAnimation(next.content.dialogConfig.animation.appear.value) {
            self.currentWrapper = next
        } completion: {
            self.currentWrapper?.content.didAppear()
            self.scheduleAutoDismissIfNeeded(for: next)
        }
    }

    /// 若弹窗配置了 `autoDismissDelay`，在出场动画完成后启动一次性计时器。
    ///
    /// 计时结束时会校验当前展示的 wrapper 是否仍是同一个实例（通过 `id` 比对），
    /// 以避免在该弹窗已被提前关闭、替换或清空后误关掉后续的其它弹窗。
    func scheduleAutoDismissIfNeeded(for wrapper: DialogWrapper) {
        guard
            let delay = wrapper.content.dialogConfig.autoDismissDelay,
            delay > 0
        else { return }

        let targetID = wrapper.id
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self else { return }
            guard self.currentWrapper?.id == targetID else { return }
            self.dismissCurrent()
        }
    }

    /// 半透明遮罩背景。
    ///
    /// - 当 `dimmingColor` 为 `.clear`（alpha == 0）时：遮罩 `.allowsHitTesting(false)`，
    ///   点击会穿透到下层视图，且不挂任何点击手势；`dismissOnBackgroundTap` 在此场景下被忽略。
    /// - 当 `dimmingColor` 非 `.clear` 时：仅在 `dismissOnBackgroundTap == true` 才挂
    ///   点击手势。dialog 内容作为该遮罩的 `.overlay` 位于其上方，点击 dialog 主体（带背景）
    ///   会被其自身吸收、不会冒泡到此手势，因此只有空白区域的点击才会触发关闭。
    @ViewBuilder
    var dimmingView: some View {
        if let wrapper = currentWrapper {
            let config = wrapper.content.dialogConfig
            if config.dimmingColor.isEffectivelyClear {
                Color.clear
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            } else {
                Color(uiColor: config.dimmingColor)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { [weak self] in
                        guard config.dismissOnBackgroundTap else { return }
                        self?.dismissCurrent()
                    }
            }
        }
    }

    /// 弹窗内容视图，包含转场、位置和内边距。
    @ViewBuilder
    var contentView: some View {
        if let wrapper = currentWrapper {
            AnyView(wrapper.content)
                .id(wrapper.id)
                .padding(paddingInsets(for: wrapper.content))
                .transition(buildTransition(for: wrapper.content))
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: alignment(for: wrapper.content)
                )
        }
    }

    /// 根据配置生成非对称转场（出场与退场可不同）。
    func buildTransition(for dialog: any DialogPresentable) -> AnyTransition {
        let t = dialog.dialogConfig.transition
        return .asymmetric(
            insertion: swiftUITransition(t.appear),
            removal: swiftUITransition(t.disappear)
        )
    }

    /// 将 `DialogTransitionEdge` 映射为 SwiftUI `AnyTransition`。
    func swiftUITransition(_ edge: DialogTransitionEdge) -> AnyTransition {
        switch edge {
        case .top: .move(edge: .top)
        case .bottom: .move(edge: .bottom)
        case .centerScale: .scale
        }
    }

    /// 将 `DialogPosition` 映射为 SwiftUI `Alignment`。
    func alignment(for dialog: any DialogPresentable) -> Alignment {
        switch dialog.dialogConfig.position {
        case .center: .center
        case .top: .top
        case .bottom: .bottom
        }
    }

    /// 根据 `DialogPosition` 计算安全区域内边距。
    func paddingInsets(for dialog: any DialogPresentable) -> EdgeInsets {
        switch dialog.dialogConfig.position {
        case .top(let safe): safe ? .init(top: safeAreaTop, leading: 0, bottom: 0, trailing: 0) : .init()
        case .bottom(let safe): safe ? .init(top: 0, leading: 0, bottom: safeAreaBottom, trailing: 0) : .init()
        case .center: .init()
        }
    }

    /// 当前 key window 的顶部安全区域高度。
    var safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.top ?? 0
    }

    /// 当前 key window 的底部安全区域高度。
    var safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
    }
}

// MARK: - UIColor + DialogKit

private extension UIColor {

    /// 该颜色是否"完全透明"（alpha 通道为 0）。
    ///
    /// 用于判断遮罩层是否应让点击穿透到下层视图。使用 `cgColor.alpha` 而非
    /// `getRed(_:green:blue:alpha:)` 以兼容非 RGB 色彩空间（例如 `UIColor.clear`
    /// 实际处于灰度色彩空间）。
    var isEffectivelyClear: Bool {
        cgColor.alpha == 0
    }
}

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
    public var dimmingColor: UIColor

    public init(
        position: DialogPosition = .center,
        transition: DialogTransition = .init(),
        animation: DialogAnimation = .init(),
        dimmingColor: UIColor = .black.withAlphaComponent(0.8)
    ) {
        self.position = position
        self.transition = transition
        self.animation = animation
        self.dimmingColor = dimmingColor
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

// MARK: - DialogAnimation

/// 弹窗动画的曲线与时长配置。
public struct DialogAnimation {

    /// SwiftUI `Animation` 值，用于 `withAnimation`。
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
        currentWrapper?.content.dialogConfig.animation.duration ?? 0.25
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

        withAnimation(dialog.dialogConfig.animation.value) {
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
    @ViewBuilder
    var dialogLayer: some View {
        Color.clear.overlay {
            dimmingView.overlay {
                contentView
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Private Implementation

private extension DialogManager {

    /// 从队列中取出下一个弹窗并以动画展示。
    func showNext() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()

        next.content.willAppear()

        withAnimation(next.content.dialogConfig.animation.value) {
            self.currentWrapper = next
        } completion: {
            self.currentWrapper?.content.didAppear()
        }
    }

    /// 半透明遮罩背景。
    @ViewBuilder
    var dimmingView: some View {
        if let wrapper = currentWrapper {
            Color(uiColor: wrapper.content.dialogConfig.dimmingColor)
                .ignoresSafeArea()
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

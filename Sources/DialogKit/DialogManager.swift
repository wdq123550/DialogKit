// DialogManager.swift
// A lightweight, queue-based dialog presentation system for SwiftUI.
// Requires iOS 17+, Swift 5.9+ (uses @Observable and withAnimation completion).

import Foundation
import SwiftUI
import Observation

// MARK: - DLDialogPresentable

/// 让 SwiftUI View 遵守此协议，即可交由 `DLDialogManager` 进行排队展示。
public protocol DLDialogPresentable: View {

    /// 弹窗的外观与行为配置。
    var dl_dialogConfig: DLDialogConfiguration { get }

    /// 在出场动画**开始之前**调用。
    func dl_willAppear()
    /// 在出场动画**完成之后**调用。
    func dl_didAppear()
    /// 在关闭动画**开始之前**调用。
    func dl_willDismiss()
    /// 在关闭动画**完成之后**调用。
    func dl_didDismiss()
}

public extension DLDialogPresentable {
    var dl_dialogConfig: DLDialogConfiguration { .init() }
    func dl_willAppear() {}
    func dl_didAppear() {}
    func dl_willDismiss() {}
    func dl_didDismiss() {}
}

// MARK: - DLDialogConfiguration

/// 弹窗的完整配置，包括位置、转场、动画与遮罩颜色。
public struct DLDialogConfiguration {

    /// 弹窗在屏幕上的停靠位置。
    public var dl_position: DLDialogPosition

    /// 弹窗的出场 / 退场转场效果。
    public var dl_transition: DLDialogTransition

    /// 弹窗的动画曲线与时长。
    public var dl_animation: DLDialogAnimation

    /// 弹窗背后遮罩层的颜色（含透明度）。
    public var dl_dimmingColor: UIColor

    public init(
        dl_position: DLDialogPosition = .dl_center,
        dl_transition: DLDialogTransition = .init(),
        dl_animation: DLDialogAnimation = .init(),
        dl_dimmingColor: UIColor = .black.withAlphaComponent(0.8)
    ) {
        self.dl_position = dl_position
        self.dl_transition = dl_transition
        self.dl_animation = dl_animation
        self.dl_dimmingColor = dl_dimmingColor
    }
}

// MARK: - DLDialogPosition

/// 弹窗在屏幕上的停靠位置。
public enum DLDialogPosition: Equatable, Sendable {
    /// 贴顶部显示；`dl_safeAreaPadding` 为 `true` 时自动避开安全区域。
    case dl_top(dl_safeAreaPadding: Bool = false)
    /// 居中显示。
    case dl_center
    /// 贴底部显示；`dl_safeAreaPadding` 为 `true` 时自动避开安全区域。
    case dl_bottom(dl_safeAreaPadding: Bool = false)
}

// MARK: - DLDialogTransition

/// 弹窗出场与退场的转场配置。
public struct DLDialogTransition: Equatable, Sendable {

    /// 出场时使用的转场方向。
    public var dl_appear: DLDialogTransitionEdge

    /// 退场时使用的转场方向。
    public var dl_disappear: DLDialogTransitionEdge

    public init(
        dl_appear: DLDialogTransitionEdge = .dl_centerScale,
        dl_disappear: DLDialogTransitionEdge = .dl_centerScale
    ) {
        self.dl_appear = dl_appear
        self.dl_disappear = dl_disappear
    }
}

// MARK: - DLDialogTransitionEdge

/// 单次转场（出场或退场）的动画方式。
public enum DLDialogTransitionEdge: Equatable, Sendable {
    /// 从屏幕顶部滑入 / 滑出。
    case dl_top
    /// 从屏幕底部滑入 / 滑出。
    case dl_bottom
    /// 在中央以缩放方式出现 / 消失。
    case dl_centerScale
}

// MARK: - DLDialogAnimationItem

/// 单个动画阶段（出场或退场）的曲线与时长。
public struct DLDialogAnimationItem {

    /// SwiftUI `Animation` 值。
    public var dl_value: Animation

    /// 动画时长（秒），需与 `dl_value` 中的时长保持一致。
    public var dl_duration: CGFloat

    public init(
        dl_value: Animation = .easeInOut(duration: 0.25),
        dl_duration: CGFloat = 0.25
    ) {
        self.dl_value = dl_value
        self.dl_duration = dl_duration
    }
}

// MARK: - DLDialogAnimation

/// 弹窗出场与退场的动画配置。
public struct DLDialogAnimation {

    /// 出场动画。
    public var dl_appear: DLDialogAnimationItem

    /// 退场动画。
    public var dl_disappear: DLDialogAnimationItem

    public init(
        dl_appear: DLDialogAnimationItem = .init(),
        dl_disappear: DLDialogAnimationItem = .init()
    ) {
        self.dl_appear = dl_appear
        self.dl_disappear = dl_disappear
    }
}

// MARK: - DLDialogWrapper

/// 内部包装器，为每个弹窗分配唯一 ID 以驱动 SwiftUI 差异更新。
internal struct DLDialogWrapper: Identifiable {
    let id = UUID()
    let dl_content: any DLDialogPresentable
}

// MARK: - DLDialogManager

/// 基于队列的弹窗管理器。
///
/// 同一时刻最多展示一个弹窗，后续弹窗会排队等待。
/// 使用 `@Observable` 驱动 SwiftUI 视图刷新，需要 iOS 17+。
///
/// **基本用法：**
/// ```swift
/// ContentView()
///     .overlay { DLDialogManager.shared.dl_dialogLayer }
///
/// DLDialogManager.shared.dl_show(MyDialog())
/// ```
@MainActor
@Observable
public final class DLDialogManager {

    /// 全局单例。
    public static let shared = DLDialogManager()

    /// 当前正在展示的弹窗包装器。
    private(set) var dl_currentWrapper: DLDialogWrapper?

    /// 等待展示的弹窗队列。
    private var dl_queue: [DLDialogWrapper] = []

    private init() {}
}

// MARK: - Public API

public extension DLDialogManager {

    /// 当前弹窗的动画时长；若无弹窗则返回默认值 `0.25`。
    var dl_currentAnimationDuration: CGFloat {
        dl_currentWrapper?.dl_content.dl_dialogConfig.dl_animation.dl_appear.dl_duration ?? 0.25
    }

    /// 当前是否有弹窗正在展示。
    var dl_isPresenting: Bool {
        dl_currentWrapper != nil
    }

    /// 将弹窗加入队列并展示。
    ///
    /// 如果当前已有弹窗正在展示，新弹窗将排队等待，直到前面的弹窗被关闭后自动展示。
    /// - Parameter dialog: 要展示的弹窗视图（需遵守 `DLDialogPresentable`）。
    func dl_show(_ dialog: any DLDialogPresentable) {
        let wrapper = DLDialogWrapper(dl_content: dialog)
        dl_queue.append(wrapper)
        if dl_currentWrapper == nil {
            dl_showNext()
        }
    }

    /// 关闭当前弹窗并立即展示指定弹窗。
    ///
    /// 新弹窗会被插入队列最前方，当前弹窗关闭后立即展示。
    /// 如果当前没有弹窗，则等同于调用 ``dl_show(_:)``。
    /// - Parameter dialog: 要插队展示的弹窗视图。
    func dl_dismissCurrentAndShow(_ dialog: any DLDialogPresentable) {
        guard dl_currentWrapper != nil else {
            dl_show(dialog)
            return
        }
        let wrapper = DLDialogWrapper(dl_content: dialog)
        dl_queue.insert(wrapper, at: 0)
        dl_dismissCurrent()
    }

    /// 关闭当前正在展示的弹窗。
    ///
    /// 关闭后会自动展示队列中的下一个弹窗（如果有）。
    func dl_dismissCurrent() {
        guard let wrapper = dl_currentWrapper else { return }
        let dialog = wrapper.dl_content

        dialog.dl_willDismiss()

        withAnimation(dialog.dl_dialogConfig.dl_animation.dl_disappear.dl_value) {
            dl_currentWrapper = nil
        } completion: {
            dialog.dl_didDismiss()
            Task { @MainActor in
                self.dl_showNext()
            }
        }
    }

    /// 关闭当前弹窗并清空整个等待队列，不带动画。
    func dl_dismissAll() {
        dl_queue.removeAll()

        guard let wrapper = dl_currentWrapper else { return }
        let dialog = wrapper.dl_content

        dialog.dl_willDismiss()
        dl_currentWrapper = nil
        dialog.dl_didDismiss()
    }

    /// 弹窗覆盖层视图，需挂载到应用根视图上。
    @ViewBuilder
    var dl_dialogLayer: some View {
        Color.clear.overlay {
            dl_dimmingView.overlay {
                dl_contentView
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Private Implementation

private extension DLDialogManager {

    /// 从队列中取出下一个弹窗并以动画展示。
    func dl_showNext() {
        guard !dl_queue.isEmpty else { return }
        let next = dl_queue.removeFirst()

        next.dl_content.dl_willAppear()

        withAnimation(next.dl_content.dl_dialogConfig.dl_animation.dl_appear.dl_value) {
            self.dl_currentWrapper = next
        } completion: {
            self.dl_currentWrapper?.dl_content.dl_didAppear()
        }
    }

    /// 半透明遮罩背景。
    @ViewBuilder
    var dl_dimmingView: some View {
        if let wrapper = dl_currentWrapper {
            Color(uiColor: wrapper.dl_content.dl_dialogConfig.dl_dimmingColor)
                .ignoresSafeArea()
        }
    }

    /// 弹窗内容视图，包含转场、位置和内边距。
    @ViewBuilder
    var dl_contentView: some View {
        if let wrapper = dl_currentWrapper {
            AnyView(wrapper.dl_content)
                .id(wrapper.id)
                .padding(dl_paddingInsets(for: wrapper.dl_content))
                .transition(dl_buildTransition(for: wrapper.dl_content))
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: dl_alignment(for: wrapper.dl_content)
                )
        }
    }

    /// 根据配置生成非对称转场（出场与退场可不同）。
    func dl_buildTransition(for dialog: any DLDialogPresentable) -> AnyTransition {
        let t = dialog.dl_dialogConfig.dl_transition
        return .asymmetric(
            insertion: dl_swiftUITransition(t.dl_appear),
            removal: dl_swiftUITransition(t.dl_disappear)
        )
    }

    /// 将 `DLDialogTransitionEdge` 映射为 SwiftUI `AnyTransition`。
    func dl_swiftUITransition(_ edge: DLDialogTransitionEdge) -> AnyTransition {
        switch edge {
        case .dl_top: .move(edge: .top)
        case .dl_bottom: .move(edge: .bottom)
        case .dl_centerScale: .scale
        }
    }

    /// 将 `DLDialogPosition` 映射为 SwiftUI `Alignment`。
    func dl_alignment(for dialog: any DLDialogPresentable) -> Alignment {
        switch dialog.dl_dialogConfig.dl_position {
        case .dl_center: .center
        case .dl_top: .top
        case .dl_bottom: .bottom
        }
    }

    /// 根据 `DLDialogPosition` 计算安全区域内边距。
    func dl_paddingInsets(for dialog: any DLDialogPresentable) -> EdgeInsets {
        switch dialog.dl_dialogConfig.dl_position {
        case .dl_top(let safe): safe ? .init(top: dl_safeAreaTop, leading: 0, bottom: 0, trailing: 0) : .init()
        case .dl_bottom(let safe): safe ? .init(top: 0, leading: 0, bottom: dl_safeAreaBottom, trailing: 0) : .init()
        case .dl_center: .init()
        }
    }

    /// 当前 key window 的顶部安全区域高度。
    var dl_safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.top ?? 0
    }

    /// 当前 key window 的底部安全区域高度。
    var dl_safeAreaBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
    }
}

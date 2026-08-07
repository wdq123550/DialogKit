// DialogManager.swift
// A lightweight, queue-based dialog presentation system for SwiftUI.
// Requires iOS 17+, Swift 5.9+ (uses @Observable and Animatable-driven animation completion).

import Foundation
import SwiftUI
import Observation

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

    /// 本轮出场 / 退场动画使用的曲线（由弹窗自己配）。
    ///
    /// 退场时 `currentWrapper` 已被置空、取不到它的配置，而 `dialogLayer` 上的隐式动画仍需要
    /// 一条曲线，因此在改动 `currentWrapper` 之前，先把本轮该用的那条缓存到这里。
    private var activeAnimation: Animation = DialogAnimationItem().value

    /// 动画令牌：每展示 / 收起一个弹窗 +1，作为 `dialogLayer` 上 `.animation(_:value:)` 的触发值。
    private var animationToken: Int = 0

    /// 出场动画的进度锚点：每展示一个弹窗 +1，由动画观察器跟随渲染逐帧推进，
    /// 推进到该值即代表出场动画「真的画完了」（见 ``AnimationCompletionObserver``）。
    private var appearProgress: CGFloat = 0

    /// 退场动画的进度锚点：每收起一个弹窗 +1，语义同 ``appearProgress``。
    private var dismissProgress: CGFloat = 0

    /// 等待出场动画结束后回调 `didAppear` 的弹窗（一次性，取出即清空，避免重复回调）。
    @ObservationIgnored private var pendingAppearWrapper: DialogWrapper?

    /// 等待退场动画结束后回调 `didDismiss` 的弹窗（一次性，取出即清空）。
    @ObservationIgnored private var pendingDismissDialog: (any DialogPresentable)?

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

        pendingDismissDialog = dialog
        // 先备好本轮曲线，再动令牌与内容：三者在同一次状态更新里生效，隐式动画会读到新曲线。
        activeAnimation = dialog.dialogConfig.animation.disappear.value
        animationToken += 1
        dismissProgress += 1
        currentWrapper = nil
    }

    /// 关闭当前弹窗并清空整个等待队列，不带动画。
    func dismissAll() {
        queue.removeAll()
        // 本方法不带动画、收尾回调在下面直接发；先把两个待回调清空，
        // 避免此刻可能仍在飞的动画观察器稍后再补发一次 didAppear / didDismiss。
        pendingAppearWrapper = nil
        pendingDismissDialog = nil

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
        // 无弹窗时整层显式放行触摸，避免依赖 Color.clear 的隐式命中测试行为；
        // 有弹窗时再交由 dimmingView 决定是否拦截（透明遮罩仍可穿透）。
        .allowsHitTesting(isPresenting)
        // 两个观察器挂在「常驻」的覆盖层上（不随弹窗插入 / 移除而重建），
        // 这样进度值的变化才有上一帧可供插值，动画才能被正常观察到。
        // ⚠️ 位置必须在下面 `.animation` 的「内侧」（上游）：只有落在隐式动画作用域内，
        // 进度值才会被逐帧插值；挂到 `.animation` 外侧会一步跳到终值、当场误报动画完成。
        .modifier(AnimationCompletionObserver(observedValue: appearProgress) {
            self.handleAppearAnimationFinished()
        })
        .modifier(AnimationCompletionObserver(observedValue: dismissProgress) {
            self.handleDismissAnimationFinished()
        })
        // 用隐式动画取代 withAnimation：动画就此归属于本层视图，而不是由调用方的 mutation
        // transaction 持有。业务页面在同一拍里发生大规模重建时，SwiftUI 会在原事务之外重新
        // 提交终点状态，那会把由 withAnimation 持有的在飞动画整个掐断——弹窗直接跳到终点、
        // completion 不结算，挂在 didAppear / didDismiss 上的业务逻辑与队列推进随之停摆。
        // 把动画声明在它真正发生的地方，就不再受外部重建牵连。
        .animation(activeAnimation, value: animationToken)
    }
}

// MARK: - Private Implementation

private extension DialogManager {

    /// 从队列中取出下一个弹窗并以动画展示。
    func showNext() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()

        next.content.willAppear()

        pendingAppearWrapper = next
        // 顺序同 dismissCurrent：先备曲线，再动令牌与内容。
        activeAnimation = next.content.dialogConfig.animation.appear.value
        animationToken += 1
        appearProgress += 1
        currentWrapper = next
    }

    /// 出场动画真的画完了（由 `dialogLayer` 上的动画观察器在渲染到终态那一帧回调）→
    /// 通知弹窗 `didAppear`，并接着安排自动关闭。
    ///
    /// - Important: 这里不能用 `withAnimation(_:completion:)` 的 completion。该 completion 要求
    ///   动画「逻辑上完成」才结算，而这个动画会被业务页面的同拍重建掐断（原因见 `dialogLayer`
    ///   上 `.animation` 的注释）；一旦被掐断，completion 会一直挂着不回调，直到下一次渲染
    ///   （往往是用户点了一下屏幕）才补调，表现为弹窗已经在屏上、`didAppear` 却迟迟不来，
    ///   挂在它上面的业务编排整个停摆。
    ///
    /// - Important: 也不能改用 `Task.sleep` 按动画时长计时。那是挂钟计时，主线程卡顿时时间到了
    ///   画面却还没画完，回调会提前打出去；观察器跟随渲染时钟，卡顿时一起卡，只会晚、不会早。
    ///
    /// - Note: 一次性 + 身份校验：`pendingAppearWrapper` 取出即清空（观察器在同值上可能被驱动
    ///   多次），且要求当前展示的仍是同一个弹窗——出场动画期间若被 ``dismissCurrentAndShow(_:)``
    ///   顶掉就不该再回调（顺带修掉原先 `currentWrapper?.content.didAppear()` 会打到后来者身上的问题）。
    func handleAppearAnimationFinished() {
        guard let wrapper = pendingAppearWrapper else { return }
        pendingAppearWrapper = nil
        guard currentWrapper?.id == wrapper.id else { return }
        wrapper.content.didAppear()
        scheduleAutoDismissIfNeeded(for: wrapper)
    }

    /// 退场动画真的画完了 → 通知弹窗 `didDismiss`，再展示队列中的下一个弹窗。
    ///
    /// 同 ``handleAppearAnimationFinished()``，不走 completion——否则收尾回调与队列推进都可能
    /// 一直挂着，后面排队的弹窗永远出不来。
    func handleDismissAnimationFinished() {
        guard let dialog = pendingDismissDialog else { return }
        pendingDismissDialog = nil
        dialog.didDismiss()
        // 关闭动画期间 currentWrapper 已被置空，若此时又有新弹窗 show 进来，
        // 它会「立即」showNext 占位。这里必须先判空，否则会二次 showNext
        // 把刚占位的弹窗直接盖掉（一闪而过）。
        guard currentWrapper == nil else { return }
        showNext()
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

// MARK: - AnimationCompletionObserver

/// 「动画真的画完了」的观察器：跟随 SwiftUI 的渲染时钟，而不是挂钟计时。
///
/// 原理：SwiftUI 在动画的每一帧把 `animatableData` 往目标值推进，并在画到终态那一帧把它设成
/// 目标值。帧由渲染驱动，所以这个信号同时避开了另外两种写法各自的坑：
/// - `Task.sleep` 按动画时长计时：那是挂钟，主线程卡顿时时间到了画面却还没画完，回调会提前
///   打出去（此时弹窗内依赖布局的数据尚未就绪）。观察器卡顿时跟着一起卡，只会晚、不会早。
/// - `withAnimation(_:completion:)` 的 completion：动画被外部重建掐断后它不结算，会一直挂着
///   不回调。观察器即便在「动画被掐断、直接跳终态」时也会立刻收到一次终值，因此绝不会挂死。
///
/// 用法上有两条硬要求，违反任意一条都会退化成「立刻误报完成」：
/// 1. 必须挂在**常驻**视图上，不能随被观察的内容一起插入 / 移除——新挂载的实例首帧就等于目标值，
///    等不到动画；
/// 2. 必须落在驱动动画的 `.animation(_:value:)` 的**内侧**（上游），否则进度值不被插值，会一步
///    跳到终值。
private struct AnimationCompletionObserver: ViewModifier, Animatable {

    /// SwiftUI 逐帧推进的动画值；等于 `targetValue` 即代表已画到终态。
    var animatableData: CGFloat {
        didSet { notifyIfFinished() }
    }

    /// 本次动画的目标值（构造时固定，不参与插值）。
    private let targetValue: CGFloat

    /// 画到终态时的回调。
    private let onFinished: () -> Void

    /// 初始化：传入当前要观察的进度值与动画结束回调。
    init(observedValue: CGFloat, onFinished: @escaping () -> Void) {
        self.animatableData = observedValue
        self.targetValue = observedValue
        self.onFinished = onFinished
    }

    /// 本观察器不改变视图外观，原样透传。
    func body(content: Content) -> some View {
        content
    }

    /// 推进到终态才回调；派发到下一个主线程周期，避免在视图更新过程中直接改状态。
    ///
    /// 这里刻意用 `DispatchQueue.main.async`，不要「顺手」换成 Swift Concurrency：本方法是在
    /// SwiftUI 的渲染 / 布局周期内部被调用的，`MainActor.run` 在已处于主线程时可能同步执行、
    /// 跳不出当前计算周期，`Task { @MainActor in }` 走协作式调度、落点由 executor 决定，
    /// 都不保证是主运行循环的下一拍。而我们要的正是「明确推迟到下一拍」，以稳妥避开
    /// Publishing changes from within view updates 警告。
    private func notifyIfFinished() {
        guard animatableData == targetValue else { return }
        let callback = onFinished
        DispatchQueue.main.async {
            callback()
        }
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

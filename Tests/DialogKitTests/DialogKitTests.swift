import Testing
import SwiftUI
@testable import DialogKit

/// 本类按顺序记下收到 didDismiss 的弹窗名字，用来检查收起回调有没有漏、顺序对不对
@MainActor
private final class DismissRecorder {
    /// 本属性按收到的先后保存弹窗名字
    var names: [String] = []
}

/// 本弹窗只用于测试：收到 didDismiss 时把自己的名字记进记录器
private struct RecordingDialog: DialogPresentable {
    /// 本属性是弹窗的名字，用来区分是哪个弹窗回调了
    let name: String
    /// 本属性是共用的记录器
    let recorder: DismissRecorder

    var body: some View { Color.clear }

    /// 本方法在收起动画播完后被调用，记下自己的名字
    func didDismiss() {
        recorder.names.append(name)
    }
}

/// 本方法把单例弹窗管理器清理干净，避免上一个测试留下的弹窗影响这一个
@MainActor
private func resetManager() {
    DialogManager.shared.dismissAll()
    DialogManager.shared.handleDismissAnimationFinished()
}

/// 弹窗 A 的退场动画还没播完，弹窗 B 展示后又被收起：A 和 B 都要收到 didDismiss，并且按收起顺序
@MainActor
@Test func dismissingAnotherDialogDuringDismissAnimationKeepsBothCallbacks() {
    resetManager()
    let manager = DialogManager.shared
    let recorder = DismissRecorder()

    manager.show(RecordingDialog(name: "A", recorder: recorder))
    manager.dismissCurrent()
    // A 还在退场，当前弹窗已经为空，B 会立刻展示
    manager.show(RecordingDialog(name: "B", recorder: recorder))
    manager.dismissCurrent()
    #expect(manager.isIdle == false)

    // 动画观察器只在最后那段退场动画播完时回调一次
    manager.handleDismissAnimationFinished()

    #expect(recorder.names == ["A", "B"])
    #expect(manager.isIdle)
}

/// 退场动画还没播完时调用 dismissAll：正在退场的和当前展示的都要收到 didDismiss，之后动画观察器再回调也不会重复发
@MainActor
@Test func dismissAllFlushesDialogsStillAnimatingOut() {
    resetManager()
    let manager = DialogManager.shared
    let recorder = DismissRecorder()

    manager.show(RecordingDialog(name: "A", recorder: recorder))
    manager.dismissCurrent()
    manager.show(RecordingDialog(name: "B", recorder: recorder))
    manager.dismissAll()

    #expect(recorder.names == ["A", "B"])
    #expect(manager.isIdle)

    manager.handleDismissAnimationFinished()
    #expect(recorder.names == ["A", "B"])
}

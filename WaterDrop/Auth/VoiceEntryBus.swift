import Foundation

/// 常驻语音入口的跨页面信号（F-017 §3.4 / 决策 D5）。
///
/// ## 为什么需要它
///
/// iOS 的三个列表页（物品 / 群组 / 提醒）都是通过 `navigationDestination`
/// 从 `MainView` **push** 进同一个 `NavigationStack` 的。所以「开口就能用」
/// 在 iOS 上的实现是：点列表页工具栏的语音按钮 → 退回主页 → 开始聆听。
///
/// 但 `MainViewModel` 是 `MainView` 的局部 `@State`，列表页拿不到它，
/// 也无从调用 `processVoiceInput`。退出导航可以用 `@Environment(\.dismiss)`，
/// **但 dismiss 之后由谁来发起聆听**需要一个跨页面的信号 —— 就是本类。
///
/// ## 为什么不用 NotificationCenter
///
/// 本仓已有 `AuthEventBus` 这个 `@Observable` 单例模式（见 `Auth/AuthEventBus.swift`），
/// 用法一致：`post` 置位、消费方 `consume` 复位。跟随既有约定，
/// 比引入第二种跨页面通信机制更不容易让下一个人困惑。
///
/// ## 为什么不用 `@Observable` 的 `didSet` 自动复位
///
/// 与 `AuthEventBus` 一致：显式 `consume`。因为「读取信号」与「消费信号」
/// 是两件事 —— 视图重绘会反复读取，但只应消费一次。
@Observable
final class VoiceEntryBus {
    static let shared = VoiceEntryBus()

    /// 为 true 表示「回到主页后应立刻开始聆听」。
    private(set) var pendingStartListening: Bool = false

    private init() {}

    func postStartListening() {
        Task { @MainActor in
            self.pendingStartListening = true
        }
    }

    /// 消费并复位。返回 true 表示调用方应发起一次聆听。
    @discardableResult
    func consumeStartListening() -> Bool {
        guard pendingStartListening else { return false }
        pendingStartListening = false
        return true
    }
}

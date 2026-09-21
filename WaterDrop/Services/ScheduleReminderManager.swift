import Foundation
import UserNotifications
import os.log

/// 本地提醒投递（F-012 ⑤ B-3.4）。
///
/// ## 为什么提醒在客户端做，而不是服务端推送
///
/// 服务端**没有任何代码**按 cron 触发 `schedules` 表 —— 它只负责**存 cron** 和
/// **算下一次触发时间**（`nextExecutionAt`，全服务端唯一的 cron 解析处，见决议 2）。
/// 真正的「到点弹通知」由这里用 `UNUserNotificationCenter` 完成。
///
/// 与 Android `ScheduleReminderScheduler` 同一套语义，但**平台差异很大**，逐条对照：
///
/// | | Android `AlarmManager` | iOS `UNUserNotificationCenter` |
/// |---|---|---|
/// | 重启后 | **全部丢失**，必须靠 `BootReceiver` 重建 | **系统代为持久化**，不需要重建 |
/// | 枚举已注册 | **没有 API**，只能自己记账 | `getPendingNotificationRequests` 直接列 |
/// | 数量上限 | 无硬上限（受系统策略影响） | **64 条**，超出静默丢弃 |
/// | 精确性 | Android 12+ 需特殊权限，否则可晚几十分钟 | 由系统调度，通常准时 |
/// | 重复触发 | 每次响完要重新注册 | 可用 `repeats: true` 真正重复 |
///
/// ⭐ **iOS 不需要 Android 那套本地登记表**：`getPendingNotificationRequests`
/// 能把已注册的通知连 `identifier` 一起列出来，所以反向清理、`cancelAll`
/// 都能直接从系统问，不必自己记账（Android 那边是迫不得已）。
///
/// ## 三条容易踩的坑
///
/// **1）`nextExecutionAt` 为 `null` 必须撤销通知。**
/// 服务端在**停用**和「cron 已无下次触发」两种情况下把这个字段置 `null`。
/// 忘了撤销 = 「停用了还会响」，这是本模块最容易出的 bug。
///
/// **2）64 条上限。**
/// 系统只保留**最早的 64 条**待触发通知，超出的**静默丢弃**（不报错、不提示）。
/// 所以 [rebuildAll] 按触发时间排序后主动截断，并记日志 —— 主动截断至少
/// 保证「留下的都是最近要响的」，而不是随机丢。
///
/// **3）没授权时 `add` 不报错。**
/// `add(_:withCompletionHandler:)` 在用户拒绝通知权限后**照样回调成功**，
/// 通知进不了系统队列也看不出来。所以授权状态必须由 UI 单独呈现（B-3.2），
/// 不能靠「注册没报错」推断「提醒会响」。
enum ScheduleReminderManager {

    private static let logger = Logger(subsystem: "com.yjqi.waterdrop.ios", category: "ScheduleReminder")

    /// 通知标识前缀。`identifier` 必须是**纯 `scheduleId`**（不加前缀），
    /// 否则撤销时要重新拼，两处不一致就漏。命名空间靠「服务端 id 是纯数字」
    /// 这个事实天然隔离，本地通知也只会由本模块创建。
    private static let maxPending = 64

    /// 提前量下限保护：`advanceMinutes` 算出来的时间若已接近/位于过去，
    /// 就**不注册**（而不是立刻弹一条）。
    ///
    /// 理由：立刻弹会把「用户三天前建的提醒，今天才打开 App」变成一次突然轰炸；
    /// 而下一次触发点服务端会在下次拉列表时重新算出，自然恢复。
    private static let minLeadSeconds: TimeInterval = 1

    // MARK: - 授权（B-3.2）

    /// 请求通知权限。
    ///
    /// ⚠️ **必须在「首次进入提醒页」时调用，不能在 App 启动时**。
    /// 启动就弹的话，用户还没看到任何提醒功能，只会顺手拒掉 —— 而 iOS 上
    /// **拒绝是一次性的**：之后 `requestAuthorization` 直接返回 `false`，
    /// 不再弹窗，只能引导用户去系统设置里手动打开。
    ///
    /// 已经决定过的用户再调不会重复弹窗（系统直接返回既有结果），所以
    /// 「每次进页面都调」也是安全的，这里就交给系统去幂等。
    ///
    /// - Returns: 是否已获授权。`false` 时 UI **必须明确告知**「提醒不会响」并给跳系统设置的入口。
    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("通知授权结果: \(granted)")
            return granted
        } catch {
            logger.error("请求通知授权失败: \(error.localizedDescription)")
            return false
        }
    }

    /// 当前授权状态（不弹窗）。
    ///
    /// 用 `notificationSettings()` 而不是缓存 `requestAuthorization` 的返回值：
    /// 用户可能在系统设置里**事后关掉**通知，那时缓存值就骗人了。
    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    // MARK: - 注册 / 撤销

    /// 按一条提醒的最新状态同步本地通知。
    ///
    /// - `nextExecutionAt` 是未来时间 → 注册（或覆盖）一条通知
    /// - `nextExecutionAt` 为 `null` / 已过去 → **撤销**
    /// - `enabled == false` → **撤销**（双保险：服务端此时也会给 `nil`，
    ///   但依赖单一字段容易被将来的改动破坏）
    ///
    /// 幂等：同一个 `identifier` 反复 `add` 会**替换**已有请求，不会重复。
    static func sync(_ schedule: ScheduleResponse) async {
        guard let scheduleId = schedule.id, !scheduleId.isEmpty else {
            logger.warning("提醒缺少 id，无法注册通知")
            return
        }

        guard schedule.isEnabled else {
            await cancel(scheduleId)
            return
        }

        guard let fireDate = triggerDate(of: schedule) else {
            // 停用 / cron 无下次触发 / 提前量已把时间推到过去 —— 三种都撤销
            await cancel(scheduleId)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = schedule.displayTitle
        if let description = schedule.description, !description.isEmpty {
            content.body = description
        } else if let taskTypeLabel = schedule.taskTypeLabel {
            content.body = taskTypeLabel
        }
        // 通知设置是**客户端自己的约定**，服务端不读不校验（见 ScheduleNotificationSettings）
        content.sound = (schedule.notificationSettings?.sound ?? true) ? .default : nil

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: scheduleId,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.debug("已注册提醒通知: \(scheduleId) @ \(fireDate)")
        } catch {
            logger.error("注册提醒通知失败: \(scheduleId) — \(error.localizedDescription)")
        }
    }

    /// 撤销一条提醒的本地通知。
    ///
    /// ⚠️ 删除提醒、停用提醒**都必须调它**。服务端删的是 `schedules` 行，
    /// **不会**去动客户端已注册的通知；不撤销的话通知会照常响，
    /// 指向一条已经不存在的提醒。
    ///
    /// `removePendingNotificationRequests` 对**不存在**的 id 是静默无操作，所以不必先查。
    static func cancel(_ scheduleId: String) async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [scheduleId])
        logger.debug("已撤销提醒通知: \(scheduleId)")
    }

    /// 用服务端的完整列表**整体重建**本地通知（App 启动时 / 拉过列表后）。
    ///
    /// ⭐ 关键在于**反向清理**：只对列表里的条目调 [sync] 是不够的。
    /// 那些**在服务端已被删除、已被停用，或属于上一个账号**的提醒，
    /// 本地通知还在但服务端列表里已经没有它们了 —— 没有任何一次 `sync` 会去碰它们，
    /// 于是它们照常响。这就是「幽灵提醒」。
    ///
    /// 所以先拿系统的待触发列表减去服务端列表，把差集撤销掉，再逐条同步。
    /// （这一点比 Android 省事：那边没有列举 API，得自己维护登记表。）
    ///
    /// ⚠️ **超过 64 条时按触发时间保留最近的 64 条**。系统对超出的部分是静默丢弃，
    /// 与其让它随机丢，不如自己按「谁先响」排序后主动截断。
    static func rebuildAll(_ schedules: [ScheduleResponse]) async {
        let incoming = Set(schedules.compactMap(\.id).filter { !$0.isEmpty })

        // 反向清理：本地待触发但服务端已经没有的（被删 / 被停用 / 换了账号）
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let ghostIds = pending.map(\.identifier).filter { !incoming.contains($0) }
        if !ghostIds.isEmpty {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: ghostIds)
            logger.debug("清理 \(ghostIds.count) 条幽灵提醒通知")
        }

        // 先算好触发时刻，按时间升序 —— 截断时留下的是「最近要响的」那批
        let scheduled: [(schedule: ScheduleResponse, fireDate: Date)] = schedules.compactMap { schedule in
            guard let fireDate = triggerDate(of: schedule) else { return nil }
            return (schedule, fireDate)
        }.sorted { $0.fireDate < $1.fireDate }

        if scheduled.count > maxPending {
            logger.warning("提醒数 \(scheduled.count) 超过系统上限 \(maxPending)，只注册最早的 \(maxPending) 条")
        }

        for entry in scheduled.prefix(maxPending) {
            await sync(entry.schedule)
        }
    }

    /// 撤销本地**全部**提醒通知。
    ///
    /// ⚠️ **退出登录时必须调用**：通知是**与账号无关的系统资源**，
    /// 不撤销的话，退出登录后（甚至换个账号登录后）上一个账号的提醒**照样会响**，
    /// 在通知栏里泄露前一个用户的数据。
    ///
    /// 调用点已收口在 ``AuthStateManager/clearAuthInfo()`` —— 登出与 token 失效
    /// 重登都会经过那里（`AuthService.logout` 与 `TokenRefreshHandler.handleRefreshFailure`），
    /// 所以不必（也不该）在各处重复调用。若将来出现不经过 `clearAuthInfo` 的
    /// 账号切换路径，需要在那边补一次。
    static func cancelAll() async {
        // 只撤 pending 而不是 removeAllPendingNotificationRequests()：
        // 后者会把未来任何模块加的通知一并清掉，越权太广。
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let ids = pending.map(\.identifier)
        guard !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        logger.info("撤销全部提醒通知（\(ids.count) 条）")
    }

    // MARK: - 内部

    /// 算出**本地通知实际该响的时刻**。
    ///
    /// 服务端给的 `nextExecutionAt` 是**触发时刻**，不含提前量；
    /// `notificationSettings.advanceMinutes` 是客户端自己的概念，在这里做减法。
    /// 返回 `nil` 表示不该注册。
    ///
    /// ⚠️ 解析格式：服务端业务字段是 ISO 8601 **不带时区后缀**的形式
    /// （`2026-09-19T09:00:00`，见 `ScheduleResponse` 注释），用 `ISO8601DateFormatter`
    /// 的默认选项**解不出来**（它要求带 `Z`）。所以这里用 `DateFormatter` 固定格式，
    /// 并按**本机时区**解释 —— 服务端存的就是用户本地时间，按本地解读才对齐。
    static func triggerDate(of schedule: ScheduleResponse) -> Date? {
        guard let next = schedule.nextExecutionAt, !next.isEmpty else { return nil }
        guard let base = parseServerDate(next) else {
            logger.warning("无法解析 nextExecutionAt: \(next)")
            return nil
        }

        let advanceMinutes = schedule.notificationSettings?.advanceMinutes ?? 0
        let fireDate = base.addingTimeInterval(-Double(advanceMinutes) * 60)

        guard fireDate.timeIntervalSinceNow > minLeadSeconds else {
            logger.debug("提醒 \(schedule.id ?? "?") 的触发时刻已在过去（或太近），不注册")
            return nil
        }
        return fireDate
    }

    /// 服务端业务时间字段的格式。**带 `T`、不带时区后缀、秒可选**。
    ///
    /// 两个 formatter 都试：有的值带毫秒（`2026-09-19T04:35:59.735174`，
    /// 见 §5.8 的 `executionTime`），有的不带。
    private static let serverFormatters: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"].map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            // 服务端存的是用户本地时间，按本机时区解读才对齐
            formatter.timeZone = TimeZone.current
            return formatter
        }
    }()

    /// 解析服务端业务时间字段。
    ///
    /// `internal`（非 `private`）：列表页展示「下次提醒」时也**解同一个格式**，
    /// 让它复用这一份 formatter —— 两处各写一套迟早会漂移
    /// （Android 那边 `ScheduleListActivity` 与 `ScheduleReminderScheduler`
    /// 就各自写了一份 ISO 解析）。
    static func parseServerDate(_ raw: String) -> Date? {
        for formatter in serverFormatters {
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}

import Foundation
import os.log

/// F-012 ⑥ (D-10)：活跃上报。
///
/// ## 为什么要节流
///
/// 服务端 `UserServiceImpl.reportUserActivity` 对 `user:activity:{userId}:{date}` 做的是
/// **increment**（累加计数），不是去重集合 —— 同一天上报 20 次，这条 key 的值就是 20。
/// `UserActivityService.getActiveUsers` 按「有没有这个 key」算活跃用户数，所以多报不会
/// 影响 DAU 的**人去重**；但 `getUserActivityStats` 的 `dailyActivity` 读的是**次数**，
/// 无脑上报会把它灌成几十倍。客户端的责任是别把脏数据写进去。
///
/// 所以：**每个用户每天最多上报一次**。按天而不是「每次冷启动」—— 后者在用户一天开
/// 20 次 App 时同样失真。
///
/// ## 为什么节流键是 `userId|date`
///
/// 只记日期的话，同一台设备上 A 登录上报过、登出、B 登录，B 当天就永远报不上。
/// 把 userId 一并存进去，换账号自然失配 → 正常上报，不需要在登出路径上挂清理钩子
/// （那种钩子正是最容易被后续改动漏掉的东西）。
///
/// ## 为什么失败静默
///
/// 活跃上报是**旁路统计**，不是业务动作。它失败了不该让用户看到任何东西 ——
/// 不弹提示、不重试、不阻塞导航。服务端那边也会把整个写入包在 try/catch 里只记日志，
/// 两端对这件事的态度是一致的。
enum HeartbeatReporter {
    private static let logger = Logger(subsystem: "com.waterdrop.ios", category: "Heartbeat")
    private static let lastReportKey = "heartbeat_last_report"

    /// 上报一次活跃（若今天尚未上报过）。幂等、可重复调用。
    ///
    /// 无登录态时直接返回：`API` 会带不上 Bearer，服务端只会回 401。
    static func reportIfNeeded() async {
        guard let userId = AuthStateManager.shared.getCurrentUserId(),
              AuthStateManager.shared.isAuthenticated else {
            return
        }

        let today = todayString()
        let stamp = "\(userId)|\(today)"
        if UserDefaults.standard.string(forKey: lastReportKey) == stamp {
            return
        }

        do {
            let response = try await AuthAPIService.reportHeartbeat()
            guard response.code == 200 else {
                logger.warning("活跃上报业务失败: \(response.message)")
                return
            }
            // 只有服务端确认成功才落节流标记 —— 先写后报的话，一次失败就把这一整天
            // 的上报机会用掉了。
            UserDefaults.standard.set(stamp, forKey: lastReportKey)
            logger.info("活跃上报成功")
        } catch {
            logger.warning("活跃上报失败: \(error.localizedDescription)")
        }
    }

    /// 本地日期（`yyyy-MM-dd`），按**本机时区**算。
    ///
    /// 不用 `ISO8601DateFormatter`：它默认输出 UTC，东八区用户晚上 8 点后就会算成
    /// 「第二天」，导致跨零点的那几小时重复上报或者漏报。
    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }
}

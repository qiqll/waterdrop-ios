import Foundation
import os.log

/// 提醒列表视图模型（F-012 ⑤ B-3.3）。
///
/// 与 Android `ScheduleListActivity` 一一对应：列表三态 → 建 / 改 / 删 / 启停，
/// 并在每次成功加载后把服务端状态同步到本地通知。
/// 服务端契约见 `wd_server/docs/api-reference.md` §5。
///
/// 三条铁律（与 `GroupListViewModel` 一致）：
///
/// 1. **一律按 `body.code` 分支，不看 HTTP 状态码**（缺陷 R）。
/// 2. **空列表是正常态**，必须与「加载失败」分开呈现。
/// 3. **`page` 从 0 开始**（本模块特有，群组那边是 1）—— 传 1 会静默跳过第一页。
///
/// 本类刻意不 `import UIKit` —— 以便放进 `WaterDropTests`。
/// （`ScheduleReminderManager` 只用 `UserNotifications`，同样与 UIKit 无关。）
@Observable
@MainActor
final class ScheduleListViewModel {

    /// 列表三态。`empty` 与 `failed` 必须分开：前者是「还没有提醒」，后者才该给重试。
    enum ListState {
        case loading
        case loaded
        case empty
        case failed
    }

    private(set) var schedules: [ScheduleResponse] = []
    private(set) var listState: ListState = .loading

    /// 提交在途（建/改/删/启停）。视图据此禁用按钮，避免连点重复提交。
    private(set) var isSubmitting = false

    /// 通知权限是否已开。`false` 时视图**必须**显示提示条 ——
    /// iOS 上没授权的话 `add` 请求会静默成功但通知永远不响（B-3.2）。
    private(set) var notificationsAuthorized = false

    var showEditor = false

    private(set) var noticeTitle = ""
    private(set) var noticeMessage = ""
    var showNotice = false

    private let logger = Logger(subsystem: "com.yjqi.waterdrop.ios", category: "ScheduleListViewModel")

    /// ⚠️ 服务端 `size` 上限 100（超过 → HTTP 422，不是 400）。一页取满。
    private static let pageSize = 100
    private static let maxPages = 100

    // MARK: - 加载

    /// 加载全部提醒（`GET /schedules`，翻页取全）。
    ///
    /// ⭐ 成功后立刻用这份权威状态重建本地通知（含清理幽灵通知）。
    /// 失败时**不能**拿空列表去 rebuild —— 网络失败不是「用户没有提醒」，
    /// 那会把用户所有提醒的通知当成幽灵清掉。
    ///
    /// **必须翻页取全**：只取第一页会让第 101 条之后的提醒既不显示也不注册，
    /// 而且不报错。
    func loadSchedules() async {
        listState = .loading
        do {
            var all: [ScheduleResponse] = []
            var page = 0
            while true {
                // ⚠️ page 从 0 开始（本模块特有）
                let response = try await ScheduleAPIService.getSchedules(page: page, size: Self.pageSize)
                guard response.code == 200 else {
                    logger.error("提醒列表业务失败: \(response.message)")
                    listState = .failed
                    return
                }
                let data = response.data
                all.append(contentsOf: data?.records ?? [])
                if all.count >= (data?.total ?? 0) || (data?.records.isEmpty ?? true) { break }
                page += 1
                if page > Self.maxPages { break }
            }
            schedules = all
            listState = all.isEmpty ? .empty : .loaded
            await ScheduleReminderManager.rebuildAll(all)
            await refreshAuthorizationState()
        } catch {
            logger.error("提醒列表加载失败: \(error.localizedDescription)")
            listState = .failed
        }
    }

    // MARK: - 权限（B-3.2）

    /// 首次进入提醒页时请求通知权限，并刷新 [notificationsAuthorized]。
    ///
    /// ⚠️ **不能在 App 启动时请求**：用户还没看到任何提醒功能就弹窗，会顺手拒掉，
    /// 而 iOS 的拒绝是**一次性**的 —— 之后系统不再弹窗，只能引导去设置里手动开。
    /// 已经决定过的用户再调不会重复弹（系统直接返回既有结果），所以每次进页面调也安全。
    func requestNotificationAuthorizationIfNeeded() async {
        _ = await ScheduleReminderManager.requestAuthorization()
        await refreshAuthorizationState()
    }

    /// 只读授权状态，不弹窗。从系统设置回来后调用它刷新提示条。
    func refreshAuthorizationState() async {
        notificationsAuthorized = await ScheduleReminderManager.isAuthorized()
    }

    // MARK: - 创建 / 更新

    /// 创建提醒（`POST /schedules`）。
    ///
    /// 成功后**重新拉列表**而不是本地拼一条：`nextExecutionAt` 是**服务端**算的
    /// （决议 2：cron 解析只在服务端一处），本地拼出来的条目必然缺它，
    /// 于是这条提醒注册不上通知。
    func createSchedule(
        title: String,
        description: String?,
        taskType: String,
        cronExpression: String
    ) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            presentNotice(title: "创建失败", message: "请填写提醒标题")
            return
        }
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let trimmedDesc = description?.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = try await ScheduleAPIService.createSchedule(
                title: trimmedTitle,
                taskType: taskType,
                cronExpression: cronExpression,
                enabled: true,
                description: (trimmedDesc?.isEmpty ?? true) ? nil : trimmedDesc,
                // 默认通知设置：响铃 + 震动 + 准点。服务端只存不读，
                // 形状是双端约定（见 ScheduleNotificationSettings）。
                notificationSettings: .default
            )
            guard response.code == 200, let created = response.data else {
                presentNotice(title: "创建失败", message: response.message)
                return
            }
            showEditor = false
            await loadSchedules()
            presentNotice(title: "创建成功", message: "提醒「\(created.displayTitle)」已创建")
        } catch {
            logger.error("创建提醒失败: \(error.localizedDescription)")
            presentNotice(title: "创建失败", message: "网络不可用，请检查网络后重试")
        }
    }

    /// 更新提醒（`PUT /schedules/{id}`）。
    ///
    /// ⚠️ **先撤销旧通知再提交**：万一提交失败，撤销反而是对的 ——
    /// 宁可少响一次，也不能让用户以为改成功了却还在旧时间响。
    /// 失败时把旧状态装回去（`sync`），别让一次提交失败静默废掉用户的提醒。
    ///
    /// `description` 传 `""` 即清空（服务端「传了就设」），所以这里不做 nil 兜底。
    func updateSchedule(
        _ existing: ScheduleResponse,
        title: String,
        description: String?,
        taskType: String,
        cronExpression: String
    ) async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            presentNotice(title: "保存失败", message: "请填写提醒标题")
            return
        }
        guard let scheduleId = existing.id, !scheduleId.isEmpty else { return }
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        await ScheduleReminderManager.cancel(scheduleId)

        do {
            var request = ScheduleUpdateRequest()
            request.title = trimmedTitle
            request.taskType = taskType
            request.cronExpression = cronExpression
            request.description = description ?? ""
            request.notificationSettings = existing.notificationSettings ?? .default

            let response = try await ScheduleAPIService.updateSchedule(scheduleId: scheduleId, request: request)
            guard response.code == 200 else {
                presentNotice(title: "保存失败", message: response.message)
                await ScheduleReminderManager.sync(existing)
                return
            }
            showEditor = false
            await loadSchedules()
            presentNotice(title: "已保存", message: "提醒「\(trimmedTitle)」已更新")
        } catch {
            logger.error("更新提醒失败: \(error.localizedDescription)")
            presentNotice(title: "保存失败", message: "网络不可用，请检查网络后重试")
            await ScheduleReminderManager.sync(existing)
        }
    }

    // MARK: - 启用 / 停用

    /// 切换开关（`POST /{id}/enable` / `POST /{id}/disable`）。
    ///
    /// ⚠️ 用**两个专用端点**而不是 `PUT {enabled: ...}` —— 服务端在这两个端点会
    /// 一并重算 `nextExecutionAt`（启用 → 算出下次时间；停用 → 置 `nil`），
    /// 而 `PUT` 走的是另一条路径。用 PUT 会让「停用后再启用」的提醒拿不到新时间。
    ///
    /// 读 `enabled` 判断当前状态，**不读 `taskStatus`**（派生字段）。
    /// 失败时**不本地翻转开关** —— 状态以服务端为准。
    func toggleSchedule(_ schedule: ScheduleResponse) async {
        guard let scheduleId = schedule.id, !scheduleId.isEmpty else { return }
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let willEnable = !schedule.isEnabled

        do {
            let response = if willEnable {
                try await ScheduleAPIService.enableSchedule(scheduleId: scheduleId)
            } else {
                try await ScheduleAPIService.disableSchedule(scheduleId: scheduleId)
            }
            guard response.code == 200 else {
                presentNotice(title: "操作失败", message: response.message)
                return
            }
            await loadSchedules()
        } catch {
            logger.error("切换提醒状态失败: \(error.localizedDescription)")
            presentNotice(title: "操作失败", message: "网络不可用，请检查网络后重试")
        }
    }

    // MARK: - 删除

    /// 删除提醒（`DELETE /schedules/{id}`），**不可逆，调用方须先确认**。
    ///
    /// ⚠️ 删除成功**必须撤销本地通知**：服务端删的是 `schedules` 行，
    /// 不会去动客户端已注册的通知，否则一条已不存在的提醒还会响。
    /// （列表加载时的 `rebuildAll` 反向清理也能兜住，但显式撤销能立刻失效。）
    func deleteSchedule(_ schedule: ScheduleResponse) async {
        guard let scheduleId = schedule.id, !scheduleId.isEmpty else { return }
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let response = try await ScheduleAPIService.deleteSchedule(scheduleId: scheduleId)
            guard response.code == 200 else {
                presentNotice(title: "删除失败", message: response.message)
                return
            }
            await ScheduleReminderManager.cancel(scheduleId)
            await loadSchedules()
            presentNotice(title: "已删除", message: "提醒「\(schedule.displayTitle)」已删除")
        } catch {
            logger.error("删除提醒失败: \(error.localizedDescription)")
            presentNotice(title: "删除失败", message: "网络不可用，请检查网络后重试")
        }
    }

    // MARK: - 弹窗

    private func presentNotice(title: String, message: String) {
        noticeTitle = title
        noticeMessage = message
        showNotice = true
    }
}

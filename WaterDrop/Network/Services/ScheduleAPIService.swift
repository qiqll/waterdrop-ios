import Foundation

/// 计划任务（提醒）API。
///
/// 对应服务端 `/api/schedules/*`（见 `wd_server/docs/api-reference.md` §5）。
/// 与 Android `ScheduleApiService.kt` 保持同一套契约：端点、字段名、错误码逐字一致。
///
/// ## 五条硬规则
///
/// 1. **一律按 `body.code` 分支，不看 HTTP 状态码**（全项目通例）。本模块尤其明显：
///    `POST /schedules/{id}/execute` 成功时 `data` 里还有个 `message`
///    字段长得像错误信息，别拿它判成败。
/// 2. **`page` 请求是 0-based，响应的 `current` 是 1-based，不要互相回填**。
///    所以下面所有分页方法的 `page` 默认值是 **`0`** 而不是 `1`
///    —— 这与 ``GroupAPIService`` 相反（那边服务端按 1-based 处理），照抄会整体偏移一页。
/// 3. **`nextExecutionAt` 是注册本地通知的唯一依据**：未来时间 → 按它注册，
///    `nil` → **撤销注册**。只有创建/更新/启用/停用这四个端点会重算它。
/// 4. **`taskStatus` 是派生字段**（恒等于 `enabled` → `ACTIVE`/`INACTIVE`），
///    **不要**用它判断开关，开关只看 `enabled`。
/// 5. **`POST /{id}/execute` 和 `POST /templates/{templateId}` 都不是它们名字听起来的样子**：
///    前者只记一条执行历史、**不产生任何通知**（别接到「测试提醒」按钮上）；
///    后者是降级实现（服务端没有模板表），等价于用默认值建一条普通提醒。
///
/// ## 错误码
///
/// | 场景 | HTTP | `code` |
/// |---|---|---|
/// | 任务不存在 / 不属于当前用户 | 404 | `12001` |
/// | cron 表达式非法 | 400 | `12002` |
/// | `page`/`size` 越界 | **422** | `400`（`VALIDATION_ERROR`） |
/// | 搜索不传 `keyword` | 400 | `400` |
///
/// 本模块所有端点都要登录态；`APIClient` 默认 `requiresAuth: true`，这里不逐条再写。
enum ScheduleAPIService {

    // MARK: - 增删改查

    /// 创建提醒（§5.1）。
    ///
    /// 服务端会**立刻算好 `nextExecutionAt`** 并回传（`enabled=false` 时为 `nil`）。
    /// 调用方拿到响应后必须按它注册/撤销本地通知 —— 不要自己算下次时间，
    /// cron 解析只在服务端一处（决议 2）。
    ///
    /// 失败：`400 / 12002` cron 非法。服务端消息是中文，直接透传。
    static func createSchedule(
        title: String,
        taskType: String,
        cronExpression: String,
        enabled: Bool = true,
        description: String? = nil,
        itemIds: [String]? = nil,
        notificationSettings: ScheduleNotificationSettings? = nil
    ) async throws -> ApiResponse<ScheduleResponse> {
        let request = ScheduleCreateRequest(
            title: title,
            taskType: taskType,
            cronExpression: cronExpression,
            enabled: enabled,
            description: description,
            itemIds: itemIds,
            notificationSettings: notificationSettings
        )
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.schedules,
            method: .POST,
            body: request
        )
    }

    /// 我的提醒列表（§5.2），0-based 分页。
    ///
    /// ⚠️ 翻页时把 UI 的页码**直接**传进来（第 1 页传 `0`）。渲染时**不要**拿
    /// 响应的 `current` 回填进 `page` —— 那样每翻一页都会整体偏移一页。
    ///
    /// `size` 上限 100，超过是 **422**（不是 400）。
    static func getSchedules(page: Int = 0, size: Int = 50)
        async throws -> ApiResponse<PagedResult<ScheduleResponse>> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.schedules,
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "size", value: String(size)),
            ]
        )
    }

    /// 提醒详情（§5.3）。不存在或不属于当前用户都是 `404 / 12001`。
    static func getSchedule(scheduleId: String) async throws -> ApiResponse<ScheduleResponse> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.scheduleById(scheduleId)
        )
    }

    /// 更新提醒（§5.4），部分更新语义。
    ///
    /// ⚠️ 服务端是「**传了就设**」：字段出现在请求体里就写入，**包括空串**。
    /// `JSONEncoder` 默认跳过 `nil` 字段，正好对应「不改」。想清空描述要显式传 `""`。
    ///
    /// 更新成功同样会重算 `nextExecutionAt`（cron 或 enabled 变了就跟着变），
    /// 调用方必须按响应重新注册本地通知。
    static func updateSchedule(scheduleId: String, request: ScheduleUpdateRequest)
        async throws -> ApiResponse<ScheduleResponse> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.scheduleById(scheduleId),
            method: .PUT,
            body: request
        )
    }

    /// 删除提醒（§5.5），**不可逆**。
    ///
    /// 服务端删的是 `schedules` 行，**不会**去动客户端已经注册好的本地通知 ——
    /// 撤销通知是调用方的责任，删之前（或删成功后）必须
    /// 按 `scheduleId` 撤销，否则闹钟会留成孤儿，一直响到用户重进 App 为止。
    static func deleteSchedule(scheduleId: String) async throws -> ApiResponse<EmptyData> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.scheduleById(scheduleId),
            method: .DELETE
        )
    }

    // MARK: - 启用 / 停用

    /// 启用提醒（§5.6）。
    ///
    /// ⚠️ 启用/停用是**两个独立端点**，不是 `PUT {enabled: ...}`。
    /// 只有这两个端点与创建/更新会重算 `nextExecutionAt`，
    /// 响应里带着新算好的时间，直接用它注册通知。
    static func enableSchedule(scheduleId: String) async throws -> ApiResponse<ScheduleResponse> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.scheduleEnable(scheduleId),
            method: .POST
        )
    }

    /// 停用提醒（§5.7）。响应里 `nextExecutionAt` 必为 `nil` —— 按它撤销本地通知。
    static func disableSchedule(scheduleId: String) async throws -> ApiResponse<ScheduleResponse> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.scheduleDisable(scheduleId),
            method: .POST
        )
    }

    // MARK: - 执行 / 模板 / 搜索

    /// 立即执行（§5.8）。**只往 `schedule_executions` 记一条，不产生任何通知。**
    ///
    /// 服务端目前**没有**查询执行历史的公开端点，写了也读不回来，所以这个接口
    /// 对用户没有可见效果 —— UI 上不要把它包装成「测试提醒」。
    static func executeSchedule(scheduleId: String)
        async throws -> ApiResponse<ScheduleExecutionResponse> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.scheduleExecute(scheduleId),
            method: .POST
        )
    }

    /// 从模板创建（§5.9）。**降级实现** —— `templateId` 服务端根本不读，
    /// 传任意值行为一致，等价于用给定字段建一条普通提醒。
    ///
    /// 要真正的「模板」得客户端自己维护模板列表，再用 ``createSchedule(title:taskType:cronExpression:enabled:description:itemIds:notificationSettings:)``。
    /// 本方法保留只为契约完整，**当前 UI 不接**。
    static func createFromTemplate(
        templateId: String,
        title: String? = nil,
        description: String? = nil,
        taskType: String? = nil,
        cronExpression: String? = nil,
        enabled: Bool? = nil
    ) async throws -> ApiResponse<ScheduleResponse> {
        let request = ScheduleTemplateRequest(
            title: title,
            description: description,
            taskType: taskType,
            cronExpression: cronExpression,
            enabled: enabled
        )
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.scheduleTemplate(templateId),
            method: .POST,
            body: request
        )
    }

    /// 搜索提醒（§5.10），按 `title` 匹配，0-based 分页。
    ///
    /// ⚠️ `keyword` **必填** —— 不传是 **HTTP 400**，不是「返回全部」。
    /// 空搜索请直接用 ``getSchedules(page:size:)``。
    ///
    /// 通配符 `%` / `_` / `\` 在服务端已按字面转义，客户端**不要**自己再转一次。
    static func searchSchedules(keyword: String, page: Int = 0, size: Int = 50)
        async throws -> ApiResponse<PagedResult<ScheduleResponse>> {
        return try await APIClient.shared.request(
            endpoint: ServerConfig.Endpoints.scheduleSearch,
            queryItems: [
                URLQueryItem(name: "keyword", value: keyword),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "size", value: String(size)),
            ]
        )
    }
}

/// 模板创建请求（§5.9）。全部可选，缺省时服务端用自己的默认值。
private struct ScheduleTemplateRequest: Encodable {
    let title: String?
    let description: String?
    let taskType: String?
    let cronExpression: String?
    let enabled: Bool?
}

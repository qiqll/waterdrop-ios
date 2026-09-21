import Foundation

// MARK: - 任务类型

/// 任务类型。
///
/// ⚠️ 服务端**不校验白名单**（`task_type` 是自由字符串，最长 100），
/// 这里只是三端自己的约定，保证 Android / iOS 展示一致。
/// 与 Android `object ScheduleTaskType` 逐字相同。
enum ScheduleTaskType {
    static let inventoryCheck = "INVENTORY_CHECK"
    static let maintenance = "MAINTENANCE"
    static let expiryWarning = "EXPIRY_WARNING"
    static let cleanup = "CLEANUP"
    static let custom = "CUSTOM"

    /// 下拉选项顺序。**这个顺序是承重的** —— 选择时按下标取值。
    static let all = [inventoryCheck, maintenance, expiryWarning, cleanup, custom]

    /// 中文名。未知取值（存量数据里的自由字符串）回退到原文，
    /// 不显示空白 —— 与 `GroupRole.label` 同策略。
    static func label(_ taskType: String?) -> String? {
        guard let taskType, !taskType.isEmpty else { return nil }
        switch taskType {
        case inventoryCheck: return "盘点"
        case maintenance: return "保养"
        case expiryWarning: return "到期提醒"
        case cleanup: return "清理"
        case custom: return "自定义"
        default: return taskType
        }
    }
}

// MARK: - Cron 预设

/// Cron 预设。
///
/// ⭐ **为什么不给用户一个自由输入框**：服务端用 Spring `CronExpression` 校验
/// （6 段、含秒位、末段 `?` 或 `*`），让用户在手机上敲 `0 0 9 * * ?` 既难输入又难理解，
/// 敲错了就是 400 / `12002`。从预设里选，**客户端就永远不需要构造或解析 cron**
/// —— 决议 2 要求 cron 解析只在服务端一处。
///
/// 与 Android `object ScheduleCronPreset` 的 `ALL` 逐项对应，**顺序也必须一致**。
enum ScheduleCronPreset {

    struct Preset {
        /// 6 段 cron 字面量，末段用 `?`（Spring 同时接受 `?` 与 `*`）。
        let cron: String
        /// 中文说明，直接展示给用户。
        let label: String
    }

    static let all: [Preset] = [
        Preset(cron: "0 0 9 * * ?", label: "每天 09:00"),
        Preset(cron: "0 0 12 * * ?", label: "每天 12:00"),
        Preset(cron: "0 0 20 * * ?", label: "每天 20:00"),
        Preset(cron: "0 30 8 * * ?", label: "每天 08:30"),
        Preset(cron: "0 0 9 ? * MON", label: "每周一 09:00"),
        Preset(cron: "0 0 9 ? * FRI", label: "每周五 09:00"),
        Preset(cron: "0 0 9 1 * ?", label: "每月 1 号 09:00"),
    ]

    /// 找不到匹配时给一个安全的默认（每天 09:00），保证「下次时间」永远是未来。
    static var defaultValue: Preset { all[0] }

    /// cron 字面量 → 中文说明。存量数据里的自造 cron 返回 `nil`，调用方回退显示原文。
    static func label(of cron: String?) -> String? {
        guard let cron else { return nil }
        let trimmed = cron.trimmingCharacters(in: .whitespaces)
        return all.first { $0.cron == trimmed }?.label
    }

    /// cron → 在 `all` 里的下标，供 Picker 回填。找不到返回 0。
    static func index(of cron: String?) -> Int {
        guard let cron else { return 0 }
        let trimmed = cron.trimmingCharacters(in: .whitespaces)
        return all.firstIndex { $0.cron == trimmed } ?? 0
    }
}

// MARK: - 响应

/// 提醒，对应服务端 `Schedule`（`api-reference.md` §5.11）。
///
/// ⚠️ **两组时间字段格式不同，不要混用**：
/// - `createTime` / `updateTime`：`BaseEntity` 的列，`yyyy-MM-dd HH:mm:ss`（**带空格**）
/// - `createdAt` / `updatedAt` / `lastExecutedAt` / `nextExecutionAt`：业务字段，
///   ISO 8601 `2026-09-19T09:00:00`（**带 `T`，且没有时区后缀**）
///
/// 所以这里**一律用 `String` 接**，由使用方按需解析。用 `Date` 接需要
/// 两套不同的 `DateFormatter`，而 `JSONDecoder` 只能配一种。
///
/// ⚠️ `createBy` / `updateBy` **是手机号**（本系统的登录标识），按 F-012 的既定决策
/// **不建模、不展示** —— 连属性都不给，杜绝以后有人顺手映射到 UI。
///
/// ⚠️ 这个结构体**刻意没有** `deleted`：查询结果恒为 `0`，建了只会诱导出
/// 「判断是否已删除」的错误逻辑。
struct ScheduleResponse: Codable, Identifiable, Hashable {
    let id: String?
    let title: String?
    let description: String?
    let taskType: String?
    let cronExpression: String?
    /// **判断开关只看这个字段。**
    let enabled: Bool?
    /// 归属用户 ID。服务端已按此过滤，正常不会拿到别人的。
    let userId: String?
    /// 派生字段，恒等于 `enabled`（`ACTIVE` / `INACTIVE`）。**不要用它判断开关。**
    let taskStatus: String?
    /// 关联物品 ID 列表。服务端存 JSON 文本，对客户端就是普通数组。
    let itemIds: [String]?
    /// 通知设置。服务端**不读**这个字段，只原样存 —— 形状由客户端约定（见 ``ScheduleNotificationSettings``）。
    let notificationSettings: ScheduleNotificationSettings?
    let createTime: String?
    let updateTime: String?
    let createdAt: String?
    let updatedAt: String?
    let lastExecutedAt: String?
    /// ⭐ **注册本地通知的唯一依据。** 未来时间 → 按它注册；`nil` → **撤销注册**。
    let nextExecutionAt: String?

    /// `ForEach` 的稳定标识。id 服务端必给，缺了兜一个常量 ——
    /// 宁可两行撞 id，也不要在解码正常数据时崩掉。
    var stableId: String { id ?? "unknown" }

    /// 展示用标题。
    var displayTitle: String {
        guard let title, !title.isEmpty else { return "未命名提醒" }
        return title
    }

    /// 开关状态。`nil` 视作停用（服务端必给，这里只是防御）。
    var isEnabled: Bool { enabled == true }

    var taskTypeLabel: String? { ScheduleTaskType.label(taskType) }

    /// cron 的中文说明；自造 cron 回退显示原文。
    var cronLabel: String {
        if let label = ScheduleCronPreset.label(of: cronExpression) { return label }
        guard let cronExpression, !cronExpression.isEmpty else { return "—" }
        return cronExpression
    }
}

/// 通知设置。
///
/// ⚠️ **服务端把这个对象当不透明 JSON 存**（`schedules.notification_settings`，
/// 最长 1024 字符），**不读、不校验、不解释**。形状完全由客户端决定 ——
/// 但 **Android / iOS 必须约定一致**，否则同一账号在两台设备上读到的是对方写的形状。
/// 与 Android `data class ScheduleNotificationSettings` 字段名逐字对应。
///
/// 加字段是安全的（老客户端解码时忽略多余的键）；**改字段名或语义**则要考虑存量数据。
struct ScheduleNotificationSettings: Codable, Hashable {
    /// 是否响铃。`nil` 视作 `true`。
    var sound: Bool?
    /// 是否震动。`nil` 视作 `true`。
    var vibrate: Bool?
    /// 提前多少分钟提醒（0 = 准点）。
    ///
    /// ⚠️ 客户端注册通知时**减去**这个值即可 —— 服务端的 `nextExecutionAt`
    /// 是**触发时刻**，不含提前量。做减法时注意别减成过去时间。
    var advanceMinutes: Int?

    static let `default` = ScheduleNotificationSettings(sound: true, vibrate: true, advanceMinutes: 0)
}

// MARK: - 请求

/// 创建提醒（§5.1）。
///
/// `title` / `taskType` / `cronExpression` / `enabled` **四项必填**，
/// 少一项服务端返回 400 并指出缺哪项。
struct ScheduleCreateRequest: Encodable {
    let title: String
    let taskType: String
    let cronExpression: String
    let enabled: Bool
    let description: String?
    let itemIds: [String]?
    let notificationSettings: ScheduleNotificationSettings?

    init(
        title: String,
        taskType: String,
        cronExpression: String,
        enabled: Bool = true,
        description: String? = nil,
        itemIds: [String]? = nil,
        notificationSettings: ScheduleNotificationSettings? = nil
    ) {
        self.title = title
        self.taskType = taskType
        self.cronExpression = cronExpression
        self.enabled = enabled
        self.description = description
        self.itemIds = itemIds
        self.notificationSettings = notificationSettings
    }
}

/// 更新提醒（§5.4），**全部字段可选**。
///
/// ⚠️ 服务端是「**传了就设**」语义：字段出现在请求体里就写入，**包括空串和空数组**。
/// 这正是 `description` 用 `String?` 而不是默认空串的原因 ——
/// 传 `nil` = 不改，传 `""` = 清空。其它字段同理。
///
/// `title` 例外：它有 NOT NULL 约束，传空串会被忽略、保留原值。
///
/// ⚠️ 另外，**不要**直接拿 ``ScheduleCreateRequest`` 当更新用：它的必填字段会强制
/// 每次都带上全部字段，而更新是部分语义，多余的字段会把值覆盖掉。
///
/// 编码细节：`JSONEncoder` 默认**不**输出 `nil` 字段（没有 `encodeIfPresent` 之外的开关），
/// 这正好符合服务端「字段没出现就是不改」的约定。注意这**与 Android 相反** ——
/// 那边 Gson 配了 `serializeNulls()`，null 会真的发出去，靠服务端按「未提供」处理。
/// 两端最终语义一致，只是达成路径不同。
struct ScheduleUpdateRequest: Encodable {
    var title: String?
    var description: String?
    var taskType: String?
    var cronExpression: String?
    var enabled: Bool?
    var itemIds: [String]?
    var notificationSettings: ScheduleNotificationSettings?
}

/// 「立即执行」的响应（§5.8）。⚠️ 只记一条历史，**不产生任何通知**。
struct ScheduleExecutionResponse: Codable {
    let scheduleId: String?
    let executionTime: String?
}

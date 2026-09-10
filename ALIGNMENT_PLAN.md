# iOS↔Android 对齐计划（P0 四项）

目标：让 iOS 端在「意图识别返回 UNKNOWN」「主题」「物品点击编辑」三块行为与 Android 基准对齐。Android 为基准，不改动 Android。

---

## 1. UNKNOWN 降级规则对齐（核心）

**当前 iOS 行为（错误）**：`IntentRecognitionService.recognizeIntent` 中，凡是在线识别返回 `.unknown`（无论成功与否），都无条件降级到本地关键词匹配。

**Android 规则（基准）**：只在**传输层/请求失败**时降级到本地（并置 `degraded=true`）；若服务端正常返回 `UNKNOWN`，直接保留 `UNKNOWN`，**不**用本地猜测。

### 改动 A — `IntentRecognitionService.swift`

**A1. `IntentResult` 增加 `degraded` 标志**（对齐 Android `IntentResult.degraded: Boolean = false`）：
```swift
struct IntentResult {
    let type: IntentType
    var itemName: String = ""
    var location: String = ""
    var category: String = ""
    var description: String = ""
    var storeTime: Date = Date()
    var storeUser: String = ""
    var queryText: String = ""
    var degraded: Bool = false   // 新增
}
```

**A2. 重写 `recognizeIntent`**（判断逻辑从「success-unknown 也降级」改为「仅 throw 才降级」）：
```swift
func recognizeIntent(text: String) async -> IntentResult {
    do {
        return try await recognizeIntentOnline(text: text)
    } catch {
        logger.error("Online intent recognition failed: \(error.localizedDescription)")
        return recognizeIntentLocal(text: text).copy(degraded: true) // 仅传输失败降级
    }
}
```
> 注：合入前确认为 `degraded` 赋值后的结果需返回 `IntentResult`（`IntentResult` 是 struct，可写 `var r = recognizeIntentLocal(...); r.degraded = true; return r`）。

**A3. `recognizeIntentOnline` 中 `code != 200 / data == nil`**：当前是非 throw 的 `guard ... else return IntentResult(.unknown)`。Android 此时是 **抛出 IOException**（业务错误也视为请求失败 → 触发降级）。这里有语义取舍：Android 把「HTTP 非 2xx」和「业务 code != 200」都当作失败进而降级。为忠实对齐，iOS 应同样在此处 `throw`。需在实现时决定：改为 `throw AiAPIError.businessError(...)`（走降级），而非返回 `.unknown`（走 UNKNOWN 分支）。**方案：抛出异常以对齐 Android** —— 服务器「失败」即降级，服务器「明确返回 UNKNOWN type」才保留 UNKNOWN。

### 改动 B — degraded 提示

Android 的降级提示是**文字前缀**（`processUserInput` 返回字符串前拼接），并非独立样式视图。

**采用 Method 1（文字前缀，Android 忠实）**：在 `IntentRecognitionService.processUserInput` 末尾，当 `intent.degraded` 且非 delete 前缀时，给返回字符串加前缀：
```swift
let reply = <原有 switch 结果>
if intent.degraded && !reply.hasPrefix(Self.deletePendingPrefix) {
    return "⚠️ 当前网络不佳，已使用离线识别（结果可能不准）\n\n\(reply)"
}
return reply
```
理由：Android 本身就是文字前缀；MainViewModel/MainView/ResultStateView 均可不动，改动最小、行为最贴近基准。Method 2（styled banner）需要动 MainViewModel + ResultStateView，与 Android 不一致，不采用。

### 改动 C — `ItemDTOs.swift` / 服务端（见第 3 节，与点击编辑合并）

---

## 2. 主题对齐（需用户决策）

**发现**：warm/neutral 双主题在**三端均只存在于数据定义，未真正实现**。iOS 的 `ThemeManager` 定义了 `warm/neutral` 枚举但**没有任何 View 读取它**；Android 的主题是「名存实亡」；neutral 调色板**在任何地方都不存在**。因此这不是「移植」，而是「**需从零设计 12+ 个颜色值**」。

**方案（需用户拍板）**：
- 新建 `Palette` struct，含 `.warm` / `.neutral` 两个实例。
- `ThemeManager` 增加 `var palette: Palette { currentTheme == .warm ? .warm : .neutral }`。
- 全项目批量替换约 64 处 `AppColors.` 引用为 `ThemeManager.shared.palette.`，涉及约 15 个文件。`@Observable` 依赖追踪使切换主题时全局自动重绘。
- 不推荐 `@Environment` 注入（工作量大）或 `static var` 薄别名（重绘可靠性弱）。

**决策点（向用户提出）**：neutral 冷调色板是新设计。选项：
- (a) 按既有的暖色系（绿 #5B7E6B / 米 #C4A882 / 橙 #E8A87C）做明度/饱和度近似的冷色版；
- (b) 完全另行设计一套冷色；
- (c) 本轮**暂缓主题**，只提交第 1、3 项（不影响未实现功能）。

> 若选 (a)/(b)，需新增 12+ 具体色值并确认；若选 (c)，主题作为单独后续任务。

---

## 3. 物品点击编辑（对齐 Android 编辑对话框）

**Android 基准**：`ItemListActivity.showEditDialog` —— 编辑位置/备注/状态（状态下拉「正常/已借出/已丢失/已损坏」→ int 1..4），保存后 `itemRepository.update(updated)` + Snackbar。

**iOS 现状**：
- `Item.swift` 有 `status: Int`（默认 1）、`remark: String?`。
- `ItemCardView.swift` 目前**无点击手势**，也不展示 status/remark。
- `ItemAPIService.updateItem(id:_:)` 已存在，PUT `items/{id}`，参数 `ItemCreateRequest`。

### 关键缺口：服务端 `ItemCreateRequest` 无 `status` 字段
- `ItemCreateRequest.java`（`wd_server/.../com/itemmanager/item/dto/ItemCreateRequest.java`）：**已确认无 `status` 字段**。`ItemServiceImpl.updateItem` 用 `BeanUtils.copyProperties(request, item, ...)`，DTO 缺失字段会被**静默忽略** → 服务端「改状态」目前是 no-op。
- 需在服务端 `ItemCreateRequest.java` 加 `private Integer status;`。
- 同时 iOS `ItemDTOs.swift` 的 `ItemCreateRequest` 加 `var status: Int?`（struct + init 参数 + init 赋值）。

### 改动清单
1. **服务端** `ItemCreateRequest.java`：加 `private Integer status;`。
2. **iOS** `ItemDTOs.swift` `ItemCreateRequest`：加 `var status: Int?`（含 init）。
3. **iOS** `ItemCardView.swift`：增加 `.onTapGesture` 打开编辑。
4. **iOS**（新增或复用）编辑对话框：编辑位置、备注、状态（Picker 单选 1..4，对应文字），保存调 `ItemRepository.update(id:_:)` 或对应 `ItemCreateRequest` 的 PUT。
5. **iOS** `ItemRepository.update(id:_:)` 已有，确认签名可传 status。

---

## 提交顺序

1. 第 1 项（UNKNOWN 对齐 + degraded 前缀）—— 纯 iOS，无需服务端。
2. 第 3 项（点击编辑）—— 需先改服务端 `ItemCreateRequest.java` + iOS DTO，再改 UI。
3. 第 2 项（主题）—— 待用户决策后单独进行。

## 验证清单
- [ ] 服务端正常返回 UNKNOWN type → iOS 显示「当前问题能力正在开发中」，**不**降级本地。
- [ ] 服务端请求失败/网络错误 → iOS 走本地匹配 + 显示「⚠️ 当前网络不佳…」前缀。
- [ ] 服务端 UNKNOWN 时删除等其它意图不受影响。
- [ ] 点击物品卡 → 编辑位置/备注/状态 → PUT 成功 → 列表刷新，状态持久化（服务端 DB 已更新 status）。

---

## 实现状态（截至 2026-08-30）

**第 1 项（UNKNOWN 降级规则对齐）— 代码已完成，`swiftc -parse` 全通过。**
- A1 `IntentResult.degraded` 标志：`IntentRecognitionService.swift:36`
- A2 仅 throw 时降级：`IntentRecognitionService.swift:52-59`
- A3 `code != 200 / data == nil` → 抛 `IntentRecognitionError.serverError`：`IntentRecognitionService.swift:76-78`
- B degraded 文字前缀：`IntentRecognitionService.swift:255-259`

**第 3 项（物品点击编辑）— 代码已完成，`swiftc -parse` 全通过。**
- 服务端 `ItemCreateRequest.java` 已有 `status`（第 54 行），**无需改动服务端**（原计划假设缺失，已纠正）。
- iOS `ItemCreateRequest` 已有 `status: Int?`（`ItemDTOs.swift:68`）+ init 参数（:88）。
- `ItemCardView.swift`：新增 `.onTapGesture` + `.sheet` 呈现编辑，`onUpdated` 回调刷新列表。
- `ItemEditSheetView.swift`（新增）：位置/备注输入 + 状态 Picker（1..4），保存回传全部 iOS 已知字段（规避 `BeanUtils.copyProperties` 拷贝 null），仅成功时 dismiss。
- `ItemListView.swift:41`：传入 `{ await viewModel.refreshItems() }`。
- `ItemRepository.update(id:_:)` 签名改为返回 `Bool`（仅 1 处调用 `ItemEditSheetView.swift:206`，无其它受影响方）。

**第 2 项（主题对齐）— 待用户决策（建议暂缓）。** 详见上文「需用户决策」。

> 验证受限：当前 active developer directory 为 CommandLineTools（非完整 Xcode），`xcodebuild` 不可用，只能用 `swiftc -parse` 做语法校验。行为验证需完整设备构建（`xcode-select -s /Applications/Xcode.app`）后进行。

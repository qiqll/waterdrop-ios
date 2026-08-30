# 水滴管家 iOS 客户端 · 开发进度文档

> 基于当前代码库（master @ `932d124`）逐文件分析生成 · 更新于 2026-08-30
> 完成度评估依据：**源码实际实现 + 编译验证（BUILD SUCCEEDED）**，非文档声明。

---

## 0. 总体进度

| 维度 | 状态 | 备注 |
|------|------|------|
| **整体功能完成度** | **~90%** | 核心业务闭环（语音→意图→CRUD）完整 |
| **编译** | ✅ 通过 | 本次实测 `BUILD SUCCEEDED`（模拟器、跳过签名） |
| **API 端点对接** | ✅ 17/17 | 与服务端 Controller 路径匹配 |
| **认证流程** | ⚠️ 代码完整，未真机验证 | 阿里云一键登录链路代码闭环 |
| **UI 覆盖** | ⚠️ 全部页面完成 | 但主题/字体落地不完整 |
| **运行时验证** | ⚠️ 未在模拟器实跑冒烟 | 本次仅静态分析 + 编译 |
| **代码签名** | ⚠️ 待配置 | `DEVELOPMENT_TEAM` 为空 |

**代码体量**：54 个 Swift 文件，约 3920 行。

---

## 1. 核心功能完成度

### 1.1 语音记录 / 查询 / 更新 / 删除（主线闭环）

| 功能 | 意图类型 | 实现 | 状态 |
|------|----------|------|------|
| 记录位置 | `RECORD_LOCATION` | `ItemRepository.recordItemLocation`（存在则更新，不存在则新建） | ✅ 完成 |
| 查询位置 | `QUERY_LOCATION` | `searchItemsByName` + 格式化结果 | ✅ 完成 |
| 更新位置 | `UPDATE_LOCATION` | `updateItemLocation`（仅改位置） | ✅ 完成 |
| 删除物品 | `DELETE_ITEM` | 5s 撤销 Snackbar，到时真正删除 | ✅ 完成 |
| 分类查询 | `QUERY_CATEGORY` | `getItemsByCategory` | ✅ 完成 |

**主流程链路**（`MainView` → `MainViewModel[processVoiceInput]` → `IntentRecognitionService` → `ItemRepository` → `ItemAPIService` → `APIClient`）已完整打通。

### 1.2 人工智能与语音

| 模块 | 实现 | 状态 |
|------|------|------|
| 在线意图识别 | `POST /ai/intent` + 本地关键词兜底 | ✅ 完成 |
| 本地意图兜底 | 关键词模式 + 9 类分类猜测 | ✅ 完成 |
| 语音识别 | `SFSpeechRecognizer(zh-CN)` 实时部分结果 | ✅ 完成 |
| 麦克风/语音权限 | iOS17 `AVAudioApplication.requestRecordPermission` | ✅ 完成 |
| AI 问答帮助 | `POST /ai/help` 聊天界面 | ✅ 完成 |

### 1.3 辅助功能

| 功能 | 实现 | 状态 |
|------|------|------|
| 物品清单浏览 | `ItemListView` 按分类分组 + 滑动删除 | ✅ 完成 |
| 数据导出 | `BackupManager.exportData` → ShareSheet | ✅ 完成 |
| 数据导入 | `fileImporter` + 逐条 insert | ✅ 完成 |
| 主题切换 | `ThemeManager`（warm/neutral） | ⚠️ **仅记录偏好，UI 未应用** |
| 字体大小调节 | `FontSizeManager`（16/20/24） | ⚠️ **仅 3 处 View 生效** |
| 昵称设置 | `UserPreferencesManager` | ✅ 完成 |
| 引导页 | `OnboardingView` 3 页 | ✅ 完成 |

---

## 2. 按模块逐项进度

### 2.1 网络层（✅ 完成）

- [x] `APIClient`（actor）：请求构建、状态码处理、5xx 重试、401 刷新重试
- [x] `TokenRefreshHandler`（actor）：并发 401 合并刷新
- [x] `NetworkError`：完整错误枚举 + 用户文案
- [x] 5 个 API Service：17 个端点齐全
- [ ] 超时/重试参数的运行时可配置性（当前为硬编码常量）

### 2.2 认证模块（✅ 代码完成，⚠️ 待真机验证）

- [x] `AuthService`：阿里云流程编排（5 步）
- [x] `AlicomFusionAuthManager`：SDK 回调 → async/await 桥接
- [x] `AuthStateManager`：登录态派生 + 过期判断
- [x] `TokenRefreshHandler`：刷新链路
- [x] `AuthEventBus`：强制登录广播
- [x] `KeychainManager`：敏感信息存储
- ⚠️ **未真机验证**：阿里云 SDK 需要真机 + 配置密钥才能实际跑通

### 2.3 业务服务（✅ 完成）

- [x] `IntentRecognitionService`：在线优先 + 本地兜底 + 分类猜测
- [x] `SpeechRecognitionManager`：完整状态机 + 权限处理
- [x] `BackupManager`：导出/导入

### 2.4 ViewModel 层（✅ 完成）

- [x] `MainViewModel`：三态切换 + 语音输入 + 删除撤销 + 自动复位
- [x] `ItemListViewModel`：分组 + 乐观删除 + 撤销
- [x] `HelpViewModel`：消息列表 + 加载态
- [x] `SettingsViewModel`：8 个状态字段 + 更新方法

### 2.5 View 层（✅ 全部页面完成）

- [x] `SplashView`：动画 + 登录态跳转
- [x] `LoginView`：一键登录 + 错误处理
- [x] `OnboardingView`：3 页引导
- [x] `MainView`：导航 + 三态卡片 + 撤销
- [x] `VoiceFabView`：按住/右滑/聆听模式手势
- [x] `ItemListView`：分组列表 + 滑动删除 + 空态
- [x] `HelpView`：聊天 UI
- [x] `SettingsView`：设置项 + 导入导出 sheet
- [x] 组件：`PulseAnimationView`/`UndoSnackbarView`/`ChatBubbleView`/`ItemCardView`/三态视图

### 2.6 设计系统（⚠️ 部分落地）

- [x] `AppColors`：完整色板（与 Android 对齐）
- [x] `ThemeManager`：主题偏好
- [x] `FontSizeManager`：字体偏好
- ⚠️ **主题未应用**：View 中未读取 `ThemeManager.currentTheme`，所有色板都是静态的
- ⚠️ **字体未全量应用**：仅 Idle/Listening/Result 三态视图使用 `currentFontSize`

---

## 3. 未实现 / 待办事项清单

### 3.1 上架前必须解决（P0）

| 优先级 | 事项 | 说明 |
|--------|------|------|
| 🔴 P0 | **HTTPS 迁移** | `SERVER_BASE_URL` 为 HTTP 明文，需切 HTTPS 并移除 ATS 例外 |
| 🔴 P0 | **代码签名配置** | `project.yml` 的 `DEVELOPMENT_TEAM` 为空，需填团队 ID 并重新 `xcodegen` |
| 🔴 P0 | **真机冒烟测试** | 阿里云一键登录、语音识别均需真机验证（模拟器不可靠） |
| 🔴 P0 | **阿里云密钥补全** | `ALICLOUD_APP_SECRET`、`ALICLOUD_AUTH_SDK_INFO` 为空，需确认是否必填 |

### 3.2 体验增强（P1）

| 优先级 | 事项 | 说明 |
|--------|------|------|
| 🟠 P1 | 主题切换落地 | 让 `AppColors` 根据 `ThemeManager.currentTheme` 生成不同色板 |
| 🟠 P1 | 字体大小全量生效 | 当前仅 3 处 View 应用，其余界面仍固定字号 |
| 🟠 P1 | 物品图片 | `Item.imageUrl` 字段存在，未实现拍照/上传 |

### 3.3 工程优化（P2）

| 优先级 | 事项 | 说明 |
|--------|------|------|
| 🔵 P2 | 补充单元测试 | 项目无任何测试 target |
| 🔵 P2 | 清理 `build/` | 存在 `yjqi` 路径的陈旧构建产物 |
| 🔵 P2 | UI 测试 | 无 UI 测试 target |

---

## 4. 各阶段完成情况（对应 plan.md 的 Phase）

对照 `plan.md` 的三阶段开发计划：

| 阶段 | 内容 | 状态 |
|------|------|------|
| **Phase 1** | 项目骨架 + 配置 + 网络层 + 认证层 | ✅ 完成 |
| **Phase 2** | Splash/Login/Onboarding 页面 | ✅ 完成 |
| **Phase 3** | 主界面 + 语音交互（核心） | ✅ 完成 |
| **Phase 4** | ItemList 清单 | ✅ 完成 |
| **Phase 5** | Help 帮助中心 | ✅ 完成 |
| **Phase 6** | Settings 设置 | ✅ 完成 |

**结论**：`plan.md` 规划的所有功能均已实现并编译通过，处于**可运行/可联调状态**。

---

## 5. 质量与风险小结

### 5.1 做得好的

1. **架构清晰**：MVVM 分层严格，`View → ViewModel → Repository → APIService → APIClient` 无跨层依赖
2. **并发设计严谨**：`actor` + `CheckedContinuation` 处理 Token 刷新合并
3. **可靠性**：5xx 指数退避重试、意图识别本地兜底、删除乐观更新 + 撤销
4. **与 Android 对齐**：色板、字体、功能均对标 Android 端
5. **配置外置**：环境切换无需改代码

### 5.2 风险点

1. 主题、字体两个"看起来做了"的功能实际未完全落地
2. 认证流程依赖 SDK 真机 + 密钥，存在隐性阻塞
3. HTTP 明文 + 空签名团队，阻断上架

---

## 6. 构建/验证记录

| 项 | 结果 |
|----|------|
| `xcodegen` 生成项目 | ✅（项目文件存在） |
| 模拟器编译（code signing off） | ✅ **BUILD SUCCEEDED** |
| API 端点与服务端匹配 | ✅ 17/17 |
| 静态代码分析 | ✅ 已逐文件审查 |
| 运行时冒烟测试 | ⏳ 未执行（无模拟器运行） |

# 水滴管家 iOS 客户端 · 系统架构文档

> 基于当前代码库（master @ `932d124`）逐文件分析生成 · 更新于 2026-08-30
> 本文只描述**代码实际实现**的架构，不包含设计中规划但尚未落地的部分。

---

## 1. 项目定位与三端协同

**水滴管家（WaterDrop）** 是一款 AI 驱动的个人物品位置管理应用。用户通过**语音指令**记录、查询、更新、删除物品存放位置，由 AI 意图识别引擎理解自然语言并执行。

本仓库是 **iOS 客户端**，与 Android 端、Spring Boot 服务端协同工作，目标是三端功能一致、界面一致、体验一致。

| 模块 | 路径 | 技术栈 |
|------|------|--------|
| **iOS 客户端**（本项目） | `.../waterdrop_ios` | SwiftUI + MVVM + `@Observable`，iOS 17.0+ |
| **Android 客户端** | `.../waterdrop` | Kotlin + Retrofit + Room + Coroutines |
| **服务端** | `.../wd_server` | Spring Boot 3.2.0 + Java 17 + MySQL |

三端通过 HTTP/JSON 通信，客户端调用的所有端点与服务端 Controller 保持一致。

> 注意：CLAUDE.md 与 DESCRIPTION.md 中记录的路径用户的绝对路径是 `/Users/yjqi/...`，但本机器当前工作目录为 `/Users/yjhome/...`（build 产物也记录了 `yjqi` 路径），说明项目在迁移/账户切换后仍能正常生成与编译。

---

## 2. 客户端整体分层架构（MVVM）

```
┌────────────────────────────────────────────────────────────┐
│                        View (SwiftUI)                       │
│  Splash · Login · Onboarding                                 │
│  Main (Idle/Listening/Result 三态) · VoiceFab                │
│  ItemList · Help · Settings · 14 个 View 文件                │
└──────────────────────────┬─────────────────────────────────┘
                           │ @Observable 绑定
┌──────────────────────────▼─────────────────────────────────┐
│                       ViewModel                             │
│  MainViewModel · ItemListViewModel                          │
│  HelpViewModel · SettingsViewModel                          │
│  (AppNavigationState 驱动导航)                               │
└──────────────────────────┬─────────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────────┐
│              Repository / Service（业务逻辑层）              │
│  ItemRepository · IntentRecognitionService                  │
│  SpeechRecognitionManager · BackupManager                   │
└──────────────────────────┬─────────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────────┐
│                    Network Layer                            │
│  APIClient (actor) · TokenRefreshHandler (actor)            │
│  5 个 API Service（Item/Ai/Auth/Alicloud/Help）              │
│  NetworkError                                              │
└──────────────────────────┬─────────────────────────────────┘
                           │ URLSession
                    ┌──────▼──────┐
                    │  服务端 REST API │
                    └─────────────┘

侧链：AuthStateManager / AuthService / AlicomFusionAuthManager（认证域）
      ThemeManager / FontSizeManager / UserPreferencesManager（偏好域）
      KeychainManager（安全存储）
```

**数据流向**：`View → ViewModel → Repository → APIService → APIClient → 服务端`

---

## 3. 代码结构总览

### 3.1 目录与文件统计

源码位于 `WaterDrop/`，共 **54 个 Swift 文件**，约 **3920 行**。

| 目录 | 职责 | 文件数 | 说明 |
|------|------|--------|------|
| `App/` | 应用入口与导航编排 | 1 | `WaterDropApp.swift` + `AppNavigationState` |
| `Auth/` | 认证域 | 5 | 阿里云一键登录 + Token 生命周期 |
| `Config/` | 运行配置 | 2 | Info.plist 读取 + 端点常量 |
| `Models/` | 数据模型 | 2 | Item、ChatMessage |
| `Models/DTOs/` | 请求/响应 DTO | 6 | Api/Auth/Item/Ai/Alicloud/Help |
| `Network/` | 网络层 | 6 | APIClient/TokenRefresh/NetworkError + 5 Service |
| `Repositories/` | 物品数据仓库 | 1 | ItemRepository |
| `Services/` | 业务服务 | 3 | 意图识别/语音识别/备份 |
| `ViewModels/` | 视图模型 | 4 | Main/ItemList/Help/Settings |
| `Views/` | 视图 | 14 | 8 个页面 + 组件 |
| `Theme/` | 设计系统 | 3 | 色板/主题/字体 |
| `Utilities/` | 工具 | 2 | 设备信息/用户偏好 |
| `Extensions/` | 扩展 | 2 | Color+Hex/Date+Formatting |

另有 `Frameworks/`（阿里云预编译 SDK）、`Configs/`（xcconfig 密钥）、`project.yml`（XcodeGen 配置）。

### 3.2 顶层依赖关系（模块间引用）

```
View ──▶ ViewModel ──▶ Repository ──▶ APIService ──▶ APIClient
  │           │              │                           │
  │           │              └── ItemRepository          │
  │           │                                         │
  │           ├── IntentRecognitionService（单例）        │
  │           │        └── ItemRepository + AiAPIService │
  │           │                                          │
  └── SpeechRecognitionManager（@Observable）
```

认证域是独立支线，被 App 层、`IntentRecognitionService`（取当前用户名）和网络层（注入 Token）消费。

---

## 4. 网络层设计

### 4.1 APIClient（actor 单例）

`APIClient.shared` 是网络层核心，用 `actor` 保证并发安全。

**核心方法**：
```swift
func request<T: Decodable>(
    endpoint: String,
    method: HTTPMethod = .GET,
    body: (any Encodable)? = nil,
    queryItems: [URLQueryItem]? = nil,
    requiresAuth: Bool = true
) async throws -> ApiResponse<T>
```

**行为**：
- **请求头**：`Accept`、`Content-Type`、`User-Agent`、`X-Client-Platform: iOS`、`X-Request-ID`（UUID）、`Authorization: Bearer <token>`（`requiresAuth=true` 时）
- **状态码处理**：
  - `2xx`：解码 `ApiResponse<T>`
  - `401`：抛 `unauthorized` → 网络层捕获后尝试刷新 Token → 重试原请求
  - `400...499`：不重试，尝试解码为 `businessError(code, message)`
  - `500...599`：指数退避重试，最多 3 次（1s / 2s）
- **超时**：读 30s（`ServerConfig.Timeout.read`），资源 60s
- **类型擦除**：`AnyEncodable` 把 `any Encodable` 包装进 `Encoder`

### 4.2 TokenRefreshHandler（actor 单例）

专门处理并发 401 刷新合并。刷新进行中时，后续进来的请求通过 `CheckedContinuation` 挂起，刷新完成后统一唤醒。刷新失败则清空 Keychain 并 `postLoginRequired()`。

### 4.3 NetworkError

```
unauthorized          → "认证已过期，请重新登录"
serverError(status)   → "服务器繁忙，请稍后重试"
networkUnavailable    → "网络连接失败，请检查网络设置"
timeout               → "连接超时，请稍后重试"
decodingFailed        → "数据解析失败"
invalidResponse       → "服务器响应异常"
businessError(code,msg)→ 服务端返回的自定义消息
unknown               → "未知错误，请稍后重试"
```

### 4.4 API 端点对接情况

客户端通过 5 个 API Service 调用 **17 个端点**（与 `TECH.md` 核对一致，均为已验证匹配）：

| Service | 端点 | 方法 |
|---------|------|------|
| `AuthAPIService` | `/users/refresh` `/users/logout` `/users/profile` | POST/POST/GET |
| `AlicloudAuthAPIService` | `/users/aliyun/auth-token` `/users/aliyun/login` | POST/POST |
| `ItemAPIService` | `/items` `/items/{id}` `/items/search` `/items/search/by-name` `/items/category/{category}` | GET/POST/PUT/DELETE |
| `AiAPIService` | `/ai/intent` `/ai/usage/today` | POST/GET |
| `HelpAPIService` | `/ai/help` `/ai/help/history` | POST/GET |

---

## 5. 数据模型层

### 5.1 响应包装（ApiResponse.swift）

```swift
struct ApiResponse<T: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: T?
    let timestamp: String?
    let traceId: String?
}
struct PagedResult<T: Decodable>: Decodable {
    let records: [T]; let total: Int; let size: Int; let current: Int; let pages: Int
}
struct EmptyData: Decodable {}
```

### 5.2 物品核心模型（Item.swift）

```swift
struct Item: Codable, Identifiable, Equatable {
    let id: String
    let name: String          // 物品名
    let location: String      // 存放位置
    var category: String      // 分类
    var description: String
    var createTime: String
    var updateTime: String
    var imageUrl: String?
    var status: Int           // 1=有效
    var remark: String?
    var operatorUser: String
}
```

### 5.3 DTO → 领域模型映射

服务端 `ItemDto` 字段更丰富（brand/model/value/warranty/quantity 等约 23 个字段），客户端通过 `toItem()` 映射为精简的 `Item`。`ItemCreateRequest` 则携带完整字段集，用于创建/更新时把可选字段透传给服务端。

### 5.4 其他模型

- `ChatMessage`：帮助中心聊天消息（id/content/isUser/inScope/isError/timestamp）
- 6 个 DTO 文件承载全部请求/响应结构

---

## 6. 认证与 Token 生命周期

### 6.1 阿里云号码一键登录流程

```
用户点击"一键登录"
  │
  ▼
1. AuthService.performAlicloudAuthentication()
     ├─ POST /users/aliyun/auth-token   ──► 服务端返回 authToken
     ▼
2. AlicomFusionAuthManager.initialize(authToken)  初始化 SDK
     ▼
3. SDK 后台 token 鉴权 → onSDKTokenAuthSuccess (isSDKReady=true)
     ▼
4. startLoginScene(from: VC)  拉起 SDK 授权页，用户确认本机号码
     ▼
5. onVerifySuccess(maskToken)  SDK 返回掩码 token（continuation 唤醒）
     ▼
6. POST /users/aliyun/login (maskToken + deviceId)  ──► 换取 accessToken/refreshToken
     ▼
7. AuthStateManager.saveAuthInfo() 存入 Keychain
     ▼
首次登录 → Onboarding；老用户 → Main
```

### 6.2 关键实现（AlicomFusionAuthManager.swift）

- 把 ObjC SDK 的回调通过 `CheckedContinuation` 桥接为 `async/await`
- `AlicomFusionAuthHandler` 用 `@unchecked @retroactive Sendable` 适配 Swift 并发
- `onSDKTokenUpdate` 回调中同步取新 token（用 `DispatchSemaphore` 阻塞 SDK 后台线程）
- 错误映射为 `AlicomFusionError`（sdkNotReady/tokenAuthFailed/verifyFailed/userCancelled/unknown）

### 6.3 Token 生命周期与刷新

```
访问受保护接口（requiresAuth=true）
   │ APIClient 注入 Bearer accessToken
   ▼
遇 401 ──► TokenRefreshHandler.refreshTokenIfNeeded() （并发合并）
   │         ├─ 进行中的刷新被 continuation 挂起
   │         └─ POST /users/refresh → 更新 Keychain → 唤醒 → 重试原请求
   ▼
刷新失败 ──► clearAuthInfo() → AuthEventBus.postLoginRequired() → App 跳登录页
```

### 6.4 AuthStateManager

`@Observable` 单例，维护 `AuthState` 枚举（`unauthenticated`/`authenticated`/`expired`），从 Keychain 派生初始状态。Token 存 Keychain 的 `kSecAttrAccessibleAfterFirstUnlock`。

---

## 7. 业务服务层

### 7.1 IntentRecognitionService（意图识别）

单例，核心流程：**在线识别优先，失败后本地关键词兜底**。

```
用户文本
   │
   ▼
1. 在线识别：POST /ai/intent（AiAPIService.recognizeIntent）
   │  成功且 type != unknown ──► 返回结构化意图
   │  失败/unknown ──► 继续
   ▼
2. 本地兜底：关键词模式匹配（recognizeIntentLocal）
   │  - RECORD_LOCATION：含"放在/放到/在/记录" → 提取物品名+位置
   │  - QUERY_LOCATION：含"在哪/哪里有/放哪了/查询/找"
   │  - UPDATE_LOCATION：含"现在在/移动到/搬到"
   │  - DELETE_ITEM：含"删除/移除"
   │  - QUERY_CATEGORY：含"查看所有/查询所有/所有的"
   ▼
3. 分类猜测（guessCategory）：物品名匹配 9 大分类关键词库
   （文具/电子产品/证件/衣物/厨房用品/书籍/工具/药品/珠宝首饰）
   ▼
4. DELETE_ITEM：暂存待删物品（consumePendingDeleteItem），交由 UI 5s 撤销
```

**意图类型**：`RECORD_LOCATION / QUERY_LOCATION / UPDATE_LOCATION / DELETE_ITEM / QUERY_CATEGORY / UNKNOWN`

### 7.2 SpeechRecognitionManager（语音识别）

`@Observable`，基于 `SFSpeechRecognizer(locale: zh-CN)`。

**状态机**：`idle → preparing → listening → processing → finished`（或 `error`）

- 权限：iOS 17+ 用 `AVAudioApplication.requestRecordPermission`
- 音频会话：`.record + .measurement + .duckOthers`，buffer 1024
- 实时部分结果：`partialText` 边听边显示
- 忽略用户取消错误（`kAFAssistantErrorDomain` code 216）

### 7.3 BackupManager（导入导出）

- **导出**：把 `ItemRepository.allItems` 编码为 JSON，写入临时目录，返回 URL
- **导入**：读取 JSON → 逐条 `insert` 到服务端 → 返回导入条数

---

## 8. ViewModel 层

### 8.1 MainViewModel（核心）

管理主界面三态（`idle / listening / result`）与语音处理：

| 职责 | 实现 |
|------|------|
| 语音输入 | `processVoiceInput()` → `IntentRecognitionService.processUserInput()` |
| 删除撤销 | `scheduleDelete(item)` → 5s 定时器 → `confirmDelete()`；`cancelDelete()` 撤销 |
| 自动复位 | 结果展示 5s 后 `resetToIdle()` |
| 待删物品 | `pendingDeleteItem` + `flushPendingDelete()`（页面消失时兜底） |

### 8.2 ItemListViewModel

- `groupedItems`：按 category 分组排序
- `scheduleDelete`：从本地列表**立即移除**（乐观更新），5s 后确认删除；`cancelDelete` 恢复

### 8.3 HelpViewModel / SettingsViewModel

- Help：发送问题 → `HelpAPIService.askHelp` → 追加 AI 消息（含 inScope 标记）
- Settings：昵称/主题/字体/导入导出共 8 个状态字段，`update*` 方法写入偏好

---

## 9. View 层（8 个页面 + 组件）

| 视图 | 文件 | 职责 |
|------|------|------|
| **Splash** | `SplashView.swift` | 水滴掉落动画，结束后按登录态跳转 |
| **Login** | `LoginView.swift` | 阿里云一键登录按钮；`ViewControllerAccessor` 获取宿主 VC |
| **Onboarding** | `OnboardingView.swift` | 3 页引导（TabView pagestyle） |
| **Main** | `MainView.swift` | 导航编排 + 三态卡片 + 撤销 Snackbar |
| **VoiceFab** | `VoiceFabView.swift` | 按住说话/右滑聆听模式的悬浮麦克风 |
| **ItemList** | `ItemListView.swift` | 分类分组列表 + 滑动删除 + 空状态 |
| **Help** | `HelpView.swift` | AI 问答聊天界面 |
| **Settings** | `SettingsView.swift` | 昵称/主题/字体/导入导出/登出 |

**复用组件**：`PulseAnimationView`（脉冲动画）、`UndoSnackbarView`（撤销条）、`ChatBubbleView`（聊天气泡）、`IdleStateView` / `ListeningStateView` / `ResultStateView`（主界面三态）、`ItemCardView`（物品卡片）。

---

## 10. 设计系统（Theme）

### 10.1 色板（AppColors.swift，55 行）

与 Android `colors.xml` 逐像素对齐。

- **主色**：`primary = #5B7E6B`（雾松绿）、`primaryVariant = #476256`、`primaryLight = #E8F0EB`
- **次色**：`secondary = #C4A882`（暖沙金）、`secondaryVariant = #A68B6A`
- **强调色**：`accent = #E8A87C`（杏色，FAB 专属）
- **语义色**：success `#5B9A6B` / warning `#E5A84B` / error `#C75450` / info `#5B8EC7`（各带背景浅色）
- **中性色**：暖灰 10 级（`neutral0` 白 → `neutral900` 近黑）
- **Surface**：`background=#FAFAF8` / `surface=白` / `surfaceVariant=#F5F3F0`
- **录音态**：`recordingActive = #C75450`，脉冲 `recordingPulse`（20% 透明度）

### 10.2 主题与字体

- `ThemeManager`：`warm / neutral` 两个主题，存 `UserDefaults`
- `FontSizeManager`：`small(16pt) / medium(20pt) / large(24pt)`，默认 small

---

## 11. 账号偏好与设备信息

- `UserPreferencesManager`：昵称（存 `UserDefaults`，默认"用户"）
- `DeviceInfo`：`deviceId`（`identifierForVendor` 或随机 UUID）、platform、systemVersion、deviceModel

---

## 12. 工程构建配置

### 12.1 技术栈

| 维度 | 选型 |
|------|------|
| UI | SwiftUI |
| 最低版本 | iOS 17.0 |
| 架构 | MVVM |
| 异步 | Swift Concurrency (async/await) |
| 状态管理 | `@Observable` |
| 网络 | URLSession（原生） |
| JSON | Codable（原生） |
| 安全存储 | Keychain |
| 语音识别 | Apple Speech（SFSpeechRecognizer zh-CN） |
| 认证 SDK | AlicomFusionAuth（阿里云） |
| 工程生成 | XcodeGen |
| Swift 版本 | 5.9 |

### 12.2 构建方式

```bash
# 生成工程（由 project.yml）
xcodegen generate

# 编译（模拟器，跳过签名）— ✅ 本次已验证 BUILD SUCCEEDED
xcodebuild -project WaterDrop.xcodeproj -target WaterDrop \
  -sdk iphonesimulator -configuration Debug \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

> 本次分析过程中用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 在命令行实际编译通过。

### 12.3 阿里云 SDK 集成要点

- SDK 位于 `Frameworks/`，通过 `BridgingHeader.h` 导入
- 链接：`-ObjC` + `AlicomFusionAuth / UMCommon / UMDevice` 三个 framework
- `AlicomFusionAuth.framework` 需 `embed=true`，其余 `embed=false`
- 依赖系统框架：CoreTelephony、SystemConfiguration；库：libc++、libz
- 三个 `.bundle`（ATAuthSDK / AlicomCaptcha4）作为 resources 打包

### 12.4 配置项（Configs/Secrets.xcconfig → Info.plist）

接线由 `project.yml` 的 `configFiles` 声明，xcodegen 生成时落到**工程级** `baseConfigurationReference`：

```yaml
configFiles:
  Debug: Configs/Secrets.xcconfig
  Release: Configs/Secrets.xcconfig
```

取值链路：`Configs/Secrets.xcconfig` → 构建设置 → `Info.plist` 的 `$(VAR)` 占位 → `Bundle.main`（`AppConfig`）。

> ⚠️ **这条链路断掉不会编译失败**，只会让 `Info.plist` 里出现空串。因此 `AppConfig.infoPlistValue`
> 把空串一律当「未配置」返回 `nil`，使 `??` 兜底和 Debug 断言能真正生效。
> 这正是 F-014 能长期潜伏的原因（详见 §14.8）。

`Configs/Secrets.xcconfig` 已被 gitignore，新克隆需从 `.example` 复制后填值：

```bash
cp Configs/Secrets.xcconfig.example Configs/Secrets.xcconfig
```

| Key | 说明 |
|-----|------|
| `SLASH` | 固定为 `/`。xcconfig 把 `//` 当行内注释，URL 里的斜杠只能用它拼出来 |
| `SERVER_BASE_URL` | 服务端地址，形如 `http:$(SLASH)$(SLASH)<host>:8080$(SLASH)api$(SLASH)` |
| `ALICLOUD_APP_KEY` | 阿里云 AppKey（真值不入库） |
| `ALICLOUD_SCHEME_CODE` | 一键登录场景码（真值不入库） |
| `ALICLOUD_APP_SECRET` / `ALICLOUD_AUTH_SDK_INFO` | 当前为空 |

自检：

```bash
xcodebuild -project WaterDrop.xcodeproj -target WaterDrop -configuration Debug -showBuildSettings \
  | grep SERVER_BASE_URL    # 应有非空值
```

---

## 13. 关键设计决策

| 决策 | 方案 | 理由 |
|------|------|------|
| 并发安全 | `APIClient`/`TokenRefreshHandler` 用 Swift `actor` | 网络层线程安全 |
| Token 刷新合并 | `CheckedContinuation` 合并并发 401 | 只刷新一次，避免雪崩 |
| 意图识别降级 | 在线 AI 优先，失败本地关键词兜底 | 弱网/断网仍可用 |
| 删除撤销 | 乐观更新 + 5s 撤销 Snackbar | 立即反馈，误删可救回 |
| 状态管理 | iOS 17 `@Observable` | 细粒度刷新 |
| 安全存储 | Keychain（`AfterFirstUnlock`） | 对标 Android EncryptedSharedPreferences |
| 语音识别 | Apple `SFSpeechRecognizer` (zh-CN) | 原生免费 |
| 配置外置 | 服务器地址/云密钥写入 Info.plist | 环境切换无需改代码 |

---

## 14. 已知限制与风险（基于代码实际）

1. **HTTP 明文**：当前 `SERVER_BASE_URL` 为 `http://<host>:8080/api/`，服务端无 TLS。
   `Info.plist` 里按主机字面量放行了 ATS（`NSExceptionDomains`），
   loopback 走 `NSAllowsLocalNetworking`。**上线前需切 HTTPS 并删掉 `NSExceptionDomains` 整块。**
   注意域名必须写死 —— Xcode 只替换字符串 value 里的 `$(VAR)`，不替换 dict 的 key，
   写变量会变成字面量而静默失效。
2. ~~**主题未落地**：`ThemeManager` 记录 `warm/neutral`，但 UI 未按主题应用不同色板。~~
   **已修（F-009）**：新增 `Theme/Palette.swift`，全项目颜色引用迁移至 `ThemeManager.shared.palette.*`。
   见 `DESIGN.md` §9.2。
3. **字体大小未全量落地**：`FontSizeManager` 仅在 `IdleStateView/ListeningStateView/ResultStateView` 三处使用，其余 View（ItemList/Help/Settings/导航栏等）仍用固定字号。
4. **代码签名**：`project.yml` 的 `DEVELOPMENT_TEAM` 为空，真机/上架需配置。
5. ~~**图片能力未实现**：`Item.imageUrl` 字段存在，但客户端无拍照/上传物品图片。~~
   **已修（F-001）**：`ItemEditSheetView` 走 `PhotosPicker` → `APIClient.uploadFile`（multipart）
   → `FileAPIService.uploadImage`，上传成功回填 `imageUrl`。
6. **密钥缺失**：`ALICLOUD_APP_SECRET`、`ALICLOUD_AUTH_SDK_INFO` 为空（可能 SFR 流程不需要 Secret，但需确认）。
7. **`open target` 构建目录被检出为 `yjqi` 路径**：当前 `yjhome` 账户下编译通过，但 build 产物记录刷旧的 `yjqi` 路径，建议清理 `build/` 目录。
8. **构建配置取值链路静默失败（F-014，已修）**：`Info.plist` 的 `$(SERVER_BASE_URL)` 占位在
   xcconfig 未接线时解析为**空串**而非报错，`AppConfig` 的 `??` 兜底又只认 `nil`，于是
   `ServerConfig.baseURL == ""`、`APIClient` 拼出无 scheme/host 的路径，**所有请求失败**，
   但 App 仍能正常启动到登录页 —— 表现为「能开、点不动」。
   现已修：`project.yml` 声明 `configFiles` + `AppConfig.infoPlistValue` 把空串视为缺失。
   同类改动的检查手法：改完配置务必 `xcodebuild -showBuildSettings | grep <KEY>` 验证，
   不要只看「编译通过」。
9. ~~**无测试**：项目不含任何单元测试/UI 测试 target。~~
   **已修**：新增 `WaterDropTests` target 与 `WaterDropTests/F011ContractAPITests.swift`，
   由 `scripts/run-f011-contract-tests.sh` 注入登录态后运行（脚本判定要求「跳过数 = 0」，
   因用例全 skip 时 xcodebuild 仍报 TEST SUCCEEDED）。覆盖范围仅 API 契约，无 UI 测试。

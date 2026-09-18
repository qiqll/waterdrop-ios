# 水滴管家 iOS · 技术文档

> 面向开发者的工程手册 · 版本 1.0.0 · 更新于 2026-08-14

---

## 1. 技术栈

| 维度 | 选型 | 对标 Android |
|------|------|--------------|
| UI 框架 | SwiftUI | XML / Material |
| 最低版本 | iOS 17.0 | — |
| 架构 | MVVM | 一致 |
| 异步 | Swift Concurrency (async/await) | Kotlin Coroutines |
| 状态管理 | `@Observable`（Observation） | LiveData / StateFlow |
| 网络 | URLSession（原生） | Retrofit + OkHttp |
| JSON | Codable（原生） | Gson |
| 安全存储 | Keychain Services | EncryptedSharedPreferences |
| 语音识别 | Apple Speech（SFSpeechRecognizer zh-CN） | DashScope SenseVoice |
| 认证 SDK | AlicomFusionAuth（阿里云号码认证） | Aliyun Fusion Auth |
| 工程生成 | XcodeGen | Gradle |
| Swift 版本 | 5.9 | — |

---

## 2. 目录结构

```
waterdrop_ios/
├── WaterDrop/                       # 源码根目录（54 个 Swift 文件）
│   ├── App/
│   │   └── WaterDropApp.swift       # @main 入口，导航编排（AppNavigationState）
│   ├── Config/
│   │   ├── AppConfig.swift          # 从 Info.plist 读取运行时配置
│   │   └── ServerConfig.swift       # API 端点常量、超时配置
│   ├── Models/
│   │   ├── Item.swift               # 物品核心模型
│   │   ├── ChatMessage.swift        # 帮助中心聊天消息模型
│   │   └── DTOs/                    # 请求/响应 DTO（Api/Auth/Item/Ai/Alicloud/Help）
│   ├── Network/
│   │   ├── APIClient.swift          # actor HTTP 客户端（重试/401 刷新）
│   │   ├── NetworkError.swift       # 错误类型与本地化文案
│   │   ├── TokenRefreshHandler.swift# actor Token 刷新合并
│   │   └── Services/               # 5 个 API Service（Item/Ai/Auth/Alicloud/Help）
│   ├── Auth/
│   │   ├── AuthStateManager.swift   # @Observable 认证状态持有者
│   │   ├── AuthService.swift        # 认证业务编排（阿里云流程）
│   │   ├── AuthEventBus.swift       # @Observable 登录事件广播
│   │   ├── KeychainManager.swift    # Keychain 读写封装
│   │   └── AlicomFusionAuthManager.swift # 阿里云 ObjC SDK 的 Swift 封装
│   ├── Repositories/
│   │   └── ItemRepository.swift     # @Observable 物品数据层
│   ├── Services/
│   │   ├── IntentRecognitionService.swift # 在线/离线意图解析
│   │   ├── SpeechRecognitionManager.swift # 语音识别封装
│   │   └── BackupManager.swift      # JSON 导出/导入
│   ├── ViewModels/
│   │   ├── MainViewModel.swift      # 语音输入、删除管理
│   │   ├── ItemListViewModel.swift  # 清单展示、撤销逻辑
│   │   ├── HelpViewModel.swift      # 聊天消息列表
│   │   └── SettingsViewModel.swift  # 主题/字体/导入导出/登出
│   ├── Views/
│   │   ├── Splash/ Auth/ Onboarding/ Main/ ItemList/ Help/ Settings/ Components/
│   ├── Theme/
│   │   ├── AppColors.swift          # 完整色板
│   │   ├── ThemeManager.swift       # 主题偏好
│   │   └── FontSizeManager.swift    # 字体大小偏好
│   ├── Utilities/
│   │   ├── UserPreferencesManager.swift # 昵称存储
│   │   └── DeviceInfo.swift         # 设备标识与系统信息
│   ├── Extensions/
│   │   ├── Color+Hex.swift          # 十六进制颜色初始化
│   │   └── Date+Formatting.swift    # 日期格式化
│   ├── Resources/
│   │   ├── Info.plist               # 配置与权限声明
│   │   └── Assets.xcassets/         # AppIcon 等资源
│   └── BridgingHeader.h             # 桥接头，导入阿里云 ObjC 框架
├── Frameworks/                      # 预编译阿里云 SDK
│   ├── AlicomFusionAuth.framework   # (embed=true)
│   ├── UMCommon.framework           # (embed=false)
│   ├── UMDevice.framework           # (embed=false)
│   ├── ATAuthSDK.bundle             # 授权页 UI 资源
│   └── AlicomCaptcha4.bundle        # 验证码资源
├── project.yml                      # XcodeGen 配置
├── DESIGN.md                        # 项目设计书
└── TECH.md                          # 本文档
```

---

## 3. 网络层

### 3.1 APIClient（actor）

单例 `APIClient.shared`。核心方法：

```swift
func request<T: Decodable>(
    endpoint: String,
    method: HTTPMethod,
    body: Encodable? = nil,
    queryItems: [URLQueryItem]? = nil,
    requiresAuth: Bool = true
) async throws -> ApiResponse<T>
```

**行为**：
- 自动注入 `Bearer accessToken`（`requiresAuth=true` 时）
- 标准请求头：`Accept`、`Content-Type`、`User-Agent`、`X-Client-Platform`、`X-Request-ID`
- 状态码处理：2xx 解析成功；4xx 抛错不重试；5xx 指数退避重试（最多 3 次，1s/2s）
- 401 → 触发 Token 刷新 → 重试原请求
- 超时：读 30s，连接 10s（`ServerConfig`）

### 3.2 TokenRefreshHandler（actor）

防止并发 401 触发多次刷新。刷新进行中的请求通过 `CheckedContinuation` 挂起，刷新完成后统一唤醒。刷新失败则清空认证并 `postLoginRequired()`。

### 3.3 NetworkError

| Case | 用户文案 |
|------|----------|
| `unauthorized` | 认证已过期，请重新登录 |
| `serverError(statusCode)` | 服务器繁忙，请稍后重试 |
| `networkUnavailable` | 网络连接失败，请检查网络设置 |
| `timeout` | 连接超时，请稍后重试 |
| `businessError(code, message)` | 服务端返回的自定义消息 |

---

## 4. API 端点对照表（客户端 ↔ 服务端）

> 所有路径以 Base URL 为前缀（当前 `http://101.42.225.65:8080/api/`）。
> ✅ 表示已与服务端 Spring Boot Controller 核对一致。

### 认证（UserController `/users`）

| 方法 | 端点 | 客户端 Service | 状态 |
|------|------|----------------|------|
| POST | `/users/aliyun/auth-token` | AlicloudAuthAPIService.getAuthToken | ✅ |
| POST | `/users/aliyun/login` | AlicloudAuthAPIService.fusionLogin | ✅ |
| POST | `/users/refresh` | AuthAPIService.refreshToken | ✅ |
| POST | `/users/logout` | AuthAPIService.logout | ✅ |
| GET | `/users/profile` | AuthAPIService.getUserProfile | ✅ |

### 物品（ItemController `/items`）

| 方法 | 端点 | 客户端 Service | 状态 |
|------|------|----------------|------|
| POST | `/items` | ItemAPIService.createItem | ✅ |
| GET | `/items` | ItemAPIService.getItems | ✅ |
| GET | `/items/{id}` | ItemAPIService.getItem | ✅ |
| PUT | `/items/{id}` | ItemAPIService.updateItem | ✅ |
| DELETE | `/items/{id}` | ItemAPIService.deleteItem | ✅ |
| POST | `/items/search` | ItemAPIService.searchItems | ✅ |
| GET | `/items/search/by-name` | ItemAPIService.getItemByName | ✅ |
| GET | `/items/category/{category}` | ItemAPIService.getItemsByCategory | ✅ |

### AI（AiController `/ai`）

| 方法 | 端点 | 客户端 Service | 状态 |
|------|------|----------------|------|
| POST | `/ai/intent?text=X` | AiAPIService.recognizeIntent | ✅ |
| GET | `/ai/usage/today` | AiAPIService.getTodayUsage | ✅ |
| POST | `/ai/help` | HelpAPIService.askHelp | ✅ |
| GET | `/ai/help/history` | HelpAPIService.getHelpHistory | ✅ |

**结论**：iOS 客户端调用的全部 17 个端点在服务端均存在且路径匹配。

---

## 5. 数据模型

### Item（核心模型）

```swift
struct Item: Codable, Identifiable, Equatable {
    let id: String
    var name: String          // 物品名，如"护照"
    var location: String      // 存放位置，如"书桌抽屉"
    var category: String      // 分类，如"证件"
    var description: String
    let createTime: String
    var updateTime: String
    var imageUrl: String?
    var status: Int           // 1 = 有效
    var remark: String?
    let operatorUser: String
}
```

服务端 `ItemDto` 字段更丰富（brand/model/value/warranty 等），通过 `toItem()` 映射为客户端精简模型。

### ApiResponse（响应包装）

```swift
struct ApiResponse<T: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: T?
    let timestamp: String?
    let traceId: String?
}
```

---

## 6. 意图识别机制

`IntentRecognitionService`（单例）流程：

```
用户文本
   │
   ▼
1. 在线识别：AiAPIService.recognizeIntent(text)
   │  成功 ──► 返回结构化意图
   │  失败 ▼
2. 本地兜底：关键词模式匹配
   │  - 物品名：从"放在""我的"等模式提取
   │  - 位置：从"在""放在""现在在"后提取
   │  - 分类：从"所有""查看所有"后提取
   ▼
3. 分类猜测：无分类时按物品名从 9 大分类关键词库推断
   （文具/电子产品/证件/衣物/厨房用品/书籍/工具/药品/珠宝首饰）
   ▼
4. DELETE_ITEM：暂存待删物品，交由 UI 确认（5s 撤销）
```

---

## 7. 语音识别

`SpeechRecognitionManager`（`@Observable`），基于 `SFSpeechRecognizer`（locale zh_CN）。

**状态机**：`idle → preparing → listening → processing → finished`（或 `error`）

**关键点**：
- 权限：iOS 17+ 用 `AVAudioApplication.requestRecordPermission`
- 音频会话：`.record` + `.measurement` + `.duckOthers`，buffer 1024
- 支持实时部分结果（`partialText`）
- 忽略用户取消错误（`kAFAssistantErrorDomain` code 216）

---

## 8. 构建与运行

### 8.1 环境要求

- Xcode 15.0+（当前环境 Xcode 16.4，SDK iOS 18.5，模拟器运行时 iOS 18.6）
- XcodeGen（`brew install xcodegen`）

### 8.2 生成工程

```bash
cd waterdrop_ios
xcodegen generate      # 由 project.yml 生成 WaterDrop.xcodeproj
```

### 8.3 编译（模拟器，跳过签名）

```bash
xcodebuild -project WaterDrop.xcodeproj -target WaterDrop \
  -sdk iphonesimulator -configuration Debug \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

> ✅ 已验证：以上命令 **BUILD SUCCEEDED**。

### 8.4 真机 / 上架

需在 `project.yml` 的 `DEVELOPMENT_TEAM` 填入开发团队 ID 后重新生成工程，Xcode 中配置签名证书与 Provisioning Profile。

### 8.5 类型检查（单文件快速验证）

```bash
swiftc -typecheck -target arm64-apple-ios17.0-simulator \
  -sdk $(xcrun --show-sdk-path --sdk iphonesimulator) \
  -F $(pwd)/Frameworks \
  -import-objc-header WaterDrop/BridgingHeader.h \
  <file.swift>
```

---

## 9. 配置项（Info.plist）

`Info.plist` **不存真值**，只写 `$(VAR)` 占位；真值来自 `Configs/Secrets.xcconfig`
（gitignore，仅 `.example` 入库），由 `project.yml` 的 `configFiles` 接线：

```
Configs/Secrets.xcconfig → 构建设置 → Info.plist 的 $(VAR) → Bundle.main（AppConfig）
```

| Key | 说明 |
|-----|------|
| `SERVER_BASE_URL` | 服务端地址。写入 xcconfig 时须用 `SLASH = /` 拼斜杠（`//` 会被当注释截断）|
| `ALICLOUD_APP_KEY` | 阿里云 AppKey（真值在 Secrets.xcconfig）|
| `ALICLOUD_SCHEME_CODE` | 一键登录场景码（真值在 Secrets.xcconfig）|
| `NSAppTransportSecurity` | 服务端为明文 HTTP，按主机**字面量**放行；loopback 走 `NSAllowsLocalNetworking`（域名不能写 `$(VAR)`，见下） |
| `NSMicrophoneUsageDescription` | 已配置 |
| `NSSpeechRecognitionUsageDescription` | 已配置 |
| `CFBundleDisplayName` | 水滴管家 |

> ⚠️ 这条链路**断掉不会编译失败**，只会得到空串。`AppConfig.infoPlistValue` 因此把空串
> 一律当「未配置」（返回 `nil`），Debug 下还会断言失败。改完配置务必用
> `xcodebuild -showBuildSettings | grep <KEY>` 复核，别只看构建成功。

联调时可用环境变量临时覆盖地址（`AppConfig.serverBaseURL` 优先读它），无需改配置文件：

```bash
SERVER_BASE_URL_OVERRIDE=http://127.0.0.1:8080/api/ ...
```

---

## 10. 阿里云 SDK 集成要点

- SDK 位于 `Frameworks/`，通过 `BridgingHeader.h` 导入 `<AlicomFusionAuth/AlicomFusionAuth.h>`
- `AlicomFusionAuthManager` 用 `CheckedContinuation` 把 SDK 回调桥接为 async/await
- 链接标志：`-ObjC` + 三个 `-framework`（AlicomFusionAuth / UMCommon / UMDevice）
- `AlicomFusionAuth.framework` 需 `embed=true`，其余 `embed=false`
- 依赖系统框架：CoreTelephony、SystemConfiguration；库：libc++、libz
- SDK 委托方法 `onSDKTokenAuthFailure` 在 Swift 中参数标签为 `fail:`
- `AlicomFusionAuthHandler` 需 `@unchecked @retroactive Sendable` 扩展以适配 Swift 并发

---

## 11. 功能健康度检查结论

| 检查项 | 结果 |
|--------|------|
| 源码编译 | ✅ BUILD SUCCEEDED（禁用签名） |
| 工程生成 | ✅ xcodegen 正常生成 xcodeproj |
| API 端点匹配 | ✅ 17/17 端点与服务端一致 |
| 配置完整性 | ✅ 接线已补（F-014）；`xcodebuild -showBuildSettings` 实测 `SERVER_BASE_URL` 非空 |
| 认证流程 | ✅ 阿里云一键登录 + Token 刷新链路完整 |
| 代码签名 | ⚠️ DEVELOPMENT_TEAM 为空，真机/上架需配置 |
| 传输安全 | ⚠️ 当前 HTTP 明文，上线需切 HTTPS 并移除 ATS 例外 |
| 运行时验证 | ✅ 编译产物可装可启；API 层联调见 `WaterDropTests/F011ContractAPITests.swift`（2026-09-14 实跑 7/7 通过） |

**总体判断**：项目结构完整、代码编译通过、与服务端 API 完全对齐，处于**可运行/可联调状态**。上线前需解决 2 个 ⚠️ 项（签名、HTTPS）。

> 「配置完整性 ✅」是**修完 F-014 之后**的结论。此前该项虽然也是 ✅，但构建产物里
> `SERVER_BASE_URL` 实为空串 —— 静态检查看到的是「配置文件里有值」，而没验证「产物里有值」。
> 这类结论必须以 `-showBuildSettings` / 产物 `Info.plist` 为准。

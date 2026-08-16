Here is Claude's plan:                                                                                 
╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌
 WaterDrop iOS 客户端开发方案                                                                           
                                                                                                        
 Context                                                                                                
                                                                                                        
 水滴管家(WaterDrop)是一款 AI                                                                           
 驱动的个人物品位置管理应用，用户通过语音指令记录、查询、更新、删除物品位置。目前 Android 客户端和      
 Spring Boot 服务端已完整实现。本方案旨在从零构建 iOS 客户端，要求与 Android                            
 端功能一致、界面一致、体验一致。

 项目路径：
 - iOS 项目: /Users/yjqi/Library/Mobile Documents/com~apple~CloudDocs/waterdrop_ios/waterdrop_ios
 (当前为空)
 - Android 参考: /Users/yjqi/Library/Mobile Documents/com~apple~CloudDocs/waterdrop
 - 服务端参考: /Users/yjqi/Library/Mobile Documents/com~apple~CloudDocs/wd_server

 ---
 一、技术栈选型

 维度: UI 框架
 选型: SwiftUI
 说明: 声明式 UI，对标 Android XML/Material
 ────────────────────────────────────────
 维度: 最低版本
 选型: iOS 16.0
 说明: 支持 NavigationStack、成熟 SwiftUI
 ────────────────────────────────────────
 维度: 架构
 选型: MVVM
 说明: 与 Android 一致：View → ViewModel → Repository → API
 ────────────────────────────────────────
 维度: 异步
 选型: Swift Concurrency (async/await)
 说明: 对标 Kotlin Coroutines
 ────────────────────────────────────────
 维度: 状态管理
 选型: @Observable (Observation 框架)
 说明: 对标 LiveData/StateFlow
 ────────────────────────────────────────
 维度: 网络
 选型: URLSession (原生)
 说明: 对标 Retrofit+OkHttp，无需第三方库
 ────────────────────────────────────────
 维度: JSON
 选型: Codable (原生)
 说明: 对标 Gson
 ────────────────────────────────────────
 维度: 安全存储
 选型: Keychain Services
 说明: 对标 EncryptedSharedPreferences
 ────────────────────────────────────────
 维度: 语音识别
 选型: Apple Speech (SFSpeechRecognizer zh-CN)
 说明: 对标 DashScope SenseVoice
 ────────────────────────────────────────
 维度: 认证 SDK
 选型: ATAuthSDK (阿里云号码认证)
 说明: 对标 Android Aliyun Fusion Auth
 ────────────────────────────────────────
 维度: 依赖管理
 选型: Swift Package Manager
 说明: 无需 CocoaPods
 ────────────────────────────────────────
 维度: 图片加载
 选型: Kingfisher (SPM)
 说明: 如需加载远程图片
 ────────────────────────────────────────
 维度: Keychain 简化
 选型: KeychainAccess (SPM)
 说明: 简化 Keychain 操作

 ---
 二、项目目录结构

 WaterDrop/
 ├── WaterDrop.xcodeproj
 ├── WaterDrop/
 │   ├── App/
 │   │   ├── WaterDropApp.swift              // @main 入口，NavigationStack 根
 │   │   └── AppDelegate.swift               // UIApplicationDelegate（阿里云SDK初始化）
 │   │
 │   ├── Config/
 │   │   ├── ServerConfig.swift              // BaseURL、超时、端点路径常量
 │   │   ├── AppConfig.swift                 // 从 xcconfig 读取敏感配置
 │   │   └── Environment.xcconfig            // API_KEY、SERVER_URL（不入 git）
 │   │
 │   ├── Models/
 │   │   ├── Item.swift                      // 物品模型
 │   │   ├── ChatMessage.swift               // 帮助聊天消息
 │   │   └── DTOs/
 │   │       ├── ApiResponse.swift           // 通用 ApiResponse<T> + PagedResult<T>
 │   │       ├── ItemDTOs.swift              // ItemDto, ItemCreateRequest, ItemSearchRequest
 │   │       ├── AuthDTOs.swift              // RefreshTokenRequest/Response, UserInfo 等
 │   │       ├── AlicloudAuthDTOs.swift      // 阿里云认证请求/响应
 │   │       ├── AiDTOs.swift                // IntentResultResponse, AiUsageTodayResponse
 │   │       └── HelpDTOs.swift              // HelpRequest/Response, AiUsageRecord
 │   │
 │   ├── Network/
 │   │   ├── APIClient.swift                 // 核心请求器（构建URL、注入Auth头、解析响应）
 │   │   ├── TokenRefreshHandler.swift        // 401时自动刷新Token并重试
 │   │   ├── RetryHandler.swift              // 5xx指数退避重试（最多3次）
 │   │   ├── NetworkError.swift              // 错误类型 + 用户友好消息
 │   │   └── Services/
 │   │       ├── ItemAPIService.swift        // 物品 CRUD + 搜索
 │   │       ├── AuthAPIService.swift        // Token 刷新、登出、Profile
 │   │       ├── AlicloudAuthAPIService.swift // 阿里云认证Token + 登录
 │   │       ├── AiAPIService.swift          // 意图识别 + 用量查询
 │   │       └── HelpAPIService.swift        // 帮助问答 + 历史
 │   │
 │   ├── Auth/
 │   │   ├── AuthService.swift               // 认证流程编排（获取Token→SDK验证→服务端登录→保存）
 │   │   ├── AuthStateManager.swift          // Keychain 存储的认证状态（@Observable）
 │   │   ├── AuthEventBus.swift              // 登录过期事件广播
 │   │   └── KeychainManager.swift           // Keychain CRUD 封装
 │   │
 │   ├── Repositories/
 │   │   └── ItemRepository.swift            // 物品数据操作（调用 ItemAPIService）
 │   │
 │   ├── Services/
 │   │   ├── IntentRecognitionService.swift   // 语音文字 → 意图 → 执行 → 格式化结果
 │   │   ├── SpeechRecognitionManager.swift   // Apple Speech 封装（开始/停止/部分结果/最终结果）
 │   │   └── BackupManager.swift             // JSON 导出/导入
 │   │
 │   ├── ViewModels/
 │   │   ├── MainViewModel.swift             // 三态切换、语音处理、删除撤销、自动重置
 │   │   ├── ItemListViewModel.swift         // 物品列表、删除撤销
 │   │   ├── HelpViewModel.swift             // 聊天消息、发送问题
 │   │   └── SettingsViewModel.swift         // 主题、字体、昵称、登出
 │   │
 │   ├── Views/
 │   │   ├── Splash/
 │   │   │   └── SplashView.swift            // 水滴动画 + 标语
 │   │   ├── Auth/
 │   │   │   └── LoginView.swift             // 登录按钮 + 自动登录检测
 │   │   ├── Onboarding/
 │   │   │   └── OnboardingView.swift        // 3页引导 TabView + 跳过/开始
 │   │   ├── Main/
 │   │   │   ├── MainView.swift              // 核心三态 UI + 导航按钮
 │   │   │   ├── VoiceFabView.swift          // 自定义语音FAB（按住+右滑手势）
 │   │   │   ├── IdleStateView.swift         // 空闲态内容
 │   │   │   ├── ListeningStateView.swift    // 聆听态内容（部分识别文字）
 │   │   │   └── ResultStateView.swift       // 结果态内容
 │   │   ├── ItemList/
 │   │   │   ├── ItemListView.swift          // 分类分组列表 + 滑动删除
 │   │   │   └── ItemCardView.swift          // 单个物品卡片
 │   │   ├── Help/
 │   │   │   ├── HelpView.swift              // 聊天界面 + 输入框
 │   │   │   └── ChatBubbleView.swift        // 用户/AI 消息气泡
 │   │   ├── Settings/
 │   │   │   └── SettingsView.swift          // 设置列表页
 │   │   └── Components/
 │   │       ├── PulseAnimationView.swift    // 脉冲环动画
 │   │       └── UndoSnackbarView.swift      // 底部撤销提示条
 │   │
 │   ├── Theme/
 │   │   ├── ThemeManager.swift              // 主题切换 + UserDefaults 持久化
 │   │   ├── FontSizeManager.swift           // 字体大小管理
 │   │   └── AppColors.swift                 // 全部颜色定义（与 Android colors.xml 完全一致）
 │   │
 │   ├── Utilities/
 │   │   ├── UserPreferencesManager.swift    // 昵称等偏好设置
 │   │   └── DeviceInfo.swift                // 设备ID、平台信息
 │   │
 │   ├── Resources/
 │   │   ├── Assets.xcassets/                // App Icon、图片、颜色集
 │   │   └── Info.plist                      // 隐私描述、URL Scheme
 │   │
 │   └── Extensions/
 │       ├── Color+Hex.swift                 // Color(hex:) 扩展
 │       └── Date+Formatting.swift           // 日期格式化
 │
 ├── WaterDropTests/                          // 单元测试
 └── WaterDropUITests/                        // UI 测试


 ---
 三、分阶段开发计划

 Phase 1: 项目搭建 + 基础设施 (网络层、配置、主题、Keychain)

 交付物： Xcode 项目、网络请求基础设施、颜色/主题系统、Keychain 存储

 文件清单：

 1. 创建 Xcode 项目 — WaterDrop.xcodeproj，Bundle ID: com.waterdrop.ios，Deployment Target: iOS 16.0
 2. Config/ServerConfig.swift
 enum ServerConfig {
     static var baseURL: String { AppConfig.serverBaseURL }
     enum Timeout {
         static let connect: TimeInterval = 10
         static let read: TimeInterval = 30
     }
     // 所有 API 端点路径常量
     enum Endpoints {
         static let alicloudAuthToken = "users/aliyun/auth-token"
         static let alicloudLogin = "users/aliyun/login"
         static let refreshToken = "users/refresh"
         static let logout = "users/logout"
         static let userProfile = "users/profile"
         static let items = "items"
         static let aiIntent = "ai/intent"
         static let aiUsageToday = "ai/usage/today"
         static let aiHelp = "ai/help"
         static let aiHelpHistory = "ai/help/history"
     }
 }
 3. Config/AppConfig.swift — 从 Info.plist / xcconfig 读取
 SERVER_BASE_URL、DASHSCOPE_API_KEY、ALICLOUD_APP_KEY、ALICLOUD_SCHEME_CODE
 4. Network/NetworkError.swift — 错误类型枚举，每种情况对应中文用户消息
   - unauthorized → "认证已过期"
   - serverError → "服务器繁忙，请稍后重试"
   - networkUnavailable → "网络连接失败"
   - timeout → "连接超时"
 5. Network/APIClient.swift — 核心网络请求器
   - actor APIClient 保证线程安全
   - request<T: Decodable>(endpoint:method:body:queryItems:requiresAuth:) 泛型方法
   - 自动注入 Authorization: Bearer <token> 头
   - 自动注入 User-Agent: WaterDrop-iOS/1.0, X-Client-Platform: iOS, X-Request-ID: UUID
   - 收到 401 时调用 TokenRefreshHandler 刷新后重试
   - 收到 5xx 时调用 RetryHandler 指数退避重试
 6. Network/TokenRefreshHandler.swift — actor 保证并发安全
   - 多个请求同时收到 401 时，只发起一次 refresh，其余排队等待结果
   - 刷新失败时发送 AuthEventBus.postLoginRequired()
 7. Network/RetryHandler.swift — 指数退避
   - delay = 1s × 2^attempt, 最多 3 次
   - 仅对 5xx 和网络错误重试，4xx 不重试
 8. Models/DTOs/ApiResponse.swift
 struct ApiResponse<T: Decodable>: Decodable {
     let code: Int
     let message: String
     let data: T?
     let timestamp: String?
     let traceId: String?
 }
 struct PagedResult<T: Decodable>: Decodable {
     let records: [T]
     let total: Int
     let size: Int
     let current: Int
     let pages: Int
 }
 struct EmptyData: Decodable {}
 9. Theme/AppColors.swift — 完整颜色定义（与 Android colors.xml 像素级一致）
 // Primary: #5B7E6B, PrimaryVariant: #476256, PrimaryLight: #E8F0EB
 // Secondary: #C4A882, SecondaryVariant: #A68B6A
 // Accent: #E8A87C, AccentVariant: #D4956B
 // Neutral: #FAFAF8, #F5F3F0, #E8E5E1, #D4D0CB, #B0ABA4,
 //          #8A847D, #6B665F, #4A4640, #2D2A26, #1A1816
 // Semantic: success #5B9A6B, warning #E5A84B, error #C75450, info #5B8EC7
 // Recording: active #C75450, pulse #C75450 (20% opacity)
 10. Theme/ThemeManager.swift — @Observable, warm/neutral 两种主题, UserDefaults 持久化
 11. Theme/FontSizeManager.swift — @Observable, small(16)/medium(20)/large(24) 三档, UserDefaults
 持久化
 12. Auth/KeychainManager.swift — Keychain CRUD: save/read/delete/deleteAll
 13. Extensions/Color+Hex.swift — Color(hex: String) 初始化器

 ---
 Phase 2: 认证系统 (阿里云号码认证 + JWT Token 管理)

 交付物： 登录/认证流程、Token 自动刷新、登录过期检测

 文件清单：

 1. Auth/AuthStateManager.swift
 @Observable final class AuthStateManager {
     enum AuthState { case unauthenticated, authenticated(userId:expiresAt:), expired(userId:) }
     private(set) var state: AuthState
     func saveAuthInfo(userId:accessToken:refreshToken:expiresAt:)
     func getAccessToken() -> String?
     func getRefreshToken() -> String?
     func getCurrentUserId() -> String?
     func clearAuthInfo()
     var isTokenExpired: Bool { get }
 }
 2. Auth/AuthEventBus.swift — @Observable, loginRequired: Bool 属性，供全局监听
 3. Auth/AuthService.swift — 认证流程编排
   - performAlicloudAuthentication(): 获取 authToken → SDK 验证 → 服务端登录 → 保存 Token
   - refreshAccessToken(): 用 refreshToken 刷新
   - logout(): 调用服务端登出 + 清除 Keychain
   - iOS 特殊: 发送 platform: "iOS", bundleId: Bundle.main.bundleIdentifier
 4. Network/Services/AuthAPIService.swift
   - refreshToken(refreshToken:) → ApiResponse<RefreshTokenResponse>
   - logout(refreshToken:) → ApiResponse<EmptyData>
   - getUserProfile() → ApiResponse<UserInfoResponse>
 5. Network/Services/AlicloudAuthAPIService.swift
   - getAuthToken(bundleId:) → ApiResponse<AlicloudAuthTokenResponse>
   - fusionLogin(verifyToken:deviceId:) → ApiResponse<AlicloudLoginResponse>
 6. Models/DTOs/AuthDTOs.swift — 全部认证相关 DTO
 struct RefreshTokenRequest: Codable { let refreshToken: String }
 struct RefreshTokenResponse: Codable { let accessToken, refreshToken: String; let expiresAt: Int64 }
 struct UserInfoResponse: Codable { let id, phone: String; let nickname, avatar: String?; let status:
 Int }
 7. Models/DTOs/AlicloudAuthDTOs.swift — 阿里云认证 DTO
 struct AlicloudAuthTokenRequest: Codable {
     let platform: String = "iOS"; let bundleId: String?; let durationSeconds: Int = 900
 }
 struct AlicloudLoginRequest: Codable {
     let verifyToken, deviceId: String; let platform: String = "iOS"
 }
 struct AlicloudLoginResponse: Codable {
     let accessToken, refreshToken: String; let user: AlicloudUserInfo; let expiresAt: Int64
 }
 8. Views/Splash/SplashView.swift — 启动动画
   - 水滴图标下落动画 + "水滴管家" + "点点滴滴，记在心里"
   - 首次启动: 2.8s, 后续: 1.2s
   - 动画结束后检查认证状态，决定跳转
 9. Views/Auth/LoginView.swift — 登录界面
   - 自动检测已登录状态（token 未过期直接跳转 MainView）
   - token 过期尝试自动刷新
   - 显示"一键登录"按钮
   - 点击后启动阿里云号码认证流程
 10. Views/Onboarding/OnboardingView.swift — 3 页引导
   - 第1页: "说一句话，记住物品位置" + "对着麦克风说「护照放在书桌抽屉里」\n我会帮你记住"
   - 第2页: "忘了放哪？问一声就好" + "说「护照在哪里」\n我会马上告诉你"
   - 第3页: "准备好了" + "轻按麦克风按钮\n开始管理你的物品"
   - TabView + 圆点指示器 + "跳过"/"开始使用" 按钮
   - 仅首次启动显示 (UserDefaults 标记)
 11. Utilities/DeviceInfo.swift — UIDevice.identifierForVendor?.uuidString 获取设备ID

 iOS 适配要点：
 - Android 用 Settings.Secure.ANDROID_ID，iOS 用 identifierForVendor
 - Android 发 packageName + packageSign，iOS 发 bundleId
 - 阿里云 ATAuthSDK iOS 版需用 UIViewControllerRepresentable 包装

 ---
 Phase 3: 主界面 + 语音交互 (核心功能)

 交付物： MainView 三态切换、语音 FAB 手势、语音识别、意图识别执行

 文件清单：

 1. Services/SpeechRecognitionManager.swift — Apple Speech 封装
 @Observable final class SpeechRecognitionManager {
     enum State { case idle, preparing, listening, processing, finished, error(String) }
     private(set) var state: State = .idle
     private(set) var recognizedText: String = ""
     private(set) var partialText: String = ""
     // 使用 SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
     // 使用 AVAudioEngine 实时录音
     func startListening()    // 开始录音+识别
     func stopListening()     // 停止录音（等待最终结果）
     func cancel()            // 取消识别
 }
   - Info.plist 必须添加:
       - NSMicrophoneUsageDescription = "水滴管家需要使用麦克风来录制语音指令"
     - NSSpeechRecognitionUsageDescription = "水滴管家需要语音识别功能来理解您的语音指令"
 2. Services/IntentRecognitionService.swift — 意图识别 + 执行
   - 与 Android IntentRecognitionService.kt 完全对标
   - recognizeIntent(text:): 先尝试 POST /api/ai/intent，失败降级本地关键词匹配
   - processUserInput(text:): 识别意图 → 执行操作 → 格式化结果字符串
   - 6种意图: RECORD_LOCATION, QUERY_LOCATION, UPDATE_LOCATION, DELETE_ITEM, QUERY_CATEGORY, UNKNOWN
   - pendingDeleteItem: 删除意图时暂存物品，不立即删除（等确认或超时）
   - DELETE_PENDING: 前缀标记删除待确认
   - 本地降级：关键词匹配（"放在"/"放到" → 记录, "在哪"/"找" → 查询, "删除" → 删除）
   - guessCategory(): 关键词→类别映射（文具、电子产品、证件...与 Android 一致）
   - 参考: Android /service/IntentRecognitionService.kt
 3. Models/DTOs/AiDTOs.swift
 struct IntentResultResponse: Codable {
     let type: String; let itemName, location, category, queryText: String?
 }
 4. Network/Services/AiAPIService.swift
   - recognizeIntent(text:) → ApiResponse<IntentResultResponse> (POST /api/ai/intent?text=xxx)
   - getTodayUsage() → ApiResponse<AiUsageTodayResponse> (GET /api/ai/usage/today)
 5. Repositories/ItemRepository.swift
 @Observable final class ItemRepository {
     static let shared = ItemRepository()
     private(set) var allItems: [Item] = []
     func refreshItems() async
     func insert(_ request: ItemCreateRequest) async -> String   // 返回 itemId
     func update(id: String, _ request: ItemCreateRequest) async
     func delete(id: String) async
     func searchItemsByName(_ name: String) async -> [Item]
     func getItemByName(_ name: String) async -> Item?
     func getItemsByCategory(_ category: String) async -> [Item]
     func recordItemLocation(name:location:category:description:) async -> String
     func updateItemLocation(name:newLocation:) async -> Bool
 }
 6. Network/Services/ItemAPIService.swift
   - createItem(_:) POST /api/items
   - getItems() GET /api/items
   - getItem(id:) GET /api/items/{id}
   - updateItem(id:_:) PUT /api/items/{id}
   - deleteItem(id:) DELETE /api/items/{id}
   - searchItems(_:) POST /api/items/search
   - getItemByName(name:) GET /api/items/search/by-name?name=xxx
   - getItemsByCategory(category:) GET /api/items/category/{category}
 7. Models/Item.swift
 struct Item: Codable, Identifiable, Equatable {
     let id: String; let name: String; let location: String
     var category: String = ""; var description: String = ""
     var createTime: String = ""; var updateTime: String = ""
     var imageUrl: String?; var status: Int = 1; var remark: String?
     var operatorUser: String = ""
 }
 8. Models/DTOs/ItemDTOs.swift — ItemDto(服务端完整字段) + ItemCreateRequest + ItemSearchRequest +
 toItem() 转换
 9. ViewModels/MainViewModel.swift
 @Observable final class MainViewModel {
     enum UIState { case idle, listening, result }
     private(set) var uiState: UIState = .idle
     private(set) var processedResult: String = ""
     private(set) var errorMessage: String = ""
     private(set) var showUndoSnackbar: Bool = false
     private(set) var pendingDeleteItemName: String = ""

     func processVoiceInput(_ text: String) async   // 调用 IntentRecognitionService
     func scheduleDelete(_ item: Item)               // 暂存待删除
     func confirmDelete()                            // 确认删除（服务端）
     func cancelDelete()                             // 撤销删除
     func flushPendingDelete()                       // 销毁时强制执行
     func scheduleAutoReset()                        // 5秒后回到 idle
 }
 10. Views/Main/VoiceFabView.swift — 最复杂的自定义组件
   - 参考: Android VoiceFabLayout.kt (456行)
   - 4 种状态: idle, pressing, sliding, listenMode
   - 手势实现: 使用 UIViewRepresentable + UILongPressGestureRecognizer（minimumPressDuration: 0）
       - ACTION_DOWN → enterPressingState(): 缩小FAB到0.85, 变红(#C75450), 显示停止图标, 启动脉冲,
 显示滑动轨道
     - ACTION_MOVE → 右滑超过阈值(120dp) → enterListenMode(): OvershootInterpolator 弹到终点,
 慢脉冲(2s)
     - ACTION_UP → onPressRelease(): FAB 弹回中心(200ms), 隐藏轨道
   - 脉冲动画: scaleX/Y 1.0↔1.4, alpha 1.0↔0.3, 持续 1000ms(普通)/2000ms(聆听模式)
   - 滑动轨道: 右侧显示"聆听模式"提示, alpha 随进度变化
   - 触觉反馈: UIImpactFeedbackGenerator(.medium) 按下, .heavy 进入聆听模式
   - 教练提示: 前3次按下显示"按住说话，右滑进入聆听模式"，2秒后消失
 11. Views/Main/MainView.swift — 主界面
   - 顶栏: 设置(齿轮)、物品列表(列表)、帮助(问号) 按钮
   - 中央: MaterialCardView 对标的卡片，三态切换 (idle/listening/result)
   - 底部: VoiceFabView 居中
   - 监听 AuthEventBus.loginRequired → 跳转登录
 12. Views/Main/IdleStateView.swift — "有什么需要我帮你记住的吗？"
 13. Views/Main/ListeningStateView.swift — "正在聆听…" + 部分识别文字实时显示
 14. Views/Main/ResultStateView.swift — 结果标签 + 结果内容
 15. Views/Components/PulseAnimationView.swift — 脉冲环动画组件
 16. Views/Components/UndoSnackbarView.swift — 底部撤销提示条
   - "已删除「xxx」" + "撤销" 按钮
   - 5秒自动消失（对标 Android Snackbar 5000ms）
   - 超时不点撤销 → confirmDelete()
   - 点击撤销 → cancelDelete()

 ---
 Phase 4: 物品列表

 交付物： ItemListView（分类分组、滑动删除、撤销、空状态）

 文件清单：

 1. ViewModels/ItemListViewModel.swift
 @Observable final class ItemListViewModel {
     private(set) var items: [Item] = []
     private(set) var showUndoSnackbar: Bool = false
     private(set) var undoItemName: String = ""
     func refreshItems() async
     func scheduleDelete(_ item: Item)
     func confirmDelete()
     func cancelDelete()
 }
 2. Views/ItemList/ItemListView.swift
   - 顶部: "共 N 件物品" 计数
   - 空状态: "还没有记录任何物品" + "试试对麦克风说「钥匙放在玄关」"
   - 非空: List + ForEach 按类别分组 (Section header 显示 "类别名 N件")
   - 每个物品支持 .swipeActions 滑动删除
   - 删除确认弹窗: "确定要删除「xxx」的记录吗？"
   - 底部 UndoSnackbarView overlay
 3. Views/ItemList/ItemCardView.swift — 单个物品卡片: 名称、位置、类别图标

 ---
 Phase 5: 帮助系统

 交付物： HelpView 聊天界面、AI 问答

 文件清单：

 1. Network/Services/HelpAPIService.swift
   - askHelp(question:) → ApiResponse<HelpResponseDto> (POST /api/ai/help)
   - getHelpHistory(page:size:) → ApiResponse<PagedResult<AiUsageRecordDto>> (GET /api/ai/help/history)
 2. Models/DTOs/HelpDTOs.swift
 struct HelpRequestDto: Codable { let question: String }
 struct HelpResponseDto: Codable { let answer: String?; let inScope: Bool; let featureRequestId:
 String? }
 3. Models/ChatMessage.swift
 struct ChatMessage: Identifiable, Equatable {
     let id = UUID(); let content: String; let isUser: Bool
     var inScope: Bool = true; var isError: Bool = false; let timestamp: Date
 }
 4. ViewModels/HelpViewModel.swift
 @Observable final class HelpViewModel {
     private(set) var messages: [ChatMessage] = []
     private(set) var isLoading: Bool = false
     func sendQuestion(_ question: String) async
 }
 5. Views/Help/HelpView.swift
   - 标题: "帮助中心"
   - 空状态: "有什么可以帮您？" + "您可以问我任何关于水滴管家的使用问题"
   - 消息列表: ScrollView + LazyVStack
   - 底部输入栏: TextField + 发送按钮
   - 发送时显示 loading 指示器
 6. Views/Help/ChatBubbleView.swift — 用户消息右对齐(primary背景), AI消息左对齐(neutral100背景)

 ---
 Phase 6: 设置页面

 交付物： SettingsView（个人信息、主题、字体、数据管理、登出）

 文件清单：

 1. Utilities/UserPreferencesManager.swift — UserDefaults 封装: nickname get/set/hasCustomNickname
 2. ViewModels/SettingsViewModel.swift
 @Observable final class SettingsViewModel {
     var nickname: String
     var theme: ThemeManager.Theme
     var fontSize: FontSizeManager.FontSize
     var showNicknameEditor: Bool = false
     var showLogoutConfirm: Bool = false
     func updateNickname(_ name: String)
     func exportData() async
     func importData() async
     func logout() async
 }
 3. Views/Settings/SettingsView.swift — List 布局
   - Section "个人": 昵称（点击弹出编辑 Alert）
   - Section "主题": Picker 切换 暖色系/素色系
   - Section "字体大小": Picker 切换 小/中/大
   - Section "数据管理": 导出数据、导入数据 按钮
   - Section: 退出登录（红色，确认 Alert）
 4. Services/BackupManager.swift — JSON 导出到文件、从文件导入

 ---
 Phase 7: 导航集成 + 打磨

 交付物： 完整导航流程、动画打磨、边界情况处理

 关键任务：

 1. App/WaterDropApp.swift — 完整导航流程
 @main struct WaterDropApp: App {
     @State private var authState = AuthStateManager.shared
     @State private var authEventBus = AuthEventBus.shared
     var body: some Scene {
         WindowGroup {
             Group {
                 if showSplash { SplashView(...) }
                 else if !authState.isAuthenticated { LoginView() }
                 else if showOnboarding { OnboardingView(...) }
                 else { MainView() }
             }
         }
     }
 }
   - SplashView 动画完成 → 检查 auth → 已认证跳 Main, 未认证跳 Login
   - Login 成功 → 首次显示 Onboarding, 否则直接 Main
   - AuthEventBus.loginRequired → 强制回到 Login
 2. 动画打磨
   - Splash: 水滴下落弹跳动画 (OvershootInterpolator 对标)
   - VoiceFab: 按下缩放、脉冲环、滑动轨道显隐、弹回动画
   - 三态切换: 淡入淡出过渡 .transition(.opacity.animation(.easeInOut(duration: 0.2)))
   - 结果态: 5秒自动重置倒计时
 3. 边界情况
   - 网络断开: 优雅错误提示
   - Token 中途过期: 401 → 自动刷新 → 刷新失败 → 弹出登录
   - 麦克风权限拒绝: 提示 + 引导去设置
   - onPause/onResume 对标: 使用 scenePhase 监听前后台切换
   - 销毁时 flush 待删除操作

 ---
 四、Android → iOS 关键映射表

 ┌────────────────────────────┬────────────────────────────────────┬────────────────┐
 │          Android           │                iOS                 │      说明      │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ EncryptedSharedPreferences │ Keychain                           │ 安全存储 Token │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ Retrofit + OkHttp          │ URLSession                         │ 网络请求       │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ Gson                       │ Codable                            │ JSON 序列化    │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ Kotlin Coroutines          │ Swift async/await                  │ 异步编程       │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ LiveData / StateFlow       │ @Observable                        │ 响应式状态     │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ ViewModel (AAC)            │ @Observable class                  │ 视图模型       │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ Activity/Fragment          │ SwiftUI View                       │ 界面           │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ Intent (导航)              │ NavigationStack                    │ 页面跳转       │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ OkHttp Interceptor         │ URLSession 请求前处理              │ 请求拦截       │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ Authenticator              │ TokenRefreshHandler                │ Token 刷新     │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ SharedPreferences          │ UserDefaults                       │ 普通偏好       │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ RecyclerView               │ List + ForEach                     │ 列表           │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ SwipeRefreshLayout         │ .refreshable                       │ 下拉刷新       │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ Snackbar                   │ 自定义 UndoSnackbarView            │ 撤销提示       │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ MotionEvent touch          │ UIGestureRecognizer                │ 手势处理       │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ HapticFeedbackConstants    │ UIImpactFeedbackGenerator          │ 触觉反馈       │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ SenseVoice SDK             │ SFSpeechRecognizer (zh-CN)         │ 语音识别       │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ Aliyun Fusion Auth Android │ ATAuthSDK (iOS)                    │ 号码认证       │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ Settings.Secure.ANDROID_ID │ UIDevice.identifierForVendor       │ 设备ID         │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ Handler.postDelayed        │ Task.sleep / Timer                 │ 延迟操作       │
 ├────────────────────────────┼────────────────────────────────────┼────────────────┤
 │ ObjectAnimator             │ SwiftUI .animation / withAnimation │ 动画           │
 └────────────────────────────┴────────────────────────────────────┴────────────────┘

 ---
 五、中文字符串表 (与 Android strings.xml 一致)

 所有用户可见文案直接硬编码在 View 中（中文单一语言），与 Android strings.xml 保持一致：

 - 应用名: "水滴管家"
 - 标语: "点点滴滴，记在心里"
 - 空闲提示: "有什么需要我帮你记住的吗？"
 - 聆听中: "正在聆听…"
 - 删除撤销: "已删除「%@」" + "撤销"
 - 撤销成功: "已撤销删除"
 - 未听清: "没听清楚，可以再说一次吗？"
 - 网络错误: "网络似乎不太好，请再试一次"
 - 物品列表标题: "我的物品"
 - 空列表: "还没有记录任何物品" + "试试对麦克风说「钥匙放在玄关」"
 - 设置: "设置", "暖色系主题", "素色系主题", "小字体/中字体/大字体"
 - 引导页: 3页文案（见 Phase 2 第10项）
 - 帮助: "帮助中心", "有什么可以帮您？"
 - 教练: "按住说话，右滑进入聆听模式"

 ---
 六、验证方案

 每个 Phase 完成后的验证：

 1. Phase 1: 编写一个简单的测试 View，调用 APIClient.request 向服务端发送请求，验证网络层正常工作
 2. Phase 2: 完整走通 登录 → Splash → Onboarding → 自动登录，验证 Token 存储和读取
 3. Phase 3: 按住语音 FAB → 说话 → 看到识别结果 → 物品被记录到服务端 → 5秒自动重置
 4. Phase 4: 打开物品列表 → 看到分类分组 → 左滑删除 → 撤销 → 确认删除
 5. Phase 5: 打开帮助 → 输入问题 → 收到 AI 回答 → 消息气泡正确显示
 6. Phase 6: 修改主题 → UI 颜色切换；修改字体 → 文字大小变化；导出/导入数据
 7. Phase 7: 完整流程走通：安装 → Splash → 登录 → 引导 → 语音记录物品 → 查询物品 → 物品列表 → 帮助 →
 设置 → 退出登录 → 重新登录（自动跳过引导）

 与 Android 一致性验证:

 - 逐屏对比 iOS 和 Android 的 UI 布局、颜色、字体
 - 验证所有 API 调用参数和响应处理与 Android 一致
 - 验证手势交互行为一致（FAB 按压、滑动、脉冲动画）
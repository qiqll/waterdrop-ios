# 水滴管家 iOS 客户端 · 项目设计书

> 版本 1.0.0 · 最后更新 2026-08-14

---

## 1. 项目概述

**水滴管家（WaterDrop）** 是一款 AI 驱动的个人物品位置管理应用。用户通过**语音指令**记录、查询、更新、删除物品的存放位置，由 AI 意图识别引擎理解自然语言并执行对应操作。

本仓库为 **iOS 客户端**，与已上线的 Android 端、Spring Boot 服务端协同工作，目标是三端**功能一致、界面一致、体验一致**。

| 维度 | 说明 |
|------|------|
| 产品定位 | 面向个人的语音物品管家，解决"东西放哪了想不起来"的痛点 |
| 核心交互 | 按住语音 FAB 说话 → AI 解析意图 → 执行 → 展示结果 |
| 目标平台 | iOS 17.0+ |
| Bundle ID | `com.yjqi.waterdrop.ios` |
| 显示名称 | 水滴管家 |

### 三模块目录说明

水滴管家由三个模块组成，均位于同级目录 `~/Library/Mobile Documents/com~apple~CloudDocs/` 下：

| 模块 | 路径 | 技术栈 | 一句话职责 |
|------|------|--------|-----------|
| **iOS 客户端**（本项目） | `.../waterdrop_ios` | SwiftUI + MVVM + @Observable，iOS 17.0+ | iOS 端语音物品管家，与 Android 端功能/界面/体验一致 |
| **Android 客户端** | `.../waterdrop` | Kotlin + Retrofit + Room + Coroutines，minSdk 30 / targetSdk 34 | Android 端语音物品管家，语音识别用 DashScope，applicationId `com.example.itemfinder` |
| **服务端** | `.../wd_server` | Spring Boot 3.2.0 + Java 17 + MySQL | REST API 后端，20 个业务模块（item/ai/auth/group/membership/payment 等），对接 AI 大模型与阿里云号码认证 |

> 完整绝对路径：
> - iOS：`/Users/yjhome/Library/Mobile Documents/com~apple~CloudDocs/waterdrop_ios/waterdrop_ios`
> - Android：`/Users/yjhome/Library/Mobile Documents/com~apple~CloudDocs/waterdrop`
> - 服务端：`/Users/yjhome/Library/Mobile Documents/com~apple~CloudDocs/wd_server`

---

## 2. 核心功能

| 功能 | 语音示例 | 意图类型 | 说明 |
|------|----------|----------|------|
| 记录位置 | "护照放在书桌抽屉" | `RECORD_LOCATION` | 已存在则更新，不存在则新建 |
| 查询位置 | "护照在哪里" | `QUERY_LOCATION` | 按名称查找并展示位置 |
| 更新位置 | "护照现在在卧室" | `UPDATE_LOCATION` | 仅更新位置，保留其它字段 |
| 删除物品 | "删除护照" | `DELETE_ITEM` | 5 秒撤销窗口后真正删除 |
| 分类查询 | "查看所有证件" | `QUERY_CATEGORY` | 列出某分类下所有物品 |

**辅助功能**：物品清单浏览（按分类分组）、AI 问答帮助中心、数据导出/导入（JSON）、主题切换、字体大小调节、昵称设置。

---

## 3. 系统架构

### 3.1 三端关系

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  iOS 客户端  │     │ Android 客户端│     │   管理后台   │
│  (本仓库)    │     │             │     │  (Web)      │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       └───────────────────┼───────────────────┘
                           │ HTTP / JSON
                  ┌────────▼─────────┐
                  │  Spring Boot 服务端│
                  │  (wd_server)      │
                  └────────┬─────────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
        ┌─────▼───┐  ┌─────▼───┐  ┌────▼─────┐
        │  MySQL  │  │ AI 大模型│  │ 阿里云号码 │
        │         │  │ (意图识别)│  │  认证服务  │
        └─────────┘  └─────────┘  └──────────┘
```

### 3.2 客户端分层架构（MVVM）

```
┌───────────────────────────────────────────────────┐
│                    View (SwiftUI)                   │
│  Splash / Login / Onboarding / Main / ItemList /   │
│  Help / Settings + Components                       │
└───────────────────────┬───────────────────────────┘
                        │ @Observable 绑定
┌───────────────────────▼───────────────────────────┐
│                   ViewModel                         │
│  Main / ItemList / Help / Settings ViewModel        │
└───────────────────────┬───────────────────────────┘
                        │
┌───────────────────────▼───────────────────────────┐
│         Repository / Service                        │
│  ItemRepository · IntentRecognitionService ·        │
│  SpeechRecognitionManager · BackupManager           │
└───────────────────────┬───────────────────────────┘
                        │
┌───────────────────────▼───────────────────────────┐
│                 Network Layer                       │
│  APIClient (actor) · TokenRefreshHandler (actor) ·  │
│  API Services · NetworkError                        │
└───────────────────────┬───────────────────────────┘
                        │ URLSession
                  ┌──────▼──────┐
                  │  服务端 API   │
                  └─────────────┘
```

**数据流向**：`View → ViewModel → Repository → APIService → APIClient → 服务端`

---

## 4. 关键设计决策

| 决策 | 方案 | 理由 |
|------|------|------|
| 并发安全 | `APIClient`、`TokenRefreshHandler` 用 Swift `actor` | 保证网络层线程安全，对标串行队列 |
| Token 刷新合并 | `TokenRefreshHandler` 用 `CheckedContinuation` 合并并发 401 | 避免多个请求同时触发刷新，只刷新一次 |
| 意图识别降级 | 在线 AI 优先，失败时本地关键词兜底 | 弱网/断网仍可用，提升可靠性 |
| 删除撤销 | 乐观更新 + 5 秒撤销 Snackbar | 立即反馈，误删可救回 |
| 状态管理 | iOS 17 `@Observable`（Observation 框架） | 比 `ObservableObject` 更细粒度、更高性能 |
| 安全存储 | Keychain（`AfterFirstUnlock`） | Token 加密存储，对标 Android EncryptedSharedPreferences |
| 语音识别 | Apple `SFSpeechRecognizer`（zh-CN） | 原生、免费、无需第三方，对标 DashScope |
| 配置外置 | 服务器地址、阿里云密钥写入 Info.plist | 环境切换无需改代码 |

---

## 5. 认证流程（阿里云号码一键登录）

```
用户点击"一键登录"
    │
    ▼
1. AuthService 调 POST /users/aliyun/auth-token  ──► 服务端返回 SDK authToken
    │
    ▼
2. AlicomFusionAuthManager.initialize(authToken)  初始化阿里云 SDK
    │
    ▼
3. SDK 后台完成 token 鉴权 → onSDKTokenAuthSuccess (isSDKReady=true)
    │
    ▼
4. startLoginScene(from: VC)  拉起 SDK 授权页，用户确认本机号码
    │
    ▼
5. onVerifySuccess(maskToken)  SDK 返回掩码 token
    │
    ▼
6. AuthService 调 POST /users/aliyun/login  (maskToken + deviceId)  ──► 服务端换取 accessToken/refreshToken
    │
    ▼
7. AuthStateManager 保存 (userId, accessToken, refreshToken, expiresAt) 到 Keychain
    │
    ▼
登录成功 → 首次进入引导页，否则进入主页
```

**Token 生命周期**：
- 访问受保护接口时，`APIClient` 自动注入 `Bearer accessToken`
- 遇 401 → `TokenRefreshHandler` 调 `/users/refresh` 刷新 → 重试原请求
- 刷新失败 → 清空 Keychain → `AuthEventBus.postLoginRequired()` → App 强制跳登录页

---

## 6. 导航流程

```
Splash（启动动画）
   │ 检查认证状态
   ├─ 已登录且 token 有效 ──────────────► Main（主页）
   ├─ token 已过期 → 尝试刷新
   │      ├─ 成功 ──────────────────────► Main
   │      └─ 失败 ──────────────────────► Login
   └─ 未登录 ───────────────────────────► Login（登录页）
                                            │ 登录成功
                                            ├─ 首次 ──► Onboarding（引导）──► Main
                                            └─ 老用户 ──────────────────────► Main

Main 可导航至：ItemList（清单） / Help（帮助） / Settings（设置）
```

由 `AppNavigationState`（`@Observable`）驱动，App 回到前台时校验登录态。

---

## 7. 设计系统

### 7.1 主色板

| 用途 | 颜色 | 色值 |
|------|------|------|
| 主色（雾松绿） | Primary | `#5B7E6B` |
| 主色变体（深松） | PrimaryVariant | `#476256` |
| 次色（暖沙金） | Secondary | `#C4A882` |
| 强调色（杏色，仅 FAB） | Accent | `#E8A87C` |
| 录音激活 | RecordingActive | `#C75450` |
| 成功 / 警告 / 错误 / 信息 | Semantic | `#5B9A6B` / `#E5A84B` / `#C75450` / `#5B8EC7` |

**中性色**：暖灰 10 级（0=白 → 900=近黑），用于文字、边框、背景层次。

### 7.2 字体大小（可调）

| 级别 | 字号 |
|------|------|
| 小 | 16pt |
| 中 | 20pt |
| 大 | 24pt |

---

## 8. 非功能性设计

| 维度 | 设计 |
|------|------|
| 可靠性 | 网络层 3 次重试 + 指数退避（5xx）；意图识别本地兜底 |
| 安全性 | Token 存 Keychain；HTTPS（当前测试环境为 HTTP，上线需切 HTTPS）|
| 可观测性 | 全链路 OSLog 日志 |
| 无障碍 | 字体大小可调、颜色对比度符合规范 |
| 本地化 | 中文 UI、zh-CN 日期格式与语音识别 |
| 性能 | `@Observable` 细粒度刷新；乐观更新减少等待感 |

---

## 9. 已知限制与后续优化

1. **HTTP 明文传输**：当前 `SERVER_BASE_URL` 为 `http://101.42.225.65:8080/api/`，上线前需切换 HTTPS 并移除 ATS 例外。
2. **主题切换未完全落地**：`ThemeManager` 提供 warm/neutral 选择，但 UI 尚未按主题应用不同色板。
3. **代码签名**：`DEVELOPMENT_TEAM` 为空，真机运行/上架需配置签名团队。
4. **图片能力**：`Item` 模型含 `imageUrl` 字段，但客户端暂未实现拍照/上传物品图片。

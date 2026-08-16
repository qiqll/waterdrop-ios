# WaterDrop iOS 项目说明

本项目是 **水滴管家（WaterDrop）** 的 iOS 端。水滴管家是一款 AI 驱动的个人物品位置管理应用，用户通过语音记录、查询、更新、删除物品位置。

## 三模块目录说明

水滴管家由三个模块组成，均位于同级目录 `~/Library/Mobile Documents/com~apple~CloudDocs/` 下：

| 模块 | 路径 | 技术栈 | 一句话职责 |
|------|------|--------|-----------|
| **iOS 客户端**（本项目） | `.../waterdrop_ios` | SwiftUI + MVVM + @Observable，iOS 17.0+ | iOS 端语音物品管家，与 Android 端功能/界面/体验一致 |
| **Android 客户端** | `.../waterdrop` | Kotlin + Retrofit + Room + Coroutines，minSdk 30 / targetSdk 34 | Android 端语音物品管家，语音识别用 DashScope，applicationId `com.example.itemfinder` |
| **服务端** | `.../wd_server` | Spring Boot 3.2.0 + Java 17 + MySQL | REST API 后端，20 个业务模块（item/ai/auth/group/membership/payment 等），对接 AI 大模型与阿里云号码认证 |

> 完整绝对路径见下方"关键路径"。三端通过 HTTP/JSON 通信，客户端调用的所有端点须与服务端 Controller 保持一致。

## 关键路径

- **iOS**：`/Users/yjqi/Library/Mobile Documents/com~apple~CloudDocs/waterdrop_ios/waterdrop_ios`
- **Android**：`/Users/yjqi/Library/Mobile Documents/com~apple~CloudDocs/waterdrop`
- **服务端**：`/Users/yjqi/Library/Mobile Documents/com~apple~CloudDocs/wd_server`

## 本项目补充说明

- 架构：MVVM（View → ViewModel → Repository → APIService → APIClient）
- 详细设计见 `DESIGN.md`，工程手册见 `TECH.md`
- 服务器地址配置在 `WaterDrop/Resources/Info.plist` 的 `SERVER_BASE_URL`

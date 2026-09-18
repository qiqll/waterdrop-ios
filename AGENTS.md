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

- **iOS**：`/Users/yjhome/Library/Mobile Documents/com~apple~CloudDocs/waterdrop_ios/waterdrop_ios`
- **Android**：`/Users/yjhome/Library/Mobile Documents/com~apple~CloudDocs/waterdrop`
- **服务端**：`/Users/yjhome/Library/Mobile Documents/com~apple~CloudDocs/wd_server`

> 服务端项目的说明见 `wd_server/AGENTS.md`。需要对照服务端 Controller、DTO、application.yml 里的配置（JWT 有效期、阿里云认证 scheme code、端点路径）时，可直接到该路径下读取。

## 本项目补充说明

- 架构：MVVM（View → ViewModel → Repository → APIService → APIClient）
- 详细设计见 `DESIGN.md`，工程手册见 `TECH.md`（配置项见 §9）

## 新克隆怎么跑起来

1. **补配置**（`Secrets.xcconfig` 已 gitignore，不复制出来就没有服务端地址）：

   ```bash
   cp Configs/Secrets.xcconfig.example Configs/Secrets.xcconfig
   # 然后填入真实的 SERVER_BASE_URL / ALICLOUD_* 值
   ```

   注意 xcconfig 把 `//` 当行内注释，URL 里的斜杠必须用模板里的 `SLASH` 变量拼，
   直接写 `http://...` 会被截断成 `http:`。

2. **生成工程**（`WaterDrop.xcodeproj` 由 `project.yml` 生成，改工程配置请改 yml 再重新生成，
   不要手改 pbxproj）：

   ```bash
   xcodegen generate --spec project.yml
   ```

3. **验证配置真的进了构建**（这步别省 —— 取值链路断了不会报错，只会得到空串）：

   ```bash
   export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
   xcodebuild -project WaterDrop.xcodeproj -target WaterDrop -configuration Debug -showBuildSettings \
     | grep SERVER_BASE_URL
   ```

   输出为空 = 配置没接上，App 会「能启动但所有请求失败」。

4. 编译 / 跑契约用例：

   ```bash
   xcodebuild -project WaterDrop.xcodeproj -scheme WaterDrop -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
   ./scripts/run-f011-contract-tests.sh    # F-011 契约回归，需本机服务端在跑
   ```

## 开发工作流（读公共库 → 执行 → 回写）

每个开发任务开始前，**先读公共文档库** `../../wd_server/docs/dev/README.md`，按其协议操作：

1. 开工前：读 `../../wd_server/docs/dev/待开发.md`，认领最上面的 `待开发` 条目（翻成 `进行中` + 记认领），
   在 `../../wd_server/docs/dev/plans/` 建 `F-###` 计划文件。
2. 实现：按计划做，跨端需求按 server→client 顺序推进，逐项打勾验收。
3. 完成后：回写 `../../wd_server/docs/dev/待开发.md`（置 `已完成`）+ `../../wd_server/docs/dev/完成记录.md` + 计划文件验收全勾。
4. 结束前重读 `../../wd_server/docs/dev/待开发.md`：若还有 `待开发` 条目且当前任务交接完成，继续下一个（依次开发下一个需求）。

**异步规则**：新需求不打断当前工作。用户把需求追加到 `../../wd_server/docs/dev/待开发.md` 即可；
当前任务完成后，按排队顺序自然接上。

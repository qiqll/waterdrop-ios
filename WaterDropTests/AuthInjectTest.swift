//
//  AuthInjectTest.swift
//
//  把宿主机换来的真实登录态写进模拟器 keychain，让 App 以「已登录」状态冷启动。
//
//  为什么需要它：
//  模拟器的 keychain 无法**从外部**写入（`simctl spawn booted security` 报
//  "Unable to obtain authorization" —— 条目没有 access group）。但本 target 配了
//  TEST_HOST，用例跑在宿主 App 的**进程内**，用的是 App 自己的 access group，
//  所以进程内的 SecItemAdd 能落进 App 之后能读到的那份 keychain。
//
//  与 F011ContractAPITests 的区别（两者都注入，但用途不同）：
//  - F011ContractAPITests 每个用例 setUp 注入、tearDown 清空，是**用完即弃**的；
//  - 本用例注入后**故意不清理**，keychain 条目要留到测试进程退出之后，
//    好让随后手动启动的 App 读到它。因此这里不重写 tearDown。
//
//  运行：scripts/inject-ios-auth.sh <手机号>
//  （手工 xcodebuild 时，token 必须经 `TEST_RUNNER_` 前缀的**环境变量**注入，
//   写在命令行上只会落到构建设置里，测试进程读不到。）
//

import XCTest
@testable import WaterDrop

final class AuthInjectTest: XCTestCase {

    /// 注入 (token, userId) 并断言它确实被 AuthStateManager 认成「已登录」。
    func testInjectAuthStateForManualWalkthrough() throws {
        let env = ProcessInfo.processInfo.environment
        guard let token = env["F011_ACCESS_TOKEN"], !token.isEmpty,
              let userId = env["F011_USER_ID"], !userId.isEmpty
        else {
            throw XCTSkip("未注入 F011_ACCESS_TOKEN / F011_USER_ID，请用 scripts/inject-ios-auth.sh 运行。")
        }

        // expiresAt 是**毫秒**。AuthStateManager 拿它和 Date().timeIntervalSince1970 * 1000 比，
        // 写秒会直接被判成过期（1970 年的毫秒数），表现为「注入了但一进 App 就被踢回登录页」。
        // 取 1 小时后：足够覆盖整轮手工点按，又不会留下一个长期有效的假登录态。
        let expiresAt = Int64(Date().timeIntervalSince1970 * 1000) + 3_600_000

        AuthStateManager.shared.saveAuthInfo(
            userId: userId, accessToken: token,
            refreshToken: "", expiresAt: expiresAt
        )

        XCTAssertTrue(
            AuthStateManager.shared.isAuthenticated,
            "写入后 isAuthenticated 应为 true —— 为 false 说明 keychain 没写进去，"
            + "或 expiresAt 被解成了过去时间"
        )
        print("AuthInjectTest: 登录态已写入 keychain，userId=\(userId)，expiresAt=\(expiresAt)")
    }
}

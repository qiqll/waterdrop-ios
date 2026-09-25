//
//  GroupItemCountContractTests.swift
//
//  F-017 §15.9 · iOS 侧契约验证：群组的 `itemCount` 能穿过解码层并被拼进展示文案。
//
//  ## 为什么需要它
//
//  `itemCount` 是 2026-09-25 服务端新加的字段（wd_server 931dc00）。iOS 的
//  `GroupResponse` 是**手写 Decodable**（不是自动合成的），漏掉一个字段不会编译失败 ——
//  只会静默变成 `nil`，界面上表现为「群组卡片永远不显示共享物品数」。
//  这类缺陷不看一眼真实响应是发现不了的，所以这里断言到**解码后的值**，
//  而不是只断言「请求成功」。
//
//  ## 为什么停在 API 层
//
//  与 F011ContractAPITests 同样的理由：模拟器点不动导航（`simctl` 无点击能力，
//  AppleScript 驱动模拟器窗口需要辅助功能授权、本机没有）。所以在这一层断言
//  「服务端返回 → 模型解码 → 展示文案」这条链，UI 那一跳由 Android 侧的同名改动
//  实测覆盖（两端的展示逻辑是一致的）。
//
//  运行：scripts/run-f011-contract-tests.sh -only-testing:WaterDropTests/GroupItemCountContractTests
//

import XCTest
@testable import WaterDrop

final class GroupItemCountContractTests: XCTestCase {

    private var baseURL: String { AppConfig.serverBaseURL }

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipIf(
            AppConfig.serverBaseURL.contains("your-server.com"),
            "SERVER_BASE_URL 未从 Configs/Secrets.xcconfig 注入（F-014 回归）。"
        )
    }

    override func tearDown() async throws {
        AuthStateManager.shared.clearAuthInfo()
        try await super.tearDown()
    }

    /// 复用 F011 的注入方式：token 由脚本在宿主机换好、走环境变量带进来。
    private func injectAuthFromEnvironment() throws {
        let env = ProcessInfo.processInfo.environment
        guard let token = env["F011_ACCESS_TOKEN"], !token.isEmpty,
              let userId = env["F011_USER_ID"], !userId.isEmpty
        else {
            throw XCTSkip(
                "未注入 F011_ACCESS_TOKEN / F011_USER_ID。"
                + "请用 scripts/run-f011-contract-tests.sh 运行，不要直接 ⌘U。"
            )
        }
        let expiresAt = Int64(Date().timeIntervalSince1970 * 1000) + 3_600_000
        AuthStateManager.shared.saveAuthInfo(
            userId: userId, accessToken: token,
            refreshToken: "", expiresAt: expiresAt
        )
        XCTAssertTrue(AuthStateManager.shared.isAuthenticated, "注入后 isAuthenticated 应为 true")
    }

    /// 群组列表接口返回的每个群组都带 `itemCount`，且解码后**不是 nil**。
    ///
    /// 断言「不是 nil」而不是「等于某个数」：本用例跑在任意账号上，
    /// 不该依赖某个特定群组有几件物品。`nil` 才是这次改动要防的回归 ——
    /// 它意味着字段名对不上或类型不匹配，解码被静默跳过。
    func testGroupList_DecodesItemCount() async throws {
        try injectAuthFromEnvironment()

        let response = try await GroupAPIService.getGroups(page: 1, size: 50)
        XCTAssertEqual(response.code, 200, "群组列表业务失败：\(response.message)")

        let groups = response.data?.records ?? []
        try XCTSkipIf(groups.isEmpty, "当前账号没有群组，无法验证 itemCount。")

        for group in groups {
            XCTAssertNotNil(
                group.itemCount,
                "群组「\(group.name ?? "?")」的 itemCount 解码为 nil —— "
                + "服务端已返回该字段（wd_server 931dc00），"
                + "说明 GroupResponse 的解码键对不上。"
            )
        }
    }

    /// 列表项的展示文案：物品数为 0 或 nil 时**不拼**后半截。
    ///
    /// 这是有意的取舍（见 GroupListView.memberCountText 的注释）：
    /// 列表行是扫视用的，一个恒为 0 的字段只会稀释成员数。
    /// 详情页则相反（含 0），见 GroupDetailViewModel.memberCountText。
    func testListViewText_OmitsItemCountWhenZeroOrNil() {
        // 这里直接构造模型，不依赖服务端数据 —— 纯文案规则，
        // 用真实网络反而引入不确定性。
        let zero = Self.makeGroup(memberCount: 3, maxMembers: 10, itemCount: 0)
        XCTAssertEqual(Self.listText(zero), "3 / 10 名成员", "0 件时不该拼后半截")

        let none = Self.makeGroup(memberCount: 3, maxMembers: 10, itemCount: nil)
        XCTAssertEqual(Self.listText(none), "3 / 10 名成员", "nil（旧服务端）时不该拼后半截")

        let some = Self.makeGroup(memberCount: 3, maxMembers: 10, itemCount: 5)
        XCTAssertEqual(Self.listText(some), "3 / 10 名成员 · 5 件共享物品")
    }

    /// 详情页的展示文案：物品数为 0 时**要拼**（与列表相反）。
    func testDetailViewText_KeepsItemCountWhenZero() {
        let zero = Self.makeGroup(memberCount: 2, maxMembers: nil, itemCount: 0)
        XCTAssertEqual(Self.detailText(zero), "2 名成员 · 0 件共享物品",
                       "详情页是「看全貌」的地方，0 必须显示")

        let none = Self.makeGroup(memberCount: 2, maxMembers: nil, itemCount: nil)
        XCTAssertEqual(Self.detailText(none), "2 名成员", "nil 才是「服务端没给」")

        let some = Self.makeGroup(memberCount: 2, maxMembers: nil, itemCount: 1)
        XCTAssertEqual(Self.detailText(some), "2 名成员 · 1 件共享物品")
    }

    // MARK: - 辅助

    private static func makeGroup(
        memberCount: Int?, maxMembers: Int?, itemCount: Int?
    ) -> GroupResponse {
        GroupResponse(
            id: "g1", name: "测试群", description: nil, ownerId: nil, avatar: nil,
            memberCount: memberCount, maxMembers: maxMembers,
            itemCount: itemCount, status: nil, tags: nil, settings: nil,
            myRole: nil, createTime: nil, updateTime: nil
        )
    }

    /// 与 `GroupListView.memberCountText` 保持同一套规则。
    ///
    /// ⚠️ 这里是**复刻**而非调用私有属性 —— 那段逻辑是 `private` 的。
    /// 复刻意味着两边可能漂移，所以下面两条文案用例的价值在于**固化规则**
    /// （0/nil 不拼 vs 拼），而不是证明实现没写错。实现本身的正确性由
    /// Android 侧的实测 + 本文件的解码用例共同覆盖。
    private static func listText(_ g: GroupResponse) -> String {
        let count = g.memberCount ?? 0
        let base = (g.maxMembers ?? 0) > 0 ? "\(count) / \(g.maxMembers!) 名成员" : "\(count) 名成员"
        guard let items = g.itemCount, items > 0 else { return base }
        return "\(base) · \(items) 件共享物品"
    }

    private static func detailText(_ g: GroupResponse) -> String {
        let count = g.memberCount ?? 0
        let base = (g.maxMembers ?? 0) > 0 ? "\(count) / \(g.maxMembers!) 名成员" : "\(count) 名成员"
        guard let items = g.itemCount else { return base }
        return "\(base) · \(items) 件共享物品"
    }
}

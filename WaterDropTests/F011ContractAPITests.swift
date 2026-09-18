//
//  F011ContractAPITests.swift
//
//  F-005 · iOS 运行性验证（API 层）
//
//  背景：F-011 的 D-1（昵称/头像写服务端）与 D-4（可选字段清空语义）在 iOS 侧的
//  运行性验证此前因 F-014（xcconfig 未接线 → 构建产物 SERVER_BASE_URL 为空）而阻塞。
//  F-014 修复后补上本用例。
//
//  为什么停在 API 层而不是 UI 层：
//  1. 阿里云融合认证一键登录需要真实 SIM 卡与运营商网关，模拟器无法完成，
//     因此无法在 CI/模拟器里走通「登录 → 进主页 → 编辑物品」的完整 UI 链路。
//  2. 模拟器的 keychain 无法从外部写入（`simctl spawn booted security` 报
//     "Unable to obtain authorization"），所以也不能像 Android 那样预置登录态。
//  于是这里改为：用短信验证码拿真 token → 直接调用 F-011 改动过的 iOS 函数 → 断言服务端真实响应。
//
//  运行前提：
//  - 本机已启动服务端（默认 http://127.0.0.1:8080/api，可用 F011_BASE_URL 覆盖）
//  - 由 scripts/run-f011-contract-tests.sh 预先登录，并把 (token, userId) 用环境变量注入。
//    iOS 测试 bundle 跑在模拟器里，拿不到宿主机进程、也连不上 Redis，所以登录态必须由脚本从外部带入。
//    这与 Android 侧 AuthInjectTest 的做法一致（token 在外部生成、再注入）。
//  - Configs/Secrets.xcconfig 存在（否则 AppConfig.serverBaseURL 走兜底值，用例会失败）
//
//  注意：ATS 在宿主 App 的 Info.plist 里按主机字面量放行了明文 HTTP（NSExceptionDomains），
//  服务端上 HTTPS 后应删掉那块 —— 否则 iOS 会以 -1022 直接拒绝所有请求。
//

import XCTest
@testable import WaterDrop

final class F011ContractAPITests: XCTestCase {

    // MARK: - 配置

    /// 服务端地址。直接读 `AppConfig.serverBaseURL`，不在这里另设覆盖入口 ——
    /// 用例并不自己拼 URL（请求都走 APIClient → ServerConfig.baseURL），
    /// 所以覆盖必须打在 AppConfig 认的那个键上（`SERVER_BASE_URL_OVERRIDE`），
    /// 否则会出现「断言里用的地址」和「实际请求的地址」不一致的假象。
    private var baseURL: String { AppConfig.serverBaseURL }

    /// 本次运行的测试物品名统一前缀，用于 tearDown 里精确清理。
    private let itemNamePrefix = "F011契约-"

    // MARK: - 生命周期

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipIf(
            AppConfig.serverBaseURL.contains("your-server.com"),
            "SERVER_BASE_URL 未从 Configs/Secrets.xcconfig 注入（F-014 回归）。"
        )
    }

    override func tearDown() async throws {
        await cleanupTestItems()
        AuthStateManager.shared.clearAuthInfo()
        try await super.tearDown()
    }

    // MARK: - 前置：注入一个真实登录态

    /// 由 scripts/run-f011-contract-tests.sh 传入的真 token。
    ///
    /// token 由脚本走「短信验证码登录」拿到（模拟器完成不了一键登录），这里只负责把它放进 keychain ——
    /// APIClient 的 requiresAuth 分支正是从那里取 token，等价于用户已登录后的状态。
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
        // expiresAt 取 1 小时后，否则 AuthStateManager 会判成 expired，APIClient 不发 token
        let expiresAt = Int64(Date().timeIntervalSince1970 * 1000) + 3_600_000
        AuthStateManager.shared.saveAuthInfo(
            userId: userId, accessToken: token,
            refreshToken: "", expiresAt: expiresAt
        )
        XCTAssertTrue(AuthStateManager.shared.isAuthenticated, "注入后 isAuthenticated 应为 true")
    }

    // MARK: - D-1：昵称同步到服务端

    /// D-1 场景 1：设置非空昵称 → 服务端读回应当是刚设置的值。
    func testD1_SetNickname_PersistsToServer() async throws {
        try injectAuthFromEnvironment()

        let expected = "F011昵称\(Int(Date().timeIntervalSince1970) % 10000)"
        let response = try await AuthAPIService.updateProfile(nickname: expected)
        XCTAssertEqual(response.code, 200, "updateProfile 应返回 200，实际 \(response.code)：\(response.message)")

        let profile = try await AuthAPIService.getUserProfile()
        XCTAssertEqual(profile.code, 200)
        XCTAssertEqual(profile.data?.nickname, expected, "服务端昵称应为刚设置的值（D-1：不再只写本地）")
    }

    /// D-1 场景 2：传 `""` 显式清空昵称 → 服务端应当被清空，而不是「保持不变」。
    ///
    /// 这条正是 D-4 契约在昵称字段上的体现：服务端用 `!= null` 判断，
    /// 空串能穿过去写库；若传 nil 则会被 MyBatis-Plus 的 NOT_NULL 策略跳过。
    func testD1_ClearNickname_WithEmptyString() async throws {
        try injectAuthFromEnvironment()

        // 先设一个非空基线——否则「清空后为空」可能本来就是空的，断言会变成空转
        _ = try await AuthAPIService.updateProfile(nickname: "F011清空前基线")
        let baseline = try await AuthAPIService.getUserProfile()
        XCTAssertEqual(baseline.data?.nickname, "F011清空前基线", "前置：非空基线应写入成功")

        // 清空
        let cleared = try await AuthAPIService.updateProfile(nickname: "")
        XCTAssertEqual(cleared.code, 200)

        let after = try await AuthAPIService.getUserProfile()
        let nickname = after.data?.nickname ?? ""
        XCTAssertTrue(
            nickname.isEmpty,
            "传 \"\" 应把昵称清空，实际读回「\(nickname)」——若仍是基线值说明空串被服务端跳过了"
        )
    }

    /// D-1 场景 3：传 nil（不修改昵称）→ 昵称应保持原样。
    ///
    /// 与场景 2 配对，证明「传 nil 保持」和「传 \"\" 清空」是两种不同语义。
    func testD1_NilNickname_PreservesExisting() async throws {
        try injectAuthFromEnvironment()

        let baseline = "F011保持基线\(Int(Date().timeIntervalSince1970) % 10000)"
        _ = try await AuthAPIService.updateProfile(nickname: baseline)

        // 只改 avatar，nickname 传 nil
        _ = try await AuthAPIService.updateProfile(nickname: nil, avatar: "https://example.com/f011.png")

        let after = try await AuthAPIService.getUserProfile()
        XCTAssertEqual(after.data?.nickname, baseline, "nickname 传 nil 时服务端不应改动它")
        XCTAssertEqual(after.data?.avatar, "https://example.com/f011.png", "同一请求里的 avatar 应写入")
    }

    // MARK: - D-4：物品可选字段清空语义（iOS 侧）

    /// D-4 场景 1：把 remark 改成 `""` → 服务端应真的清空。
    ///
    /// 用的是 ItemEditSheetView 走的同一条路径：Item → ItemCreateRequest(from:) → update(id:)。
    func testD4_ClearRemark_WithEmptyString() async throws {
        try injectAuthFromEnvironment()

        let itemId = await ItemRepository.shared.insert(ItemCreateRequest(
            name: itemNamePrefix + "清空备注", location: "客厅",
            category: "测试", remark: "非空基线备注"
        ))
        XCTAssertFalse(itemId.isEmpty, "前置：创建物品应成功")
        _ = await ItemRepository.shared.refreshItems()

        let created = ItemRepository.shared.allItems.first { $0.id == itemId }
        XCTAssertEqual(created?.remark, "非空基线备注", "前置：非空基线备注应写入成功")

        // 模拟用户在编辑页清空备注并保存
        var edited = try XCTUnwrap(created)
        edited.remark = ""   // ItemEditSheetView 里 trimmedRemark 直接赋值，不做 isEmpty ? nil
        let ok = await ItemRepository.shared.update(id: itemId, ItemCreateRequest(from: edited))
        XCTAssertTrue(ok, "update 应返回 true")

        _ = await ItemRepository.shared.refreshItems()
        let after = ItemRepository.shared.allItems.first { $0.id == itemId }
        XCTAssertEqual(after?.remark ?? "N/A", "", "备注应被清空（传 \"\" 而非 nil）")
    }

    /// D-4 场景 2：备注改为 `nil` → 服务端应保持原值不变。
    ///
    /// 与场景 1 配对，证明 `""` 与 `nil` 在真实服务端上是两种不同结果。
    func testD4_NilRemark_PreservesExisting() async throws {
        try injectAuthFromEnvironment()

        let itemId = await ItemRepository.shared.insert(ItemCreateRequest(
            name: itemNamePrefix + "保持备注", location: "卧室",
            category: "测试", remark: "应当被保持"
        ))
        XCTAssertFalse(itemId.isEmpty)
        _ = await ItemRepository.shared.refreshItems()

        var edited = try XCTUnwrap(ItemRepository.shared.allItems.first { $0.id == itemId })
        edited.remark = nil
        edited.location = "书房"   // 同请求里改一个别的字段，证明请求确实生效了
        let ok = await ItemRepository.shared.update(id: itemId, ItemCreateRequest(from: edited))
        XCTAssertTrue(ok)

        _ = await ItemRepository.shared.refreshItems()
        let after = ItemRepository.shared.allItems.first { $0.id == itemId }
        XCTAssertEqual(after?.remark, "应当被保持", "remark 传 nil 时服务端不应改动它")
        XCTAssertEqual(after?.location, "书房", "同请求里的 location 应已更新")
    }

    /// D-4 场景 3：非空 → 非空覆盖，确认不是「只能清空、不能改值」的假阳性。
    func testD4_NonEmptyRemark_Overwrites() async throws {
        try injectAuthFromEnvironment()

        let itemId = await ItemRepository.shared.insert(ItemCreateRequest(
            name: itemNamePrefix + "覆盖备注", location: "厨房",
            category: "测试", remark: "旧值"
        ))
        XCTAssertFalse(itemId.isEmpty)
        _ = await ItemRepository.shared.refreshItems()

        var edited = try XCTUnwrap(ItemRepository.shared.allItems.first { $0.id == itemId })
        edited.remark = "新值"
        let ok = await ItemRepository.shared.update(id: itemId, ItemCreateRequest(from: edited))
        XCTAssertTrue(ok)

        _ = await ItemRepository.shared.refreshItems()
        let after = ItemRepository.shared.allItems.first { $0.id == itemId }
        XCTAssertEqual(after?.remark, "新值", "非空备注应被覆盖")
    }

    // MARK: - D-2 回归：字段往返不丢

    /// D-2：创建一个带满可选字段的物品，读回后这些字段应逐一相等。
    ///
    /// 这条守的是 `ItemDto.toItem()` 里曾经被静默丢弃的那 11 个字段。
    func testD2_OptionalFieldsSurviveRoundTrip() async throws {
        try injectAuthFromEnvironment()

        let name = itemNamePrefix + "全字段"
        let itemId = await ItemRepository.shared.insert(ItemCreateRequest(
            name: name, location: "储藏室", description: "描述F011", category: "测试",
            locationDetail: "第三个柜子", tags: "标签A,标签B", value: 123.45,
            brand: "品牌F011", model: "型号F011", serialNumber: "SN-F011-0001",
            purchaseDate: "2026-01-15", warranty: "24个月", quantity: 3, unit: "个",
            remark: "备注F011"
        ))
        XCTAssertFalse(itemId.isEmpty)
        _ = await ItemRepository.shared.refreshItems()

        let item = try XCTUnwrap(ItemRepository.shared.allItems.first { $0.id == itemId })
        XCTAssertEqual(item.locationDetail, "第三个柜子")
        XCTAssertEqual(item.tags, "标签A,标签B")
        XCTAssertEqual(item.value, 123.45)
        XCTAssertEqual(item.brand, "品牌F011")
        XCTAssertEqual(item.model, "型号F011")
        XCTAssertEqual(item.serialNumber, "SN-F011-0001")
        XCTAssertEqual(item.purchaseDate, "2026-01-15")
        XCTAssertEqual(item.warranty, "24个月")
        XCTAssertEqual(item.quantity, 3)
        XCTAssertEqual(item.unit, "个")

        // 更新路径也要带上这些字段（ItemCreateRequest(from:) 全量回传），逐个改一遍再读回
        var edited = item
        edited.locationDetail = "第四个柜子"
        edited.tags = "标签C"
        edited.value = 999.99
        edited.brand = "品牌F011改"
        edited.model = "型号F011改"
        edited.serialNumber = "SN-F011-0002"
        edited.purchaseDate = "2026-02-20"
        edited.warranty = "36个月"
        edited.quantity = 7
        edited.unit = "箱"
        let ok = await ItemRepository.shared.update(id: itemId, ItemCreateRequest(from: edited))
        XCTAssertTrue(ok)

        _ = await ItemRepository.shared.refreshItems()
        let updated = try XCTUnwrap(ItemRepository.shared.allItems.first { $0.id == itemId })
        XCTAssertEqual(updated.locationDetail, "第四个柜子", "locationDetail 应可更新")
        XCTAssertEqual(updated.tags, "标签C", "tags 应可更新")
        XCTAssertEqual(updated.value, 999.99, "value 应可更新")
        XCTAssertEqual(updated.brand, "品牌F011改", "brand 应可更新")
        XCTAssertEqual(updated.model, "型号F011改", "model 应可更新")
        XCTAssertEqual(updated.serialNumber, "SN-F011-0002", "serialNumber 应可更新")
        XCTAssertEqual(updated.purchaseDate, "2026-02-20", "purchaseDate 应可更新")
        XCTAssertEqual(updated.warranty, "36个月", "warranty 应可更新")
        XCTAssertEqual(updated.quantity, 7, "quantity 应可更新")
        XCTAssertEqual(updated.unit, "箱", "unit 应可更新")
    }

    // MARK: - 清理

    /// 删除本次创建的全部测试物品，避免污染开发库。
    private func cleanupTestItems() async {
        guard AuthStateManager.shared.isAuthenticated else { return }
        await ItemRepository.shared.refreshItems()
        let mine = ItemRepository.shared.allItems.filter { $0.name.hasPrefix(itemNamePrefix) }
        for item in mine {
            await ItemRepository.shared.delete(id: item.id)
        }
    }
}

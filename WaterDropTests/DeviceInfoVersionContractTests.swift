//
//  DeviceInfoVersionContractTests.swift
//
//  F-018 ② · iOS 侧契约：User-Agent 必须带**真实的**版本号。
//
//  ## 为什么要测这个
//
//  此前 UA 是硬编码的 `"WaterDrop-iOS/1.0"`（`APIClient.swift`）——
//  **发版到 1.2 了 UA 里还是 1.0**。而服务端唯一的版本信号就是 UA，
//  于是它完全无法判断「用户在用哪个版本」，
//  `app_versions.min_support_version` 判定因此没有输入、形同虚设。
//
//  这类缺陷的特点是**不会报错、不会崩溃**：硬编码字符串永远「工作」，
//  只是它说的不是真话。所以只能靠契约测试守住 ——
//  断言 UA 与 `Bundle` 里的版本一致，而不是断言某个字面值。
//
//  ## 为什么断言「与 Bundle 一致」而不是「等于 1.0.0」
//
//  写死期望值的话，每次发版都要改测试，且改的时候很容易顺手把实现也改回硬编码。
//  断言「UA 里的版本 == Bundle 里的版本」则与发版解耦，且**恰好**表达了
//  「不能硬编码」这个约束 —— 硬编码的值一旦与 Bundle 不符就会红。
//

import XCTest
@testable import WaterDrop

final class DeviceInfoVersionContractTests: XCTestCase {

    /// UA 必须包含 `Bundle` 里的真实版本号。
    func testUserAgentCarriesRealAppVersion() {
        let version = DeviceInfo.appVersion
        XCTAssertNotEqual(version, "unknown",
                          "读不到 CFBundleShortVersionString —— 构建配置有问题")

        XCTAssertTrue(
            DeviceInfo.userAgent.contains(version),
            "UA 必须包含真实版本号。当前 UA=\(DeviceInfo.userAgent)，"
            + "Bundle 版本=\(version)。"
            + "若 UA 里出现的是别的值（如写死的 1.0），说明又硬编码回去了 —— "
            + "那会让服务端无法判断用户在用哪个版本"
        )
    }

    /// UA 必须带构建号。
    ///
    /// 只带营销版本时，一次「同版本号的热修」在服务端看来与旧版无异。
    func testUserAgentCarriesBuildNumber() {
        let build = DeviceInfo.buildNumber
        XCTAssertNotEqual(build, "unknown", "读不到 CFBundleVersion")

        XCTAssertTrue(
            DeviceInfo.userAgent.contains(build),
            "UA 必须包含构建号。当前 UA=\(DeviceInfo.userAgent)，build=\(build)"
        )
    }

    /// UA 前缀必须是服务端能解析的格式。
    ///
    /// 服务端 `extractVersionFromUserAgent` 按「名称/版本」取第一个 `/` 之后、
    /// 第一个空格之前的内容。Android 用的是
    /// `WaterDrop-Android/1.2.0`，两端共用同一个解析器 ——
    /// 前缀若被改掉（比如删掉 `WaterDrop-iOS/`），服务端就取不到版本了。
    func testUserAgentPrefixIsParseableByServer() {
        XCTAssertTrue(
            DeviceInfo.userAgent.hasPrefix("WaterDrop-iOS/"),
            "UA 必须以 `WaterDrop-iOS/` 开头 —— 服务端按这个格式解析版本号。"
            + "当前值：\(DeviceInfo.userAgent)"
        )

        // 复刻服务端的解析逻辑，验证真的能取出版本
        let parsed = Self.serverSideParse(DeviceInfo.userAgent)
        XCTAssertEqual(parsed, DeviceInfo.appVersion,
                       "用服务端的解析规则从 UA 取出的版本，必须等于真实版本")
    }

    /// 反证：硬编码的值必须与 Bundle 不符（否则这条契约就是恒真的空断言）。
    ///
    /// 这个用例本身不测实现，而是**校验测试的有效性** ——
    /// 如果某天 `MARKETING_VERSION` 恰好就是 1.0，那么「UA 含 1.0」这个断言
    /// 就无法区分「读的是 Bundle」和「硬编码 1.0」。本用例把这件事显式暴露出来。
    func testHardcodedLegacyValueWouldBeCaught() {
        let legacy = "1.0"   // 曾经硬编码在 APIClient 里的值
        if DeviceInfo.appVersion == legacy {
            XCTFail("""
                ⚠️ 测试有效性警告：当前 MARKETING_VERSION 恰好是 "\(legacy)"，\
                与曾经硬编码的值相同 —— 这会让「UA 含真实版本」的断言\
                无法区分实现是读 Bundle 还是写死的。\
                发版改掉 MARKETING_VERSION 后本用例会自动恢复有效。
                """)
        }
    }

    // MARK: - 复刻服务端解析

    /// 与 `UserServiceImpl.extractVersionFromUserAgent` 保持同一套规则。
    private static func serverSideParse(_ ua: String) -> String? {
        guard let slash = ua.firstIndex(of: "/") else { return nil }
        let after = ua[ua.index(after: slash)...]
        guard !after.isEmpty else { return nil }
        let v = after.prefix { $0 != " " }
        return v.isEmpty ? nil : String(v)
    }
}

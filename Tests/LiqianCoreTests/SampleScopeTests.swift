import XCTest
@testable import LiqianCore

// MARK: - 示例统计呈现修（v5.13 B 案）
//
// 隔离过滤本身是 PRO-AUDIT-2 定版、一字不动；本组钉死两点：
//  ① 示例身份只认存储 ID：用户自建的「示例·…」真礼簿（ID 不在
//     存储集合里）不被认领、其记录计入统计聚合输入；
//  ② 示例-only（有示例簿、无真实记录）时统计页走示例版空态。
final class SampleScopeTests: XCTestCase {

    /// ① 用户自建「示例·自家喜事」：标题以示例开头但 ID 未被
    /// 生成流程记录 → 不在示例集合内 → 聚合输入包含它的记录。
    func testUserLedgerTitledSampleIsNotClaimed() {
        let sampleID = UUID()
        let userLedgerID = UUID() // 标题「示例·自家喜事」，用户自建
        let result = SampleScope.sampleIDs(
            storedIDs: [sampleID],
            existingIDs: [sampleID, userLedgerID]
        )
        XCTAssertEqual(result, [sampleID])
        XCTAssertFalse(result.contains(userLedgerID))
        // 聚合输入＝全部记录滤掉示例集合：该用户的记录留得下
        let allLedgerIDs = [sampleID, userLedgerID, userLedgerID]
        let aggregated = allLedgerIDs.filter { !result.contains($0) }
        XCTAssertEqual(aggregated, [userLedgerID, userLedgerID])
    }

    /// 存储里有、账本已删的残留 ID 求交自然失效
    func testStaleStoredIDsDropOut() {
        let alive = UUID()
        let result = SampleScope.sampleIDs(
            storedIDs: [alive, UUID()], existingIDs: [alive])
        XCTAssertEqual(result, [alive])
    }

    /// ② 空态分档：示例-only 出示例版；真空出普通版；有真实记录不出空态
    func testStatsEmptyKind() {
        XCTAssertEqual(
            SampleScope.statsEmptyKind(hasSamples: true, realRecordCount: 0),
            .sampleOnly)
        XCTAssertEqual(
            SampleScope.statsEmptyKind(hasSamples: false, realRecordCount: 0),
            .realEmpty)
        XCTAssertEqual(
            SampleScope.statsEmptyKind(hasSamples: true, realRecordCount: 3),
            .none)
        XCTAssertEqual(
            SampleScope.statsEmptyKind(hasSamples: false, realRecordCount: 3),
            .none)
    }

    /// 源码守卫：标题认领不许回潮——SampleData 不得再按标题前缀判定
    func testSampleDataHasNoTitleClaim() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/LiqianApp/SampleData.swift")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("仓库源码不在预期路径，守卫跳过")
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(
            source.contains("hasPrefix(\"示例\")"),
            "示例身份只认存储 ID，标题前缀认领不得回潮")
        XCTAssertTrue(
            source.contains("SampleScope.sampleIDs("),
            "示例身份判定必须走 Core 纯函数")
    }
}

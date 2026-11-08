import XCTest
@testable import LiqianCore

// MARK: - App Group 解析（v4.6）：无 ALTAppGroups 时回退原始组名

final class AppGroupResolverTests: XCTestCase {
    func testFallbackWhenKeyMissing() {
        // 测试进程的 Bundle 没有 ALTAppGroups，必须回退常量——
        // 这也是正规签名安装（App Store / 开发者签名）下的预期行为
        XCTAssertEqual(AppGroupResolver.groupID(from: Bundle.main), AppGroupResolver.fallbackGroupID)
        XCTAssertEqual(AppGroupResolver.groupID, "group.site.didichou.liqian")
    }

    func testFallbackConstantMatchesProjectDeclaration() {
        // 与 Project.swift 三个 target 的 application-groups 声明同值，改一处必查这里
        XCTAssertEqual(AppGroupResolver.fallbackGroupID, "group.site.didichou.liqian")
        XCTAssertEqual(AppGroupResolver.altAppGroupsKey, "ALTAppGroups")
    }
}

// MARK: - 候选组名集（v5.11.1：Widget 读取侧多候选尝试的构造规则）

extension AppGroupResolverTests {
    private var suffixed: String { AppGroupResolver.fallbackGroupID + ".ABCDEFG123" }

    func testCandidatesResolvedIsFallbackOnly() {
        // 未重签（无 ALTAppGroups）：候选集只有原名一项，读取行为与旧版一致
        let result = AppGroupResolver.candidateGroupIDs(
            resolved: AppGroupResolver.fallbackGroupID, altGroups: []
        )
        XCTAssertEqual(result, [AppGroupResolver.fallbackGroupID])
    }

    func testCandidatesResolvedFirstThenFallback() {
        // 解析名带 TeamID 后缀：解析名打头、原名（去后缀变体）随后，去重保序
        let result = AppGroupResolver.candidateGroupIDs(
            resolved: suffixed, altGroups: [suffixed]
        )
        XCTAssertEqual(result, [suffixed, AppGroupResolver.fallbackGroupID])
    }

    func testCandidatesIncludeAllAltGroupsInOrder() {
        // ALTAppGroups 全部项纳入（不只首项），顺序即尝试顺序
        let other = "group.site.didichou.liqian.ZYXWVU9876"
        let result = AppGroupResolver.candidateGroupIDs(
            resolved: AppGroupResolver.fallbackGroupID, altGroups: [suffixed, other]
        )
        XCTAssertEqual(
            result, [AppGroupResolver.fallbackGroupID, suffixed, other]
        )
    }

    func testCandidatesStripAndAppendVariantsCoincide() {
        // 解析名是原名、后缀名只出现在 ALTAppGroups 里：补后缀变体即该项，
        // 集内不产生重复；反向（解析名带后缀）去后缀变体即原名，同样在集内
        let a = AppGroupResolver.candidateGroupIDs(
            resolved: AppGroupResolver.fallbackGroupID, altGroups: [suffixed]
        )
        XCTAssertEqual(a, [AppGroupResolver.fallbackGroupID, suffixed])
        let b = AppGroupResolver.candidateGroupIDs(resolved: suffixed, altGroups: [])
        XCTAssertEqual(b, [suffixed, AppGroupResolver.fallbackGroupID])
    }

    func testCandidatesSkipsBlanksAndDuplicates() {
        let result = AppGroupResolver.candidateGroupIDs(
            resolved: "  ", altGroups: ["", AppGroupResolver.fallbackGroupID]
        )
        XCTAssertEqual(result, [AppGroupResolver.fallbackGroupID])
    }

    func testTeamIDShape() {
        XCTAssertTrue(AppGroupResolver.isTeamIDShaped("ABCDEFG123"))
        XCTAssertFalse(AppGroupResolver.isTeamIDShaped("abc"))
        XCTAssertFalse(AppGroupResolver.isTeamIDShaped("abcdefg123")) // 小写不算
        XCTAssertFalse(AppGroupResolver.isTeamIDShaped("ABCDEFG1234")) // 11 位不算
    }

    func testTeamIDSuffixExtraction() {
        XCTAssertEqual(
            AppGroupResolver.teamIDSuffix(of: suffixed, base: AppGroupResolver.fallbackGroupID),
            "ABCDEFG123"
        )
        XCTAssertNil(
            AppGroupResolver.teamIDSuffix(
                of: AppGroupResolver.fallbackGroupID, base: AppGroupResolver.fallbackGroupID
            )
        )
        XCTAssertNil(
            AppGroupResolver.teamIDSuffix(
                of: AppGroupResolver.fallbackGroupID + ".v2",
                base: AppGroupResolver.fallbackGroupID
            )
        )
    }

    func testCurrentProcessCandidatesStartWithResolved() {
        // 测试进程无 ALTAppGroups：候选集退化为 [解析名]，与 testFallbackWhenKeyMissing 同境
        XCTAssertEqual(
            AppGroupResolver.candidateGroupIDs, [AppGroupResolver.groupID]
        )
    }
}

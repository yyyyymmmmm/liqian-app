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

import XCTest
@testable import LiqianCore

/// v5.14.2 存储锁定热修源码守卫：模式锁定/显式 URL/创建错误不吞/
/// 落盘自检/开关诚实化/硬显形，逐条钉死防回潮。口径与
/// NativePassGuardTests 同款：源码不在预期路径时跳过。
final class StoreLockGuardTests: XCTestCase {

    private func repoSource(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("仓库源码不在预期路径，守卫跳过：\(relative)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 模式锁定与显式 URL 必须在位：锁键、本地固定文件名、锁定分支
    func testModeLockAndExplicitURLPresent() throws {
        let cloud = try repoSource("Sources/LiqianApp/CloudSync.swift")
        XCTAssertTrue(cloud.contains("storeModeLock"), "模式锁定键必须在位")
        XCTAssertTrue(cloud.contains("storeModeLockBasis"), "锁定依据键必须在位")
        XCTAssertTrue(cloud.contains("LiqianLocal.store"), "本地店面必须显式固定文件名")
        XCTAssertTrue(cloud.contains("localStoreURL"), "本地店面 URL 必须单点定义")
    }

    /// CloudKit 创建错误不许再被 try? 吞：工厂必须交出 error 且留痕
    func testCloudCreationErrorIsSurfaced() throws {
        let cloud = try repoSource("Sources/LiqianApp/CloudSync.swift")
        XCTAssertTrue(cloud.contains("error: Error?"), "CloudKit 工厂必须把错误交出来")
        XCTAssertTrue(cloud.contains("cloud container creation failed"), "创建失败必须记日志")
        XCTAssertFalse(
            cloud.contains("return try? ModelContainer(for: schema, configurations: [config])"),
            "旧的 try? 静默吞错写法不得回潮")
    }

    /// 落盘自检与不安全硬显形链必须在位
    func testProbeAndHardSignalPresent() throws {
        let cloud = try repoSource("Sources/LiqianApp/CloudSync.swift")
        XCTAssertTrue(cloud.contains("runProbe"), "启动写-回读自检必须在位")
        XCTAssertTrue(cloud.contains("storageUnsafe"), "不安全状态必须单点发布")
        let content = try repoSource("Sources/LiqianApp/ContentView.swift")
        XCTAssertTrue(content.contains("cloudSync.storageUnsafe"), "红条必须改认 storageUnsafe")
        XCTAssertTrue(content.contains(".background(Color.red)"), "警示条必须固定红、不随主题")
        let guardFile = try repoSource("Sources/LiqianApp/StorageGuard.swift")
        XCTAssertTrue(guardFile.contains("storageBlockGuard"), "记账入口整页阻断必须在位")
    }

    /// 救援与开关诚实化、诊断行必须在位
    func testRescueToggleAndDiagnosticPresent() throws {
        let cloud = try repoSource("Sources/LiqianApp/CloudSync.swift")
        XCTAssertTrue(cloud.contains("StoreRescue.run"), "首次启动必须触发搁浅数据救援")
        XCTAssertTrue(cloud.contains("storeRescueV5142Done"), "救援完成标志守门必须在位")
        XCTAssertTrue(cloud.contains("syncToggleLockedOff"), "开关诚实化判定必须在位")
        let rescue = try repoSource("Sources/LiqianApp/StoreRescue.swift")
        XCTAssertTrue(rescue.contains("StoreMergePlanner.plan"), "救援比对必须走 Core 纯函数计划")
        let me = try repoSource("Sources/LiqianApp/MeView.swift")
        XCTAssertTrue(me.contains("cloudSync.diagnosticLine"), "数据页必须有存储诊断行")
        XCTAssertTrue(me.contains("syncToggleLockedOff"), "数据页开关必须消费诚实化判定")
    }

    /// 五个记账入口都必须挂整页阻断（一处漏挂＝不安全时还能记账）
    func testAllRecordEntriesGuarded() throws {
        for file in [
            "RecordFormView", "LedgerFormView", "BatchEntryView",
            "SceneModeView", "QuickSentenceView",
        ] {
            let source = try repoSource("Sources/LiqianApp/\(file).swift")
            XCTAssertTrue(
                source.contains(".storageBlockGuard()"),
                "\(file) 必须挂存储阻断守卫")
        }
    }
}

import XCTest
@testable import LiqianCore

// MARK: - 改名校验（v5.10：纯函数；重名判定排除旧名自身）

final class RelationRenameValidationTests: XCTestCase {
    private let existing = ["亲戚", "朋友", "同事", "同学", "邻居", "其他", "闺蜜", "战友"]

    func testRenameToFreshNamePasses() {
        XCTAssertEqual(
            RelationCatalog.validateRename(from: "闺蜜", rawNew: " 好姐妹 ", existing: existing),
            .success("好姐妹")
        )
    }

    func testRenameToSameNameIsNoOpPass() {
        XCTAssertEqual(
            RelationCatalog.validateRename(from: "闺蜜", rawNew: "闺蜜", existing: existing),
            .success("闺蜜")
        )
    }

    func testRenameToSystemNameRejected() {
        XCTAssertEqual(
            RelationCatalog.validateRename(from: "闺蜜", rawNew: "朋友", existing: existing),
            .failure(.duplicate)
        )
    }

    func testRenameToOtherCustomRejected() {
        XCTAssertEqual(
            RelationCatalog.validateRename(from: "闺蜜", rawNew: "战友", existing: existing),
            .failure(.duplicate)
        )
    }

    func testRenameEmptyAndTooLongRejected() {
        XCTAssertEqual(
            RelationCatalog.validateRename(from: "闺蜜", rawNew: "  ", existing: existing),
            .failure(.empty)
        )
        XCTAssertEqual(
            RelationCatalog.validateRename(from: "闺蜜", rawNew: "一二三四五六七", existing: existing),
            .failure(.tooLong)
        )
    }
}

// MARK: - 目录改名与排序（隔离 UserDefaults suite）

final class RelationRenameStorageTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.relation-rename.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testRenameCustomReplacesInPlaceKeepingOrder() {
        RelationCatalog.setCustom(["战友", "闺蜜", "发小"], in: defaults)
        XCTAssertTrue(RelationCatalog.renameCustom(from: "闺蜜", to: "好姐妹", in: defaults))
        XCTAssertEqual(RelationCatalog.custom(in: defaults), ["战友", "好姐妹", "发小"])
        XCTAssertEqual(
            RelationCatalog.all(in: defaults),
            LiqianConstants.relations + ["战友", "好姐妹", "发小"]
        )
    }

    func testRenameSystemOrMissingReturnsFalseAndKeepsCatalog() {
        RelationCatalog.setCustom(["闺蜜"], in: defaults)
        XCTAssertFalse(RelationCatalog.renameCustom(from: "朋友", to: "好友", in: defaults))
        XCTAssertFalse(RelationCatalog.renameCustom(from: "不存在", to: "好友", in: defaults))
        XCTAssertEqual(RelationCatalog.custom(in: defaults), ["闺蜜"])
    }

    func testExtractCustomOrderFollowsDraggedFullOrder() {
        let customs = ["战友", "闺蜜", "发小"]
        // 整表里自定义被拖成 发小 → 战友 → 闺蜜（系统行位置变化不影响提取）
        let dragged = ["亲戚", "发小", "朋友", "战友", "同事", "闺蜜", "同学", "邻居", "其他"]
        XCTAssertEqual(
            RelationCatalog.extractCustomOrder(from: dragged, customs: customs),
            ["发小", "战友", "闺蜜"]
        )
    }

    func testApplyOrderPersistsCustomSequence() {
        RelationCatalog.setCustom(["战友", "闺蜜", "发小"], in: defaults)
        let dragged = LiqianConstants.relations + ["发小", "闺蜜", "战友"]
        RelationCatalog.applyOrder(fullOrder: dragged, in: defaults)
        XCTAssertEqual(RelationCatalog.custom(in: defaults), ["发小", "闺蜜", "战友"])
        // 选择器口径：all() 的自定义段与新顺序一致
        XCTAssertEqual(
            Array(RelationCatalog.all(in: defaults).suffix(3)),
            ["发小", "闺蜜", "战友"]
        )
    }
}

// MARK: - 级联值映射：套用后旧名零残留

final class RelationCascadeTests: XCTestCase {
    func testMapOnlyExactMatch() {
        XCTAssertEqual(RelationCascade.map("闺蜜", from: "闺蜜", to: "好姐妹"), "好姐妹")
        XCTAssertEqual(RelationCascade.map("朋友", from: "闺蜜", to: "好姐妹"), "朋友")
        XCTAssertEqual(RelationCascade.map("", from: "闺蜜", to: "好姐妹"), "")
    }

    func testAppliedLeavesZeroResidueAcrossAllReferenceKinds() {
        // 三类引用合并验：记录关系值、提醒关系值、回收站快照关系值同口径
        let recordValues = ["闺蜜", "朋友", "闺蜜", "战友"]
        let reminderValues = ["闺蜜", ""]
        let trashValues = ["闺蜜", "邻居"]
        let all = recordValues + reminderValues + trashValues
        let renamed = RelationCascade.applied(to: all, from: "闺蜜", to: "好姐妹")
        XCTAssertEqual(
            LedgerMath.relationReferenceCount(of: "闺蜜", in: renamed), 0,
            "级联后旧名必须零残留"
        )
        XCTAssertEqual(LedgerMath.relationReferenceCount(of: "好姐妹", in: renamed), 4)
        // 无关值一位不动
        XCTAssertEqual(LedgerMath.relationReferenceCount(of: "朋友", in: renamed), 1)
        XCTAssertEqual(LedgerMath.relationReferenceCount(of: "", in: renamed), 1)
    }

    func testReferenceCountMatchesCascadeScope() {
        // 待送出记录也落在引用里：计数不分状态，级联范围与之一致
        let values = ["战友", "战友", "朋友"]
        XCTAssertEqual(LedgerMath.relationReferenceCount(of: "战友", in: values), 2)
        XCTAssertEqual(LedgerMath.relationReferenceCount(of: "同学", in: values), 0)
    }
}

// MARK: - 关系用量（行内「N 人 · M 笔」；与 relationSummary 同口径）

final class RelationUsageTests: XCTestCase {
    private func entry(
        person: String, relation: String, cents: Int = 10_000,
        direction: String = LiqianConstants.received,
        status: String = LiqianConstants.sentStatus
    ) -> EntrySnapshot {
        EntrySnapshot(
            person: person, relation: relation, amountCents: cents,
            direction: direction, date: "2026-01-01", status: status
        )
    }

    func testUsageCountsDistinctPeopleAndRecords() {
        let entries = [
            entry(person: "张三", relation: "战友"),
            entry(person: "张三", relation: "战友"),
            entry(person: "李四", relation: "战友"),
            entry(person: "张三", relation: "闺蜜"),
        ]
        let usage = Dictionary(
            uniqueKeysWithValues: LedgerMath.relationUsage(from: entries).map { ($0.relation, $0) }
        )
        XCTAssertEqual(usage["战友"]?.people, 2)
        XCTAssertEqual(usage["战友"]?.records, 3)
        // 同一人可出现在多个关系下，各关系分别计数
        XCTAssertEqual(usage["闺蜜"]?.people, 1)
        XCTAssertEqual(usage["闺蜜"]?.records, 1)
    }

    func testUsageExcludesPendingSendLikeRelationSummary() {
        let entries = [
            entry(person: "张三", relation: "战友"),
            entry(
                person: "王五", relation: "战友",
                direction: LiqianConstants.given, status: LiqianConstants.pendingStatus
            ),
        ]
        let usage = LedgerMath.relationUsage(from: entries)
        XCTAssertEqual(usage.count, 1)
        XCTAssertEqual(usage.first?.people, 1)
        XCTAssertEqual(usage.first?.records, 1)
        // 与 relationSummary 的笔数口径对齐
        let summary = LedgerMath.relationSummary(from: entries)
        XCTAssertEqual(summary.first?.count, usage.first?.records)
    }
}

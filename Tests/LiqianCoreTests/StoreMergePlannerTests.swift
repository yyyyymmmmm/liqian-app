import XCTest
@testable import LiqianCore

// MARK: - v5.14.2 搁浅数据救援：合并计划纯逻辑单测
// 钉死三件事：①同 ID 绝不重复并入；②二次运行（主店已含并入结果）
// 零新增；③孤儿实体（挂靠的礼簿/记录两边都不在）不并入。

final class StoreMergePlannerTests: XCTestCase {

    private let ledgerA = UUID()
    private let ledgerB = UUID()
    private let ledgerOrphan = UUID()
    private let recordA = UUID()
    private let recordB = UUID()
    private let recordOrphan = UUID()

    /// 主店：有礼簿 A 及其一条记录；源店：A（含同 ID 记录＋一条新记录）
    /// ＋整本 B（礼簿＋记录＋成员）——B 整本并入，A 只补新记录
    func testStrandedLedgerMergedAndExistingLedgerOnlyToppedUp() {
        let main = StoreSnapshotIDs(
            ledgerIDs: [ledgerA],
            records: [StoreChildRef(id: recordA, ledgerID: ledgerA)]
        )
        let memberB = UUID()
        let source = StoreSnapshotIDs(
            ledgerIDs: [ledgerA, ledgerB],
            records: [
                StoreChildRef(id: recordA, ledgerID: ledgerA),
                StoreChildRef(id: recordB, ledgerID: ledgerA),
                StoreChildRef(id: UUID(), ledgerID: ledgerB),
            ],
            members: [StoreChildRef(id: memberB, ledgerID: ledgerB)]
        )
        let plan = StoreMergePlanner.plan(main: main, source: source)
        XCTAssertEqual(plan.ledgerIDs, [ledgerB], "只有主店没有的礼簿整本并入")
        XCTAssertTrue(plan.recordIDs.contains(recordB), "已存在礼簿下的新记录也要补并入")
        XCTAssertFalse(plan.recordIDs.contains(recordA), "同 ID 记录绝不重复并入")
        XCTAssertEqual(plan.recordIDs.count, 2, "A 的新记录＋B 的记录，共 2 笔")
        XCTAssertEqual(plan.memberIDs, [memberB], "随礼簿并入的成员一并过来")
    }

    /// 幂等：把计划并进主店快照后重算，零新增（救援重跑/多候选店面安全）
    func testSecondRunProducesEmptyPlan() {
        let main = StoreSnapshotIDs(ledgerIDs: [ledgerA])
        let blessingB = UUID()
        let source = StoreSnapshotIDs(
            ledgerIDs: [ledgerA, ledgerB],
            records: [StoreChildRef(id: recordB, ledgerID: ledgerB)],
            blessings: [StoreBlessingRef(id: blessingB, recordID: recordB)],
            reminderIDs: [UUID()]
        )
        let plan = StoreMergePlanner.plan(main: main, source: source)
        XCTAssertFalse(plan.isEmpty)
        // 模拟并入后的主店：源店全部实体都进了主店
        let merged = StoreSnapshotIDs(
            ledgerIDs: main.ledgerIDs.union(source.ledgerIDs),
            records: source.records,
            blessings: source.blessings,
            reminderIDs: source.reminderIDs
        )
        XCTAssertTrue(
            StoreMergePlanner.plan(main: merged, source: source).isEmpty,
            "已并入后再算必须为空计划，救援重跑零新增")
    }

    /// 同 ID 全量重合：计划为空（什么都不复制）
    func testIdenticalStoresProduceEmptyPlan() {
        let snap = StoreSnapshotIDs(
            ledgerIDs: [ledgerA],
            records: [StoreChildRef(id: recordA, ledgerID: ledgerA)],
            reminderIDs: [UUID()]
        )
        XCTAssertTrue(StoreMergePlanner.plan(main: snap, source: snap).isEmpty)
    }

    /// 孤儿不并入：记录/成员/回执挂的礼簿两边都不在，祝福挂的记录不在
    func testOrphansAreNotMerged() {
        let main = StoreSnapshotIDs(ledgerIDs: [ledgerA])
        let source = StoreSnapshotIDs(
            records: [StoreChildRef(id: recordOrphan, ledgerID: ledgerOrphan)],
            members: [StoreChildRef(id: UUID(), ledgerID: ledgerOrphan)],
            receipts: [StoreChildRef(id: UUID(), ledgerID: ledgerOrphan)],
            blessings: [StoreBlessingRef(id: UUID(), recordID: recordOrphan)]
        )
        let plan = StoreMergePlanner.plan(main: main, source: source)
        XCTAssertTrue(plan.isEmpty, "挂靠不成立的孤儿实体一概不并入")
    }

    /// 祝福随记录并入：记录本次并入时，挂它的祝福也并入；
    /// 记录已在主店时，缺的祝福同样补并入
    func testBlessingFollowsItsRecord() {
        let blessingNew = UUID()
        let blessingExisting = UUID()
        let main = StoreSnapshotIDs(
            ledgerIDs: [ledgerA],
            records: [StoreChildRef(id: recordA, ledgerID: ledgerA)]
        )
        let source = StoreSnapshotIDs(
            ledgerIDs: [ledgerA],
            records: [
                StoreChildRef(id: recordA, ledgerID: ledgerA),
                StoreChildRef(id: recordB, ledgerID: ledgerA),
            ],
            blessings: [
                StoreBlessingRef(id: blessingNew, recordID: recordB),
                StoreBlessingRef(id: blessingExisting, recordID: recordA),
            ]
        )
        let plan = StoreMergePlanner.plan(main: main, source: source)
        XCTAssertEqual(plan.blessingIDs, [blessingNew, blessingExisting])
    }

    /// 子实体同 ID 去重＋挂靠过滤并行：签名同 ID 不重入、
    /// 挂在并入礼簿上的新签名入、挂未知礼簿的不入
    func testChildEntitiesDedupeAndFilter() {
        let signatureKnown = UUID()
        let signatureNew = UUID()
        let bindingNew = UUID()
        let main = StoreSnapshotIDs(
            ledgerIDs: [ledgerA],
            signatures: [StoreChildRef(id: signatureKnown, ledgerID: ledgerA)]
        )
        let source = StoreSnapshotIDs(
            ledgerIDs: [ledgerA, ledgerB],
            signatures: [
                StoreChildRef(id: signatureKnown, ledgerID: ledgerA),
                StoreChildRef(id: signatureNew, ledgerID: ledgerB),
                StoreChildRef(id: UUID(), ledgerID: ledgerOrphan),
            ],
            bindings: [StoreChildRef(id: bindingNew, ledgerID: ledgerB)]
        )
        let plan = StoreMergePlanner.plan(main: main, source: source)
        XCTAssertEqual(plan.signatureIDs, [signatureNew])
        XCTAssertEqual(plan.bindingIDs, [bindingNew])
    }

    /// 重要日子不挂礼簿：按 ID 去重并入
    func testRemindersMergeByID() {
        let known = UUID()
        let fresh = UUID()
        let main = StoreSnapshotIDs(reminderIDs: [known])
        let source = StoreSnapshotIDs(reminderIDs: [known, fresh])
        XCTAssertEqual(StoreMergePlanner.plan(main: main, source: source).reminderIDs, [fresh])
    }

    /// 空源店：空计划（候选店面不存在/为空时安静跳过的依据）
    func testEmptySourceProducesEmptyPlan() {
        let main = StoreSnapshotIDs(ledgerIDs: [ledgerA])
        XCTAssertTrue(StoreMergePlanner.plan(main: main, source: StoreSnapshotIDs()).isEmpty)
    }
}

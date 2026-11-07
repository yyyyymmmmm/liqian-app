import XCTest
@testable import LiqianCore

// MARK: - 自定义关系校验（纯函数）

final class RelationValidationTests: XCTestCase {
    private let existing = RelationCatalog.all(in: UserDefaults(suiteName: "validation-none")!)

    func testTrimsAndAccepts() {
        XCTAssertEqual(
            RelationCatalog.validate("  闺蜜 ", existing: existing),
            .success("闺蜜")
        )
    }

    func testEmptyRejected() {
        XCTAssertEqual(RelationCatalog.validate("", existing: existing), .failure(.empty))
        XCTAssertEqual(RelationCatalog.validate("   ", existing: existing), .failure(.empty))
    }

    func testTooLongRejected() {
        // 7 个字 > 上限 6
        XCTAssertEqual(
            RelationCatalog.validate("一二三四五六七", existing: existing),
            .failure(.tooLong)
        )
        // 恰好 6 个字可过
        XCTAssertEqual(
            RelationCatalog.validate("一二三四五六", existing: existing),
            .success("一二三四五六")
        )
    }

    func testDuplicateAgainstSystemRejected() {
        XCTAssertEqual(
            RelationCatalog.validate("朋友", existing: existing),
            .failure(.duplicate)
        )
    }

    func testDuplicateAgainstCustomRejected() {
        XCTAssertEqual(
            RelationCatalog.validate("闺蜜", existing: existing + ["闺蜜"]),
            .failure(.duplicate)
        )
    }
}

// MARK: - 自定义关系存储（隔离 UserDefaults suite，不碰 .standard）

final class RelationCatalogStorageTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.relations.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testAllIsSystemThenCustomInAddOrder() {
        RelationCatalog.setCustom(["战友", "闺蜜"], in: defaults)
        XCTAssertEqual(
            RelationCatalog.all(in: defaults),
            LiqianConstants.relations + ["战友", "闺蜜"]
        )
    }

    func testSetCustomSanitizes() {
        // 与系统重名、条目自身重复、空白与空串一律清掉，保序
        RelationCatalog.setCustom([" 闺蜜 ", "朋友", "闺蜜", "", "  ", "战友"], in: defaults)
        XCTAssertEqual(RelationCatalog.custom(in: defaults), ["闺蜜", "战友"])
    }

    func testAddAndRemove() {
        XCTAssertEqual(RelationCatalog.add("发小", in: defaults), .success("发小"))
        XCTAssertEqual(RelationCatalog.custom(in: defaults), ["发小"])
        // 重复添加被拒且不改变列表
        XCTAssertEqual(RelationCatalog.add("发小", in: defaults), .failure(.duplicate))
        XCTAssertEqual(RelationCatalog.custom(in: defaults), ["发小"])
        RelationCatalog.remove("发小", in: defaults)
        XCTAssertEqual(RelationCatalog.custom(in: defaults), [])
        // 删系统关系无效果（它不在自定义列表里，all 仍含系统词表）
        RelationCatalog.remove("朋友", in: defaults)
        XCTAssertTrue(RelationCatalog.all(in: defaults).contains("朋友"))
    }

    func testPickerOptionsFallback() {
        RelationCatalog.setCustom(["闺蜜"], in: defaults)
        let base = RelationCatalog.all(in: defaults)
        // 已在目录内：不重复并入
        XCTAssertEqual(RelationCatalog.pickerOptions(including: "闺蜜", in: defaults), base)
        XCTAssertEqual(RelationCatalog.pickerOptions(including: "朋友", in: defaults), base)
        // 空串：不并入
        XCTAssertEqual(RelationCatalog.pickerOptions(including: "", in: defaults), base)
        // 已删的自定义关系：临时并入末尾，选中态不丢
        XCTAssertEqual(
            RelationCatalog.pickerOptions(including: "老战友", in: defaults),
            base + ["老战友"]
        )
    }
}

// MARK: - 备份段（customRelations 可选段：带走、旧备份兼容、空不写段）

final class RelationBackupTests: XCTestCase {
    func testRoundTrip() throws {
        let data = LiqianBackup.makeBackup(
            ledgers: [], records: [], customRelations: ["闺蜜", "战友"]
        )
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("customRelations"))
        XCTAssertEqual(LiqianBackup.parseBackupRelations(data), ["闺蜜", "战友"])
        // 主段照常可解
        let parsed = try LiqianBackup.parseBackupFull(data)
        XCTAssertTrue(parsed.ledgers.isEmpty)
    }

    func testEmptyRelationsWriteNoSegment() {
        let data = LiqianBackup.makeBackup(ledgers: [], records: [])
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("customRelations"))
        XCTAssertEqual(LiqianBackup.parseBackupRelations(data), [])
    }

    func testOldBackupWithoutSegmentDecodes() throws {
        // 旧备份 JSON：根本没有 customRelations 键
        let old = #"{"ledgers":[],"records":[]}"#
        let data = Data(old.utf8)
        let parsed = try LiqianBackup.parseBackupFull(data)
        XCTAssertTrue(parsed.ledgers.isEmpty)
        XCTAssertEqual(LiqianBackup.parseBackupRelations(data), [])
    }
}

// MARK: - 解析放宽（粘贴解析与 AI 解析认自定义关系；走 .standard 需存取还原）

final class RelationParserTests: XCTestCase {
    private var savedRaw: Any?

    override func setUp() {
        super.setUp()
        savedRaw = UserDefaults.standard.object(forKey: RelationCatalog.customRelationsKey)
        UserDefaults.standard.removeObject(forKey: RelationCatalog.customRelationsKey)
    }

    override func tearDown() {
        if let savedRaw {
            UserDefaults.standard.set(savedRaw, forKey: RelationCatalog.customRelationsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: RelationCatalog.customRelationsKey)
        }
        super.tearDown()
    }

    /// 3 字自定义关系「老战友」：不在目录时粘贴解析认不出（>2 字非词表词），
    /// 加进目录后能认出。2 字关系本来就有「任意 2 字」兜底，这里专测目录路径。
    func testTextParserRecognizesCustomRelation() {
        let before = LedgerTextParser.parse("张三 500 老战友")
        XCTAssertEqual(before.count, 1)
        if case .success = before[0].result {
            XCTFail("目录外 3 字关系不应被认出")
        }
        RelationCatalog.add("老战友")
        let after = LedgerTextParser.parse("张三 500 老战友")
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(
            after[0].result,
            .success(name: "张三", amountCents: 50_000, relation: "老战友")
        )
    }

    /// AI 解析：关系严格走目录——目录外被过滤为 nil，自定义关系保留。
    func testAIParseKeepsCustomRelation() throws {
        let json = """
        {"records":[
          {"name":"小美","amountYuan":500,"relation":"闺蜜","method":"微信","direction":"received"}
        ]}
        """
        let before = try AIParse.decode(Data(json.utf8))
        XCTAssertNil(before.records[0].relation)
        RelationCatalog.add("闺蜜")
        let after = try AIParse.decode(Data(json.utf8))
        XCTAssertEqual(after.records[0].relation, "闺蜜")
    }
}

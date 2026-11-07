import XCTest
@testable import LiqianCore

// MARK: - 礼谱内页分段（v3.1：按关系分组＋保序）

private struct SectionRow {
    let name: String
    let relation: String
}

final class LibuSectionGroupingTests: XCTestCase {
    private func sections(
        _ rows: [(name: String, relation: String)]
    ) -> [LibuRelationSection<SectionRow>] {
        LibuSections.groupByRelation(
            rows.map { SectionRow(name: $0.name, relation: $0.relation) }
        ) { $0.relation }
    }

    /// 多关系：段序严格按枚举序（亲戚/朋友/同事/同学/邻居/其他），
    /// 与入参出现顺序无关；段内保持入参相对顺序。
    func testMultipleRelationsFollowEnumOrder() {
        let result = sections([
            ("甲", "同学"), ("乙", "亲戚"), ("丙", "朋友"),
            ("丁", "亲戚"), ("戊", "邻居"), ("己", "同事"), ("庚", "其他"),
        ])
        XCTAssertEqual(
            result.map(\.relation),
            ["亲戚", "朋友", "同事", "同学", "邻居", "其他"]
        )
        XCTAssertEqual(result[0].records.map(\.name), ["乙", "丁"])
        XCTAssertEqual(result[1].records.map(\.name), ["丙"])
        XCTAssertEqual(result[5].records.map(\.name), ["庚"])
    }

    /// 枚举外关系附后（与汇总页按關係小計同口径），不吞、不改名。
    func testUnknownRelationAppendedAfterKnown() {
        let result = sections([
            ("甲", "老乡"), ("乙", "朋友"), ("丙", "其他"),
        ])
        XCTAssertEqual(result.map(\.relation), ["朋友", "其他", "老乡"])
        XCTAssertEqual(result[2].records.map(\.name), ["甲"])
    }

    /// 单关系：只出一段，记录全数保序。
    func testSingleRelation() {
        let result = sections([
            ("甲", "朋友"), ("乙", "朋友"), ("丙", "朋友"),
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].relation, "朋友")
        XCTAssertEqual(result[0].records.map(\.name), ["甲", "乙", "丙"])
    }

    /// 空记录：无段。
    func testEmpty() {
        XCTAssertTrue(sections([]).isEmpty)
    }

    /// 空关系归入「其他」段，与显式「其他」合并。
    func testBlankRelationFallsIntoOther() {
        let result = sections([
            ("甲", ""), ("乙", "其他"), ("丙", "朋友"),
        ])
        XCTAssertEqual(result.map(\.relation), ["朋友", "其他"])
        XCTAssertEqual(result[1].records.map(\.name), ["甲", "乙"])
    }
}

// MARK: - 段序走关系目录（自定义关系：系统之后、添加序、目录外附后）

final class LibuCatalogOrderTests: XCTestCase {
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

    private func sections(
        _ rows: [(name: String, relation: String)]
    ) -> [LibuRelationSection<SectionRow>] {
        LibuSections.groupByRelation(
            rows.map { SectionRow(name: $0.name, relation: $0.relation) }
        ) { $0.relation }
    }

    /// 自定义关系按添加序排在系统词表之后（不是字面序）；
    /// 目录外的关系（已删的自定义等）仍按字面序附在最后。
    func testCustomRelationsFollowCatalogOrder() {
        RelationCatalog.setCustom(["战友", "闺蜜"])
        let result = sections([
            ("甲", "闺蜜"), ("乙", "老乡"), ("丙", "战友"),
            ("丁", "朋友"), ("戊", "闺蜜"),
        ])
        XCTAssertEqual(
            result.map(\.relation),
            ["朋友", "战友", "闺蜜", "老乡"]
        )
        XCTAssertEqual(result[2].records.map(\.name), ["甲", "戊"])
    }
}

// MARK: - 段题签笔数（v3.1：汉字数字，账簿计数式起头省「壹」）

final class LibuChineseCountTests: XCTestCase {
    func testCounts() {
        XCTAssertEqual(LibuText.chineseCount(0), "零")
        XCTAssertEqual(LibuText.chineseCount(1), "壹")
        XCTAssertEqual(LibuText.chineseCount(9), "玖")
        XCTAssertEqual(LibuText.chineseCount(10), "拾")
        XCTAssertEqual(LibuText.chineseCount(12), "拾貳")
        XCTAssertEqual(LibuText.chineseCount(20), "貳拾")
        XCTAssertEqual(LibuText.chineseCount(99), "玖拾玖")
        XCTAssertEqual(LibuText.chineseCount(100), "壹佰")
        XCTAssertEqual(LibuText.chineseCount(101), "壹佰零壹")
        XCTAssertEqual(LibuText.chineseCount(110), "壹佰壹拾")
        XCTAssertEqual(LibuText.chineseCount(112), "壹佰壹拾貳")
        XCTAssertEqual(LibuText.chineseCount(1000), "壹仟")
        XCTAssertEqual(LibuText.chineseCount(10000), "壹萬")
        XCTAssertEqual(LibuText.chineseCount(100000), "拾萬")
    }
}

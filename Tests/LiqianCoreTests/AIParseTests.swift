import XCTest
@testable import LiqianCore

// MARK: - AI 多笔解析共用管线（v2.7：一句话记账与智能粘贴共用 AIParse.decode）

final class AIParseTests: XCTestCase {
    /// 一句话里多个人 → 多条记录：金额元→分换算、方向映射、顺序保留
    func testMultiPersonSentenceDecodesAllRecords() throws {
        let json = """
        {"records":[
          {"name":"大舅","amountYuan":2000,"relation":"亲戚","method":"现金","direction":"received"},
          {"name":"二姨","amountYuan":1000,"relation":null,"method":null,"direction":"received"},
          {"name":"张三","amountYuan":500,"relation":"朋友","method":"微信","direction":"given"}
        ]}
        """
        let outcome = try AIParse.decode(Data(json.utf8))
        XCTAssertEqual(outcome.records.count, 3)
        XCTAssertEqual(outcome.validRecords.count, 3)
        XCTAssertEqual(outcome.invalidCount, 0)
        XCTAssertEqual(outcome.records[0].name, "大舅")
        XCTAssertEqual(outcome.records[0].amountCents, 200_000)
        XCTAssertEqual(outcome.records[0].relation, "亲戚")
        XCTAssertEqual(outcome.records[0].direction, LiqianConstants.received)
        XCTAssertEqual(outcome.records[1].name, "二姨")
        XCTAssertEqual(outcome.records[1].amountCents, 100_000)
        XCTAssertNil(outcome.records[1].relation)
        XCTAssertEqual(outcome.records[2].name, "张三")
        XCTAssertEqual(outcome.records[2].amountCents, 50_000)
        XCTAssertEqual(outcome.records[2].method, "微信")
        XCTAssertEqual(outcome.records[2].direction, LiqianConstants.given)
        XCTAssertTrue(outcome.uncertain.isEmpty)
    }

    /// 字段映射细则：带小数金额换算、白名单外的关系被过滤、
    /// 无效条目（姓名空/金额 0）保留并标 isValid=false、uncertain 透传
    func testFieldMappingWhitelistAndInvalidRecords() throws {
        let json = """
        {"records":[
          {"name":"王五","amountYuan":88.5,"relation":"表哥","method":"微信","direction":"received","eventHint":"满月"},
          {"name":"","amountYuan":0,"relation":null,"method":null,"direction":"received"},
          {"name":"赵六","amountYuan":0,"relation":null,"method":null,"direction":null}
        ],"uncertain":[2]}
        """
        let outcome = try AIParse.decode(Data(json.utf8))
        XCTAssertEqual(outcome.records.count, 3)
        // 88.5 元 → 8850 分；「表哥」不在关系词表 → nil；事由透传
        XCTAssertEqual(outcome.records[0].amountCents, 8_850)
        XCTAssertNil(outcome.records[0].relation)
        XCTAssertEqual(outcome.records[0].method, "微信")
        XCTAssertEqual(outcome.records[0].eventHint, "满月")
        XCTAssertTrue(outcome.records[0].isValid)
        // 无效条目不丢、只标记，调用方据此计数/标行
        XCTAssertFalse(outcome.records[1].isValid)
        XCTAssertFalse(outcome.records[2].isValid)
        XCTAssertEqual(outcome.invalidCount, 2)
        XCTAssertEqual(outcome.validRecords.map(\.name), ["王五"])
        XCTAssertEqual(outcome.uncertain, [2])
    }

    /// 整体结构不对（非 JSON / 缺 records）必须抛错，不静默返回空
    func testUnreadableThrows() {
        XCTAssertThrowsError(try AIParse.decode(Data("not json".utf8)))
        XCTAssertThrowsError(try AIParse.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try AIParse.decode(Data("{\"records\":{}}".utf8)))
    }
}

import XCTest
@testable import LiqianCore

// MARK: - 备份·礼谱属性四字段（v2.10：主家/书记/核实人/地点）

final class BackupFieldsTests: XCTestCase {
    /// 带新字段往返：编码再解码，四字段不丢
    func testRoundTripWithLibuFields() throws {
        let file = BackupFile(
            ledgers: [BackupLedger(
                id: "abc", title: "我的婚礼", type: "婚礼", date: "2026-11-16", note: "",
                hostName: "杨敏杰", scribe: "杨发强", verifier: "张艳侠", location: "西故现村"
            )],
            records: []
        )
        let data = try JSONEncoder().encode(file)
        let parsed = try LiqianBackup.parseBackup(data)
        let ledger = try XCTUnwrap(parsed.ledgers.first)
        XCTAssertEqual(ledger.hostName, "杨敏杰")
        XCTAssertEqual(ledger.scribe, "杨发强")
        XCTAssertEqual(ledger.verifier, "张艳侠")
        XCTAssertEqual(ledger.location, "西故现村")
    }

    /// 模型 → 备份映射带上四字段（导出备份不丢礼谱属性）
    func testMakeBackupCarriesLibuFields() throws {
        let ledger = Ledger(
            title: "我的婚礼", type: "婚礼", date: "2026-11-16",
            hostName: "杨敏杰", scribe: "杨发强", verifier: nil, location: "西故现村"
        )
        let data = LiqianBackup.makeBackup(ledgers: [ledger], records: [])
        let parsed = try LiqianBackup.parseBackup(data)
        let bl = try XCTUnwrap(parsed.ledgers.first)
        XCTAssertEqual(bl.hostName, "杨敏杰")
        XCTAssertEqual(bl.scribe, "杨发强")
        XCTAssertNil(bl.verifier)
        XCTAssertEqual(bl.location, "西故现村")
    }

    /// 旧格式（无四键）解码：四字段为 nil，其余字段照常
    func testOldFormatWithoutLibuKeysDecodesNil() throws {
        let json = """
        {"ledgers":[{"id":"1730000000000000","title":"我的婚礼","type":"婚礼","date":"2026-11-16","note":""}],
         "records":[]}
        """
        let parsed = try LiqianBackup.parseBackup(Data(json.utf8))
        let ledger = try XCTUnwrap(parsed.ledgers.first)
        XCTAssertNil(ledger.hostName)
        XCTAssertNil(ledger.scribe)
        XCTAssertNil(ledger.verifier)
        XCTAssertNil(ledger.location)
        XCTAssertEqual(ledger.title, "我的婚礼")
    }
}

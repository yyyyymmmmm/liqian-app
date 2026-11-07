import Foundation
import XCTest
@testable import LiqianCore

/// 活礼谱（v4.2）备份元数据段：二进制不进 JSON、元数据可选段往返、
/// 旧备份兼容、深链格式。
final class LiveBackupTests: XCTestCase {

    private func fixtureLedger() -> Ledger {
        Ledger(title: "我的婚礼", type: "婚礼", date: "2026-11-16")
    }

    private func fixtureRecord(ledgerID: UUID) -> GiftRecord {
        GiftRecord(
            ledgerID: ledgerID, person: "大舅", amountCents: 200_000,
            direction: LiqianConstants.received, date: "2026-11-16"
        )
    }

    func testLiveMetadataRoundTrip() throws {
        let ledger = fixtureLedger()
        let record = fixtureRecord(ledgerID: ledger.id)
        let signature = GuestSignature(
            ledgerID: ledger.id, recordID: record.id, person: "大舅",
            imageData: Data([0x89, 0x50, 0x4E, 0x47]),
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let blessing = VoiceBlessing(
            recordID: record.id, fileName: "blessing-x.m4a", duration: 12.5,
            transcript: "祝你们百年好合",
            createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        )

        let data = LiqianBackup.makeBackup(
            ledgers: [ledger], records: [record],
            signatures: [signature], blessings: [blessing]
        )
        let live = LiqianBackup.parseBackupLive(data)

        XCTAssertEqual(live.signatures.count, 1)
        XCTAssertEqual(live.signatures.first?.person, "大舅")
        XCTAssertEqual(live.signatures.first?.ledgerId, ledger.id.uuidString)
        XCTAssertEqual(live.signatures.first?.recordId, record.id.uuidString)
        XCTAssertEqual(live.signatures.first?.idUUID, signature.id)

        XCTAssertEqual(live.blessings.count, 1)
        XCTAssertEqual(live.blessings.first?.recordUUID, record.id)
        XCTAssertEqual(live.blessings.first?.duration, 12.5)
        XCTAssertEqual(live.blessings.first?.transcript, "祝你们百年好合")
        XCTAssertEqual(live.blessings.first?.fileName, "blessing-x.m4a")
    }

    /// 二进制红线：签名图与音频本体不进 JSON——备份文本里既没有
    /// imageData 键，也不该出现签名 PNG 的 Base64 内容。
    func testBackupContainsNoBinaryPayload() throws {
        let ledger = fixtureLedger()
        let record = fixtureRecord(ledgerID: ledger.id)
        // 足够长且特征明显的假 PNG 数据（真数据 Base64 后一定可检索）
        let png = Data((0..<256).map { UInt8($0 & 0xFF) })
        let signature = GuestSignature(
            ledgerID: ledger.id, recordID: record.id, person: "大舅", imageData: png
        )
        let data = LiqianBackup.makeBackup(
            ledgers: [ledger], records: [record], signatures: [signature]
        )
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("imageData"))
        XCTAssertFalse(json.contains(png.base64EncodedString()))
    }

    /// 没用过活礼谱时不写段：与旧格式同构（无 signatures/voiceBlessings 键）
    func testEmptyLiveSegmentsOmitted() throws {
        let ledger = fixtureLedger()
        let data = LiqianBackup.makeBackup(ledgers: [ledger], records: [])
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("signatures"))
        XCTAssertFalse(json.contains("voiceBlessings"))

        let live = LiqianBackup.parseBackupLive(data)
        XCTAssertTrue(live.signatures.isEmpty)
        XCTAssertTrue(live.blessings.isEmpty)
    }

    /// 旧备份（只有 ledgers/records/reminders）解析活礼谱段为空，不报错
    func testOldBackupWithoutLiveKeys() throws {
        let old = """
        {"ledgers": [], "records": [], "reminders": []}
        """
        let live = LiqianBackup.parseBackupLive(Data(old.utf8))
        XCTAssertTrue(live.signatures.isEmpty)
        XCTAssertTrue(live.blessings.isEmpty)
    }

    func testBlessingDeepLinkRoundTrip() throws {
        let id = UUID()
        let urlString = LiqianDeepLink.blessingURL(id: id)
        XCTAssertEqual(urlString, "liqian://blessing/\(id.uuidString)")
        let url = try XCTUnwrap(URL(string: urlString))
        XCTAssertEqual(LiqianDeepLink.blessingID(from: url), id)
        // 非祝福深链不误认
        let other = try XCTUnwrap(URL(string: "liqian://quick-record"))
        XCTAssertNil(LiqianDeepLink.blessingID(from: other))
    }
}

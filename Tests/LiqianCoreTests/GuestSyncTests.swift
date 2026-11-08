import XCTest
@testable import LiqianCore

/// 扫码随礼同步纯逻辑（v5.12）：去重、游标、since 编码、时间解析、
/// 入账映射与契约 DTO 解码——全部按 liqian-guest/API.md 契约样本钉死。
final class GuestSyncTests: XCTestCase {
    private func sub(_ id: Int, at createdAt: String, amount: Int? = nil) -> GuestSubmissionDTO {
        GuestSubmissionDTO(id: id, name: "宾客\(id)", amountCents: amount, blessing: "祝福\(id)", createdAt: createdAt)
    }

    // MARK: - 去重

    func testPlannerDropsAlreadyStoredIDs() {
        let batch = [
            sub(1, at: "2026-11-09T07:48:50.070+08:00"),
            sub(2, at: "2026-11-09T07:49:12.311+08:00"),
            sub(3, at: "2026-11-09T07:50:01.000+08:00"),
        ]
        let plan = GuestSyncPlanner.plan(existingServerIDs: [1, 3], incoming: batch, currentCursor: nil)
        XCTAssertEqual(plan.newSubmissions.map(\.id), [2])
    }

    func testPlannerDedupsWithinBatch() {
        let dup = sub(5, at: "2026-11-09T08:00:00.000+08:00")
        let plan = GuestSyncPlanner.plan(existingServerIDs: [], incoming: [dup, dup], currentCursor: nil)
        XCTAssertEqual(plan.newSubmissions.count, 1)
    }

    func testPlannerKeepsAllFreshInOrder() {
        let batch = [
            sub(1, at: "2026-11-09T07:48:50.070+08:00"),
            sub(2, at: "2026-11-09T07:49:12.311+08:00"),
        ]
        let plan = GuestSyncPlanner.plan(existingServerIDs: [], incoming: batch, currentCursor: nil)
        XCTAssertEqual(plan.newSubmissions.map(\.id), [1, 2])
    }

    // MARK: - 游标

    func testCursorAdvancesToLastItemCreatedAt() {
        let batch = [
            sub(1, at: "2026-11-09T07:48:50.070+08:00"),
            sub(2, at: "2026-11-09T07:49:12.311+08:00"),
        ]
        let plan = GuestSyncPlanner.plan(
            existingServerIDs: [], incoming: batch,
            currentCursor: "2026-11-09T07:00:00.000+08:00"
        )
        XCTAssertEqual(plan.newCursor, "2026-11-09T07:49:12.311+08:00")
    }

    func testCursorAdvancesEvenWhenBatchAllDuplicates() {
        // 崩溃后重拉：整批已落库，游标仍须推进，否则每次启动全量重拉
        let batch = [sub(1, at: "2026-11-09T07:48:50.070+08:00")]
        let plan = GuestSyncPlanner.plan(existingServerIDs: [1], incoming: batch, currentCursor: nil)
        XCTAssertTrue(plan.newSubmissions.isEmpty)
        XCTAssertEqual(plan.newCursor, "2026-11-09T07:48:50.070+08:00")
    }

    func testCursorUnchangedOnEmptyBatch() {
        let plan = GuestSyncPlanner.plan(
            existingServerIDs: [1], incoming: [],
            currentCursor: "2026-11-09T07:00:00.000+08:00"
        )
        XCTAssertEqual(plan.newCursor, "2026-11-09T07:00:00.000+08:00")
        XCTAssertTrue(plan.newSubmissions.isEmpty)
    }

    // MARK: - since 编码（契约明示 + 必须 %2B）

    func testEncodeSinceEscapesPlusAndColon() {
        let encoded = GuestSyncPlanner.encodeSince("2026-11-09T07:48:50.070+08:00")
        XCTAssertEqual(encoded, "2026-11-09T07%3A48%3A50.070%2B08%3A00")
        XCTAssertFalse(encoded.contains("+"))
    }

    // MARK: - 时间解析

    func testParsesFractionalBeijingTime() {
        let date = GuestTime.parse("2026-11-09T07:48:50.070+08:00")
        XCTAssertNotNil(date)
        // 北京时间 07:48:50.070 ＝ UTC 前一日 23:48:50.070
        let expected = ISO8601DateFormatter().date(from: "2026-11-08T23:48:50Z")
        XCTAssertNotNil(expected)
        XCTAssertEqual(date!.timeIntervalSince1970, expected!.timeIntervalSince1970 + 0.07, accuracy: 0.001)
    }

    func testParsesPlainISOTime() {
        XCTAssertNotNil(GuestTime.parse("2026-11-09T07:48:50+08:00"))
        XCTAssertNil(GuestTime.parse("不是时间"))
    }

    // MARK: - 映射口径

    func testEventTypeMapping() {
        XCTAssertEqual(GuestReceiptMapping.apiEventType(isBai: true), "white")
        XCTAssertEqual(GuestReceiptMapping.apiEventType(isBai: false), "red")
    }

    func testRecordNoteCarriesSourceAndBlessing() {
        XCTAssertEqual(GuestReceiptMapping.recordNote(blessing: "新婚快乐"), "宾客扫码随礼：新婚快乐")
        XCTAssertEqual(GuestReceiptMapping.recordNote(blessing: "  "), "宾客扫码随礼")
        XCTAssertEqual(GuestReceiptMapping.recordNote(blessing: ""), "宾客扫码随礼")
    }

    // MARK: - 契约 DTO 解码（样本逐字取自 API.md）

    func testDecodesSubmissionsResponseFromContract() throws {
        let json = """
        {"ok":true,"eventId":"ev_oBXuTLfE8xLM","closed":false,"submissions":[
          {"id":1,"name":"张三","amountCents":50000,"blessing":"新婚快乐，白头偕老","source":"guest","createdAt":"2026-11-09T07:48:50.070+08:00"},
          {"id":2,"name":"李四","amountCents":null,"blessing":"百年好合","source":"guest","createdAt":"2026-11-09T07:49:12.311+08:00"}
        ]}
        """
        let decoded = try JSONDecoder().decode(GuestSubmissionsResponseDTO.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.ok)
        XCTAssertFalse(decoded.closed)
        XCTAssertEqual(decoded.submissions.count, 2)
        XCTAssertEqual(decoded.submissions[0].amountCents, 50000)
        XCTAssertNil(decoded.submissions[1].amountCents)
    }

    func testDecodesCreateEventResponseFromContract() throws {
        // 字段形状逐字按 API.md 契约，令牌为合成假值（示例原文不进公开仓库）
        let json = """
        {"ok":true,"eventId":"ev_SAMPLE000000","publicToken":"SAMPLEpublicToken00000000000000ab","hostSecret":"SAMPLEhostSecret-000000000000000000000000xy","guestUrl":"https://sui.inkroot.cn/g/SAMPLEpublicToken00000000000000ab"}
        """
        let decoded = try JSONDecoder().decode(GuestEventCreatedDTO.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.eventId, "ev_SAMPLE000000")
        XCTAssertTrue(decoded.guestUrl.hasSuffix(decoded.publicToken))
    }

    // MARK: - 回执模型状态

    func testReceiptDefaultsPendingAndBookingGate() {
        let withMoney = GuestReceipt(
            ledgerID: UUID(), eventID: "ev_x", serverID: 1,
            name: "张三", amountCents: 50000, blessing: "新婚快乐",
            createdAtRaw: "2026-11-09T07:48:50.070+08:00"
        )
        XCTAssertEqual(withMoney.status, .pending)
        XCTAssertTrue(withMoney.canBook)
        let noMoney = GuestReceipt(
            ledgerID: UUID(), eventID: "ev_x", serverID: 2,
            name: "李四", amountCents: nil, blessing: "百年好合",
            createdAtRaw: "2026-11-09T07:49:12.311+08:00"
        )
        XCTAssertFalse(noMoney.canBook)
        noMoney.status = .accepted
        XCTAssertEqual(noMoney.statusRaw, "accepted")
        XCTAssertFalse(noMoney.canBook)
        XCTAssertNotNil(withMoney.createdAtDate)
    }
}

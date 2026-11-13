import XCTest
@testable import LiqianCore

// MARK: - v5.14.1 保存链热修：纯逻辑单测
// ① SaveFlow 成败分发——失败绝不触发成功反馈（审计 A5 的契约）；
// ② LedgerCountdown 天数/文案边界——今天/昨天/明天/跨月/白事抑制。

final class SaveChainTests: XCTestCase {

    private struct StubError: Error {}

    // MARK: SaveFlow

    /// 保存成功：只走 onSuccess，返回 true
    func testSaveFlowSuccessRunsSuccessOnly() {
        var success = 0
        var failure = 0
        let ok = SaveFlow.run(
            save: {},
            onSuccess: { success += 1 },
            onFailure: { _ in failure += 1 }
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(success, 1)
        XCTAssertEqual(failure, 0)
    }

    /// 保存抛错：只走 onFailure 且把原错误交出去，返回 false——
    /// 成功反馈（落印/关页/报数）在这一档绝不许触发
    func testSaveFlowFailureRunsFailureOnlyWithError() {
        var success = 0
        var received: Error?
        let ok = SaveFlow.run(
            save: { throw StubError() },
            onSuccess: { success += 1 },
            onFailure: { received = $0 }
        )
        XCTAssertFalse(ok)
        XCTAssertEqual(success, 0, "保存失败时成功反馈不得触发")
        XCTAssertTrue(received is StubError, "原错误必须原样交给失败侧（记日志用）")
    }

    /// 失败文案定版：人话、无技术词、各入口共用这一句
    func testSaveFailureMessageWording() {
        XCTAssertEqual(SaveFlow.failureMessage, "没存上，再试一次；内容都还在，没有丢。")
    }

    // MARK: LedgerCountdown（today 钉在 2026-11-13）

    private let today = "2026-11-13"

    func testCountdownTomorrow() {
        XCTAssertEqual(
            LedgerCountdown.daysUntil(eventDate: "2026-11-14", today: today, isBai: false), 1)
        XCTAssertEqual(
            LedgerCountdown.text(eventDate: "2026-11-14", today: today, isBai: false),
            "还有 1 天")
    }

    func testCountdownToday() {
        XCTAssertEqual(
            LedgerCountdown.daysUntil(eventDate: "2026-11-13", today: today, isBai: false), 0)
        XCTAssertEqual(
            LedgerCountdown.text(eventDate: "2026-11-13", today: today, isBai: false),
            "就是今天")
    }

    func testCountdownYesterday() {
        XCTAssertEqual(
            LedgerCountdown.daysUntil(eventDate: "2026-11-12", today: today, isBai: false), -1)
        XCTAssertEqual(
            LedgerCountdown.text(eventDate: "2026-11-12", today: today, isBai: false),
            "已过 1 天")
    }

    /// 跨月：11-30 → 12-03 是 3 天（按日历日差，不按 30 天月估）
    func testCountdownCrossMonth() {
        XCTAssertEqual(
            LedgerCountdown.daysUntil(eventDate: "2026-12-03", today: "2026-11-30", isBai: false),
            3)
        XCTAssertEqual(
            LedgerCountdown.text(eventDate: "2026-12-03", today: "2026-11-30", isBai: false),
            "还有 3 天")
    }

    /// 跨年已过：2026-12-31 → 2027-01-02 已过 2 天
    func testCountdownPastCrossYear() {
        XCTAssertEqual(
            LedgerCountdown.text(eventDate: "2026-12-31", today: "2027-01-02", isBai: false),
            "已过 2 天")
    }

    /// 白事抑制：未来/当天/已过全不显（天数与文案同为 nil）
    func testCountdownBaiSuppressed() {
        for event in ["2026-11-14", "2026-11-13", "2026-11-12"] {
            XCTAssertNil(
                LedgerCountdown.daysUntil(eventDate: event, today: today, isBai: true),
                "白事 \(event) 不应给出天数")
            XCTAssertNil(
                LedgerCountdown.text(eventDate: event, today: today, isBai: true),
                "白事 \(event) 不应给出倒计时文案")
        }
    }
}


// MARK: - v5.14.1 源码守卫（口径同 NativePassGuardTests 的 repoSource）

final class SaveChainGuardTests: XCTestCase {

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

    /// 六个落库入口：全部走 SaveSupport，且不许再有静默 save 回潮；
    /// App 层 SaveSupport 必须真 save（禁止 try? 吞错）
    func testSixEntryPointsUseSaveSupportNoSilentSave() throws {
        let entries = [
            "Sources/LiqianApp/LedgerFormView.swift",
            "Sources/LiqianApp/RecordFormView.swift",
            "Sources/LiqianApp/BatchEntryView.swift",
            "Sources/LiqianApp/SceneModeView.swift",
            "Sources/LiqianApp/PhotoOCRView.swift",
            "Sources/LiqianApp/AdvisorView.swift",
        ]
        for path in entries {
            let src = try repoSource(path)
            XCTAssertTrue(src.contains("SaveSupport.attempt"), "\(path) 必须走 SaveSupport.attempt")
            XCTAssertFalse(
                src.contains("try? modelContext.save()"),
                "\(path) 不得再有静默 save（审计 A5）")
        }
        let support = try repoSource("Sources/LiqianApp/SaveSupport.swift")
        XCTAssertTrue(support.contains("try context.save()"), "SaveSupport 必须真 save")
        XCTAssertFalse(support.contains("try?"), "SaveSupport 内不得吞错")
    }

    /// lastUsed 回写覆盖：批量/现场/OCR/问账四入口成功后回写实际入账
    /// 礼簿；记一笔的 @AppStorage 写与 SaveSupport 写的是同一个键
    func testLastUsedWriteBackCoverage() throws {
        for path in [
            "Sources/LiqianApp/BatchEntryView.swift",
            "Sources/LiqianApp/SceneModeView.swift",
            "Sources/LiqianApp/PhotoOCRView.swift",
            "Sources/LiqianApp/AdvisorView.swift",
        ] {
            let src = try repoSource(path)
            XCTAssertTrue(
                src.contains("SaveSupport.rememberLedger(ledger.id)"),
                "\(path) 入账成功后必须回写上次使用礼簿")
        }
        let record = try repoSource("Sources/LiqianApp/RecordFormView.swift")
        XCTAssertTrue(
            record.contains("DefaultLedgerPicker.lastUsedKey"),
            "记一笔 @AppStorage 必须用 DefaultLedgerPicker.lastUsedKey 同键")
        let core = try repoSource("Sources/LiqianCore/DefaultLedger.swift")
        XCTAssertTrue(
            core.contains("lastUsedKey = \"lastUsedLedgerID\""),
            "lastUsed 键字面量不得漂移（两处写入同一 UserDefaults 键）")
    }

    /// 日期包：记一笔固定簿默认事由日＋日期行在主表单；批量/OCR 有
    /// 整批日期并真正写进记录；回执入账传提交日
    func testDatePackageWiring() throws {
        let record = try repoSource("Sources/LiqianApp/RecordFormView.swift")
        XCTAssertTrue(
            record.contains("LiqianDate.date(from: ledger.date)"),
            "记一笔（固定簿）默认日期必须是礼簿事由日")
        XCTAssertTrue(record.contains("private var dateRow"), "日期行必须在主表单明面")
        XCTAssertTrue(record.contains("receiptDate: Date"), "回执 init 必须接提交日参数")

        let batch = try repoSource("Sources/LiqianApp/BatchEntryView.swift")
        XCTAssertTrue(batch.contains("DatePicker(\"记录日期\""), "批量必须有整批日期选择")
        XCTAssertEqual(
            batch.components(separatedBy: "LiqianDate.string(from: batchDate)").count - 1, 3,
            "批量三通道（逐行/粘贴/AI）落库日期必须都用整批日期")

        let ocr = try repoSource("Sources/LiqianApp/PhotoOCRView.swift")
        XCTAssertTrue(ocr.contains("DatePicker(\"记录日期\""), "OCR 必须有整批日期选择")
        XCTAssertTrue(
            ocr.contains("LiqianDate.string(from: batchDate)"), "OCR 落库日期必须用整批日期")

        let receipts = try repoSource("Sources/LiqianApp/GuestReceiptsView.swift")
        XCTAssertTrue(
            receipts.contains("receipt.createdAtDate"),
            "回执入账必须把服务器提交日传给记一笔预填")
    }

    /// 倒计时呈现两处在位：礼簿卡副标题＋详情头部（白事抑制在 Core
    /// 函数内，由逻辑单测钉死）
    func testCountdownPresentationWiring() throws {
        let card = try repoSource("Sources/LiqianDesign/Components.swift")
        XCTAssertTrue(
            card.contains("LedgerCountdown.text"), "礼簿卡副标题必须接倒计时文案")
        let detail = try repoSource("Sources/LiqianApp/LedgerDetailView.swift")
        XCTAssertTrue(
            detail.contains("LedgerCountdown.text"), "礼簿详情头部必须接倒计时文案")
    }
}

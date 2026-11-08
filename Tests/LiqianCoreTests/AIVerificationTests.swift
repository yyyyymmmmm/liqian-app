import XCTest
@testable import LiqianCore

/// v5.2.1：验证状态机——落盘还原、换 Key 自动回未验证、失败原因留存、
/// 清除后回未验证。用独立 suite 的 UserDefaults，不污染标准域。
final class AIVerificationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.aiverification.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testNoKeyMeansNoKeyStatus() {
        XCTAssertEqual(
            AIVerificationStore.status(currentKeyLast4: nil, defaults: defaults),
            .noKey
        )
    }

    func testKeyWithoutRecordIsUnverified() {
        XCTAssertEqual(
            AIVerificationStore.status(currentKeyLast4: "51af", defaults: defaults),
            .unverified
        )
    }

    func testVerifiedRecordRestoresAfterRelaunch() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        AIVerificationStore.save(
            AIVerificationRecord(outcome: .verified, keyLast4: "51af", at: at),
            defaults: defaults
        )
        XCTAssertEqual(
            AIVerificationStore.status(currentKeyLast4: "51af", defaults: defaults),
            .verified(at: at)
        )
    }

    func testFailedRecordKeepsHumanReason() {
        let at = Date(timeIntervalSince1970: 1_700_000_100)
        AIVerificationStore.save(
            AIVerificationRecord(
                outcome: .failed, keyLast4: "51af", at: at,
                failureReason: "DeepSeek 账户余额不足"
            ),
            defaults: defaults
        )
        XCTAssertEqual(
            AIVerificationStore.status(currentKeyLast4: "51af", defaults: defaults),
            .failed(reason: "DeepSeek 账户余额不足", at: at)
        )
    }

    func testKeyChangeInvalidatesOldRecord() {
        AIVerificationStore.save(
            AIVerificationRecord(
                outcome: .verified, keyLast4: "51af", at: Date()
            ),
            defaults: defaults
        )
        // 换了 Key（尾号不同）→ 旧结论作废，自动回未验证
        XCTAssertEqual(
            AIVerificationStore.status(currentKeyLast4: "99zz", defaults: defaults),
            .unverified
        )
    }

    func testClearReturnsToUnverified() {
        AIVerificationStore.save(
            AIVerificationRecord(
                outcome: .verified, keyLast4: "51af", at: Date()
            ),
            defaults: defaults
        )
        AIVerificationStore.clear(defaults: defaults)
        XCTAssertEqual(
            AIVerificationStore.status(currentKeyLast4: "51af", defaults: defaults),
            .unverified
        )
    }
}

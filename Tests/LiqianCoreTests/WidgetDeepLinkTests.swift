import XCTest
@testable import LiqianCore

/// v5.1 小组件深链：待回页整卡落点 liqian://pending（与人物/祝福深链同族，
/// App 侧 onOpenURL 承接切往来 Tab，隐私锁守卫在 App 侧）。
final class WidgetDeepLinkTests: XCTestCase {
    func testPendingURLRoundTrip() {
        let url = URL(string: LiqianDeepLink.pendingURL())
        XCTAssertEqual(LiqianDeepLink.pendingURL(), "liqian://pending")
        XCTAssertNotNil(url)
        XCTAssertTrue(LiqianDeepLink.isPending(url!))
    }

    func testIsPendingRejectsOtherDeepLinks() {
        XCTAssertFalse(LiqianDeepLink.isPending(URL(string: "liqian://quick-record")!))
        XCTAssertFalse(LiqianDeepLink.isPending(URL(string: LiqianDeepLink.personURL(name: "王小明"))!))
        XCTAssertFalse(LiqianDeepLink.isPending(URL(string: "https://example.com/pending")!))
    }

    func testPendingURLIsNotParsedAsPersonOrBlessing() {
        let url = URL(string: LiqianDeepLink.pendingURL())!
        XCTAssertNil(LiqianDeepLink.personName(from: url))
        XCTAssertNil(LiqianDeepLink.blessingID(from: url))
    }
}

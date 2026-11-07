import XCTest
@testable import LiqianCore

// MARK: - Pro 权益判定（v5）：机主旗优先、产品 id 精确匹配、四门控面同口径
final class EntitlementsTests: XCTestCase {
    func testOwnerBuildAlwaysPro() {
        XCTAssertTrue(ProEntitlement.isPro(verifiedProductIDs: [], ownerBuild: true))
        XCTAssertTrue(ProEntitlement.isPro(verifiedProductIDs: ["other.product"], ownerBuild: true))
    }

    func testVerifiedProProductGrants() {
        XCTAssertTrue(
            ProEntitlement.isPro(
                verifiedProductIDs: [LiqianConstants.proProductID],
                ownerBuild: false
            )
        )
    }

    func testNoPurchaseNoPro() {
        XCTAssertFalse(ProEntitlement.isPro(verifiedProductIDs: [], ownerBuild: false))
        XCTAssertFalse(
            ProEntitlement.isPro(
                verifiedProductIDs: ["site.didichou.liqian.pro2", "com.example.other"],
                ownerBuild: false
            )
        )
    }

    func testAllFeaturesShareSameGate() {
        for feature in ProFeature.allCases {
            XCTAssertFalse(
                ProEntitlement.canUse(feature, verifiedProductIDs: [], ownerBuild: false),
                "\(feature) 未购不应可用"
            )
            XCTAssertTrue(
                ProEntitlement.canUse(
                    feature,
                    verifiedProductIDs: [LiqianConstants.proProductID],
                    ownerBuild: false
                ),
                "\(feature) 已购应可用"
            )
            XCTAssertTrue(
                ProEntitlement.canUse(feature, verifiedProductIDs: [], ownerBuild: true),
                "\(feature) 机主构建应可用"
            )
        }
        XCTAssertEqual(ProFeature.allCases.count, 4, "门控面定版只有四处，增减先改任务书")
    }
}

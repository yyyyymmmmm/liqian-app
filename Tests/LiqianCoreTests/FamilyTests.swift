import XCTest
@testable import LiqianCore

/// 家族协作与传承（v4.5）：班子同步口径与班子备份段
final class FamilyTests: XCTestCase {
    private let ledgerID = UUID()

    private func member(
        _ name: String, _ role: MemberRole, secondsAgo: TimeInterval = 0
    ) -> LedgerMemberValue {
        LedgerMemberValue(
            ledgerID: ledgerID, name: name, role: role,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 - secondsAgo)
        )
    }

    // MARK: - 班子 → 字段

    func testFieldsDeriveScribeAndVerifierFromMembers() {
        let members = [
            member("杨敏杰", .host),
            member("王芳", .scribe),
            member("杨父", .verifier),
            member("小妹", .viewer),
        ]
        let out = MemberSync.fields(
            from: members,
            current: .init(hostName: "旧主家", scribe: "旧书记", verifier: "旧核实")
        )
        XCTAssertEqual(out.hostName, "杨敏杰")
        XCTAssertEqual(out.scribe, "王芳")
        XCTAssertEqual(out.verifier, "杨父")
    }

    func testFieldsClearScribeAndVerifierWhenRoleAbsent() {
        // 书记/核实以班子为唯一真源：班子没有 → 字段清空
        let out = MemberSync.fields(
            from: [member("杨敏杰", .host)],
            current: .init(hostName: "杨敏杰", scribe: "王芳", verifier: "杨父")
        )
        XCTAssertNil(out.scribe)
        XCTAssertNil(out.verifier)
    }

    func testHostFieldKeptWhenNoHostMember() {
        // 主家字段兼落款回退/预填语义：班子无主家成员时不清空
        let out = MemberSync.fields(
            from: [member("王芳", .scribe)],
            current: .init(hostName: "杨敏杰")
        )
        XCTAssertEqual(out.hostName, "杨敏杰")
        XCTAssertEqual(out.scribe, "王芳")
    }

    func testRepresentativePicksEarliestCreated() {
        let members = [
            member("后来的书记", .scribe, secondsAgo: 10),
            member("先来的书记", .scribe, secondsAgo: 100),
        ]
        XCTAssertEqual(
            MemberSync.representative(of: .scribe, in: members)?.name, "先来的书记"
        )
        let out = MemberSync.fields(from: members, current: .init())
        XCTAssertEqual(out.scribe, "先来的书记")
    }

    // MARK: - 字段 → 班子种子

    func testSeedFromFieldsInRoleOrder() {
        let seeds = MemberSync.seed(
            from: .init(hostName: "杨敏杰", scribe: "王芳", verifier: "杨父")
        )
        XCTAssertEqual(seeds.map(\.name), ["杨敏杰", "王芳", "杨父"])
        XCTAssertEqual(seeds.map(\.role), [.host, .scribe, .verifier])
    }

    func testSeedSkipsEmptyFields() {
        XCTAssertTrue(MemberSync.seed(from: .init()).isEmpty)
        let partial = MemberSync.seed(from: .init(scribe: "  王芳  "))
        XCTAssertEqual(partial.count, 1)
        XCTAssertEqual(partial.first?.name, "王芳")
        XCTAssertEqual(partial.first?.role, .scribe)
    }

    // MARK: - 角色权限映射

    func testRolePermissions() {
        XCTAssertEqual(MemberRole.host.sharePermission, .owner)
        XCTAssertEqual(MemberRole.scribe.sharePermission, .readWrite)
        XCTAssertEqual(MemberRole.verifier.sharePermission, .readWrite)
        XCTAssertEqual(MemberRole.viewer.sharePermission, .readOnly)
        XCTAssertTrue(MemberRole.scribe.canEdit)
        XCTAssertFalse(MemberRole.viewer.canEdit)
    }

    // MARK: - 备份班子段

    func testBackupRoundTripWithMembers() throws {
        let ledger = Ledger(
            id: ledgerID, title: "我的婚礼", type: "婚礼", date: "2026-11-16"
        )
        let m1 = LedgerMember(
            ledgerID: ledgerID, name: "王芳", role: MemberRole.scribe.rawValue,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let m2 = LedgerMember(
            ledgerID: ledgerID, name: "杨父", role: MemberRole.verifier.rawValue,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let data = LiqianBackup.makeBackup(ledgers: [ledger], records: [], members: [m1, m2])
        let parsed = try LiqianBackup.parseBackupFull(data)
        XCTAssertEqual(parsed.members.count, 2)
        XCTAssertEqual(parsed.members.first?.name, "王芳")
        XCTAssertEqual(parsed.members.first?.role, "书记")
        XCTAssertEqual(parsed.members.first?.ledgerUUID, ledgerID)
        XCTAssertEqual(
            LiqianBackup.memberDate(from: parsed.members.first?.createdAt ?? ""),
            Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testOldBackupWithoutMembersParsesEmpty() throws {
        let json = """
        {"ledgers":[{"id":"1730000000000000","title":"我的婚礼","type":"婚礼","date":"2026-11-16","note":""}],
         "records":[]}
        """
        let parsed = try LiqianBackup.parseBackupFull(Data(json.utf8))
        XCTAssertTrue(parsed.members.isEmpty)
        XCTAssertEqual(parsed.ledgers.count, 1)
    }
}

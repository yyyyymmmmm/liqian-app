import XCTest
import PDFKit
import UIKit
@testable import LiqianCore

// MARK: - 礼谱排版四件（v5.12.1，用户 2026-11-09 批准打包）
//
// 背景：v3.1 定版的内页是「按关系分段、段段换页」，一节 1 笔也独占
// 一页（用户实报「没写满就换了一页」）；姓名超 4 字被 prefix(4) 静
// 默截断；汇总分页是扁平行数组机械切块、会断在小計组中间；金额大
// 写步距固定 18 无下界检查，¥188,888 一档整列约 678pt、超 647pt
// 列高会压版框下线。本组测试四层钉死：
//  ① 计划层：LibuPagination 的拼流/切页/分档/汇总分页纯函数；
//  ② 生产纯链：真实 GiftRecord 走生产同链（groupByRelation→
//     entries→paginate）断言用户实例内页恰 2 页；
//  ③ 源码守卫：GiftBookPDF 装配层确实消费 Core 纯函数、旧逐节切块
//     与 prefix(4) 不许回潮；
//  ④ 渲染层：以 Core 档位值在真实页面几何上合成一列，PDFKit 抽字
//     断言五字姓名全字在场、像素扫描断言最不利列不越版框下线。
final class LibuPaginationTests: XCTestCase {

    // MARK: ① 条目流拼流与切页

    private typealias SEntry = LibuFlowEntry<String>

    private func sections(
        _ spec: [(String, Int)]
    ) -> [LibuRelationSection<String>] {
        spec.map { relation, count in
            LibuRelationSection(
                relation: relation,
                records: (0..<count).map { "\(relation)\($0)" }
            )
        }
    }

    private func isTitle(_ entry: SEntry) -> Bool {
        if case .sectionTitle = entry { return true }
        return false
    }

    private func titleText(_ entry: SEntry) -> String? {
        if case .sectionTitle(let relation, let count) = entry {
            return "\(relation)×\(count)"
        }
        return nil
    }

    func testFlowCompositionTitlePositionsAndCounts() {
        let flow = LibuBookFlow.entries(
            sections: sections([
                ("親戚", 4), ("朋友", 2), ("同事", 2), ("同學", 1), ("鄰里", 1),
            ]),
            includeTitles: true
        )
        XCTAssertEqual(flow.count, 15, "5 节题签＋10 笔记录＝15 列")
        let titles = flow.enumerated().compactMap { i, e in
            titleText(e).map { (i, $0) }
        }
        XCTAssertEqual(titles.map(\.0), [0, 5, 8, 11, 13], "题签列紧贴各节首笔之前")
        XCTAssertEqual(
            titles.map(\.1),
            ["親戚×4", "朋友×2", "同事×2", "同學×1", "鄰里×1"],
            "题签笔数＝整节总数口径不变"
        )
    }

    func testUserExampleFlowsIntoExactlyTwoPages() {
        // 用户实例：親戚4/朋友2/同事2/同學1/鄰里1 → 流 15 列 → 内页 2 页
        // （旧版逐节换页是 5 页）
        let flow = LibuBookFlow.entries(
            sections: sections([
                ("親戚", 4), ("朋友", 2), ("同事", 2), ("同學", 1), ("鄰里", 1),
            ]),
            includeTitles: true
        )
        let pages = LibuBookFlow.paginate(entries: flow, columnsPerPage: 8)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages.map(\.count), [8, 7])
        XCTAssertEqual(titleText(pages[1][0]), "同事×2", "第二页首列是同事题签（节界落在页界）")
    }

    func testTitleAtLastColumnDefersToNextPage() {
        // 甲节 6 笔：题签＋6 笔＝7 列占满首页前 7 列，乙题签恰落第 8 列
        // （页末列）→ 孤行守护顺延，首页只排 7 列
        let flow = LibuBookFlow.entries(
            sections: sections([("甲", 6), ("乙", 2)]),
            includeTitles: true
        )
        let pages = LibuBookFlow.paginate(entries: flow, columnsPerPage: 8)
        XCTAssertEqual(pages.map(\.count), [7, 3])
        XCTAssertEqual(titleText(pages[1][0]), "乙×2")
        XCTAssertFalse(isTitle(pages[0][6]), "首页最后一列必须是记录、不是题签")
    }

    func testTitleDeferralChainsAcrossPages() {
        let flow = LibuBookFlow.entries(
            sections: sections([("甲", 6), ("乙", 6), ("丙", 1)]),
            includeTitles: true
        )
        let pages = LibuBookFlow.paginate(entries: flow, columnsPerPage: 8)
        XCTAssertEqual(pages.map(\.count), [7, 7, 2])
        XCTAssertEqual(titleText(pages[2][0]), "丙×1")
    }

    func testSingleSectionWithoutTitlesFlowsPlain() {
        let flow = LibuBookFlow.entries(
            sections: sections([("朋友", 10)]),
            includeTitles: false
        )
        XCTAssertEqual(flow.count, 10)
        XCTAssertFalse(flow.contains(where: isTitle), "单节不出题签")
        let pages = LibuBookFlow.paginate(entries: flow, columnsPerPage: 8)
        XCTAssertEqual(pages.map(\.count), [8, 2])
    }

    func testFlowExactMultipleLeavesNoEmptyPage() {
        let flow = LibuBookFlow.entries(
            sections: sections([("朋友", 16)]),
            includeTitles: false
        )
        let pages = LibuBookFlow.paginate(entries: flow, columnsPerPage: 8)
        XCTAssertEqual(pages.map(\.count), [8, 8])
    }

    func testFlowEmptyInputs() {
        XCTAssertTrue(LibuBookFlow.entries(
            sections: [LibuRelationSection<String>](), includeTitles: true
        ).isEmpty)
        XCTAssertTrue(LibuBookFlow.paginate(
            entries: [SEntry](), columnsPerPage: 8
        ).isEmpty)
    }

    // MARK: ① 姓名分档与列高

    func testNameLayoutTiers() {
        for count in 1...4 {
            let tier = LibuNameLayout.tier(characterCount: count)
            XCTAssertEqual(tier.fontSize, 20, "\(count) 字原档字号")
            XCTAssertEqual(tier.step, 27, "\(count) 字原档步距")
        }
        for count in 5...6 {
            let tier = LibuNameLayout.tier(characterCount: count)
            XCTAssertEqual(tier.fontSize, 16)
            XCTAssertEqual(tier.step, 22)
        }
        for count in [7, 9, 12] {
            let tier = LibuNameLayout.tier(characterCount: count)
            XCTAssertEqual(tier.fontSize, 13)
            XCTAssertEqual(tier.step, 18)
        }
    }

    func testNameLayoutHeightsFollowSlots() {
        XCTAssertEqual(LibuNameLayout.height(characterCount: 1), 81, "短名按 3 字位归一")
        XCTAssertEqual(LibuNameLayout.height(characterCount: 2), 81)
        XCTAssertEqual(LibuNameLayout.height(characterCount: 4), 108)
        XCTAssertEqual(LibuNameLayout.height(characterCount: 5), 110, "5 字降档后仅比 4 字原档高 2pt")
        XCTAssertEqual(LibuNameLayout.height(characterCount: 7), 126)
    }

    // MARK: ① 金额分档与最不利列高

    func testAmountLayoutTiers() {
        XCTAssertEqual(LibuAmountLayout.tier(uppercaseCount: 10).step, 18, "≤10 字原档")
        XCTAssertEqual(LibuAmountLayout.tier(uppercaseCount: 11).step, 15, "11 字起收一档")
        XCTAssertEqual(LibuAmountLayout.tier(uppercaseCount: 14).step, 15)
        XCTAssertEqual(LibuAmountLayout.tier(uppercaseCount: 15).fontSize, 12, "15 字起字号步距同收")
        XCTAssertEqual(LibuAmountLayout.tier(uppercaseCount: 15).step, 13)
    }

    func testWorstCaseColumnFitsColumnHeight() {
        // 最不利组合：四字名＋大写 13 字（¥188,888）＋小字 18 字
        // （「¥188,888 · 微信 · 隨禮」）＋首笔日期 5 字（含闰月口径）
        let worst = LibuColumnMetrics.recordHeight(
            nameCount: 4, uppercaseCount: 13, smallCount: 18, dateCount: 5
        )
        XCTAssertEqual(worst, 639)
        XCTAssertLessThanOrEqual(worst, LibuColumnMetrics.columnHeight)
        // 15 字大写（¥1,888,888）同口径也收得进
        let bigger = LibuColumnMetrics.recordHeight(
            nameCount: 4, uppercaseCount: 15, smallCount: 18, dateCount: 5
        )
        XCTAssertEqual(bigger, 639)
        XCTAssertLessThanOrEqual(bigger, LibuColumnMetrics.columnHeight)
        // 五字名叠最不利金额：降档后 641 仍在列高内
        let fiveName = LibuColumnMetrics.recordHeight(
            nameCount: 5, uppercaseCount: 13, smallCount: 18, dateCount: 5
        )
        XCTAssertEqual(fiveName, 641)
        XCTAssertLessThanOrEqual(fiveName, LibuColumnMetrics.columnHeight)
        // 旧固定步距 18 的同组合是 678、必溢出——分档修的就是这个
        let legacy = LibuNameLayout.height(characterCount: 4)
            + LibuColumnMetrics.gapAfterName + CGFloat(13) * 18
            + LibuColumnMetrics.gapAfterAmount + CGFloat(18) * 13
            + LibuColumnMetrics.gapBeforeDate + CGFloat(5) * 14
        XCTAssertGreaterThan(legacy, LibuColumnMetrics.columnHeight)
    }

    // MARK: ① 汇总 keep-together 分页

    private func srow(
        _ dy: CGFloat, group: Int, header: Bool = false, whole: Bool = false
    ) -> LibuSummaryRow {
        LibuSummaryRow(dy: dy, isHeader: header, group: group, keepGroupWhole: whole)
    }

    private func summaryPages(
        _ rows: [LibuSummaryRow],
        first: CGFloat = 100, page: CGFloat = 100,
        last: CGFloat = 10_000, lastFirst: CGFloat = 10_000
    ) -> [[Int]] {
        LibuSummaryPaginator.paginate(
            rows: rows,
            firstPageCapacity: first, pageCapacity: page,
            lastPageCapacity: last, lastPageFirstCapacity: lastFirst
        )
    }

    func testSummaryHeaderNeverOrphanedAtPageEnd() {
        let rows = [
            srow(70, group: 0, whole: true),
            srow(20, group: 0, whole: true),
            srow(10, group: 2, header: true),
            srow(30, group: 2),
        ]
        // 首页已用 90：组头 10 恰放得下、组员 30 放不下 → 组头随组员换页
        XCTAssertEqual(summaryPages(rows), [[0, 1], [2, 3]])
    }

    func testSummarySmallGroupMovesWhollyToNextPage() {
        let rows = [
            srow(50, group: 0, whole: true),
            srow(50, group: 0, whole: true),
            srow(36, group: 1, header: true, whole: true),
            srow(30, group: 1, whole: true),
            srow(30, group: 1, whole: true),
        ]
        // 按方式组高 96：首页（容量 120）只剩 20 → 整组换页（次页容量 100 放得下）
        XCTAssertEqual(summaryPages(rows, first: 120), [[0, 1], [2, 3, 4]])
    }

    func testSummaryLargeGroupMaySplitButKeepsHeaderWithBody() {
        let rows = [srow(36, group: 2, header: true)]
            + (0..<5).map { _ in srow(30, group: 2) }
        // 按日大组 186 超一页容量：许拆，首页排组头＋2 行、余下续页
        let pages = summaryPages(rows)
        XCTAssertEqual(pages, [[0, 1, 2], [3, 4, 5]])
    }

    func testSummaryOversizedWholeGroupDegradesToRowFlow() {
        let rows = [srow(36, group: 1, header: true, whole: true)]
            + (0..<5).map { _ in srow(30, group: 1, whole: true) }
        // 整组 186 比一页（100）还高：整组保持不可能，退化逐行、不得死循环
        XCTAssertEqual(summaryPages(rows), [[0, 1, 2], [3, 4, 5]])
    }

    func testSummaryLastPageRepairKeepsWholeGroupIntact() {
        let rows = [
            srow(34, group: 0, whole: true),
            srow(36, group: 3, header: true, whole: true),
            srow(28, group: 3, whole: true),
            srow(28, group: 3, whole: true),
            srow(28, group: 3, whole: true),
        ]
        // 一页排得下（总高 154 ≤ 573），但末页保护界 130：机械挪行会把
        // 按關係组从中间劈开（只挪尾行 1 行即达界）——复核须整组随行
        let pages = summaryPages(
            rows, first: 573, page: 647, last: 425, lastFirst: 130
        )
        XCTAssertEqual(pages, [[0], [1, 2, 3, 4]])
    }

    func testSummaryLastPageRepairNeverLeavesHeaderBehind() {
        let rows = [
            srow(34, group: 0, whole: true),
            srow(34, group: 0, whole: true),
            srow(36, group: 2, header: true),
            srow(28, group: 2),
            srow(28, group: 2),
        ]
        // 末页保护界 110：机械切口落在组头之后（保留页以组头收尾），
        // 复核须把组头一并挪走
        let pages = summaryPages(
            rows, first: 573, page: 647, last: 425, lastFirst: 110
        )
        XCTAssertEqual(pages, [[0, 1], [2, 3, 4]])
    }

    func testSummaryEmptyRowsYieldOneEmptyPage() {
        let pages = summaryPages([])
        XCTAssertEqual(pages.count, 1)
        XCTAssertTrue(pages[0].isEmpty)
    }

    // MARK: ② 生产纯链（真实模型 → 分组 → 拼流 → 切页）

    func testProductionChainUserExampleYieldsTwoContentPages() {
        let ledgerID = UUID()
        func record(_ person: String, _ relation: String) -> GiftRecord {
            GiftRecord(
                ledgerID: ledgerID, person: person, relation: relation,
                amountCents: 10_000, direction: LiqianConstants.received,
                method: "现金", date: "2026-11-16"
            )
        }
        var counted: [GiftRecord] = []
        for i in 0..<4 { counted.append(record("亲戚\(i)", "亲戚")) }
        for i in 0..<2 { counted.append(record("朋友\(i)", "朋友")) }
        for i in 0..<2 { counted.append(record("同事\(i)", "同事")) }
        counted.append(record("同学0", "同学"))
        counted.append(record("邻居0", "邻居"))

        // 与 GiftBookPDF.makePDF 内页装配同一条链
        let sections = LibuSections.groupByRelation(counted) { $0.relation }
        XCTAssertEqual(sections.map(\.relation), ["亲戚", "朋友", "同事", "同学", "邻居"])
        XCTAssertEqual(sections.map { $0.records.count }, [4, 2, 2, 1, 1])
        let flow = LibuBookFlow.entries(sections: sections, includeTitles: true)
        XCTAssertEqual(flow.count, 15)
        let pages = LibuBookFlow.paginate(entries: flow, columnsPerPage: 8)
        XCTAssertEqual(pages.count, 2, "示例量级数据内页恰 2 页（旧版 5 页）")
        XCTAssertEqual(pages.map(\.count), [8, 7])
    }

    // MARK: ③ 源码守卫

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

    func testGiftBookPDFConsumesFlowAndTierFunctions() throws {
        let source = try repoSource("Sources/LiqianApp/GiftBookPDF.swift")
        XCTAssertTrue(source.contains("LibuBookFlow.entries("), "内页装配必须走拼流纯函数")
        XCTAssertTrue(source.contains("LibuBookFlow.paginate("), "内页装配必须走切页纯函数")
        XCTAssertTrue(source.contains("LibuSummaryPaginator.paginate("), "汇总必须走 keep-together 分页")
        XCTAssertTrue(source.contains("LibuNameLayout.tier("), "姓名绘制必须走分档")
        XCTAssertTrue(source.contains("LibuAmountLayout.tier("), "大写绘制必须走分档")
        XCTAssertTrue(source.contains("verticalSectionTitleText"), "题签列文案函数须在位")
        XCTAssertFalse(source.contains("func drawSectionTitle"), "横排题签带不许回潮")
        XCTAssertFalse(source.contains("func sectionTitleText"), "横排题签文案不许回潮")
        XCTAssertFalse(source.contains("by: columnsPerPage"), "逐节独立切块（段段换页）不许回潮")
        XCTAssertFalse(source.contains("prefix(4)"), "姓名 4 字硬截不许回潮")
        XCTAssertTrue(source.contains("let chars = Array(name)"), "姓名必须整串入列")
    }

    // MARK: ④ 渲染层（真实页面几何合成）

    private let pageBounds = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
    private let contentTopY: CGFloat = 116
    private let contentBottomY: CGFloat = 763

    /// 与生产 drawVertical 同构的逐字竖排（字居中、逐字步进）。
    private func drawVerticalText(
        _ text: String, centerX: CGFloat, topY: CGFloat,
        font: UIFont, step: CGFloat
    ) -> CGFloat {
        var y = topY
        for ch in text {
            let attr = NSAttributedString(
                string: String(ch),
                attributes: [.font: font, .foregroundColor: UIColor.black]
            )
            let size = attr.size()
            attr.draw(at: CGPoint(x: centerX - size.width / 2, y: y))
            y += step
        }
        return y
    }

    private func renderSinglePage(_ draw: () -> Void) throws -> PDFDocument {
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        let data = renderer.pdfData { context in
            context.beginPage()
            UIColor.white.setFill()
            UIRectFill(pageBounds)
            draw()
        }
        return try XCTUnwrap(PDFDocument(data: data))
    }

    func testRenderedFiveCharNameAppearsInFull() throws {
        let name = "欧阳娜娜娜" // 5 字：旧版 prefix(4) 会静默砍掉末字
        let tier = LibuNameLayout.tier(characterCount: name.count)
        let doc = try renderSinglePage {
            // 与生产 drawNameColumn 同构：槽位 [0..<字数]、档位字号/步距
            for (i, ch) in name.enumerated() {
                let attr = NSAttributedString(
                    string: String(ch),
                    attributes: [
                        .font: UIFont.systemFont(ofSize: tier.fontSize),
                        .foregroundColor: UIColor.black,
                    ]
                )
                let size = attr.size()
                attr.draw(at: CGPoint(
                    x: 300 - size.width / 2,
                    y: contentTopY + CGFloat(i) * tier.step
                ))
            }
        }
        let text = try XCTUnwrap(doc.page(at: 0)?.string)
        XCTAssertTrue(text.contains("欧"), "五字名首字在场")
        XCTAssertTrue(text.contains("阳"), "五字名次字在场")
        XCTAssertEqual(
            text.filter { $0 == "娜" }.count, 3,
            "五字名三个「娜」必须全数绘出（旧版只出前 4 字、仅两个）"
        )
    }

    func testRenderedWorstCaseColumnStaysInsideFrame() throws {
        // 生产最不利列合成：四字名＋大写 13 字＋小字 18 字＋日期 5 字，
        // 档位与间隔全走 LibuNameLayout/LibuAmountLayout/LibuColumnMetrics
        let upper = "壹拾捌萬捌仟捌佰捌拾捌圓整"
        XCTAssertEqual(upper.count, 13, "¥188,888 大写 13 字")
        let small = "¥188,888 · 微信 · 隨禮"
        XCTAssertEqual(small.count, 18)
        let amountTier = LibuAmountLayout.tier(uppercaseCount: upper.count)
        let doc = try renderSinglePage {
            var y = contentTopY
            let nameTier = LibuNameLayout.tier(characterCount: 4)
            y = drawVerticalText(
                "欧阳娜娜", centerX: 300, topY: y,
                font: .systemFont(ofSize: nameTier.fontSize), step: nameTier.step
            )
            _ = y
            var bottom = contentTopY
                + LibuNameLayout.height(characterCount: 4)
                + LibuColumnMetrics.gapAfterName
            bottom = drawVerticalText(
                upper, centerX: 300, topY: bottom,
                font: .systemFont(ofSize: amountTier.fontSize), step: amountTier.step
            ) + LibuColumnMetrics.gapAfterAmount
            bottom = drawVerticalText(
                small, centerX: 300, topY: bottom,
                font: .systemFont(ofSize: 9), step: LibuColumnMetrics.smallStep
            ) + LibuColumnMetrics.gapBeforeDate
            bottom = drawVerticalText(
                "閏六月廿三", centerX: 300, topY: bottom,
                font: .systemFont(ofSize: 10.5), step: LibuColumnMetrics.dateStep
            )
            XCTAssertLessThanOrEqual(bottom, contentBottomY, "合成列底边须在版框内")
        }
        // 像素扫描：版框下线（763pt）以下、列带 x∈[260,340] 内不许有墨迹
        let page = try XCTUnwrap(doc.page(at: 0))
        let thumb = page.thumbnail(
            of: CGSize(width: 595, height: 842), for: .mediaBox
        )
        let width = 595, height = 842
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        let cg = try XCTUnwrap(thumb.cgImage)
        let context = try XCTUnwrap(ctx)
        // 纵向翻转 CTM 后绘制：内存第 0 行＝页面顶部（UIKit 坐标 y=0），
        // 行号即 UIKit y，可直接按版框下线 763 分界扫描
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var inkBelowFrame = 0
        for row in 764..<height {
            for col in 260...340 {
                let idx = (row * width + col) * 4
                if pixels[idx] < 200 || pixels[idx + 1] < 200 || pixels[idx + 2] < 200 {
                    inkBelowFrame += 1
                }
            }
        }
        XCTAssertEqual(inkBelowFrame, 0, "版框下线以下列带内不许有墨迹（记录列越界）")
    }
}

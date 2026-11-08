import Foundation
import PDFKit
import UIKit
import LiqianCore

/// 家族汇册（v5 成书做实，Pro）：多本礼簿合并成一部家族礼谱 PDF。
/// 结构：卷首总目（各簿名录＋年份）→ 按簿分章（章题页＋正文，正文复用
/// 屏幕版礼谱排版 GiftBookPDF，谱序用内置模板保证整册确定性，不走 AI）
/// → 卷末跨簿人物总索引（聚合口径在 LiqianCore.FamilyAlbum，已单测）。
/// 自制页（总目/章题/索引）走汇册自有版式：纸面＋版框＋楷体题字，
/// 与礼谱同族但不冒充礼谱内页形制。
enum FamilyAlbumPDF {
    private static let pageW = CGFloat(PrintBookSpec.trimWidthPoints)
    private static let pageH = CGFloat(PrintBookSpec.trimHeightPoints)
    private static var bounds: CGRect { CGRect(x: 0, y: 0, width: pageW, height: pageH) }

    struct Item {
        let ledger: Ledger
        /// 成册口径记录（调用侧已排除待送出）
        let countedRecords: [GiftRecord]
    }

    static func makeAlbum(items: [Item]) -> URL? {
        // 编章口径：按礼簿日期升序（家族编年），同日按簿名
        let ordered = items.sorted { ($0.ledger.date, $0.ledger.title) < ($1.ledger.date, $1.ledger.title) }
        guard !ordered.isEmpty else { return nil }

        // 各簿正文（屏幕版礼谱管线，模板谱序）
        var ledgerDocs: [PDFDocument] = []
        for item in ordered {
            let guests = Set(item.countedRecords.map(\.person)).count
            let preface = LibuPreface.template(
                type: item.ledger.type, date: item.ledger.date,
                hostName: (item.ledger.hostName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                guestCount: guests,
                location: (item.ledger.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            )
            // 汇册各簿走屏幕版礼谱管线：補記同样不带（v5.11.5 屏幕口径）
            guard let url = GiftBookPDF.makePDF(
                ledger: item.ledger, records: item.countedRecords, prefaceText: preface,
                includesSupplement: false
            ), let doc = PDFDocument(url: url) else { return nil }
            ledgerDocs.append(doc)
        }

        // 跨簿索引（Core 聚合）
        let index = FamilyAlbum.personIndex(ledgers: ordered.map {
            FamilyAlbum.LedgerInput(
                ledgerID: $0.ledger.id, title: $0.ledger.title, date: $0.ledger.date,
                personNames: $0.countedRecords.map(\.person)
            )
        })

        // 自制页：总目 → 章题（逐簿）→ 索引，一次渲染后按页序拆用
        let tocPages = tocPageCount(count: ordered.count)
        let indexPages = indexPageCount(count: index.count)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let customData = renderer.pdfData { context in
            drawTOCPages(context: context, items: ordered)
            for (i, item) in ordered.enumerated() {
                drawChapterPage(context: context, item: item, chapter: i + 1)
            }
            drawIndexPages(context: context, index: index)
        }
        guard let custom = PDFDocument(data: customData),
              custom.pageCount == tocPages + ordered.count + indexPages
        else { return nil }

        // 装配
        let out = PDFDocument()
        var at = 0
        func append(_ doc: PDFDocument, pages: some Sequence<Int>) {
            for i in pages {
                if let page = doc.page(at: i) {
                    out.insert(page, at: at)
                    at += 1
                }
            }
        }
        append(custom, pages: 0..<tocPages)
        for (i, doc) in ledgerDocs.enumerated() {
            append(custom, pages: [tocPages + i])
            append(doc, pages: 0..<doc.pageCount)
        }
        append(custom, pages: (tocPages + ordered.count)..<custom.pageCount)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("家族礼谱汇册.pdf")
        return out.write(to: url) ? url : nil
    }

    // MARK: - 分页口径

    private static let tocRowsPerPage = 16
    private static let indexRowsPerPage = 24

    private static func tocPageCount(count: Int) -> Int {
        max(1, Int(ceil(Double(count) / Double(tocRowsPerPage))))
    }

    private static func indexPageCount(count: Int) -> Int {
        max(1, Int(ceil(Double(count) / Double(indexRowsPerPage))))
    }

    // MARK: - 总目

    private static func drawTOCPages(context: UIGraphicsPDFRendererContext, items: [Item]) {
        let pages = tocPageCount(count: items.count)
        for pageIndex in 0..<pages {
            context.beginPage(withBounds: bounds, pageInfo: [:])
            let cg = context.cgContext
            PDFPageDrawing.fillPage(bounds, bai: false, in: cg)
            PDFPageDrawing.drawFrame(in: bounds, bai: false, cg: cg)
            if pageIndex == 0 {
                PDFPageDrawing.drawParagraph(
                    "家族禮譜", in: CGRect(x: 64, y: 110, width: pageW - 128, height: 30),
                    fontSize: 15, color: PDFPageDrawing.stone, serif: true
                )
                PDFPageDrawing.drawParagraph(
                    "總目", in: CGRect(x: 64, y: 140, width: pageW - 128, height: 52),
                    fontSize: 34, color: PDFPageDrawing.ink, bold: true, serif: true
                )
            } else {
                PDFPageDrawing.drawParagraph(
                    "總目（續）", in: CGRect(x: 64, y: 110, width: pageW - 128, height: 40),
                    fontSize: 22, color: PDFPageDrawing.ink, bold: true, serif: true
                )
            }
            var y: CGFloat = 226
            let start = pageIndex * tocRowsPerPage
            for i in start..<min(start + tocRowsPerPage, items.count) {
                let item = items[i]
                let guests = Set(item.countedRecords.map(\.person)).count
                PDFPageDrawing.drawParagraph(
                    "第\(chapterNumeral(i + 1))章　\(item.ledger.title)",
                    in: CGRect(x: 72, y: y, width: 300, height: 26),
                    fontSize: 15.5, color: PDFPageDrawing.ink, serif: true
                )
                PDFPageDrawing.drawParagraph(
                    "\(item.ledger.type) · \(LiqianDate.displayString(for: item.ledger.date)) · \(item.countedRecords.count) 筆 · \(guests) 人",
                    in: CGRect(x: pageW - 372, y: y + 2, width: 300, height: 24),
                    fontSize: 12, color: PDFPageDrawing.stone, alignment: .right
                )
                y += 34
            }
            PDFPageDrawing.drawParagraph(
                "—— 共 \(items.count) 簿 · 按年份編章 ——",
                in: CGRect(x: 64, y: pageH - 120, width: pageW - 128, height: 22),
                fontSize: 11.5, color: PDFPageDrawing.stone, alignment: .center
            )
        }
    }

    // MARK: - 章题页

    private static func drawChapterPage(context: UIGraphicsPDFRendererContext, item: Item, chapter: Int) {
        context.beginPage(withBounds: bounds, pageInfo: [:])
        let cg = context.cgContext
        let bai = item.ledger.isBai
        PDFPageDrawing.fillPage(bounds, bai: bai, in: cg)
        PDFPageDrawing.drawFrame(in: bounds, bai: bai, cg: cg)
        let ink = bai ? PDFPageDrawing.baiInk : PDFPageDrawing.ink
        // 右开本味：题字列偏右，事由日期列居左
        PDFPageDrawing.drawVerticalText(
            String(item.ledger.title.prefix(12)),
            centerX: pageW * 0.64, topY: 190,
            fontSize: 30, color: ink, cg: cg
        )
        PDFPageDrawing.drawVerticalText(
            "\(item.ledger.type) · \(LiqianDate.ganzhiFullDate(for: item.ledger.date))",
            centerX: pageW * 0.36, topY: 210,
            fontSize: 15, color: bai ? PDFPageDrawing.baiDeep : PDFPageDrawing.cinnabar, cg: cg, bold: false
        )
        if let first = item.ledger.title.first {
            PDFPageDrawing.drawSeal(
                char: String(first),
                center: CGPoint(x: pageW * 0.64, y: 190 + CGFloat(min(item.ledger.title.count, 12)) * 36 + 46),
                size: 42, bai: bai, cg: cg
            )
        }
        let guests = Set(item.countedRecords.map(\.person)).count
        PDFPageDrawing.drawParagraph(
            "第\(chapterNumeral(chapter))章 · 共 \(item.countedRecords.count) 筆 · \(guests) 人",
            in: CGRect(x: 64, y: pageH - 130, width: pageW - 128, height: 24),
            fontSize: 12.5, color: PDFPageDrawing.stone, alignment: .center
        )
    }

    // MARK: - 人物总索引

    private static func drawIndexPages(
        context: UIGraphicsPDFRendererContext, index: [FamilyAlbum.PersonIndexEntry]
    ) {
        let pages = indexPageCount(count: index.count)
        for pageIndex in 0..<pages {
            context.beginPage(withBounds: bounds, pageInfo: [:])
            let cg = context.cgContext
            PDFPageDrawing.fillPage(bounds, bai: false, in: cg)
            PDFPageDrawing.drawFrame(in: bounds, bai: false, cg: cg)
            PDFPageDrawing.drawParagraph(
                pageIndex == 0 ? "人物總索引" : "人物總索引（續）",
                in: CGRect(x: 64, y: 110, width: pageW - 128, height: 44),
                fontSize: 26, color: PDFPageDrawing.ink, bold: true, serif: true
            )
            if pageIndex == 0 {
                PDFPageDrawing.drawParagraph(
                    "姓名之後為其出現的禮簿與筆數；同名即同人（與 App 內口徑一致）。",
                    in: CGRect(x: 64, y: 158, width: pageW - 128, height: 22),
                    fontSize: 11.5, color: PDFPageDrawing.stone
                )
            }
            var y: CGFloat = pageIndex == 0 ? 200 : 170
            let start = pageIndex * indexRowsPerPage
            for i in start..<min(start + indexRowsPerPage, index.count) {
                let entry = index[i]
                let detail = entry.appearances
                    .map { "\($0.ledgerTitle)×\($0.count)" }
                    .joined(separator: " · ")
                PDFPageDrawing.drawParagraph(
                    entry.name,
                    in: CGRect(x: 72, y: y, width: 92, height: 22),
                    fontSize: 13, color: PDFPageDrawing.ink, bold: true
                )
                PDFPageDrawing.drawParagraph(
                    "\(detail)（共 \(entry.totalCount) 筆）",
                    in: CGRect(x: 168, y: y + 1, width: pageW - 240, height: 22),
                    fontSize: 12, color: PDFPageDrawing.stone
                )
                y += 27
            }
        }
    }

    // MARK: - 章号

    private static func chapterNumeral(_ n: Int) -> String {
        let digits = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
        if n >= 1 && n <= 9 { return digits[n - 1] }
        if n == 10 { return "十" }
        if n > 10 && n < 20 { return "十" + digits[n - 11] }
        return "\(n)"
    }
}

import Foundation
import PDFKit
import UIKit
import LiqianCore

/// 印刷版礼谱（v5 成书做实，Pro）：在屏幕版礼谱 PDF 之上装配印刷文件——
/// 屏幕版管线（GiftBookPDF）一字不动，这里只做印厂交付层：
/// ① 首页＝封面展开图（封面＋书脊＋封底一页，含出血；右开本排版：
///    左封面、右封底，下单须与印厂书面确认与本图一致）；
/// ② 内页逐页套 3mm 出血页盒（内容原样，出血环以同纸色延展；
///    自第 1 页起，第 0 页封面只进展开图，不重复嵌回——v5.11.5）；
/// ③ 末页＝「印刷参数说明」（右开本、RGB 转档打样认色、纸张建议等，
///    口径引 POD 调研，见 V5-NOTES）。
/// 内页以 4 倍分辨率栅格化嵌回——印刷锐度够用且实现稳妥；封面展开图的
/// 封面区同理取自屏幕版封面页。
enum GiftBookPrintPDF {
    private static let pageW = CGFloat(PrintBookSpec.trimWidthPoints)
    private static let pageH = CGFloat(PrintBookSpec.trimHeightPoints)
    private static let bleed = CGFloat(PrintBookSpec.bleedPoints)

    /// 由已生成的屏幕版礼谱装配印刷版，返回临时文件 URL（失败 nil）
    static func makePrintPDF(
        screenPDF: URL, ledger: Ledger, spineWidthMM: Double,
        libuScript: LibuScript = .traditional
    ) -> URL? {
        guard let doc = PDFDocument(url: screenPDF), doc.pageCount > 0 else { return nil }
        let bai = ledger.isBai
        let spinePt = CGFloat(PrintBookSpec.points(fromMM: spineWidthMM))
        let spreadW = pageW * 2 + spinePt + bleed * 2
        let spreadH = pageH + bleed * 2
        let bleedBounds = CGRect(x: 0, y: 0, width: pageW + bleed * 2, height: pageH + bleed * 2)

        let safeName = ledger.title.replacingOccurrences(of: "/", with: "、")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName)-礼谱-印刷版.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: .zero)
        do {
            try renderer.writePDF(to: url) { context in
                // ① 封面展开图
                context.beginPage(withBounds: CGRect(x: 0, y: 0, width: spreadW, height: spreadH), pageInfo: [:])
                drawCoverSpread(
                    context: context, doc: doc, ledger: ledger,
                    spinePt: spinePt, spreadSize: CGSize(width: spreadW, height: spreadH)
                )
                // ② 内页（套出血）：从屏幕版第 1 页起——第 0 页封面已进
                // 展开图左区，再嵌一遍就是封面重复（v5.11.5 修复，取页
                // 口径以 PrintBookSpec 为唯一事实源）
                for index in PrintBookSpec.interiorSourceIndices(sourcePageCount: doc.pageCount) {
                    guard let page = doc.page(at: index) else { continue }
                    context.beginPage(withBounds: bleedBounds, pageInfo: [:])
                    let cg = context.cgContext
                    PDFPageDrawing.fillPage(bleedBounds, bai: bai, in: cg)
                    let image = page.thumbnail(
                        of: CGSize(width: pageW * 4, height: pageH * 4),
                        for: .mediaBox
                    )
                    image.draw(in: CGRect(x: bleed, y: bleed, width: pageW, height: pageH))
                }
                // ③ 印刷参数说明（成品尺寸页，无出血）
                context.beginPage(
                    withBounds: CGRect(x: 0, y: 0, width: pageW, height: pageH),
                    pageInfo: [:]
                )
                drawSpecPage(
                    context: context, ledger: ledger,
                    interiorPages: PrintBookSpec.interiorPageCount(sourcePageCount: doc.pageCount),
                    spineWidthMM: spineWidthMM, script: libuScript
                )
            }
        } catch {
            return nil
        }
        return url
    }

    // MARK: - 封面展开图（右开本：左＝封面，中＝书脊，右＝封底）

    private static func drawCoverSpread(
        context: UIGraphicsPDFRendererContext, doc: PDFDocument,
        ledger: Ledger, spinePt: CGFloat, spreadSize: CGSize
    ) {
        let cg = context.cgContext
        let bai = ledger.isBai
        let bounds = CGRect(origin: .zero, size: spreadSize)
        PDFPageDrawing.fillPage(bounds, bai: bai, in: cg)

        let coverRect = CGRect(x: bleed, y: bleed, width: pageW, height: pageH)
        let spineRect = CGRect(x: bleed + pageW, y: 0, width: spinePt, height: spreadSize.height)
        let backRect = CGRect(x: bleed + pageW + spinePt, y: bleed, width: pageW, height: pageH)

        // 封面：屏幕版第一页原样
        if let coverPage = doc.page(at: 0) {
            let image = coverPage.thumbnail(
                of: CGSize(width: pageW * 4, height: pageH * 4),
                for: .mediaBox
            )
            image.draw(in: coverRect)
        }

        // 书脊：深一档底＋竖排簿名（书脊太薄时不硬塞字，参数页有注明）
        cg.setFillColor((bai ? PDFPageDrawing.baiDeep : PDFPageDrawing.cinnabarDeep).cgColor)
        cg.fill(spineRect)
        if spinePt >= 12 {
            PDFPageDrawing.drawVerticalText(
                ledger.title,
                centerX: spineRect.midX, topY: bleed + 36,
                fontSize: min(17, spinePt * 0.6),
                color: .white, cg: cg
            )
        }

        // 封底：纸面＋居中竖排谱名＋印（素面留白，成书体面在克制）
        PDFPageDrawing.drawVerticalText(
            ledger.title,
            centerX: backRect.midX, topY: backRect.minY + pageH * 0.30,
            fontSize: 21, color: bai ? PDFPageDrawing.baiInk : PDFPageDrawing.ink, cg: cg
        )
        if let first = ledger.title.first {
            PDFPageDrawing.drawSeal(
                char: String(first),
                center: CGPoint(x: backRect.midX, y: backRect.minY + pageH * 0.30 + CGFloat(ledger.title.count) * 25 + 44),
                size: 40, bai: bai, cg: cg
            )
        }
    }

    // MARK: - 印刷参数说明页（给印厂看的操作说明，不上礼谱形制）

    private static func drawSpecPage(
        context: UIGraphicsPDFRendererContext, ledger: Ledger,
        interiorPages: Int, spineWidthMM: Double, script: LibuScript
    ) {
        // v5.13：参数页随谱面脚本出字（简繁双写逐句校；旧版只有简体
        // 一份、夹在繁体谱里属单语言时代的遗留，不再保留）。
        let trad = script == .traditional
        let cg = context.cgContext
        let bai = ledger.isBai
        let bounds = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        PDFPageDrawing.fillPage(bounds, bai: bai, in: cg)
        let ink = bai ? PDFPageDrawing.baiInk : PDFPageDrawing.ink
        let textRect = CGRect(x: 64, y: 84, width: pageW - 128, height: pageH - 168)

        var y = textRect.minY
        func block(_ text: String, size: CGFloat = 12.5, bold: Bool = false, gap: CGFloat = 10) {
            let height: CGFloat = size * 6
            PDFPageDrawing.drawParagraph(
                text, in: CGRect(x: textRect.minX, y: y, width: textRect.width, height: height),
                fontSize: size, color: ink, bold: bold, lineSpacing: 5
            )
            // 按行数估算推进（参数页是固定文案，逐段手排比自动流式更可控）
            let lines = max(1, Int(ceil(Double(text.count) / (size > 14 ? 18.0 : 30.0))))
            y += CGFloat(lines) * (size + 5) + gap
        }

        block(trad ? "印刷參數說明" : "印刷参数说明", size: 20, bold: true, gap: 16)
        block(trad ? "本書：\(ledger.title)（\(ledger.type)）· 內頁 \(interiorPages) 頁 · 另封面展開圖 1 頁（本文件第 1 頁）· 參數頁 1 頁（本頁）" : "本书：\(ledger.title)（\(ledger.type)）· 内页 \(interiorPages) 页 · 另封面展开图 1 页（本文件第 1 页）· 参数页 1 页（本页）")
        block(trad ? "一、開本方向：右開本。本書為豎排右起的傳統禮譜，裝訂邊在右側，與 POD 常規的左開本相反——下單時請務必書面確認按右開本裝訂，封面展開圖（第 1 頁）按右開本排版：左為封面、右為封底。" : "一、开本方向：右开本。本书为竖排右起的传统礼谱，装订边在右侧，与 POD 常规的左开本相反——下单时请务必书面确认按右开本装订，封面展开图（第 1 页）按右开本排版：左为封面、右为封底。", gap: 12)
        block(trad ? "二、出血與尺寸：成品 A4（210×297mm）。內頁與封面展開圖均已含 3mm 出血，請勿再調整頁邊距或二次裁切內容區；出血環為紙色延展。文件未附裁切標記，按出血邊裁切即可。" : "二、出血与尺寸：成品 A4（210×297mm）。内页与封面展开图均已含 3mm 出血，请勿再调整页边距或二次裁切内容区；出血环为纸色延展。文件未附裁切标记，按出血边裁切即可。", gap: 12)
        block(trad ? "三、色彩：文件為 RGB。朱砂、素藍等顏色轉 CMYK 後會有可感色差，請先打一頁樣張認色（重點看封面朱砂與內頁版框），確認後再整本印製；不要直接整本出片。" : "三、色彩：文件为 RGB。朱砂、素蓝等颜色转 CMYK 后会有可感色差，请先打一页样张认色（重点看封面朱砂与内页版框），确认后再整本印制；不要直接整本出片。", gap: 12)
        block(trad ? "四、書脊：本文件書脊寬按 \(String(format: "%.1f", spineWidthMM))mm 製作（按 \(interiorPages) 頁估算）。實際紙張厚度不同會有出入，請印廠按所選紙張復算後回確認，書脊文字居中即可。" : "四、书脊：本文件书脊宽按 \(String(format: "%.1f", spineWidthMM))mm 制作（按 \(interiorPages) 页估算）。实际纸张厚度不同会有出入，请印厂按所选纸张复算后回确认，书脊文字居中即可。", gap: 12)
        block(trad ? "五、紙張與裝訂建議：鎖線精裝；內頁米白膠版紙或輕型紙 80–100g（勿用純白銅版紙，太亮失禮譜氣）；封面硬紙板裱印。內頁滿版紙色為淺米色，印廠若建議改用米白紙實物呈色、內頁改白底，請先打樣對比再定。" : "五、纸张与装订建议：锁线精装；内页米白胶版纸或轻型纸 80–100g（勿用纯白铜版纸，太亮失礼谱气）；封面硬纸板裱印。内页满版纸色为浅米色，印厂若建议改用米白纸实物呈色、内页改白底，请先打样对比再定。", gap: 12)
        block(trad ? "六、頁序：第 1 頁封面展開圖 → 內頁（禮譜正文，順序與屏幕版一致）→ 本參數頁（本頁不裝訂進書，僅作交付說明）。" : "六、页序：第 1 页封面展开图 → 内页（礼谱正文，顺序与屏幕版一致）→ 本参数页（本页不装订进书，仅作交付说明）。", gap: 12)
        block(trad ? "—— 禮記 導出 · 印刷版禮譜" : "—— 礼记 导出 · 印刷版礼谱", size: 11)
    }
}

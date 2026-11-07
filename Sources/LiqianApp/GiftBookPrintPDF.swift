import Foundation
import PDFKit
import UIKit
import LiqianCore

/// 印刷版礼谱（v5 成书做实，Pro）：在屏幕版礼谱 PDF 之上装配印刷文件——
/// 屏幕版管线（GiftBookPDF）一字不动，这里只做印厂交付层：
/// ① 首页＝封面展开图（封面＋书脊＋封底一页，含出血；右开本排版：
///    左封面、右封底，下单须与印厂书面确认与本图一致）；
/// ② 内页逐页套 3mm 出血页盒（内容原样，出血环以同纸色延展）；
/// ③ 末页＝「印刷参数说明」（右开本、RGB 转档打样认色、纸张建议等，
///    口径引 POD 调研，见 V5-NOTES）。
/// 内页以 4 倍分辨率栅格化嵌回——印刷锐度够用且实现稳妥；封面展开图的
/// 封面区同理取自屏幕版封面页。
enum GiftBookPrintPDF {
    private static let pageW = CGFloat(PrintBookSpec.trimWidthPoints)
    private static let pageH = CGFloat(PrintBookSpec.trimHeightPoints)
    private static let bleed = CGFloat(PrintBookSpec.bleedPoints)

    /// 由已生成的屏幕版礼谱装配印刷版，返回临时文件 URL（失败 nil）
    static func makePrintPDF(screenPDF: URL, ledger: Ledger, spineWidthMM: Double) -> URL? {
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
                // ② 内页（套出血）
                for index in 0..<doc.pageCount {
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
                    interiorPages: doc.pageCount, spineWidthMM: spineWidthMM
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
        interiorPages: Int, spineWidthMM: Double
    ) {
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

        block("印刷参数说明", size: 20, bold: true, gap: 16)
        block("本书：\(ledger.title)（\(ledger.type)）· 内页 \(interiorPages) 页 · 另封面展开图 1 页（本文件第 1 页）· 参数页 1 页（本页）")
        block("一、开本方向：右开本。本书为竖排右起的传统礼谱，装订边在右侧，与 POD 常规的左开本相反——下单时请务必书面确认按右开本装订，封面展开图（第 1 页）按右开本排版：左为封面、右为封底。", gap: 12)
        block("二、出血与尺寸：成品 A4（210×297mm）。内页与封面展开图均已含 3mm 出血，请勿再调整页边距或二次裁切内容区；出血环为纸色延展。文件未附裁切标记，按出血边裁切即可。", gap: 12)
        block("三、色彩：文件为 RGB。朱砂、素蓝等颜色转 CMYK 后会有可感色差，请先打一页样张认色（重点看封面朱砂与内页版框），确认后再整本印制；不要直接整本出片。", gap: 12)
        block("四、书脊：本文件书脊宽按 \(String(format: "%.1f", spineWidthMM))mm 制作（按 \(interiorPages) 页估算）。实际纸张厚度不同会有出入，请印厂按所选纸张复算后回确认，书脊文字居中即可。", gap: 12)
        block("五、纸张与装订建议：锁线精装；内页米白胶版纸或轻型纸 80–100g（勿用纯白铜版纸，太亮失礼谱气）；封面硬纸板裱印。内页满版纸色为浅米色，印厂若建议改用米白纸实物呈色、内页改白底，请先打样对比再定。", gap: 12)
        block("六、页序：第 1 页封面展开图 → 内页（礼谱正文，顺序与屏幕版一致）→ 本参数页（本页不装订进书，仅作交付说明）。", gap: 12)
        block("—— 礼记 导出 · 印刷版礼谱", size: 11)
    }
}

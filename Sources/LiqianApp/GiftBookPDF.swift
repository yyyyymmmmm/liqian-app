import Foundation
import UIKit
import LiqianCore

/// 礼谱 PDF 生成（docs/LIBU-PDF-SPEC.md）：A4、竖排右起、楷体题字、
/// 金额中文大写、朱砂格线、封面落款盖印；白事整册换素蓝、无描金。
/// 口径：待送出的随礼不计入礼谱（钱还没送出去），汇总页另注笔数；
/// 同人同簿多笔并列多列不合并，与 App 一致。
/// 免费版每页页脚带「礼钱账本 · 导出」小字——会员版去掉此字样（导出分层卖点），
/// 届时把 footerBrand 置空即可。
enum GiftBookPDF {
    // A4 @72dpi
    private static let pageW: CGFloat = 595.28
    private static let pageH: CGFloat = 841.89
    private static let margin: CGFloat = 46
    private static let columnsPerPage = 8

    private static let footerBrand = "礼钱账本 · 导出" // 会员版置 ""

    // 印刷口径用浅色令牌的静态值（与 Palette 浅色一致；PDF 是留存物不跟深色模式）
    private static let paper = uiColor(0xF6F1E7)
    private static let cardInk = uiColor(0x2B2620)
    private static let stone = uiColor(0x6B6353)
    private static let cinnabar = uiColor(0xA62B1F)
    private static let cinnabarDeep = uiColor(0x8E241B)
    private static let gold = uiColor(0xB98A2F)
    private static let baiPaper = uiColor(0xECEEF0)
    private static let baiInk = uiColor(0x33383B)
    private static let baiPrimary = uiColor(0x5B6770)
    private static let baiDeep = uiColor(0x47525A)

    private static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// 生成礼谱并写到临时目录，返回文件 URL（失败返回 nil）
    static func makePDF(ledger: Ledger, records: [GiftRecord]) -> URL? {
        let bai = ledger.isBai
        // 成册口径：排除待送出；按日期升序（登记先后），同日按姓名定序
        let counted = records
            .filter { !$0.isPendingSend }
            .sorted { ($0.date, $0.person) < ($1.date, $1.person) }
        let pendingCount = records.count - counted.count

        let bounds = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let safeName = ledger.title.replacingOccurrences(of: "/", with: "、")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName)-礼谱.pdf")

        do {
            try renderer.writePDF(to: url) { context in
                drawCover(context: context, ledger: ledger, bai: bai)
                let chunks = stride(from: 0, to: counted.count, by: columnsPerPage).map {
                    Array(counted[$0..<min($0 + columnsPerPage, counted.count)])
                }
                if chunks.isEmpty {
                    drawContentPage(context: context, ledger: ledger, bai: bai, pageRecords: [], pageIndex: 1)
                } else {
                    for (i, chunk) in chunks.enumerated() {
                        drawContentPage(context: context, ledger: ledger, bai: bai, pageRecords: chunk, pageIndex: i + 1)
                    }
                }
                drawSummary(
                    context: context, ledger: ledger, bai: bai,
                    counted: counted, pendingCount: pendingCount
                )
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: - 封面

    private static func drawCover(context: UIGraphicsPDFRendererContext, ledger: Ledger, bai: Bool) {
        context.beginPage()
        let main = bai ? baiPrimary : cinnabar
        main.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: pageW, height: pageH))

        // 内框线：红事描金、白事白色细线（白事无金）
        let frameRect = CGRect(x: 20, y: 20, width: pageW - 40, height: pageH - 40)
        (bai ? UIColor.white.withAlphaComponent(0.5) : gold).setStroke()
        let frame = UIBezierPath(rect: frameRect)
        frame.lineWidth = 1
        frame.stroke()

        // 题字：簿名竖排居中
        let titleFont = kaitiFont(46)
        _ = drawVertical(
            ledger.title,
            centerX: pageW / 2, topY: 168,
            font: titleFont, color: .white, step: 58
        )
        // 题字左列：事由 + 公历 + 农历（右起读序：题字之后是小字列）
        let info = "\(ledger.type) · \(ledger.date) · \(LiqianDate.lunarString(for: ledger.date))"
        _ = drawVertical(
            info,
            centerX: pageW / 2 - 76, topY: 176,
            font: kaitiFont(14), color: UIColor.white.withAlphaComponent(0.85), step: 19
        )

        // 右下落款 + 印章
        _ = drawVertical(
            "主家谨识",
            centerX: pageW - 148, topY: pageH - 268,
            font: kaitiFont(15), color: UIColor.white.withAlphaComponent(0.9), step: 21
        )
        let sealChar = ledger.title.first.map { String($0) } ?? "礼"
        drawSeal(
            rect: CGRect(x: pageW - 128, y: pageH - 178, width: 60, height: 60),
            char: sealChar,
            fill: bai ? baiDeep : cinnabarDeep,
            border: UIColor.white.withAlphaComponent(0.65)
        )
    }

    // MARK: - 内页

    private static func drawContentPage(
        context: UIGraphicsPDFRendererContext,
        ledger: Ledger, bai: Bool,
        pageRecords: [GiftRecord], pageIndex: Int
    ) {
        context.beginPage()
        (bai ? baiPaper : paper).setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: pageW, height: pageH))
        let main = bai ? baiPrimary : cinnabar
        let ink = bai ? baiInk : cardInk
        let sub = bai ? baiPrimary : stone

        drawHeaderFooter(ledger: ledger, bai: bai, pageLabel: "第 \(pageIndex) 页")

        let contentTop: CGFloat = 92
        let contentBottom: CGFloat = 776
        let colW = (pageW - margin * 2) / CGFloat(columnsPerPage)

        // 列间朱砂（白事素蓝）细线
        main.withAlphaComponent(0.45).setStroke()
        for i in 1..<columnsPerPage {
            let x = pageW - margin - colW * CGFloat(i)
            let line = UIBezierPath()
            line.move(to: CGPoint(x: x, y: contentTop - 12))
            line.addLine(to: CGPoint(x: x, y: contentBottom))
            line.lineWidth = 0.75
            line.stroke()
        }

        for (i, r) in pageRecords.enumerated() {
            // 右起：第 0 列在最右
            let centerX = pageW - margin - colW * (CGFloat(i) + 0.5)
            var y = contentTop
            // 姓名：楷体大字，限 4 字高
            y = drawVertical(
                String(r.person.prefix(4)),
                centerX: centerX, topY: y,
                font: kaitiFont(20), color: ink, step: 26
            )
            y += 14
            // 金额大写
            y = drawVertical(
                MoneyText.chineseUppercase(cents: r.amountCents),
                centerX: centerX, topY: y,
                font: kaitiFont(13), color: main, step: 17.5
            )
            y += 10
            // 小字：阿拉伯金额 + 方式（随礼另注方向，避免混册时看错）
            var small = "\(LedgerMath.fmtMoney(cents: r.amountCents)) · \(r.method)"
            if r.direction == LiqianConstants.given { small += " · 随礼" }
            _ = drawVertical(
                small,
                centerX: centerX, topY: y,
                font: serifFont(9), color: sub, step: 12.5
            )
        }
    }

    // MARK: - 汇总页

    private static func drawSummary(
        context: UIGraphicsPDFRendererContext,
        ledger: Ledger, bai: Bool,
        counted: [GiftRecord], pendingCount: Int
    ) {
        context.beginPage()
        (bai ? baiPaper : paper).setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: pageW, height: pageH))
        let main = bai ? baiPrimary : cinnabar
        let ink = bai ? baiInk : cardInk

        drawHeaderFooter(ledger: ledger, bai: bai, pageLabel: "汇总")

        var y: CGFloat = 108
        drawText("汇总", at: CGPoint(x: margin, y: y), font: kaitiFont(24), color: ink)
        y += 52

        let receivedList = counted.filter { $0.direction == LiqianConstants.received }
        let givenList = counted.filter { $0.direction == LiqianConstants.given }
        let peopleCount = Set(counted.map(\.person)).count
        let totalReceived = receivedList.reduce(0) { $0 + $1.amountCents }
        let totalGiven = givenList.reduce(0) { $0 + $1.amountCents }

        let lineFont = kaitiFont(15.5)
        func line(_ s: String, dy: CGFloat = 34) {
            drawText(s, at: CGPoint(x: margin, y: y), font: lineFont, color: ink)
            y += dy
        }
        line("总人数 \(peopleCount) 人 · 总笔数 \(counted.count) 笔")
        if !receivedList.isEmpty {
            line("收礼合计 \(LedgerMath.fmtMoney(cents: totalReceived))")
            line("大写：\(MoneyText.chineseUppercase(cents: totalReceived))", dy: 40)
        }
        if !givenList.isEmpty {
            line("随礼合计 \(LedgerMath.fmtMoney(cents: totalGiven))")
            line("大写：\(MoneyText.chineseUppercase(cents: totalGiven))", dy: 40)
        }
        if pendingCount > 0 {
            line("另有待送出 \(pendingCount) 笔，未计入本谱。", dy: 40)
        }

        // 按方式分布（口径同上：只计已成册记录）
        var byMethod: [(method: String, cents: Int, count: Int)] = []
        for m in LiqianConstants.methods {
            let list = counted.filter { $0.method == m }
            if !list.isEmpty {
                byMethod.append((m, list.reduce(0) { $0 + $1.amountCents }, list.count))
            }
        }
        let otherMethods = counted.filter { !LiqianConstants.methods.contains($0.method) }
        if !otherMethods.isEmpty {
            byMethod.append(("其他", otherMethods.reduce(0) { $0 + $1.amountCents }, otherMethods.count))
        }
        if !byMethod.isEmpty {
            y += 6
            drawText("按方式", at: CGPoint(x: margin, y: y), font: kaitiFont(16), color: main)
            y += 36
            for item in byMethod {
                line("\(item.method)：\(LedgerMath.fmtMoney(cents: item.cents)) · \(item.count) 笔", dy: 30)
            }
        }

        // 校对空行（纸礼簿的手工仪式感）
        let checkY: CGFloat = pageH - 268
        drawText("校对：", at: CGPoint(x: margin, y: checkY), font: kaitiFont(15), color: ink)
        main.withAlphaComponent(0.6).setStroke()
        let underline = UIBezierPath()
        underline.move(to: CGPoint(x: margin + 52, y: checkY + 22))
        underline.addLine(to: CGPoint(x: margin + 232, y: checkY + 22))
        underline.lineWidth = 0.75
        underline.stroke()

        // 落款 + 盖印
        _ = drawVertical(
            "主家谨识",
            centerX: pageW - 148, topY: pageH - 268,
            font: kaitiFont(15), color: ink, step: 21
        )
        let sealChar = ledger.title.first.map { String($0) } ?? "礼"
        drawSeal(
            rect: CGRect(x: pageW - 128, y: pageH - 178, width: 60, height: 60),
            char: sealChar,
            fill: main,
            border: bai ? nil : gold
        )
    }

    // MARK: - 页眉页脚

    private static func drawHeaderFooter(ledger: Ledger, bai: Bool, pageLabel: String) {
        let sub = bai ? baiPrimary : stone
        // 页眉：簿名右对齐小字（右起版式，页眉从右读）
        let header = NSAttributedString(
            string: ledger.title,
            attributes: [.font: serifFont(11), .foregroundColor: sub]
        )
        let hs = header.size()
        header.draw(at: CGPoint(x: pageW - margin - hs.width, y: 36))
        // 页脚：左品牌小字（免费版口径）、中页码
        if !footerBrand.isEmpty {
            drawText(footerBrand, at: CGPoint(x: margin, y: pageH - 44), font: serifFont(8.5), color: sub)
        }
        let footer = NSAttributedString(
            string: pageLabel,
            attributes: [.font: serifFont(10), .foregroundColor: sub]
        )
        let fs = footer.size()
        footer.draw(at: CGPoint(x: (pageW - fs.width) / 2, y: pageH - 46))
    }

    // MARK: - 绘制原语

    /// 竖排：逐字自上而下、水平居中于 centerX，返回画完后的底部 y
    @discardableResult
    private static func drawVertical(
        _ text: String,
        centerX: CGFloat, topY: CGFloat,
        font: UIFont, color: UIColor, step: CGFloat
    ) -> CGFloat {
        var y = topY
        for ch in text {
            let s = String(ch)
            let attr = NSAttributedString(
                string: s,
                attributes: [.font: font, .foregroundColor: color]
            )
            let size = attr.size()
            attr.draw(at: CGPoint(x: centerX - size.width / 2, y: y))
            y += step
        }
        return y
    }

    private static func drawText(_ text: String, at point: CGPoint, font: UIFont, color: UIColor) {
        NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: color]
        ).draw(at: point)
    }

    /// 圆角方印：朱砂底、白字、内细框（与 SealStampView 同规格）
    private static func drawSeal(rect: CGRect, char: String, fill: UIColor, border: UIColor?) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.width * 0.16)
        fill.setFill()
        path.fill()
        let inner = rect.insetBy(dx: rect.width * 0.09, dy: rect.height * 0.09)
        let innerPath = UIBezierPath(roundedRect: inner, cornerRadius: rect.width * 0.10)
        UIColor.white.withAlphaComponent(0.55).setStroke()
        innerPath.lineWidth = 1
        innerPath.stroke()
        if let border {
            border.setStroke()
            let outer = UIBezierPath(roundedRect: rect, cornerRadius: rect.width * 0.16)
            outer.lineWidth = 1
            outer.stroke()
        }
        let attr = NSAttributedString(
            string: char,
            attributes: [.font: kaitiFont(rect.width * 0.52), .foregroundColor: UIColor.white]
        )
        let size = attr.size()
        attr.draw(at: CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        ))
    }

    // MARK: - 字体（楷体优先，回退宋体、再回退系统衬线）

    private static func kaitiFont(_ size: CGFloat) -> UIFont {
        for name in ["Kaiti SC", "STKaiti"] {
            if let f = UIFont(name: name, size: size) { return f }
        }
        return serifFont(size)
    }

    private static func serifFont(_ size: CGFloat) -> UIFont {
        for name in ["Songti SC", "STSongti SC", "STSong"] {
            if let f = UIFont(name: name, size: size) { return f }
        }
        if let descriptor = UIFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return UIFont.systemFont(ofSize: size)
    }
}

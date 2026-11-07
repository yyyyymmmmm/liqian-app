import Foundation
import UIKit
import LiqianCore

/// 礼谱 PDF 生成 v3（docs/LIBU-PDF-SPEC.md + docs/LIBU-V3-SPEC.md）：
/// A4、古籍版心（朱砂双线版框、天头留阔、地脚鱼尾＋谱名＋页码）、宣纸纹理、
/// 竖排右起、楷体题字、金额中文大写、三印（题字闲章/主家印/纪年印，-1.5° 手钤感
/// ＋印文种子噪点）、封面后可插入 AI/模板谱序页；白事整册换素蓝：版框单线、
/// 素纸无纹、无闲章、无描金。
/// 口径：待送出的随礼不计入礼谱（钱还没送出去），汇总页另注笔数；
/// 同人同簿多笔并列多列不合并，与 App 一致。
/// 免费版每页地脚带「礼钱账本 · 导出」小字——会员版去掉此字样（导出分层卖点），
/// 届时把 footerBrand 置空即可。
/// 字体仍用系统 Kaiti SC（书法字体授权是上架前商务事项，见 LIBU-V3-SPEC §5）。
enum GiftBookPDF {
    // A4 @72dpi
    private static let pageW: CGFloat = 595.28
    private static let pageH: CGFloat = 841.89
    private static let columnsPerPage = 8

    // 版心（v3）：版框距页边 上 90 / 下 55 / 左右 48；内容区再内收
    private static let frameX: CGFloat = 48
    private static let frameTop: CGFloat = 90
    private static let frameBottom: CGFloat = 55
    private static let contentLeft: CGFloat = 64
    private static let contentTop: CGFloat = 116
    private static let contentBottom: CGFloat = 763
    private static var contentRight: CGFloat { pageW - contentLeft }
    private static var colW: CGFloat {
        (contentRight - contentLeft) / CGFloat(columnsPerPage)
    }
    private static var frameRect: CGRect {
        CGRect(
            x: frameX, y: frameTop,
            width: pageW - frameX * 2, height: pageH - frameTop - frameBottom
        )
    }

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

    // MARK: - 入口

    /// 生成礼谱并写到临时目录，返回文件 URL（失败返回 nil）。
    /// hostName：礼谱落款姓名（导出 sheet 传入，缺省读「礼谱落款姓名」设置）；
    /// prefaceText：非空时在封面后插入谱序页（文本由导出 sheet 备好：AI 或模板）。
    static func makePDF(
        ledger: Ledger,
        records: [GiftRecord],
        hostName: String = UserDefaults.standard.string(forKey: "hostName") ?? "",
        prefaceText: String? = nil
    ) -> URL? {
        let bai = ledger.isBai
        let host = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
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
                drawCover(context: context, ledger: ledger, bai: bai, hostName: host)
                if let prefaceText, !prefaceText.isEmpty {
                    drawPreface(
                        context: context, ledger: ledger, bai: bai,
                        text: prefaceText, hostName: host
                    )
                }
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
                    counted: counted, pendingCount: pendingCount, hostName: host
                )
            }
            return url
        } catch {
            return nil
        }
    }

    /// 落款显示名：未设置落款姓名时用「主家」
    private static func colophonName(hostName: String) -> String {
        hostName.isEmpty ? "主家" : hostName
    }

    /// 题字闲章吉语（按事由；白事不用闲章，返回 nil）
    private static func idleSealText(for type: String) -> String? {
        switch type {
        case "婚礼": return "百年好合"
        case "寿宴": return "福寿康宁"
        case "乔迁": return "乔迁之喜"
        case "满月", "周岁": return "平安喜乐"
        case "升学": return "金榜题名"
        case "开业": return "开业大吉"
        case LiqianConstants.baiType: return nil
        default: return "吉祥如意"
        }
    }

    // MARK: - 封面

    private static func drawCover(
        context: UIGraphicsPDFRendererContext, ledger: Ledger, bai: Bool, hostName: String
    ) {
        context.beginPage()
        let main = bai ? baiPrimary : cinnabar
        main.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: pageW, height: pageH))

        // 线装暗示（封面/封底才有）：两道竖细线 + 四个装订点
        drawBindingMarks(color: .white)

        // 内框线：红事描金、白事白色细线（白事无金）
        let frameRect = CGRect(x: 20, y: 20, width: pageW - 40, height: pageH - 40)
        (bai ? UIColor.white.withAlphaComponent(0.5) : gold).setStroke()
        let frame = UIBezierPath(rect: frameRect)
        frame.lineWidth = 1
        frame.stroke()

        // 题字：簿名竖排居中（长名自动收紧字距，别压到落款区）
        let titleCount = max(ledger.title.count, 1)
        var titleStep: CGFloat = 58
        var titleSize: CGFloat = 46
        let titleAvail = (pageH - 330) - 168
        if CGFloat(titleCount) * titleStep > titleAvail {
            titleStep = titleAvail / CGFloat(titleCount)
            titleSize = max(30, titleStep * 0.79)
        }
        _ = drawVertical(
            ledger.title,
            centerX: pageW / 2, topY: 168,
            font: kaitiFont(titleSize), color: .white, step: titleStep
        )
        // 题字左列：事由 + 公历 + 干支全日期（全谱统一写法）
        let info = "\(ledger.type) · \(ledger.date) · \(LiqianDate.ganzhiFullDate(for: ledger.date))"
        _ = drawVertical(
            info,
            centerX: pageW / 2 - 76, topY: 176,
            font: kaitiFont(14), color: UIColor.white.withAlphaComponent(0.85), step: 19
        )

        // 题字闲章：题字右侧小印（白事无闲章——礼制）
        if let idle = idleSealText(for: ledger.type) {
            drawSeal(
                center: CGPoint(x: pageW / 2 + 70, y: 208),
                size: 44, text: idle,
                fill: cinnabarDeep,
                stroke: UIColor.white.withAlphaComponent(0.5),
                speck: cinnabar
            )
        }

        // 右下落款 + 主家印
        _ = drawVertical(
            "\(colophonName(hostName: hostName))谨识",
            centerX: pageW - 148, topY: pageH - 268,
            font: kaitiFont(15), color: UIColor.white.withAlphaComponent(0.9), step: 21
        )
        drawSeal(
            center: CGPoint(x: pageW - 98, y: pageH - 108),
            size: 54, text: hostName.isEmpty ? "主家谨识" : hostName,
            fill: bai ? baiDeep : cinnabarDeep,
            stroke: UIColor.white.withAlphaComponent(0.65),
            speck: main
        )
    }

    // MARK: - 谱序页（封面之后、内页之前；竖排右起、列网格同内页，放不下续页）

    private struct PrefaceColumn {
        var runs: [(text: String, font: UIFont, color: UIColor, step: CGFloat)] = []
    }

    private static func drawPreface(
        context: UIGraphicsPDFRendererContext,
        ledger: Ledger, bai: Bool,
        text: String, hostName: String
    ) {
        let ink = bai ? baiInk : cardInk
        let sub = bai ? baiPrimary : stone
        let bodyFont = kaitiFont(15)
        let bodyStep: CGFloat = 20
        let charsPerColumn = max(1, Int((contentBottom - contentTop) / bodyStep))

        var columns: [PrefaceColumn] = []
        let chars = Array(text.filter { !$0.isNewline })
        var idx = 0
        while idx < chars.count {
            let end = min(idx + charsPerColumn, chars.count)
            columns.append(PrefaceColumn(runs: [
                (String(chars[idx..<end]), bodyFont, ink, bodyStep),
            ]))
            idx = end
        }
        // 落款另起一列（先空一列再落款，谱序的呼吸感）
        columns.append(PrefaceColumn())
        let colophonIndex = columns.count
        columns.append(PrefaceColumn(runs: [
            ("\(colophonName(hostName: hostName)) 谨识", kaitiFont(15), ink, 20),
            (LiqianDate.ganzhiFullDate(for: ledger.date), serifFont(10.5), sub, 15),
        ]))

        let pageChunks = stride(from: 0, to: columns.count, by: columnsPerPage).map {
            Array(columns[$0..<min($0 + columnsPerPage, columns.count)])
        }
        for (pi, pageCols) in pageChunks.enumerated() {
            context.beginPage()
            drawPaperBase(bai: bai)
            drawHeaderFooter(ledger: ledger, bai: bai, pageLabel: pi == 0 ? "谱序" : "谱序（续）")
            for (ci, col) in pageCols.enumerated() {
                let centerX = contentRight - colW * (CGFloat(ci) + 0.5)
                var y = contentTop
                for (ri, run) in col.runs.enumerated() {
                    if ri > 0 { y += 6 }
                    y = drawVertical(
                        run.text, centerX: centerX, topY: y,
                        font: run.font, color: run.color, step: run.step
                    )
                }
                // 落款列下方钤主家印
                if pi * columnsPerPage + ci == colophonIndex {
                    drawSeal(
                        center: CGPoint(x: centerX, y: min(y + 30, contentBottom - 4)),
                        size: 54, text: hostName.isEmpty ? "主家谨识" : hostName,
                        fill: bai ? baiPrimary : cinnabar,
                        stroke: bai ? nil : gold,
                        speck: bai ? baiPaper : paper
                    )
                }
            }
        }
    }

    // MARK: - 内页

    private static func drawContentPage(
        context: UIGraphicsPDFRendererContext,
        ledger: Ledger, bai: Bool,
        pageRecords: [GiftRecord], pageIndex: Int
    ) {
        context.beginPage()
        drawPaperBase(bai: bai)
        let main = bai ? baiPrimary : cinnabar
        let ink = bai ? baiInk : cardInk
        let sub = bai ? baiPrimary : stone

        drawHeaderFooter(ledger: ledger, bai: bai, pageLabel: "第 \(pageIndex) 页")

        // 列间朱砂（白事素蓝）细线
        main.withAlphaComponent(0.45).setStroke()
        for i in 1..<columnsPerPage {
            let x = contentRight - colW * CGFloat(i)
            let line = UIBezierPath()
            line.move(to: CGPoint(x: x, y: contentTop - 10))
            line.addLine(to: CGPoint(x: x, y: contentBottom))
            line.lineWidth = 0.75
            line.stroke()
        }

        for (i, r) in pageRecords.enumerated() {
            // 右起：第 0 列在最右
            let centerX = contentRight - colW * (CGFloat(i) + 0.5)
            var y = contentTop
            // 姓名：楷体大字，限 4 字高
            y = drawVertical(
                String(r.person.prefix(4)),
                centerX: centerX, topY: y,
                font: kaitiFont(20), color: ink, step: 27
            )
            y += 14
            // 金额大写
            y = drawVertical(
                MoneyText.chineseUppercase(cents: r.amountCents),
                centerX: centerX, topY: y,
                font: kaitiFont(13), color: main, step: 18
            )
            y += 10
            // 小字：阿拉伯金额 + 方式（随礼另注方向，避免混册时看错）
            var small = "\(LedgerMath.fmtMoney(cents: r.amountCents)) · \(r.method)"
            if r.direction == LiqianConstants.given { small += " · 随礼" }
            _ = drawVertical(
                small,
                centerX: centerX, topY: y,
                font: serifFont(9), color: sub, step: 13
            )
        }
    }

    // MARK: - 汇总页（封底）

    private static func drawSummary(
        context: UIGraphicsPDFRendererContext,
        ledger: Ledger, bai: Bool,
        counted: [GiftRecord], pendingCount: Int, hostName: String
    ) {
        context.beginPage()
        drawPaperBase(bai: bai)
        let main = bai ? baiPrimary : cinnabar
        let ink = bai ? baiInk : cardInk

        drawHeaderFooter(ledger: ledger, bai: bai, pageLabel: "汇总")
        // 线装暗示（封底才有）
        drawBindingMarks(color: main)

        var y: CGFloat = 132
        drawText("汇总", at: CGPoint(x: contentLeft, y: y), font: kaitiFont(24), color: ink)
        y += 52

        let receivedList = counted.filter { $0.direction == LiqianConstants.received }
        let givenList = counted.filter { $0.direction == LiqianConstants.given }
        let peopleCount = Set(counted.map(\.person)).count
        let totalReceived = receivedList.reduce(0) { $0 + $1.amountCents }
        let totalGiven = givenList.reduce(0) { $0 + $1.amountCents }

        let lineFont = kaitiFont(15.5)
        func line(_ s: String, dy: CGFloat = 34) {
            drawText(s, at: CGPoint(x: contentLeft, y: y), font: lineFont, color: ink)
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
            drawText("按方式", at: CGPoint(x: contentLeft, y: y), font: kaitiFont(16), color: main)
            y += 36
            for item in byMethod {
                line("\(item.method)：\(LedgerMath.fmtMoney(cents: item.cents)) · \(item.count) 笔", dy: 30)
            }
        }

        // 校对空行（纸礼簿的手工仪式感）
        let checkY: CGFloat = pageH - 268
        drawText("校对：", at: CGPoint(x: contentLeft, y: checkY), font: kaitiFont(15), color: ink)
        main.withAlphaComponent(0.6).setStroke()
        let underline = UIBezierPath()
        underline.move(to: CGPoint(x: contentLeft + 52, y: checkY + 22))
        underline.addLine(to: CGPoint(x: contentLeft + 232, y: checkY + 22))
        underline.lineWidth = 0.75
        underline.stroke()

        // 落款 + 主家印 + 纪年印（干支年 + 月雅称，如「丙午冬月」）
        _ = drawVertical(
            "\(colophonName(hostName: hostName))谨识",
            centerX: pageW - 148, topY: pageH - 268,
            font: kaitiFont(15), color: ink, step: 21
        )
        drawSeal(
            center: CGPoint(x: pageW - 98, y: pageH - 120),
            size: 54, text: hostName.isEmpty ? "主家谨识" : hostName,
            fill: main,
            stroke: bai ? nil : gold,
            speck: bai ? baiPaper : paper
        )
        let eraText = LiqianDate.ganzhiYear(for: ledger.date)
            + LiqianDate.lunarMonthAlias(for: ledger.date)
        drawSeal(
            center: CGPoint(x: pageW - 184, y: pageH - 120),
            size: 48, text: eraText,
            fill: main,
            stroke: bai ? nil : gold,
            speck: bai ? baiPaper : paper
        )
    }

    // MARK: - 纸面、版框、页眉地脚、线装

    /// 纸面：底色 + 宣纸纹理（白事素纸无纹）
    private static func drawPaperBase(bai: Bool) {
        (bai ? baiPaper : paper).setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: pageW, height: pageH))
        if !bai {
            paperTexture.drawAsPattern(in: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        }
    }

    /// 版框：红事朱砂双线（外 1.6 / 内 0.5，间距约 6），白事素蓝单线（礼制差异）
    private static func drawPageFrame(bai: Bool) {
        if bai {
            baiPrimary.withAlphaComponent(0.85).setStroke()
            let p = UIBezierPath(rect: frameRect)
            p.lineWidth = 1
            p.stroke()
        } else {
            cinnabar.setStroke()
            let outer = UIBezierPath(rect: frameRect)
            outer.lineWidth = 1.6
            outer.stroke()
            let inner = UIBezierPath(rect: frameRect.insetBy(dx: 6, dy: 6))
            inner.lineWidth = 0.5
            inner.stroke()
        }
    }

    /// 页眉（天头：簿名右对齐小字）＋地脚（左谱名、右页码、居中鱼尾与品牌小字）
    private static func drawHeaderFooter(ledger: Ledger, bai: Bool, pageLabel: String) {
        drawPageFrame(bai: bai)
        let sub = bai ? baiPrimary : stone
        let main = bai ? baiPrimary : cinnabar

        let header = NSAttributedString(
            string: ledger.title,
            attributes: [.font: serifFont(11), .foregroundColor: sub]
        )
        let hs = header.size()
        header.draw(at: CGPoint(x: contentRight - hs.width, y: 56))

        let footY = pageH - 34
        drawText(ledger.title, at: CGPoint(x: frameX, y: footY), font: serifFont(9.5), color: sub)
        let footer = NSAttributedString(
            string: pageLabel,
            attributes: [.font: serifFont(10), .foregroundColor: sub]
        )
        let fs = footer.size()
        footer.draw(at: CGPoint(x: pageW - frameX - fs.width, y: footY))
        drawFishTail(center: CGPoint(x: pageW / 2, y: footY + 5), color: main)
        if !footerBrand.isEmpty {
            let brand = NSAttributedString(
                string: footerBrand,
                attributes: [.font: serifFont(7), .foregroundColor: sub.withAlphaComponent(0.8)]
            )
            let bs = brand.size()
            brand.draw(at: CGPoint(x: (pageW - bs.width) / 2, y: footY + 15))
        }
    }

    /// 小鱼尾（简化：左侧两条折线 + 右侧小三角），呼应版心折口
    private static func drawFishTail(center: CGPoint, color: UIColor) {
        color.withAlphaComponent(0.75).setStroke()
        let chevron = UIBezierPath()
        chevron.move(to: CGPoint(x: center.x - 10, y: center.y - 6))
        chevron.addLine(to: CGPoint(x: center.x - 2, y: center.y))
        chevron.addLine(to: CGPoint(x: center.x - 10, y: center.y + 6))
        chevron.lineWidth = 0.7
        chevron.stroke()
        color.withAlphaComponent(0.75).setFill()
        let tri = UIBezierPath()
        tri.move(to: CGPoint(x: center.x + 1, y: center.y - 6))
        tri.addLine(to: CGPoint(x: center.x + 9, y: center.y))
        tri.addLine(to: CGPoint(x: center.x + 1, y: center.y + 6))
        tri.close()
        tri.fill()
    }

    /// 线装暗示：距右缘约 8/15pt 两道竖细线 + 四个装订点（仅封面与封底调用）
    private static func drawBindingMarks(color: UIColor) {
        color.withAlphaComponent(0.5).setStroke()
        for x in [pageW - 15, pageW - 8] {
            let p = UIBezierPath()
            p.move(to: CGPoint(x: x, y: 64))
            p.addLine(to: CGPoint(x: x, y: pageH - 64))
            p.lineWidth = 0.6
            p.stroke()
        }
        color.withAlphaComponent(0.65).setFill()
        for i in 1...4 {
            let y = pageH * CGFloat(i) / 5
            UIBezierPath(ovalIn: CGRect(x: pageW - 11.5 - 2.2, y: y - 2.2, width: 4.4, height: 4.4)).fill()
        }
    }

    // MARK: - 宣纸纹理（固定种子生成一次，逐页平铺；白事不用）

    private static let paperTexture: UIImage = makePaperTexture()

    private static func makePaperTexture() -> UIImage {
        let side: CGFloat = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { _ in
            var rng = SeededRNG(state: 0x9E37_79B9_7F4A_7C15)
            for _ in 0..<2600 {
                let x = CGFloat(rng.next()) * side
                let y = CGFloat(rng.next()) * side
                let r = 0.5 + CGFloat(rng.next()) * 0.9
                let a = 0.02 + CGFloat(rng.next()) * 0.03
                UIColor(red: 0.45, green: 0.38, blue: 0.25, alpha: a).setFill()
                UIBezierPath(ovalIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
            }
        }
    }

    /// 确定性随机数（LCG）：纹理与印面噪点都靠它保证同谱同貌、不随进程变
    private struct SeededRNG {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 40) / 16_777_216.0
        }
    }

    /// 稳定字符串 hash（djb2 变体）：String.hashValue 跨进程随机，不能当种子
    private static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 5381
        for scalar in s.unicodeScalars {
            h = (h &* 33) &+ UInt64(scalar.value)
        }
        return h
    }

    // MARK: - 印章（三印共用：朱砂底白文、内细框、-1.5° 手钤、印文种子微噪点）

    private static func drawSeal(
        center: CGPoint, size: CGFloat, text: String,
        fill: UIColor, stroke: UIColor?, speck: UIColor
    ) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: -1.5 * .pi / 180)

        let rect = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: size * 0.12)
        fill.setFill()
        path.fill()
        if let stroke {
            stroke.setStroke()
            let outer = UIBezierPath(roundedRect: rect, cornerRadius: size * 0.12)
            outer.lineWidth = 1
            outer.stroke()
        }
        let inner = rect.insetBy(dx: size * 0.085, dy: size * 0.085)
        UIColor.white.withAlphaComponent(0.5).setStroke()
        let innerPath = UIBezierPath(roundedRect: inner, cornerRadius: size * 0.09)
        innerPath.lineWidth = max(0.75, size * 0.016)
        innerPath.stroke()

        drawSealText(text, in: inner)

        // 印泥不匀：以印文为种子的确定性纸色微噪点（裁进印面内）
        path.addClip()
        var rng = SeededRNG(state: stableHash(text) | 1)
        for _ in 0..<24 {
            let x = rect.minX + CGFloat(rng.next()) * rect.width
            let y = rect.minY + CGFloat(rng.next()) * rect.height
            let r = 0.6 + CGFloat(rng.next()) * 1.0
            let a = 0.05 + CGFloat(rng.next()) * 0.07
            speck.withAlphaComponent(a).setFill()
            UIBezierPath(ovalIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
        }
        ctx.restoreGState()
    }

    /// 印面文字排布：1 字居中；2–3 字竖列；4 字 2×2（右列先）；
    /// 5 字右 3 左 2；6 字右 3 左 3（列内自上而下，列序右起）
    private static func drawSealText(_ text: String, in rect: CGRect) {
        let chars = Array(text.prefix(6))
        guard !chars.isEmpty else { return }
        let columns: [[Character]]
        switch chars.count {
        case 1:
            columns = [chars]
        case 2, 3:
            columns = [chars]
        case 4:
            columns = [[chars[0], chars[1]], [chars[2], chars[3]]]
        case 5:
            columns = [[chars[0], chars[1], chars[2]], [chars[3], chars[4]]]
        default:
            columns = [[chars[0], chars[1], chars[2]], [chars[3], chars[4], chars[5]]]
        }
        let maxRows = columns.map(\.count).max() ?? 1
        let cellW = rect.width / CGFloat(columns.count)
        let cellH = rect.height / CGFloat(maxRows)
        let font = kaitiFont(min(cellW, cellH) * 0.8)
        for (ci, col) in columns.enumerated() {
            // ci = 0 是最右列
            let cx = rect.maxX - cellW * (CGFloat(ci) + 0.5)
            for (ri, ch) in col.enumerated() {
                let cy = rect.minY + cellH * (CGFloat(ri) + 0.5)
                let attr = NSAttributedString(
                    string: String(ch),
                    attributes: [.font: font, .foregroundColor: UIColor.white]
                )
                let size = attr.size()
                attr.draw(at: CGPoint(x: cx - size.width / 2, y: cy - size.height / 2))
            }
        }
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

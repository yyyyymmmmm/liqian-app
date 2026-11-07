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
/// v2.8（docs/V28-NOTES.md）：内页逐笔农历日期（同日只标首笔）、欄題
/// （红事「賀儀」/白事「奠儀」）、固定文字全繁体、金额大写走正式财务繁体
/// （MoneyText.chineseUppercaseTraditional）、汇总页加按日/按關係小計、
/// 卷末補記页。人名/簿名/事由等用户数据照原样，严禁繁简转换。
/// v2.10（docs/V210-NOTES.md）：主家/书记/核实人/地点改读礼簿属性
/// （汇总页落款区三行、封面信息列缀地点）；姓名列按 3 字位归一
/// （双字名间字）；白事大写不缀「整」；汇总后、補記前加答谢辞页
/// （红事「答謝」/白事「銘謝」）。
/// v3.1（docs/V31-NOTES.md）：内页按关系分段登记——段段换页另起，
/// 段首出题签（繁体关系名＋汉字笔数）；只有一段时不出题签。随礼与
/// 收礼同册（逐笔注「隨禮」），无独立随礼卷，分段统一作用于全册。
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

    private static let footerBrand = "禮錢賬本 · 導出" // 会员版置 ""（固定品牌串，繁体）

    // 印刷色（PRO-AUDIT §3.2 整改）：与 Palette v3 浅色令牌逐项同值，改色先改
    // docs/DESIGN.md 与 Palette 再同步此处；PDF 是留存物，只用浅色值不跟深色模式。
    // 对应关系：paper/cardInk/stone/cinnabar/gold = Palette 的 paper/ink/stone/primary/gold；
    // cinnabarDeep、baiDeep 为 PDF 印刷专用的同色系深阶（App 内无对应令牌）。
    private static let paper = uiColor(0xFAF9F6)
    private static let cardInk = uiColor(0x262520)
    private static let stone = uiColor(0x6F6C64)
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
    /// 主家/书记/核实人/地点是礼簿自身属性（v2.10），直接读 Ledger；
    /// hostName 参数只是兜底：礼簿没设主家时用它（缺省读全局「礼谱落款姓名」
    /// 设置），再空回退「主家」字面（colophonName）。
    /// prefaceText：非空时在封面后插入谱序页（文本由导出 sheet 备好：AI 或模板）。
    /// memorial：纪念版开关（v4.5 传承）——封面右上加「紀念」题签，其余版式与
    /// 正式礼谱完全一致（纪念版是只读导出物，不进日常记账流，靠题签区分）。
    static func makePDF(
        ledger: Ledger,
        records: [GiftRecord],
        hostName: String = UserDefaults.standard.string(forKey: "hostName") ?? "",
        prefaceText: String? = nil,
        memorial: Bool = false
    ) -> URL? {
        let bai = ledger.isBai
        let ledgerHost = (ledger.hostName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let host = ledgerHost.isEmpty
            ? hostName.trimmingCharacters(in: .whitespacesAndNewlines)
            : ledgerHost
        let location = (ledger.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // 成册口径：排除待送出；按日期升序（登记先后），同日按姓名定序
        let counted = records
            .filter { !$0.isPendingSend }
            .sorted { ($0.date, $0.person) < ($1.date, $1.person) }
        let pendingCount = records.count - counted.count
        // 逐笔日期口径：同一天只在该日首笔标注（全册流序判「首笔」，跨页同理），
        // 连排同日不重复出日期，版面清爽
        var seenDates = Set<String>()
        var firstOfDayIDs = Set<UUID>()
        for r in counted where !seenDates.contains(r.date) {
            seenDates.insert(r.date)
            firstOfDayIDs.insert(r.id)
        }

        let bounds = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let safeName = ledger.title.replacingOccurrences(of: "/", with: "、")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName)-礼谱.pdf")

        do {
            try renderer.writePDF(to: url) { context in
                drawCover(
                    context: context, ledger: ledger, bai: bai,
                    hostName: host, location: location, memorial: memorial
                )
                if let prefaceText, !prefaceText.isEmpty {
                    drawPreface(
                        context: context, ledger: ledger, bai: bai,
                        text: prefaceText, hostName: host
                    )
                }
                // 内页分段（v3.1）：按关系分段、段段换页另起，段首出题签；
                // 只有一段（或空册）时不出题签，与汇总小计的单组口径一致。
                // 页码全册连续。分组与保序走 Core 的 LibuSections。
                let sections = LibuSections.groupByRelation(counted) { $0.relation }
                let showSectionTitles = sections.count > 1
                if sections.isEmpty {
                    drawContentPage(
                        context: context, ledger: ledger, bai: bai,
                        pageRecords: [], pageIndex: 1, firstOfDayIDs: firstOfDayIDs,
                        sectionTitle: nil
                    )
                } else {
                    var pageIndex = 0
                    for section in sections {
                        let title = showSectionTitles
                            ? sectionTitleText(
                                relation: section.relation,
                                count: section.records.count
                            )
                            : nil
                        let chunks = stride(
                            from: 0, to: section.records.count, by: columnsPerPage
                        ).map {
                            Array(section.records[$0..<min($0 + columnsPerPage, section.records.count)])
                        }
                        for (ci, chunk) in chunks.enumerated() {
                            pageIndex += 1
                            drawContentPage(
                                context: context, ledger: ledger, bai: bai,
                                pageRecords: chunk, pageIndex: pageIndex,
                                firstOfDayIDs: firstOfDayIDs,
                                sectionTitle: ci == 0 ? title : nil
                            )
                        }
                    }
                }
                drawSummary(
                    context: context, ledger: ledger, bai: bai,
                    counted: counted, pendingCount: pendingCount, hostName: host
                )
                drawThanksPage(context: context, ledger: ledger, bai: bai, hostName: host)
                drawSupplementPage(context: context, ledger: ledger, bai: bai)
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

    /// 题字闲章吉语（按事由匹配简体词表键，印文固定串用繁体；白事不用闲章，返回 nil）
    private static func idleSealText(for type: String) -> String? {
        switch type {
        case "婚礼": return "百年好合"
        case "寿宴": return "福壽康寧"
        case "乔迁": return "喬遷之喜"
        case "满月", "周岁": return "平安喜樂"
        case "升学": return "金榜題名"
        case "开业": return "開業大吉"
        case LiqianConstants.baiType: return nil
        default: return "吉祥如意"
        }
    }

    // MARK: - 封面

    private static func drawCover(
        context: UIGraphicsPDFRendererContext, ledger: Ledger, bai: Bool,
        hostName: String, location: String = "", memorial: Bool = false
    ) {
        context.beginPage()
        let main = bai ? baiPrimary : cinnabar
        main.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: pageW, height: pageH))

        // 线装暗示（封面/封底才有）：两道竖细线 + 四个装订点
        drawBindingMarks(color: .white)

        // 纪念版题签（v4.5）：封面右上一枚竖排小签「紀念」，细框白字，
        // 与题字闲章分列两侧——闲章在题字右（+70），题签靠右框角，互不抢位。
        if memorial {
            let signCenterX = pageW - 64
            let signTop: CGFloat = 54
            let signStep: CGFloat = 25
            let signRect = CGRect(
                x: signCenterX - 16, y: signTop - 8,
                width: 32, height: signStep * 2 + 18
            )
            UIColor.white.withAlphaComponent(0.75).setStroke()
            let signPath = UIBezierPath(rect: signRect)
            signPath.lineWidth = 1
            signPath.stroke()
            _ = drawVertical(
                "紀念",
                centerX: signCenterX, topY: signTop,
                font: kaitiFont(19),
                color: UIColor.white.withAlphaComponent(0.92), step: signStep
            )
        }

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
        // 题字左列：事由（用户数据原样） + 公历 + 干支全日期（生成串转繁体，全谱统一写法）；
        // 地点非空时缀于末（固定词「於」繁体＋地点原文，地点是用户数据不转繁体）
        var info = "\(ledger.type) · \(ledger.date) · \(LibuText.traditionalGenerated(LiqianDate.ganzhiFullDate(for: ledger.date)))"
        if !location.isEmpty { info += " · 於\(location)" }
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

        // 右下落款 + 主家印（落款用语为固定串用繁体；姓名为用户数据原样）
        _ = drawVertical(
            "\(colophonName(hostName: hostName))謹識",
            centerX: pageW - 148, topY: pageH - 268,
            font: kaitiFont(15), color: UIColor.white.withAlphaComponent(0.9), step: 21
        )
        drawSeal(
            center: CGPoint(x: pageW - 98, y: pageH - 108),
            size: 54, text: hostName.isEmpty ? "主家謹識" : hostName,
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
            ("\(colophonName(hostName: hostName)) 謹識", kaitiFont(15), ink, 20),
            (LibuText.traditionalGenerated(LiqianDate.ganzhiFullDate(for: ledger.date)), serifFont(10.5), sub, 15),
        ]))

        drawColumnPages(
            context: context, ledger: ledger, bai: bai,
            columns: columns, pageLabel: "譜序",
            colophonIndex: colophonIndex, hostName: hostName
        )
    }

    /// 竖排文本页的分页绘制（谱序、答谢辞共用）：列自右起排、满 8 列续页，
    /// 落款列（colophonIndex）下方钤主家印。
    private static func drawColumnPages(
        context: UIGraphicsPDFRendererContext,
        ledger: Ledger, bai: Bool,
        columns: [PrefaceColumn], pageLabel: String,
        colophonIndex: Int, hostName: String
    ) {
        let pageChunks = stride(from: 0, to: columns.count, by: columnsPerPage).map {
            Array(columns[$0..<min($0 + columnsPerPage, columns.count)])
        }
        for (pi, pageCols) in pageChunks.enumerated() {
            context.beginPage()
            drawPaperBase(bai: bai)
            drawHeaderFooter(
                ledger: ledger, bai: bai,
                pageLabel: pi == 0 ? pageLabel : "\(pageLabel)（續）"
            )
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
                        size: 54, text: hostName.isEmpty ? "主家謹識" : hostName,
                        fill: bai ? baiPrimary : cinnabar,
                        stroke: bai ? nil : gold,
                        speck: bai ? baiPaper : paper
                    )
                }
            }
        }
    }

    // MARK: - 答谢辞页（汇总之后、補記之前；红事「答謝」/白事「銘謝」）

    /// 答谢辞正文（繁体固定模板，写死在 PDF 层）：只插值主家名与事由原文
    /// （均为用户数据，照原样、不转繁体）。白事版素语，全篇不用「賀/喜」字眼。
    private static func thanksText(ledger: Ledger, bai: Bool, hostName: String) -> String {
        let host = colophonName(hostName: hostName)
        if bai {
            return "諸位親朋，於家中有故之時，親臨弔唁，扶持相助，\(host)銘感五內。"
                + "哀痛之際，賴諸位慰藉，方得稍安。此恩此德，無以為報，唯銘諸心版。"
                + "謹彙此譜，非徒記數，實誌厚誼。他年展卷，當念今日諸位之情。"
        }
        return "諸位親朋，遠道而來，厚禮隆情，\(host)銘感於心。"
            + "\(ledger.type)之日，蓬蓽生輝，笑語盈堂；所記者非簿上之數，乃平生之厚誼也。"
            + "謹彙此譜，藏之箱篋，傳之子孫。他年展卷，猶見今日之盛；"
            + "諸位有用得著主家之處，但憑吩咐，必當竭誠以報。"
    }

    private static func drawThanksPage(
        context: UIGraphicsPDFRendererContext,
        ledger: Ledger, bai: Bool, hostName: String
    ) {
        let ink = bai ? baiInk : cardInk
        let sub = bai ? baiPrimary : stone
        let bodyFont = kaitiFont(15)
        let bodyStep: CGFloat = 20
        let charsPerColumn = max(1, Int((contentBottom - contentTop) / bodyStep))

        var columns: [PrefaceColumn] = []
        let chars = Array(thanksText(ledger: ledger, bai: bai, hostName: hostName).filter { !$0.isNewline })
        var idx = 0
        while idx < chars.count {
            let end = min(idx + charsPerColumn, chars.count)
            columns.append(PrefaceColumn(runs: [
                (String(chars[idx..<end]), bodyFont, ink, bodyStep),
            ]))
            idx = end
        }
        // 落款另起一列（先空一列再落款，与谱序同式）
        columns.append(PrefaceColumn())
        let colophonIndex = columns.count
        columns.append(PrefaceColumn(runs: [
            ("\(colophonName(hostName: hostName)) 謹謝", kaitiFont(15), ink, 20),
            (LibuText.traditionalGenerated(LiqianDate.ganzhiFullDate(for: ledger.date)), serifFont(10.5), sub, 15),
        ]))

        drawColumnPages(
            context: context, ledger: ledger, bai: bai,
            columns: columns, pageLabel: bai ? "銘謝" : "答謝",
            colophonIndex: colophonIndex, hostName: hostName
        )
    }

    // MARK: - 内页

    private static func drawContentPage(
        context: UIGraphicsPDFRendererContext,
        ledger: Ledger, bai: Bool,
        pageRecords: [GiftRecord], pageIndex: Int,
        firstOfDayIDs: Set<UUID>,
        sectionTitle: String?
    ) {
        context.beginPage()
        drawPaperBase(bai: bai)
        let main = bai ? baiPrimary : cinnabar
        let ink = bai ? baiInk : cardInk
        let sub = bai ? baiPrimary : stone

        drawHeaderFooter(ledger: ledger, bai: bai, pageLabel: "第 \(pageIndex) 頁")

        // 欄題：版框内顶端居中（红事「賀儀」/白事「奠儀」；白事全谱禁用賀字）
        let columnTitle = bai ? "奠儀" : "賀儀"
        let titleAttr = NSAttributedString(
            string: columnTitle,
            attributes: [.font: kaitiFont(15), .foregroundColor: main]
        )
        let titleSize = titleAttr.size()
        titleAttr.draw(at: CGPoint(x: (pageW - titleSize.width) / 2, y: 99))

        // 段题签（v3.1）：只在段首页、欄題之下出（续页不重复，老谱规矩）。
        // 出题签的页，列线与记录列整体下移让位。
        let recordsTop = contentTop + (sectionTitle != nil ? 36 : 0)
        if let sectionTitle {
            drawSectionTitle(sectionTitle, bai: bai, topY: 126)
        }

        // 列间朱砂（白事素蓝）细线（自欄題/题签下方起）
        main.withAlphaComponent(0.45).setStroke()
        for i in 1..<columnsPerPage {
            let x = contentRight - colW * CGFloat(i)
            let line = UIBezierPath()
            line.move(to: CGPoint(x: x, y: recordsTop + 6))
            line.addLine(to: CGPoint(x: x, y: contentBottom))
            line.lineWidth = 0.75
            line.stroke()
        }

        for (i, r) in pageRecords.enumerated() {
            // 右起：第 0 列在最右
            let centerX = contentRight - colW * (CGFloat(i) + 0.5)
            var y = recordsTop
            // 姓名：楷体大字，限 4 字高（用户数据原样）；按 3 字位归一排版
            y = drawNameColumn(
                r.person,
                centerX: centerX, topY: y,
                font: kaitiFont(20), color: ink, step: 27
            )
            y += 14
            // 金额大写（正式财务繁体，PDF 专用；白事奠儀不缀「整」）
            y = drawVertical(
                upperAmount(cents: r.amountCents, bai: bai),
                centerX: centerX, topY: y,
                font: kaitiFont(13), color: main, step: 18
            )
            y += 10
            // 小字：阿拉伯金额 + 方式（随礼另注方向，避免混册时看错；方式为记录数据原样）
            var small = "\(LedgerMath.fmtMoney(cents: r.amountCents)) · \(r.method)"
            if r.direction == LiqianConstants.given { small += " · 隨禮" }
            y = drawVertical(
                small,
                centerX: centerX, topY: y,
                font: serifFont(9), color: sub, step: 13
            )
            // 逐笔日期：该日首笔才标农历月日小字（生成串转繁体），同日连排不重复
            if firstOfDayIDs.contains(r.id) {
                y += 8
                _ = drawVertical(
                    LibuText.traditionalGenerated(LiqianDate.lunarMonthDay(for: r.date)),
                    centerX: centerX, topY: y,
                    font: kaitiFont(10.5), color: sub, step: 14
                )
            }
        }
    }

    // MARK: - 段题签（v3.1）

    /// 关系名的繁体字面（仅系统词表内的值）：关系是 Picker 选的系统词，
    /// 不是用户自由文本，换繁体与欄題/汇总固定串同口径；词表外的关系
    /// （历史数据原文）不映射、照原样出（见 traditionalRelation）。
    private static let traditionalRelations: [String: String] = [
        "亲戚": "親戚", "朋友": "朋友", "同事": "同事",
        "同学": "同學", "邻居": "鄰居", "其他": "其他",
    ]

    private static func traditionalRelation(_ relation: String) -> String {
        traditionalRelations[relation] ?? relation
    }

    /// 段题签文案：繁体关系名 · 汉字笔数（如「親戚 · 拾貳筆」）
    private static func sectionTitleText(relation: String, count: Int) -> String {
        "\(traditionalRelation(relation)) · \(LibuText.chineseCount(count))筆"
    }

    /// 段题签绘制：楷体 13（小于欄題 15，不抢层级）、主色，水平居中于版心；
    /// 题文两侧各缀一段 30pt 主色细线，与版框线语言一致。
    private static func drawSectionTitle(_ text: String, bai: Bool, topY: CGFloat) {
        let main = bai ? baiPrimary : cinnabar
        let attr = NSAttributedString(
            string: text,
            attributes: [.font: kaitiFont(13), .foregroundColor: main]
        )
        let size = attr.size()
        let x = (pageW - size.width) / 2
        attr.draw(at: CGPoint(x: x, y: topY))
        main.withAlphaComponent(0.6).setStroke()
        let midY = topY + size.height / 2
        for (x1, x2) in [(x - 42, x - 12), (x + size.width + 12, x + size.width + 42)] {
            let line = UIBezierPath()
            line.move(to: CGPoint(x: x1, y: midY))
            line.addLine(to: CGPoint(x: x2, y: midY))
            line.lineWidth = 0.75
            line.stroke()
        }
    }

    /// 姓名列（v2.10 双字名间字）：竖排按 3 字位归一——3 字及以上自然排；
    /// 恰 2 字时两字间让出一个字距（总跨度＝3 字位，与三字名底边齐）；
    /// 1 字名居中于中间字位。返回姓名列底边 y，金额列自此往下接（口径同旧）。
    @discardableResult
    private static func drawNameColumn(
        _ name: String,
        centerX: CGFloat, topY: CGFloat,
        font: UIFont, color: UIColor, step: CGFloat
    ) -> CGFloat {
        let chars = Array(name.prefix(4))
        guard !chars.isEmpty else { return topY }
        let slots: [Int]
        switch chars.count {
        case 1: slots = [1]
        case 2: slots = [0, 2]
        default: slots = Array(0..<chars.count)
        }
        for (ch, slot) in zip(chars, slots) {
            let attr = NSAttributedString(
                string: String(ch),
                attributes: [.font: font, .foregroundColor: color]
            )
            let size = attr.size()
            attr.draw(at: CGPoint(
                x: centerX - size.width / 2,
                y: topY + CGFloat(slot) * step
            ))
        }
        return topY + CGFloat(max(3, chars.count)) * step
    }

    /// 金额大写分派：红事走正式财务繁体（圓整），白事走奠儀版（不缀整）
    private static func upperAmount(cents: Int, bai: Bool) -> String {
        bai
            ? MoneyText.chineseUppercaseTraditionalBai(cents: cents)
            : MoneyText.chineseUppercaseTraditional(cents: cents)
    }

    // MARK: - 汇总页（封底）

    /// 汇总流式行：正文行与段头行（段头主色、略大），dy 为行后步进
    private struct SummaryLine {
        let text: String
        let size: CGFloat
        let isHeader: Bool
        let dy: CGFloat
    }

    private static func drawSummary(
        context: UIGraphicsPDFRendererContext,
        ledger: Ledger, bai: Bool,
        counted: [GiftRecord], pendingCount: Int, hostName: String
    ) {
        let main = bai ? baiPrimary : cinnabar
        let ink = bai ? baiInk : cardInk
        // 页题：白事用奠儀口径（繁体固定串）；红事「彙總」
        let title = bai ? "奠儀總計" : "彙總"

        let receivedList = counted.filter { $0.direction == LiqianConstants.received }
        let givenList = counted.filter { $0.direction == LiqianConstants.given }
        let peopleCount = Set(counted.map(\.person)).count
        let totalReceived = receivedList.reduce(0) { $0 + $1.amountCents }
        let totalGiven = givenList.reduce(0) { $0 + $1.amountCents }

        // —— 组装全部汇总行（固定文字繁体；人名/方式/关系等记录数据原样）——
        var lines: [SummaryLine] = []
        func add(_ s: String, size: CGFloat = 15.5, header: Bool = false, dy: CGFloat = 34) {
            lines.append(SummaryLine(text: s, size: size, isHeader: header, dy: dy))
        }
        add("總人數 \(peopleCount) 人 · 總筆數 \(counted.count) 筆")
        if !receivedList.isEmpty {
            add("收禮合計 \(LedgerMath.fmtMoney(cents: totalReceived))")
            add("大寫：\(upperAmount(cents: totalReceived, bai: bai))", dy: 40)
        }
        if !givenList.isEmpty {
            add("隨禮合計 \(LedgerMath.fmtMoney(cents: totalGiven))")
            add("大寫：\(upperAmount(cents: totalGiven, bai: bai))", dy: 40)
        }
        if pendingCount > 0 {
            add("另有待送出 \(pendingCount) 筆，未計入本譜。", dy: 40)
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
            add("按方式", size: 16, header: true, dy: 36)
            for item in byMethod {
                add("\(item.method)：\(LedgerMath.fmtMoney(cents: item.cents)) · \(item.count) 筆", dy: 30)
            }
        }

        // 按日小計（v2.8 新增；成册口径、日期升序；金额只出数字，大写只留总计。
        // 只有一天时与总计重复，不出此节）
        let dayGroups = Dictionary(grouping: counted, by: \.date)
            .sorted { $0.key < $1.key }
        if dayGroups.count > 1 {
            add("按日小計", size: 16, header: true, dy: 36)
            for (date, list) in dayGroups {
                let rec = list.filter { $0.direction == LiqianConstants.received }
                    .reduce(0) { $0 + $1.amountCents }
                let giv = list.filter { $0.direction == LiqianConstants.given }
                    .reduce(0) { $0 + $1.amountCents }
                var s = "\(LibuText.traditionalGenerated(LiqianDate.ganzhiFullDate(for: date))) · \(list.count) 筆"
                if rec > 0 { s += " 收 \(LedgerMath.fmtMoney(cents: rec))" }
                if giv > 0 { s += " 隨 \(LedgerMath.fmtMoney(cents: giv))" }
                add(s, size: 13.5, dy: 28)
            }
        }

        // 按關係小計（v2.8 新增；关系为记录数据原样，排序按词表序、表外者附后。
        // 只有一种关系时与总计重复，不出此节）
        let relGroups = Dictionary(grouping: counted, by: \.relation)
        if relGroups.count > 1 {
            add("按關係小計", size: 16, header: true, dy: 36)
            let orderedRelations = LiqianConstants.relations.filter { relGroups[$0] != nil }
                + relGroups.keys.filter { !LiqianConstants.relations.contains($0) }.sorted()
            for relation in orderedRelations {
                guard let list = relGroups[relation] else { continue }
                let rec = list.filter { $0.direction == LiqianConstants.received }
                    .reduce(0) { $0 + $1.amountCents }
                let giv = list.filter { $0.direction == LiqianConstants.given }
                    .reduce(0) { $0 + $1.amountCents }
                var s = "\(relation)：\(list.count) 筆"
                if rec > 0 { s += " 收 \(LedgerMath.fmtMoney(cents: rec))" }
                if giv > 0 { s += " 隨 \(LedgerMath.fmtMoney(cents: giv))" }
                add(s, size: 13.5, dy: 28)
            }
        }

        // —— 分页：末页底部留给校对与落款印章（行不得排进 pageH-300 以下）——
        let firstStartY: CGFloat = 190 // 首页题下（题 132 + 24 号字 + 呼吸）
        let contStartY = contentTop
        let lastBottom = pageH - 300
        var chunks: [[SummaryLine]] = []
        var current: [SummaryLine] = []
        var y = firstStartY
        for line in lines {
            if y + line.dy > contentBottom && !current.isEmpty {
                chunks.append(current)
                current = []
                y = contStartY
            }
            current.append(line)
            y += line.dy
        }
        chunks.append(current)
        // 恰好整页排满时尾部会多一个空块，去掉免得出一页空白汇总
        if chunks.count > 1, chunks[chunks.count - 1].isEmpty {
            chunks.removeLast()
        }
        // 末页溢出校对区时，把末尾行整体挪到新的一页
        func endY(of chunk: [SummaryLine], pageIndex: Int) -> CGFloat {
            (pageIndex == 0 ? firstStartY : contStartY) + chunk.reduce(0) { $0 + $1.dy }
        }
        while chunks.count > 0, endY(of: chunks[chunks.count - 1], pageIndex: chunks.count - 1) > lastBottom,
              chunks[chunks.count - 1].count > 1 {
            var moved: [SummaryLine] = []
            while endY(of: chunks[chunks.count - 1], pageIndex: chunks.count - 1) > lastBottom,
                  chunks[chunks.count - 1].count > 1 {
                moved.insert(chunks[chunks.count - 1].removeLast(), at: 0)
            }
            chunks.append(moved)
        }
        if chunks.isEmpty { chunks = [[]] }

        for (pi, chunk) in chunks.enumerated() {
            context.beginPage()
            drawPaperBase(bai: bai)
            drawHeaderFooter(
                ledger: ledger, bai: bai,
                pageLabel: pi == 0 ? title : "\(title)（續）"
            )
            if pi == 0 {
                // 线装暗示（汇总首页沿旧封底规格）
                drawBindingMarks(color: main)
                drawText(title, at: CGPoint(x: contentLeft, y: 132), font: kaitiFont(24), color: ink)
            }
            var ly = pi == 0 ? firstStartY : contStartY
            for line in chunk {
                drawText(
                    line.text, at: CGPoint(x: contentLeft, y: ly),
                    font: kaitiFont(line.size), color: line.isHeader ? main : ink
                )
                ly += line.dy
            }
        }
        // 以下校对/落款落在最后一个汇总页（当前页）上，位置口径与旧版一致

        // 校對空行（纸礼簿的手工仪式感）
        let checkY: CGFloat = pageH - 268
        drawText("校對：", at: CGPoint(x: contentLeft, y: checkY), font: kaitiFont(15), color: ink)
        main.withAlphaComponent(0.6).setStroke()
        let underline = UIBezierPath()
        underline.move(to: CGPoint(x: contentLeft + 52, y: checkY + 22))
        underline.addLine(to: CGPoint(x: contentLeft + 232, y: checkY + 22))
        underline.lineWidth = 0.75
        underline.stroke()

        // 書記 / 核實（v2.10）：礼簿属性里的记账人与核实人，与主家落款同处
        // 汇总页落款区（左下），各一行小字＋姓名首字小方印位；姓名是用户数据
        // 照原样。未设则整行不出；两行皆无时落款区即现状（仅主家落款与印）。
        var staffY = checkY + 44
        for (label, person) in [("書記", ledger.scribe), ("核實", ledger.verifier)] {
            let name = (person ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let lineText = "\(label) \(name)"
            let attr = NSAttributedString(
                string: lineText,
                attributes: [.font: kaitiFont(13.5), .foregroundColor: ink]
            )
            attr.draw(at: CGPoint(x: contentLeft, y: staffY))
            drawSeal(
                center: CGPoint(x: contentLeft + attr.size().width + 19, y: staffY + 10),
                size: 25, text: String(name.prefix(1)),
                fill: main,
                stroke: bai ? nil : gold,
                speck: bai ? baiPaper : paper
            )
            staffY += 40
        }

        // 落款 + 主家印 + 纪年印（干支年 + 月雅称，如「丙午冬月」，生成串转繁体）
        _ = drawVertical(
            "\(colophonName(hostName: hostName))謹識",
            centerX: pageW - 148, topY: pageH - 268,
            font: kaitiFont(15), color: ink, step: 21
        )
        drawSeal(
            center: CGPoint(x: pageW - 98, y: pageH - 120),
            size: 54, text: hostName.isEmpty ? "主家謹識" : hostName,
            fill: main,
            stroke: bai ? nil : gold,
            speck: bai ? baiPaper : paper
        )
        let eraText = LibuText.traditionalGenerated(
            LiqianDate.ganzhiYear(for: ledger.date)
                + LiqianDate.lunarMonthAlias(for: ledger.date)
        )
        drawSeal(
            center: CGPoint(x: pageW - 184, y: pageH - 120),
            size: 48, text: eraText,
            fill: main,
            stroke: bai ? nil : gold,
            speck: bai ? baiPaper : paper
        )
    }

    // MARK: - 補記页（卷末空白页：同版框同栏格，供打印后手写补记）

    private static func drawSupplementPage(
        context: UIGraphicsPDFRendererContext,
        ledger: Ledger, bai: Bool
    ) {
        context.beginPage()
        drawPaperBase(bai: bai)
        let main = bai ? baiPrimary : cinnabar

        drawHeaderFooter(ledger: ledger, bai: bai, pageLabel: "補記")

        // 页题：版框内顶端居中，与内页欄題同位同式
        let titleAttr = NSAttributedString(
            string: "補記",
            attributes: [.font: kaitiFont(15), .foregroundColor: main]
        )
        let titleSize = titleAttr.size()
        titleAttr.draw(at: CGPoint(x: (pageW - titleSize.width) / 2, y: 99))

        // 栏格：与内页相同的列间细线，空栏待手写
        main.withAlphaComponent(0.45).setStroke()
        for i in 1..<columnsPerPage {
            let x = contentRight - colW * CGFloat(i)
            let line = UIBezierPath()
            line.move(to: CGPoint(x: x, y: contentTop + 6))
            line.addLine(to: CGPoint(x: x, y: contentBottom))
            line.lineWidth = 0.75
            line.stroke()
        }
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
                stone.withAlphaComponent(a).setFill()
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

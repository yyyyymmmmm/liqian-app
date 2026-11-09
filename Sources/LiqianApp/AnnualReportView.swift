import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 人情年度报告（v5.11 叙事版重构）：与人情总览分工——那边管查
/// （数字＋下钻），这边管讲（故事）。结构：开场句 → 年度三格（全页
/// 只出现一次）→ 之最三连 → 与去年同比（只给差值、不复读绝对数）
/// → 按事由 → 年度总结句 → 一步分享。
/// 口径纯化：本页只讲所选年度；全时段待回等跨年数字一律不在本页
/// （那是人情总览页尾的事，v5.8 审计 #8）。稀疏年份（笔数 < 5）走
/// 简略模式：开场＋三格＋总结合成一卡，不摆半空的之最/事由。
/// 之最与总结全部由 LedgerMath 从真实记录派生，无数据整项不出现。
struct AnnualReportView: View {
    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]

    @State private var selectedYear: String = ""
    /// 分享图卡预渲染结果：进页/年份/数据变化时后台渲染好，
    /// 分享按钮一次点击直达系统分享（v5.8 审计 #8 的一步流）
    @State private var shareImage: Image?
    @State private var shareError: String?

    /// 统计隔离（PRO-AUDIT-2 第 2 项）：示例账本的记录不计入年度报告
    private var snapshots: [EntrySnapshot] {
        let ids = SampleData.sampleIDs(ledgers: ledgers)
        return AppSupport.snapshots(
            records: records.filter { !ids.contains($0.ledgerID) },
            ledgers: ledgers
        )
    }

    private var years: [String] {
        Array(Set(snapshots.map { String($0.date.prefix(4)) })).sorted(by: >)
    }

    private var year: String {
        if years.contains(selectedYear) { return selectedYear }
        let current = LiqianDate.currentYearString()
        return years.contains(current) ? current : (years.first ?? current)
    }

    private var yearBinding: Binding<String> {
        Binding(get: { year }, set: { selectedYear = $0 })
    }

    private var yearEntries: [EntrySnapshot] {
        snapshots.filter { $0.date.hasPrefix(year) }
    }

    private var summary: YearSummary {
        LedgerMath.yearSummary(from: snapshots, year: year)
    }

    private var prevYear: String { String((Int(year) ?? 0) - 1) }

    private var prevSummary: YearSummary {
        LedgerMath.yearSummary(from: snapshots, year: prevYear)
    }

    /// 同比只在上一年真有数据时出现，不足一年整条隐藏
    private var hasPrevData: Bool { prevSummary.count > 0 }

    private var peopleCount: Int {
        Set(yearEntries.filter { !$0.isPendingSend }.map(\.person)).count
    }

    private var highlights: LedgerMath.AnnualHighlights {
        LedgerMath.annualHighlights(from: yearEntries)
    }

    private var typeRows: [TypeSummary] {
        LedgerMath.typeSummary(from: yearEntries).filter { $0.count > 0 }
    }

    /// 主导事由占全年往来总额（收+随）的份额，给总结句点名「主角」用
    private var dominantShare: Double {
        let grand = typeRows.reduce(0) { $0 + $1.received + $1.given }
        guard grand > 0, let top = typeRows.first else { return 0 }
        return Double(top.received + top.given) / Double(grand)
    }

    private var openingLine: String {
        "\(year) 年，你与 \(peopleCount) 位亲友有过人情往来。"
    }

    private var closingLine: String {
        LedgerMath.annualClosingLine(
            dominantType: typeRows.first?.type,
            dominantShare: dominantShare,
            peopleCount: peopleCount
        )
    }

    /// 稀疏降级线：笔数太少时之最/事由摆出来全是半空卡，合并简略呈现
    private var isSparse: Bool { summary.count < 5 }

    /// 图卡之最一条：优先最大一笔，其次往来最多的人，都没有则不出
    private var cardHighlightLine: String? {
        if let b = highlights.biggest {
            let money = LedgerMath.fmtMoney(cents: b.amountCents)
            return b.direction == LiqianConstants.received
                ? "最大一笔：\(b.person) 随了 \(money)"
                : "最大一笔：你随给 \(b.person) \(money)"
        }
        if let t = highlights.topPerson {
            return "往来最多：\(t.name) · \(LedgerMath.fmtMoney(cents: t.received + t.given))"
        }
        return nil
    }

    /// 图卡渲染签名：年份或关键数字变了才重渲，避免每次刷新白渲
    private var shareRenderKey: String {
        "\(year)|\(summary.count)|\(summary.recv)|\(summary.given)|\(peopleCount)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: LiqianMetrics.spacingSM) {
                if years.isEmpty {
                    ContentUnavailableView {
                        Label("还没有记录", systemImage: "chart.bar.doc.horizontal")
                    } description: {
                        Text("先记几笔再来看年度报告。")
                    }
                    .padding(.top, 40)
                } else {
                    yearBar
                    if isSparse {
                        sparseCard
                    } else {
                        headlineCard
                        highlightsCard
                        if hasPrevData { yoyCard }
                        if !typeRows.isEmpty { typeCard }
                        closingCard
                    }
                    shareCard
                }
            }
            .padding(LiqianMetrics.spacingM)
        }
        .background(Palette.groupedBackground.ignoresSafeArea())
        .navigationTitle("人情年度报告")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: shareRenderKey) {
            renderShareImage()
        }
    }

    // MARK: - 年份（与人情总览同形态：菜单 Picker，不再 segmented 塞卡）

    private var yearBar: some View {
        HStack {
            Text("年份")
                .foregroundStyle(Palette.ink)
            Spacer()
            Picker("年份", selection: yearBinding) {
                ForEach(years, id: \.self) { y in
                    Text("\(y) 年").tag(y)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
        .liqianCardSurface(padding: 10)
    }

    // MARK: - 开场＋三格（数字全页只出现这一次）

    private var headlineCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingSM) {
            Text(openingLine)
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.ink)
                .lineSpacing(4)
            StatRow {
                StatCell(label: "收礼", value: LedgerMath.fmtMoney(cents: summary.recv))
                StatCell(label: "随礼", value: LedgerMath.fmtMoney(cents: summary.given))
                StatCell(label: "往来人数", value: "\(peopleCount)")
            }
            Text("全年共 \(summary.count) 笔往来（待送出不计入）")
                .font(.footnote)
                .foregroundStyle(Palette.stone)
        }
        .liqianCardSurface()
    }

    /// 稀疏简略模式：开场、三格、总结合成一卡
    private var sparseCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingSM) {
            Text(openingLine)
                .font(.title3.weight(.bold))
                .foregroundStyle(Palette.ink)
                .lineSpacing(4)
            StatRow {
                StatCell(label: "收礼", value: LedgerMath.fmtMoney(cents: summary.recv))
                StatCell(label: "随礼", value: LedgerMath.fmtMoney(cents: summary.given))
                StatCell(label: "往来人数", value: "\(peopleCount)")
            }
            if !closingLine.isEmpty {
                Text(closingLine)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    .lineSpacing(4)
            }
            Text("这一年的往来还不多，先记着——笔数攒起来，年底再来看完整报告。")
                .font(.footnote)
                .foregroundStyle(Palette.stone)
        }
        .liqianCardSurface()
    }

    // MARK: - 之最三连（各项独立可缺，无数据整项不出现）

    private var highlightsCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("年度之最")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            if let b = highlights.biggest {
                highlightBlock(label: "最大一笔", line: biggestLine(b))
            }
            if let m = highlights.busiestMonth, highlights.busiestMonthCount > 0,
               Set(yearEntries.map { String($0.date.prefix(7)) }).count > 1 {
                highlightBlock(
                    label: "最忙的月份",
                    line: "\(m) 月最热闹，一个月里记了 \(highlights.busiestMonthCount) 笔。"
                )
            }
            if let t = highlights.topPerson {
                highlightBlock(label: "往来最多的人", line: topPersonLine(t))
            }
        }
        .liqianCardSurface()
    }

    private func highlightBlock(label: String, line: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Palette.stone)
            Text(line)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .lineSpacing(4)
        }
        .padding(.vertical, LiqianMetrics.spacingXS)
    }

    private func biggestLine(_ b: LedgerMath.AnnualHighlights.Biggest) -> String {
        let money = LedgerMath.fmtMoney(cents: b.amountCents)
        let scene = b.ledgerType.isEmpty ? "" : "在\(b.ledgerType)上"
        if b.direction == LiqianConstants.received {
            return "\(b.person)\(scene)随了 \(money)，是这一年最大的一笔。"
        }
        return "你\(scene)随给 \(b.person) 的 \(money)，是这一年最大的一笔。"
    }

    private func topPersonLine(_ t: PersonSummary) -> String {
        var s = "\(t.name)（\(t.relation)）全年往来 "
        s += "\(LedgerMath.fmtMoney(cents: t.received + t.given))，"
        if t.balance == 0 {
            s += "账已结清。"
        } else if t.balance > 0 {
            s += "还待回 \(LedgerMath.fmtMoney(cents: t.balance))。"
        } else {
            s += "你多随了 \(LedgerMath.fmtMoney(cents: -t.balance))。"
        }
        return s
    }

    // MARK: - 同比（只给差值，绝对数不在这里复读）

    private var yoyCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("与 \(prevYear) 年比")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            yoyLine("收礼", delta: summary.recv - prevSummary.recv, money: true)
            yoyLine("随礼", delta: summary.given - prevSummary.given, money: true)
            yoyLine("笔数", delta: summary.count - prevSummary.count, money: false)
        }
        .liqianCardSurface()
    }

    private func yoyLine(_ label: String, delta: Int, money: Bool) -> some View {
        let text: String
        if delta == 0 {
            text = "\(label)和去年一样"
        } else if money {
            text = delta > 0
                ? "\(label)比去年多了 \(LedgerMath.fmtMoney(cents: delta))"
                : "\(label)比去年少了 \(LedgerMath.fmtMoney(cents: -delta))"
        } else {
            text = delta > 0 ? "\(label)比去年多了 \(delta) 笔" : "\(label)比去年少了 \(-delta) 笔"
        }
        return Text(text)
            .font(.subheadline)
            .foregroundStyle(Palette.ink)
            .frame(minHeight: 28)
    }

    // MARK: - 按事由（与总览同口径占比条；本页只展示不下钻）

    private var typeCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("按事由")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            ForEach(typeRows) { t in
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                    HStack(spacing: LiqianMetrics.spacingSM) {
                        Text(t.type)
                            .foregroundStyle(Palette.ink)
                        Text("\(t.count) 笔")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(Palette.stone)
                        Spacer()
                    }
                    Text("收 \(LedgerMath.fmtMoney(cents: t.received)) · 随 \(LedgerMath.fmtMoney(cents: t.given))")
                        .font(.liqianMoney(.subheadline))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                    proportionBar(for: t)
                }
                .padding(.vertical, LiqianMetrics.spacingXS)
            }
        }
        .liqianCardSurface()
    }

    /// 事由占比条：与人情总览同口径（以最大事由总额为满格），只作视觉编码
    private func proportionBar(for t: TypeSummary) -> some View {
        let maxTotal = typeRows.map { $0.received + $0.given }.max() ?? 0
        let fraction = maxTotal > 0
            ? Double(t.received + t.given) / Double(maxTotal)
            : 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.stone.opacity(0.15))
                Capsule()
                    .fill(Palette.stone)
                    .frame(width: max(4, geo.size.width * fraction))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    // MARK: - 年度总结

    private var closingCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
            Text("这一年")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text(closingLine)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .lineSpacing(5)
        }
        .liqianCardSurface()
    }

    // MARK: - 分享（一步流：图卡预渲染，点一次直达系统分享）

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingSM) {
            Text("分享图卡")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text("含开场、一条之最与年度总结；只带往来第一位亲友的姓名，其余为年度汇总，不含明细。")
                .font(.footnote)
                .foregroundStyle(Palette.stone)
            if let shareImage {
                ShareLink(
                    item: shareImage,
                    preview: SharePreview("人情年度报告", image: shareImage)
                ) {
                    Label("分享年度图卡", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.primary)
            } else if shareError != nil {
                Text(shareError ?? "")
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
                Button {
                    renderShareImage()
                } label: {
                    Label("重新生成图卡", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                }
                .buttonStyle(.glass)
            } else {
                HStack(spacing: LiqianMetrics.spacingS) {
                    ProgressView()
                    Text("图卡生成中…")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
                .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
            }
        }
        .liqianCardSurface()
    }

    private func renderShareImage() {
        guard !years.isEmpty else { return }
        let card = AnnualReportCard(
            year: year,
            openingLine: openingLine,
            highlightLine: cardHighlightLine,
            closingLine: closingLine,
            todayText: LiqianDate.todayString()
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let ui = renderer.uiImage {
            shareImage = Image(uiImage: ui)
            shareError = nil
        } else {
            // 生成失败必须有反馈，不许静默（F5）
            shareImage = nil
            shareError = "图卡生成失败，请重试"
        }
    }
}

/// 分享图卡（叙事版）：竖版，米纸底、右侧竖排题字（衬线白名单：分享图卡）。
/// 内容只三件：开场句、一条之最、年度总结——不再复制报告页的三格数字。
struct AnnualReportCard: View {
    let year: String
    let openingLine: String
    let highlightLine: String?
    let closingLine: String
    let todayText: String

    private var verticalTitle: [String] {
        "\(year)年人情报告".map { String($0) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                Text(openingLine)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.paperInk)
                    .lineSpacing(5)
                Divider().overlay(Palette.paperLine)
                if let highlightLine {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("年度之最")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.paperStone)
                        Text(highlightLine)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Palette.paperInk)
                            .lineSpacing(4)
                    }
                }
                Spacer()
                if !closingLine.isEmpty {
                    Text(closingLine)
                        .font(.liqianSerifFixed(size: 15))
                        .foregroundStyle(Palette.paperInk)
                        .lineSpacing(5)
                }
                Text("礼记 · \(todayText)")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.paperStone)
            }
            Spacer()
            VStack(spacing: 14) {
                VStack(spacing: 3) {
                    ForEach(verticalTitle.indices, id: \.self) { i in
                        Text(verticalTitle[i])
                            .font(.liqianSerifFixed(size: 23))
                            .foregroundStyle(Palette.paperInk)
                    }
                }
                SealStampView(char: "礼", size: 44, fixedBrand: true)
            }
        }
        .padding(24)
        .frame(width: 340, height: 460, alignment: .topLeading)
        .background(Palette.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Palette.paperLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

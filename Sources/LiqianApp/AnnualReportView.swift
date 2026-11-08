import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 人情年度报告（v2）：按年汇总往来 + 可分享图卡。
/// 金额口径与「我的」页年度卡完全一致：LedgerMath.yearSummary——
/// 待送出的随礼不计入随礼金额与笔数（钱还没送出去）。待回礼为当前全时段口径。
struct AnnualReportView: View {
    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]

    @State private var selectedYear: String = ""
    @State private var shareImage: Image?
    @State private var shareError: String?
    /// 图卡生成成功触感（v4.7 审计补齐）：原来生成完只有图出现、无确认反馈
    @State private var shareTrigger = 0

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
        years.contains(selectedYear) ? selectedYear : (years.first ?? LiqianDate.currentYearString())
    }

    private var yearEntries: [EntrySnapshot] {
        snapshots.filter { $0.date.hasPrefix(year) }
    }

    private var summary: YearSummary {
        LedgerMath.yearSummary(from: snapshots, year: year)
    }

    private var peopleCount: Int {
        Set(yearEntries.filter { !$0.isPendingSend }.map(\.person)).count
    }

    private var topPeople: [PersonSummary] {
        LedgerMath.people(from: yearEntries)
            .sorted { ($0.received + $0.given) > ($1.received + $1.given) }
    }

    private var typeRows: [TypeSummary] {
        LedgerMath.typeSummary(from: yearEntries).filter { $0.count > 0 }
    }

    private var pendingPeople: [PersonSummary] {
        LedgerMath.people(from: snapshots).filter { $0.hasPending }
    }

    private var pendingTotal: Int {
        pendingPeople.reduce(0) { $0 + $1.pendingCents }
    }

    private var summarySentence: String {
        var s = "\(year) 年与 \(peopleCount) 位亲友有往来，共 \(summary.count) 笔，"
        s += "收礼 \(LedgerMath.fmtMoney(cents: summary.recv))，随礼 \(LedgerMath.fmtMoney(cents: summary.given))。"
        if !pendingPeople.isEmpty {
            s += "目前待回礼 \(pendingPeople.count) 人，合计 \(LedgerMath.fmtMoney(cents: pendingTotal))。"
        }
        return s
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
                    yearPickerCard
                    headlineCard
                    topCard
                    typeCard
                    pendingCard
                    shareCard
                }
            }
            .padding(LiqianMetrics.spacingM)
        }
        .background(Palette.groupedBackground.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: shareTrigger)
        .navigationTitle("人情年度报告")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedYear.isEmpty {
                selectedYear = years.contains(LiqianDate.currentYearString())
                    ? LiqianDate.currentYearString()
                    : (years.first ?? "")
            }
        }
    }

    private var yearPickerCard: some View {
        Picker("年份", selection: $selectedYear) {
            ForEach(years, id: \.self) { y in
                Text("\(y) 年").tag(y)
            }
        }
        .pickerStyle(.segmented)
        .liqianCardSurface(padding: 10)
    }

    private var headlineCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingSM) {
            Text("\(year) 年人情报告")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            // v5.3.2 统计格定版：三格等分居中（旧内容宽 HStack 左排）
            StatRow {
                StatCell(label: "收礼", value: LedgerMath.fmtMoney(cents: summary.recv))
                StatCell(label: "随礼", value: LedgerMath.fmtMoney(cents: summary.given))
                StatCell(label: "往来人数", value: "\(peopleCount)")
            }
            Text("共 \(summary.count) 笔往来（待送出不计入，与全年口径一致）")
                .font(.footnote)
                .foregroundStyle(Palette.stone)
            Text(summarySentence)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .lineSpacing(5)
        }
        .liqianCardSurface()
    }

    private var topCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("往来最多")
                .font(.headline.weight(.bold))
                .foregroundStyle(Palette.ink)
            if topPeople.isEmpty {
                Text("这一年还没有往来记录")
                    .foregroundStyle(Palette.stone)
            } else {
                ForEach(Array(topPeople.prefix(3).enumerated()), id: \.element.id) { idx, p in
                    HStack(spacing: LiqianMetrics.spacingSM) {
                        Text("\(idx + 1)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.stone)
                            .frame(width: 18, alignment: .leading)
                        Text(p.name)
                            .foregroundStyle(Palette.ink)
                        Text(p.relation)
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                        Spacer()
                        Text(LedgerMath.fmtMoney(cents: p.received + p.given))
                            .font(.liqianMoney(.title3))
                            .foregroundStyle(Palette.ink)
                            .contentTransition(.numericText())
                    }
                    .frame(minHeight: 36)
                }
            }
        }
        .liqianCardSurface()
    }

    private var typeCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("按事由")
                .font(.headline.weight(.bold))
                .foregroundStyle(Palette.ink)
            if typeRows.isEmpty {
                Text("还没有记录")
                    .foregroundStyle(Palette.stone)
            } else {
                ForEach(typeRows) { t in
                    HStack {
                        Text(t.type)
                            .foregroundStyle(Palette.ink)
                        Text("\(t.count) 笔")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                        Spacer()
                        Text("收 \(LedgerMath.fmtMoney(cents: t.received)) · 随 \(LedgerMath.fmtMoney(cents: t.given))")
                            .font(.liqianMoney(.title3))
                            .foregroundStyle(Palette.ink)
                            .contentTransition(.numericText())
                    }
                    .padding(.vertical, LiqianMetrics.spacingXS)
                }
            }
        }
        .liqianCardSurface()
    }

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("待回礼（累计）")
                .font(.headline.weight(.bold))
                .foregroundStyle(Palette.ink)
            if pendingPeople.isEmpty {
                Text("暂无待回礼记录")
                    .foregroundStyle(Palette.stone)
            } else {
                Text("待回礼 \(pendingPeople.count) 人 · 合计 \(LedgerMath.fmtMoney(cents: pendingTotal))")
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                // 文案与定版口径对齐（v4.4）：计算一直是净差额（LedgerMath），
                // 旧句描述的是已废止的「最后一笔收礼之后」规则，只改文案不动计算
                Text("收礼多于随礼的差额自动计算，不分年份。")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            }
        }
        .liqianCardSurface()
    }

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingSM) {
            Text("分享图卡")
                .font(.headline.weight(.bold))
                .foregroundStyle(Palette.ink)
            Text("含往来第一位亲友的姓名与汇总，其余为年度汇总数据。")
                .font(.footnote)
                .foregroundStyle(Palette.stone)
            Button {
                makeShareImage()
            } label: {
                Label("生成分享图", systemImage: "photo")
                    .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.primary)
            if let shareError {
                Text(shareError)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
            if let shareImage {
                ShareLink(
                    item: shareImage,
                    preview: SharePreview("人情年度报告", image: shareImage)
                ) {
                    Label("分享这张图", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                }
                .buttonStyle(.glass)
            }
        }
        .liqianCardSurface()
    }

    private func makeShareImage() {
        let card = AnnualReportCard(
            year: year,
            receivedCents: summary.recv,
            givenCents: summary.given,
            peopleCount: peopleCount,
            count: summary.count,
            topName: topPeople.first?.name,
            topTotalCents: topPeople.first.map { $0.received + $0.given },
            todayText: LiqianDate.todayString()
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let ui = renderer.uiImage {
            shareImage = Image(uiImage: ui)
            shareError = nil
            shareTrigger += 1
        } else {
            // 生成失败必须有反馈，不许静默（F5）
            shareError = "图卡生成失败，请重试"
        }
    }
}

/// 分享图卡：竖版，米纸底、右侧竖排题字、核心三数字、Top1、印章、日期。
/// 只放汇总数字与往来第一的姓名（与报告页同口径），不放他人明细。
struct AnnualReportCard: View {
    let year: String
    let receivedCents: Int
    let givenCents: Int
    let peopleCount: Int
    let count: Int
    let topName: String?
    let topTotalCents: Int?
    let todayText: String

    private var verticalTitle: [String] {
        "\(year)年人情报告".map { String($0) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                stat(label: "收礼", value: LedgerMath.fmtMoney(cents: receivedCents), color: Palette.paperInk)
                stat(label: "随礼", value: LedgerMath.fmtMoney(cents: givenCents), color: Palette.paperInk)
                stat(label: "往来亲友", value: "\(peopleCount) 位", color: Palette.paperInk)
                Divider().overlay(Palette.paperLine)
                if let topName, let topTotalCents {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("往来最多")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.paperStone)
                        Text("\(topName) · \(LedgerMath.fmtMoney(cents: topTotalCents))")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Palette.paperInk)
                    }
                }
                Text("全年共 \(count) 笔往来")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.paperStone)
                Spacer()
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

    private func stat(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.liqianMoneyFixed(size: 26))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Palette.paperStone)
        }
    }
}

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

    private var snapshots: [EntrySnapshot] {
        AppSupport.snapshots(records: records, ledgers: ledgers)
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
            s += "目前还有 \(pendingPeople.count) 人的礼没回，合计 \(LedgerMath.fmtMoney(cents: pendingTotal))。"
        }
        return s
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if years.isEmpty {
                    Text("还没有记录，先记几笔再来看年度报告。")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.stone)
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
            .padding(16)
        }
        .background(Palette.paper.ignoresSafeArea())
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
        VStack(alignment: .leading, spacing: 12) {
            Text("\(year) 年人情报告")
                .font(.liqianSerif(size: 20))
                .foregroundStyle(Palette.ink)
            HStack(spacing: 20) {
                headlineStat(label: "收礼", value: summary.recv, color: Palette.primary)
                headlineStat(label: "随礼", value: summary.given, color: Palette.ink)
                headlineStat(label: "往来人数", text: "\(peopleCount)", color: Palette.ink)
            }
            Text("共 \(summary.count) 笔往来（待送出不计入，与全年口径一致）")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.stone)
            Text(summarySentence)
                .font(.system(size: 14))
                .foregroundStyle(Palette.ink)
                .lineSpacing(5)
        }
        .liqianCardSurface()
    }

    private func headlineStat(label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LedgerMath.fmtMoney(cents: value))
                .font(.liqianMoney(size: 19))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Palette.stone)
        }
    }

    private func headlineStat(label: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.liqianMoney(size: 19))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Palette.stone)
        }
    }

    private var topCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("往来最多")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.ink)
            if topPeople.isEmpty {
                Text("这一年还没有往来记录")
                    .foregroundStyle(Palette.stone)
            } else {
                ForEach(Array(topPeople.prefix(3).enumerated()), id: \.element.id) { idx, p in
                    HStack(spacing: 10) {
                        Text("\(idx + 1)")
                            .font(.liqianSerif(size: 15))
                            .foregroundStyle(Palette.stone)
                            .frame(width: 18, alignment: .leading)
                        Text(p.name)
                            .foregroundStyle(Palette.ink)
                        Text(p.relation)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.stone)
                        Spacer()
                        Text(LedgerMath.fmtMoney(cents: p.received + p.given))
                            .font(.liqianMoney(size: 15))
                            .foregroundStyle(Palette.ink)
                    }
                    .frame(minHeight: 36)
                }
            }
        }
        .liqianCardSurface()
    }

    private var typeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("按事由")
                .font(.system(size: 16, weight: .bold))
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
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.stone)
                        Spacer()
                        Text("收 \(LedgerMath.fmtMoney(cents: t.received)) · 随 \(LedgerMath.fmtMoney(cents: t.given))")
                            .font(.liqianMoney(size: 14))
                            .foregroundStyle(Palette.ink)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .liqianCardSurface()
    }

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("待回礼（至今）")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.ink)
            if pendingPeople.isEmpty {
                Text("没有欠着的人情，轻松。")
                    .foregroundStyle(Palette.stone)
            } else {
                Text("\(pendingPeople.count) 人 · 合计 \(LedgerMath.fmtMoney(cents: pendingTotal)) 还没回")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.ink)
                Text("按「最近一次收礼之后还没送出」自动算的，这笔账不分年份。")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.stone)
            }
        }
        .liqianCardSurface()
    }

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("分享图卡")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.ink)
            Text("把这一年的人情往来做成一张图，发给家人一起看看。图上只有汇总数字，不带任何人的明细金额。")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.stone)
            Button {
                makeShareImage()
            } label: {
                Label("生成分享图", systemImage: "photo")
                    .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.primary)
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
                stat(label: "收礼", value: LedgerMath.fmtMoney(cents: receivedCents), color: Palette.primary)
                stat(label: "随礼", value: LedgerMath.fmtMoney(cents: givenCents), color: Palette.ink)
                stat(label: "往来亲友", value: "\(peopleCount) 位", color: Palette.ink)
                Divider().overlay(Palette.hairline)
                if let topName, let topTotalCents {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("往来最多")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.stone)
                        Text("\(topName) · \(LedgerMath.fmtMoney(cents: topTotalCents))")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Palette.ink)
                    }
                }
                Text("全年共 \(count) 笔往来")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.stone)
                Spacer()
                Text("礼钱账本 · \(todayText)")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.stone)
            }
            Spacer()
            VStack(spacing: 14) {
                VStack(spacing: 3) {
                    ForEach(verticalTitle.indices, id: \.self) { i in
                        Text(verticalTitle[i])
                            .font(.liqianSerif(size: 23))
                            .foregroundStyle(Palette.ink)
                    }
                }
                SealStampView(char: "礼", size: 44)
            }
        }
        .padding(24)
        .frame(width: 340, height: 460, alignment: .topLeading)
        .background(Palette.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Palette.gold, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func stat(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.liqianMoney(size: 26))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Palette.stone)
        }
    }
}

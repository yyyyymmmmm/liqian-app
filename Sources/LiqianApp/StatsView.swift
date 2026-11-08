import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 人情总览（v5.10 重构，审计 #7）：与图表 Tab、年度报告三面分工——
/// 图表管「看图」，本页管「看数＋下钻」，报告管「讲故事」。
/// 结构：结论条 → 年份切换＋年度三格 → 待回名单 → 按事由（带占比条、
/// 可下钻场次）→ 往来排行（Top 5＋查看全部）→ 全部时段一行。
/// 口径：统计隔离排除示例账本；全页随年份切换走；金额全是汇总口径，
/// 按 v5.0.2 定版走 StatCell＋fmtMoney 墨色（SignedMoneyText 只给逐笔）。
struct StatsView: View {
    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]

    @State private var selectedYear = ""
    @State private var personRoute: PeopleView.NameRoute?
    @State private var occasionRoute: OccasionRoute?
    @State private var showAllRanking = false

    struct OccasionRoute: Identifiable, Hashable {
        let type: String
        var id: String { type }
    }

    /// 统计隔离：示例账本的记录不计入
    private var sampleIDs: Set<UUID> { SampleData.sampleIDs(ledgers: ledgers) }

    private var statRecords: [GiftRecord] {
        let ids = sampleIDs
        return records.filter { !ids.contains($0.ledgerID) }
    }

    private var snapshots: [EntrySnapshot] {
        AppSupport.snapshots(records: statRecords, ledgers: ledgers)
    }

    /// 有数据的年份（倒序），与年度报告同一选择口径
    private var years: [String] {
        Array(Set(snapshots.map { String($0.date.prefix(4)) })).sorted(by: >)
    }

    /// 生效年份：选中值有效则用之，否则当前年优先、再退最近年份
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

    private var yearSummary: YearSummary {
        LedgerMath.yearSummary(from: snapshots, year: year)
    }

    private var peopleCount: Int {
        Set(yearEntries.filter { !$0.isPendingSend }.map(\.person)).count
    }

    /// 待回名单（该年口径）：差额为正的人，待回＝max(balance, 0) 定版口径
    private var pendingPeople: [PersonSummary] {
        LedgerMath.people(from: yearEntries)
            .filter { $0.hasPending }
            .sorted { $0.pendingCents > $1.pendingCents }
    }

    private var pendingTotal: Int {
        pendingPeople.reduce(0) { $0 + $1.pendingCents }
    }

    private var typeSummaries: [TypeSummary] {
        LedgerMath.typeSummary(from: yearEntries).filter { $0.count > 0 }
    }

    /// 往来排行（该年口径）：按收+随总额倒序，与往来页对齐同一排序
    private var rankedPeople: [PersonSummary] {
        LedgerMath.people(from: yearEntries)
            .sorted { ($0.received + $0.given) > ($1.received + $1.given) }
    }

    private var conclusionText: String {
        var s = "\(year) 年与 \(peopleCount) 位亲友有往来，共 \(yearSummary.count) 笔。"
        if !pendingPeople.isEmpty {
            s += "待回 \(pendingPeople.count) 人，合计 \(LedgerMath.fmtMoney(cents: pendingTotal))。"
        }
        return s
    }

    var body: some View {
        Group {
            if snapshots.isEmpty {
                ContentUnavailableView {
                    Label("还没有记录", systemImage: "chart.bar.doc.horizontal")
                } description: {
                    Text("先记几笔再来看人情总览。")
                }
            } else {
                list
            }
        }
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("人情总览")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $personRoute) { route in
            PersonDetailView(name: route.name)
        }
        .navigationDestination(item: $occasionRoute) { route in
            OccasionLedgersView(type: route.type, year: year)
        }
        .navigationDestination(isPresented: $showAllRanking) {
            AllRankingView(year: year)
        }
    }

    private var list: some View {
        List {
            // ① 结论条：一句自动结论，看完知道「所以呢」
            Section {
                Text(conclusionText)
                    .foregroundStyle(Palette.ink)
                    .frame(minHeight: LiqianMetrics.minTapTarget)
            }

            // ② 年份切换（与年度报告同口径）＋③ 年度三格（v5.3.2 定版）
            Section {
                Picker("年份", selection: yearBinding) {
                    ForEach(years, id: \.self) { y in
                        Text("\(y) 年").tag(y)
                    }
                }
                .pickerStyle(.menu)
                StatRow {
                    StatCell(label: "收礼", value: LedgerMath.fmtMoney(cents: yearSummary.recv))
                    StatCell(label: "随礼", value: LedgerMath.fmtMoney(cents: yearSummary.given))
                    StatCell(label: "笔数", value: "\(yearSummary.count)", unit: "笔")
                }
                .listRowInsets(EdgeInsets(
                    top: LiqianMetrics.spacingSM,
                    leading: LiqianMetrics.cardPadding,
                    bottom: LiqianMetrics.spacingSM,
                    trailing: LiqianMetrics.cardPadding
                ))
            } header: {
                Text("\(year) 年往来")
            }

            // 待回名单：结论条的下钻落点，点人进往来详情
            if !pendingPeople.isEmpty {
                Section {
                    ForEach(pendingPeople) { p in
                        personRow(p, trailing: "待回 \(LedgerMath.fmtMoney(cents: p.pendingCents))")
                    }
                } header: {
                    Text("待回")
                } footer: {
                    Text("待回为该年收随差额（收多于随的部分），点名字进往来详情。")
                }
            }

            // ④ 按事由：两行排版不再挤压，占比条给「哪个是大头」的视觉编码；
            // 点行下钻到该事由在该年的场次（礼簿）
            Section {
                if typeSummaries.isEmpty {
                    Text("这一年还没有记录")
                        .foregroundStyle(Palette.stone)
                } else {
                    ForEach(typeSummaries) { t in
                        Button {
                            occasionRoute = OccasionRoute(type: t.type)
                        } label: {
                            VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                                HStack(spacing: LiqianMetrics.spacingSM) {
                                    Text(t.type)
                                        .foregroundStyle(Palette.ink)
                                    Text("\(t.count) 笔")
                                        .font(.footnote)
                                        .monospacedDigit()
                                        .foregroundStyle(Palette.stone)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Palette.stone)
                                        .accessibilityHidden(true)
                                }
                                Text("收 \(LedgerMath.fmtMoney(cents: t.received)) · 随 \(LedgerMath.fmtMoney(cents: t.given))")
                                    .font(.liqianMoney(.subheadline))
                                    .foregroundStyle(Palette.ink)
                                    .contentTransition(.numericText())
                                proportionBar(for: t)
                            }
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("按事由")
            }

            // ⑤ 往来排行：Top 5＋查看全部（全名单同口径排序，点人下钻）
            Section {
                if rankedPeople.isEmpty {
                    Text("这一年还没有记录")
                        .foregroundStyle(Palette.stone)
                } else {
                    ForEach(Array(rankedPeople.prefix(5).enumerated()), id: \.element.id) { idx, p in
                        personRow(
                            p,
                            rank: idx + 1,
                            trailing: balanceText(p)
                        )
                    }
                    Button {
                        showAllRanking = true
                    } label: {
                        HStack {
                            Text("查看全部 \(rankedPeople.count) 人")
                                .foregroundStyle(Palette.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.stone)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("往来排行")
            }

            // 全时段总量：与年度口径分开，单独一段放页尾
            Section {
                Text("共 \(ledgers.count - sampleIDs.count) 本礼簿 · \(statRecords.count) 笔记录 · \(LedgerMath.people(from: snapshots).count) 位亲友")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Palette.stone)
            } header: {
                Text("全部时段")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    /// 人物行（待回名单/排行共用）：名次可选，右侧主数字为往来总额、
    /// 副文案由调用方给（待回金额或差额定版术语）
    private func personRow(
        _ p: PersonSummary, rank: Int? = nil, trailing: String
    ) -> some View {
        Button {
            personRoute = PeopleView.NameRoute(name: p.name)
        } label: {
            HStack(spacing: LiqianMetrics.spacingSM) {
                if let rank {
                    Text("\(rank)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.stone)
                        .frame(width: 18, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                    Text(p.name)
                        .foregroundStyle(Palette.ink)
                    Text(p.relation)
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: LiqianMetrics.spacingXS) {
                    Text(LedgerMath.fmtMoney(cents: p.received + p.given))
                        .font(.liqianMoney(.title3))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                    Text(trailing)
                        .font(.caption)
                        .foregroundStyle(Palette.stone)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.stone)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: LiqianMetrics.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 差额文案（定版术语）：待回／多随／已结清
    private func balanceText(_ p: PersonSummary) -> String {
        if p.balance == 0 { return "已结清" }
        return p.balance > 0
            ? "待回 \(LedgerMath.fmtMoney(cents: p.balance))"
            : "多随 \(LedgerMath.fmtMoney(cents: -p.balance))"
    }

    /// 事由占比条：以最大事由总额为满格，金额仍墨色、条只作视觉编码
    private func proportionBar(for t: TypeSummary) -> some View {
        let maxTotal = typeSummaries.map { $0.received + $0.given }.max() ?? 0
        let fraction = maxTotal > 0
            ? Double(t.received + t.given) / Double(maxTotal)
            : 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.stone.opacity(0.15))
                Capsule()
                    .fill(Palette.primary)
                    .frame(width: max(4, geo.size.width * fraction))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// 往来排行全名单（人情总览「查看全部」落点）：与总览排行同一数据源、
/// 同一排序（收+随总额倒序），点人进往来详情。
private struct AllRankingView: View {
    let year: String

    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @State private var personRoute: PeopleView.NameRoute?

    private var rankedPeople: [PersonSummary] {
        let ids = SampleData.sampleIDs(ledgers: ledgers)
        let snaps = AppSupport.snapshots(
            records: records.filter { !ids.contains($0.ledgerID) },
            ledgers: ledgers
        ).filter { $0.date.hasPrefix(year) }
        return LedgerMath.people(from: snaps)
            .sorted { ($0.received + $0.given) > ($1.received + $1.given) }
    }

    var body: some View {
        List {
            ForEach(Array(rankedPeople.enumerated()), id: \.element.id) { idx, p in
                Button {
                    personRoute = PeopleView.NameRoute(name: p.name)
                } label: {
                    HStack(spacing: LiqianMetrics.spacingSM) {
                        Text("\(idx + 1)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.stone)
                            .frame(width: 24, alignment: .leading)
                        VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                            Text(p.name)
                                .foregroundStyle(Palette.ink)
                            Text(p.relation)
                                .font(.footnote)
                                .foregroundStyle(Palette.stone)
                        }
                        Spacer()
                        Text(LedgerMath.fmtMoney(cents: p.received + p.given))
                            .font(.liqianMoney(.title3))
                            .foregroundStyle(Palette.ink)
                            .contentTransition(.numericText())
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.stone)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("\(year) 年往来排行")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $personRoute) { route in
            PersonDetailView(name: route.name)
        }
    }
}

/// 按事由下钻（人情总览「按事由」行落点）：该事由在该年有记录的场次
/// （礼簿）列表，点进礼簿详情。口径与总览一致：排除示例账本、
/// 按记录年份归属（不是礼簿日期），避免两边对不上。
private struct OccasionLedgersView: View {
    let type: String
    let year: String

    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @Query private var records: [GiftRecord]

    private var occasionLedgers: [Ledger] {
        let ids = SampleData.sampleIDs(ledgers: ledgers)
        let hitIDs = Set(
            records
                .filter {
                    !ids.contains($0.ledgerID) && $0.date.hasPrefix(year)
                }
                .map(\.ledgerID)
        )
        return ledgers.filter {
            $0.type == type && hitIDs.contains($0.id) && !ids.contains($0.id)
        }
    }

    private func summary(for ledger: Ledger) -> (count: Int, received: Int, given: Int) {
        var count = 0
        var received = 0
        var given = 0
        for r in records where r.ledgerID == ledger.id && r.date.hasPrefix(year) {
            if r.isPendingSend { continue }
            if r.direction == LiqianConstants.received {
                received += r.amountCents
            } else {
                given += r.amountCents
            }
            count += 1
        }
        return (count, received, given)
    }

    var body: some View {
        Group {
            if occasionLedgers.isEmpty {
                ContentUnavailableView {
                    Label("没有场次", systemImage: "book.closed")
                } description: {
                    Text("\(year) 年还没有「\(type)」的礼簿记录。")
                }
            } else {
                List {
                    ForEach(occasionLedgers) { ledger in
                        NavigationLink {
                            LedgerDetailView(ledger: ledger)
                        } label: {
                            let s = summary(for: ledger)
                            VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                                Text(ledger.title)
                                    .foregroundStyle(Palette.ink)
                                Text("\(ledger.date) · \(s.count) 笔 · 收 \(LedgerMath.fmtMoney(cents: s.received)) · 随 \(LedgerMath.fmtMoney(cents: s.given))")
                                    .font(.footnote)
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.stone)
                            }
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle(type)
        .navigationBarTitleDisplayMode(.inline)
    }
}

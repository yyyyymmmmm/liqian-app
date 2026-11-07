import Charts
import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 统计二级页（v3「我的」整合归档）：年度/事由统计、往来排行、关系分布从「我的」迁入。
/// 聚合口径与原 MeView 完全一致，只搬位置不改逻辑；金额一律墨色（v3 纪律）。
struct StatsView: View {
    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]

    @State private var personRoute: PeopleView.NameRoute?

    private var year: String { LiqianDate.currentYearString() }

    private var snapshots: [EntrySnapshot] {
        AppSupport.snapshots(records: records, ledgers: ledgers)
    }

    private var yearSummary: YearSummary {
        LedgerMath.yearSummary(from: snapshots, year: year)
    }

    private var typeSummaries: [TypeSummary] {
        LedgerMath.typeSummary(from: snapshots).filter { $0.count > 0 }
    }

    /// 往来排行：按收+随总额倒序
    private var rankedPeople: [PersonSummary] {
        LedgerMath.people(from: snapshots)
            .sorted { ($0.received + $0.given) > ($1.received + $1.given) }
    }

    private var relationSummaries: [RelationSummary] {
        LedgerMath.relationSummary(from: snapshots).filter { $0.count > 0 }
    }

    var body: some View {
        List {
            asCardRow(yearCard)
            asCardRow(typeCard)
            asCardRow(rankingCard)
            asCardRow(relationCard)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle("统计")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $personRoute) { route in
            PersonDetailView(name: route.name)
        }
    }

    // MARK: - 卡片们

    private var yearCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("\(year) 年往来")
                .font(.headline.weight(.bold))
                .foregroundStyle(Palette.ink)
            HStack(spacing: LiqianMetrics.spacingM) {
                HStack(spacing: LiqianMetrics.spacingS) {
                    Text("收礼")
                        .foregroundStyle(Palette.stone)
                    Text(LedgerMath.fmtMoney(cents: yearSummary.recv))
                        .font(.liqianMoney(.title3))
                        .foregroundStyle(Palette.ink)
                }
                HStack(spacing: LiqianMetrics.spacingS) {
                    Text("随礼")
                        .foregroundStyle(Palette.stone)
                    Text(LedgerMath.fmtMoney(cents: yearSummary.given))
                        .font(.liqianMoney(.title3))
                        .foregroundStyle(Palette.ink)
                }
                Text("共 \(yearSummary.count) 笔")
                    .foregroundStyle(Palette.stone)
            }
            .font(.body)
            Text("全部：\(ledgers.count) 本礼簿 · \(records.count) 笔记录 · \(LedgerMath.people(from: snapshots).count) 位亲友")
                .font(.footnote)
                .foregroundStyle(Palette.stone)
        }
        .statsCardSurface()
    }

    private var typeCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("按事由")
                .font(.headline.weight(.bold))
                .foregroundStyle(Palette.ink)
            if typeSummaries.isEmpty {
                Text("还没有记录")
                    .foregroundStyle(Palette.stone)
            } else {
                ForEach(typeSummaries) { t in
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
                    }
                    .padding(.vertical, LiqianMetrics.spacingXS)
                }
            }
        }
        .statsCardSurface()
    }

    /// 往来排行 Top5：往来总额最大的几位，差额小字辅助判断
    private var rankingCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("往来排行")
                .font(.headline.weight(.bold))
                .foregroundStyle(Palette.ink)
            if rankedPeople.isEmpty {
                Text("还没有记录")
                    .foregroundStyle(Palette.stone)
            } else {
                ForEach(Array(rankedPeople.prefix(5).enumerated()), id: \.element.id) { idx, p in
                    Button {
                        personRoute = PeopleView.NameRoute(name: p.name)
                    } label: {
                        HStack(spacing: LiqianMetrics.spacingSM) {
                            Text("\(idx + 1)")
                                .font(.liqianSerif(.subheadline))
                                .foregroundStyle(Palette.stone)
                                .frame(width: 18, alignment: .leading)
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
                                Text(balanceSmallText(p))
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
            }
        }
        .statsCardSurface()
    }

    private func balanceSmallText(_ p: PersonSummary) -> String {
        if p.balance == 0 { return "已结清" }
        return p.balance > 0
            ? "对方多给 \(LedgerMath.fmtMoney(cents: p.balance))"
            : "我多给 \(LedgerMath.fmtMoney(cents: -p.balance))"
    }

    /// 关系分布：按关系聚合往来总额的横向条形图。
    /// v3：朱砂单色阶——同一色按总额占比变透明度，不引入新色。
    private var relationCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("关系分布")
                .font(.headline.weight(.bold))
                .foregroundStyle(Palette.ink)
            if relationSummaries.isEmpty {
                Text("还没有记录")
                    .foregroundStyle(Palette.stone)
            } else {
                Chart(relationSummaries) { s in
                    BarMark(
                        x: .value("金额（元）", Double(s.total) / 100.0),
                        y: .value("关系", s.relation)
                    )
                    .foregroundStyle(Palette.primary.opacity(opacity(of: s)))
                    .cornerRadius(4)
                }
                .frame(height: CGFloat(relationSummaries.count) * 36 + 12)
            }
        }
        .statsCardSurface()
    }

    /// 单色阶透明度：最大总额为满色，其余按比例变淡（下限 0.35 保可读）
    private func opacity(of s: RelationSummary) -> Double {
        let maxTotal = relationSummaries.map(\.total).max() ?? 0
        guard maxTotal > 0 else { return 1 }
        return 0.35 + 0.65 * Double(s.total) / Double(maxTotal)
    }

    private func asCardRow<V: View>(_ view: V) -> some View {
        view
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: LiqianMetrics.spacingS, leading: LiqianMetrics.spacingM, bottom: LiqianMetrics.spacingS, trailing: LiqianMetrics.spacingM))
    }
}

/// 统计页卡片表面（与原「我的」页卡面口径一致：卡面色 + 发丝线 + 统一圆角）
private extension View {
    func statsCardSurface(padding: CGFloat = LiqianMetrics.cardPadding) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner))
            .overlay(
                RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                    .stroke(Palette.hairline, lineWidth: 1)
            )
    }
}

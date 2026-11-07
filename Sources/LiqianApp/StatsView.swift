import Charts
import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 统计二级页（PRO-AUDIT-2 §3.3 改版）：List(.insetGrouped) 原生 Section/行，
/// 私有卡面 statsCardSurface 已删（全 App 卡面只留 Components.liqianCardSurface 一份）。
/// 聚合口径与原「我的」页一致，另按第 2 项统计隔离排除示例账本；金额一律墨色。
struct StatsView: View {
    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @Environment(\.colorScheme) private var colorScheme

    @State private var personRoute: PeopleView.NameRoute?

    private var year: String { LiqianDate.currentYearString() }

    /// 统计隔离：示例账本的记录不计入
    private var sampleIDs: Set<UUID> { SampleData.sampleIDs(ledgers: ledgers) }

    private var statRecords: [GiftRecord] {
        let ids = sampleIDs
        return records.filter { !ids.contains($0.ledgerID) }
    }

    private var snapshots: [EntrySnapshot] {
        AppSupport.snapshots(records: statRecords, ledgers: ledgers)
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
            Section {
                HStack(spacing: LiqianMetrics.spacingM) {
                    summaryPair(label: "收礼", cents: yearSummary.recv)
                    summaryPair(label: "随礼", cents: yearSummary.given)
                    Text("共 \(yearSummary.count) 笔")
                        .monospacedDigit()
                        .foregroundStyle(Palette.stone)
                }
                .font(.body)
            } header: {
                Text("\(year) 年往来")
            } footer: {
                Text("全部：\(ledgers.count - sampleIDs.count) 本礼簿 · \(statRecords.count) 笔记录 · \(LedgerMath.people(from: snapshots).count) 位亲友")
                    .monospacedDigit()
            }

            Section {
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
                                .monospacedDigit()
                                .foregroundStyle(Palette.stone)
                            Spacer()
                            Text("收 \(LedgerMath.fmtMoney(cents: t.received)) · 随 \(LedgerMath.fmtMoney(cents: t.given))")
                                .font(.liqianMoney(.title3))
                                .foregroundStyle(Palette.ink)
                                .contentTransition(.numericText())
                        }
                    }
                }
            } header: {
                Text("按事由")
            }

            Section {
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
                                    .font(.subheadline.weight(.medium))
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
                                        .contentTransition(.numericText())
                                    Text(balanceSmallText(p))
                                        .font(.caption)
                                        .foregroundStyle(Palette.stone)
                                }
                                // Button 行不由系统提供披露箭头，手绘一枚是唯一允许的场景
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
            } header: {
                Text("往来排行")
            }

            Section {
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
                    .accessibilityLabel(relationAccessibilityText)
                }
            } header: {
                Text("关系分布")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("统计")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $personRoute) { route in
            PersonDetailView(name: route.name)
        }
    }

    private func summaryPair(label: String, cents: Int) -> some View {
        HStack(spacing: LiqianMetrics.spacingS) {
            Text(label)
                .foregroundStyle(Palette.stone)
            Text(LedgerMath.fmtMoney(cents: cents))
                .font(.liqianMoney(.title3, dark: colorScheme == .dark))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
        }
    }

    private func balanceSmallText(_ p: PersonSummary) -> String {
        if p.balance == 0 { return "已结清" }
        return p.balance > 0
            ? "对方多给 \(LedgerMath.fmtMoney(cents: p.balance))"
            : "我多给 \(LedgerMath.fmtMoney(cents: -p.balance))"
    }

    /// 关系分布图的 VoiceOver 等价物：逐关系读出总额（图本身读屏不可达）
    private var relationAccessibilityText: String {
        let parts = relationSummaries.map { "\($0.relation)往来总额 \(LedgerMath.fmtMoney(cents: $0.total))" }
        return "关系分布：" + parts.joined(separator: "；")
    }

    /// 单色阶透明度：最大总额为满色，其余按比例变淡（下限 0.35 保可读）
    private func opacity(of s: RelationSummary) -> Double {
        let maxTotal = relationSummaries.map(\.total).max() ?? 0
        guard maxTotal > 0 else { return 1 }
        return 0.35 + 0.65 * Double(s.total) / Double(maxTotal)
    }
}

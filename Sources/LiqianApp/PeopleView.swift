import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

struct PeopleView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @State private var query = ""
    @State private var personRoute: NameRoute?
    @State private var ledgerRoute: Ledger?

    /// 人物详情路由（按姓名）
    struct NameRoute: Identifiable, Hashable {
        let name: String
        var id: String { name }
    }

    private var summaries: [PersonSummary] {
        LedgerMath.people(from: AppSupport.snapshots(records: records, ledgers: ledgers))
    }

    /// 备礼清单数据源：全部待送出记录，按计划日期（记录 date）升序
    private var pendingSends: [GiftRecord] {
        records
            .filter { $0.isPendingSend }
            .sorted { $0.date < $1.date }
    }

    private var searching: Bool { !query.isEmpty }

    private var filteredPeople: [PersonSummary] {
        searching ? summaries.filter { $0.name.contains(query) } : summaries
    }

    private var filteredLedgers: [Ledger] {
        searching ? ledgers.filter { $0.title.contains(query) || $0.type.contains(query) } : []
    }

    var body: some View {
        NavigationStack {
            List {
                if !searching && !pendingSends.isEmpty {
                    prepListCard
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }

                if searching {
                    Section("人物") {
                        if filteredPeople.isEmpty {
                            emptyRow("没有叫这个名字的人")
                        } else {
                            ForEach(filteredPeople) { p in personRow(p) }
                        }
                    }
                    Section("礼簿") {
                        if filteredLedgers.isEmpty {
                            emptyRow("没有对得上的礼簿")
                        } else {
                            ForEach(filteredLedgers) { l in ledgerRow(l) }
                        }
                    }
                } else {
                    if summaries.isEmpty {
                        VStack(spacing: LiqianMetrics.spacingS) {
                            Text("还没有往来记录，先去礼簿里记一笔。")
                                .font(.system(size: 15))
                                .foregroundStyle(Palette.stone)
                            Button("生成示例数据，先看看效果") {
                                SampleData.generate(into: modelContext)
                            }
                            .foregroundStyle(Palette.primary)
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                        }
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .padding(.top, 32)
                    } else {
                        ForEach(summaries) { p in personRow(p) }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("人情往来")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, prompt: "搜姓名，或者搜礼簿、事由")
            .navigationDestination(item: $personRoute) { route in
                PersonDetailView(name: route.name)
            }
            .navigationDestination(item: $ledgerRoute) { ledger in
                LedgerDetailView(ledger: ledger)
            }
        }
    }

    /// 备礼清单卡：待送出的礼集中展示，点行进人物详情去处理
    private var prepListCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("备礼清单")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.ink)
            Text("记下了还没送出去的礼，送出后把那笔改成「已送出」。")
                .font(.system(size: 12))
                .foregroundStyle(Palette.stone)
                .padding(.bottom, 4)
            ForEach(pendingSends) { r in
                Button {
                    personRoute = NameRoute(name: r.person)
                } label: {
                    HStack(spacing: 8) {
                        Text(r.person)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer()
                        Text(r.date)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.stone)
                        Text(LedgerMath.fmtMoney(cents: r.amountCents))
                            .font(.liqianMoney(size: 15))
                            .foregroundStyle(Palette.ink)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.stone)
                    }
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(LiqianMetrics.cardPadding)
        .background(
            Palette.card,
            in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                .stroke(Palette.hairline, lineWidth: 1)
        )
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Palette.stone)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func personRow(_ p: PersonSummary) -> some View {
        Button {
            personRoute = NameRoute(name: p.name)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.name)
                        .foregroundStyle(Palette.ink)
                    Text("\(p.relation) · \(p.count) 笔 · 最近 \(p.lastDate)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.stone)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(balanceText(p))
                        .font(.liqianMoney(size: 15))
                        .foregroundStyle(Palette.ink)
                    if p.hasPending {
                        Text("还有 \(LedgerMath.fmtMoney(cents: p.pendingCents)) 没回")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.primary)
                    }
                }
            }
            .padding(12)
            .background(
                Palette.card,
                in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                    .stroke(Palette.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner))
        }
        .buttonStyle(ScaleOnPressButtonStyle())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    private func balanceText(_ p: PersonSummary) -> String {
        if p.balance == 0 { return "两清" }
        return p.balance > 0
            ? "他多给 \(LedgerMath.fmtMoney(cents: p.balance))"
            : "我多给 \(LedgerMath.fmtMoney(cents: -p.balance))"
    }

    private func ledgerRow(_ l: Ledger) -> some View {
        Button {
            ledgerRoute = l
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(l.isBai ? Palette.baiPrimary : Palette.primary)
                    Text(l.type.map { String($0) }.joined(separator: "\n"))
                        .font(.liqianSerif(size: 12))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(1)
                }
                .frame(width: 30, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(l.title)
                        .foregroundStyle(Palette.ink)
                    Text("\(l.type) · \(l.date)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.stone)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.stone)
            }
            .padding(12)
            .background(
                l.isBai ? Palette.baiCard : Palette.card,
                in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                    .stroke(l.isBai ? Palette.baiLine : Palette.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner))
        }
        .buttonStyle(ScaleOnPressButtonStyle())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}

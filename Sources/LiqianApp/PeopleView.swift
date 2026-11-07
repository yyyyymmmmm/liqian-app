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
    @State private var showSampleDone = false

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
                    Section {
                        ForEach(pendingSends) { r in prepRow(r) }
                    } header: {
                        Text("备礼清单")
                    } footer: {
                        Text("记下了还没送出去的礼，送出后把那笔改成「已送出」。")
                    }
                }

                if searching {
                    Section("亲友") {
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
                        Section {
                            ContentUnavailableView {
                                Label("还没有往来记录", systemImage: "person.2")
                            } description: {
                                Text("先去礼簿里记一笔。")
                            } actions: {
                                Button("生成示例数据") {
                                    if SampleData.generate(into: modelContext) {
                                        showSampleDone = true
                                    }
                                }
                                .foregroundStyle(Palette.primary)
                                .frame(minHeight: LiqianMetrics.minTapTarget)
                            }
                            .padding(.vertical, LiqianMetrics.spacingL)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    } else {
                        Section {
                            ForEach(summaries) { p in personRow(p) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("往来")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, prompt: "姓名、礼簿或事由")
            .navigationDestination(item: $personRoute) { route in
                PersonDetailView(name: route.name)
            }
            .navigationDestination(item: $ledgerRoute) { ledger in
                LedgerDetailView(ledger: ledger)
            }
            .alert("示例数据已生成", isPresented: $showSampleDone) {
                Button("好") {}
            } message: {
                Text("「礼簿」页多了两本示例礼簿，「往来」页能看到往来差额和备礼清单的效果。")
            }
        }
    }

    /// 备礼清单行：待送出的礼，点行进人物详情去处理
    private func prepRow(_ r: GiftRecord) -> some View {
        Button {
            personRoute = NameRoute(name: r.person)
        } label: {
            HStack(spacing: LiqianMetrics.spacingS) {
                Text(r.person)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer()
                Text(LiqianDate.displayString(for: r.date))
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
                Text(LedgerMath.fmtMoney(cents: r.amountCents))
                    .font(.liqianMoney(.title3))
                    .foregroundStyle(Palette.ink)
            }
            .frame(minHeight: LiqianMetrics.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Palette.stone)
    }

    private func personRow(_ p: PersonSummary) -> some View {
        Button {
            personRoute = NameRoute(name: p.name)
        } label: {
            HStack(spacing: LiqianMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                    Text(p.name)
                        .foregroundStyle(Palette.ink)
                    Text("\(p.relation) · \(p.count) 笔 · 最近 \(LiqianDate.displayString(for: p.lastDate))")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: LiqianMetrics.spacingXS) {
                    Text(balanceText(p))
                        .font(.liqianMoney(.title3))
                        .foregroundStyle(Palette.ink)
                    if p.hasPending {
                        Text("待回礼 \(LedgerMath.fmtMoney(cents: p.pendingCents))")
                            .font(.caption)
                            .foregroundStyle(Palette.primary)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func balanceText(_ p: PersonSummary) -> String {
        if p.balance == 0 { return "已结清" }
        return p.balance > 0
            ? "对方多给 \(LedgerMath.fmtMoney(cents: p.balance))"
            : "我多给 \(LedgerMath.fmtMoney(cents: -p.balance))"
    }

    private func ledgerRow(_ l: Ledger) -> some View {
        Button {
            ledgerRoute = l
        } label: {
            HStack(spacing: LiqianMetrics.spacingSM) {
                ZStack {
                    RoundedRectangle(cornerRadius: LiqianMetrics.tagCorner)
                        .fill(l.isBai ? Palette.baiPrimaryFill : Palette.primaryFill)
                    Text(l.type.map { String($0) }.joined(separator: "\n"))
                        .font(.liqianSerifFixed(size: 12))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(1)
                }
                .frame(width: 30, height: 44)
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                    Text(l.title)
                        .foregroundStyle(Palette.ink)
                    Text("\(l.type) · \(LiqianDate.displayString(for: l.date))")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.stone)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}

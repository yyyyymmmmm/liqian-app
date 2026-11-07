import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

struct PeopleView: View {
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
                Text("人情往来")
                    .font(.liqianBigTitle)
                    .foregroundStyle(Palette.ink)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

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
                        Text("还没有往来记录，先去礼簿里记一笔。")
                            .font(.system(size: 15))
                            .foregroundStyle(Palette.stone)
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
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜姓名，或者搜礼簿、事由")
            .navigationDestination(item: $personRoute) { route in
                PersonDetailView(name: route.name)
            }
            .navigationDestination(item: $ledgerRoute) { ledger in
                LedgerDetailView(ledger: ledger)
            }
        }
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
                        .foregroundStyle(p.balance > 0 ? Palette.primary : Palette.ink)
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

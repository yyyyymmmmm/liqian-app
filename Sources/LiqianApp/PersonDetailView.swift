import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 人物详情＝回礼决策页：顶部先给结论行，下方时间线（同 Flutter 版口径）
struct PersonDetailView: View {
    let name: String

    @Query private var allRecords: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @State private var formMode: FormMode?

    private enum FormMode: Identifiable {
        case create(direction: String)
        case edit(GiftRecord)

        var id: String {
            switch self {
            case .create(let d): return "create-\(d)"
            case .edit(let r): return "edit-\(r.id.uuidString)"
            }
        }
    }

    private var personRecords: [GiftRecord] {
        allRecords
            .filter { $0.person == name }
            .sorted { $0.date > $1.date }
    }

    private var received: Int {
        personRecords.filter { $0.direction == LiqianConstants.received }.reduce(0) { $0 + $1.amountCents }
    }

    private var given: Int {
        personRecords
            .filter { $0.direction == LiqianConstants.given && !$0.isPendingSend }
            .reduce(0) { $0 + $1.amountCents }
    }

    private var balance: Int { received - given }

    private var pending: Int {
        LedgerMath.people(from: AppSupport.snapshots(records: allRecords, ledgers: ledgers))
            .first { $0.name == name }?.pendingCents ?? 0
    }

    private func ledger(of r: GiftRecord) -> Ledger? {
        ledgers.first { $0.id == r.ledgerID }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerCard
                if personRecords.isEmpty {
                    Text("还没有往来记录")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.stone)
                        .padding(.top, 32)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(personRecords) { r in
                            timelineRow(r)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        formMode = .create(direction: LiqianConstants.received)
                    } label: {
                        Label("记一笔收礼", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Palette.primary)

                    Button {
                        formMode = .create(direction: LiqianConstants.given)
                    } label: {
                        Label("记一笔随礼", systemImage: "arrow.up.circle")
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                    }
                    .buttonStyle(.glass)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .sheet(item: $formMode) { mode in
            switch mode {
            case .create(let direction):
                RecordFormView(personName: name, presetDirection: direction)
            case .edit(let record):
                RecordFormView(existing: record)
            }
        }
    }

    private var headerCard: some View {
        VStack(spacing: 0) {
            HStack {
                headerStat(label: "他给我的", value: received)
                Spacer()
                headerStat(label: "我给他的", value: given)
            }
            Divider()
                .overlay(Palette.hairline)
                .padding(.vertical, 12)
            Text(conclusion)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.ink)
            if pending > 0 {
                Text("其中 \(LedgerMath.fmtMoney(cents: pending)) 是最近收下、还没回的")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.primary)
                    .padding(.top, 4)
            }
        }
        .padding(LiqianMetrics.cardPadding)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner))
        .overlay(
            RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                .stroke(Palette.hairline, lineWidth: 1)
        )
    }

    private func headerStat(label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text(LedgerMath.fmtMoney(cents: value))
                .font(.liqianSerif(size: 18))
                .foregroundStyle(Palette.ink)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Palette.stone)
        }
        .frame(maxWidth: .infinity)
    }

    private var conclusion: String {
        if balance == 0 { return "往来两清" }
        return balance > 0
            ? "他多给 \(LedgerMath.fmtMoney(cents: balance))，下次他办事记得回"
            : "我多给 \(LedgerMath.fmtMoney(cents: -balance))"
    }

    private func timelineRow(_ r: GiftRecord) -> some View {
        let l = ledger(of: r)
        let isBai = l?.isBai ?? false
        return Button {
            formMode = .edit(r)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("\(l?.title ?? "")（\(l?.type ?? "")）")
                            .foregroundStyle(isBai ? Palette.baiInk : Palette.ink)
                            .lineLimit(1)
                        DirectionTag(direction: r.direction, bai: isBai)
                        if r.isPendingSend {
                            PendingTag(bai: isBai)
                        }
                    }
                    Text(subtitle(of: r))
                        .font(.system(size: 12.5))
                        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                }
                Spacer()
                Text("\(r.direction == LiqianConstants.received ? "+" : "-")\(LedgerMath.fmtMoney(cents: r.amountCents))")
                    .font(.liqianMoney(size: 16))
                    .foregroundStyle(
                        r.direction == LiqianConstants.received
                            ? (isBai ? Palette.baiInk : Palette.primary)
                            : Palette.ink
                    )
            }
            .padding(12)
            .background(
                isBai ? Palette.baiCard : Palette.card,
                in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                    .stroke(isBai ? Palette.baiLine : Palette.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner))
        }
        .buttonStyle(ScaleOnPressButtonStyle())
    }

    private func subtitle(of r: GiftRecord) -> String {
        var s = "\(r.date) · \(r.method)"
        if !r.note.isEmpty { s += " · \(r.note)" }
        return s
    }
}

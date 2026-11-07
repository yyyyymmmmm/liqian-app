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

    /// 回礼参考区间：只用与这个人的历史往来算，没收过他的礼就不给（Core 纯函数）
    private var suggestion: ReturnGiftSuggestion? {
        LedgerMath.returnGiftSuggestion(
            from: AppSupport.snapshots(records: allRecords, ledgers: ledgers),
            person: name,
            today: LiqianDate.todayString()
        )
    }

    private func ledger(of r: GiftRecord) -> Ledger? {
        ledgers.first { $0.id == r.ledgerID }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: LiqianMetrics.spacingSM) {
                headerCard
                if let suggestion {
                    suggestionCard(suggestion)
                }
                if personRecords.isEmpty {
                    Text("还没有往来记录")
                        .font(.body)
                        .foregroundStyle(Palette.stone)
                        .padding(.top, LiqianMetrics.spacingXL)
                } else {
                    LazyVStack(spacing: LiqianMetrics.spacingS) {
                        ForEach(personRecords) { r in
                            timelineRow(r)
                        }
                    }
                }
            }
            .padding(LiqianMetrics.spacingM)
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            GlassEffectContainer(spacing: LiqianMetrics.spacingSM) {
                HStack(spacing: LiqianMetrics.spacingSM) {
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
                .padding(.horizontal, LiqianMetrics.spacingM)
                .padding(.vertical, LiqianMetrics.spacingS)
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
                headerStat(label: "收礼合计", value: received)
                Spacer()
                headerStat(label: "随礼合计", value: given)
            }
            Divider()
                .overlay(Palette.hairline)
                .padding(.vertical, LiqianMetrics.spacingSM)
            Text(conclusion)
                .font(.body.weight(.bold))
                .foregroundStyle(Palette.ink)
            if pending > 0 {
                Text("其中 \(LedgerMath.fmtMoney(cents: pending)) 待回礼")
                    .font(.footnote)
                    .foregroundStyle(Palette.primary)
                    .padding(.top, LiqianMetrics.spacingXS)
            }
        }
        .padding(LiqianMetrics.cardPadding)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner))
        .overlay(
            RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                .stroke(Palette.hairline, lineWidth: 1)
        )
    }

    private func suggestionCard(_ s: ReturnGiftSuggestion) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("回礼参考")
                .font(.headline.weight(.bold))
                .foregroundStyle(Palette.ink)
            Text(suggestionText(s))
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(LiqianMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner))
        .overlay(
            RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                .stroke(Palette.hairline, lineWidth: 1)
        )
    }

    private func suggestionText(_ s: ReturnGiftSuggestion) -> String {
        let year = String(s.lastDate.prefix(4))
        let typePart = s.lastType.isEmpty ? "" : " · \(s.lastType)"
        var text = "上次 \(name) 随你 \(LedgerMath.fmtMoney(cents: s.lastAmountCents))"
        text += "（\(year) 年\(typePart)），对等略添的参考区间 "
        text += "\(LedgerMath.fmtMoney(cents: s.lowerCents))–\(LedgerMath.fmtMoney(cents: s.upperCents))，"
        text += "仅供参考，量力而行。"
        return text
    }

    private func headerStat(label: String, value: Int) -> some View {
        VStack(spacing: LiqianMetrics.spacingXS) {
            Text(LedgerMath.fmtMoney(cents: value))
                .font(.liqianSerif(.title3))
                .foregroundStyle(Palette.ink)
            Text(label)
                .font(.footnote)
                .foregroundStyle(Palette.stone)
        }
        .frame(maxWidth: .infinity)
    }

    private var conclusion: String {
        if balance == 0 { return "已结清" }
        return balance > 0
            ? "对方多给 \(LedgerMath.fmtMoney(cents: balance))，下次对方办事记得回"
            : "我多给 \(LedgerMath.fmtMoney(cents: -balance))"
    }

    private func timelineRow(_ r: GiftRecord) -> some View {
        let l = ledger(of: r)
        let isBai = l?.isBai ?? false
        return Button {
            formMode = .edit(r)
        } label: {
            HStack(spacing: LiqianMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                    HStack(spacing: LiqianMetrics.spacingS) {
                        Text("\(l?.title ?? "")（\(l?.type ?? "")）")
                            .foregroundStyle(isBai ? Palette.baiInk : Palette.ink)
                            .lineLimit(1)
                        DirectionTag(direction: r.direction, bai: isBai)
                        if r.isPendingSend {
                            PendingTag(bai: isBai)
                        }
                    }
                    Text(subtitle(of: r))
                        .font(.footnote)
                        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                }
                Spacer()
                Text("\(r.direction == LiqianConstants.received ? "+" : "-")\(LedgerMath.fmtMoney(cents: r.amountCents))")
                    .font(.liqianMoney(.title3))
                    .foregroundStyle(isBai ? Palette.baiInk : Palette.ink)
            }
            .padding(LiqianMetrics.spacingSM)
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
        var s = "\(LiqianDate.displayString(for: r.date)) · \(r.method)"
        if !r.note.isEmpty { s += " · \(r.note)" }
        return s
    }
}

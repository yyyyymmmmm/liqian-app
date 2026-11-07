import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 人物详情＝回礼决策页：顶部先给结论行，下方时间线（同 Flutter 版口径）
struct PersonDetailView: View {
    let name: String

    @Environment(\.modelContext) private var modelContext
    @Query private var allRecords: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @Query private var allReminderDays: [ReminderDay]
    @State private var formMode: FormMode?
    // 活礼谱（v4.2）：时间线行长按的两个动作目标
    @State private var signatureRecord: GiftRecord?
    @State private var blessingRecord: GiftRecord?

    /// 这个人的重要日子（同名对齐，与全 App 人名口径一致），按下一次临近排序
    private var personDays: [ReminderDay] {
        allReminderDays
            .filter { $0.person == name }
            .sorted {
                ReminderMath.nextOccurrence(
                    calendarKind: $0.calendarKind, month: $0.month, day: $0.day, from: Date()
                ) < ReminderMath.nextOccurrence(
                    calendarKind: $1.calendarKind, month: $1.month, day: $1.day, from: Date()
                )
            }
    }

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
                if !personDays.isEmpty {
                    reminderDaysCard
                }
                if let suggestion {
                    suggestionCard(suggestion)
                }
                if personRecords.isEmpty {
                    ContentUnavailableView {
                        Label("还没有往来记录", systemImage: "person.crop.circle")
                    } description: {
                        Text("与这位亲友的往来会记在这里。")
                    }
                    .padding(.top, LiqianMetrics.spacingXL)
                } else {
                    // 时间线＝单张分组容器：一张卡内 hairline 分隔的行列，不再每笔一张浮卡
                    VStack(spacing: 0) {
                        ForEach(Array(personRecords.enumerated()), id: \.element.id) { idx, r in
                            if idx > 0 {
                                Divider()
                                    .overlay(Palette.hairline)
                                    .padding(.leading, LiqianMetrics.spacingM)
                            }
                            timelineRow(r)
                                // 活礼谱（v4.2）：长按一笔 → 签名/语音祝福
                                .contextMenu {
                                    Button {
                                        signatureRecord = r
                                    } label: {
                                        Label("请来宾签名", systemImage: "signature")
                                    }
                                    Button {
                                        blessingRecord = r
                                    } label: {
                                        Label("语音祝福", systemImage: "waveform")
                                    }
                                }
                        }
                    }
                    .liqianCardSurface(padding: 0)
                }
            }
            .padding(LiqianMetrics.spacingM)
        }
        .background(Palette.groupedBackground.ignoresSafeArea())
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        // v2.5 包 4：不再隐藏 Tab 栏（pop 补显动画慢半拍）；底部双按钮是
        // safeAreaInset，自动落在 Tab 栏上方，不会被遮挡。
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
        .sheet(item: $signatureRecord) { record in
            SignatureCaptureView(person: record.person) { png in
                modelContext.insert(
                    GuestSignature(
                        ledgerID: record.ledgerID, recordID: record.id,
                        person: record.person, imageData: png
                    )
                )
                try? modelContext.save()
            }
        }
        .sheet(item: $blessingRecord) { record in
            RecordBlessingsView(record: record)
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
        .liqianCardSurface()
    }

    /// 重要日子只读区（v3.0）：只展示这个人的日子与下一次时间，
    /// 编辑走「管理提醒」进人情提醒页，不在本页改数据。
    private var reminderDaysCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("重要日子")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            ForEach(personDays) { day in
                let occurrence = ReminderMath.nextOccurrence(
                    calendarKind: day.calendarKind, month: day.month, day: day.day, from: Date()
                )
                let n = ReminderMath.daysUntil(occurrence, from: Date())
                HStack(spacing: LiqianMetrics.spacingS) {
                    Text(day.kind)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(ReminderMath.dateNote(calendarKind: day.calendarKind, occurrence: occurrence)) · \(n == 0 ? "就是今天" : "还有 \(n) 天")")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                    if !day.enabled {
                        Text("已停用")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                    }
                }
            }
            NavigationLink {
                RemindersView()
            } label: {
                Label("管理提醒", systemImage: "bell")
                    .font(.subheadline)
            }
            .tint(Palette.primary)
        }
        .liqianCardSurface()
    }

    private func suggestionCard(_ s: ReturnGiftSuggestion) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("回礼参考")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text(suggestionText(s))
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .liqianCardSurface()
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
                .font(.liqianMoney(.title3))
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
            .padding(.horizontal, LiqianMetrics.spacingM)
            .padding(.vertical, LiqianMetrics.spacingSM)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(of r: GiftRecord) -> String {
        var s = "\(LiqianDate.displayString(for: r.date)) · \(r.method)"
        if !r.note.isEmpty { s += " · \(r.note)" }
        return s
    }
}

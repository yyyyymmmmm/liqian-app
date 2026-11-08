import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 人物详情＝回礼决策页：顶部先给结论行，下方时间线（同 Flutter 版口径）
struct PersonDetailView: View {
    let name: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var allRecords: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @Query private var allReminderDays: [ReminderDay]
    @State private var formMode: FormMode?
    // 活礼谱（v4.2）：时间线行长按的两个动作目标
    @State private var signatureRecord: GiftRecord?
    @State private var blessingRecord: GiftRecord?
    /// 长按菜单删除（v4.4）：与礼簿详情页同款确认＋同款归档口径
    @State private var recordToDelete: GiftRecord?
    @State private var deleteTrigger = 0

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

    /// 回礼参考年涨幅设置（「我的 → 记录」里可改 0/3/5%）
    @AppStorage(ReplyAdvisor.annualRateKey) private var annualRatePercent = ReplyAdvisor.defaultAnnualRatePercent

    /// 回礼建议（v4.3 区间模型）：锚×年涨幅×场合系数×红白取整＋理由。
    /// 本页没有具体场合，场合取锚所属事由（按上次的场合估）；没收过他的礼
    /// 时 advice 为 nil，卡片出回退文案而不是消失。
    private var advice: ReplyAdvice? {
        ReplyAdvisor.advice(
            from: AppSupport.snapshots(records: allRecords, ledgers: ledgers),
            person: name,
            occasionType: anchorOccasionType,
            today: LiqianDate.todayString(),
            annualRatePercent: annualRatePercent
        )
    }

    /// 锚所属事由：这个人最近一笔收礼所在礼簿的类型（personRecords 已按日期倒序）
    private var anchorOccasionType: String {
        guard let latest = personRecords.first(where: { $0.direction == LiqianConstants.received }) else {
            return ""
        }
        return ledger(of: latest)?.type ?? ""
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
                suggestionCard
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
                                // 长按菜单四动作（v4.4 与礼簿详情页同口径同序）：
                                // 编辑（与点行同效）/签名/语音祝福/删除（垫底标红）
                                .contextMenu {
                                    Button {
                                        formMode = .edit(r)
                                    } label: {
                                        Label("编辑", systemImage: "pencil")
                                    }
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
                                    Divider()
                                    Button(role: .destructive) {
                                        recordToDelete = r
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .liqianCardSurface(padding: 0)
                    // 时间线行增删动画（v4.4）
                    .animation(reduceMotion ? nil : .snappy, value: personRecords.map(\.id))
                }
            }
            .padding(LiqianMetrics.spacingM)
        }
        .background(Palette.groupedBackground.ignoresSafeArea())
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        // v2.5 包 4：不再隐藏 Tab 栏（pop 补显动画慢半拍）；底部双按钮
        // 自动落在 Tab 栏上方，不会被遮挡。
        // v5 设计一期：safeAreaInset → safeAreaBar（审计采用清单）——
        // 内容可滚至行动条之下由系统出滚动边缘效果，玻璃按钮形态不变。
        .safeAreaBar(edge: .bottom) {
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
        .alert(
            "删除这笔记录？",
            isPresented: Binding(
                get: { recordToDelete != nil },
                set: { if !$0 { recordToDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let r = recordToDelete { deleteRecord(r) }
                recordToDelete = nil
            }
            Button("取消", role: .cancel) { recordToDelete = nil }
        } message: {
            Text("删除后 30 天内可以在「我的 → 最近删除」恢复。")
        }
        .sensoryFeedback(.warning, trigger: deleteTrigger)
    }

    /// 删一笔：与礼簿详情页同语义——快照进最近删除，30 天可恢复
    private func deleteRecord(_ r: GiftRecord) {
        TrashStore.archive(record: r)
        modelContext.delete(r)
        try? modelContext.save()
        deleteTrigger += 1
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
                .contentTransition(.numericText())
            if pending > 0 {
                Text("其中 \(LedgerMath.fmtMoney(cents: pending)) 待回礼")
                    .font(.footnote)
                    .foregroundStyle(Palette.primary)
                    .padding(.top, LiqianMetrics.spacingXS)
                    .contentTransition(.numericText())
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

    /// 回礼参考卡（v4.3）：有依据出区间＋建议值＋理由逐行；
    /// 没收过他的礼（advice == nil）出回退文案，不瞎给数
    private var suggestionCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("回礼参考")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            if let a = advice {
                HStack(alignment: .firstTextBaseline, spacing: LiqianMetrics.spacingS) {
                    Text("\(LedgerMath.fmtMoney(cents: a.lowerCents)) – \(LedgerMath.fmtMoney(cents: a.upperCents))")
                        .font(.liqianMoney(.title3))
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                    Text("可参考 \(LedgerMath.fmtMoney(cents: a.suggestedCents))")
                        .font(.subheadline)
                        .foregroundStyle(Palette.primary)
                        .contentTransition(.numericText())
                }
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                    ForEach(a.reasons, id: \.self) { reason in
                        Text("· \(reason)")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                    }
                }
                Text("只是按你和 \(name) 的往来记录算的，仅供参考，量力而行。")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            } else {
                Text("还没收过 \(name) 的礼，没有可参考的往来记录。下次他办事，按当地通常的份量和你们的关系拿捏即可。")
                    .font(.subheadline)
                    .foregroundStyle(Palette.stone)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .liqianCardSurface()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerStat(label: String, value: Int) -> some View {
        VStack(spacing: LiqianMetrics.spacingXS) {
            Text(LedgerMath.fmtMoney(cents: value))
                .font(.liqianMoney(.title3))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy, value: value)
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
                SignedMoneyText(cents: r.amountCents, direction: r.direction, bai: isBai)
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

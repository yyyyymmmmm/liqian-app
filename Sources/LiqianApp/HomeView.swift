import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 首页＝总览台（v4.7 重规划，替代原「礼簿列表当首页」）：自上而下——
/// 下一个重要日子倒计时 → 待回礼 → 本月往来 → 快捷动作 → 最近动态 →
/// 我的礼簿（原 LedgersView 的礼簿列表能力完整下沉到本页下半区）→
/// 礼谱成书旗舰卡（v5.11：常驻弱位在礼簿段下方；某本礼簿到了成书
/// 时机时升位到礼簿段顶部）。右下 FAB 自 v5.11 起是「记一笔」
/// （用户批准），新建礼簿在礼簿段头。
/// 数据口径与全 App 一致：AppSupport.snapshots + 示例礼簿隔离
/// （SampleData.sampleIDs），待回 = max(balance, 0)，金额 fmtMoney。
/// 跨 Tab 跳转只走 ContentView 既有通道：待回人物经 personDeepLinkName
/// 绑定切往来 Tab（与 liqian://person 深链同一条路），本月卡经
/// tabSelection 绑定切图表 Tab，不新造跳转机制。
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @Query private var records: [GiftRecord]
    @Query private var allMembers: [LedgerMember]
    @Query private var allReminderDays: [ReminderDay]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// 待回人物待达姓名（ContentView 持有，PeopleView 消费），与深链同绑定
    @Binding private var deepLinkPerson: String?
    /// Tab 选择（ContentView 持有）：本月卡 → 图表(2)，待回行 → 往来(1)
    @Binding private var tabSelection: Int

    init(deepLinkPerson: Binding<String?>, tabSelection: Binding<Int>) {
        _deepLinkPerson = deepLinkPerson
        _tabSelection = tabSelection
    }

    @State private var personRoute: PeopleView.NameRoute?
    @State private var ledgerRoute: Ledger?
    @State private var showNewLedger = false
    @State private var editingLedger: Ledger?
    @State private var ledgerToDelete: Ledger?
    @State private var deleteTrigger = 0
    @State private var showSampleDone = false
    @State private var showQuickRecord = false
    @State private var batchTarget: Ledger?
    @State private var ocrTarget: Ledger?
    @State private var showAdvisor = false
    @State private var actionResultText = ""
    @State private var showActionResult = false
    @Namespace private var zoomSpace

    // MARK: - 数据口径（同 LedgersView/ChartsView）

    private var sampleIDs: Set<UUID> { SampleData.sampleIDs(ledgers: ledgers) }

    private var statRecords: [GiftRecord] {
        let ids = sampleIDs
        return records.filter { !ids.contains($0.ledgerID) }
    }

    private var snapshots: [EntrySnapshot] {
        AppSupport.snapshots(records: statRecords, ledgers: ledgers)
    }

    private var pendingPeople: [PersonSummary] {
        LedgerMath.people(from: snapshots).filter { $0.hasPending }
            .sorted { $0.pendingCents > $1.pendingCents }
    }

    private var pendingTotal: Int {
        pendingPeople.reduce(0) { $0 + $1.pendingCents }
    }

    /// 下一个重要日子：与小组件速览同源（WidgetSummaryWriter.nextReminder）
    private var nextReminder: WidgetSummaryWriter.NextReminder? {
        WidgetSummaryWriter.nextReminder(from: allReminderDays.map(\.value))
    }

    /// 距下一次 occurrence 的整天数（occurrence 为当天 0 点；今天即 0）
    private func daysUntil(_ occurrence: Date) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return cal.dateComponents([.day], from: today, to: cal.startOfDay(for: occurrence)).day ?? 0
    }

    /// 本月往来（记录 date 前缀匹配当前年月；待送出不计金额/笔数，同全 App 口径）
    private var monthRecords: [GiftRecord] {
        let prefix = String(LiqianDate.todayString().prefix(7))
        return statRecords.filter { $0.date.hasPrefix(prefix) && !$0.isPendingSend }
    }

    private var monthReceived: Int {
        monthRecords.filter { $0.direction == LiqianConstants.received }
            .reduce(0) { $0 + $1.amountCents }
    }

    private var monthGiven: Int {
        monthRecords.filter { $0.direction == LiqianConstants.given }
            .reduce(0) { $0 + $1.amountCents }
    }

    /// 最近动态：跨礼簿最近 8 笔（示例记录不入，同旧速览口径）
    private var recentRecords: [GiftRecord] {
        Array(statRecords.sorted { $0.date > $1.date }.prefix(8))
    }

    private func ledger(of r: GiftRecord) -> Ledger? {
        ledgers.first { $0.id == r.ledgerID }
    }

    /// 批量录入/拍礼簿的目标礼簿：日期最新的一本非示例礼簿（ledgers 已按
    /// 日期倒序）；没有时两个入口禁用（记一笔/问管家不受影响）
    private var actionTargetLedger: Ledger? {
        ledgers.first { !sampleIDs.contains($0.id) }
    }

    /// 卡片行口径（同 LedgersView）：行透明无分隔、卡片自带表面，
    /// 行上下各 6pt 拼出卡间距 12，两侧与页面边距一致。
    private var cardRowInsets: EdgeInsets {
        EdgeInsets(
            top: 6, leading: LiqianMetrics.spacingM,
            bottom: 6, trailing: LiqianMetrics.spacingM
        )
    }

    private var plainRow: some ViewModifier {
        PlainCardRow(insets: cardRowInsets)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let next = nextReminder {
                        countdownCard(next)
                            .modifier(plainRow)
                    }
                    if !pendingPeople.isEmpty {
                        pendingCard
                            .modifier(plainRow)
                    }
                    if !monthRecords.isEmpty {
                        monthCard
                            .modifier(plainRow)
                    }
                    quickActionsCard
                        .modifier(plainRow)
                    if !recentRecords.isEmpty {
                        recentCard
                            .modifier(plainRow)
                    }
                }
                Section {
                    if ledgers.isEmpty {
                        emptyState
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
                        // 事件驱动升位（v5.11）：有礼簿到了成书时机，
                        // 旗舰卡升到礼簿段顶部（常驻位在段下方，见下）
                        if let promoted = promotedBookLedger {
                            bookFlagshipCard(ledger: promoted, promoted: true)
                                .modifier(plainRow)
                        }
                        ForEach(ledgers) { ledger in
                            Button {
                                ledgerRoute = ledger
                            } label: {
                                LedgerCoverCard(
                                    ledger: ledger,
                                    receivedCents: received(of: ledger),
                                    givenCents: given(of: ledger),
                                    count: count(of: ledger)
                                )
                                .matchedTransitionSource(id: ledger.id, in: zoomSpace)
                            }
                            .buttonStyle(ScaleOnPressButtonStyle())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(cardRowInsets)
                            // 左滑：编辑／删除（与原礼簿页同路径，删除进最近删除）
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    ledgerToDelete = ledger
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    editingLedger = ledger
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                            }
                        }
                    }
                } header: {
                    if !ledgers.isEmpty {
                        HStack {
                            Text("我的礼簿")
                            Spacer()
                            // 新建礼簿入口（v5.11）：FAB 让位给记一笔后收进段头
                            Button {
                                showNewLedger = true
                            } label: {
                                Label("新建礼簿", systemImage: "plus")
                                    .font(.footnote.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Palette.primary)
                        }
                    }
                }
                // 礼谱成书旗舰卡常驻席位（v5.11）：固定在礼簿段下方，
                // 不置顶不抢记账注意力；有升位对象时本卡不出（已升到段顶）
                if promotedBookLedger == nil, let target = flagshipBookLedger {
                    Section {
                        bookFlagshipCard(ledger: target, promoted: false)
                            .modifier(plainRow)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.pageBG.ignoresSafeArea())
            .contentMargins(.bottom, 72, for: .scrollContent)
            .animation(reduceMotion ? nil : .snappy, value: ledgers.count)
            .animation(reduceMotion ? nil : .snappy, value: statRecords.count)
            .navigationTitle("首页")
            .navigationBarTitleDisplayMode(.large)
            // FAB 换「记一笔」（v5.11，用户批准）：最高频动作占浮动位，
            // 默认礼簿由 RecordFormView 内的 DefaultLedgerPicker 决定
            // （上次使用优先）；新建礼簿收进「我的礼簿」段头入口。
            .overlay(alignment: .bottomTrailing) {
                AddFloatingButton(label: "记一笔", bottomPadding: AddFloatingButton.tabBarClearance) {
                    showQuickRecord = true
                }
            }
            .navigationDestination(item: $personRoute) { route in
                PersonDetailView(name: route.name)
            }
            .navigationDestination(item: $ledgerRoute) { ledger in
                LedgerDetailView(ledger: ledger)
                    .navigationTransition(.zoom(sourceID: ledger.id, in: zoomSpace))
            }
            .sheet(isPresented: $showNewLedger) {
                LedgerFormView()
            }
            .sheet(item: $editingLedger) { ledger in
                LedgerFormView(existing: ledger)
            }
            .sheet(isPresented: $showQuickRecord) {
                RecordFormView(personName: "", presetDirection: LiqianConstants.received)
            }
            .sheet(item: $batchTarget) { ledger in
                BatchEntryView(ledger: ledger) { n in
                    actionResultText = "共记 \(n) 笔"
                    showActionResult = true
                }
            }
            .sheet(item: $ocrTarget) { ledger in
                PhotoOCRView(ledger: ledger) { n in
                    actionResultText = "共导入 \(n) 笔收礼"
                    showActionResult = true
                }
            }
            .sheet(isPresented: $showAdvisor) {
                AdvisorView()
            }
            .alert("完成", isPresented: $showActionResult) {
                Button("好") {}
            } message: {
                Text(actionResultText)
            }
            .confirmationDialog(
                "删除这本礼簿？",
                isPresented: Binding(
                    get: { ledgerToDelete != nil },
                    set: { if !$0 { ledgerToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let l = ledgerToDelete { deleteLedger(l) }
                    ledgerToDelete = nil
                }
                Button("取消", role: .cancel) { ledgerToDelete = nil }
            } message: {
                Text("礼簿里的记录会一并删除，30 天内可以在「我的 → 最近删除」恢复。")
            }
            .sensoryFeedback(.warning, trigger: deleteTrigger)
            .alert("示例数据已生成", isPresented: $showSampleDone) {
                Button("好") {}
            } message: {
                Text("首页多了两本示例礼簿，「往来」页能看到往来差额和备礼清单的效果。")
            }
        }
    }

    /// 侧滑删除礼簿：与详情页删除同语义——整簿快照进最近删除，30 天可恢复
    private func deleteLedger(_ ledger: Ledger) {
        let rs = records.filter { $0.ledgerID == ledger.id }
        let ms = allMembers.filter { $0.ledgerID == ledger.id }
        TrashStore.archive(ledger: ledger, records: rs, members: ms)
        for r in rs {
            modelContext.delete(r)
        }
        for m in ms {
            modelContext.delete(m)
        }
        modelContext.delete(ledger)
        try? modelContext.save()
        deleteTrigger += 1
    }

    // MARK: - 倒计时卡

    private func countdownCard(_ next: WidgetSummaryWriter.NextReminder) -> some View {
        let days = daysUntil(next.occurrence)
        return HStack(spacing: LiqianMetrics.spacingSM) {
            Image(systemName: "calendar.badge.clock")
                .font(.title2)
                .foregroundStyle(Palette.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                Text(next.title)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(LiqianDate.displayString(for: LiqianDate.string(from: next.occurrence)))
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            }
            Spacer()
            VStack(spacing: 0) {
                if days == 0 {
                    Text("就是今天")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Palette.primary)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(days)")
                            .font(.liqianMoney(.largeTitle, dark: colorScheme == .dark))
                            .foregroundStyle(Palette.primary)
                        Text("天后")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                    }
                }
            }
        }
        .liqianCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            days == 0
                ? "\(next.title)，就是今天"
                : "\(next.title)，还有 \(days) 天，\(LiqianDate.displayString(for: LiqianDate.string(from: next.occurrence)))"
        )
    }

    // MARK: - 待回礼卡

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
            HStack {
                Text("待回礼")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("共 \(pendingPeople.count) 人 · \(LedgerMath.fmtMoney(cents: pendingTotal))")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
                    .contentTransition(.numericText())
            }
            .padding(.bottom, LiqianMetrics.spacingXS)
            ForEach(pendingPeople.prefix(3)) { p in
                Button {
                    // 经 ContentView 既有深链通道：在往来页打开该人物
                    // （顺序与 onOpenURL 的 person 深链一致：先切 Tab 再置名）
                    tabSelection = 1
                    deepLinkPerson = p.name
                } label: {
                    HStack {
                        Text(p.name)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(LedgerMath.fmtMoney(cents: p.pendingCents))
                            .font(.liqianMoney(.title3))
                            .foregroundStyle(Palette.primary)
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
            if pendingPeople.count > 3 {
                Text("还有 \(pendingPeople.count - 3) 人待回礼，去「往来」页看全部。")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
                    .padding(.top, LiqianMetrics.spacingXS)
            }
        }
        .liqianCardSurface()
    }

    // MARK: - 本月往来卡（点卡进图表 Tab）

    private var monthCard: some View {
        Button {
            tabSelection = 2
        } label: {
            VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
                HStack {
                    Text("本月往来")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("看图表")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Palette.stone)
                        .accessibilityHidden(true)
                }
                // v5.3.2 统计格定版：三栏等分居中（旧内容宽 HStack
                // 前挤后散被用户圈图点名）
                StatRow {
                    StatCell(label: "收礼", value: LedgerMath.fmtMoney(cents: monthReceived))
                    StatCell(label: "随礼", value: LedgerMath.fmtMoney(cents: monthGiven))
                    StatCell(label: "本月笔数", value: "\(monthRecords.count)", unit: "笔")
                }
            }
            .liqianCardSurface()
        }
        // 整卡可点也要有按压反馈（与礼簿行 ScaleOnPress 同口径，不用 .plain 裸跳）
        .buttonStyle(ScaleOnPressButtonStyle())
    }

    // MARK: - 快捷动作

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            HStack(spacing: LiqianMetrics.spacingS) {
                quickAction(
                    icon: "square.and.pencil", label: "记一笔",
                    enabled: true
                ) {
                    showQuickRecord = true
                }
                quickAction(
                    icon: "list.bullet.rectangle", label: "批量录入",
                    enabled: actionTargetLedger != nil
                ) {
                    batchTarget = actionTargetLedger
                }
                quickAction(
                    icon: "text.viewfinder", label: "拍礼簿",
                    enabled: actionTargetLedger != nil
                ) {
                    ocrTarget = actionTargetLedger
                }
                quickAction(
                    icon: "sparkles", label: "问管家",
                    enabled: true
                ) {
                    showAdvisor = true
                }
            }
            if actionTargetLedger == nil {
                Text("批量录入与拍礼簿需要先有一本自己的礼簿（示例礼簿不作目标）。")
                    .font(.caption)
                    .foregroundStyle(Palette.stone)
            }
        }
        .liqianCardSurface()
    }

    private func quickAction(
        icon: String, label: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: LiqianMetrics.spacingXS) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(enabled ? Palette.primary : Palette.stone.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .background(
                        (enabled ? Palette.primary : Palette.stone).opacity(0.10),
                        in: Circle()
                    )
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(enabled ? Palette.ink : Palette.stone)
            }
            .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScaleOnPressButtonStyle())
        .disabled(!enabled)
    }

    // MARK: - 最近动态

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
            Text("最近动态")
                .font(.headline.weight(.bold))
                .foregroundStyle(Palette.ink)
                .padding(.bottom, LiqianMetrics.spacingXS)
            ForEach(recentRecords) { r in
                Button {
                    personRoute = PeopleView.NameRoute(name: r.person)
                } label: {
                    HStack(spacing: LiqianMetrics.spacingS) {
                        DirectionTag(direction: r.direction, bai: ledger(of: r)?.isBai ?? false)
                        Text(r.person)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text(ledger(of: r)?.title ?? "")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                            .lineLimit(1)
                        Spacer()
                        Text(LiqianDate.displayString(for: r.date))
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                        SignedMoneyText(
                            cents: r.amountCents,
                            direction: r.direction,
                            bai: ledger(of: r)?.isBai ?? false
                        )
                    }
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .liqianCardSurface()
    }

    // MARK: - 空态

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有礼簿", systemImage: "book.closed")
        } description: {
            Text("从最近一场事开始记。")
        } actions: {
            Button("新建第一本礼簿") {
                showNewLedger = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.primaryFill)
            .frame(minHeight: LiqianMetrics.minTapTarget)
            Button("生成示例数据") {
                if SampleData.generate(into: modelContext) {
                    showSampleDone = true
                }
            }
            .foregroundStyle(Palette.stone)
            .frame(minHeight: LiqianMetrics.minTapTarget)
        }
        .padding(.top, 48)
    }

    // MARK: - 礼谱成书旗舰卡（v5.11：常驻弱位＋事件驱动升位）

    /// 成书升位门槛（成册口径笔数）：20 笔是一场小场次（家宴/满月）
    /// 能成册的下限——再少印出来是几页纸、不成「书」。笔数口径与
    /// LibuExportView 的 countedCount 一致：排除待送出。
    private static let bookPromotionMinCount = 20

    private func countedCount(of ledger: Ledger) -> Int {
        records.filter { $0.ledgerID == ledger.id && !$0.isPendingSend }.count
    }

    /// 升位对象：非示例礼簿中，场次日期已过（ledger.date < 今天）且
    /// 成册笔数达标者，取笔数最多的一本（ledgers 已按日期倒序，
    /// 同笔数时 max 取先到者＝日期较近的一本）。
    private var promotedBookLedger: Ledger? {
        let today = LiqianDate.todayString()
        return ledgers
            .filter {
                !sampleIDs.contains($0.id) && $0.date < today
                    && countedCount(of: $0) >= Self.bookPromotionMinCount
            }
            .max { countedCount(of: $0) < countedCount(of: $1) }
    }

    /// 常驻旗舰卡的落点：最近一本非示例礼簿（点卡进其详情，导出→
    /// 装订成书在详情内）；一本真礼簿都没有时整卡不出。
    private var flagshipBookLedger: Ledger? {
        ledgers.first { !sampleIDs.contains($0.id) }
    }

    /// 旗舰卡：纸面满块＋衬线标题（衬线白名单：礼簿封面满块同格），
    /// 与首页数据卡天然区分；存在感靠文案与视觉，不靠位置。
    private func bookFlagshipCard(ledger: Ledger, promoted: Bool) -> some View {
        Button {
            ledgerRoute = ledger
        } label: {
            HStack(alignment: .top, spacing: LiqianMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                    if promoted {
                        Text("《\(ledger.title)》记完了，可以成书了")
                            .font(.liqianSerif(.title3))
                            .foregroundStyle(Palette.paperInk)
                        Text("这场事已经办完，共记了 \(countedCount(of: ledger)) 笔。")
                            .font(.footnote)
                            .foregroundStyle(Palette.paperStone)
                            .lineSpacing(3)
                        Text("把礼簿印成锁线精装的礼谱——摆在家里、送给长辈，都是拿得出手的传家件。")
                            .font(.footnote)
                            .foregroundStyle(Palette.paperStone)
                            .lineSpacing(3)
                    } else {
                        Text("把你家的礼簿，做成一本能传下去的礼谱")
                            .font(.liqianSerif(.title3))
                            .foregroundStyle(Palette.paperInk)
                        Text("礼谱已是印刷级排版，装订成书是锁线精装、右开本，约 299–399 元一本。")
                            .font(.footnote)
                            .foregroundStyle(Palette.paperStone)
                            .lineSpacing(3)
                    }
                    HStack(spacing: 4) {
                        Text(promoted ? "去成书" : "看看成书")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.primary)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.primary)
                            .accessibilityHidden(true)
                    }
                    .padding(.top, 2)
                }
                Spacer()
                SealStampView(char: "谱", size: 40)
            }
            .padding(LiqianMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner))
            .overlay(
                RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                    .stroke(Palette.paperLine, lineWidth: 1)
            )
        }
        .buttonStyle(ScaleOnPressButtonStyle())
    }

    // MARK: - 礼簿行口径（同 LedgersView）

    private func received(of ledger: Ledger) -> Int {
        records
            .filter { $0.ledgerID == ledger.id && $0.direction == LiqianConstants.received }
            .reduce(0) { $0 + $1.amountCents }
    }

    private func given(of ledger: Ledger) -> Int {
        records
            .filter { $0.ledgerID == ledger.id && $0.direction == LiqianConstants.given && !$0.isPendingSend }
            .reduce(0) { $0 + $1.amountCents }
    }

    private func count(of ledger: Ledger) -> Int {
        records.filter { $0.ledgerID == ledger.id }.count
    }
}

/// 卡片行修饰：List 行透明、无分隔线、统一行距（HomeView 卡片与礼簿行共用）
private struct PlainCardRow: ViewModifier {
    let insets: EdgeInsets
    func body(content: Content) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(insets)
    }
}

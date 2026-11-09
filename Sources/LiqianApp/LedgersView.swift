import Charts
import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

struct LedgersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @Query private var records: [GiftRecord]
    @Query private var allMembers: [LedgerMember]
    @State private var showNewLedger = false
    @State private var personRoute: PeopleView.NameRoute?
    @State private var ledgerRoute: Ledger?
    @State private var ledgerToDelete: Ledger?
    @State private var editingLedger: Ledger?
    @State private var deleteTrigger = 0
    @State private var showSampleDone = false
    @Namespace private var zoomSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// 统计隔离（PRO-AUDIT-2 第 2 项）：示例账本的记录不计入首页任何汇总/速览
    private var sampleIDs: Set<UUID> { SampleData.sampleIDs(ledgers: ledgers) }

    private var statRecords: [GiftRecord] {
        let ids = sampleIDs
        return records.filter { !ids.contains($0.ledgerID) }
    }

    private var totalReceived: Int {
        statRecords.filter { $0.direction == LiqianConstants.received }.reduce(0) { $0 + $1.amountCents }
    }

    private var totalGiven: Int {
        statRecords
            .filter { $0.direction == LiqianConstants.given && !$0.isPendingSend }
            .reduce(0) { $0 + $1.amountCents }
    }

    // MARK: 首页即报表（v1.1）

    private var snapshots: [EntrySnapshot] {
        AppSupport.snapshots(records: statRecords, ledgers: ledgers)
    }

    private var pendingPeople: [PersonSummary] {
        LedgerMath.people(from: snapshots).filter { $0.hasPending }
    }

    private var pendingTotal: Int {
        pendingPeople.reduce(0) { $0 + $1.pendingCents }
    }

    private var thisYearSummary: YearSummary {
        LedgerMath.yearSummary(from: snapshots, year: LiqianDate.currentYearString())
    }

    /// 最近往来：按日期倒序 5 条（同日保持 @Query 原序的相对顺序；示例记录不入速览）
    private var recentRecords: [GiftRecord] {
        Array(statRecords.sorted { $0.date > $1.date }.prefix(5))
    }

    private func ledger(of r: GiftRecord) -> Ledger? {
        ledgers.first { $0.id == r.ledgerID }
    }

    /// 卡片行口径（v2.5 包 3）：首页改为 List 承载以获得原生侧滑——
    /// 全部内容同在一个 Section，行本身透明、无分隔线，卡片自带表面；
    /// 行上下各留 6pt（半距字面量）拼出原卡间距 12，两侧 16 与原页面边距一致。
    private var cardRowInsets: EdgeInsets {
        EdgeInsets(
            top: 6, leading: LiqianMetrics.spacingM,
            bottom: 6, trailing: LiqianMetrics.spacingM
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // 0 数据时隐藏汇总卡：只留空状态，不重复宣告「什么都没有」（S7）
                    if !statRecords.isEmpty {
                        summaryCard
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(cardRowInsets)
                    }
                    if !pendingPeople.isEmpty {
                        pendingCard
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(cardRowInsets)
                    }
                    if thisYearSummary.count > 0 {
                        yearChartCard
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(cardRowInsets)
                    }
                    if !recentRecords.isEmpty {
                        recentCard
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(cardRowInsets)
                    }
                    if ledgers.isEmpty {
                        emptyState
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    } else {
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
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(cardRowInsets)
                            // 左滑：编辑／删除（删除走与详情页「更多」同款确认，包 1/3）
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
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.pageBG.ignoresSafeArea())
            // 底部多留一段：滚动到底时最后一张卡不被 FAB 与 Tab 栏遮挡
            .contentMargins(.bottom, 72, for: .scrollContent)
            .animation(reduceMotion ? nil : .snappy, value: ledgers.count)
            // 记录增减时汇总/待回/最近三张卡的出现与消失同样平滑（v4.4），
            // 不只礼簿行有动画
            .animation(reduceMotion ? nil : .snappy, value: statRecords.count)
            .navigationTitle("礼簿")
            .navigationBarTitleDisplayMode(.large)
            // 新增动作收敛到右下角 FAB（v2.4 定版，替代原工具栏 + 按钮）；
            // 首页不隐藏 Tab 栏，FAB 须避让浮动 Tab 栏高度
            .overlay(alignment: .bottomTrailing) {
                AddFloatingButton(label: "新建礼簿", bottomPadding: AddFloatingButton.tabBarClearance) {
                    showNewLedger = true
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
                Text("「首页」多了两本示例礼簿，「往来」页能看到往来差额和备礼清单的效果。")
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

    private var summaryCard: some View {
        HStack {
            stat(label: "累计收礼", value: LedgerMath.fmtMoney(cents: totalReceived), color: Palette.ink, numericValue: totalReceived)
            Spacer()
            stat(label: "累计随礼", value: LedgerMath.fmtMoney(cents: totalGiven), color: Palette.ink, numericValue: totalGiven)
            Spacer()
            stat(label: "礼簿", value: "\(ledgers.count) 本", color: Palette.ink, numericValue: ledgers.count)
        }
        .padding(.vertical, LiqianMetrics.spacingM)
        .padding(.horizontal, LiqianMetrics.spacingSM)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner))
    }

    private func stat(label: String, value: String, color: Color, numericValue: Int) -> some View {
        VStack(spacing: LiqianMetrics.spacingXS) {
            Text(value)
                .font(.liqianMoney(.title2, dark: colorScheme == .dark))
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy, value: numericValue)
            Text(label)
                .font(.footnote)
                .foregroundStyle(Palette.stone)
        }
    }

    /// 待回礼卡：有人没回才出现，最多列 3 人，点行进人物详情
    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
            HStack {
                Text("待回礼")
                    .font(.headline)
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
                    personRoute = PeopleView.NameRoute(name: p.name)
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

    /// 本年收/随迷你柱状图：数据稀疏（低频应用，全年可能就几笔），
    /// 按月拆柱会只剩一两根孤柱误导人，直接用年度总量两根柱更诚实。
    private var yearChartCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("\(LiqianDate.currentYearString()) 年往来")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Chart {
                BarMark(
                    x: .value("方向", "收礼"),
                    y: .value("金额（元）", Double(thisYearSummary.recv) / 100.0)
                )
                .foregroundStyle(Palette.primary)
                .cornerRadius(6)
                .annotation(position: .top, alignment: .center) {
                    Text(LedgerMath.fmtMoney(cents: thisYearSummary.recv))
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
                BarMark(
                    x: .value("方向", "随礼"),
                    y: .value("金额（元）", Double(thisYearSummary.given) / 100.0)
                )
                .foregroundStyle(Palette.ink)
                .cornerRadius(6)
                .annotation(position: .top, alignment: .center) {
                    Text(LedgerMath.fmtMoney(cents: thisYearSummary.given))
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 120)
            .accessibilityLabel("\(LiqianDate.currentYearString()) 年往来：收礼 \(LedgerMath.fmtMoney(cents: thisYearSummary.recv))，随礼 \(LedgerMath.fmtMoney(cents: thisYearSummary.given))")
        }
        .liqianCardSurface()
    }

    /// 最近往来 5 条：人名 + 事由 + 方向签，金额一律墨色（方向靠签区分，v3 纪律），点行进所属礼簿
    private var recentCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
            Text("最近往来")
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .padding(.bottom, LiqianMetrics.spacingXS)
            ForEach(recentRecords) { r in
                Button {
                    if let l = ledger(of: r) { ledgerRoute = l }
                } label: {
                    HStack(spacing: LiqianMetrics.spacingS) {
                        DirectionTag(direction: r.direction, bai: ledger(of: r)?.isBai ?? false)
                        Text(r.person)
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text(ledger(of: r)?.type ?? "")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
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
        }
        .liqianCardSurface()
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有礼簿", systemImage: "book.closed")
        } description: {
            Text("从最近一场事开始记。")
        } actions: {
            // 空状态主行动用 prominent 样式（HIG/ContentUnavailableView 惯例，S6）
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

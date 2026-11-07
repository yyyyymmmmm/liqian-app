import Charts
import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

struct LedgersView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @Query private var records: [GiftRecord]
    @State private var showNewLedger = false
    @State private var personRoute: PeopleView.NameRoute?
    @State private var ledgerRoute: Ledger?
    @Namespace private var zoomSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var totalReceived: Int {
        records.filter { $0.direction == LiqianConstants.received }.reduce(0) { $0 + $1.amountCents }
    }

    private var totalGiven: Int {
        records
            .filter { $0.direction == LiqianConstants.given && !$0.isPendingSend }
            .reduce(0) { $0 + $1.amountCents }
    }

    // MARK: 首页即报表（v1.1）

    private var snapshots: [EntrySnapshot] {
        AppSupport.snapshots(records: records, ledgers: ledgers)
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

    /// 最近往来：按日期倒序 5 条（同日保持 @Query 原序的相对顺序）
    private var recentRecords: [GiftRecord] {
        Array(records.sorted { $0.date > $1.date }.prefix(5))
    }

    private func ledger(of r: GiftRecord) -> Ledger? {
        ledgers.first { $0.id == r.ledgerID }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingM) {
                    summaryCard
                    if !pendingPeople.isEmpty {
                        pendingCard
                    }
                    if thisYearSummary.count > 0 {
                        yearChartCard
                    }
                    if !recentRecords.isEmpty {
                        recentCard
                    }
                    if ledgers.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: LiqianMetrics.spacingSM) {
                            ForEach(ledgers) { ledger in
                                NavigationLink {
                                    LedgerDetailView(ledger: ledger)
                                        .navigationTransition(.zoom(sourceID: ledger.id, in: zoomSpace))
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
                            }
                        }
                        .animation(reduceMotion ? nil : .snappy, value: ledgers.count)
                    }
                }
                .padding(LiqianMetrics.spacingM)
            }
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("礼簿")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewLedger = true
                    } label: {
                        Label("新建礼簿", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(item: $personRoute) { route in
                PersonDetailView(name: route.name)
            }
            .navigationDestination(item: $ledgerRoute) { ledger in
                LedgerDetailView(ledger: ledger)
            }
            .sheet(isPresented: $showNewLedger) {
                LedgerFormView()
            }
        }
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
        .overlay(
            RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                .stroke(Palette.hairline, lineWidth: 1)
        )
    }

    private func stat(label: String, value: String, color: Color, numericValue: Int) -> some View {
        VStack(spacing: LiqianMetrics.spacingXS) {
            Text(value)
                .font(.liqianMoney(.title2))
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
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("共 \(pendingPeople.count) 人 · \(LedgerMath.fmtMoney(cents: pendingTotal))")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
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
                .font(.headline.weight(.bold))
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
        }
        .liqianCardSurface()
    }

    /// 最近往来 5 条：人名 + 事由 + 方向签，金额一律墨色（方向靠签区分，v3 纪律），点行进所属礼簿
    private var recentCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
            Text("最近往来")
                .font(.headline.weight(.bold))
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
            Button("新建第一本礼簿") {
                showNewLedger = true
            }
            .foregroundStyle(Palette.primary)
            .frame(minHeight: LiqianMetrics.minTapTarget)
            Button("生成示例数据") {
                SampleData.generate(into: modelContext)
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

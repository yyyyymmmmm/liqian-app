import Charts
import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 图表页（v4.6，四栏新增）：人情往来的财务式全景——总览、月度收送趋势、
/// 年度汇总、关系结构、场合分布、人物洞察与待回清单。
/// 数据口径与全 App 统计一致：AppSupport.snapshots + 示例礼簿隔离
/// （SampleData.sampleIDs），随礼只计已送出（待送出不计金额/笔数），
/// 待回恒为 max(balance, 0)（LedgerMath.people 定版口径）；金额 fmtMoney。
/// 设计纪律：中性打底、朱砂只表「收」、墨灰表「送」、金色不入 UI；
/// 全部数字等宽（monospacedDigit）；入场动效（KPI 滚动、柱条生长、环图扫入）
/// 在 Reduce Motion 开启时全部瞬时呈现（POLISH 口径）。
struct ChartsView: View {
    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var scope: ChartScope = .all
    @State private var selectedYear = ""
    /// 点选读数（v4.7.1）：月度三图共用的选中月份「轴标签」（窗口内唯一），
    /// nil 或标签已随范围切换失效时，读数回退到最近有数据的月份
    /// （effectiveTrendBucket / effectiveNetRow 统一兜底）。
    @State private var selectedMonthLabel: String?
    @State private var personRoute: PeopleView.NameRoute?
    /// 钻取（v4.7）：场合行 → 礼簿详情；关系行 → 该关系人物列表
    @State private var ledgerRoute: Ledger?
    @State private var relationRoute: RelationRoute?
    /// 入场进度 0→1：驱动柱条生长与环图扫入（Reduce Motion 时恒 1）
    @State private var entrance: Double = 0

    // MARK: - 数据管线（口径同 StatsView）

    private var sampleIDs: Set<UUID> { SampleData.sampleIDs(ledgers: ledgers) }

    private var statRecords: [GiftRecord] {
        let ids = sampleIDs
        return records.filter { !ids.contains($0.ledgerID) }
    }

    private var allSnapshots: [EntrySnapshot] {
        AppSupport.snapshots(records: statRecords, ledgers: ledgers)
    }

    /// 数据中出现过的自然年（倒序），供「自然年」档选年
    private var availableYears: [String] {
        Array(Set(allSnapshots.map { String($0.date.prefix(4)) })).sorted(by: >)
    }

    private var effectiveYear: String {
        if availableYears.contains(selectedYear) { return selectedYear }
        return availableYears.first ?? LiqianDate.currentYearString()
    }

    /// 近 12 个月档的起始月（含当月共 12 个月），格式 yyyy-MM
    private var last12StartKey: String {
        let cal = Calendar.current
        let start = cal.date(byAdding: .month, value: -11, to: Date()) ?? Date()
        let comps = cal.dateComponents([.year, .month], from: start)
        return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
    }

    private func inScope(_ date: String) -> Bool {
        switch scope {
        case .all: return true
        case .last12: return String(date.prefix(7)) >= last12StartKey
        case .year: return date.hasPrefix(effectiveYear + "-")
        }
    }

    /// 滚动金额存档的范围键（v5.4）：自然年档带年份，各范围存档互不串扰
    private var rollScopeKey: String {
        scope == .year ? "year-\(effectiveYear)" : scope.rawValue
    }

    private var scopedSnapshots: [EntrySnapshot] {
        allSnapshots.filter { inScope($0.date) }
    }

    private var scopedRecords: [GiftRecord] {
        statRecords.filter { inScope($0.date) }
    }

    private var people: [PersonSummary] { LedgerMath.people(from: scopedSnapshots) }

    private var totalReceived: Int {
        scopedSnapshots.filter { $0.direction == LiqianConstants.received && !$0.isPendingSend }
            .reduce(0) { $0 + $1.amountCents }
    }

    private var totalGiven: Int {
        scopedSnapshots.filter { $0.direction == LiqianConstants.given && !$0.isPendingSend }
            .reduce(0) { $0 + $1.amountCents }
    }

    private var pendingPeople: [PersonSummary] {
        people.filter { $0.hasPending }.sorted { $0.pendingCents > $1.pendingCents }
    }

    // MARK: - 聚合结构

    private struct MonthBucket: Identifiable {
        var key: String // yyyy-MM
        var label: String
        var received: Int
        var given: Int
        var id: String { key }
        var total: Int { received + given }
    }

    /// 趋势图的月份窗口：基础序列为最近 12 个月（全部/近12个月档，缺月补零）
    /// 或自然年 1–12 月；再经 Core 的 adaptiveMonthKeys 按数据跨度收敛——
    /// 数据跨度 ≤4 个月时只画「跨度 + 两端各 1 个月」，不再硬摆 12 个空槽
    /// （v4.7.1 修真机实证：单月有数时图面 90% 空白、长标签挤成糊）。
    /// 轴标签走 Core 的 monthAxisLabel 短格式（同年「N月」、跨年仅 1 月带年份）；
    /// 旧版「01月·26」长串 + 12 标签无稀释全量绘制正是重叠乱码的根因。
    /// 聚合只吃 scoped 数据，全部档的窗口外月份不进图（全史由年度汇总承载）。
    private var monthBuckets: [MonthBucket] {
        let cal = Calendar.current
        var baseKeys: [String] = []
        switch scope {
        case .year:
            baseKeys = (1...12).map { String(format: "%@-%02d", effectiveYear, $0) }
        case .all, .last12:
            let now = Date()
            for back in stride(from: 11, through: 0, by: -1) {
                let d = cal.date(byAdding: .month, value: -back, to: now) ?? now
                let c = cal.dateComponents([.year, .month], from: d)
                baseKeys.append(String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0))
            }
        }
        let dataMonths = Set(LedgerMath.monthlyAggregates(from: scopedSnapshots).map(\.month))
        let keys = LedgerMath.adaptiveMonthKeys(baseKeys: baseKeys, dataMonths: dataMonths)
        let multiYear = Set(keys.map { String($0.prefix(4)) }).count > 1
        return keys.map { key in
            var recv = 0
            var giv = 0
            for e in scopedSnapshots where String(e.date.prefix(7)) == key && !e.isPendingSend {
                if e.direction == LiqianConstants.received { recv += e.amountCents }
                else if e.direction == LiqianConstants.given { giv += e.amountCents }
            }
            return MonthBucket(
                key: key,
                label: LedgerMath.monthAxisLabel(key: key, multiYear: multiYear),
                received: recv, given: giv
            )
        }
    }

    // MARK: - 点选读数与窗口度量（v4.7.1）

    /// 当前生效的选中月（收送）：用户点选命中则用它，否则回退最近有数据的月份
    private var effectiveTrendBucket: MonthBucket? {
        if let label = selectedMonthLabel,
           let hit = monthBuckets.first(where: { $0.label == label }) {
            return hit
        }
        return monthBuckets.last(where: { $0.total > 0 }) ?? monthBuckets.last
    }

    /// 当前生效的选中月（净额/累计）：与收送图同一选中标签，两卡联动
    private var effectiveNetRow: NetMonth? {
        if let label = selectedMonthLabel,
           let hit = netMonths.first(where: { $0.label == label }) {
            return hit
        }
        return netMonths.last(where: { $0.net != 0 }) ?? netMonths.last
    }

    /// 横轴可见标签：stride 稀释到 ≤6 个（12 槽时隔月显示），三图共用
    private var monthTickLabels: [String] {
        let labels = monthBuckets.map(\.label)
        guard labels.count > 6 else { return labels }
        let step = Int(ceil(Double(labels.count) / 6.0))
        return labels.enumerated().filter { $0.offset % step == 0 }.map(\.element)
    }

    /// 图高随槽位收敛：少槽不高（自适应窗口的配套，5 槽以下用紧凑高）
    private var trendChartHeight: CGFloat { monthBuckets.count <= 5 ? 148 : 190 }
    private var netChartHeight: CGFloat { monthBuckets.count <= 5 ? 96 : 120 }
    private var cumulativeChartHeight: CGFloat { monthBuckets.count <= 5 ? 80 : 96 }

    /// 选中月的逐笔明细（图表明细联动）：与图同口径——范围内、待送出不计，
    /// 按日期倒序（同日金额大者先），展示层截断前 10 笔并注明总数
    private var selectedMonthRecords: [GiftRecord] {
        guard let key = effectiveTrendBucket?.key else { return [] }
        return scopedRecords
            .filter { $0.date.hasPrefix(key) && !$0.isPendingSend }
            .sorted { a, b in
                if a.date != b.date { return a.date > b.date }
                return a.amountCents > b.amountCents
            }
    }

    /// yyyy-MM → 「2026年10月」（读数行与明细标题用）
    private func monthTitle(_ key: String) -> String {
        "\(key.prefix(4))年\(Int(key.suffix(2)) ?? 0)月"
    }

    /// 净额读数文本：正数带 +，负数由 fmtMoney 自带 −（¥-N 口径），零 plain
    private func netMoneyText(_ cents: Int) -> String {
        cents > 0 ? "+" + LedgerMath.fmtMoney(cents: cents) : LedgerMath.fmtMoney(cents: cents)
    }

    /// 含零基线并留边距的 Y 域：负值能落到零轴下方、折线末点不贴边裁切
    private func paddedDomain(values: [Double]) -> ClosedRange<Double> {
        let lo = min(0, values.min() ?? 0)
        let hi = max(0, values.max() ?? 0)
        if hi - lo <= 0 { return (lo - 50)...(hi + 50) }
        let pad = (hi - lo) * 0.15
        return (lo == 0 ? 0 : lo - pad)...(hi + pad)
    }

    private struct YearRow: Identifiable {
        var year: String
        var received: Int
        var given: Int
        var id: String { year }
        var net: Int { received - given }
    }

    private var yearRows: [YearRow] {
        var map: [String: (Int, Int)] = [:]
        for e in scopedSnapshots where !e.isPendingSend {
            let y = String(e.date.prefix(4))
            var pair = map[y] ?? (0, 0)
            if e.direction == LiqianConstants.received { pair.0 += e.amountCents }
            else if e.direction == LiqianConstants.given { pair.1 += e.amountCents }
            map[y] = pair
        }
        return map.map { YearRow(year: $0.key, received: $0.value.0, given: $0.value.1) }
            .sorted { $0.year > $1.year }
    }

    private var relationRows: [RelationSummary] {
        LedgerMath.relationSummary(from: scopedSnapshots).filter { $0.count > 0 }
    }

    private struct OccasionRow: Identifiable {
        var id: UUID
        var title: String
        var type: String
        var date: String
        var received: Int
        var given: Int
        var count: Int
        var total: Int { received + given }
    }

    /// 场合＝一本一本的礼簿（一个场次）：按本汇总收+送，取 Top 8
    private var occasionRows: [OccasionRow] {
        let byID = Dictionary(ledgers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var map: [UUID: OccasionRow] = [:]
        for r in scopedRecords {
            if map[r.ledgerID] == nil {
                let l = byID[r.ledgerID]
                map[r.ledgerID] = OccasionRow(
                    id: r.ledgerID, title: l?.title ?? "（已删礼簿）", type: l?.type ?? "",
                    date: l?.date ?? "",
                    received: 0, given: 0, count: 0
                )
            }
            if r.isPendingSend { continue }
            if r.direction == LiqianConstants.received { map[r.ledgerID]?.received += r.amountCents }
            else { map[r.ledgerID]?.given += r.amountCents }
            map[r.ledgerID]?.count += 1
        }
        return map.values.filter { $0.count > 0 }
            .sorted { $0.total > $1.total }
            .prefix(8).map { $0 }
    }

    private var topPeople: [PersonSummary] {
        people.sorted { ($0.received + $0.given) > ($1.received + $1.given) }
            .prefix(10).map { $0 }
    }

    // MARK: - v4.7 补全聚合（沉到 Core 的 LedgerMath，视图只做窗口拼装）

    private struct NetMonth: Identifiable {
        var key: String
        var label: String
        var net: Int
        /// 窗口内累计净额（自窗口首月起算）
        var cumulative: Int
        var id: String { key }
    }

    /// 净额趋势窗口与收送趋势同键同标（monthBuckets），净额/累计走 Core 月度聚合；
    /// 累计只在窗口内滚算（口径在卡内注明），窗口外月份不混入。
    private var netMonths: [NetMonth] {
        let byKey = Dictionary(
            LedgerMath.monthlyAggregates(from: scopedSnapshots).map { ($0.month, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var running = 0
        return monthBuckets.map { bucket in
            let net = byKey[bucket.key]?.net ?? 0
            running += net
            return NetMonth(key: bucket.key, label: bucket.label, net: net, cumulative: running)
        }
    }

    private var typeRows: [TypeSummary] {
        LedgerMath.typeSummary(from: scopedSnapshots).filter { $0.count > 0 }
    }

    /// 红白汇总：[红事, 白事] 固定两行（Core kindSummary，判定同 Ledger.isBai）
    private var kindRows: [LedgerMath.KindAggregate] {
        LedgerMath.kindSummary(from: scopedSnapshots)
    }

    private var bucketRows: [LedgerMath.AmountBucket] {
        LedgerMath.amountBuckets(from: scopedSnapshots)
    }

    /// 年度整表：全范围（allSnapshots），不受顶部范围切换影响
    private var yearTableRows: [LedgerMath.YearAggregate] {
        LedgerMath.yearlyAggregates(from: allSnapshots)
    }

    /// 关系钻取路由（值为关系名）
    private struct RelationRoute: Identifiable, Hashable {
        var relation: String
        var id: String { relation }
    }

    // MARK: - 主体

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingL) {
                    rangeSelector
                    if allSnapshots.isEmpty {
                        emptyStateCard
                    } else if scopedSnapshots.isEmpty {
                        scopeEmptyCard
                    } else {
                        overviewCard
                        trendCard
                        netTrendCard
                        relationCard
                        typeCard
                        kindCard
                        occasionCard
                        peopleCard
                        amountBucketCard
                        pendingCard
                        yearTableCard
                    }
                }
                .padding(.horizontal, LiqianMetrics.spacingL)
                .padding(.vertical, LiqianMetrics.spacingSM)
            }
            // 底部留白与首页/礼簿页同口径（contentMargins 72）：iOS 26 悬浮
            // Tab 栏会压住滚到底的页脚文字（v4.7.1 修真机实证遮挡）
            .contentMargins(.bottom, 72, for: .scrollContent)
            .background(Palette.pageBG.ignoresSafeArea())
            .navigationTitle("图表")
            .navigationDestination(item: $personRoute) { route in
                PersonDetailView(name: route.name)
            }
            .navigationDestination(item: $ledgerRoute) { ledger in
                LedgerDetailView(ledger: ledger)
            }
            .navigationDestination(item: $relationRoute) { route in
                // 人物列表与环图同口径：只取该关系下的快照再按人聚合，
                // 金额即该关系内的往来，不混入此人在其他关系下的记录
                RelationPeopleList(
                    relation: route.relation,
                    people: LedgerMath.people(
                        from: scopedSnapshots.filter { $0.relation == route.relation }
                    ),
                    personRoute: $personRoute
                )
            }
            .onAppear { restartEntrance() }
            .onChange(of: scope) { _, _ in restartEntrance() }
            .onChange(of: effectiveYear) { _, _ in restartEntrance() }
        }
    }

    private func restartEntrance() {
        if reduceMotion {
            entrance = 1
        } else {
            entrance = 0
            withAnimation(.default) { entrance = 1 }
        }
    }

    // MARK: - 范围选择（v5.14 全原生整改：系统 segmented Picker，与全 App
    // 其余分段同款；旧自绘胶囊指示器＋matchedGeometry 滑移整段删除）

    private var rangeSelector: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Picker("范围", selection: $scope) {
                ForEach(ChartScope.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .sensoryFeedback(.selection, trigger: scope)

            if scope == .year {
                HStack(spacing: LiqianMetrics.spacingS) {
                    Text("年份")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                    Menu {
                        ForEach(availableYears, id: \.self) { year in
                            Button {
                                selectedYear = year
                            } label: {
                                if year == effectiveYear {
                                    Label(year + " 年", systemImage: "checkmark")
                                } else {
                                    Text(year + " 年")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: LiqianMetrics.spacingXS) {
                            Text(effectiveYear + " 年")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(Palette.primary)
                    }
                }
            }
        }
    }

    // MARK: - 空态

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundStyle(Palette.primary)
            Text("暂无可统计的往来")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text("在「首页」记一笔后，这里会生成图表。示例礼簿的数据不计入统计。")
                .font(.subheadline)
                .foregroundStyle(Palette.stone)
                .fixedSize(horizontal: false, vertical: true)
        }
        .liqianCardSurface()
    }

    private var scopeEmptyCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("所选范围内暂无记录")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text("换一个时间范围，或在「首页」补记这个时段的往来。")
                .font(.subheadline)
                .foregroundStyle(Palette.stone)
        }
        .liqianCardSurface()
    }

    // MARK: - 总览

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingM) {
            cardHeader("总览", caption: scope.caption(year: effectiveYear))
            // v5.3.2 统计格定版：等宽网格居中（旧 2 列左对齐、标签在上，
            // 起始线不齐被用户圈图点名）。常规字号 3 列×2 行；无障碍
            // 大字号退 2 列×3 行防大数字挤爆（StatCell 另有下限缩放兜底）。
            StatGrid(columns: dynamicTypeSize.isAccessibilitySize ? 2 : 3) {
                StatCell(
                    label: "累计收",
                    spokenValue: LedgerMath.fmtMoney(cents: totalReceived)
                ) {
                    RollingMoneyText(cents: totalReceived, style: .title2, rollKey: "charts.totalReceived.\(rollScopeKey)")
                }
                StatCell(
                    label: "累计送",
                    spokenValue: LedgerMath.fmtMoney(cents: totalGiven)
                ) {
                    RollingMoneyText(cents: totalGiven, style: .title2, rollKey: "charts.totalGiven.\(rollScopeKey)")
                }
                StatCell(
                    label: "净往来（收 − 送）",
                    spokenValue: LedgerMath.fmtMoney(cents: totalReceived - totalGiven)
                ) {
                    RollingMoneyText(cents: totalReceived - totalGiven, style: .title2, rollKey: "charts.net.\(rollScopeKey)")
                }
                StatCell(
                    label: "待回礼 · \(pendingPeople.count) 人",
                    spokenValue: LedgerMath.fmtMoney(
                        cents: pendingPeople.reduce(0) { $0 + $1.pendingCents }
                    )
                ) {
                    RollingMoneyText(
                        cents: pendingPeople.reduce(0) { $0 + $1.pendingCents },
                        style: .title2,
                        rollKey: "charts.pendingTotal.\(rollScopeKey)"
                    )
                }
                StatCell(label: "往来人数", value: "\(people.count)", unit: "人", style: .title2)
                StatCell(
                    label: "场次（礼簿）",
                    value: "\(Set(scopedRecords.map(\.ledgerID)).count)",
                    unit: "场",
                    style: .title2
                )
            }
        }
        .liqianCardSurface()
    }

    // MARK: - 收送趋势 + 年度汇总

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingM) {
            HStack(alignment: .firstTextBaseline) {
                Text("收送趋势")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                legendDot(color: Palette.primary, text: "收礼")
                legendDot(color: givenColor, text: "随礼")
            }
            // 点选读数行（v4.7.1）：替代原静态逐柱合计标注——旧标注锚在柱顶、
            // 数值能浮到轴最大值之外（真机实证 ¥2,700 标在 2000 刻度上方）。
            // 改竞品通行做法：点/拖月份出虚线 RuleMark，精确值走本行文本。
            if let sel = effectiveTrendBucket {
                HStack(spacing: LiqianMetrics.spacingS) {
                    Text(monthTitle(sel.key))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("收 " + LedgerMath.fmtMoney(cents: sel.received))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Palette.moneyReceived)
                    Text("送 " + LedgerMath.fmtMoney(cents: sel.given))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Palette.moneyGiven)
                    Text("净 " + netMoneyText(sel.received - sel.given))
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(monthTitle(sel.key))：收 \(LedgerMath.fmtMoney(cents: sel.received))，送 \(LedgerMath.fmtMoney(cents: sel.given))，净 \(LedgerMath.fmtMoney(cents: sel.received - sel.given))")
            }
            Chart {
                ForEach(monthBuckets) { bucket in
                    BarMark(
                        x: .value("月份", bucket.label),
                        y: .value("收礼", Double(bucket.received) * entrance / 100.0)
                    )
                    .position(by: .value("方向", "收礼"))
                    .foregroundStyle(by: .value("方向", "收礼"))
                    .cornerRadius(2)
                    BarMark(
                        x: .value("月份", bucket.label),
                        y: .value("随礼", Double(bucket.given) * entrance / 100.0)
                    )
                    .position(by: .value("方向", "随礼"))
                    .foregroundStyle(by: .value("方向", "随礼"))
                    .cornerRadius(2)
                }
                if let sel = effectiveTrendBucket {
                    RuleMark(x: .value("月份", sel.label))
                        .foregroundStyle(Palette.stone.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartForegroundStyleScale(["收礼": Palette.primary, "随礼": givenColor])
            .chartLegend(.hidden)
            .chartXSelection(value: $selectedMonthLabel)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Palette.line)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(axisMoneyText(v))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Palette.stone)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: monthTickLabels) { _ in
                    AxisValueLabel()
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Palette.stone)
                }
            }
            .frame(height: trendChartHeight)
            .accessibilityLabel(trendAccessibilityText)

            if scope == .all {
                Text(monthBuckets.count < 12
                    ? "数据集中在 \(monthBuckets.count) 个月，趋势图已按跨度收敛；更早的往来见下方按年汇总。"
                    : "趋势图显示最近 12 个月；更早的往来见下方按年汇总。")
                    .font(.caption)
                    .foregroundStyle(Palette.stone)
            }

            // 图表明细联动（v4.7.1，竞品对标 A）：选中月的逐笔明细就在图下，
            // 点行进人物详情——图从「看」变成「用」（鲨鱼记账触图出当日
            // 最大三笔的同构做法，这里给整月全量）。口径与图一致：
            // 范围内、待送出不计（待送笔不进合计，也不在此列出）。
            if let sel = effectiveTrendBucket {
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("\(monthTitle(sel.key))明细")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("共 \(selectedMonthRecords.count) 笔")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Palette.stone)
                }
                if selectedMonthRecords.isEmpty {
                    Text("这个月没有往来记录。")
                        .font(.caption)
                        .foregroundStyle(Palette.stone)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(selectedMonthRecords.prefix(10).enumerated()), id: \.element.id) { idx, record in
                            Button {
                                personRoute = PeopleView.NameRoute(name: record.person)
                            } label: {
                                HStack(spacing: LiqianMetrics.spacingS) {
                                    DirectionTag(
                                        direction: record.direction,
                                        bai: ledgers.first { $0.id == record.ledgerID }?.isBai ?? false
                                    )
                                    Text(record.person)
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                    Text(ledgers.first { $0.id == record.ledgerID }?.title ?? "")
                                        .font(.footnote)
                                        .foregroundStyle(Palette.stone)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(LiqianDate.displayString(for: record.date))
                                        .font(.footnote)
                                        .foregroundStyle(Palette.stone)
                                    SignedMoneyText(
                                        cents: record.amountCents,
                                        direction: record.direction,
                                        bai: ledgers.first { $0.id == record.ledgerID }?.isBai ?? false,
                                        style: .body
                                    )
                                }
                                .frame(minHeight: LiqianMetrics.minTapTarget)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if idx < min(selectedMonthRecords.count, 10) - 1 {
                                Divider()
                            }
                        }
                    }
                    if selectedMonthRecords.count > 10 {
                        Text("还有 \(selectedMonthRecords.count - 10) 笔，点任意一笔可进人物详情，或到对应礼簿查看全部。")
                            .font(.caption)
                            .foregroundStyle(Palette.stone)
                    }
                }
            }

            if !yearRows.isEmpty {
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("按年汇总")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    // 与页末「年度总表」（全范围）区分：这里是当前范围内的年汇总
                    Text(scope.caption(year: effectiveYear))
                        .font(.caption)
                        .foregroundStyle(Palette.stone)
                }
                VStack(spacing: LiqianMetrics.spacingS) {
                    ForEach(yearRows) { row in
                        HStack(spacing: LiqianMetrics.spacingS) {
                            // 年份标签固定宽单行（v4.7.1）：旧宽 52 装不下
                            // 「2026 年」被挤成两行（真机实证），64 + 不换行
                            Text(row.year + " 年")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                                .frame(width: 64, alignment: .leading)
                            Text("收 " + LedgerMath.fmtMoney(cents: row.received))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Palette.stone)
                            Text("送 " + LedgerMath.fmtMoney(cents: row.given))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Palette.stone)
                            Spacer()
                            Text("净 " + LedgerMath.fmtMoney(cents: row.net))
                                .font(.footnote.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Palette.ink)
                        }
                    }
                }
            }
        }
        .liqianCardSurface()
    }

    /// 随礼系列色（v5.0.2）：黛青语义令牌，与收礼的主题强调成对；
    /// 全图收/送系列（趋势双柱/净额负柱/事由成对条/红事随礼）统一走它
    private var givenColor: Color { Palette.moneyGiven }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: LiqianMetrics.spacingXS) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption)
                .foregroundStyle(Palette.stone)
        }
    }

    private var trendAccessibilityText: String {
        let parts = monthBuckets.filter { $0.total > 0 }.map {
            "\($0.key)：收 \(LedgerMath.fmtMoney(cents: $0.received))，送 \(LedgerMath.fmtMoney(cents: $0.given))"
        }
        return "收送趋势（按月）。" + (parts.isEmpty ? "暂无数据" : parts.joined(separator: "；"))
    }

    // MARK: - 净额趋势（v4.7：月净额柱 + 窗口内累计折线，上下两图共用月份轴）

    /// 窗口内有净额变动的月份数：决定累计图是画折线还是退化为落点
    private var cumulativeChangeCount: Int { netMonths.filter { $0.net != 0 }.count }

    private var netTrendCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingM) {
            cardHeader("净额趋势", caption: "月净额（收 − 送）与累计净额")
            // 点选读数行（v4.7.1）：与收送图共用选中月份，两卡联动
            if let sel = effectiveNetRow {
                HStack(spacing: LiqianMetrics.spacingS) {
                    Text(monthTitle(sel.key))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("净 " + netMoneyText(sel.net))
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.ink)
                    Text("累计 " + LedgerMath.fmtMoney(cents: sel.cumulative))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(Palette.stone)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(monthTitle(sel.key))：净额 \(LedgerMath.fmtMoney(cents: sel.net))，累计净额 \(LedgerMath.fmtMoney(cents: sel.cumulative))")
            }
            Chart {
                ForEach(netMonths) { row in
                    BarMark(
                        x: .value("月份", row.label),
                        y: .value("净额", Double(row.net) * entrance / 100.0)
                    )
                    .foregroundStyle(row.net >= 0 ? Palette.primary : givenColor)
                    .cornerRadius(2)
                }
                RuleMark(y: .value("零", 0))
                    .foregroundStyle(Palette.stone.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                if let sel = effectiveNetRow {
                    RuleMark(x: .value("月份", sel.label))
                        .foregroundStyle(Palette.stone.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            // Y 域显式含零并留边距：负净额月份必须能画到零轴下方（v4.7.1）
            .chartYScale(domain: paddedDomain(values: netMonths.map { Double($0.net) / 100.0 }))
            .chartXSelection(value: $selectedMonthLabel)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Palette.line)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(axisMoneyText(v))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Palette.stone)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: monthTickLabels) { _ in
                    AxisValueLabel()
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Palette.stone)
                }
            }
            .frame(height: netChartHeight)
            .accessibilityLabel(netTrendAccessibilityText)

            Text("累计净额")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Chart {
                if cumulativeChangeCount >= 2 {
                    ForEach(netMonths) { row in
                        LineMark(
                            x: .value("月份", row.label),
                            y: .value("累计净额", Double(row.cumulative) * entrance / 100.0)
                        )
                        .foregroundStyle(Palette.ink)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(
                            x: .value("月份", row.label),
                            y: .value("累计净额", Double(row.cumulative) * entrance / 100.0)
                        )
                        .foregroundStyle(Palette.ink)
                        .symbolSize(14)
                    }
                    // 末点数值标签：锚点透明、只借位置挂标注；Y 域已留
                    // 15% 边距，标签不会像旧版那样贴边被裁切（真机实证）
                    if let last = netMonths.last {
                        PointMark(
                            x: .value("月份", last.label),
                            y: .value("累计净额", Double(last.cumulative) * entrance / 100.0)
                        )
                        .foregroundStyle(.clear)
                        .symbolSize(0)
                        .annotation(position: .top, alignment: .trailing, spacing: 2) {
                            Text(LedgerMath.fmtMoney(cents: last.cumulative))
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Palette.ink)
                        }
                    }
                } else {
                    // 退化形态（v4.7.1）：净额变动不足两个月时不拉整窗斜线
                    // ——旧版 11 个月为 0、末月突跳，折线射向图外且末点被裁；
                    // 改为只在累计非零处落点，数值由下方说明行承载。
                    ForEach(netMonths.filter { $0.cumulative != 0 }) { row in
                        PointMark(
                            x: .value("月份", row.label),
                            y: .value("累计净额", Double(row.cumulative) * entrance / 100.0)
                        )
                        .foregroundStyle(Palette.ink)
                        .symbolSize(36)
                    }
                }
                RuleMark(y: .value("零", 0))
                    .foregroundStyle(Palette.stone.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            .chartYScale(domain: paddedDomain(values: netMonths.map { Double($0.cumulative) / 100.0 }))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Palette.line)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(axisMoneyText(v))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Palette.stone)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: monthTickLabels) { _ in
                    AxisValueLabel()
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Palette.stone)
                }
            }
            .frame(height: cumulativeChartHeight)
            .accessibilityLabel(cumulativeAccessibilityText)

            if cumulativeChangeCount == 1, let only = netMonths.first(where: { $0.net != 0 }) {
                Text("仅 \(monthTitle(only.key)) 有净额变动，累计净额 \(LedgerMath.fmtMoney(cents: netMonths.last?.cumulative ?? 0))。")
                    .font(.caption)
                    .foregroundStyle(Palette.stone)
            } else if cumulativeChangeCount == 0 {
                Text("所选范围内收送相抵，累计净额无变化。")
                    .font(.caption)
                    .foregroundStyle(Palette.stone)
            }

        }
        .liqianCardSurface()
    }

    private var netTrendAccessibilityText: String {
        let parts = netMonths.filter { $0.net != 0 }.map {
            "\($0.key)：净 \(LedgerMath.fmtMoney(cents: $0.net))"
        }
        return "净额趋势（按月）。" + (parts.isEmpty ? "暂无数据" : parts.joined(separator: "；"))
    }

    private var cumulativeAccessibilityText: String {
        guard let last = netMonths.last else { return "累计净额：暂无数据" }
        return "累计净额：截至 \(last.key)，共 \(LedgerMath.fmtMoney(cents: last.cumulative))"
    }

    // MARK: - 关系结构（环图）

    private var relationCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingM) {
            cardHeader("关系分布", caption: "按往来总额（收 + 送）")
            if relationRows.isEmpty {
                Text("暂无数据")
                    .font(.subheadline)
                    .foregroundStyle(Palette.stone)
            } else {
                ZStack {
                    Chart(Array(relationRows.enumerated()), id: \.element.id) { idx, row in
                        SectorMark(
                            angle: .value("往来", Double(row.total) * max(entrance, 0.0001)),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .cornerRadius(4)
                        .foregroundStyle(sliceColor(index: idx))
                    }
                    .chartLegend(.hidden)
                    .frame(height: 190)
                    VStack(spacing: 2) {
                        Text("往来总额")
                            .font(.caption)
                            .foregroundStyle(Palette.stone)
                        RollingMoneyText(
                            cents: relationRows.reduce(0) { $0 + $1.total },
                            style: .title3,
                            rollKey: "charts.relationTotal.\(rollScopeKey)"
                        )
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(relationAccessibilityText)
                VStack(spacing: LiqianMetrics.spacingS) {
                    ForEach(Array(relationRows.enumerated()), id: \.element.id) { idx, row in
                        // 钻取（v4.7）：点行进该关系的人物列表
                        Button {
                            relationRoute = RelationRoute(relation: row.relation)
                        } label: {
                            HStack(spacing: LiqianMetrics.spacingS) {
                                Circle()
                                    .fill(sliceColor(index: idx))
                                    .frame(width: 8, height: 8)
                                Text(row.relation)
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.ink)
                                Text("\(row.count) 笔")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Palette.stone)
                                Spacer()
                                Text(percentText(row.total))
                                    .font(.footnote.monospacedDigit())
                                    .foregroundStyle(Palette.stone)
                                Text(LedgerMath.fmtMoney(cents: row.total))
                                    .font(.liqianMoney(.body))
                                    .foregroundStyle(Palette.ink)
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
                }
            }
        }
        .liqianCardSurface()
    }

    /// 环图色阶：朱砂领首（最大关系组），其余走暖灰中性阶——单色族、
    /// 无金色，浅/深两模式都由令牌与不透明度推导，不写死 hex。
    private func sliceColor(index: Int) -> Color {
        switch index {
        case 0: return Palette.primary
        case 1: return Palette.ink.opacity(0.72)
        case 2: return Palette.ink.opacity(0.50)
        case 3: return Palette.primary.opacity(0.45)
        case 4: return Palette.ink.opacity(0.34)
        case 5: return Palette.primary.opacity(0.28)
        default: return Palette.ink.opacity(0.22)
        }
    }

    private func percentText(_ part: Int) -> String {
        let all = relationRows.reduce(0) { $0 + $1.total }
        guard all > 0 else { return "" }
        return String(format: "%.0f%%", Double(part) / Double(all) * 100)
    }

    // MARK: - 占比条分段（v4.7.1，竞品对标 B：随手记式占比的一行化）

    /// 事由占比：按往来总额（收+送）分段，色彩与关系环图同阶（sliceColor）
    private var typeShareSegments: [ShareStackBar.Segment] {
        let total = typeRows.reduce(0) { $0 + $1.received + $1.given }
        guard total > 0 else { return [] }
        return typeRows.enumerated().map { idx, row in
            let frac = Double(row.received + row.given) / Double(total)
            return ShareStackBar.Segment(
                id: row.type,
                fraction: frac * entrance,
                rawFraction: frac,
                color: sliceColor(index: idx),
                // 前三段是深色阶（朱砂/墨 0.72/墨 0.50）用白字，其后浅阶用墨字
                labelColor: idx <= 2 ? .white : Palette.ink,
                percentText: String(format: "%.0f%%", frac * 100)
            )
        }
    }

    private var typeShareAccessibilityText: String {
        let total = typeRows.reduce(0) { $0 + $1.received + $1.given }
        guard total > 0 else { return "事由金额占比：暂无数据" }
        let parts = typeRows.map {
            "\($0.type) \(String(format: "%.0f%%", Double($0.received + $0.given) / Double(total) * 100))"
        }
        return "事由金额占比：" + parts.joined(separator: "，")
    }

    /// 红白占比：红事朱砂、白事素蓝（与红白条图同色义）
    private var kindShareSegments: [ShareStackBar.Segment] {
        let total = kindRows.reduce(0) { $0 + $1.received + $1.given }
        guard total > 0 else { return [] }
        return kindRows.map { row in
            let frac = Double(row.received + row.given) / Double(total)
            return ShareStackBar.Segment(
                id: row.name,
                fraction: frac * entrance,
                rawFraction: frac,
                color: row.isBai ? Palette.baiPrimary : Palette.primary,
                labelColor: .white,
                percentText: String(format: "%.0f%%", frac * 100)
            )
        }
    }

    private var kindShareAccessibilityText: String {
        let total = kindRows.reduce(0) { $0 + $1.received + $1.given }
        guard total > 0 else { return "红白金额占比：暂无数据" }
        let parts = kindRows.map {
            "\($0.name) \(String(format: "%.0f%%", Double($0.received + $0.given) / Double(total) * 100))"
        }
        return "红白金额占比：" + parts.joined(separator: "，")
    }

    private var relationAccessibilityText: String {
        let parts = relationRows.map {
            "\($0.relation) \($0.count) 笔，往来 \(LedgerMath.fmtMoney(cents: $0.total))"
        }
        return "关系分布：" + parts.joined(separator: "；")
    }

    // MARK: - 事由分布（v4.7：按礼簿事由，收/送分开成对条形）

    private var typeCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingM) {
            HStack(alignment: .firstTextBaseline) {
                Text("事由分布")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                legendDot(color: Palette.primary, text: "收礼")
                legendDot(color: givenColor, text: "随礼")
            }
            if typeRows.isEmpty {
                Text("暂无数据")
                    .font(.subheadline)
                    .foregroundStyle(Palette.stone)
            } else {
                // 占比条（v4.7.1）：先给份额的一眼读数，下方成对条再给收/送结构
                ShareStackBar(segments: typeShareSegments, accessibilityText: typeShareAccessibilityText)
                Chart(typeRows) { row in
                    BarMark(
                        x: .value("收礼", Double(row.received) * entrance / 100.0),
                        y: .value("事由", row.type)
                    )
                    .position(by: .value("方向", "收礼"))
                    .foregroundStyle(by: .value("方向", "收礼"))
                    .cornerRadius(3)
                    BarMark(
                        x: .value("随礼", Double(row.given) * entrance / 100.0),
                        y: .value("事由", row.type)
                    )
                    .position(by: .value("方向", "随礼"))
                    .foregroundStyle(by: .value("方向", "随礼"))
                    .cornerRadius(3)
                }
                .chartForegroundStyleScale(["收礼": Palette.primary, "随礼": givenColor])
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine().foregroundStyle(Palette.line)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(axisMoneyText(v))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Palette.stone)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink)
                    }
                }
                .frame(height: CGFloat(typeRows.count) * 52 + 16)
                .accessibilityLabel(typeAccessibilityText)
                VStack(spacing: LiqianMetrics.spacingXS) {
                    ForEach(typeRows) { row in
                        HStack(spacing: LiqianMetrics.spacingS) {
                            Text(row.type)
                                .font(.caption)
                                .foregroundStyle(Palette.stone)
                                .frame(width: 30, alignment: .leading)
                            Spacer()
                            Text("收 \(LedgerMath.fmtMoney(cents: row.received)) · 送 \(LedgerMath.fmtMoney(cents: row.given)) · \(row.count) 笔")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Palette.stone)
                        }
                    }
                }
            }
        }
        .liqianCardSurface()
    }

    private var typeAccessibilityText: String {
        let parts = typeRows.map {
            "\($0.type)：收 \(LedgerMath.fmtMoney(cents: $0.received))，送 \(LedgerMath.fmtMoney(cents: $0.given))，共 \($0.count) 笔"
        }
        return "事由分布：" + parts.joined(separator: "；")
    }

    // MARK: - 红白分开（v4.7：判定同 Ledger.isBai，红事朱砂、白事素蓝，不混账）

    private var kindCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingM) {
            cardHeader("红白分开", caption: "红事与白事分开统计")
            // 占比条（v4.7.1）：红/白总份额一行看清，下方条图再拆收/送
            if kindRows.contains(where: { $0.received + $0.given > 0 }) {
                ShareStackBar(segments: kindShareSegments, accessibilityText: kindShareAccessibilityText)
            }
            Chart(kindRows) { row in
                BarMark(
                    x: .value("收礼", Double(row.received) * entrance / 100.0),
                    y: .value("类别", row.name)
                )
                .position(by: .value("类目", row.isBai ? "白事收礼" : "红事收礼"))
                .foregroundStyle(by: .value("类目", row.isBai ? "白事收礼" : "红事收礼"))
                .cornerRadius(3)
                BarMark(
                    x: .value("随礼", Double(row.given) * entrance / 100.0),
                    y: .value("类别", row.name)
                )
                .position(by: .value("类目", row.isBai ? "白事随礼" : "红事随礼"))
                .foregroundStyle(by: .value("类目", row.isBai ? "白事随礼" : "红事随礼"))
                .cornerRadius(3)
            }
            .chartForegroundStyleScale([
                "红事收礼": Palette.primary,
                "红事随礼": givenColor,
                "白事收礼": Palette.baiPrimary,
                "白事随礼": Palette.baiPrimary.opacity(0.45),
            ])
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
                    AxisGridLine().foregroundStyle(Palette.line)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(axisMoneyText(v))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Palette.stone)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                }
            }
            .frame(height: 120)
            .accessibilityLabel(kindAccessibilityText)
            VStack(spacing: LiqianMetrics.spacingXS) {
                ForEach(kindRows) { row in
                    HStack(spacing: LiqianMetrics.spacingS) {
                        Text(row.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(row.isBai ? Palette.baiPrimary : Palette.primary)
                            .frame(width: 30, alignment: .leading)
                        Spacer()
                        Text("收 \(LedgerMath.fmtMoney(cents: row.received)) · 送 \(LedgerMath.fmtMoney(cents: row.given)) · 净 \(LedgerMath.fmtMoney(cents: row.net)) · \(row.count) 笔 · \(row.occasions) 场")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Palette.stone)
                    }
                }
            }
        }
        .liqianCardSurface()
    }

    private var kindAccessibilityText: String {
        let parts = kindRows.map {
            "\($0.name)：收 \(LedgerMath.fmtMoney(cents: $0.received))，送 \(LedgerMath.fmtMoney(cents: $0.given))，净 \(LedgerMath.fmtMoney(cents: $0.net))，共 \($0.count) 笔、\($0.occasions) 场"
        }
        return "红白分开：" + parts.joined(separator: "；")
    }

    // MARK: - 场合分布

    private var occasionCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingM) {
            cardHeader("场合分布", caption: "按礼簿汇总收 + 送，取前 8 场")
            if occasionRows.isEmpty {
                Text("暂无数据")
                    .font(.subheadline)
                    .foregroundStyle(Palette.stone)
            } else {
                Chart(occasionRows) { row in
                    BarMark(
                        x: .value("往来", Double(row.total) * entrance / 100.0),
                        // 图类目按标题字符串归组：两本同名礼簿会被画成一条，
                        // 与下方逐本明细对不上（v4.7 审计修正）——同名时
                        // 图标签带上日期消歧，明细行仍显示原标题。
                        y: .value("场合", occasionChartLabel(row))
                    )
                    .foregroundStyle(Palette.stone.opacity(barOpacity(total: row.total, in: occasionRows.map(\.total))))
                    .cornerRadius(4)
                    .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                        Text(LedgerMath.fmtMoney(cents: row.total))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Palette.stone)
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine().foregroundStyle(Palette.line)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(axisMoneyText(v))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Palette.stone)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink)
                    }
                }
                .frame(height: CGFloat(occasionRows.count) * 36 + 16)
                .accessibilityLabel(occasionAccessibilityText)
                VStack(spacing: LiqianMetrics.spacingXS) {
                    ForEach(occasionRows) { row in
                        // 钻取（v4.7）：点行进这本礼簿的详情页
                        Button {
                            ledgerRoute = ledgers.first { $0.id == row.id }
                        } label: {
                            HStack(spacing: LiqianMetrics.spacingS) {
                                Text(row.type)
                                    .font(.caption)
                                    .foregroundStyle(Palette.stone)
                                    .frame(width: 30, alignment: .leading)
                                Text(row.title)
                                    .font(.caption)
                                    .foregroundStyle(Palette.stone)
                                    .lineLimit(1)
                                Spacer()
                                Text("收 \(LedgerMath.fmtMoney(cents: row.received)) · 送 \(LedgerMath.fmtMoney(cents: row.given)) · \(row.count) 笔")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Palette.stone)
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
                }
            }
        }
        .liqianCardSurface()
    }

    /// 场合图标签：标题唯一时原样；同名多本时加日期消歧（与图归组口径对齐）
    private func occasionChartLabel(_ row: OccasionRow) -> String {
        let duplicates = occasionRows.filter { $0.title == row.title }.count > 1
        guard duplicates, !row.date.isEmpty else { return row.title }
        return "\(row.title) · \(LiqianDate.displayString(for: row.date))"
    }

    private var occasionAccessibilityText: String {
        let parts = occasionRows.map {
            "\($0.title)：收 \(LedgerMath.fmtMoney(cents: $0.received))，送 \(LedgerMath.fmtMoney(cents: $0.given))"
        }
        return "场合分布：" + parts.joined(separator: "；")
    }

    // MARK: - 人物洞察

    private var peopleCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingM) {
            cardHeader("往来人物", caption: "按往来总额（收 + 送）取前 10 人")
            if topPeople.isEmpty {
                Text("暂无数据")
                    .font(.subheadline)
                    .foregroundStyle(Palette.stone)
            } else {
                Chart(topPeople) { person in
                    BarMark(
                        x: .value("往来", Double(person.received + person.given) * entrance / 100.0),
                        y: .value("人物", person.name)
                    )
                    .foregroundStyle(Palette.stone.opacity(barOpacity(total: person.received + person.given, in: topPeople.map { $0.received + $0.given })))
                    .cornerRadius(4)
                    .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                        Text(LedgerMath.fmtMoney(cents: person.received + person.given))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Palette.stone)
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine().foregroundStyle(Palette.line)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(axisMoneyText(v))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Palette.stone)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink)
                    }
                }
                .frame(height: CGFloat(topPeople.count) * 36 + 16)
                .accessibilityLabel(peopleAccessibilityText)
            }
        }
        .liqianCardSurface()
    }

    private var peopleAccessibilityText: String {
        let parts = topPeople.map {
            "\($0.name)：往来 \(LedgerMath.fmtMoney(cents: $0.received + $0.given))"
        }
        return "往来人物排行：" + parts.joined(separator: "；")
    }

    // MARK: - 待回清单

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            cardHeader("待回礼", caption: "待回 = 收 − 送的净差额，点名字看详情")
            if pendingPeople.isEmpty {
                HStack(spacing: LiqianMetrics.spacingS) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.primary)
                    Text("没有待回礼，都结清了")
                        .font(.subheadline)
                        .foregroundStyle(Palette.stone)
                }
            } else {
                ForEach(Array(pendingPeople.prefix(8))) { person in
                    Button {
                        personRoute = PeopleView.NameRoute(name: person.name)
                    } label: {
                        HStack(spacing: LiqianMetrics.spacingSM) {
                            VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                                Text(person.name)
                                    .font(.body)
                                    .foregroundStyle(Palette.ink)
                                Text("\(person.relation) · 最近 \(LiqianDate.displayString(for: person.lastDate))")
                                    .font(.caption)
                                    .foregroundStyle(Palette.stone)
                            }
                            Spacer()
                            Text(LedgerMath.fmtMoney(cents: person.pendingCents))
                                .font(.liqianMoney(.body))
                                .foregroundStyle(Palette.ink)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.stone)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if person.id != pendingPeople.prefix(8).last?.id {
                        Divider()
                    }
                }
                if pendingPeople.count > 8 {
                    Text("共 \(pendingPeople.count) 人待回，在「往来」页查看全部")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Palette.stone)
                }
            }
        }
        .liqianCardSurface()
    }

    // MARK: - 金额段分布（v4.7：单笔金额落桶，笔数条形 + 金额标注双口径）

    private var amountBucketCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingM) {
            cardHeader("金额段分布", caption: "按单笔金额分段，条长为笔数")
            if bucketRows.allSatisfy({ $0.count == 0 }) {
                Text("暂无数据")
                    .font(.subheadline)
                    .foregroundStyle(Palette.stone)
            } else {
                Chart(bucketRows) { row in
                    BarMark(
                        x: .value("笔数", Double(row.count) * entrance),
                        y: .value("金额段", row.label)
                    )
                    .foregroundStyle(Palette.stone.opacity(barOpacity(total: row.count, in: bucketRows.map(\.count))))
                    .cornerRadius(4)
                    .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                        Text("\(row.count) 笔 · \(LedgerMath.fmtMoney(cents: row.totalCents))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Palette.stone)
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine().foregroundStyle(Palette.line)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Palette.stone)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink)
                    }
                }
                .frame(height: CGFloat(bucketRows.count) * 36 + 16)
                .accessibilityLabel(bucketAccessibilityText)
            }
        }
        .liqianCardSurface()
    }

    private var bucketAccessibilityText: String {
        let parts = bucketRows.filter { $0.count > 0 }.map {
            "\($0.label)：\($0.count) 笔，合计 \(LedgerMath.fmtMoney(cents: $0.totalCents))"
        }
        return "金额段分布：" + (parts.isEmpty ? "暂无数据" : parts.joined(separator: "；"))
    }

    // MARK: - 年度整表（v4.7：全范围，不随顶部范围切换；净额同比对上一个有数据的年份）

    private var yearTableCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            cardHeader("年度总表", caption: "全部年份 · 不随上方范围切换")
            if yearTableRows.isEmpty {
                Text("暂无数据")
                    .font(.subheadline)
                    .foregroundStyle(Palette.stone)
            } else {
                ForEach(Array(yearTableRows.enumerated()), id: \.element.id) { idx, row in
                    VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                        HStack(spacing: LiqianMetrics.spacingS) {
                            Text(row.year + " 年")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text("\(row.count) 笔 · \(row.occasions) 场")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Palette.stone)
                        }
                        HStack(spacing: LiqianMetrics.spacingS) {
                            Text("收 \(LedgerMath.fmtMoney(cents: row.received))")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Palette.stone)
                            Text("送 \(LedgerMath.fmtMoney(cents: row.given))")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Palette.stone)
                            Spacer()
                            Text("净 \(LedgerMath.fmtMoney(cents: row.net))")
                                .font(.footnote.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Palette.ink)
                            if let delta = row.netDelta {
                                Text("同比 \(delta >= 0 ? "+" : "−")\(LedgerMath.fmtMoney(cents: abs(delta)))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Palette.stone)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(yearRowAccessibilityText(row))
                    if idx != yearTableRows.count - 1 {
                        Divider()
                    }
                }
                Text("同比＝净额与上一个有数据的年份之差。")
                    .font(.caption)
                    .foregroundStyle(Palette.stone)
            }
        }
        .liqianCardSurface()
    }

    private func yearRowAccessibilityText(_ row: LedgerMath.YearAggregate) -> String {
        var text = "\(row.year) 年：收 \(LedgerMath.fmtMoney(cents: row.received))，送 \(LedgerMath.fmtMoney(cents: row.given))，净 \(LedgerMath.fmtMoney(cents: row.net))，共 \(row.count) 笔、\(row.occasions) 场"
        if let delta = row.netDelta {
            text += "，净额同比 \(delta >= 0 ? "多" : "少") \(LedgerMath.fmtMoney(cents: abs(delta)))"
        }
        return text
    }

    // MARK: - 通用小件

    private func cardHeader(_ title: String, caption: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Spacer()
            Text(caption)
                .font(.caption)
                .foregroundStyle(Palette.stone)
        }
    }

    /// 单色阶透明度（StatsView 同口径）：最大值为满色，其余按比例变淡，下限保可读
    private func barOpacity(total: Int, in totals: [Int]) -> Double {
        let maxTotal = totals.max() ?? 0
        guard maxTotal > 0 else { return 1 }
        return 0.35 + 0.65 * Double(total) / Double(maxTotal)
    }

    /// 轴标签紧凑金额（元）：过万用「万」，与图内完整 fmtMoney 标注分工
    private func axisMoneyText(_ yuan: Double) -> String {
        if yuan >= 10_000 {
            let wan = yuan / 10_000
            return (wan == wan.rounded() ? String(format: "%.0f万", wan) : String(format: "%.1f万", wan))
        }
        return String(format: "%.0f", yuan)
    }
}

// MARK: - 占比条（v4.7.1 立项；v5.14 全原生整改：自绘 GeometryReader 分段
// 改 Swift Charts 单行堆叠 BarMark，与同页其余图同框架）

/// 单行占比条：分段宽度＝金额占比，段够宽（≥16%）时段内标百分比；
/// 与卡内条形图上下互补——占比条给「份额」的一眼读数，条形给收/送结构。
/// 段宽由父层按入场进度（entrance）缩放实现生长动画，百分比按原始
/// 占比判定与显示；Reduce Motion 时父层 entrance 恒 1，即瞬时呈现。
/// 旧自绘版的 2pt 段缝不再复刻：堆叠条以段界色差分段（系统图表惯例）。
private struct ShareStackBar: View {
    struct Segment: Identifiable {
        var id: String
        /// 已按入场进度缩放的宽度占比
        var fraction: Double
        /// 原始占比（决定是否段内标注）
        var rawFraction: Double
        var color: Color
        var labelColor: Color
        var percentText: String
    }

    let segments: [Segment]
    let accessibilityText: String

    var body: some View {
        Group {
            if segments.isEmpty {
                Color.clear
            } else {
                Chart(segments) { seg in
                    BarMark(
                        x: .value("占比", max(seg.fraction, 0)),
                        y: .value("占比条", "占比")
                    )
                    .foregroundStyle(seg.color)
                    .annotation(position: .overlay) {
                        if seg.rawFraction >= 0.16 {
                            Text(seg.percentText)
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(seg.labelColor)
                        }
                    }
                }
                .chartXScale(domain: 0.0...1.0)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .frame(height: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

// MARK: - 范围档位

private enum ChartScope: String, CaseIterable, Identifiable {
    case all
    case last12
    case year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "全部"
        case .last12: return "近 12 个月"
        case .year: return "自然年"
        }
    }

    func caption(year: String) -> String {
        switch self {
        case .all: return "全部时间"
        case .last12: return "近 12 个月"
        case .year: return year + " 年"
        }
    }
}

// MARK: - 关系人物列表（v4.7 钻取落点：环图明细行 → 本页 → 人物详情）

/// 某关系下的往来人物（入参已按该关系口径聚合），按往来总额倒序；
/// 点行经 personRoute 进人物详情（与待回清单同一条 NameRoute 通道）。
private struct RelationPeopleList: View {
    let relation: String
    let people: [PersonSummary]
    @Binding var personRoute: PeopleView.NameRoute?

    private var sorted: [PersonSummary] {
        people.sorted { ($0.received + $0.given) > ($1.received + $1.given) }
    }

    var body: some View {
        List {
            if sorted.isEmpty {
                Text("这个关系下暂时没有往来记录")
                    .font(.subheadline)
                    .foregroundStyle(Palette.stone)
            } else {
                ForEach(sorted) { person in
                    Button {
                        personRoute = PeopleView.NameRoute(name: person.name)
                    } label: {
                        HStack(spacing: LiqianMetrics.spacingSM) {
                            VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                                Text(person.name)
                                    .font(.body)
                                    .foregroundStyle(Palette.ink)
                                Text("收 \(LedgerMath.fmtMoney(cents: person.received)) · 送 \(LedgerMath.fmtMoney(cents: person.given)) · \(person.count) 笔")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Palette.stone)
                            }
                            Spacer()
                            if person.hasPending {
                                Text("待回 \(LedgerMath.fmtMoney(cents: person.pendingCents))")
                                    .font(.footnote.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(Palette.primary)
                            }
                            Text(LedgerMath.fmtMoney(cents: person.received + person.given))
                                .font(.liqianMoney(.body))
                                .foregroundStyle(Palette.ink)
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
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle(relation)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - KPI 滚动金额（滚动策略 v5.4：按「指标＋范围」存档上次显示值，
// 值真变了才滚、没变静态直出——旧版每次进页都从 0 滚一遍被用户点名。
// 策略本体在 LiqianCore/RollingMoneyStore（可单测）；Reduce Motion
// 仍直出终值；暗色模式字重降一档——质感审计第 2/4 条）

private struct RollingMoneyText: View {
    let cents: Int
    var style: Font.TextStyle = .title2
    /// 存档键的指标部分（同一指标在不同范围各存一份，互不串扰）
    var rollKey: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// 本轮滚动的起点值
    @State private var fromValue: Double = 0
    /// 已落定值：无动画进行时显示它（不能直接读 cents——onChange 触发时
    /// cents 已是新值，拿它当「当前显示」会让二次切换失去滚动起点）
    @State private var settledValue: Double = 0
    @State private var startDate: Date?
    private let duration: TimeInterval = 0.9

    /// 完整存档键：指标＋当前范围（自然年档带年份）
    private var storageKey: String { "\(rollKey)" }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: startDate == nil)) { context in
            Text(LedgerMath.fmtMoney(cents: Int(displayedValue(at: context.date).rounded())))
                .font(.liqianMoney(style, dark: colorScheme == .dark))
                .foregroundStyle(Palette.ink)
        }
        .onAppear { evaluate() }
        .onChange(of: cents) { _, _ in evaluate() }
        .onChange(of: storageKey) { _, _ in evaluate() }
    }

    private func displayedValue(at date: Date) -> Double {
        guard let startDate else { return settledValue }
        let t = date.timeIntervalSince(startDate) / duration
        if t >= 1 { return Double(cents) }
        if t <= 0 { return fromValue }
        let eased = 1 - pow(1 - t, 3) // easeOutCubic：先快后慢
        return fromValue + (Double(cents) - fromValue) * eased
    }

    /// 按存档决策：没变 → 静态直出；变了 → 从存档值（或正在显示的值）滚起，
    /// 并立刻把新值落档（中途退出也不重复滚同一变化）
    private func evaluate() {
        let plan = RollingMoneyStore.plan(metricKey: storageKey, currentCents: cents)
        guard plan.rolls else {
            settledValue = Double(cents)
            startDate = nil
            return
        }
        RollingMoneyStore.store(cents: cents, metricKey: storageKey)
        if reduceMotion {
            settledValue = Double(cents)
            startDate = nil
            return
        }
        // 正在滚的中途又变值：从当下显示值续滚，不跳回存档旧值
        fromValue = startDate == nil ? Double(plan.fromCents) : displayedValue(at: Date())
        let start = Date()
        startDate = start
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration + 0.1))
            if startDate == start {
                settledValue = Double(cents)
                startDate = nil
            }
        }
    }
}

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

    @State private var scope: ChartScope = .all
    @State private var selectedYear = ""
    @State private var personRoute: PeopleView.NameRoute?
    /// 入场进度 0→1：驱动柱条生长与环图扫入（Reduce Motion 时恒 1）
    @State private var entrance: Double = 0
    @Namespace private var rangeNamespace

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

    /// 趋势图的 12 个月窗口：全部/近12个月档取最近 12 个月（缺月补零，轴才连续）；
    /// 自然年档取该年 1–12 月。聚合只吃 scoped 数据，全部档的窗口外月份不进图
    /// （全史由下方年度汇总承载，口径在卡内注明）。
    private var monthBuckets: [MonthBucket] {
        let cal = Calendar.current
        var keys: [String] = []
        switch scope {
        case .year:
            keys = (1...12).map { String(format: "%@-%02d", effectiveYear, $0) }
        case .all, .last12:
            let now = Date()
            for back in stride(from: 11, through: 0, by: -1) {
                let d = cal.date(byAdding: .month, value: -back, to: now) ?? now
                let c = cal.dateComponents([.year, .month], from: d)
                keys.append(String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0))
            }
        }
        let multiYear = Set(keys.map { String($0.prefix(4)) }).count > 1
        return keys.map { key in
            var recv = 0
            var giv = 0
            for e in scopedSnapshots where String(e.date.prefix(7)) == key && !e.isPendingSend {
                if e.direction == LiqianConstants.received { recv += e.amountCents }
                else if e.direction == LiqianConstants.given { giv += e.amountCents }
            }
            let month = Int(key.suffix(2)) ?? 0
            let label = multiYear
                ? "\(key.suffix(2))月·\(String(key.prefix(4)).suffix(2))"
                : "\(month)月"
            return MonthBucket(key: key, label: label, received: recv, given: giv)
        }
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
                        relationCard
                        occasionCard
                        peopleCard
                        pendingCard
                    }
                }
                .padding(.horizontal, LiqianMetrics.spacingL)
                .padding(.vertical, LiqianMetrics.spacingSM)
            }
            .background(Palette.pageBG.ignoresSafeArea())
            .navigationTitle("图表")
            .navigationDestination(item: $personRoute) { route in
                PersonDetailView(name: route.name)
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
            withAnimation(.easeOut(duration: 0.7)) { entrance = 1 }
        }
    }

    // MARK: - 范围选择（滑块式：matchedGeometry 指示器 + 选择触感，贴手无迟滞弹簧）

    private var rangeSelector: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            HStack(spacing: 3) {
                ForEach(ChartScope.allCases) { item in
                    Button {
                        if scope != item {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                                scope = item
                            }
                        }
                    } label: {
                        Text(item.label)
                            .font(.subheadline.weight(scope == item ? .semibold : .regular))
                            .foregroundStyle(scope == item ? Palette.ink : Palette.stone)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background {
                                if scope == item {
                                    Capsule()
                                        .fill(Palette.surface)
                                        .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
                                        .matchedGeometryEffect(id: "rangePill", in: rangeNamespace)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Palette.stone.opacity(0.12), in: Capsule())
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
            Text("在「首页」记下收礼或随礼后，这里会生成总览、收送趋势、关系分布与人物洞察。示例礼簿的数据不计入统计。")
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
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: LiqianMetrics.spacingM
            ) {
                moneyMetric(label: "累计收", cents: totalReceived)
                moneyMetric(label: "累计送", cents: totalGiven)
                moneyMetric(label: "净往来（收 − 送）", cents: totalReceived - totalGiven)
                moneyMetric(
                    label: "待回礼 · \(pendingPeople.count) 人",
                    cents: pendingPeople.reduce(0) { $0 + $1.pendingCents }
                )
                countMetric(label: "往来人数", value: people.count, unit: "人")
                countMetric(label: "场次（礼簿）", value: Set(scopedRecords.map(\.ledgerID)).count, unit: "场")
            }
        }
        .liqianCardSurface()
    }

    private func moneyMetric(label: String, cents: Int) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Palette.stone)
            RollingMoneyText(cents: cents, style: .title2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func countMetric(label: String, value: Int, unit: String) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Palette.stone)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(value)")
                    .font(.system(.title2, weight: colorScheme == .dark ? .medium : .semibold)
                        .monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText(value: Double(value)))
                Text(unit)
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Chart(monthBuckets) { bucket in
                BarMark(
                    x: .value("月份", bucket.label),
                    y: .value("收礼", Double(bucket.received) * entrance / 100.0),
                    position: .by(.value("方向", "收礼"))
                )
                .foregroundStyle(by: .value("方向", "收礼"))
                .cornerRadius(2)
                BarMark(
                    x: .value("月份", bucket.label),
                    y: .value("随礼", Double(bucket.given) * entrance / 100.0),
                    position: .by(.value("方向", "随礼"))
                )
                .foregroundStyle(by: .value("方向", "随礼"))
                .cornerRadius(2)
                if bucket.total > 0 {
                    PointMark(
                        x: .value("月份", bucket.label),
                        y: .value("合计", Double(max(bucket.received, bucket.given)) / 100.0)
                    )
                    .annotation(position: .top, spacing: 2) {
                        Text(LedgerMath.fmtMoney(cents: bucket.total))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Palette.stone)
                    }
                    .opacity(0)
                }
            }
            .chartForegroundStyleScale(["收礼": Palette.primary, "随礼": givenColor])
            .chartLegend(.hidden)
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
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Palette.stone)
                }
            }
            .frame(height: 190)
            .accessibilityLabel(trendAccessibilityText)

            if scope == .all {
                Text("趋势图显示最近 12 个月；更早的往来见下方按年汇总。")
                    .font(.caption)
                    .foregroundStyle(Palette.stone)
            }

            if !yearRows.isEmpty {
                Divider()
                Text("按年汇总")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                VStack(spacing: LiqianMetrics.spacingS) {
                    ForEach(yearRows) { row in
                        HStack(spacing: LiqianMetrics.spacingS) {
                            Text(row.year + " 年")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 52, alignment: .leading)
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

    private var givenColor: Color { Palette.ink.opacity(0.42) }

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
                            style: .title3
                        )
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(relationAccessibilityText)
                VStack(spacing: LiqianMetrics.spacingS) {
                    ForEach(Array(relationRows.enumerated()), id: \.element.id) { idx, row in
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
                        }
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

    private var relationAccessibilityText: String {
        let parts = relationRows.map {
            "\($0.relation) \($0.count) 笔，往来 \(LedgerMath.fmtMoney(cents: $0.total))"
        }
        return "关系分布：" + parts.joined(separator: "；")
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
                        y: .value("场合", row.title)
                    )
                    .foregroundStyle(Palette.primary.opacity(barOpacity(total: row.total, in: occasionRows.map(\.total))))
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
                        }
                    }
                }
            }
        }
        .liqianCardSurface()
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
                    .foregroundStyle(Palette.primary.opacity(barOpacity(total: person.received + person.given, in: topPeople.map { $0.received + $0.given })))
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

// MARK: - KPI 滚动金额（入场从 0、切换从旧值，先快后慢 ease-out；
// Reduce Motion 时瞬时落值；暗色模式字重降一档——质感审计第 2/4 条）

private struct RollingMoneyText: View {
    let cents: Int
    var style: Font.TextStyle = .title2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// 本轮滚动的起点值（入场为 0，切换为当下显示值）
    @State private var fromValue: Double = 0
    /// 已落定值：无动画进行时显示它（不能直接读 cents——onChange 触发时
    /// cents 已是新值，拿它当「当前显示」会让二次切换失去滚动起点）
    @State private var settledValue: Double = 0
    @State private var startDate: Date?
    private let duration: TimeInterval = 0.9

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: startDate == nil)) { context in
            Text(LedgerMath.fmtMoney(cents: Int(displayedValue(at: context.date).rounded())))
                .font(.system(style, weight: colorScheme == .dark ? .medium : .semibold)
                    .monospacedDigit())
                .foregroundStyle(Palette.ink)
        }
        .onAppear { beginRoll(from: 0) }
        .onChange(of: cents) { _, _ in beginRoll(from: displayedValue(at: Date())) }
    }

    private func displayedValue(at date: Date) -> Double {
        guard let startDate else { return settledValue }
        let t = date.timeIntervalSince(startDate) / duration
        if t >= 1 { return Double(cents) }
        if t <= 0 { return fromValue }
        let eased = 1 - pow(1 - t, 3) // easeOutCubic：先快后慢
        return fromValue + (Double(cents) - fromValue) * eased
    }

    private func beginRoll(from: Double) {
        if reduceMotion {
            settledValue = Double(cents)
            startDate = nil
        } else {
            fromValue = from
            let start = Date()
            startDate = start
            // 滚完落定并停表，避免 TimelineView 长期空转（startDate 被新一轮
            // 滚动替换时不误停新动画）
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(duration + 0.1))
                if startDate == start {
                    settledValue = Double(cents)
                    startDate = nil
                }
            }
        }
    }
}

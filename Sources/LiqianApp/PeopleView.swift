import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

struct PeopleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @State private var query = ""
    @State private var personRoute: NameRoute?
    @State private var ledgerRoute: Ledger?
    @State private var prepToDelete: GiftRecord?
    @State private var showSampleDone = false
    @State private var showAdvisor = false
    /// 小组件人物深链（v4.5）：ContentView 收到 liqian://person/<姓名> 后
    /// 切到本页并把姓名放进这个绑定，本页消费后置路由并清空绑定
    @Binding private var deepLinkPerson: String?

    init(deepLinkPerson: Binding<String?> = .constant(nil)) {
        _deepLinkPerson = deepLinkPerson
    }

    /// 备礼左滑结果的触感（v4.4）：删除＝警告、标记已送出＝成功，
    /// 此前两条路径都是静默改数（触感审计补齐）
    @State private var prepDeleteTrigger = 0
    @State private var prepSentTrigger = 0

    /// 人物详情路由（按姓名）
    struct NameRoute: Identifiable, Hashable {
        let name: String
        var id: String { name }
    }

    private var summaries: [PersonSummary] {
        LedgerMath.people(from: AppSupport.snapshots(records: records, ledgers: ledgers))
    }

    /// 备礼清单数据源：全部待送出记录，按计划日期（记录 date）升序
    private var pendingSends: [GiftRecord] {
        records
            .filter { $0.isPendingSend }
            .sorted { $0.date < $1.date }
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
                if !searching {
                    Section {
                        Button {
                            showAdvisor = true
                        } label: {
                            HStack(spacing: LiqianMetrics.spacingS) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(Palette.primary)
                                Text("问账")
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                Text("问一句，查全账")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.stone)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Palette.stone)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !searching && !pendingSends.isEmpty {
                    Section {
                        ForEach(pendingSends) { r in prepRow(r) }
                    } header: {
                        Text("备礼清单")
                    } footer: {
                        Text("还没送出的礼记在这里，送出后在记录里改为已送出。")
                    }
                }

                if searching {
                    Section("亲友") {
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
                        Section {
                            ContentUnavailableView {
                                Label("还没有往来记录", systemImage: "person.2")
                            } description: {
                                Text("先去礼簿里记一笔。")
                            } actions: {
                                Button("生成示例数据") {
                                    if SampleData.generate(into: modelContext) {
                                        showSampleDone = true
                                    }
                                }
                                .foregroundStyle(Palette.primary)
                                .frame(minHeight: LiqianMetrics.minTapTarget)
                            }
                            .padding(.vertical, LiqianMetrics.spacingL)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    } else {
                        Section {
                            ForEach(summaries) { p in personRow(p) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.pageBG.ignoresSafeArea())
            // 行增删动画（v4.4）：人物与备礼行集合变化时平滑过渡
            .animation(reduceMotion ? nil : .snappy, value: summaries.map(\.name))
            .animation(reduceMotion ? nil : .snappy, value: pendingSends.map(\.id))
            .sensoryFeedback(.warning, trigger: prepDeleteTrigger)
            .sensoryFeedback(.success, trigger: prepSentTrigger)
            .navigationTitle("往来")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $query, prompt: "姓名、礼簿或事由")
            .alert(
                "删除这笔备礼？",
                isPresented: Binding(
                    get: { prepToDelete != nil },
                    set: { if !$0 { prepToDelete = nil } }
                )
            ) {
                Button("删除", role: .destructive) {
                    if let r = prepToDelete { deletePrep(r) }
                    prepToDelete = nil
                }
                Button("取消", role: .cancel) { prepToDelete = nil }
            } message: {
                Text("删除后 30 天内可以在「我的 → 最近删除」恢复。")
            }
            .navigationDestination(item: $personRoute) { route in
                PersonDetailView(name: route.name)
            }
            .navigationDestination(item: $ledgerRoute) { ledger in
                LedgerDetailView(ledger: ledger)
            }
            .navigationDestination(isPresented: $showAdvisor) {
                AdvisorView()
            }
            .onAppear { consumeDeepLinkPerson() }
            .onChange(of: deepLinkPerson) { _, _ in consumeDeepLinkPerson() }
            .alert("示例数据已生成", isPresented: $showSampleDone) {
                Button("好") {}
            } message: {
                Text("「首页」多了两本示例礼簿，「往来」页能看到往来差额和备礼清单的效果。")
            }
        }
    }

    /// 备礼清单行：待送出的礼，点行进人物详情去处理；
    /// 左滑删除（进最近删除）／标记已送出行（v2.5 包 3）
    /// 消费小组件人物深链：姓名还在往来名单里才置路由；人已不在（记录删光）
    /// 就静默作罢，不硬跳一个空详情。消费完立即清空绑定防重复触发。
    private func consumeDeepLinkPerson() {
        guard let name = deepLinkPerson else { return }
        deepLinkPerson = nil
        guard summaries.contains(where: { $0.name == name }) else { return }
        query = ""
        personRoute = NameRoute(name: name)
    }

    private func prepRow(_ r: GiftRecord) -> some View {
        Button {
            personRoute = NameRoute(name: r.person)
        } label: {
            HStack(spacing: LiqianMetrics.spacingS) {
                Text(r.person)
                    .foregroundStyle(Palette.ink)
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                prepToDelete = r
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                markPrepSent(r)
            } label: {
                Label("已送出", systemImage: "checkmark.circle")
            }
            .tint(Palette.primary)
        }
    }

    /// 标记已送出：与记录表单里改状态同一口径（status 置已送出，开始计入差额）
    private func markPrepSent(_ r: GiftRecord) {
        r.status = LiqianConstants.sentStatus
        try? modelContext.save()
        prepSentTrigger += 1
    }

    /// 删除备礼：与详情页删记录同语义——快照进最近删除，30 天可恢复
    private func deletePrep(_ r: GiftRecord) {
        TrashStore.archive(record: r)
        modelContext.delete(r)
        try? modelContext.save()
        prepDeleteTrigger += 1
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Palette.stone)
    }

    /// 人物行（v2.4 定版结构）：左＝姓名＋全量数字次行；
    /// 右＝状态金额单行不换行。待回与差额同源（LedgerMath 定版）：
    /// 差额 > 0 时主行即「待回 ¥X」（朱砂），不再另挂一行同义的「待回礼」；
    /// 差额 < 0 显示「多随 ¥X」（墨色），差额 = 0 显示「已结清」。
    private func personRow(_ p: PersonSummary) -> some View {
        Button {
            personRoute = NameRoute(name: p.name)
        } label: {
            HStack(spacing: LiqianMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                    Text(p.name)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text("收 \(LedgerMath.fmtMoney(cents: p.received)) · 随 \(LedgerMath.fmtMoney(cents: p.given)) · \(p.count) 笔 · 最近 \(LiqianDate.displayString(for: p.lastDate))")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                        .lineLimit(1)
                }
                Spacer()
                Text(statusText(p))
                    .font(.liqianMoney(.title3))
                    .foregroundStyle(statusColor(p))
                    .lineLimit(1)
                    .layoutPriority(1)
                    // 差额变化数字滚动过渡（v4.4）：待回/多随金额变更不再整字跳变
                    .contentTransition(.numericText())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusText(_ p: PersonSummary) -> String {
        if p.balance > 0 { return "待回 \(LedgerMath.fmtMoney(cents: p.pendingCents))" }
        if p.balance < 0 { return "多随 \(LedgerMath.fmtMoney(cents: -p.balance))" }
        return "已结清"
    }

    private func statusColor(_ p: PersonSummary) -> Color {
        if p.balance > 0 { return Palette.primary } // 待回是行动提示，用强调色
        if p.balance < 0 { return Palette.ink }
        return Palette.stone
    }

    private func ledgerRow(_ l: Ledger) -> some View {
        Button {
            ledgerRoute = l
        } label: {
            HStack(spacing: LiqianMetrics.spacingSM) {
                ZStack {
                    RoundedRectangle(cornerRadius: LiqianMetrics.tagCorner)
                        .fill(l.isBai ? Palette.baiPrimaryFill : Palette.primaryFill)
                    Text(l.type.map { String($0) }.joined(separator: "\n"))
                        .font(.liqianSerifFixed(size: 12))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(1)
                }
                .frame(width: 30, height: 44)
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                    Text(l.title)
                        .foregroundStyle(Palette.ink)
                    Text("\(l.type) · \(LiqianDate.displayString(for: l.date))")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.stone)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}

/// 备礼清单独立页（v2.5 包 5：「我的 → 记录」入口落点）：与「往来」页顶部
/// 同源同规——全部待送出按计划日期升序，行形态与侧滑（删除进最近删除／
/// 标记已送出）一致，点行进人物详情。本页自带 @Query，不依赖往来页状态。
struct PrepListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var records: [GiftRecord]
    @State private var personRoute: PeopleView.NameRoute?
    @State private var prepToDelete: GiftRecord?
    /// 与往来页同口径的左滑结果触感（v4.4）：删除＝警告、已送出＝成功
    @State private var prepDeleteTrigger = 0
    @State private var prepSentTrigger = 0

    private var pendingSends: [GiftRecord] {
        records
            .filter { $0.isPendingSend }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        List {
            if pendingSends.isEmpty {
                ContentUnavailableView {
                    Label("没有待送出的礼", systemImage: "gift")
                } description: {
                    Text("记随礼时选「待送出」，会记在这里。")
                }
                .padding(.vertical, LiqianMetrics.spacingL)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(pendingSends) { r in
                        row(r)
                    }
                } footer: {
                    Text("还没送出的礼记在这里，送出后在记录里改为已送出。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .animation(reduceMotion ? nil : .snappy, value: pendingSends.map(\.id))
        .sensoryFeedback(.warning, trigger: prepDeleteTrigger)
        .sensoryFeedback(.success, trigger: prepSentTrigger)
        .navigationTitle("备礼清单")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $personRoute) { route in
            PersonDetailView(name: route.name)
        }
        .alert(
            "删除这笔备礼？",
            isPresented: Binding(
                get: { prepToDelete != nil },
                set: { if !$0 { prepToDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let r = prepToDelete { deletePrep(r) }
                prepToDelete = nil
            }
            Button("取消", role: .cancel) { prepToDelete = nil }
        } message: {
            Text("删除后 30 天内可以在「我的 → 最近删除」恢复。")
        }
    }

    private func row(_ r: GiftRecord) -> some View {
        Button {
            personRoute = PeopleView.NameRoute(name: r.person)
        } label: {
            HStack(spacing: LiqianMetrics.spacingS) {
                Text(r.person)
                    .foregroundStyle(Palette.ink)
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                prepToDelete = r
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                markPrepSent(r)
            } label: {
                Label("已送出", systemImage: "checkmark.circle")
            }
            .tint(Palette.primary)
        }
    }

    private func markPrepSent(_ r: GiftRecord) {
        r.status = LiqianConstants.sentStatus
        try? modelContext.save()
        prepSentTrigger += 1
    }

    private func deletePrep(_ r: GiftRecord) {
        TrashStore.archive(record: r)
        modelContext.delete(r)
        try? modelContext.save()
        prepDeleteTrigger += 1
    }
}

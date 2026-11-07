import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import LiqianCore
import LiqianDesign

/// 「我的」（v3 整合归档）：iOS 设置式结构——
/// 顶部总览卡（全时段总收/总送/往来人数，墨色数字）+ 待回礼卡，
/// 其余按「统计与报告 / 数据 / 隐私与安全 / 关于」分组收纳；
/// 统计明细（年度/事由/排行/关系图）移入 StatsView，本页只留入口。
struct MeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]

    @State private var personRoute: PeopleView.NameRoute?
    @State private var csvURL: URL?
    @State private var exportDocument = JSONBackupDocument(data: Data())
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingImport: (ledgers: [BackupLedger], records: [BackupRecord])?
    @State private var showImportConfirm = false
    @State private var infoTitle = ""
    @State private var infoMessage = ""
    @State private var showInfo = false
    @State private var importTrigger = 0
    @AppStorage("privacyLock") private var privacyLock = false
    @AppStorage("hostName") private var hostName = ""

    private var snapshots: [EntrySnapshot] {
        AppSupport.snapshots(records: records, ledgers: ledgers)
    }

    /// 全时段总收（待送出不计，口径同 LedgerMath.yearSummary）
    private var totalReceived: Int {
        snapshots
            .filter { !$0.isPendingSend && $0.direction == LiqianConstants.received }
            .reduce(0) { $0 + $1.amountCents }
    }

    /// 全时段总送（待送出不计）
    private var totalGiven: Int {
        snapshots
            .filter { !$0.isPendingSend && $0.direction == LiqianConstants.given }
            .reduce(0) { $0 + $1.amountCents }
    }

    private var peopleCount: Int {
        LedgerMath.people(from: snapshots).count
    }

    private var pendingPeople: [PersonSummary] {
        LedgerMath.people(from: snapshots).filter { $0.hasPending }
    }

    private var csvFingerprint: String {
        "\(records.count)-\(ledgers.count)-\(records.reduce(0) { $0 + $1.amountCents })"
    }

    var body: some View {
        NavigationStack {
            List {
                asCardRow(overviewCard)
                asCardRow(pendingCard)

                groupHeader("统计与报告")
                asCardRow(statsGroupCard)

                groupHeader("数据")
                asCardRow(dataGroupCard)

                groupHeader("AI 智能助手")
                asCardRow(aiGroupCard)

                groupHeader("隐私与安全")
                asCardRow(privacyCard)

                groupHeader("关于")
                asCardRow(aboutCard)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $personRoute) { route in
                PersonDetailView(name: route.name)
            }
            .task(id: csvFingerprint) {
                csvURL = AppSupport.writeTempFile(
                    name: "礼钱账本导出.csv",
                    content: AppSupport.csvText(records: records, ledgers: ledgers)
                )
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "礼钱账本备份"
            ) { result in
                if case .failure = result {
                    showInfo(title: "导出失败", message: "备份没能存下来，再试一次。")
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .confirmationDialog("覆盖恢复？", isPresented: $showImportConfirm, titleVisibility: .visible) {
                Button("覆盖恢复", role: .destructive) { performImport() }
                Button("取消", role: .cancel) {}
            } message: {
                if let p = pendingImport {
                    Text("备份里有 \(p.ledgers.count) 本礼簿、\(p.records.count) 笔记录。现在手机里有 \(ledgers.count) 本礼簿、\(records.count) 笔记录，恢复后会被全部覆盖，覆盖了就回不来了。")
                }
            }
            .alert(infoTitle, isPresented: $showInfo) {
                Button("好") {}
            } message: {
                Text(infoMessage)
            }
            .sensoryFeedback(.success, trigger: importTrigger)
        }
    }

    // MARK: - 总览与待回礼

    /// 总览卡：全时段总收/总送/往来人数，大数字一律墨色（v3 纪律）
    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                overviewStat(label: "总收礼", value: LedgerMath.fmtMoney(cents: totalReceived))
                Spacer()
                overviewStat(label: "总随礼", value: LedgerMath.fmtMoney(cents: totalGiven))
                Spacer()
                overviewStat(label: "往来亲友", value: "\(peopleCount) 位")
            }
            Text("\(ledgers.count) 本礼簿 · \(records.count) 笔记录（待送出不计入收支）")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.stone)
        }
        .cardSurface()
    }

    private func overviewStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.liqianMoney(size: 20))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Palette.stone)
        }
    }

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("还没回的礼")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.ink)
            if pendingPeople.isEmpty {
                Text("没有欠着的人情，轻松。")
                    .foregroundStyle(Palette.stone)
            } else {
                ForEach(pendingPeople) { p in
                    Button {
                        personRoute = PeopleView.NameRoute(name: p.name)
                    } label: {
                        HStack {
                            Text(p.name)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            // 待回礼是行动提示，保留朱砂（v3 纪律的明示例外）
                            Text(LedgerMath.fmtMoney(cents: p.pendingCents))
                                .font(.liqianMoney(size: 15))
                                .foregroundStyle(Palette.primary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.stone)
                        }
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text("按「最近一次收礼之后还没送出」自动算的，不用手动标。")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.stone)
            }
        }
        .cardSurface()
    }

    // MARK: - 分组：统计与报告

    private var statsGroupCard: some View {
        VStack(spacing: 0) {
            NavigationLink {
                StatsView()
            } label: {
                entryRow(
                    icon: "chart.bar.xaxis",
                    title: "统计",
                    subtitle: "年度、事由、往来排行与关系分布"
                )
            }
            .buttonStyle(.plain)
            groupDivider
            NavigationLink {
                AnnualReportView()
            } label: {
                entryRow(
                    icon: "chart.bar.doc.horizontal",
                    title: "人情年度报告",
                    subtitle: "按年看往来，做一张能发给家人的报告图",
                    iconColor: Palette.primary
                )
            }
            .buttonStyle(.plain)
        }
        .cardSurface(padding: 0)
    }

    // MARK: - 分组：数据

    private var dataGroupCard: some View {
        VStack(spacing: 0) {
            csvEntryRow
            groupDivider
            Button {
                exportDocument = JSONBackupDocument(
                    data: LiqianBackup.makeBackup(ledgers: ledgers, records: records)
                )
                showExporter = true
            } label: {
                entryRow(
                    icon: "tray.and.arrow.up",
                    title: "导出备份（JSON）",
                    subtitle: "全量备份：礼簿和记录都在，换手机靠它恢复",
                    chevron: false
                )
            }
            .buttonStyle(.plain)
            groupDivider
            Button {
                showImporter = true
            } label: {
                entryRow(
                    icon: "tray.and.arrow.down",
                    title: "从备份恢复",
                    subtitle: "选一个备份文件，覆盖现在的数据",
                    chevron: false
                )
            }
            .buttonStyle(.plain)
            groupDivider
            NavigationLink {
                TrashView()
            } label: {
                entryRow(
                    icon: "trash",
                    title: "回收站",
                    subtitle: "删掉的礼簿和记录，30 天内能恢复"
                )
            }
            .buttonStyle(.plain)
            groupDivider
            Button {
                toggleSamples()
            } label: {
                entryRow(
                    icon: "sparkles",
                    title: "示例数据",
                    subtitle: hasSamples ? "已生成示例礼簿，点这里清除" : "生成两本示例礼簿，先看看效果",
                    chevron: false
                )
            }
            .buttonStyle(.plain)
            groupDivider
            NavigationLink {
                HostNameEditView()
            } label: {
                entryRow(
                    icon: "signature",
                    title: "礼谱落款姓名",
                    subtitle: hostName.isEmpty
                        ? "还没设置，礼谱落款先用「主家谨识」"
                        : "礼谱封面、谱序落款与主家印用「\(hostName)」"
                )
            }
            .buttonStyle(.plain)
        }
        .cardSurface(padding: 0)
    }

    private var csvEntryRow: some View {
        Group {
            if let csvURL {
                ShareLink(item: csvURL) {
                    entryRow(
                        icon: "tablecells",
                        title: "导出 CSV",
                        subtitle: "全部记录导出成表格，Excel 能打开",
                        chevron: false
                    )
                }
                .buttonStyle(.plain)
            } else {
                entryRow(
                    icon: "tablecells",
                    title: "导出 CSV",
                    subtitle: "全部记录导出成表格，Excel 能打开",
                    chevron: false
                )
                .opacity(0.5)
            }
        }
    }

    private var hasSamples: Bool { SampleData.hasSamples(ledgers: ledgers) }

    /// 示例数据开关：生成两本示例礼簿看效果，看完一键清掉（不碰真实数据）
    private func toggleSamples() {
        if hasSamples {
            SampleData.clearSamples(ledgers: ledgers, records: records, in: modelContext)
            showInfo(title: "示例数据已清除", message: "两本示例礼簿和里面的记录都清掉了，你自己的数据没动。")
        } else {
            SampleData.generate(into: modelContext)
            showInfo(title: "示例数据已生成", message: "「礼簿」页多了两本示例礼簿，人情页能看到往来差额和备礼清单的效果。")
        }
    }

    // MARK: - 分组：AI 智能助手

    private var aiGroupCard: some View {
        NavigationLink {
            AISettingsView()
        } label: {
            entryRow(
                icon: "wand.and.stars",
                title: "AI 智能助手",
                subtitle: aiStatusText,
                iconColor: Palette.primary
            )
        }
        .buttonStyle(.plain)
        .cardSurface(padding: 0)
    }

    /// AI 状态小字：没 Key / 已停用 / 已启用，三态说清
    private var aiStatusText: String {
        switch AIAccess.readiness() {
        case .noKey:
            return "填你自己的 DeepSeek Key，用 AI 解析账目文字、生成贺词"
        case .notEnabled:
            return "Key 已填，开关还没打开"
        case .ready:
            return "已启用：智能解析、一句话记账、贺词生成"
        }
    }

    // MARK: - 分组：隐私与安全

    /// 隐私锁：开启后冷启动与回前台（>30 秒）要先解锁，后台预览模糊（逻辑在 ContentView）
    private var privacyCard: some View {
        Toggle(isOn: $privacyLock) {
            HStack(spacing: 12) {
                Image(systemName: "faceid")
                    .foregroundStyle(Palette.ink)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("隐私锁")
                        .foregroundStyle(Palette.ink)
                    Text("打开 App、从后台回来超过半分钟，都要先用 Face ID 或密码解锁；切到后台时内容会模糊。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.stone)
                }
            }
        }
        .tint(Palette.primary)
        .frame(minHeight: LiqianMetrics.minTapTarget)
        .cardSurface()
    }

    // MARK: - 分组：关于

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("版本")
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("原生版 v1.0")
                    .foregroundStyle(Palette.stone)
            }
            Divider().overlay(Palette.hairline)
            Text("数据只存在这台手机上，不联网、不上传。换手机或重装前，先用上面「数据」里的导出备份存一份。")
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.stone)
                .lineSpacing(5)
            Text("备份与旧版（Flutter 版）互通：两边导出的 JSON 备份可以互相恢复。")
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.stone)
                .lineSpacing(5)
        }
        .cardSurface()
    }

    // MARK: - 分组零件

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.stone)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 2, trailing: 16))
    }

    private var groupDivider: some View {
        Divider()
            .overlay(Palette.hairline)
            .padding(.leading, 52)
    }

    /// 设置式入口行：图标 + 标题/副标题 + 右侧值或箭头
    private func entryRow(
        icon: String,
        title: String,
        subtitle: String? = nil,
        iconColor: Color = Palette.ink,
        chevron: Bool = true
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.stone)
                }
            }
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.stone)
            }
        }
        .padding(.horizontal, LiqianMetrics.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: LiqianMetrics.minTapTarget)
        .contentShape(Rectangle())
    }

    // MARK: - 导入

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure = result {
                showInfo(title: "备份文件有问题", message: "这个文件读不了，或者不是礼钱账本的备份。数据没有动。")
            }
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            pendingImport = try LiqianBackup.parseBackup(data)
            showImportConfirm = true
        } catch {
            showInfo(title: "备份文件有问题", message: "这个文件读不了，或者不是礼钱账本的备份。数据没有动。")
        }
    }

    private func performImport() {
        guard let p = pendingImport else { return }
        for r in records { modelContext.delete(r) }
        for l in ledgers { modelContext.delete(l) }
        // 备份里的 id 是字符串：原生备份是 UUID 串可直转；
        // Flutter 旧备份是时间戳串，转不成 UUID 就新发一个，并按账本逐个建映射保证记录挂得上
        var idMap: [String: UUID] = [:]
        for bl in p.ledgers {
            let newID = bl.idUUID ?? UUID()
            idMap[bl.id] = newID
            modelContext.insert(
                Ledger(id: newID, title: bl.title, type: bl.type, date: bl.date, note: bl.note)
            )
        }
        var importedRecords = 0
        for br in p.records {
            guard let lid = idMap[br.ledgerId] else { continue }
            modelContext.insert(
                GiftRecord(
                    id: br.idUUID ?? UUID(),
                    ledgerID: lid,
                    person: br.person,
                    relation: br.relation,
                    amountCents: br.amountCents,
                    direction: br.direction,
                    method: br.method,
                    note: br.note,
                    date: br.date,
                    status: br.status,
                    returned: br.returned
                )
            )
            importedRecords += 1
        }
        try? modelContext.save()
        importTrigger += 1
        pendingImport = nil
        showInfo(
            title: "恢复完成",
            message: "已导入 \(p.ledgers.count) 本礼簿、\(importedRecords) 笔记录。"
        )
    }

    private func showInfo(title: String, message: String) {
        infoTitle = title
        infoMessage = message
        showInfo = true
    }

    private func asCardRow<V: View>(_ view: V) -> some View {
        view
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

/// 礼谱落款姓名编辑页：与导出 sheet 共用 @AppStorage("hostName")，
/// 礼谱的封面落款、谱序落款、主家印都读它；空 = 回退「主家谨识」。
struct HostNameEditView: View {
    @AppStorage("hostName") private var hostName = ""
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        List {
            Section {
                TextField("如：杨敏杰", text: $text)
                    .font(.system(size: 16))
            } footer: {
                Text("写主家在礼谱上落款用的名字，一般 2–4 个字。不填的话，礼谱上用「主家谨识」落款、盖「主家谨识」印。")
            }
            if !hostName.isEmpty {
                Section {
                    Button("清除落款姓名", role: .destructive) {
                        hostName = ""
                        text = ""
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle("礼谱落款姓名")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    hostName = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
            }
        }
        .onAppear {
            if text.isEmpty { text = hostName }
        }
    }
}

/// 「我的」页卡片表面：卡面色 + 发丝线 + 统一圆角/内边距
private extension View {
    func cardSurface(padding: CGFloat = LiqianMetrics.cardPadding) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner))
            .overlay(
                RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                    .stroke(Palette.hairline, lineWidth: 1)
            )
    }
}
